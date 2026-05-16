# Agent Loop — Design (Sub-project #2)

Date: 2026-05-16
Status: Approved for planning
Language: Harbour (MT build, hbmk2)
Depends on: Sub-project #1 (DeepSeek API client — `DS_ChatCompletion`)

## Context

Sub-project #2 of a Claude Code-style agentic client in Harbour. It builds the
agent loop: drive a multi-turn conversation against the DeepSeek API, detect
`tool_calls` in the model's reply, execute them, feed results back, and repeat
until the model stops or a limit is reached.

The real tool registry and concrete tools (Read/Write/Edit/Bash/Glob/Grep) are
sub-project #3. To stay decomposed and testable, #2 does **not** execute tools
itself: it receives an injectable `tool_executor` codeblock — the same seam
pattern used for the HTTP transport in #1. #3 plugs the real registry in later
without touching #2.

## Architecture

New module: `src/dsagent.prg`. Depends only on `dsapi` (`DS_ChatCompletion`).
It does not touch `dssse` / `dshttp` / `dsconfig`. `dsagent` orchestrates;
`dsapi` performs HTTP + SSE. `dsagent` knows nothing of curl or SSE.

No global mutable state. The input message array is never mutated. Each run is
self-contained — pool-safe.

### Public API

```
DS_AgentRun( oClient, aMessages, hOpts, bOnEvent ) -> hResult
```

- `oClient` — client from #1 (`DS_Client`).
- `aMessages` — initial history (system + user messages). Not mutated.
- `hOpts` — `{ model, max_iterations, tools, tool_executor, temperature,
  max_tokens, transport }`. All optional except as noted below.
- `bOnEvent` — optional codeblock, invoked per loop/SSE event.

### tool_executor contract

Injectable codeblock:

```
{| cToolName, cArgumentsJson | -> cResultString }
```

Always returns a string. A tool failure (unknown tool, bad arguments, internal
exception) is the executor's responsibility to catch and report — it returns an
error string, never throws. The loop never inspects success; it appends the
returned string as the `tool` message content. This realises the
error-as-tool-result decision: the model sees the error and can recover.

### hResult shape

```
{ success, messages, content, stop_reason, iterations, usage,
  error_type, message }
```

- `success` — `.T.` unless the loop stopped on an API failure or a config error.
- `messages` — the complete final history (input copy + appended messages).
- `content` — text of the last assistant message (`""` if none).
- `stop_reason` — `"stop"` | `"max_iterations"` | `"error"`.
- `iterations` — number of loop turns performed.
- `usage` — token usage accumulated across all API calls (hash; keys summed).
- `error_type` — `NIL` on success; otherwise passthrough from #1
  (`network` / `api` / `stream_incomplete` / `config`) or `"config"` for
  agent-level config errors.
- `message` — human-readable error text, or `NIL`.

### Private helpers (STATIC)

- build an OpenAI-format assistant message from a #1 `hResult`
- build a `tool` role message from a tool result
- accumulate `usage` hashes across turns

## Loop Flow

```
1. Validate aMessages (non-empty array) -> else fast-fail config error.
   aMsgs  := deep copy of aMessages
   nIter  := 0
   hUsage := empty hash
   nMax   := hOpts.max_iterations, default 25 (<= 0 -> 25)

2. DO WHILE nIter < nMax
      nIter++
      emit { type: "iteration_start", n: nIter }

      hChat := DS_ChatCompletion( oClient, aMsgs,
                  { model, tools, temperature, max_tokens, transport },
                  bOnEvent )

      IF !hChat.success
         -> error hResult (see Error Handling), RETURN
      ENDIF

      accumulate hChat.usage into hUsage
      AAdd( aMsgs, assistant message built from hChat )

      IF hChat.tool_calls is empty
         stop_reason := "stop"
         EXIT
      ENDIF

      IF tool_executor is NIL
         -> error hResult (config), RETURN
      ENDIF

      FOR EACH tc IN hChat.tool_calls
         emit { type: "tool_call", id, name, arguments }
         cRes := Eval( tool_executor, tc.name, tc.arguments )
         emit { type: "tool_result", id, content: cRes }
         AAdd( aMsgs, { role: "tool", tool_call_id: tc.id, content: cRes } )
      NEXT
   ENDDO

3. IF the loop exhausted nMax without EXIT
      stop_reason := "max_iterations"
   ENDIF

4. RETURN { success: .T., messages: aMsgs,
            content: text of last assistant message,
            stop_reason, iterations: nIter, usage: hUsage,
            error_type: NIL, message: NIL }
```

### Message construction

- **Assistant message**: `{ "role" => "assistant", "content" => hChat.content,
  "tool_calls" => [ { "id" => tc.id, "type" => "function",
  "function" => { "name" => tc.name, "arguments" => tc.arguments } } ] }`.
  When `hChat.tool_calls` is empty, the `tool_calls` key is omitted.
- **Tool message**: `{ "role" => "tool", "tool_call_id" => tc.id,
  "content" => cRes }`.
- `arguments` is the raw JSON string from #1, passed through unchanged to both
  the executor and the assistant message.
- Multiple `tool_calls` in one turn are all executed before the next API call.

### Events

All events go to `bOnEvent` (when supplied):

- SSE events forwarded from #1: `text_delta`, `tool_call_delta`, `finish`,
  `usage`, `done`, `error`.
- Agent-level events added by #2: `iteration_start`, `tool_call`, `tool_result`.

## Error Handling

- **API failure mid-loop**: `DS_ChatCompletion` returns `success = .F.` (already
  classified by #1). The loop stops and returns
  `{ success: .F., stop_reason: "error", error_type: <#1 error_type>,
  message: <#1 message>, messages: aMsgs (partial), iterations: nIter,
  usage: hUsage }`. #1 already emits its own error event to `bOnEvent`; the
  loop does not re-emit.
- **Model requests a tool with no `tool_executor`**: fast-fail before executing
  anything. `error_type: "config"`,
  `message: "model requested tool but no tool_executor provided"`,
  `stop_reason: "error"`. The partial history includes the assistant message
  carrying the `tool_calls`.
- **Tool failure** (unknown tool, bad args, internal exception): not a loop
  error. The `tool_executor` must catch it and return an error string. The loop
  appends that string as the `tool` message content and continues. The model
  recovers on the next turn.
- **Invalid `aMessages`** (empty, or not an array): fast-fail
  `error_type: "config"`, no API call.
- **`max_iterations` <= 0 or absent**: default 25.
- **Iteration cap reached**: not an error. `success = .T.`,
  `stop_reason = "max_iterations"`, partial content is valid.
- **Rule**: `dsagent` never throws an uncaught exception — every path returns an
  `hResult`. A `tool_executor` that throws an uncaught exception is an executor
  bug (sub-project #3's responsibility); `dsagent` does not wrap it in a `TRY`.

## Testing

Reuses the #1 test harness: `tests/run_tests.prg` (with `T_Assert` / `T_Equal`),
a new `Test_Agent()` entry point, and a new `tests/test_agent.prg`.

No network. The loop calls `DS_ChatCompletion` N times, each with
`hOpts["transport"]`. Tests use a **stateful transport** — a codeblock closing
over a counter and an array of canned SSE responses; each invocation returns the
next turn's bytes. This simulates multi-turn offline. The `tool_executor` under
test is a mock codeblock returning a fixed string (or counting its calls).

Test cases:

- **Single turn, no tools**: transport returns text + `[DONE]`. Expect
  `stop_reason = "stop"`, `iterations = 1`, correct `content`.
- **Tool turn**: turn 1 returns `tool_calls`, turn 2 returns final text. Expect
  the executor called, a `tool` message appended, `iterations = 2`, final
  `content` correct.
- **Multiple tool_calls in one turn**: turn 1 has two `tool_calls`. Expect both
  executed before turn 2.
- **Iteration cap**: transport always returns `tool_calls`,
  `max_iterations = 3`. Expect `stop_reason = "max_iterations"`,
  `iterations = 3`, `success = .T.`.
- **API failure mid-loop**: a turn returns `ok = .F.`. Expect `success = .F.`,
  `error_type` passthrough, `stop_reason = "error"`.
- **Tool requested with no executor**: expect `error_type = "config"`,
  `stop_reason = "error"`.
- **History**: `hResult["messages"]` is the complete final history; the input
  `aMessages` is not mutated.
- **Usage accumulation**: two turns -> token counts summed in `hResult["usage"]`.

Build: add `test_agent.prg` and `../src/dsagent.prg` to `tests/tests.hbp`; add a
`Test_Agent()` call to the runner's `Main()`.

## Self-Review

- **Scope**: one module, one public function, one implementation plan. Focused.
- **Decomposition honoured**: tool execution stays in #3 behind the injectable
  `tool_executor` seam; #2 is a pure loop.
- **Deferred (out of scope for #2)**: real tools and the tool registry (#3);
  terminal UI and running the loop on a background thread (#4); subagents and
  the thread pool (#6.5). Cancellation mid-loop belongs to #4 (no consumer yet).
- **Type consistency**: `hResult` keys, message hashes (`role` / `content` /
  `tool_calls` / `tool_call_id`), and the `tool_executor` contract
  (`{|cToolName,cArgumentsJson| -> cResultString}`) are used identically
  throughout.
- **Placeholder scan**: no TBD / TODO; all sections concrete.

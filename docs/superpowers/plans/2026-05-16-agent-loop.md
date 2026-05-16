# Agent Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Harbour module that drives a multi-turn DeepSeek conversation, executes the model's tool calls via an injectable executor, and loops until the model stops or an iteration cap is reached.

**Architecture:** One module, `src/dsagent.prg`, exposing `DS_AgentRun`. It depends only on `dsapi` (`DS_ChatCompletion` from sub-project #1). Tool execution is delegated to an injectable `tool_executor` codeblock — the same seam pattern as the HTTP transport in #1 — so the loop is fully testable offline and the real tool registry (#3) plugs in later untouched. No global mutable state; the input message array is never mutated.

**Tech Stack:** Harbour (MT build, `hbmk2`, BCC), core `hb_jsonEncode`/`hb_jsonDecode`. Reuses the #1 test harness.

---

## File Structure

```
src/dsagent.prg        Agent loop: DS_AgentRun + STATIC helpers
tests/test_agent.prg   Agent loop tests + mock transport helper
tests/tests.hbp        (modified) add test_agent.prg + ../src/dsagent.prg
tests/run_tests.prg    (modified) call Test_Agent() in Main()
```

Conventions (same as #1): public functions are `FUNCTION`, private helpers are
`STATIC FUNCTION`. Hashes carry data. Every public function returns a value;
none throws an uncaught exception.

The build runs from the `tests/` directory: `hbmk2 tests.hbp` produces
`tests/run_tests.exe`. Toolchain is not on PATH — prefix it:
`$env:PATH = 'C:\harbour\bin\win\bcc;C:\bcc77\bin;' + $env:PATH`.

---

### Task 1: Scaffold — wire the agent module and test file into the build

**Files:**
- Create: `src/dsagent.prg`
- Create: `tests/test_agent.prg`
- Modify: `tests/tests.hbp`
- Modify: `tests/run_tests.prg`

- [ ] **Step 1: Create the `dsagent.prg` stub**

`src/dsagent.prg`:

```harbour
FUNCTION DS_AgentRun( oClient, aMessages, hOpts, bOnEvent )
   HB_SYMBOL_UNUSED( oClient )
   HB_SYMBOL_UNUSED( aMessages )
   HB_SYMBOL_UNUSED( hOpts )
   HB_SYMBOL_UNUSED( bOnEvent )
   RETURN NIL
```

- [ ] **Step 2: Create the `test_agent.prg` stub**

`tests/test_agent.prg`:

```harbour
FUNCTION Test_Agent()
   RETURN NIL
```

- [ ] **Step 3: Add both files to the build**

In `tests/tests.hbp`, add `test_agent.prg` after `test_api.prg`, and
`../src/dsagent.prg` after `../src/dsapi.prg`. The file becomes:

```
-orun_tests
-mt
-gtcgi
run_tests.prg
test_sse.prg
test_config.prg
test_http.prg
test_api.prg
test_agent.prg
../src/dsconfig.prg
../src/dssse.prg
../src/dshttp.prg
../src/dsapi.prg
../src/dsagent.prg
```

- [ ] **Step 4: Call `Test_Agent()` from the runner**

In `tests/run_tests.prg`, add `Test_Agent()` to `Main()` after `Test_Api()`:

```harbour
FUNCTION Main()
   Test_SSE()
   Test_Config()
   Test_Http()
   Test_Api()
   Test_Agent()
   ? ""
   ? "pass: " + LTrim( Str( s_nPass ) ) + "   fail: " + LTrim( Str( s_nFail ) )
   ErrorLevel( iif( s_nFail > 0, 1, 0 ) )
   RETURN NIL
```

- [ ] **Step 5: Build and run**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: builds clean; output ends with `pass: 47   fail: 0` (the 47 existing
tests; `Test_Agent()` adds none yet); exit code 0.

- [ ] **Step 6: Commit**

```bash
git add src/dsagent.prg tests/test_agent.prg tests/tests.hbp tests/run_tests.prg
git commit -m "chore: scaffold agent loop module and test file"
```

---

### Task 2: Core loop — single turn, no tools

**Files:**
- Modify: `src/dsagent.prg` (replace stub)
- Modify: `tests/test_agent.prg` (replace stub)

This task implements input validation, the deep copy, the iteration loop, one
API call, the assistant message, usage accumulation, and the `"stop"` exit. Tool
execution and error handling are added in Tasks 3 and 4.

- [ ] **Step 1: Write the failing tests and mock transport helper**

Replace the entire contents of `tests/test_agent.prg`:

```harbour
// Stateful mock transport: each DS_ChatCompletion call inside the loop pops the
// next turn. Calls past the end repeat the last turn (lets cap tests loop).
// A turn is { "sse" => <raw SSE bytes>, "http" => { ok,status,curl_code,error } }.
STATIC FUNCTION AgentTransport( aTurns )
   LOCAL nCall := 0
   RETURN {| hReq, bOnChunk | ;
      DS_AgentTestTurn( aTurns, ( nCall := nCall + 1 ), hReq, bOnChunk ) }

STATIC FUNCTION DS_AgentTestTurn( aTurns, nCall, hReq, bOnChunk )
   LOCAL hTurn
   HB_SYMBOL_UNUSED( hReq )
   IF nCall > Len( aTurns )
      nCall := Len( aTurns )
   ENDIF
   hTurn := aTurns[ nCall ]
   IF !Empty( hTurn[ "sse" ] )
      Eval( bOnChunk, hTurn[ "sse" ] )
   ENDIF
   RETURN hTurn[ "http" ]

// SSE for a turn whose assistant reply is plain text then stops.
STATIC FUNCTION SSE_Text( cText )
   RETURN 'data: {"choices":[{"delta":{"content":"' + cText + '"}}]}' + Chr(10) + ;
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}' + Chr(10) + ;
          "data: [DONE]" + Chr(10)

// SSE for a turn that requests one tool call (function cName, arguments "{}").
STATIC FUNCTION SSE_Tool( cId, cName )
   RETURN 'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"' + cId + ;
          '","function":{"name":"' + cName + '","arguments":"{}"}}]}}]}' + Chr(10) + ;
          'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}' + Chr(10) + ;
          "data: [DONE]" + Chr(10)

STATIC FUNCTION HttpOK()
   RETURN { "ok" => .T., "status" => 200, "curl_code" => 0, "error" => "" }

FUNCTION Test_Agent()
   LOCAL oClient, hRes, bTransport

   oClient := DS_Client( { "api_key" => "k", "model" => "deepseek-chat" } )

   // single turn, plain text reply, no tools
   bTransport := AgentTransport( { { "sse" => SSE_Text( "hello" ), "http" => HttpOK() } } )
   hRes := DS_AgentRun( oClient, ;
      { { "role" => "user", "content" => "hi" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hRes[ "success" ], .T., "agent: single-turn success" )
   T_Equal( hRes[ "stop_reason" ], "stop", "agent: single-turn stop reason" )
   T_Equal( hRes[ "iterations" ], 1, "agent: single-turn iteration count" )
   T_Equal( hRes[ "content" ], "hello", "agent: single-turn content" )
   T_Equal( Len( hRes[ "messages" ] ), 2, "agent: single-turn message count" )
   T_Equal( hRes[ "messages" ][ 2 ][ "role" ], "assistant", "agent: assistant appended" )

   // invalid history -> config error, no API call
   hRes := DS_AgentRun( oClient, {}, { "transport" => bTransport }, NIL )
   T_Equal( hRes[ "success" ], .F., "agent: empty history fails" )
   T_Equal( hRes[ "error_type" ], "config", "agent: empty history error_type" )
   T_Equal( hRes[ "stop_reason" ], "error", "agent: empty history stop_reason" )
   RETURN NIL
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL for the `agent:` tests (`DS_AgentRun` is the stub returning NIL —
array access on NIL raises a bound error). The 47 existing tests still pass.

- [ ] **Step 3: Implement the core loop**

Replace the entire contents of `src/dsagent.prg`:

```harbour
// Runs the agent loop: drive a multi-turn DeepSeek conversation until the model
// stops or the iteration cap is reached. Tool execution is added in Task 3,
// API-failure handling in Task 4.
// hOpts: { model, max_iterations, tools, tool_executor, temperature,
//          max_tokens, transport }
// Returns hResult: { success, messages, content, stop_reason, iterations,
//                    usage, error_type, message }
FUNCTION DS_AgentRun( oClient, aMessages, hOpts, bOnEvent )
   LOCAL hResult, aMsgs, nIter := 0, nMax, hUsage, hChat, hChatParams

   IF ValType( hOpts ) != "H"
      hOpts := {=>}
   ENDIF

   hResult := { "success" => .F., "messages" => {}, "content" => "", ;
                "stop_reason" => NIL, "iterations" => 0, "usage" => {=>}, ;
                "error_type" => NIL, "message" => NIL }

   // validate the input history
   IF ValType( aMessages ) != "A" .OR. Len( aMessages ) == 0
      hResult[ "error_type" ]  := "config"
      hResult[ "message" ]     := "aMessages must be a non-empty array"
      hResult[ "stop_reason" ] := "error"
      RETURN hResult
   ENDIF

   // deep copy so the caller's array is never mutated
   aMsgs  := hb_jsonDecode( hb_jsonEncode( aMessages ) )
   nMax   := iif( hb_HHasKey( hOpts, "max_iterations" ) .AND. ;
                  ValType( hOpts[ "max_iterations" ] ) == "N" .AND. ;
                  hOpts[ "max_iterations" ] > 0, hOpts[ "max_iterations" ], 25 )
   hUsage := {=>}

   DO WHILE nIter < nMax
      nIter++
      DS_AgentEmit( bOnEvent, { "type" => "iteration_start", "n" => nIter } )

      hChatParams := {=>}
      IF hb_HHasKey( hOpts, "transport" )
         hChatParams[ "transport" ] := hOpts[ "transport" ]
      ENDIF
      IF hb_HHasKey( hOpts, "model" )
         hChatParams[ "model" ] := hOpts[ "model" ]
      ENDIF
      IF hb_HHasKey( hOpts, "tools" )
         hChatParams[ "tools" ] := hOpts[ "tools" ]
      ENDIF
      IF hb_HHasKey( hOpts, "temperature" )
         hChatParams[ "temperature" ] := hOpts[ "temperature" ]
      ENDIF
      IF hb_HHasKey( hOpts, "max_tokens" )
         hChatParams[ "max_tokens" ] := hOpts[ "max_tokens" ]
      ENDIF

      hChat := DS_ChatCompletion( oClient, aMsgs, hChatParams, bOnEvent )

      DS_AgentAddUsage( hUsage, hChat[ "usage" ] )
      AAdd( aMsgs, DS_AgentAsstMsg( hChat ) )

      IF Empty( hChat[ "tool_calls" ] )
         hResult[ "stop_reason" ] := "stop"
         EXIT
      ENDIF
   ENDDO

   hResult[ "success" ]    := .T.
   hResult[ "messages" ]   := aMsgs
   hResult[ "iterations" ] := nIter
   hResult[ "usage" ]      := hUsage
   hResult[ "content" ]    := DS_AgentLastText( aMsgs )
   RETURN hResult

// Builds an OpenAI-format assistant message from a DS_ChatCompletion result.
STATIC FUNCTION DS_AgentAsstMsg( hChat )
   LOCAL hMsg, aTC := {}, tc
   hMsg := { "role" => "assistant", "content" => hChat[ "content" ] }
   IF !Empty( hChat[ "tool_calls" ] )
      FOR EACH tc IN hChat[ "tool_calls" ]
         AAdd( aTC, { "id" => tc[ "id" ], "type" => "function", ;
                      "function" => { "name" => tc[ "name" ], ;
                                      "arguments" => tc[ "arguments" ] } } )
      NEXT
      hMsg[ "tool_calls" ] := aTC
   ENDIF
   RETURN hMsg

// Returns the content of the last assistant message, or "" if there is none.
STATIC FUNCTION DS_AgentLastText( aMsgs )
   LOCAL i
   FOR i := Len( aMsgs ) TO 1 STEP -1
      IF aMsgs[ i ][ "role" ] == "assistant"
         RETURN aMsgs[ i ][ "content" ]
      ENDIF
   NEXT
   RETURN ""

// Adds the numeric keys of xUsage into hUsage (running totals across turns).
STATIC FUNCTION DS_AgentAddUsage( hUsage, xUsage )
   LOCAL cKey
   IF ValType( xUsage ) != "H"
      RETURN NIL
   ENDIF
   FOR EACH cKey IN hb_HKeys( xUsage )
      IF ValType( xUsage[ cKey ] ) == "N"
         hUsage[ cKey ] := iif( hb_HHasKey( hUsage, cKey ), hUsage[ cKey ], 0 ) + ;
                           xUsage[ cKey ]
      ENDIF
   NEXT
   RETURN NIL

STATIC FUNCTION DS_AgentEmit( bOnEvent, hEv )
   IF bOnEvent != NIL
      Eval( bOnEvent, hEv )
   ENDIF
   RETURN NIL
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `agent:` lines `ok`; the 47 existing tests still `ok`; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add src/dsagent.prg tests/test_agent.prg
git commit -m "feat: agent loop core — single-turn conversation"
```

---

### Task 3: Tool execution — multi-turn tool calls

**Files:**
- Modify: `src/dsagent.prg`
- Modify: `tests/test_agent.prg`

- [ ] **Step 1: Add the failing tests**

Append inside `Test_Agent()` in `tests/test_agent.prg`, before `RETURN NIL`:

```harbour
   // tool turn: turn 1 requests a tool, turn 2 replies with text
   bTransport := AgentTransport( { ;
      { "sse" => SSE_Tool( "c1", "ping" ), "http" => HttpOK() }, ;
      { "sse" => SSE_Text( "done" ),       "http" => HttpOK() } } )
   hRes := DS_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport, ;
        "tool_executor" => {| cName, cArgs | ;
           HB_SYMBOL_UNUSED( cArgs ), "result-of-" + cName } }, NIL )
   T_Equal( hRes[ "success" ], .T., "agent: tool turn success" )
   T_Equal( hRes[ "iterations" ], 2, "agent: tool turn iterations" )
   T_Equal( hRes[ "stop_reason" ], "stop", "agent: tool turn stop reason" )
   T_Equal( hRes[ "content" ], "done", "agent: tool turn final content" )
   // messages: user, assistant(tool_calls), tool, assistant(text)
   T_Equal( Len( hRes[ "messages" ] ), 4, "agent: tool turn message count" )
   T_Equal( hRes[ "messages" ][ 3 ][ "role" ], "tool", "agent: tool message role" )
   T_Equal( hRes[ "messages" ][ 3 ][ "tool_call_id" ], "c1", "agent: tool message id" )
   T_Equal( hRes[ "messages" ][ 3 ][ "content" ], "result-of-ping", ;
            "agent: tool message content" )

   // model requests a tool but no executor supplied -> config error
   bTransport := AgentTransport( { { "sse" => SSE_Tool( "c9", "ping" ), ;
                                     "http" => HttpOK() } } )
   hRes := DS_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hRes[ "success" ], .F., "agent: no executor fails" )
   T_Equal( hRes[ "error_type" ], "config", "agent: no executor error_type" )
   T_Equal( hRes[ "stop_reason" ], "error", "agent: no executor stop_reason" )

   // input array is not mutated by the run
   aInput := { { "role" => "user", "content" => "keep" } }
   bTransport := AgentTransport( { { "sse" => SSE_Text( "ok" ), "http" => HttpOK() } } )
   DS_AgentRun( oClient, aInput, { "transport" => bTransport }, NIL )
   T_Equal( Len( aInput ), 1, "agent: input array not mutated" )

   // usage accumulates across turns
   bTransport := AgentTransport( { ;
      { "sse" => SSE_Tool( "c1", "ping" ), "http" => HttpOK() }, ;
      { "sse" => 'data: {"choices":[{"delta":{"content":"x"}}]}' + Chr(10) + ;
                 'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}' + Chr(10) + ;
                 'data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":7}}' + ;
                 Chr(10) + "data: [DONE]" + Chr(10), ;
        "http" => HttpOK() } } )
   hRes := DS_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport, ;
        "tool_executor" => {| cName, cArgs | ;
           HB_SYMBOL_UNUSED( cName ), HB_SYMBOL_UNUSED( cArgs ), "r" } }, NIL )
   T_Equal( hRes[ "usage" ][ "prompt_tokens" ], 5, "agent: usage accumulated" )
```

Add `aInput` to the `LOCAL` line at the top of `Test_Agent()`:

```harbour
   LOCAL oClient, hRes, bTransport, aInput
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL for the new `agent:` tests — Task 2's loop has no tool handling,
so a tool turn loops to the cap and never reaches turn 2, and the no-executor
case is not detected. Task 2's tests still pass.

- [ ] **Step 3: Add tool handling to the loop**

In `src/dsagent.prg`, replace this block inside the `DO WHILE`:

```harbour
      IF Empty( hChat[ "tool_calls" ] )
         hResult[ "stop_reason" ] := "stop"
         EXIT
      ENDIF
   ENDDO
```

with:

```harbour
      IF Empty( hChat[ "tool_calls" ] )
         hResult[ "stop_reason" ] := "stop"
         EXIT
      ENDIF

      // model wants tools but caller supplied no executor -> fast-fail
      IF !hb_HHasKey( hOpts, "tool_executor" ) .OR. hOpts[ "tool_executor" ] == NIL
         hResult[ "messages" ]    := aMsgs
         hResult[ "iterations" ]  := nIter
         hResult[ "usage" ]       := hUsage
         hResult[ "error_type" ]  := "config"
         hResult[ "message" ]     := "model requested tool but no tool_executor provided"
         hResult[ "stop_reason" ] := "error"
         RETURN hResult
      ENDIF

      // execute every tool call this turn, append each result as a tool message
      FOR EACH tc IN hChat[ "tool_calls" ]
         DS_AgentEmit( bOnEvent, { "type" => "tool_call", "id" => tc[ "id" ], ;
                                   "name" => tc[ "name" ], ;
                                   "arguments" => tc[ "arguments" ] } )
         cRes := Eval( hOpts[ "tool_executor" ], tc[ "name" ], tc[ "arguments" ] )
         DS_AgentEmit( bOnEvent, { "type" => "tool_result", "id" => tc[ "id" ], ;
                                   "content" => cRes } )
         AAdd( aMsgs, { "role" => "tool", "tool_call_id" => tc[ "id" ], ;
                        "content" => cRes } )
      NEXT
   ENDDO

   IF hResult[ "stop_reason" ] == NIL
      hResult[ "stop_reason" ] := "max_iterations"
   ENDIF
```

Then add `tc` and `cRes` to the `LOCAL` line of `DS_AgentRun`:

```harbour
   LOCAL hResult, aMsgs, nIter := 0, nMax, hUsage, hChat, hChatParams, tc, cRes
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `agent:` lines `ok`; existing tests still `ok`; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add src/dsagent.prg tests/test_agent.prg
git commit -m "feat: agent loop executes tool calls and assembles tool messages"
```

---

### Task 4: Limits and errors — iteration cap and API failure

**Files:**
- Modify: `src/dsagent.prg`
- Modify: `tests/test_agent.prg`

- [ ] **Step 1: Add the failing tests**

Append inside `Test_Agent()` in `tests/test_agent.prg`, before `RETURN NIL`:

```harbour
   // iteration cap: the model keeps requesting tools; cap stops the loop
   bTransport := AgentTransport( { { "sse" => SSE_Tool( "c1", "ping" ), ;
                                     "http" => HttpOK() } } )
   hRes := DS_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport, "max_iterations" => 3, ;
        "tool_executor" => {| cName, cArgs | ;
           HB_SYMBOL_UNUSED( cName ), HB_SYMBOL_UNUSED( cArgs ), "r" } }, NIL )
   T_Equal( hRes[ "success" ], .T., "agent: cap success flag" )
   T_Equal( hRes[ "stop_reason" ], "max_iterations", "agent: cap stop reason" )
   T_Equal( hRes[ "iterations" ], 3, "agent: cap iteration count" )

   // API failure mid-loop surfaces in hResult
   bTransport := AgentTransport( { { "sse" => "", ;
      "http" => { "ok" => .F., "status" => 0, "curl_code" => 7, ;
                  "error" => "no connect" } } } )
   hRes := DS_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hRes[ "success" ], .F., "agent: api failure success flag" )
   T_Equal( hRes[ "error_type" ], "network", "agent: api failure error_type" )
   T_Equal( hRes[ "stop_reason" ], "error", "agent: api failure stop reason" )
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL for the API-failure `agent:` tests — `DS_ChatCompletion` returns
`success = .F.`, but the loop does not yet check it, so it reads `tool_calls`
off a failed result and misbehaves. The cap tests already pass (Task 3 added the
`max_iterations` branch).

- [ ] **Step 3: Add the API-failure check**

In `src/dsagent.prg`, find this line inside the `DO WHILE`:

```harbour
      hChat := DS_ChatCompletion( oClient, aMsgs, hChatParams, bOnEvent )

      DS_AgentAddUsage( hUsage, hChat[ "usage" ] )
```

and insert the failure check between the two statements:

```harbour
      hChat := DS_ChatCompletion( oClient, aMsgs, hChatParams, bOnEvent )

      IF !hChat[ "success" ]
         hResult[ "messages" ]    := aMsgs
         hResult[ "iterations" ]  := nIter
         hResult[ "usage" ]       := hUsage
         hResult[ "error_type" ]  := hChat[ "error_type" ]
         hResult[ "message" ]     := hChat[ "message" ]
         hResult[ "stop_reason" ] := "error"
         RETURN hResult
      ENDIF

      DS_AgentAddUsage( hUsage, hChat[ "usage" ] )
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `agent:` lines `ok`; existing tests still `ok`; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add src/dsagent.prg tests/test_agent.prg
git commit -m "feat: agent loop handles API failure and iteration cap"
```

---

## Self-Review

**Spec coverage:**
- `DS_AgentRun` signature, `hOpts` keys, `bOnEvent` — Task 2 (params threaded
  into `hChatParams`).
- `tool_executor` injectable contract `{|cToolName,cArgumentsJson|->cResultString}`
  — Task 3.
- `hResult` shape (success, messages, content, stop_reason, iterations, usage,
  error_type, message) — initialised Task 2, completed Tasks 3–4.
- Loop flow (deep copy, iteration_start, API call, assistant message, stop) —
  Task 2.
- Assistant message + tool message construction (OpenAI format) — Tasks 2–3.
- Multiple tool_calls per turn — Task 3 (`FOR EACH tc`).
- Events `iteration_start` / `tool_call` / `tool_result` plus forwarded SSE
  events — Tasks 2–3.
- Error handling: API failure mid-loop — Task 4; no-executor config error —
  Task 3; invalid `aMessages` — Task 2; iteration cap (not an error) — cap
  branch Task 3, test Task 4.
- Usage accumulation across turns — `DS_AgentAddUsage`, Task 2; tested Task 3.
- Input not mutated — `hb_jsonDecode(hb_jsonEncode())` deep copy, Task 2; tested
  Task 3.
- Testing: stateful mock transport, `Test_Agent()`, all spec cases — Tasks 2–4.

**Placeholder scan:** none. The Task 1 stubs are intentional, explicitly
replaced in Tasks 2–3. Every code step shows complete code.

**Type consistency:** `hResult` keys, message hashes (`role` / `content` /
`tool_calls` / `tool_call_id`), `hChat` keys consumed from #1 (`success` /
`content` / `tool_calls` / `usage` / `error_type` / `message`), tool_call
fields (`id` / `name` / `arguments`), and the helper names (`DS_AgentAsstMsg`,
`DS_AgentLastText`, `DS_AgentAddUsage`, `DS_AgentEmit`) are used identically
across all tasks.

**Deferred (out of scope for #2):** the real tool registry and concrete tools
(#3); terminal UI and running the loop on a background thread (#4); subagents
and the thread pool (#6.5); mid-loop cancellation (#4 — no consumer yet).

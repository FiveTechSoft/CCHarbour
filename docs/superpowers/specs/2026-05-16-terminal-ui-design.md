# Terminal UI — Design (Sub-project #4)

Date: 2026-05-16
Status: Approved for planning
Language: Harbour (MT build, hbmk2)
Depends on: #1 (`DS_Client`, `DSCFG_Resolve`), #2 (`DS_AgentRun`),
#3 (`DSTools_Registry` / `DSTools_Schemas` / `DSTools_Executor`).

## Context

Sub-project #4 of a Claude Code-style agentic client in Harbour. Sub-projects
#1–#3 built the API client, the agent loop, and the tool system. #4 is the
interactive front end: a terminal REPL that reads the user's input, runs the
agent loop with the full builtin tool set, streams the model's reply and tool
activity to the screen, and keeps the conversation across turns. It produces
the project's runnable binary, `cc.exe`.

The REPL is **synchronous**: each turn runs `DS_AgentRun` on the main thread.
Streaming still works — `DS_AgentRun`'s `bOnEvent` callback fires per chunk
while the call is in progress, so text appears live. What a synchronous REPL
gives up is typing while a response streams and cancelling mid-response; those
belong to a later threaded sub-project (#6.5 owns the thread pool) and are out
of scope here.

## Architecture

Two new modules plus an app build:

```
src/dsui.prg     Pure UI logic: command parsing, event rendering, summarising
src/dsrepl.prg   The interactive REPL loop and Main()
cc.hbp           Application build project -> cc.exe
tests/test_ui.prg  Unit tests for dsui.prg
```

`dsui.prg` depends on nothing — a pure layer. `dsrepl.prg` is a thin I/O shell
over `dsui`, `DS_Client` (#1), `DSTools_Registry`/`Schemas`/`Executor` (#3) and
`DS_AgentRun` (#2). All decidable logic (command parsing, event rendering)
lives in the pure `dsui.prg`; `dsrepl.prg` only does I/O and orchestration.

### dsui.prg API (pure, no I/O)

```
DSUI_ParseCommand( cLine )    -> hAction
   hAction = { "type" => "exit"|"clear"|"help"|"message"|"empty",
               "text" => <trimmed line> }
DSUI_RenderEvent( hEv )       -> cString   one agent event -> display text ("" if ignored)
DSUI_Summarize( cText, nMax ) -> cString   first line + "[<N> chars]" annotation
DSUI_SystemPrompt()           -> cString   the seeded system message
DSUI_Help()                   -> cString   the /help text
```

`DSUI_ParseCommand` trims the line. Recognised commands are exactly `/exit`,
`/quit` (both -> `exit`), `/clear`, `/help`. An empty or whitespace-only line ->
`empty`. Any other line — including one starting with `/` that is not a
recognised command — -> `message`, with `text` set to the trimmed line.

`DSUI_RenderEvent` maps an agent/SSE event hash to display text:
- `text_delta` -> the delta text itself (streamed inline, no newline added).
- `tool_call` -> a compact line, e.g. `  -> read {"path":"src/x.prg"}`.
- `tool_result` -> a summarised line via `DSUI_Summarize`, e.g. `  <- [142 chars]`.
- `error` -> a marked line, e.g. `!! error: <message>`.
- `iteration_start`, `finish`, `usage`, `done`, `tool_call_delta` -> `""`
  (ignored; `usage` is rendered by the REPL itself at end of turn).

### dsrepl.prg API

```
Main( cModel )                        program entry point
DSREPL_Run( oClient, oReg, cModel )    the interactive loop
```

### Builds

- `tests/tests.hbp` gains `test_ui.prg` and `../src/dsui.prg`, and the runner
  gains a `Test_UI()` call. It does **not** include `dsrepl.prg` — that file
  has a `Main()` which would collide with the test runner's `Main()`.
- `cc.hbp` is a new build project producing `cc.exe`, with `-mt -gtcgi` and the
  ten source files: `dsconfig`, `dssse`, `dshttp`, `dsapi`, `dsagent`,
  `dstools`, `dstools_file`, `dstools_search`, `dstools_shell`, `dsui`,
  `dsrepl`.

## REPL Flow

```
Main( cModel ):
   1. cModel := cModel  (CLI arg)  |  env DEEPSEEK_MODEL  |  "deepseek-chat"
   2. hCfg := DSCFG_Resolve( {=>} )            // validate API key early
      if !hCfg.ok: print "Error: no API key. Set DEEPSEEK_API_KEY." ; exit 1
   3. oClient := DS_Client( { "model" => cModel } )
   4. oReg    := DSTools_Registry()
   5. BEGIN SEQUENCE: DSREPL_Run( oClient, oReg, cModel )
      RECOVER: print short trace ; exit 1

DSREPL_Run( oClient, oReg, cModel ):
   aMsgs  := { { "role" => "system", "content" => DSUI_SystemPrompt() } }
   bRender := {| hEv | OutStd( DSUI_RenderEvent( hEv ) ) }
   print banner: "CCHarbour - model: <cModel>. /help for commands."

   DO WHILE .T.
      print "> "
      cLine := read one line from stdin
      if EOF -> EXIT

      hAction := DSUI_ParseCommand( cLine )
      DO CASE
      CASE hAction.type == "empty"  -> LOOP
      CASE hAction.type == "exit"   -> EXIT
      CASE hAction.type == "help"   -> print DSUI_Help() ; LOOP
      CASE hAction.type == "clear"
         aMsgs := { { "role" => "system", "content" => DSUI_SystemPrompt() } }
         print "[conversation reset]" ; LOOP
      CASE hAction.type == "message"
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => hAction.text } )
         hRes := DS_AgentRun( oClient, aTurn,
                    { "model" => cModel,
                      "tools" => DSTools_Schemas( oReg ),
                      "tool_executor" => DSTools_Executor( oReg ) },
                    bRender )
         print newline
         IF hRes.success
            aMsgs := hRes.messages              // commit; multi-turn history
            IF hRes.stop_reason == "max_iterations"
               print "[stopped: iteration cap]"
            ENDIF
            print "[tokens: prompt <p>, completion <c>]"  // from hRes.usage
         ELSE
            print "!! error: <hRes.error_type>: <hRes.message>"
            // aMsgs untouched: the failed turn is discarded whole
         ENDIF
      ENDCASE
   ENDDO
   print "bye"
```

The user message is appended to a **clone** (`aTurn`), never to `aMsgs`
directly. `aMsgs` is replaced with `hRes.messages` only on success, so a failed
turn is discarded entirely and the user can retype against clean history.

`DSUI_RenderEvent` returns `""` for `usage`; the REPL reads `hRes.usage`
itself and prints the token line once per turn. The `usage` hash keys are
`prompt_tokens` and `completion_tokens`; either may be absent, in which case the
REPL prints `0` for it.

## Error Handling

- **Missing API key**: `DSCFG_Resolve` fails in `Main` — print
  `"Error: no API key. Set DEEPSEEK_API_KEY."`, exit 1, before any prompt.
- **Agent failure** (`hRes.success == .F.`): `error_type` is one of
  `network` / `api` / `stream_incomplete` / `config` (classified in #1/#2). The
  REPL prints `!! error: <error_type>: <message>`, discards the turn, and
  continues the loop. It never crashes — the user retypes.
- **Iteration cap** (`hRes.success == .T.`, `stop_reason == "max_iterations"`):
  not an error. The REPL prints `[stopped: iteration cap]` after the reply.
- **Tool failure**: already a tool-result error string inside the conversation
  (#3). The REPL shows it via the `tool_result` event. The loop continues.
- **EOF on stdin** (Ctrl+Z): the loop exits cleanly, exit 0.
- **Oversized input line**: no special limit — `DS_AgentRun` and the API handle
  it.
- **Rule**: `dsrepl` never lets an exception escape. `Main` wraps `DSREPL_Run`
  in `BEGIN SEQUENCE`; an unforeseen exception prints a short trace and exits 1
  rather than hanging the terminal.

## Testing

`dsui.prg` is pure and unit-tested. Reuses the #1–#3 harness:
`tests/run_tests.prg` (`T_Assert` / `T_Equal`), a new `Test_UI()` entry point,
and a new `tests/test_ui.prg`.

Test cases:

- **`DSUI_ParseCommand`**: `/exit` -> `exit`; `/quit` -> `exit`; `/clear` ->
  `clear`; `/help` -> `help`; `""` -> `empty`; a whitespace-only line ->
  `empty`; `"hello"` -> `message` with `text == "hello"`; `/foo` (unknown
  slash) -> `message`; `"/exit "` with trailing spaces -> `exit` (trimming).
- **`DSUI_RenderEvent`**: `text_delta` -> the delta text; `tool_call` -> a
  string containing `->` and the tool name; `tool_result` -> a summarised
  string; `error` -> a string containing `error`; `iteration_start` -> `""`.
- **`DSUI_Summarize`**: a short single-line text -> returned essentially as is;
  a multi-line text -> first line plus a `[<N> chars]` annotation; a text
  longer than `nMax` -> truncated.
- **`DSUI_SystemPrompt`**: returns a non-empty string.
- **`DSUI_Help`**: returns a non-empty string mentioning the three commands.

`dsrepl.prg` (the loop, `Main`, all I/O) is **not** unit-tested. It is verified
by a documented manual smoke test: build `cc.exe`, run it, exercise `/help`, a
real message turn (with `DEEPSEEK_API_KEY` set), and `/exit` — the same
opt-in style as #1's `integration.exe`.

Build: add `test_ui.prg` and `../src/dsui.prg` to `tests/tests.hbp`; add a
`Test_UI()` call to the runner's `Main()`. Create `cc.hbp` producing `cc.exe`.

## Self-Review

- **Scope**: two modules (one pure, one thin shell) plus an app build — one
  focused implementation plan.
- **Decomposition honoured**: #4 consumes the artifacts of #1–#3 and adds only
  the front end. Persistence, settings, and multi-session belong to #5;
  threading, cancellation, and `shell` timeout belong to #6.5.
- **Deferred (out of scope for #4)**: typing during a streaming response and
  mid-response cancellation (#6.5); persistent on-disk history and settings
  (#5); `shell` hard timeout (#6.5).
- **Type consistency**: `hAction` keys (`type` / `text`), the event hashes
  consumed by `DSUI_RenderEvent` (`type` plus `text` / `name` / `arguments` /
  `id` / `content` / `message`), and the `DS_AgentRun` call shape
  (`hOpts` keys `model` / `tools` / `tool_executor`, `hResult` keys `success` /
  `messages` / `stop_reason` / `usage` / `error_type` / `message`) match the
  definitions in #2 and #3.
- **Placeholder scan**: no TBD / TODO; every function, command, and error
  string is concrete.

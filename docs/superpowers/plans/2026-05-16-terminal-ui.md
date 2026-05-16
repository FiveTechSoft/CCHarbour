# Terminal UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the interactive terminal REPL — the runnable `cc.exe` binary — that reads user input, runs the agent loop with the builtin tools, streams the reply to the screen, and keeps the conversation across turns.

**Architecture:** Two modules. `src/dsui.prg` holds pure UI logic (command parsing, event rendering, summarising) and is unit-tested. `src/dsrepl.prg` is a thin I/O shell — the loop and `Main()` — over `dsui`, `DS_Client` (#1), `DSTools_*` (#3) and `DS_AgentRun` (#2). A new build `cc.hbp` produces `cc.exe`.

**Tech Stack:** Harbour (MT build, `hbmk2`, BCC), `OutStd` for output, `FRead`/`hb_GetStdIn` for line input. Reuses the #1–#3 test harness for `dsui.prg`.

---

## Deviation from the spec

`cc.hbp` uses `-mt` only, not `-gtcgi`. The REPL does all I/O through `OutStd`
(stdout) and `FRead(hb_GetStdIn())` (stdin), which bypass the Harbour GT
entirely, so the GT choice is irrelevant — the default keeps the build simple.

---

## File Structure

```
src/dsui.prg       Pure UI logic: ParseCommand, RenderEvent, Summarize, SystemPrompt, Help
src/dsrepl.prg     The REPL loop, Main(), stdin line reader, usage line
cc.hbp             Application build project -> cc.exe
tests/test_ui.prg  Unit tests for dsui.prg
tests/tests.hbp    (modified) add test_ui.prg + ../src/dsui.prg
tests/run_tests.prg (modified) call Test_UI() in Main()
```

Conventions (same as #1–#3): public functions are `FUNCTION`, private helpers
are `STATIC FUNCTION`. Hashes carry data. No public function throws an uncaught
exception.

The test build runs from `tests/`: `hbmk2 tests.hbp` -> `tests/run_tests.exe`.
The app build runs from the repo root: `hbmk2 cc.hbp` -> `cc.exe`. The
toolchain is not on PATH — prefix it:
`$env:PATH = 'C:\harbour\bin\win\bcc;C:\bcc77\bin;' + $env:PATH`.

`tests.hbp` must NOT include `dsrepl.prg`: it defines `Main()`, which would
collide with the test runner's `Main()`.

---

### Task 1: Scaffold — UI module and test file

**Files:**
- Create: `src/dsui.prg`
- Create: `tests/test_ui.prg`
- Modify: `tests/tests.hbp`
- Modify: `tests/run_tests.prg`

- [ ] **Step 1: Create the `dsui.prg` stub**

`src/dsui.prg`:

```harbour
FUNCTION DSUI_ParseCommand( cLine )
   HB_SYMBOL_UNUSED( cLine )
   RETURN NIL
```

- [ ] **Step 2: Create the `test_ui.prg` stub**

`tests/test_ui.prg`:

```harbour
FUNCTION Test_UI()
   RETURN NIL
```

- [ ] **Step 3: Add both files to the build**

In `tests/tests.hbp`, add `test_ui.prg` after `test_tools.prg`, and
`../src/dsui.prg` after `../src/dstools_shell.prg`. The file becomes:

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
test_tools.prg
test_ui.prg
../src/dsconfig.prg
../src/dssse.prg
../src/dshttp.prg
../src/dsapi.prg
../src/dsagent.prg
../src/dstools.prg
../src/dstools_file.prg
../src/dstools_search.prg
../src/dstools_shell.prg
../src/dsui.prg
```

- [ ] **Step 4: Call `Test_UI()` from the runner**

In `tests/run_tests.prg`, add `Test_UI()` to `Main()` after `Test_Tools()`:

```harbour
FUNCTION Main()
   Test_SSE()
   Test_Config()
   Test_Http()
   Test_Api()
   Test_Agent()
   Test_Tools()
   Test_UI()
   ? ""
   ? "pass: " + LTrim( Str( s_nPass ) ) + "   fail: " + LTrim( Str( s_nFail ) )
   ErrorLevel( iif( s_nFail > 0, 1, 0 ) )
   RETURN NIL
```

- [ ] **Step 5: Build and run**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: builds clean; output ends with `pass: 117   fail: 0` (the 117
existing tests; `Test_UI()` adds none yet); exit code 0.

- [ ] **Step 6: Commit**

```bash
git add src/dsui.prg tests/test_ui.prg tests/tests.hbp tests/run_tests.prg
git commit -m "chore: scaffold terminal UI module and test file"
```

---

### Task 2: DSUI_ParseCommand

**Files:**
- Modify: `src/dsui.prg` (replace stub)
- Modify: `tests/test_ui.prg` (replace stub)

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `tests/test_ui.prg`:

```harbour
FUNCTION Test_UI()
   LOCAL hA

   hA := DSUI_ParseCommand( "/exit" )
   T_Equal( hA[ "type" ], "exit", "ui: /exit parses to exit" )

   hA := DSUI_ParseCommand( "/quit" )
   T_Equal( hA[ "type" ], "exit", "ui: /quit parses to exit" )

   hA := DSUI_ParseCommand( "/clear" )
   T_Equal( hA[ "type" ], "clear", "ui: /clear parses to clear" )

   hA := DSUI_ParseCommand( "/help" )
   T_Equal( hA[ "type" ], "help", "ui: /help parses to help" )

   hA := DSUI_ParseCommand( "" )
   T_Equal( hA[ "type" ], "empty", "ui: blank line parses to empty" )

   hA := DSUI_ParseCommand( "    " )
   T_Equal( hA[ "type" ], "empty", "ui: whitespace line parses to empty" )

   hA := DSUI_ParseCommand( "hello there" )
   T_Equal( hA[ "type" ], "message", "ui: text parses to message" )
   T_Equal( hA[ "text" ], "hello there", "ui: message keeps text" )

   hA := DSUI_ParseCommand( "/foo" )
   T_Equal( hA[ "type" ], "message", "ui: unknown slash is a message" )

   hA := DSUI_ParseCommand( "  /exit  " )
   T_Equal( hA[ "type" ], "exit", "ui: command is trimmed" )
   RETURN NIL
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL for the `ui:` tests — `DSUI_ParseCommand` returns NIL, so the
hash access raises a bound error. The 117 existing tests still pass.

- [ ] **Step 3: Implement DSUI_ParseCommand**

Replace the entire contents of `src/dsui.prg`:

```harbour
// Classifies a line of REPL input. Returns:
//   { "type" => "exit"|"clear"|"help"|"message"|"empty", "text" => <trimmed> }
FUNCTION DSUI_ParseCommand( cLine )
   LOCAL cTrim := AllTrim( hb_CStr( cLine ) )
   DO CASE
   CASE Empty( cTrim )
      RETURN { "type" => "empty", "text" => "" }
   CASE Lower( cTrim ) == "/exit" .OR. Lower( cTrim ) == "/quit"
      RETURN { "type" => "exit", "text" => cTrim }
   CASE Lower( cTrim ) == "/clear"
      RETURN { "type" => "clear", "text" => cTrim }
   CASE Lower( cTrim ) == "/help"
      RETURN { "type" => "help", "text" => cTrim }
   ENDCASE
   RETURN { "type" => "message", "text" => cTrim }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `ui:` lines `ok`; the 117 existing tests still `ok`; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add src/dsui.prg tests/test_ui.prg
git commit -m "feat: REPL command parsing"
```

---

### Task 3: DSUI_Summarize and DSUI_RenderEvent

**Files:**
- Modify: `src/dsui.prg`
- Modify: `tests/test_ui.prg`

- [ ] **Step 1: Add the failing tests**

Append inside `Test_UI()` in `tests/test_ui.prg`, before `RETURN NIL`:

```harbour
   // DSUI_Summarize
   T_Equal( DSUI_Summarize( "short", 80 ), "short", "ui: summarize short text" )
   T_Assert( "first" $ DSUI_Summarize( "first" + Chr(10) + "second", 80 ), ;
             "ui: summarize keeps first line" )
   T_Assert( !( "second" $ DSUI_Summarize( "first" + Chr(10) + "second", 80 ) ), ;
             "ui: summarize drops later lines" )
   T_Assert( "chars]" $ DSUI_Summarize( "first" + Chr(10) + "second", 80 ), ;
             "ui: summarize annotates size" )
   T_Assert( Len( DSUI_Summarize( Replicate( "x", 200 ), 80 ) ) < 110, ;
             "ui: summarize truncates long text" )

   // DSUI_RenderEvent
   T_Equal( DSUI_RenderEvent( { "type" => "text_delta", "text" => "hi" } ), "hi", ;
            "ui: render text_delta" )
   T_Assert( "read" $ DSUI_RenderEvent( { "type" => "tool_call", "id" => "c1", ;
             "name" => "read", "arguments" => '{"path":"x"}' } ), ;
             "ui: render tool_call shows name" )
   T_Assert( "->" $ DSUI_RenderEvent( { "type" => "tool_call", "id" => "c1", ;
             "name" => "read", "arguments" => "{}" } ), ;
             "ui: render tool_call has arrow" )
   T_Assert( "chars]" $ DSUI_RenderEvent( { "type" => "tool_result", "id" => "c1", ;
             "content" => "line one" + Chr(10) + "line two" } ), ;
             "ui: render tool_result summarises" )
   T_Assert( "error" $ DSUI_RenderEvent( { "type" => "error", ;
             "error_type" => "network", "message" => "boom" } ), ;
             "ui: render error" )
   T_Equal( DSUI_RenderEvent( { "type" => "iteration_start", "n" => 1 } ), "", ;
            "ui: render ignores iteration_start" )
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL / build error — `DSUI_Summarize` and `DSUI_RenderEvent` are
undefined.

- [ ] **Step 3: Append the two functions to `dsui.prg`**

Append to `src/dsui.prg`:

```harbour
// Returns the first line of cText, truncated to nMax characters, with a
// "[<N> chars]" annotation when anything was dropped. nMax defaults to 80.
FUNCTION DSUI_Summarize( cText, nMax )
   LOCAL cFirst, nNL, nLen
   cText := hb_CStr( cText )
   nLen  := Len( cText )
   IF ValType( nMax ) != "N" .OR. nMax <= 0
      nMax := 80
   ENDIF
   nNL := At( Chr(10), cText )
   cFirst := iif( nNL > 0, Left( cText, nNL - 1 ), cText )
   cFirst := StrTran( cFirst, Chr(13), "" )
   IF Len( cFirst ) > nMax
      cFirst := Left( cFirst, nMax )
   ENDIF
   IF Len( cFirst ) < nLen
      RETURN cFirst + " [" + LTrim( Str( nLen ) ) + " chars]"
   ENDIF
   RETURN cFirst

// Maps one agent/SSE event hash to display text ("" when the event is ignored).
FUNCTION DSUI_RenderEvent( hEv )
   LOCAL cType
   IF ValType( hEv ) != "H" .OR. !hb_HHasKey( hEv, "type" )
      RETURN ""
   ENDIF
   cType := hEv[ "type" ]
   DO CASE
   CASE cType == "text_delta"
      RETURN hb_CStr( hEv[ "text" ] )
   CASE cType == "tool_call"
      RETURN Chr(10) + "  -> " + hb_CStr( hEv[ "name" ] ) + " " + ;
             hb_CStr( hEv[ "arguments" ] ) + Chr(10)
   CASE cType == "tool_result"
      RETURN "  <- " + DSUI_Summarize( hb_CStr( hEv[ "content" ] ), 80 ) + Chr(10)
   CASE cType == "error"
      RETURN Chr(10) + "!! error: " + hb_CStr( hEv[ "message" ] ) + Chr(10)
   ENDCASE
   RETURN ""
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `ui:` lines `ok`; existing tests still `ok`; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add src/dsui.prg tests/test_ui.prg
git commit -m "feat: event rendering and result summarising"
```

---

### Task 4: DSUI_SystemPrompt and DSUI_Help

**Files:**
- Modify: `src/dsui.prg`
- Modify: `tests/test_ui.prg`

- [ ] **Step 1: Add the failing tests**

Append inside `Test_UI()` in `tests/test_ui.prg`, before `RETURN NIL`:

```harbour
   // DSUI_SystemPrompt and DSUI_Help
   T_Assert( Len( DSUI_SystemPrompt() ) > 0, "ui: system prompt non-empty" )
   T_Assert( "/help" $ DSUI_Help(), "ui: help mentions /help" )
   T_Assert( "/clear" $ DSUI_Help(), "ui: help mentions /clear" )
   T_Assert( "/exit" $ DSUI_Help(), "ui: help mentions /exit" )
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL / build error — `DSUI_SystemPrompt` and `DSUI_Help` are
undefined.

- [ ] **Step 3: Append the two functions to `dsui.prg`**

Append to `src/dsui.prg`:

```harbour
// The system message seeded into every conversation.
FUNCTION DSUI_SystemPrompt()
   RETURN "You are CCHarbour, a terminal coding assistant. " + ;
          "You have tools to read, write and edit files, search with glob and " + ;
          "grep, and run shell commands. Use them to help the user with coding " + ;
          "tasks. Be concise."

// The text shown by the /help command.
FUNCTION DSUI_Help()
   RETURN "Commands:" + Chr(10) + ;
          "  /help   show this help" + Chr(10) + ;
          "  /clear  reset the conversation" + Chr(10) + ;
          "  /exit   quit (alias: /quit)" + Chr(10) + ;
          "Type anything else to talk to the assistant."
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `ui:` lines `ok`; existing tests still `ok`; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add src/dsui.prg tests/test_ui.prg
git commit -m "feat: system prompt and help text"
```

---

### Task 5: REPL loop, Main, and the cc.exe build

**Files:**
- Create: `src/dsrepl.prg`
- Create: `cc.hbp`

`dsrepl.prg` is all I/O and orchestration; it is not unit-tested. It is
verified by a clean build and a documented manual smoke test.

- [ ] **Step 1: Create `dsrepl.prg`**

`src/dsrepl.prg`:

```harbour
#include "fileio.ch"

// Program entry point. Optional cModel CLI argument overrides the model.
FUNCTION Main( cModel )
   LOCAL hCfg, oClient, oReg, oErr
   IF Empty( cModel )
      cModel := hb_GetEnv( "DEEPSEEK_MODEL" )
   ENDIF
   IF Empty( cModel )
      cModel := "deepseek-chat"
   ENDIF
   hCfg := DSCFG_Resolve( {=>} )
   IF !hCfg[ "ok" ]
      OutStd( "Error: no API key. Set DEEPSEEK_API_KEY." + Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   ENDIF
   oClient := DS_Client( { "model" => cModel } )
   oReg    := DSTools_Registry()
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      DSREPL_Run( oClient, oReg, cModel )
   RECOVER USING oErr
      OutStd( Chr(10) + "Fatal: " + ;
              iif( ValType( oErr ) == "O", hb_CStr( oErr:Description ), "exception" ) + ;
              Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   END SEQUENCE
   RETURN NIL

// The interactive loop: read a line, dispatch, run the agent, repeat.
FUNCTION DSREPL_Run( oClient, oReg, cModel )
   LOCAL aMsgs, bRender, cLine, hAction, aTurn, hRes
   aMsgs   := { { "role" => "system", "content" => DSUI_SystemPrompt() } }
   bRender := {| hEv | OutStd( DSUI_RenderEvent( hEv ) ) }
   OutStd( "CCHarbour - model: " + cModel + ". /help for commands." + Chr(10) )
   DO WHILE .T.
      OutStd( Chr(10) + "> " )
      cLine := DSREPL_ReadLine()
      IF cLine == NIL
         EXIT
      ENDIF
      hAction := DSUI_ParseCommand( cLine )
      DO CASE
      CASE hAction[ "type" ] == "empty"
         // nothing
      CASE hAction[ "type" ] == "exit"
         EXIT
      CASE hAction[ "type" ] == "help"
         OutStd( DSUI_Help() + Chr(10) )
      CASE hAction[ "type" ] == "clear"
         aMsgs := { { "role" => "system", "content" => DSUI_SystemPrompt() } }
         OutStd( "[conversation reset]" + Chr(10) )
      CASE hAction[ "type" ] == "message"
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => hAction[ "text" ] } )
         hRes := DS_AgentRun( oClient, aTurn, ;
            { "model" => cModel, ;
              "tools" => DSTools_Schemas( oReg ), ;
              "tool_executor" => DSTools_Executor( oReg ) }, ;
            bRender )
         OutStd( Chr(10) )
         IF hRes[ "success" ]
            aMsgs := hRes[ "messages" ]
            IF hRes[ "stop_reason" ] == "max_iterations"
               OutStd( "[stopped: iteration cap]" + Chr(10) )
            ENDIF
            OutStd( DSREPL_UsageLine( hRes[ "usage" ] ) + Chr(10) )
         ELSE
            OutStd( "!! error: " + hb_CStr( hRes[ "error_type" ] ) + ": " + ;
                    hb_CStr( hRes[ "message" ] ) + Chr(10) )
         ENDIF
      ENDCASE
   ENDDO
   OutStd( Chr(10) + "bye" + Chr(10) )
   RETURN NIL

// Reads one line from stdin. Returns the line, or NIL at end of input.
STATIC FUNCTION DSREPL_ReadLine()
   LOCAL cLine := "", cCh := Space(1), nRead, hIn := hb_GetStdIn()
   DO WHILE .T.
      nRead := FRead( hIn, @cCh, 1 )
      IF nRead == 0
         RETURN iif( Empty( cLine ), NIL, cLine )
      ENDIF
      IF cCh == Chr(10)
         EXIT
      ENDIF
      IF cCh != Chr(13)
         cLine += cCh
      ENDIF
   ENDDO
   RETURN cLine

// Formats the per-turn token usage line from a DS_AgentRun usage hash.
STATIC FUNCTION DSREPL_UsageLine( xUsage )
   LOCAL nP := 0, nC := 0
   IF ValType( xUsage ) == "H"
      IF hb_HHasKey( xUsage, "prompt_tokens" ) .AND. ;
         ValType( xUsage[ "prompt_tokens" ] ) == "N"
         nP := xUsage[ "prompt_tokens" ]
      ENDIF
      IF hb_HHasKey( xUsage, "completion_tokens" ) .AND. ;
         ValType( xUsage[ "completion_tokens" ] ) == "N"
         nC := xUsage[ "completion_tokens" ]
      ENDIF
   ENDIF
   RETURN "[tokens: prompt " + LTrim( Str( nP ) ) + ", completion " + ;
          LTrim( Str( nC ) ) + "]"
```

- [ ] **Step 2: Create the `cc.hbp` build project**

`cc.hbp` (in the repo root):

```
-occ
-mt
src/dsconfig.prg
src/dssse.prg
src/dshttp.prg
src/dsapi.prg
src/dsagent.prg
src/dstools.prg
src/dstools_file.prg
src/dstools_search.prg
src/dstools_shell.prg
src/dsui.prg
src/dsrepl.prg
```

- [ ] **Step 3: Build cc.exe**

Run (from the repo root): `hbmk2 cc.hbp`
Expected: builds clean; produces `cc.exe` in the repo root; exit code 0.

- [ ] **Step 4: Verify the test suite still builds and passes**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: `pass: <N>   fail: 0`, exit code 0 — `dsrepl.prg` is not part of the
test build, so the suite is unaffected.

- [ ] **Step 5: Manual smoke test**

This step is interactive and is run by the human partner, not automated.

Without a key set, run `cc.exe`:
Expected: prints `Error: no API key. Set DEEPSEEK_API_KEY.` and exits.

With a key set (`set DEEPSEEK_API_KEY=<key>`), run `cc.exe`:
1. The banner `CCHarbour - model: deepseek-chat. /help for commands.` appears.
2. At the `>` prompt, type `/help` — the three commands are listed.
3. Type `read the file src/dsui.prg and tell me how many functions it defines`
   — streamed text appears, a `-> read ...` line appears, then the reply, then
   a `[tokens: ...]` line.
4. Type `/clear` — `[conversation reset]` appears.
5. Type `/exit` — `bye` appears and the program exits with code 0.

- [ ] **Step 6: Commit**

```bash
git add src/dsrepl.prg cc.hbp
git commit -m "feat: interactive terminal REPL and cc.exe build"
```

---

## Self-Review

**Spec coverage:**
- `dsui.prg` pure API — `DSUI_ParseCommand` (Task 2), `DSUI_Summarize` /
  `DSUI_RenderEvent` (Task 3), `DSUI_SystemPrompt` / `DSUI_Help` (Task 4).
- `dsrepl.prg` — `Main`, `DSREPL_Run`, stdin reader, usage line (Task 5).
- REPL flow: config check, registry, seeded system message, read/dispatch loop,
  clone-per-turn, commit-on-success — Task 5.
- Three commands plus message/empty handling — Tasks 2 and 5.
- Streaming render via `bRender` / `DSUI_RenderEvent` — Tasks 3 and 5.
- Error handling: missing key, agent failure, iteration cap, EOF,
  `BEGIN SEQUENCE` net — Task 5.
- `cc.hbp` -> `cc.exe` build — Task 5.
- Testing: `dsui.prg` unit tests (Tasks 2–4), documented manual smoke test
  (Task 5 Step 5).

**Placeholder scan:** none. The Task 1 stub is intentional, replaced in Task 2.
Every code step shows complete code. Task 5 has no unit-test steps because the
REPL is pure I/O — this is stated and replaced by a clean build plus the
documented smoke test, consistent with #1's `integration.exe`.

**Type consistency:** `hAction` keys (`type` / `text`); the event hashes read by
`DSUI_RenderEvent` (`type`, `text`, `name`, `arguments`, `content`, `message`)
match the events emitted by #2/#3; the `DS_AgentRun` call uses `hOpts` keys
`model` / `tools` / `tool_executor` and reads `hResult` keys `success` /
`messages` / `stop_reason` / `usage` / `error_type` / `message` exactly as
defined in #2; `DSTools_Registry` / `DSTools_Schemas` / `DSTools_Executor` and
`DS_Client` / `DSCFG_Resolve` are used with the signatures from #1 and #3.

**Deviation from spec:** `cc.hbp` uses `-mt` only (no `-gtcgi`) — see the
Deviation section; the REPL's `OutStd`/`FRead` I/O bypasses the GT.

**Deferred (out of scope for #4):** typing during a streaming response and
mid-response cancellation (#6.5); persistent on-disk history and settings (#5);
`shell` hard timeout (#6.5).

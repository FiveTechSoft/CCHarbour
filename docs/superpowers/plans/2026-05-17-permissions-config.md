# Permissions and Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a permission gate that checks each tool call against allow/deny/ask rules, and a `settings.json` file that supplies those rules plus model/url/iteration config.

**Architecture:** Two pure modules. `src/dssettings.prg` loads `settings.json` merged over built-in defaults. `src/dsperm.prg` wraps the raw tool executor from #3 with a gate that consults per-tool modes and an injectable `bAsk` callback, returning a new executor with the identical contract. `src/dsrepl.prg` wires both into `Main`.

**Tech Stack:** Harbour (MT build, `hbmk2`, BCC), core `hb_jsonDecode` / `hb_jsonEncode`. Reuses the #1–#4 test harness.

---

## File Structure

```
src/dssettings.prg     DSSettings_Defaults, DSSettings_Load
src/dsperm.prg         DSPerm_Gate (+ STATIC helpers)
src/dsrepl.prg         (modified) wire settings + gate into Main
cc.hbp                 (modified) add the two new src files
tests/test_settings.prg  Unit tests for dssettings
tests/test_perm.prg      Unit tests for dsperm
tests/tests.hbp          (modified) add test files + src files
tests/run_tests.prg      (modified) call Test_Settings() and Test_Perm()
```

Conventions (same as #1–#4): public functions are `FUNCTION`, private helpers
are `STATIC FUNCTION`. Hashes carry data. No public function throws an uncaught
exception.

The test build runs from `tests/`: `hbmk2 tests.hbp` -> `tests/run_tests.exe`.
The app build runs from the repo root: `hbmk2 cc.hbp` -> `cc.exe`. The
toolchain is not on PATH — prefix it:
`$env:PATH = 'C:\harbour\bin\win\bcc;C:\bcc77\bin;' + $env:PATH`.

---

### Task 1: Scaffold — settings and permission modules

**Files:**
- Create: `src/dssettings.prg`
- Create: `src/dsperm.prg`
- Create: `tests/test_settings.prg`
- Create: `tests/test_perm.prg`
- Modify: `tests/tests.hbp`
- Modify: `tests/run_tests.prg`

- [ ] **Step 1: Create the `dssettings.prg` stub**

`src/dssettings.prg`:

```harbour
FUNCTION DSSettings_Defaults()
   RETURN NIL
```

- [ ] **Step 2: Create the `dsperm.prg` stub**

`src/dsperm.prg`:

```harbour
FUNCTION DSPerm_Gate( bInner, hPermissions, bAsk )
   HB_SYMBOL_UNUSED( bInner )
   HB_SYMBOL_UNUSED( hPermissions )
   HB_SYMBOL_UNUSED( bAsk )
   RETURN NIL
```

- [ ] **Step 3: Create the two test-file stubs**

`tests/test_settings.prg`:

```harbour
FUNCTION Test_Settings()
   RETURN NIL
```

`tests/test_perm.prg`:

```harbour
FUNCTION Test_Perm()
   RETURN NIL
```

- [ ] **Step 4: Add the four files to the test build**

In `tests/tests.hbp`, add `test_settings.prg` and `test_perm.prg` after
`test_ui.prg`, and `../src/dssettings.prg` and `../src/dsperm.prg` after
`../src/dsui.prg`. The file becomes:

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
test_settings.prg
test_perm.prg
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
../src/dssettings.prg
../src/dsperm.prg
```

- [ ] **Step 5: Call the new test functions from the runner**

In `tests/run_tests.prg`, add the two calls to `Main()` after `Test_UI()`:

```harbour
FUNCTION Main()
   Test_SSE()
   Test_Config()
   Test_Http()
   Test_Api()
   Test_Agent()
   Test_Tools()
   Test_UI()
   Test_Settings()
   Test_Perm()
   ? ""
   ? "pass: " + LTrim( Str( s_nPass ) ) + "   fail: " + LTrim( Str( s_nFail ) )
   ErrorLevel( iif( s_nFail > 0, 1, 0 ) )
   RETURN NIL
```

- [ ] **Step 6: Build and run**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: builds clean; output ends with `pass: 142   fail: 0` (the 142
existing tests; the new entry points add none yet); exit code 0.

- [ ] **Step 7: Commit**

```bash
git add src/dssettings.prg src/dsperm.prg tests/test_settings.prg tests/test_perm.prg tests/tests.hbp tests/run_tests.prg
git commit -m "chore: scaffold permissions and settings modules"
```

---

### Task 2: dssettings — defaults and file loading

**Files:**
- Modify: `src/dssettings.prg` (replace stub)
- Modify: `tests/test_settings.prg` (replace stub)

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `tests/test_settings.prg`:

```harbour
FUNCTION Test_Settings()
   LOCAL hD, hL, cTmp

   // defaults
   hD := DSSettings_Defaults()
   T_Equal( hD[ "model" ], "deepseek-chat", "settings: default model" )
   T_Equal( hD[ "base_url" ], "https://api.deepseek.com", "settings: default base_url" )
   T_Equal( hD[ "max_iterations" ], 25, "settings: default max_iterations" )
   T_Equal( hD[ "permissions" ][ "shell" ], "ask", "settings: default shell mode" )
   T_Equal( hD[ "permissions" ][ "read" ], "allow", "settings: default read mode" )

   // missing file -> defaults
   hL := DSSettings_Load( hb_DirTemp() + "no_such_settings.json" )
   T_Equal( hL[ "model" ], "deepseek-chat", "settings: missing file uses defaults" )

   // a file overriding model and one permission
   cTmp := hb_DirTemp() + "ccharbour_test_settings.json"
   hb_MemoWrit( cTmp, '{"model":"deepseek-reasoner","permissions":{"shell":"allow"}}' )
   hL := DSSettings_Load( cTmp )
   T_Equal( hL[ "model" ], "deepseek-reasoner", "settings: file overrides model" )
   T_Equal( hL[ "base_url" ], "https://api.deepseek.com", "settings: unset key keeps default" )
   T_Equal( hL[ "permissions" ][ "shell" ], "allow", "settings: file overrides one permission" )
   T_Equal( hL[ "permissions" ][ "read" ], "allow", "settings: other permissions keep defaults" )
   FErase( cTmp )

   // malformed JSON -> defaults
   cTmp := hb_DirTemp() + "ccharbour_bad_settings.json"
   hb_MemoWrit( cTmp, "{not valid json" )
   hL := DSSettings_Load( cTmp )
   T_Equal( hL[ "model" ], "deepseek-chat", "settings: malformed file uses defaults" )
   FErase( cTmp )
   RETURN NIL
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL / build error for the `settings:` tests — `DSSettings_Defaults`
returns NIL and `DSSettings_Load` is undefined. The 142 existing tests still
pass.

- [ ] **Step 3: Implement dssettings.prg**

Replace the entire contents of `src/dssettings.prg`:

```harbour
// Returns the built-in default settings hash.
FUNCTION DSSettings_Defaults()
   RETURN { "model"          => "deepseek-chat", ;
            "base_url"       => "https://api.deepseek.com", ;
            "max_iterations" => 25, ;
            "permissions"    => { "read"  => "allow", "glob"  => "allow", ;
                                  "grep"  => "allow", "write" => "ask", ;
                                  "edit"  => "ask",   "shell" => "ask" } }

// Loads settings.json merged over the defaults.
// cPath omitted -> env CCHARBOUR_CONFIG, else .ccharbour/settings.json under cwd.
// Missing or malformed file -> the pure defaults. Never throws.
FUNCTION DSSettings_Load( cPath )
   LOCAL hSet := DSSettings_Defaults(), cText, xJson, cKey, cTool
   IF Empty( cPath )
      cPath := hb_GetEnv( "CCHARBOUR_CONFIG" )
   ENDIF
   IF Empty( cPath )
      cPath := ".ccharbour" + hb_ps() + "settings.json"
   ENDIF
   IF !hb_FileExists( cPath )
      RETURN hSet
   ENDIF
   cText := hb_MemoRead( cPath )
   xJson := hb_jsonDecode( cText )
   IF ValType( xJson ) != "H"
      RETURN hSet
   ENDIF
   FOR EACH cKey IN hb_HKeys( xJson )
      IF cKey == "permissions"
         IF ValType( xJson[ "permissions" ] ) == "H"
            FOR EACH cTool IN hb_HKeys( xJson[ "permissions" ] )
               hSet[ "permissions" ][ cTool ] := xJson[ "permissions" ][ cTool ]
            NEXT
         ENDIF
      ELSE
         hSet[ cKey ] := xJson[ cKey ]
      ENDIF
   NEXT
   RETURN hSet
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `settings:` lines `ok`; the 142 existing tests still `ok`; exit
code 0.

- [ ] **Step 5: Commit**

```bash
git add src/dssettings.prg tests/test_settings.prg
git commit -m "feat: settings.json loading with defaults"
```

---

### Task 3: dsperm — the permission gate

**Files:**
- Modify: `src/dsperm.prg` (replace stub)
- Modify: `tests/test_perm.prg` (replace stub)

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `tests/test_perm.prg`:

```harbour
FUNCTION Test_Perm()
   LOCAL bGate, bInner, hPerm, nInner, nAsk

   // allow -> inner runs
   nInner := 0
   bInner := {| cN, cA | HB_SYMBOL_UNUSED( cN ), HB_SYMBOL_UNUSED( cA ), ;
                         nInner++, "ran" }
   bGate := DSPerm_Gate( bInner, { "read" => "allow" }, NIL )
   T_Equal( Eval( bGate, "read", "{}" ), "ran", "perm: allow runs inner" )
   T_Equal( nInner, 1, "perm: allow called inner once" )

   // deny -> inner never runs
   nInner := 0
   bGate := DSPerm_Gate( bInner, { "shell" => "deny" }, NIL )
   T_Assert( "denied by policy" $ Eval( bGate, "shell", "{}" ), ;
             "perm: deny returns policy error" )
   T_Equal( nInner, 0, "perm: deny did not call inner" )

   // ask + "y" -> inner runs
   nInner := 0
   bGate := DSPerm_Gate( bInner, { "shell" => "ask" }, ;
      {| cN, cA | HB_SYMBOL_UNUSED( cN ), HB_SYMBOL_UNUSED( cA ), "y" } )
   T_Equal( Eval( bGate, "shell", "{}" ), "ran", "perm: ask+y runs inner" )

   // ask + "n" -> denied
   nInner := 0
   bGate := DSPerm_Gate( bInner, { "shell" => "ask" }, ;
      {| cN, cA | HB_SYMBOL_UNUSED( cN ), HB_SYMBOL_UNUSED( cA ), "n" } )
   T_Assert( "denied by user" $ Eval( bGate, "shell", "{}" ), ;
             "perm: ask+n returns user error" )
   T_Equal( nInner, 0, "perm: ask+n did not call inner" )

   // ask + "a" -> session upgrade: inner runs twice, ask asked once
   nInner := 0
   nAsk := 0
   bGate := DSPerm_Gate( bInner, { "shell" => "ask" }, ;
      {| cN, cA | HB_SYMBOL_UNUSED( cN ), HB_SYMBOL_UNUSED( cA ), nAsk++, "a" } )
   Eval( bGate, "shell", "{}" )
   Eval( bGate, "shell", "{}" )
   T_Equal( nAsk, 1, "perm: 'a' asks only once" )
   T_Equal( nInner, 2, "perm: 'a' runs inner both times" )

   // ask with no bAsk -> fails closed (deny)
   nInner := 0
   bGate := DSPerm_Gate( bInner, { "shell" => "ask" }, NIL )
   T_Assert( "denied" $ Eval( bGate, "shell", "{}" ), "perm: ask + no bAsk denies" )
   T_Equal( nInner, 0, "perm: ask + no bAsk did not call inner" )

   // invalid mode -> treated as ask (here, no bAsk -> deny)
   bGate := DSPerm_Gate( bInner, { "shell" => "maybe" }, NIL )
   T_Assert( "denied" $ Eval( bGate, "shell", "{}" ), "perm: invalid mode treated as ask" )

   // caller's permissions hash is not mutated by an "a" upgrade
   hPerm := { "shell" => "ask" }
   bGate := DSPerm_Gate( bInner, hPerm, ;
      {| cN, cA | HB_SYMBOL_UNUSED( cN ), HB_SYMBOL_UNUSED( cA ), "a" } )
   Eval( bGate, "shell", "{}" )
   T_Equal( hPerm[ "shell" ], "ask", "perm: caller hash not mutated" )
   RETURN NIL
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL for the `perm:` tests — `DSPerm_Gate` is the stub returning NIL,
so `Eval` on it raises an error. The existing tests still pass.

- [ ] **Step 3: Implement dsperm.prg**

Replace the entire contents of `src/dsperm.prg`:

```harbour
// Wraps a raw tool executor with a permission gate.
// bInner       : the raw executor, {|cName,cArgsJson| -> cString}.
// hPermissions : { toolName => "allow"|"deny"|"ask" }.
// bAsk         : optional {|cName,cArgsJson| -> "y"|"n"|"a"}.
// Returns a gated executor with the same {|cName,cArgsJson| -> cString} contract.
FUNCTION DSPerm_Gate( bInner, hPermissions, bAsk )
   LOCAL hPerm := DSPerm_CloneModes( hPermissions )
   RETURN {| cName, cArgsJson | ;
      DSPerm_Decide( hPerm, bInner, bAsk, cName, cArgsJson ) }

// Copies the caller's permission hash so an "a" upgrade never mutates it.
STATIC FUNCTION DSPerm_CloneModes( hPermissions )
   LOCAL hOut := {=>}, cKey
   IF ValType( hPermissions ) == "H"
      FOR EACH cKey IN hb_HKeys( hPermissions )
         hOut[ cKey ] := hPermissions[ cKey ]
      NEXT
   ENDIF
   RETURN hOut

// Decides allow/deny for one call; "a" upgrades the tool to allow for the session.
STATIC FUNCTION DSPerm_Decide( hPerm, bInner, bAsk, cName, cArgsJson )
   LOCAL cMode, cAns
   cMode := iif( hb_HHasKey( hPerm, cName ), hPerm[ cName ], "ask" )
   IF !( cMode == "allow" .OR. cMode == "deny" .OR. cMode == "ask" )
      cMode := "ask"
   ENDIF
   DO CASE
   CASE cMode == "allow"
      RETURN Eval( bInner, cName, cArgsJson )
   CASE cMode == "deny"
      RETURN "Error: tool '" + hb_CStr( cName ) + "' denied by policy"
   ENDCASE
   // cMode == "ask"
   cAns := iif( bAsk == NIL, "n", DSPerm_Norm( Eval( bAsk, cName, cArgsJson ) ) )
   DO CASE
   CASE cAns == "y"
      RETURN Eval( bInner, cName, cArgsJson )
   CASE cAns == "a"
      hPerm[ cName ] := "allow"
      RETURN Eval( bInner, cName, cArgsJson )
   ENDCASE
   RETURN "Error: tool '" + hb_CStr( cName ) + "' denied by user"

// Normalises an ask answer to a single lowercase character; non-strings -> "n".
STATIC FUNCTION DSPerm_Norm( xAns )
   LOCAL cAns
   IF ValType( xAns ) != "C"
      RETURN "n"
   ENDIF
   cAns := Lower( AllTrim( xAns ) )
   RETURN iif( Empty( cAns ), "n", Left( cAns, 1 ) )
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `perm:` lines `ok`; the existing tests still `ok`; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add src/dsperm.prg tests/test_perm.prg
git commit -m "feat: permission gate with allow/deny/ask and session upgrade"
```

---

### Task 4: Wire settings and the gate into the REPL

**Files:**
- Modify: `src/dsrepl.prg` (replace whole file)
- Modify: `cc.hbp`

`dsrepl.prg` is pure I/O and orchestration; it is verified by a clean build and
a documented manual smoke test.

- [ ] **Step 1: Replace `src/dsrepl.prg`**

Replace the entire contents of `src/dsrepl.prg`:

```harbour
#include "fileio.ch"

// Program entry point. Optional cModel CLI argument overrides the settings model.
FUNCTION Main( cModel )
   LOCAL hSet, hCfg, oClient, oReg, bGate, oErr
   hSet := DSSettings_Load()
   IF Empty( cModel )
      cModel := hb_GetEnv( "DEEPSEEK_MODEL" )
   ENDIF
   IF Empty( cModel )
      cModel := hSet[ "model" ]
   ENDIF
   hCfg := DSCFG_Resolve( {=>} )
   IF !hCfg[ "ok" ]
      OutStd( "Error: no API key. Set DEEPSEEK_API_KEY." + Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   ENDIF
   oClient := DS_Client( { "model" => cModel, "base_url" => hSet[ "base_url" ] } )
   oReg    := DSTools_Registry()
   bGate   := DSPerm_Gate( DSTools_Executor( oReg ), hSet[ "permissions" ], ;
                           {| cN, cA | DSREPL_AskPerm( cN, cA ) } )
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      DSREPL_Run( oClient, oReg, cModel, bGate, hSet[ "max_iterations" ] )
   RECOVER USING oErr
      OutStd( Chr(10) + "Fatal: " + ;
              iif( ValType( oErr ) == "O", hb_CStr( oErr:Description ), "exception" ) + ;
              Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   END SEQUENCE
   RETURN NIL

// The interactive loop: read a line, dispatch, run the agent, repeat.
FUNCTION DSREPL_Run( oClient, oReg, cModel, bGate, nMaxIter )
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
              "tool_executor" => bGate, ;
              "max_iterations" => nMaxIter }, ;
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

// Permission prompt for a tool in "ask" mode. Returns the typed answer
// ("y"/"n"/"a"); the gate normalises it. Never throws.
STATIC FUNCTION DSREPL_AskPerm( cName, cArgsJson )
   LOCAL cLine := "n", oErr
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      OutStd( Chr(10) + "Tool '" + hb_CStr( cName ) + "' wants to run: " + ;
              DSUI_Summarize( hb_CStr( cArgsJson ), 120 ) + Chr(10) + ;
              "Allow? [y/n/a] " )
      cLine := DSREPL_ReadLine()
      IF cLine == NIL
         cLine := "n"
      ENDIF
   RECOVER USING oErr
      HB_SYMBOL_UNUSED( oErr )
      cLine := "n"
   END SEQUENCE
   RETURN cLine

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
   // strip a leading UTF-8 BOM (piped input on Windows may prepend one)
   IF hb_BLeft( cLine, 3 ) == Chr(239) + Chr(187) + Chr(191)
      cLine := SubStr( cLine, 4 )
   ENDIF
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

- [ ] **Step 2: Add the new sources to `cc.hbp`**

Replace the entire contents of `cc.hbp`:

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
src/dssettings.prg
src/dsperm.prg
src/dsui.prg
src/dsrepl.prg
```

- [ ] **Step 3: Build cc.exe**

Run (from the repo root): `hbmk2 cc.hbp`
Expected: builds clean; produces `cc.exe`; exit code 0.

- [ ] **Step 4: Verify the test suite still builds and passes**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: `pass: <N>   fail: 0`, exit code 0 — `dsrepl.prg` is not in the test
build, so the suite is unaffected.

- [ ] **Step 5: Manual smoke test**

This step is interactive and is run by the human partner.

With `DEEPSEEK_API_KEY` set and no settings file present, run `cc.exe`:
1. Ask the assistant to run a shell command (e.g. `run the shell command: echo
   hi`). A `Tool 'shell' wants to run: ... Allow? [y/n/a]` prompt appears.
2. Type `n` — the assistant receives a "denied by user" result and reports it.
3. Ask again and type `y` — the command runs.

Then create `.ccharbour/settings.json` containing
`{"permissions":{"shell":"deny"}}` and run `cc.exe` again:
4. Ask the assistant to run a shell command — no prompt appears; the result is
   a "denied by policy" error.

`/exit` quits with code 0 in both runs.

- [ ] **Step 6: Commit**

```bash
git add src/dsrepl.prg cc.hbp
git commit -m "feat: wire settings and permission gate into the REPL"
```

---

## Self-Review

**Spec coverage:**
- `DSSettings_Defaults` / `DSSettings_Load`, merge, env/cwd path resolution,
  malformed-file handling — Task 2.
- `DSPerm_Gate` and the allow/deny/ask flow, session `"a"` upgrade, fail-closed
  behaviour, caller-hash immutability — Task 3.
- REPL wiring: load settings, build `DS_Client` with `base_url`, build the
  gated executor with `DSREPL_AskPerm`, pass `max_iterations` — Task 4.
- `bAsk` contract and the y/n/a prompt — Task 4 (`DSREPL_AskPerm`).
- `cc.hbp` gains both modules — Task 4.
- Testing: `dssettings` and `dsperm` unit tests (Tasks 2–3), documented manual
  smoke test (Task 4 Step 5).

**Placeholder scan:** none. The Task 1 stubs are intentional, replaced in
Tasks 2–3. Every code step shows complete code. Task 4 has no unit-test steps
because `dsrepl.prg` is pure I/O — stated, and replaced by a clean build plus
the documented smoke test, consistent with #4.

**Type consistency:** `hSettings` keys (`model` / `base_url` /
`max_iterations` / `permissions`); the mode strings (`allow` / `deny` / `ask`);
`DSPerm_Gate( bInner, hPermissions, bAsk )`; the executor contract
`{|cName,cArgsJson|->cString}`; the `bAsk` contract
`{|cName,cArgsJson|->"y"|"n"|"a"}`; and the `DS_AgentRun` `hOpts` keys
(`model` / `tools` / `tool_executor` / `max_iterations`) match #2–#4.
`DS_Client` receiving `base_url` flows through `oClient["opts"]` into
`DSCFG_Resolve` exactly as defined in #1.

**Deferred (out of scope for #5):** argument-pattern permission rules;
user-level / merged settings files; persisting an `"a"` upgrade to
`settings.json`; MCP and hooks (#6); thread pool and cancellation (#6.5).

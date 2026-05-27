# Hooks System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a minimal hooks system to CCHarbour that fires user-defined shell commands when a turn finishes, with a `/hook` REPL command for CRUD.

**Architecture:** New `cchooks.prg` module exposes pure helpers (`Add`/`Remove`/`Edit`/`List`/`IsValidEvent`) and a fire-and-forget `Run` that spawns each configured command via `hb_processOpen` after setting `CCHARBOUR_*` env vars. `CCREPL_RunTurn` calls `CCHOOKS_Run( "turn_complete", ... )` after each turn. `/hook` slash-command is wired through the existing `ccui.prg` parser → `ccrepl.prg` dispatch. Settings live under `hooks` and `hooks_log` keys in `.ccharbour/settings.json`.

**Tech Stack:** Harbour (Cl*pper-style), `hb_processOpen`, `hb_SetEnv`, `hb_MemoRead`/`hb_MemoWrit`, `hb_jsonEncode`/`hb_jsonDecode`, existing CCSETTINGS / CCREPL infrastructure.

**Spec:** `docs/superpowers/specs/2026-05-27-hooks-system-design.md`

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `src/cchooks.prg` | Pure helpers + fire-and-forget `Run` + log writer | Create |
| `src/ccsettings.prg` | Add `hooks` / `hooks_log` to defaults + merge sub-hash | Modify |
| `src/ccui.prg` | Parse `/hook` into `{ type=>"hook", text=>... }` | Modify |
| `src/ccrepl.prg` | Dispatch `"hook"` action + fire `turn_complete` post-RunTurn + `CCREPL_HandleHook` | Modify |
| `cc.hbp`, `cc_linux.hbp`, `cc_mac.hbp` | Register `src/cchooks.prg` for all three platform builds | Modify |
| `tests/test_hooks.prg` | Unit + integration tests | Create |
| `tests/run_tests.prg` | Register `Test_Hooks()` | Modify |
| `tests/tests.hbp` | Add `test_hooks.prg` + `../src/cchooks.prg` | Modify |

---

### Task 1: Settings defaults + load merge

**Files:**
- Modify: `src/ccsettings.prg` (CCSETTINGS_Defaults at line 5, CCSETTINGS_Load at line 25)
- Modify: `tests/test_settings.prg` (Test_Settings)

- [ ] **Step 1.1: Add failing tests in `tests/test_settings.prg`**

Append before the final `RETURN NIL`:
```harbour
   // hooks defaults
   hL := CCSETTINGS_Defaults()
   T_Equal( ValType( hL[ "hooks" ] ), "H", "settings: default hooks is hash" )
   T_Equal( Len( hb_HKeys( hL[ "hooks" ] ) ), 0, "settings: default hooks empty" )
   T_Equal( hL[ "hooks_log" ], .F., "settings: default hooks_log false" )

   // hooks merge from file
   cTmp := hb_DirTemp() + "ccharbour_hooks_settings.json"
   hb_MemoWrit( cTmp, '{"hooks":{"turn_complete":["echo hi"]},"hooks_log":true}' )
   hL := CCSETTINGS_Load( cTmp )
   T_Equal( Len( hL[ "hooks" ][ "turn_complete" ] ), 1, "settings: hooks array merged" )
   T_Equal( hL[ "hooks" ][ "turn_complete" ][ 1 ], "echo hi", "settings: hook cmd preserved" )
   T_Equal( hL[ "hooks_log" ], .T., "settings: hooks_log merged" )
   FErase( cTmp )
```

- [ ] **Step 1.2: Run test to verify it fails**

Build + run tests (see Task 8 for the full build command; for now compile incrementally):
```cmd
cd c:\CCHarbour\tests
"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp
.\run_tests.exe
```
Expected: 4 new FAILs for the hooks lines (defaults missing + merge missing).

- [ ] **Step 1.3: Update `CCSETTINGS_Defaults` in `src/ccsettings.prg`**

Replace the existing `FUNCTION CCSETTINGS_Defaults` body (lines 5-18) with:
```harbour
FUNCTION CCSETTINGS_Defaults()
   RETURN { "model"             => "deepseek-v4-flash", ;
            "base_url"          => "https://api.deepseek.com", ;
            "max_iterations"    => 25, ;
            "color"             => .T., ;
            "co_author"         => "", ;
            "shell_timeout"     => 30, ;
            "compact_threshold" => 0.7, ;
            "permissions"       => { "read"  => "allow", "glob"  => "allow", ;
                                     "grep"  => "allow", "write" => "ask", ;
                                     "edit"  => "ask",   "shell" => "ask", ;
                                     "web_search"   => "ask",   "web_fetch"    => "ask", ;
                                     "github_read"  => "allow", "github_write" => "ask", ;
                                     "memory" => "allow" }, ;
            "hooks"             => {=>}, ;
            "hooks_log"         => .F. }
```

- [ ] **Step 1.4: Update `CCSETTINGS_Load` merge loop**

In `src/ccsettings.prg`, locate the `FOR EACH cKey IN hb_HKeys( xJson )` loop (lines 48-58). Replace it with:
```harbour
   FOR EACH cKey IN hb_HKeys( xJson )
      IF cKey == "permissions"
         IF ValType( xJson[ "permissions" ] ) == "H"
            FOR EACH cTool IN hb_HKeys( xJson[ "permissions" ] )
               hSet[ "permissions" ][ cTool ] := xJson[ "permissions" ][ cTool ]
            NEXT
         ENDIF
      ELSEIF cKey == "hooks"
         IF ValType( xJson[ "hooks" ] ) == "H"
            hSet[ "hooks" ] := xJson[ "hooks" ]
         ENDIF
      ELSE
         hSet[ cKey ] := xJson[ cKey ]
      ENDIF
   NEXT
```

The whole-hash replace (not per-event merge) is deliberate: hooks are user-authored, and a missing event key in the file should mean "no hooks for that event," not "fall back to defaults" (defaults are empty anyway).

- [ ] **Step 1.5: Run test to verify it passes**

```cmd
cd c:\CCHarbour\tests
"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp
.\run_tests.exe
```
Expected: all 4 new tests PASS, previous tests still PASS.

- [ ] **Step 1.6: Commit**

```cmd
git add src/ccsettings.prg tests/test_settings.prg
git commit -m "feat(settings): default hooks/hooks_log keys with merge support

Add hooks (empty hash) and hooks_log (false) to CCSETTINGS_Defaults
and merge them from settings.json. Whole-hash replace for hooks,
matching the user-authored semantics."
```

---

### Task 2: `cchooks.prg` pure helpers + `IsValidEvent`

**Files:**
- Create: `src/cchooks.prg`
- Create: `tests/test_hooks.prg`

- [ ] **Step 2.1: Create `tests/test_hooks.prg` with the pure-function tests**

```harbour
// Unit and integration tests for the hooks system.
// Pure helpers tested in-process; spawn/log tests touch the filesystem
// under hb_DirTemp() and clean up after themselves.
FUNCTION Test_Hooks()
   LOCAL hSet, aList, lOk

   // CCHOOKS_ValidEvents
   T_Equal( hb_CStr( CCHOOKS_ValidEvents()[ 1 ] ), "turn_complete", ;
           "hooks: turn_complete is the canonical event" )
   T_Equal( CCHOOKS_IsValidEvent( "turn_complete" ), .T., ;
           "hooks: turn_complete is valid" )
   T_Equal( CCHOOKS_IsValidEvent( "foo" ), .F., ;
           "hooks: 'foo' is not a valid event" )

   // CCHOOKS_List: empty settings
   hSet := { "hooks" => {=>} }
   T_Equal( Len( CCHOOKS_List( hSet, "turn_complete" ) ), 0, ;
           "hooks: list empty when no event" )

   // CCHOOKS_Add appends
   hSet := { "hooks" => {=>} }
   T_Equal( CCHOOKS_Add( hSet, "turn_complete", "echo a" ), .T., ;
           "hooks: add valid event returns .T." )
   T_Equal( Len( hSet[ "hooks" ][ "turn_complete" ] ), 1, ;
           "hooks: add creates array of len 1" )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 1 ], "echo a", ;
           "hooks: add stores cmd verbatim" )
   CCHOOKS_Add( hSet, "turn_complete", "echo b" )
   T_Equal( Len( hSet[ "hooks" ][ "turn_complete" ] ), 2, ;
           "hooks: second add appends" )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 2 ], "echo b", ;
           "hooks: append preserves order" )

   // Add invalid event
   T_Equal( CCHOOKS_Add( hSet, "foo", "echo x" ), .F., ;
           "hooks: add invalid event returns .F." )

   // CCHOOKS_Remove valid + out-of-range
   hSet := { "hooks" => { "turn_complete" => { "a", "b", "c" } } }
   T_Equal( CCHOOKS_Remove( hSet, "turn_complete", 2 ), .T., ;
           "hooks: remove valid idx returns .T." )
   T_Equal( Len( hSet[ "hooks" ][ "turn_complete" ] ), 2, ;
           "hooks: remove shrinks array" )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 1 ], "a", ;
           "hooks: remove preserves earlier" )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 2 ], "c", ;
           "hooks: remove preserves later" )
   T_Equal( CCHOOKS_Remove( hSet, "turn_complete", 99 ), .F., ;
           "hooks: remove out-of-range returns .F." )
   T_Equal( Len( hSet[ "hooks" ][ "turn_complete" ] ), 2, ;
           "hooks: remove out-of-range no mutation" )

   // CCHOOKS_Edit
   hSet := { "hooks" => { "turn_complete" => { "old1", "old2" } } }
   T_Equal( CCHOOKS_Edit( hSet, "turn_complete", 1, "new1" ), .T., ;
           "hooks: edit valid idx returns .T." )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 1 ], "new1", ;
           "hooks: edit replaces at idx" )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 2 ], "old2", ;
           "hooks: edit leaves other entries" )
   T_Equal( CCHOOKS_Edit( hSet, "turn_complete", 99, "x" ), .F., ;
           "hooks: edit out-of-range returns .F." )

   RETURN NIL
```

Note: `Test_Hooks` won't compile yet because the helpers don't exist. That is the failing-test state.

- [ ] **Step 2.2: Wire `Test_Hooks` into `tests/run_tests.prg` and `tests/tests.hbp`**

In `tests/run_tests.prg`, add `Test_Hooks()` before the `? ""` line (after `Test_Diff()`):
```harbour
   Test_Diff()
   Test_Hooks()
   ? ""
```

In `tests/tests.hbp`, add `test_hooks.prg` after `test_diff.prg`, and `../src/cchooks.prg` after the last `../src/cc*.prg` line:
```
test_diff.prg
test_hooks.prg
...
../src/ccsettings.prg
../src/cchooks.prg
```

- [ ] **Step 2.3: Run tests to verify they fail**

```cmd
cd c:\CCHarbour\tests
"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp
```
Expected: the build itself fails because `cchooks.prg` does not exist yet ("cannot open file ../src/cchooks.prg"). That's the failing state for this task.

- [ ] **Step 2.4: Create `src/cchooks.prg` with the pure helpers**

```harbour
// Canonical list of events the hooks system supports.
// Keep this small until a real use case justifies expansion.
FUNCTION CCHOOKS_ValidEvents()
   RETURN { "turn_complete" }

// True if cEvent is in the canonical event list.
FUNCTION CCHOOKS_IsValidEvent( cEvent )
   RETURN AScan( CCHOOKS_ValidEvents(), {| c | c == cEvent } ) > 0

// Returns the array of hook command strings registered for cEvent in
// hSet, or an empty array if the event is absent or hSet has no hooks
// key. Safe to call with arbitrary settings hashes.
FUNCTION CCHOOKS_List( hSet, cEvent )
   IF ValType( hSet ) != "H" .OR. !hb_HHasKey( hSet, "hooks" )
      RETURN {}
   ENDIF
   IF ValType( hSet[ "hooks" ] ) != "H" .OR. ;
      !hb_HHasKey( hSet[ "hooks" ], cEvent )
      RETURN {}
   ENDIF
   RETURN hSet[ "hooks" ][ cEvent ]

// Appends cCmd to hSet["hooks"][cEvent], creating intermediate keys as
// needed. Returns .T. on success, .F. if cEvent is not a valid event.
// Mutates hSet in place; caller is responsible for CCSETTINGS_Save.
FUNCTION CCHOOKS_Add( hSet, cEvent, cCmd )
   IF !CCHOOKS_IsValidEvent( cEvent )
      RETURN .F.
   ENDIF
   IF ValType( hSet ) != "H"
      RETURN .F.
   ENDIF
   IF !hb_HHasKey( hSet, "hooks" ) .OR. ValType( hSet[ "hooks" ] ) != "H"
      hSet[ "hooks" ] := {=>}
   ENDIF
   IF !hb_HHasKey( hSet[ "hooks" ], cEvent )
      hSet[ "hooks" ][ cEvent ] := {}
   ENDIF
   AAdd( hSet[ "hooks" ][ cEvent ], cCmd )
   RETURN .T.

// Removes the 1-based nIdx-th entry from hSet["hooks"][cEvent]. Returns
// .F. (and leaves hSet untouched) if the event is missing or the index
// is out of range. Mutates hSet on success.
FUNCTION CCHOOKS_Remove( hSet, cEvent, nIdx )
   LOCAL aHooks
   IF !CCHOOKS_IsValidEvent( cEvent ) .OR. ValType( hSet ) != "H"
      RETURN .F.
   ENDIF
   aHooks := CCHOOKS_List( hSet, cEvent )
   IF nIdx < 1 .OR. nIdx > Len( aHooks )
      RETURN .F.
   ENDIF
   hb_ADel( aHooks, nIdx, .T. )
   RETURN .T.

// Replaces the 1-based nIdx-th entry with cCmd. Same return-value
// semantics as CCHOOKS_Remove.
FUNCTION CCHOOKS_Edit( hSet, cEvent, nIdx, cCmd )
   LOCAL aHooks
   IF !CCHOOKS_IsValidEvent( cEvent ) .OR. ValType( hSet ) != "H"
      RETURN .F.
   ENDIF
   aHooks := CCHOOKS_List( hSet, cEvent )
   IF nIdx < 1 .OR. nIdx > Len( aHooks )
      RETURN .F.
   ENDIF
   aHooks[ nIdx ] := cCmd
   RETURN .T.
```

- [ ] **Step 2.5: Run tests to verify they pass**

```cmd
cd c:\CCHarbour\tests
"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp
.\run_tests.exe
```
Expected: all `Test_Hooks` pure-helper tests PASS, all previous tests still PASS.

- [ ] **Step 2.6: Commit**

```cmd
git add src/cchooks.prg tests/test_hooks.prg tests/run_tests.prg tests/tests.hbp
git commit -m "feat(hooks): pure CRUD helpers + IsValidEvent

Add cchooks.prg with ValidEvents/IsValidEvent/List/Add/Remove/Edit
plus a tests/test_hooks.prg with full coverage. No spawning or REPL
wiring yet."
```

---

### Task 3: `CCHOOKS_LogPath` + `CCHOOKS_Log`

**Files:**
- Modify: `src/cchooks.prg` (append)
- Modify: `tests/test_hooks.prg` (append within `Test_Hooks`)

- [ ] **Step 3.1: Append failing tests to `Test_Hooks` (before `RETURN NIL`)**

```harbour
   // LogPath returns ".ccharbour/hooks.log" relative to cwd
   T_Equal( CCHOOKS_LogPath(), ".ccharbour" + hb_ps() + "hooks.log", ;
           "hooks: LogPath default" )

   // Log writes only when hooks_log is .T.
   // (use a temp cwd-relative path by stashing cwd, switching, restoring)
   LOCAL cOldCwd := hb_cwd(), cTmpDir, cLogPath
   cTmpDir := hb_DirTemp() + "ccharbour_log_test"
   hb_DirBuild( cTmpDir )
   hb_cwd( cTmpDir )
   // Default settings -> hooks_log .F. -> no file
   FErase( CCHOOKS_LogPath() )
   CCHOOKS_Log( "test line" )
   T_Equal( hb_FileExists( CCHOOKS_LogPath() ), .F., ;
           "hooks: Log no-op when hooks_log disabled" )
   // Enable hooks_log via a real settings.json under .ccharbour/
   hb_DirBuild( ".ccharbour" )
   hb_MemoWrit( ".ccharbour" + hb_ps() + "settings.json", ;
                '{"hooks_log":true}' )
   CCHOOKS_Log( "test line" )
   T_Equal( hb_FileExists( CCHOOKS_LogPath() ), .T., ;
           "hooks: Log writes when hooks_log enabled" )
   T_Assert( "test line" $ hb_MemoRead( CCHOOKS_LogPath() ), ;
            "hooks: Log appends the line" )
   // Cleanup
   FErase( CCHOOKS_LogPath() )
   FErase( ".ccharbour" + hb_ps() + "settings.json" )
   hb_cwd( cOldCwd )
```

- [ ] **Step 3.2: Append helpers to `src/cchooks.prg`**

```harbour
// Path to the hooks log file, relative to the CCHarbour cwd. Matches
// the location convention used by .ccharbour/settings.json so the log
// sits next to the config that opted into it.
FUNCTION CCHOOKS_LogPath()
   RETURN ".ccharbour" + hb_ps() + "hooks.log"

// Appends cLine + LF to CCHOOKS_LogPath() iff settings have hooks_log
// set to .T.. Best-effort: writes are wrapped so a missing directory
// or read-only filesystem cannot crash the REPL.
FUNCTION CCHOOKS_Log( cLine )
   LOCAL hSet := CCSETTINGS_Load(), cTs, cPath, cDir
   IF !hb_HGetDef( hSet, "hooks_log", .F. )
      RETURN NIL
   ENDIF
   cTs   := DToS( Date() ) + " " + Time()
   // Normalise "20260527" -> "2026-05-27" for readability.
   cTs := SubStr( cTs, 1, 4 ) + "-" + SubStr( cTs, 5, 2 ) + "-" + ;
          SubStr( cTs, 7, 2 ) + " " + SubStr( cTs, 10 )
   cPath := CCHOOKS_LogPath()
   cDir  := hb_FNameDir( cPath )
   IF !Empty( cDir ) .AND. !hb_DirExists( cDir )
      hb_DirBuild( cDir )
   ENDIF
   hb_MemoWrit( cPath, hb_MemoRead( cPath ) + ;
                "[" + cTs + "] " + cLine + Chr(10) )
   RETURN NIL
```

- [ ] **Step 3.3: Run tests, verify pass**

```cmd
cd c:\CCHarbour\tests
"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp
.\run_tests.exe
```
Expected: all `hooks: Log*` and `hooks: LogPath*` tests PASS.

- [ ] **Step 3.4: Commit**

```cmd
git add src/cchooks.prg tests/test_hooks.prg
git commit -m "feat(hooks): LogPath and gated Log writer

CCHOOKS_LogPath returns .ccharbour/hooks.log. CCHOOKS_Log appends a
timestamped line iff settings.hooks_log is .T., otherwise no-ops."
```

---

### Task 4: `CCHOOKS_Run` with `hb_processOpen` + env vars

**Files:**
- Modify: `src/cchooks.prg` (append)
- Modify: `tests/test_hooks.prg` (append within `Test_Hooks`)

- [ ] **Step 4.1: Append failing tests to `Test_Hooks`**

```harbour
   // Run: no-op when no hooks
   LOCAL cTmpDir2 := hb_DirTemp() + "ccharbour_run_test"
   hb_DirBuild( cTmpDir2 )
   hb_cwd( cTmpDir2 )
   hb_DirBuild( ".ccharbour" )
   hb_MemoWrit( ".ccharbour" + hb_ps() + "settings.json", "{}" )
   CCHOOKS_Run( "turn_complete", { "status" => "success", ;
      "model" => "m", "tokens" => 0, "duration_ms" => 0 } )
   T_Assert( .T., "hooks: Run with no hooks does not crash" )

   // Run spawns and sets env vars
   LOCAL cMarker := cTmpDir2 + hb_ps() + "marker.txt"
   LOCAL cCmd
   FErase( cMarker )
   IF hb_OsIsWin()
      cCmd := "cmd /c echo %CCHARBOUR_STATUS% > " + cMarker
   ELSE
      cCmd := "sh -c 'echo $CCHARBOUR_STATUS > " + cMarker + "'"
   ENDIF
   hb_MemoWrit( ".ccharbour" + hb_ps() + "settings.json", ;
                '{"hooks":{"turn_complete":["' + StrTran( cCmd, "\", "\\" ) + ;
                '"]},"hooks_log":false}' )
   CCHOOKS_Run( "turn_complete", { "status" => "success", ;
      "model" => "m", "tokens" => 1, "duration_ms" => 10 } )
   // Give the spawned process up to 2 seconds to materialise the file.
   LOCAL nDeadline := hb_MilliSeconds() + 2000
   DO WHILE !hb_FileExists( cMarker ) .AND. hb_MilliSeconds() < nDeadline
      hb_idleSleep( 0.05 )
   ENDDO
   T_Assert( hb_FileExists( cMarker ), ;
            "hooks: Run spawns hook process" )
   T_Assert( "success" $ hb_MemoRead( cMarker ), ;
            "hooks: Run sets CCHARBOUR_STATUS env var" )

   // Cleanup
   FErase( cMarker )
   FErase( ".ccharbour" + hb_ps() + "settings.json" )
   FErase( CCHOOKS_LogPath() )
   hb_cwd( cOldCwd )
```

- [ ] **Step 4.2: Append `CCHOOKS_Run` to `src/cchooks.prg`**

```harbour
// Fires every hook registered under cEvent. hContext keys consumed:
//   "status"       -> "success" | "error" | "interrupted"
//   "model"        -> active model name (string)
//   "tokens"       -> total turn tokens (numeric, 0 if unavailable)
//   "duration_ms"  -> turn wall-clock duration (numeric, 0 if unavailable)
// Each hook is spawned detached (fire-and-forget). Env vars are set on
// the CCHarbour process before each spawn; the child inherits them.
// Failures are logged when hooks_log is on and otherwise silenced.
FUNCTION CCHOOKS_Run( cEvent, hContext )
   LOCAL aHooks, cCmd, hSet, nProc
   IF !CCHOOKS_IsValidEvent( cEvent )
      CCHOOKS_Log( "event=" + hb_CStr( cEvent ) + " WARN unknown-event skip" )
      RETURN NIL
   ENDIF
   hSet := CCSETTINGS_Load()
   aHooks := CCHOOKS_List( hSet, cEvent )
   IF Len( aHooks ) == 0
      RETURN NIL
   ENDIF
   IF ValType( hContext ) != "H"
      hContext := {=>}
   ENDIF
   hb_SetEnv( "CCHARBOUR_EVENT", cEvent )
   hb_SetEnv( "CCHARBOUR_STATUS", ;
      hb_CStr( hb_HGetDef( hContext, "status", "success" ) ) )
   hb_SetEnv( "CCHARBOUR_MODEL", ;
      hb_CStr( hb_HGetDef( hContext, "model", "" ) ) )
   hb_SetEnv( "CCHARBOUR_TOKENS", ;
      LTrim( Str( hb_HGetDef( hContext, "tokens", 0 ) ) ) )
   hb_SetEnv( "CCHARBOUR_DURATION_MS", ;
      LTrim( Str( hb_HGetDef( hContext, "duration_ms", 0 ) ) ) )
   hb_SetEnv( "CCHARBOUR_CWD", hb_cwd() )
   FOR EACH cCmd IN aHooks
      BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
         nProc := hb_processOpen( cCmd, NIL, NIL, NIL, .T. /* detach */ )
         IF nProc == -1
            CCHOOKS_Log( "event=" + cEvent + " ERROR spawn-failed cmd=" + cCmd )
         ELSE
            CCHOOKS_Log( "event=" + cEvent + ;
                         " status=" + ;
                         hb_CStr( hb_HGetDef( hContext, "status", "success" ) ) + ;
                         " cmd=" + cCmd )
         ENDIF
         RECOVER USING oErr
         CCHOOKS_Log( "event=" + cEvent + " ERROR exception cmd=" + cCmd )
         HB_SYMBOL_UNUSED( oErr )
      END SEQUENCE
   NEXT
   RETURN NIL
```

- [ ] **Step 4.3: Run tests, verify pass**

```cmd
cd c:\CCHarbour\tests
"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp
.\run_tests.exe
```
Expected: spawn-related tests PASS within ~2s.

- [ ] **Step 4.4: Commit**

```cmd
git add src/cchooks.prg tests/test_hooks.prg
git commit -m "feat(hooks): Run with fire-and-forget spawn + env context

CCHOOKS_Run spawns each registered hook for cEvent via hb_processOpen
(detached). Env vars CCHARBOUR_EVENT/STATUS/MODEL/TOKENS/DURATION_MS/
CWD are set before each spawn. Spawn failures are logged when
hooks_log is enabled and silenced otherwise."
```

---

### Task 5: Fire `turn_complete` from `CCREPL_RunTurn`

**Files:**
- Modify: `src/ccrepl.prg` (lines 389-418, the `CCREPL_RunTurn` body)

- [ ] **Step 5.1: Locate the function**

`CCREPL_RunTurn` starts at line 389. The block ending at line 417 contains the status branches:
```harbour
   IF hRes[ "success" ]
      CCREPL_ShowTokenBar( hRes[ "usage" ], nTurnMs )
      ...
   ELSE
      CCREPL_Out( Chr(10) )
   ENDIF
   RETURN { "result" => hRes, "render" => oRender }
```

- [ ] **Step 5.2: Insert the fire just before `RETURN`**

Replace the final block (current lines 410-418) with:
```harbour
   IF hRes[ "success" ]
      CCREPL_ShowTokenBar( hRes[ "usage" ], nTurnMs )
      CCREPL_AccumUsage( hRes[ "usage" ] )
      CCREPL_MaybeWarnCompact( hRes[ "usage" ], cModel )
      CCREPL_MaybeWarnNoToolCall( hRes, cModel )
   ELSE
      CCREPL_Out( Chr(10) )
   ENDIF
   CCHOOKS_Run( "turn_complete", { ;
      "status"      => CCREPL_TurnStatus( hRes ), ;
      "model"       => hb_CStr( cModel ), ;
      "tokens"      => CCREPL_TurnTokens( hRes ), ;
      "duration_ms" => nTurnMs } )
   RETURN { "result" => hRes, "render" => oRender }
```

- [ ] **Step 5.3: Add the two helper functions to `src/ccrepl.prg`**

Place them right after `CCREPL_RunTurn`'s `RETURN` (before the `// Implements /provider` comment that follows):
```harbour
// Maps an agent result hash to the string status the hooks system
// expects. interrupted > error precedence: an interrupted turn often
// surfaces as success=.F. with error_type="cancelled" or as
// stop_reason="interrupted" on success=.T..
STATIC FUNCTION CCREPL_TurnStatus( hRes )
   IF ValType( hRes ) != "H"
      RETURN "error"
   ENDIF
   IF hb_HGetDef( hRes, "stop_reason", "" ) == "interrupted" .OR. ;
      hb_CStr( hb_HGetDef( hRes, "error_type", "" ) ) == "cancelled"
      RETURN "interrupted"
   ENDIF
   IF hb_HGetDef( hRes, "success", .F. )
      RETURN "success"
   ENDIF
   RETURN "error"

// Best-effort total-token extraction from an agent result hash. Returns
// 0 when the turn errored before the model returned a usage block.
STATIC FUNCTION CCREPL_TurnTokens( hRes )
   LOCAL hU
   IF ValType( hRes ) != "H" .OR. !hb_HHasKey( hRes, "usage" )
      RETURN 0
   ENDIF
   hU := hRes[ "usage" ]
   IF ValType( hU ) != "H"
      RETURN 0
   ENDIF
   RETURN hb_HGetDef( hU, "prompt_tokens", 0 ) + ;
          hb_HGetDef( hU, "completion_tokens", 0 )
```

- [ ] **Step 5.4: Build + smoke test**

Use the existing Windows build (build_cc.bat will rebuild ccrepl.prg + link cchooks.prg after Task 8; for now, the test build below is sufficient to verify it compiles in the test linkage):
```cmd
cd c:\CCHarbour\tests
"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp
.\run_tests.exe
```
Expected: builds clean, all previous tests still PASS. (No new test exercises this yet — Task 8 covers the full main-build smoke.)

- [ ] **Step 5.5: Commit**

```cmd
git add src/ccrepl.prg
git commit -m "feat(repl): fire turn_complete hook after each RunTurn

CCREPL_RunTurn calls CCHOOKS_Run('turn_complete', ...) with status,
model, tokens, and duration_ms once the turn settles. Adds two
STATIC helpers (CCREPL_TurnStatus / CCREPL_TurnTokens) to derive the
status string and total-token count from the agent result hash."
```

---

### Task 6: `/hook` command parser in `ccui.prg`

**Files:**
- Modify: `src/ccui.prg` (CCUI_ParseCommand, lines 7-56)
- Modify: `tests/test_ui.prg` (assume exists; if not, append to `Test_UI`)

- [ ] **Step 6.1: Locate the existing `CCUI_ParseCommand` cases**

The switch ends at line 54 (after the `/btw` block) and falls through to the default `message` return at line 56.

- [ ] **Step 6.2: Add the `/hook` case**

Insert just before the `/btw` block (around line 48):
```harbour
   CASE cLow == "/hook" .OR. Left( cLow, 6 ) == "/hook "
      RETURN { "type" => "hook", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
```

- [ ] **Step 6.3: Add parser tests**

In `tests/test_ui.prg` find `Test_UI` and append:
```harbour
   // /hook parser
   T_Equal( CCUI_ParseCommand( "/hook" )[ "type" ], "hook", ;
           "ui: /hook parsed as hook type" )
   T_Equal( CCUI_ParseCommand( "/hook" )[ "text" ], "", ;
           "ui: /hook (bare) text empty" )
   T_Equal( CCUI_ParseCommand( "/hook list" )[ "type" ], "hook", ;
           "ui: /hook list parsed as hook type" )
   T_Equal( CCUI_ParseCommand( "/hook add turn_complete echo hi" )[ "text" ], ;
           "add turn_complete echo hi", ;
           "ui: /hook strips prefix, keeps rest verbatim" )
```

- [ ] **Step 6.4: Run tests**

```cmd
cd c:\CCHarbour\tests
"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp
.\run_tests.exe
```
Expected: 4 new `ui:` tests PASS.

- [ ] **Step 6.5: Commit**

```cmd
git add src/ccui.prg tests/test_ui.prg
git commit -m "feat(ui): parse /hook into a hook action

CCUI_ParseCommand maps /hook (and /hook <subcommand...>) to
{ type=>'hook', text=><rest> }, leaving subcommand parsing to the
REPL handler."
```

---

### Task 7: `CCREPL_HandleHook` + dispatch

**Files:**
- Modify: `src/ccrepl.prg` (action switch around line 258, plus new handler near `CCREPL_HandleProvider` at line 429)
- Modify: `tests/test_hooks.prg` (append within `Test_Hooks`)

- [ ] **Step 7.1: Append handler tests to `Test_Hooks`**

```harbour
   // Handler: list with no hooks renders an empty block (just header)
   LOCAL cTmpDir3 := hb_DirTemp() + "ccharbour_handler_test"
   hb_DirBuild( cTmpDir3 )
   hb_cwd( cTmpDir3 )
   hb_DirBuild( ".ccharbour" )
   hb_MemoWrit( ".ccharbour" + hb_ps() + "settings.json", "{}" )
   LOCAL cOut := CCREPL_HandleHookForTest( "list" )
   T_Assert( "turn_complete" $ cOut, ;
            "hooks-handler: list output names the event" )
   T_Assert( "(none)" $ cOut .OR. "no hooks" $ Lower( cOut ), ;
            "hooks-handler: list shows empty marker" )

   // Handler: add valid event persists to settings.json
   cOut := CCREPL_HandleHookForTest( "add turn_complete echo persisted" )
   T_Assert( "echo persisted" $ ;
             hb_MemoRead( ".ccharbour" + hb_ps() + "settings.json" ), ;
            "hooks-handler: add persists cmd to settings.json" )

   // Handler: add unknown event yields error containing valid event list
   cOut := CCREPL_HandleHookForTest( "add foo bar" )
   T_Assert( "foo" $ cOut .AND. "turn_complete" $ cOut, ;
            "hooks-handler: add unknown event lists valid events" )

   // Handler: remove valid idx pops the entry
   cOut := CCREPL_HandleHookForTest( "remove turn_complete 1" )
   T_Assert( !( "echo persisted" $ ;
                hb_MemoRead( ".ccharbour" + hb_ps() + "settings.json" ) ), ;
            "hooks-handler: remove drops the entry" )

   // Handler: edit valid idx swaps the cmd
   CCREPL_HandleHookForTest( "add turn_complete echo before" )
   CCREPL_HandleHookForTest( "edit turn_complete 1 echo after" )
   T_Assert( "echo after" $ ;
             hb_MemoRead( ".ccharbour" + hb_ps() + "settings.json" ), ;
            "hooks-handler: edit swaps the cmd" )

   // Handler: log subcommand with hooks_log off prints the disabled hint
   cOut := CCREPL_HandleHookForTest( "log" )
   T_Assert( "disabled" $ Lower( cOut ), ;
            "hooks-handler: log subcommand hints when disabled" )

   // Handler: test subcommand dispatches CCHOOKS_Run with dummy env
   FErase( cTmpDir3 + hb_ps() + "marker_t.txt" )
   IF hb_OsIsWin()
      cCmd := "cmd /c echo %CCHARBOUR_STATUS% > " + cTmpDir3 + hb_ps() + ;
              "marker_t.txt"
   ELSE
      cCmd := "sh -c 'echo $CCHARBOUR_STATUS > " + cTmpDir3 + hb_ps() + ;
              "marker_t.txt'"
   ENDIF
   CCREPL_HandleHookForTest( "remove turn_complete 1" )
   CCREPL_HandleHookForTest( "add turn_complete " + cCmd )
   cOut := CCREPL_HandleHookForTest( "test turn_complete" )
   nDeadline := hb_MilliSeconds() + 2000
   DO WHILE !hb_FileExists( cTmpDir3 + hb_ps() + "marker_t.txt" ) .AND. ;
            hb_MilliSeconds() < nDeadline
      hb_idleSleep( 0.05 )
   ENDDO
   T_Assert( hb_FileExists( cTmpDir3 + hb_ps() + "marker_t.txt" ), ;
            "hooks-handler: test fires the hook" )
   T_Assert( "success" $ ;
             hb_MemoRead( cTmpDir3 + hb_ps() + "marker_t.txt" ), ;
            "hooks-handler: test passes status=success" )

   // Cleanup
   FErase( ".ccharbour" + hb_ps() + "settings.json" )
   FErase( cTmpDir3 + hb_ps() + "marker_t.txt" )
   hb_cwd( cOldCwd )
```

The tests reference `CCREPL_HandleHookForTest`, a thin testing seam that returns the rendered output instead of writing to the live REPL (so we can assert on it). It will be added together with `CCREPL_HandleHook`.

- [ ] **Step 7.2: Add the dispatcher case to the action switch**

In `src/ccrepl.prg` around line 277-279 (next to the `"rewind"` case), add:
```harbour
      CASE hAction[ "type" ] == "hook"
         CCREPL_HandleHook( hAction[ "text" ], oPrompt )
```

- [ ] **Step 7.3: Add `CCREPL_HandleHook` and `CCREPL_HandleHookForTest`**

Place these just after `CCREPL_HandleProvider` (after its closing `RETURN`, around line 550). Implementation:
```harbour
// Implements /hook — CRUD + test/log for the hooks system.
// Usage:
//   /hook                          list all hooks per event
//   /hook list [event]             same (optional filter)
//   /hook add <event> <cmd...>     append a hook to the event
//   /hook remove <event> <idx>     remove the 1-based idx-th entry
//   /hook edit <event> <idx> <cmd> replace the idx-th entry
//   /hook test <event>             fire with dummy env (debug helper)
//   /hook log                      tail last 20 log lines or print hint
STATIC FUNCTION CCREPL_HandleHook( cArg, oPrompt )
   LOCAL cOut := CCREPL_HookRender( cArg )
   CCREPL_Out( cOut )
   IF oPrompt != NIL
      CCPROMPT_Redraw( oPrompt )
   ENDIF
   RETURN NIL

// Same as CCREPL_HandleHook but returns the rendered text instead of
// writing it to the REPL. Used by tests.
FUNCTION CCREPL_HandleHookForTest( cArg )
   RETURN CCREPL_HookRender( cArg )

// Pure-ish renderer: takes the raw /hook arg and returns the output
// the REPL should display. Handles all subcommands.
STATIC FUNCTION CCREPL_HookRender( cArg )
   LOCAL cSub, cRest, cOut := "", hSet, aHooks, i, cEvent
   LOCAL nIdx, cCmd, nSpace, cLog
   cArg := AllTrim( hb_CStr( cArg ) )
   nSpace := At( " ", cArg )
   IF nSpace > 0
      cSub  := Lower( Left( cArg, nSpace - 1 ) )
      cRest := AllTrim( SubStr( cArg, nSpace + 1 ) )
   ELSE
      cSub  := Lower( cArg )
      cRest := ""
   ENDIF
   IF Empty( cSub )
      cSub := "list"
   ENDIF
   hSet := CCSETTINGS_Load()
   DO CASE
   CASE cSub == "list"
      cOut += "Hooks:" + Chr(10)
      FOR EACH cEvent IN CCHOOKS_ValidEvents()
         IF !Empty( cRest ) .AND. cRest != cEvent
            LOOP
         ENDIF
         aHooks := CCHOOKS_List( hSet, cEvent )
         cOut += "  " + cEvent + ":" + Chr(10)
         IF Len( aHooks ) == 0
            cOut += "    (none)" + Chr(10)
         ELSE
            FOR i := 1 TO Len( aHooks )
               cOut += "    " + LTrim( Str( i ) ) + ". " + aHooks[ i ] + Chr(10)
            NEXT
         ENDIF
      NEXT
   CASE cSub == "add"
      nSpace := At( " ", cRest )
      IF nSpace == 0
         RETURN "usage: /hook add <event> <cmd>" + Chr(10)
      ENDIF
      cEvent := Lower( Left( cRest, nSpace - 1 ) )
      cCmd   := AllTrim( SubStr( cRest, nSpace + 1 ) )
      IF Empty( cCmd )
         RETURN "error: command empty" + Chr(10)
      ENDIF
      IF !CCHOOKS_IsValidEvent( cEvent )
         RETURN "error: unknown event '" + cEvent + ;
                "'. Valid: " + CCREPL_HookEventList() + Chr(10)
      ENDIF
      CCHOOKS_Add( hSet, cEvent, cCmd )
      CCSETTINGS_Save( hSet )
      cOut := "[hook added -> " + cEvent + ": " + cCmd + "]" + Chr(10)
   CASE cSub == "remove"
      nSpace := At( " ", cRest )
      IF nSpace == 0
         RETURN "usage: /hook remove <event> <idx>" + Chr(10)
      ENDIF
      cEvent := Lower( Left( cRest, nSpace - 1 ) )
      nIdx   := Val( AllTrim( SubStr( cRest, nSpace + 1 ) ) )
      IF !CCHOOKS_IsValidEvent( cEvent )
         RETURN "error: unknown event '" + cEvent + ;
                "'. Valid: " + CCREPL_HookEventList() + Chr(10)
      ENDIF
      aHooks := CCHOOKS_List( hSet, cEvent )
      IF nIdx < 1 .OR. nIdx > Len( aHooks )
         RETURN "error: index " + LTrim( Str( nIdx ) ) + ;
                " out of range (1.." + LTrim( Str( Len( aHooks ) ) ) + ")" + Chr(10)
      ENDIF
      CCHOOKS_Remove( hSet, cEvent, nIdx )
      CCSETTINGS_Save( hSet )
      cOut := "[hook removed -> " + cEvent + " #" + LTrim( Str( nIdx ) ) + "]" + Chr(10)
   CASE cSub == "edit"
      nSpace := At( " ", cRest )
      IF nSpace == 0
         RETURN "usage: /hook edit <event> <idx> <cmd>" + Chr(10)
      ENDIF
      cEvent := Lower( Left( cRest, nSpace - 1 ) )
      cRest  := AllTrim( SubStr( cRest, nSpace + 1 ) )
      nSpace := At( " ", cRest )
      IF nSpace == 0
         RETURN "usage: /hook edit <event> <idx> <cmd>" + Chr(10)
      ENDIF
      nIdx := Val( Left( cRest, nSpace - 1 ) )
      cCmd := AllTrim( SubStr( cRest, nSpace + 1 ) )
      IF Empty( cCmd )
         RETURN "error: command empty" + Chr(10)
      ENDIF
      IF !CCHOOKS_IsValidEvent( cEvent )
         RETURN "error: unknown event '" + cEvent + ;
                "'. Valid: " + CCREPL_HookEventList() + Chr(10)
      ENDIF
      aHooks := CCHOOKS_List( hSet, cEvent )
      IF nIdx < 1 .OR. nIdx > Len( aHooks )
         RETURN "error: index " + LTrim( Str( nIdx ) ) + ;
                " out of range (1.." + LTrim( Str( Len( aHooks ) ) ) + ")" + Chr(10)
      ENDIF
      CCHOOKS_Edit( hSet, cEvent, nIdx, cCmd )
      CCSETTINGS_Save( hSet )
      cOut := "[hook edited -> " + cEvent + " #" + LTrim( Str( nIdx ) ) + ": " + ;
              cCmd + "]" + Chr(10)
   CASE cSub == "test"
      cEvent := iif( Empty( cRest ), "turn_complete", Lower( cRest ) )
      IF !CCHOOKS_IsValidEvent( cEvent )
         RETURN "error: unknown event '" + cEvent + ;
                "'. Valid: " + CCREPL_HookEventList() + Chr(10)
      ENDIF
      CCHOOKS_Run( cEvent, { "status" => "success", ;
         "model" => "test", "tokens" => 0, "duration_ms" => 0 } )
      cOut := "[fired " + LTrim( Str( Len( CCHOOKS_List( hSet, cEvent ) ) ) ) + ;
              " hook(s) -- check log if hooks_log enabled]" + Chr(10)
   CASE cSub == "log"
      IF !hb_HGetDef( hSet, "hooks_log", .F. )
         RETURN "[hooks_log disabled -- set \"hooks_log\": true in " + ;
                ".ccharbour" + hb_ps() + "settings.json]" + Chr(10)
      ENDIF
      cOut := "[log: " + CCHOOKS_LogPath() + "]" + Chr(10)
      IF hb_FileExists( CCHOOKS_LogPath() )
         cLog := hb_MemoRead( CCHOOKS_LogPath() )
         // Tail last 20 lines.
         LOCAL aLines := hb_ATokens( cLog, Chr(10) )
         LOCAL nStart := Max( 1, Len( aLines ) - 19 )
         FOR i := nStart TO Len( aLines )
            IF !Empty( aLines[ i ] )
               cOut += "  " + aLines[ i ] + Chr(10)
            ENDIF
         NEXT
      ENDIF
   OTHERWISE
      RETURN "Unknown /hook subcommand. " + ;
             "Use: list | add | remove | edit | test | log" + Chr(10)
   ENDCASE
   RETURN cOut

// Comma-separated string of valid event names for error messages.
STATIC FUNCTION CCREPL_HookEventList()
   LOCAL aEv := CCHOOKS_ValidEvents(), cOut := "", i
   FOR i := 1 TO Len( aEv )
      cOut += aEv[ i ]
      IF i < Len( aEv )
         cOut += ", "
      ENDIF
   NEXT
   RETURN cOut
```

- [ ] **Step 7.4: Run tests, verify pass**

```cmd
cd c:\CCHarbour\tests
"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp
.\run_tests.exe
```
Expected: all new `hooks-handler:` tests PASS, all previous tests still PASS.

- [ ] **Step 7.5: Commit**

```cmd
git add src/ccrepl.prg tests/test_hooks.prg
git commit -m "feat(repl): /hook CRUD + test/log subcommands

Wire 'hook' action into the dispatch switch. CCREPL_HandleHook
delegates to a pure CCREPL_HookRender that returns the formatted
output, used in tests via CCREPL_HandleHookForTest. Subcommands:
list (default), add, remove, edit, test, log."
```

---

### Task 8: Register `cchooks.prg` in main builds + full build smoke

**Files:**
- Modify: `cc.hbp`
- Modify: `cc_linux.hbp`
- Modify: `cc_mac.hbp`

- [ ] **Step 8.1: Add `src/cchooks.prg` to `cc.hbp`**

After the `src/ccsettings.prg` line (line 23), insert:
```
src/cchooks.prg
```

- [ ] **Step 8.2: Mirror in `cc_linux.hbp` and `cc_mac.hbp`**

Same insertion point: right after `src/ccsettings.prg`.

- [ ] **Step 8.3: Full build (Windows)**

```cmd
cd c:\CCHarbour
.\build_cc.bat
```
Expected: clean build, produces `cc.exe`. No undefined-symbol errors for `CCHOOKS_*` or `CCREPL_HandleHook`.

- [ ] **Step 8.4: Smoke test the REPL**

Run `cc.exe` and try:
```
/hook
/hook add turn_complete powershell -c "[console]::beep(800,200)"
/hook
/hook test turn_complete
hello world
```
Expected:
- `/hook` lists `turn_complete: (none)` initially.
- After add, `/hook` lists the new command with index 1.
- `/hook test turn_complete` triggers the beep.
- A normal message turn also triggers the beep at completion.

- [ ] **Step 8.5: Commit**

```cmd
git add cc.hbp cc_linux.hbp cc_mac.hbp
git commit -m "build: register cchooks.prg in all three platform builds

Adds src/cchooks.prg to cc.hbp, cc_linux.hbp, and cc_mac.hbp so the
hooks module links into the main CCHarbour binary on every platform."
```

---

## Self-Review

**1. Spec coverage:**

| Spec section | Implemented in |
|---|---|
| `CCHOOKS_*` API surface | Tasks 2-4 |
| Settings shape (`hooks`, `hooks_log`) | Task 1 |
| Defaults | Task 1 |
| Env vars passed to hooks | Task 4 |
| `/hook` command surface (all 6 subcommands) | Tasks 6-7 |
| `turn_complete` fire integration | Task 5 |
| Status/tokens/duration extraction | Task 5 (helpers) |
| Error handling — runtime cases | Task 4 (try/recover in Run, no-op paths in List/Add/Remove/Edit) |
| Error handling — interactive `/hook` cases | Task 7 |
| Log format | Task 3 (timestamp prefix), Task 4 (event=/status=/cmd= lines) |
| Reload settings on every fire | Task 4 (`CCSETTINGS_Load()` inside `CCHOOKS_Run`) |
| Cross-platform spawn tests | Tasks 4 & 7 (Windows/POSIX branching) |
| Build registration | Task 8 |

No gaps.

**2. Placeholder scan:** None — every step ships actual code or commands.

**3. Type/name consistency:**
- `CCHOOKS_ValidEvents` returns an array, used as such in `CCHOOKS_IsValidEvent` (AScan), `CCREPL_HookEventList` (loop), and `CCREPL_HookRender` (FOR EACH).
- `CCHOOKS_Add/Remove/Edit` all take `(hSet, cEvent, ...)` in the same order.
- `hContext` keys (`status`/`model`/`tokens`/`duration_ms`) are read in `CCHOOKS_Run` with the exact spelling produced by `CCREPL_RunTurn`'s call site.
- `CCREPL_TurnStatus` / `CCREPL_TurnTokens` names match their use site in Task 5 step 5.2.
- `CCHOOKS_LogPath` / `CCHOOKS_Log` referenced consistently in handler `log` subcommand and in `CCHOOKS_Run`.

All clean.

# Tool System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Harbour tool system — a registry plus six builtin tools (`read`, `write`, `edit`, `glob`, `grep`, `shell`) — that produces the schema array and executor codeblock the agent loop (#2) consumes.

**Architecture:** A hash-based registry (`{ toolName => hTool }`) with no global state. `DSTools_Registry()` builds a fresh registry with all six builtins; `DSTools_Schemas()` and `DSTools_Executor()` turn it into the `hOpts["tools"]` array and `hOpts["tool_executor"]` codeblock of `DS_AgentRun`. Each tool is a record `{ name, description, parameters, handler }`; handlers catch their own errors and return strings — they never throw.

**Tech Stack:** Harbour (MT build, `hbmk2`, BCC), core `hb_jsonEncode`/`hb_jsonDecode`, `hb_DirScan`, `hb_regexComp`, `hb_processRun`. Reuses the #1/#2 test harness.

---

## Deviations from the spec

Two refinements decided during planning, both approved:

1. **`shell` has no `timeout` argument.** A correct hard timeout in single-threaded
   Harbour risks a pipe-buffer deadlock; `hb_processRun` drains output correctly
   but offers no timeout. Timeout enforcement is deferred to #4, where the loop
   runs on a cancellable background thread that can kill the child process —
   the same reasoning that deferred cancellation in #1. `shell` parameters are
   `{ command, shell? }`.
2. **The `shell` argument is the full launcher prefix.** Default `"cmd.exe /c"`.
   An override supplies the entire launcher (e.g. `"powershell -Command"`), so
   any interpreter works, not only `cmd`.

---

## File Structure

```
src/dstools.prg          Registry core: Registry, Register, Schemas, Executor
src/dstools_file.prg     read, write, edit tool definitions + handlers
src/dstools_search.prg   glob, grep tool definitions + handlers
src/dstools_shell.prg    shell tool definition + handler
tests/test_tools.prg     Tool system tests
tests/tests.hbp          (modified) add test_tools.prg + the 4 src files
tests/run_tests.prg      (modified) call Test_Tools() in Main()
```

Conventions (same as #1/#2): public functions are `FUNCTION`, private helpers
are `STATIC FUNCTION`. Hashes carry data. No public function throws an uncaught
exception.

The build runs from the `tests/` directory: `hbmk2 tests.hbp` produces
`tests/run_tests.exe`. The toolchain is not on PATH — prefix it:
`$env:PATH = 'C:\harbour\bin\win\bcc;C:\bcc77\bin;' + $env:PATH`.

Tests build JSON argument strings with `hb_jsonEncode` (never hand-written) so
Windows paths with backslashes are escaped correctly.

---

### Task 1: Scaffold — registry module and test file

**Files:**
- Create: `src/dstools.prg`
- Create: `tests/test_tools.prg`
- Modify: `tests/tests.hbp`
- Modify: `tests/run_tests.prg`

- [ ] **Step 1: Create the `dstools.prg` stub**

`src/dstools.prg`:

```harbour
FUNCTION DSTools_Registry()
   RETURN {=>}
```

- [ ] **Step 2: Create the `test_tools.prg` stub**

`tests/test_tools.prg`:

```harbour
FUNCTION Test_Tools()
   RETURN NIL
```

- [ ] **Step 3: Add both files to the build**

In `tests/tests.hbp`, add `test_tools.prg` after `test_agent.prg`, and
`../src/dstools.prg` after `../src/dsagent.prg`. The file becomes:

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
../src/dsconfig.prg
../src/dssse.prg
../src/dshttp.prg
../src/dsapi.prg
../src/dsagent.prg
../src/dstools.prg
```

- [ ] **Step 4: Call `Test_Tools()` from the runner**

In `tests/run_tests.prg`, add `Test_Tools()` to `Main()` after `Test_Agent()`:

```harbour
FUNCTION Main()
   Test_SSE()
   Test_Config()
   Test_Http()
   Test_Api()
   Test_Agent()
   Test_Tools()
   ? ""
   ? "pass: " + LTrim( Str( s_nPass ) ) + "   fail: " + LTrim( Str( s_nFail ) )
   ErrorLevel( iif( s_nFail > 0, 1, 0 ) )
   RETURN NIL
```

- [ ] **Step 5: Build and run**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: builds clean; output ends with `pass: 75   fail: 0` (the 75 existing
tests; `Test_Tools()` adds none yet); exit code 0.

- [ ] **Step 6: Commit**

```bash
git add src/dstools.prg tests/test_tools.prg tests/tests.hbp tests/run_tests.prg
git commit -m "chore: scaffold tool system module and test file"
```

---

### Task 2: Registry core — Register, Schemas, Executor

**Files:**
- Modify: `src/dstools.prg` (replace stub)
- Modify: `tests/test_tools.prg` (replace stub)

`DSTools_Registry()` stays empty in this task — builtin tools are registered by
Tasks 3–6. The registry, schema array, and executor are tested here with a
custom tool registered via `DSTools_Register`.

- [ ] **Step 1: Write the failing tests**

Replace the entire contents of `tests/test_tools.prg`:

```harbour
// Returns the schema entry for cName from an aSchemas array, or NIL.
STATIC FUNCTION FindSchema( aSchemas, cName )
   LOCAL h
   FOR EACH h IN aSchemas
      IF h[ "function" ][ "name" ] == cName
         RETURN h
      ENDIF
   NEXT
   RETURN NIL

FUNCTION Test_Tools()
   LOCAL oReg, bExec, aSchemas, hEcho, hCustom

   // a custom tool used to exercise the registry and executor
   hCustom := { "name" => "echo", ;
                "description" => "Echoes its text argument", ;
                "parameters" => { "type" => "object", ;
                   "properties" => { "text" => { "type" => "string" } }, ;
                   "required" => { "text" } }, ;
                "handler" => {| hArgs | "echo:" + hArgs[ "text" ] } }

   oReg := DSTools_Registry()
   T_Equal( ValType( oReg ), "H", "tools: registry is a hash" )
   DSTools_Register( oReg, hCustom )
   T_Equal( hb_HHasKey( oReg, "echo" ), .T., "tools: register adds tool" )

   // schemas expose the registered tool in OpenAI form
   aSchemas := DSTools_Schemas( oReg )
   hEcho := FindSchema( aSchemas, "echo" )
   T_Assert( hEcho != NIL, "tools: schema present for echo" )
   T_Equal( hEcho[ "type" ], "function", "tools: schema type" )
   T_Equal( hEcho[ "function" ][ "description" ], "Echoes its text argument", ;
            "tools: schema description" )
   T_Equal( ValType( hEcho[ "function" ][ "parameters" ] ), "H", ;
            "tools: schema parameters" )

   // the executor dispatches by name and parses JSON arguments
   bExec := DSTools_Executor( oReg )
   T_Equal( Eval( bExec, "echo", '{"text":"hi"}' ), "echo:hi", ;
            "tools: executor dispatches and parses args" )
   T_Equal( Eval( bExec, "nope", "{}" ), "Error: unknown tool 'nope'", ;
            "tools: executor unknown tool" )
   T_Equal( Eval( bExec, "echo", "not json" ), "Error: invalid arguments JSON", ;
            "tools: executor invalid JSON" )
   T_Equal( Eval( bExec, "echo", "{}" ), "Error: missing required argument 'text'", ;
            "tools: executor missing required arg" )
   RETURN NIL
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL / build error for the `tools:` tests — `DSTools_Register`,
`DSTools_Schemas`, `DSTools_Executor` are not defined. The 75 existing tests
still pass.

- [ ] **Step 3: Implement the registry core**

Replace the entire contents of `src/dstools.prg`:

```harbour
// Creates a fresh tool registry with all builtin tools registered.
// (Builtin registrations are added by Tasks 3-6.)
FUNCTION DSTools_Registry()
   LOCAL oReg := {=>}
   RETURN oReg

// Adds a tool record to the registry, keyed by its name.
// hTool: { name, description, parameters, handler }.
FUNCTION DSTools_Register( oReg, hTool )
   oReg[ hTool[ "name" ] ] := hTool
   RETURN oReg

// Returns the OpenAI "tools" array for every registered tool.
FUNCTION DSTools_Schemas( oReg )
   LOCAL aOut := {}, cKey, hTool
   FOR EACH cKey IN hb_HKeys( oReg )
      hTool := oReg[ cKey ]
      AAdd( aOut, { "type" => "function", ;
                    "function" => { "name" => hTool[ "name" ], ;
                                    "description" => hTool[ "description" ], ;
                                    "parameters" => hTool[ "parameters" ] } } )
   NEXT
   RETURN aOut

// Returns the executor codeblock { |cName,cArgsJson| -> cResultString }.
// It plugs straight into DS_AgentRun's hOpts["tool_executor"].
FUNCTION DSTools_Executor( oReg )
   RETURN {| cName, cArgsJson | DSTools_Dispatch( oReg, cName, cArgsJson ) }

// Looks up a tool, validates arguments, runs the handler under an error net.
STATIC FUNCTION DSTools_Dispatch( oReg, cName, cArgsJson )
   LOCAL hTool, xArgs, cReq, cResult, oErr
   IF !hb_HHasKey( oReg, cName )
      RETURN "Error: unknown tool '" + hb_CStr( cName ) + "'"
   ENDIF
   hTool := oReg[ cName ]
   xArgs := hb_jsonDecode( hb_CStr( cArgsJson ) )
   IF ValType( xArgs ) != "H"
      RETURN "Error: invalid arguments JSON"
   ENDIF
   IF hb_HHasKey( hTool[ "parameters" ], "required" )
      FOR EACH cReq IN hTool[ "parameters" ][ "required" ]
         IF !hb_HHasKey( xArgs, cReq )
            RETURN "Error: missing required argument '" + cReq + "'"
         ENDIF
      NEXT
   ENDIF
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      cResult := Eval( hTool[ "handler" ], xArgs )
   RECOVER USING oErr
      cResult := "Error: tool '" + cName + "' failed: " + ;
                 iif( ValType( oErr ) == "O", hb_CStr( oErr:Description ), "exception" )
   END SEQUENCE
   RETURN cResult
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `tools:` lines `ok`; the 75 existing tests still `ok`; exit
code 0.

- [ ] **Step 5: Commit**

```bash
git add src/dstools.prg tests/test_tools.prg
git commit -m "feat: tool registry — register, schemas, executor"
```

---

### Task 3: read tool

**Files:**
- Create: `src/dstools_file.prg`
- Modify: `src/dstools.prg` (register the tool)
- Modify: `tests/test_tools.prg`
- Modify: `tests/tests.hbp`

- [ ] **Step 1: Add the failing tests**

Append inside `Test_Tools()` in `tests/test_tools.prg`, before `RETURN NIL`:

```harbour
   // read tool
   bExec := DSTools_Executor( DSTools_Registry() )
   cTmp := hb_DirTemp() + "dstools_read.txt"
   hb_MemoWrit( cTmp, "alpha" + Chr(10) + "beta" + Chr(10) + "gamma" + Chr(10) )

   cRes := Eval( bExec, "read", hb_jsonEncode( { "path" => cTmp } ) )
   T_Assert( "alpha" $ cRes, "tools: read returns content" )
   T_Assert( Chr(9) $ cRes, "tools: read has line-number tab" )

   cRes := Eval( bExec, "read", ;
      hb_jsonEncode( { "path" => cTmp, "offset" => 2 } ) )
   T_Assert( "gamma" $ cRes, "tools: read offset keeps later lines" )
   T_Assert( !( "alpha" $ cRes ), "tools: read offset drops earlier lines" )

   cRes := Eval( bExec, "read", ;
      hb_jsonEncode( { "path" => cTmp, "max_lines" => 1 } ) )
   T_Assert( "[truncated:" $ cRes, "tools: read max_lines truncates" )

   cRes := Eval( bExec, "read", ;
      hb_jsonEncode( { "path" => hb_DirTemp() + "no_such_file.txt" } ) )
   T_Assert( "Error: file not found" $ cRes, "tools: read missing file" )
   FErase( cTmp )
```

Add `cTmp` and `cRes` to the `LOCAL` line of `Test_Tools()`:

```harbour
   LOCAL oReg, bExec, aSchemas, hEcho, hCustom, cTmp, cRes
```

- [ ] **Step 2: Add the test source file to the build**

In `tests/tests.hbp`, add `../src/dstools_file.prg` after `../src/dstools.prg`.

- [ ] **Step 3: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL / build error for the `read` `tools:` tests — `dstools_file.prg`
does not exist yet and `DSTool_Read` is undefined.

- [ ] **Step 4: Create `dstools_file.prg` with the read tool**

`src/dstools_file.prg`:

```harbour
// read: returns the line-numbered content of a text file.
FUNCTION DSTool_Read()
   RETURN { "name" => "read", ;
            "description" => "Read a text file from disk. Returns line-numbered content.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "path" => { "type" => "string", ;
                              "description" => "Path of the file to read" }, ;
                  "offset" => { "type" => "integer", ;
                                "description" => "Number of leading lines to skip" }, ;
                  "max_lines" => { "type" => "integer", ;
                                   "description" => "Maximum lines to return (default 2000)" } }, ;
               "required" => { "path" } }, ;
            "handler" => {| hArgs | DSTool_ReadRun( hArgs ) } }

STATIC FUNCTION DSTool_ReadRun( hArgs )
   LOCAL cPath, cText, aLines, nOffset, nMax, nFrom, nTo, i, cLine
   LOCAL cOut := "", nShown := 0
   cPath := hb_CStr( hArgs[ "path" ] )
   IF !hb_FileExists( cPath )
      RETURN "Error: file not found: " + cPath
   ENDIF
   cText  := hb_MemoRead( cPath )
   aLines := hb_ATokens( cText, Chr(10) )
   FOR i := 1 TO Len( aLines )
      aLines[ i ] := StrTran( aLines[ i ], Chr(13), "" )
   NEXT
   nOffset := iif( hb_HHasKey( hArgs, "offset" ) .AND. ;
                   ValType( hArgs[ "offset" ] ) == "N", Int( hArgs[ "offset" ] ), 0 )
   nMax    := iif( hb_HHasKey( hArgs, "max_lines" ) .AND. ;
                   ValType( hArgs[ "max_lines" ] ) == "N", Int( hArgs[ "max_lines" ] ), 2000 )
   nFrom := nOffset + 1
   nTo   := Min( Len( aLines ), nFrom + nMax - 1 )
   FOR i := nFrom TO nTo
      cLine := aLines[ i ]
      IF Len( cLine ) > 2000
         cLine := Left( cLine, 2000 ) + "..."
      ENDIF
      cOut += Str( i, 6 ) + Chr(9) + cLine + Chr(10)
      nShown++
   NEXT
   IF nTo < Len( aLines )
      cOut += "[truncated: " + LTrim( Str( Len( aLines ) - nTo ) ) + " more lines]" + Chr(10)
   ENDIF
   IF nShown == 0
      RETURN "(empty, or offset past end of file)"
   ENDIF
   RETURN cOut
```

- [ ] **Step 5: Register the read tool**

In `src/dstools.prg`, change `DSTools_Registry` to register the tool:

```harbour
FUNCTION DSTools_Registry()
   LOCAL oReg := {=>}
   DSTools_Register( oReg, DSTool_Read() )
   RETURN oReg
```

- [ ] **Step 6: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `tools:` lines `ok`; existing tests still `ok`; exit code 0.

- [ ] **Step 7: Commit**

```bash
git add src/dstools_file.prg src/dstools.prg tests/test_tools.prg tests/tests.hbp
git commit -m "feat: read tool"
```

---

### Task 4: write and edit tools

**Files:**
- Modify: `src/dstools_file.prg`
- Modify: `src/dstools.prg` (register the tools)
- Modify: `tests/test_tools.prg`

- [ ] **Step 1: Add the failing tests**

Append inside `Test_Tools()` in `tests/test_tools.prg`, before `RETURN NIL`:

```harbour
   // write tool
   bExec := DSTools_Executor( DSTools_Registry() )
   cTmp := hb_DirTemp() + "dstools_write.txt"
   FErase( cTmp )
   cRes := Eval( bExec, "write", ;
      hb_jsonEncode( { "path" => cTmp, "content" => "hello world" } ) )
   T_Assert( "Wrote" $ cRes, "tools: write reports success" )
   T_Equal( hb_MemoRead( cTmp ), "hello world", "tools: write content on disk" )

   // edit tool: unique replacement
   hb_MemoWrit( cTmp, "one two one" )
   cRes := Eval( bExec, "edit", hb_jsonEncode( { "path" => cTmp, ;
      "old_string" => "two", "new_string" => "TWO" } ) )
   T_Assert( "Edited" $ cRes, "tools: edit reports success" )
   T_Equal( hb_MemoRead( cTmp ), "one TWO one", "tools: edit applied" )

   // edit tool: non-unique target without replace_all -> error
   hb_MemoWrit( cTmp, "x x x" )
   cRes := Eval( bExec, "edit", hb_jsonEncode( { "path" => cTmp, ;
      "old_string" => "x", "new_string" => "y" } ) )
   T_Assert( "not unique" $ cRes, "tools: edit non-unique error" )

   // edit tool: replace_all
   cRes := Eval( bExec, "edit", hb_jsonEncode( { "path" => cTmp, ;
      "old_string" => "x", "new_string" => "y", "replace_all" => .T. } ) )
   T_Equal( hb_MemoRead( cTmp ), "y y y", "tools: edit replace_all" )

   // edit tool: missing file -> error
   cRes := Eval( bExec, "edit", hb_jsonEncode( { ;
      "path" => hb_DirTemp() + "no_such_edit.txt", ;
      "old_string" => "a", "new_string" => "b" } ) )
   T_Assert( "Error: file not found" $ cRes, "tools: edit missing file" )
   FErase( cTmp )
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL / build error — `DSTool_Write` and `DSTool_Edit` are undefined.

- [ ] **Step 3: Append the write and edit tools to `dstools_file.prg`**

Append to `src/dstools_file.prg`:

```harbour
// write: writes content to a file, overwriting, creating parent directories.
FUNCTION DSTool_Write()
   RETURN { "name" => "write", ;
            "description" => "Write text content to a file, overwriting it.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "path" => { "type" => "string", ;
                              "description" => "Path of the file to write" }, ;
                  "content" => { "type" => "string", ;
                                 "description" => "Content to write" } }, ;
               "required" => { "path", "content" } }, ;
            "handler" => {| hArgs | DSTool_WriteRun( hArgs ) } }

STATIC FUNCTION DSTool_WriteRun( hArgs )
   LOCAL cPath, cContent, cDir
   cPath    := hb_CStr( hArgs[ "path" ] )
   cContent := hb_CStr( hArgs[ "content" ] )
   cDir     := hb_FNameDir( cPath )
   IF !Empty( cDir ) .AND. !hb_DirExists( cDir )
      hb_DirBuild( cDir )
   ENDIF
   IF !hb_MemoWrit( cPath, cContent )
      RETURN "Error: cannot write " + cPath
   ENDIF
   RETURN "Wrote " + LTrim( Str( hb_BLen( cContent ) ) ) + " bytes to " + cPath

// edit: replaces an exact string in a file.
FUNCTION DSTool_Edit()
   RETURN { "name" => "edit", ;
            "description" => "Replace an exact string in a file. old_string must be unique unless replace_all is set.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "path" => { "type" => "string", ;
                              "description" => "Path of the file to edit" }, ;
                  "old_string" => { "type" => "string", ;
                                    "description" => "Exact text to replace" }, ;
                  "new_string" => { "type" => "string", ;
                                    "description" => "Replacement text" }, ;
                  "replace_all" => { "type" => "boolean", ;
                                     "description" => "Replace every occurrence" } }, ;
               "required" => { "path", "old_string", "new_string" } }, ;
            "handler" => {| hArgs | DSTool_EditRun( hArgs ) } }

STATIC FUNCTION DSTool_EditRun( hArgs )
   LOCAL cPath, cOld, cNew, lAll, cText, nCount
   cPath := hb_CStr( hArgs[ "path" ] )
   cOld  := hb_CStr( hArgs[ "old_string" ] )
   cNew  := hb_CStr( hArgs[ "new_string" ] )
   lAll  := hb_HHasKey( hArgs, "replace_all" ) .AND. hArgs[ "replace_all" ] == .T.
   IF !hb_FileExists( cPath )
      RETURN "Error: file not found: " + cPath
   ENDIF
   cText  := hb_MemoRead( cPath )
   nCount := DSTool_CountSub( cText, cOld )
   IF nCount == 0
      RETURN "Error: old_string not found in " + cPath
   ENDIF
   IF nCount > 1 .AND. !lAll
      RETURN "Error: old_string not unique (" + LTrim( Str( nCount ) ) + ;
             " matches); set replace_all or add context"
   ENDIF
   IF lAll
      cText := StrTran( cText, cOld, cNew )
   ELSE
      cText := StrTran( cText, cOld, cNew, 1, 1 )
   ENDIF
   IF !hb_MemoWrit( cPath, cText )
      RETURN "Error: cannot write " + cPath
   ENDIF
   RETURN "Edited " + cPath + " (" + LTrim( Str( iif( lAll, nCount, 1 ) ) ) + ;
          " replacement(s))"

// Counts non-overlapping occurrences of cSub in cText.
STATIC FUNCTION DSTool_CountSub( cText, cSub )
   LOCAL nCount := 0, nPos := 1, nFound
   IF Empty( cSub )
      RETURN 0
   ENDIF
   DO WHILE ( nFound := hb_At( cSub, cText, nPos ) ) > 0
      nCount++
      nPos := nFound + Len( cSub )
   ENDDO
   RETURN nCount
```

- [ ] **Step 4: Register the write and edit tools**

In `src/dstools.prg`, extend `DSTools_Registry`:

```harbour
FUNCTION DSTools_Registry()
   LOCAL oReg := {=>}
   DSTools_Register( oReg, DSTool_Read() )
   DSTools_Register( oReg, DSTool_Write() )
   DSTools_Register( oReg, DSTool_Edit() )
   RETURN oReg
```

- [ ] **Step 5: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `tools:` lines `ok`; existing tests still `ok`; exit code 0.

- [ ] **Step 6: Commit**

```bash
git add src/dstools_file.prg src/dstools.prg tests/test_tools.prg
git commit -m "feat: write and edit tools"
```

---

### Task 5: glob and grep tools

**Files:**
- Create: `src/dstools_search.prg`
- Modify: `src/dstools.prg` (register the tools)
- Modify: `tests/test_tools.prg`
- Modify: `tests/tests.hbp`

- [ ] **Step 1: Add the failing tests**

Append inside `Test_Tools()` in `tests/test_tools.prg`, before `RETURN NIL`:

```harbour
   // glob + grep tools: build a small temp directory tree
   bExec := DSTools_Executor( DSTools_Registry() )
   cTmpDir := hb_DirTemp() + "dstools_search"
   hb_DirBuild( cTmpDir )
   hb_MemoWrit( cTmpDir + hb_ps() + "a.txt", "needle here" + Chr(10) + "plain line" + Chr(10) )
   hb_MemoWrit( cTmpDir + hb_ps() + "b.txt", "another needle" + Chr(10) )
   hb_MemoWrit( cTmpDir + hb_ps() + "c.log", "needle in log" + Chr(10) )

   // glob: match *.txt
   cRes := Eval( bExec, "glob", ;
      hb_jsonEncode( { "pattern" => "*.txt", "path" => cTmpDir } ) )
   T_Assert( "a.txt" $ cRes, "tools: glob finds a.txt" )
   T_Assert( "b.txt" $ cRes, "tools: glob finds b.txt" )
   T_Assert( !( "c.log" $ cRes ), "tools: glob respects the mask" )

   // glob: no matches
   cRes := Eval( bExec, "glob", ;
      hb_jsonEncode( { "pattern" => "*.xyz", "path" => cTmpDir } ) )
   T_Assert( "No matches" $ cRes, "tools: glob no matches" )

   // grep: pattern across files
   cRes := Eval( bExec, "grep", ;
      hb_jsonEncode( { "pattern" => "needle", "path" => cTmpDir } ) )
   T_Assert( "a.txt:1:" $ cRes, "tools: grep reports file:line" )
   T_Assert( "needle in log" $ cRes, "tools: grep scans all files by default" )

   // grep: glob filter restricts scanned files
   cRes := Eval( bExec, "grep", hb_jsonEncode( { "pattern" => "needle", ;
      "path" => cTmpDir, "glob" => "*.log" } ) )
   T_Assert( "needle in log" $ cRes, "tools: grep glob filter keeps matches" )
   T_Assert( !( "a.txt" $ cRes ), "tools: grep glob filter excludes others" )

   // grep: invalid regex -> error
   cRes := Eval( bExec, "grep", hb_jsonEncode( { "pattern" => "[unclosed", ;
      "path" => cTmpDir } ) )
   T_Assert( "Error: invalid regex" $ cRes, "tools: grep invalid regex" )

   FErase( cTmpDir + hb_ps() + "a.txt" )
   FErase( cTmpDir + hb_ps() + "b.txt" )
   FErase( cTmpDir + hb_ps() + "c.log" )
   hb_DirDelete( cTmpDir )
```

Add `cTmpDir` to the `LOCAL` line of `Test_Tools()`:

```harbour
   LOCAL oReg, bExec, aSchemas, hEcho, hCustom, cTmp, cRes, cTmpDir
```

- [ ] **Step 2: Add the test source file to the build**

In `tests/tests.hbp`, add `../src/dstools_search.prg` after
`../src/dstools_file.prg`.

- [ ] **Step 3: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL / build error — `dstools_search.prg` does not exist and
`DSTool_Glob` / `DSTool_Grep` are undefined.

- [ ] **Step 4: Create `dstools_search.prg`**

`src/dstools_search.prg`:

```harbour
// glob: lists files matching a filename mask under a directory, recursively.
FUNCTION DSTool_Glob()
   RETURN { "name" => "glob", ;
            "description" => "List files matching a filename pattern (e.g. *.prg) under a directory, recursively.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "pattern" => { "type" => "string", ;
                                 "description" => "Filename mask, e.g. *.prg or **/*.txt" }, ;
                  "path" => { "type" => "string", ;
                              "description" => "Root directory to search (default current directory)" } }, ;
               "required" => { "pattern" } }, ;
            "handler" => {| hArgs | DSTool_GlobRun( hArgs ) } }

STATIC FUNCTION DSTool_GlobRun( hArgs )
   LOCAL cPattern, cPath, cMask, aFiles, a1, cOut := "", nShown := 0
   LOCAL nCap := 200
   cPattern := hb_CStr( hArgs[ "pattern" ] )
   cPath := iif( hb_HHasKey( hArgs, "path" ) .AND. !Empty( hArgs[ "path" ] ), ;
                 hb_CStr( hArgs[ "path" ] ), "." )
   IF !hb_DirExists( cPath )
      RETURN "Error: directory not found: " + cPath
   ENDIF
   // accept "**/mask" or "dir/mask" — the last path segment is the file mask
   cMask := cPattern
   IF "/" $ cMask
      cMask := SubStr( cMask, RAt( "/", cMask ) + 1 )
   ENDIF
   IF "\" $ cMask
      cMask := SubStr( cMask, RAt( "\", cMask ) + 1 )
   ENDIF
   aFiles := hb_DirScan( cPath, cMask )
   FOR EACH a1 IN aFiles
      IF "D" $ a1[ 5 ]
         LOOP
      ENDIF
      IF nShown >= nCap
         cOut += "[truncated: more matches]" + Chr(10)
         EXIT
      ENDIF
      cOut += a1[ 1 ] + Chr(10)
      nShown++
   NEXT
   IF nShown == 0
      RETURN "No matches for " + cPattern
   ENDIF
   RETURN cOut

// grep: searches file contents with a regular expression.
FUNCTION DSTool_Grep()
   RETURN { "name" => "grep", ;
            "description" => "Search file contents with a regular expression. Returns file:line:text matches.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "pattern" => { "type" => "string", ;
                                 "description" => "Regular expression to search for" }, ;
                  "path" => { "type" => "string", ;
                              "description" => "Root directory to search (default current directory)" }, ;
                  "glob" => { "type" => "string", ;
                              "description" => "Filename mask filtering which files are scanned" } }, ;
               "required" => { "pattern" } }, ;
            "handler" => {| hArgs | DSTool_GrepRun( hArgs ) } }

STATIC FUNCTION DSTool_GrepRun( hArgs )
   LOCAL cPattern, cPath, cGlob, pRegex, aFiles, a1, cFile, cText, aLines, i
   LOCAL cOut := "", nShown := 0, nCap := 200
   cPattern := hb_CStr( hArgs[ "pattern" ] )
   cPath := iif( hb_HHasKey( hArgs, "path" ) .AND. !Empty( hArgs[ "path" ] ), ;
                 hb_CStr( hArgs[ "path" ] ), "." )
   cGlob := iif( hb_HHasKey( hArgs, "glob" ) .AND. !Empty( hArgs[ "glob" ] ), ;
                 hb_CStr( hArgs[ "glob" ] ), "*" )
   IF !hb_DirExists( cPath )
      RETURN "Error: path not found: " + cPath
   ENDIF
   pRegex := hb_regexComp( cPattern )
   IF pRegex == NIL
      RETURN "Error: invalid regex: " + cPattern
   ENDIF
   aFiles := hb_DirScan( cPath, cGlob )
   FOR EACH a1 IN aFiles
      IF "D" $ a1[ 5 ]
         LOOP
      ENDIF
      cFile  := cPath + hb_ps() + a1[ 1 ]
      cText  := hb_MemoRead( cFile )
      aLines := hb_ATokens( cText, Chr(10) )
      FOR i := 1 TO Len( aLines )
         IF hb_regexHas( pRegex, aLines[ i ] )
            IF nShown >= nCap
               cOut += "[truncated: more matches]" + Chr(10)
               RETURN cOut
            ENDIF
            cOut += a1[ 1 ] + ":" + LTrim( Str( i ) ) + ":" + ;
                    StrTran( aLines[ i ], Chr(13), "" ) + Chr(10)
            nShown++
         ENDIF
      NEXT
   NEXT
   IF nShown == 0
      RETURN "No matches for " + cPattern
   ENDIF
   RETURN cOut
```

- [ ] **Step 5: Register the glob and grep tools**

In `src/dstools.prg`, extend `DSTools_Registry`:

```harbour
FUNCTION DSTools_Registry()
   LOCAL oReg := {=>}
   DSTools_Register( oReg, DSTool_Read() )
   DSTools_Register( oReg, DSTool_Write() )
   DSTools_Register( oReg, DSTool_Edit() )
   DSTools_Register( oReg, DSTool_Glob() )
   DSTools_Register( oReg, DSTool_Grep() )
   RETURN oReg
```

- [ ] **Step 6: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `tools:` lines `ok`; existing tests still `ok`; exit code 0.

- [ ] **Step 7: Commit**

```bash
git add src/dstools_search.prg src/dstools.prg tests/test_tools.prg tests/tests.hbp
git commit -m "feat: glob and grep tools"
```

---

### Task 6: shell tool and end-to-end check

**Files:**
- Create: `src/dstools_shell.prg`
- Modify: `src/dstools.prg` (register the tool)
- Modify: `tests/test_tools.prg`
- Modify: `tests/tests.hbp`

- [ ] **Step 1: Add the failing tests**

Append inside `Test_Tools()` in `tests/test_tools.prg`, before `RETURN NIL`:

```harbour
   // shell tool
   bExec := DSTools_Executor( DSTools_Registry() )
   cRes := Eval( bExec, "shell", hb_jsonEncode( { "command" => "echo hello" } ) )
   T_Assert( "hello" $ cRes, "tools: shell captures output" )
   T_Assert( "[exit code: 0]" $ cRes, "tools: shell reports exit 0" )

   cRes := Eval( bExec, "shell", hb_jsonEncode( { "command" => "exit 3" } ) )
   T_Assert( "[exit code: 3]" $ cRes, "tools: shell reports non-zero exit" )

   // end-to-end: the default registry exposes all six builtin tools
   aSchemas := DSTools_Schemas( DSTools_Registry() )
   T_Equal( Len( aSchemas ), 6, "tools: registry has six builtins" )
   T_Assert( FindSchema( aSchemas, "read" )  != NIL, "tools: builtin read" )
   T_Assert( FindSchema( aSchemas, "write" ) != NIL, "tools: builtin write" )
   T_Assert( FindSchema( aSchemas, "edit" )  != NIL, "tools: builtin edit" )
   T_Assert( FindSchema( aSchemas, "glob" )  != NIL, "tools: builtin glob" )
   T_Assert( FindSchema( aSchemas, "grep" )  != NIL, "tools: builtin grep" )
   T_Assert( FindSchema( aSchemas, "shell" ) != NIL, "tools: builtin shell" )
```

- [ ] **Step 2: Add the test source file to the build**

In `tests/tests.hbp`, add `../src/dstools_shell.prg` after
`../src/dstools_search.prg`.

- [ ] **Step 3: Run the tests to verify they fail**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL / build error — `dstools_shell.prg` does not exist and
`DSTool_Shell` is undefined. The "six builtins" test fails (only five
registered).

- [ ] **Step 4: Create `dstools_shell.prg`**

`src/dstools_shell.prg`:

```harbour
// shell: runs a command through a launcher and returns combined output.
// The "shell" argument is the full launcher prefix; default "cmd.exe /c".
// No timeout: a hard timeout requires the cancellable background-thread model
// introduced in sub-project #4.
FUNCTION DSTool_Shell()
   RETURN { "name" => "shell", ;
            "description" => "Run a shell command and return its combined output and exit code.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "command" => { "type" => "string", ;
                                 "description" => "Command line to run" }, ;
                  "shell" => { "type" => "string", ;
                               "description" => "Launcher prefix (default 'cmd.exe /c')" } }, ;
               "required" => { "command" } }, ;
            "handler" => {| hArgs | DSTool_ShellRun( hArgs ) } }

STATIC FUNCTION DSTool_ShellRun( hArgs )
   LOCAL cCommand, cShell, cCmdLine, cOut := "", cErr := "", nExit, cResult
   cCommand := hb_CStr( hArgs[ "command" ] )
   cShell := iif( hb_HHasKey( hArgs, "shell" ) .AND. !Empty( hArgs[ "shell" ] ), ;
                  hb_CStr( hArgs[ "shell" ] ), "cmd.exe /c" )
   cCmdLine := cShell + " " + cCommand
   nExit := hb_processRun( cCmdLine, , @cOut, @cErr )
   IF nExit == -1
      RETURN "Error: cannot run shell: " + cCmdLine
   ENDIF
   cResult := cOut
   IF !Empty( cErr )
      cResult += cErr
   ENDIF
   IF hb_BLen( cResult ) > 30000
      cResult := hb_BLeft( cResult, 30000 ) + Chr(10) + "[output truncated]" + Chr(10)
   ENDIF
   IF !Empty( cResult ) .AND. !( Right( cResult, 1 ) == Chr(10) )
      cResult += Chr(10)
   ENDIF
   cResult += "[exit code: " + LTrim( Str( nExit ) ) + "]"
   RETURN cResult
```

- [ ] **Step 5: Register the shell tool**

In `src/dstools.prg`, extend `DSTools_Registry` to its final form:

```harbour
FUNCTION DSTools_Registry()
   LOCAL oReg := {=>}
   DSTools_Register( oReg, DSTool_Read() )
   DSTools_Register( oReg, DSTool_Write() )
   DSTools_Register( oReg, DSTool_Edit() )
   DSTools_Register( oReg, DSTool_Glob() )
   DSTools_Register( oReg, DSTool_Grep() )
   DSTools_Register( oReg, DSTool_Shell() )
   RETURN oReg
```

- [ ] **Step 6: Run the tests to verify they pass**

Run (from `tests/`): `hbmk2 tests.hbp` then `run_tests.exe`
Expected: all `tools:` lines `ok`; existing tests still `ok`; exit code 0.

- [ ] **Step 7: Commit**

```bash
git add src/dstools_shell.prg src/dstools.prg tests/test_tools.prg tests/tests.hbp
git commit -m "feat: shell tool and complete six-tool registry"
```

---

## Self-Review

**Spec coverage:**
- Registry API (`DSTools_Registry` / `Register` / `Schemas` / `Executor`) —
  Task 2.
- `hTool` record shape, hash-based registry, no global state — Task 2.
- `DSTools_Schemas` OpenAI form (`type` / `function`) — Task 2.
- `DSTools_Executor` contract and the 5-step dispatch (unknown tool, invalid
  JSON, missing required arg, `BEGIN SEQUENCE` net, return string) — Task 2.
- `read` / `write` / `edit` tools, args, behaviour, error strings — Tasks 3–4.
- `glob` / `grep` tools, args, caps, error strings — Task 5.
- `shell` tool — Task 6 (no `timeout`; `shell` arg is the launcher prefix — see
  Deviations).
- Error handling at executor and handler levels — Tasks 2–6.
- Testing: registry, executor, every tool, end-to-end six-builtin check —
  Tasks 2–6.

**Placeholder scan:** none. The Task 1 stubs are intentional, replaced in
Task 2. Every code step shows complete code.

**Type consistency:** the `hTool` record keys (`name` / `description` /
`parameters` / `handler`), the executor contract (`{|cName,cArgsJson|->cString}`),
the schema entry shape (`type` / `function` with `name`/`description`/`parameters`),
and the tool-definition function names (`DSTool_Read`, `DSTool_Write`,
`DSTool_Edit`, `DSTool_Glob`, `DSTool_Grep`, `DSTool_Shell`) are used identically
across all tasks. `DSTools_Schemas` / `DSTools_Executor` outputs match the
`hOpts["tools"]` / `hOpts["tool_executor"]` inputs of `DS_AgentRun` from #2.

**Deviations from spec:** `shell` `timeout` deferred to #4; `shell` argument is
the launcher prefix. Both documented in the Deviations section above.

**Deferred (out of scope for #3):** permission gating (#5); terminal UI (#4);
subagents and thread pool (#6.5); MCP-provided tools (#6, via the same
`DSTools_Register` seam); `shell` hard timeout (#4).

# Agent Memory and the CC.md Rename — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent agent memory to CCHarbour — a `memory` tool over a per-project `memory.md` loaded into the system prompt — and rename the project-context file from `CLAUDE.md` to `CC.md`.

**Architecture:** A new `memory` tool (`src/dstools_memory.prg`) appends/reads/clears `memory.md`; `DSUI_SystemPrompt` loads `memory.md` alongside the renamed `CC.md` project context.

**Tech Stack:** Harbour. Tested through the existing `tests/run_tests.prg` harness.

**Spec:** `docs/superpowers/specs/2026-05-19-memory-and-cc-md-design.md`

---

## Build & test commands

- Build cc.exe: `build.bat` from the repo root → `Build OK -> cc.exe`.
- Build the test runner: from `tests/`, `call` the MSVC `vcvars64.bat` (e.g. `C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat`), then `set "HB_USER_CFLAGS=-MD"`, `set "HB_USER_LDFLAGS=/NODEFAULTLIB:libcmt.lib /NODEFAULTLIB:libucrt.lib /NODEFAULTLIB:libvcruntime.lib msvcrt.lib ucrt.lib vcruntime.lib"`, then `"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp` (`tests/build_tests.bat` has a bug — if it fails write your own .bat). Run `run_tests.exe` from `tests/`; last line `pass: N   fail: M`, fail must be 0.

---

## Task 1: The `memory` tool

**Files:**
- Create: `src/dstools_memory.prg`
- Create: `tests/test_memory.prg`
- Modify: `cc.hbp`, `tests/tests.hbp`, `tests/run_tests.prg`

- [ ] **Step 1: Wire the new files into the build and test harness**

In `cc.hbp`, add `src/dstools_memory.prg` on the line after `src/dstools_github.prg`.

In `tests/tests.hbp`: add `test_memory.prg` on the line after `test_github.prg`, and add `../src/dstools_memory.prg` on the line after `../src/dstools_github.prg`.

In `tests/run_tests.prg`, in `Main()`, add a call to `Test_Memory()` immediately after the existing `Test_Github()` call.

- [ ] **Step 2: Write the failing test**

Create `tests/test_memory.prg`:

```harbour
FUNCTION Test_Memory()
   LOCAL hTool, cTmp, cRes
   cTmp := hb_DirTemp() + "ds_test_memory.md"
   FErase( cTmp )
   hTool := DSTool_Memory( cTmp )

   T_Equal( hTool[ "name" ], "memory", "memory: tool name" )
   T_Equal( hTool[ "parameters" ][ "required" ][ 1 ], "operation", ;
            "memory: operation required" )

   // append to a non-existent file creates it
   cRes := Eval( hTool[ "handler" ], { "operation" => "append", "text" => "fact one" } )
   T_Equal( cRes, "Remembered.", "memory: append result" )
   // a second append adds another line
   Eval( hTool[ "handler" ], { "operation" => "append", "text" => "fact two" } )

   // read returns both entries
   cRes := Eval( hTool[ "handler" ], { "operation" => "read" } )
   T_Assert( "fact one" $ cRes .AND. "fact two" $ cRes, "memory: read returns entries" )

   // clear empties the file
   cRes := Eval( hTool[ "handler" ], { "operation" => "clear" } )
   T_Equal( cRes, "Memory cleared.", "memory: clear result" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "read" } )
   T_Equal( cRes, "(memory is empty)", "memory: read after clear" )

   // read on an absent file is the empty state
   FErase( cTmp )
   cRes := Eval( hTool[ "handler" ], { "operation" => "read" } )
   T_Equal( cRes, "(memory is empty)", "memory: read absent file" )

   // append without text -> validation error
   cRes := Eval( hTool[ "handler" ], { "operation" => "append" } )
   T_Equal( cRes, "Error: memory 'append' requires 'text'", "memory: append missing text" )

   // unknown operation
   cRes := Eval( hTool[ "handler" ], { "operation" => "bogus" } )
   T_Equal( cRes, "Error: memory: unknown operation 'bogus'", "memory: unknown op" )

   FErase( cTmp )
   RETURN NIL
```

- [ ] **Step 3: Run test to verify it fails**

Build and run the test runner.
Expected: FAIL — `DSTool_Memory` undefined.

- [ ] **Step 4: Write minimal implementation**

Create `src/dstools_memory.prg`:

```harbour
// The memory tool: a persistent agent memory file the model maintains across
// sessions. cMemPath (the path to memory.md) is captured at registry-build
// time, so it is injectable for tests.

FUNCTION DSTool_Memory( cMemPath )
   RETURN { "name" => "memory", ;
            "description" => "Your persistent memory across sessions. " + ;
               "operation 'append' adds a fact, 'read' returns the whole " + ;
               "memory, 'clear' empties it.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "operation" => { "type" => "string", ;
                     "description" => "One of: append, read, clear" }, ;
                  "text" => { "type" => "string", ;
                     "description" => "The memory entry to add (operation append)" } }, ;
               "required" => { "operation" } }, ;
            "handler" => {| hArgs | DSTool_MemoryRun( hArgs, cMemPath ) } }

STATIC FUNCTION DSTool_MemoryRun( hArgs, cMemPath )
   LOCAL cOp, cCur
   cOp := Lower( hb_CStr( hArgs[ "operation" ] ) )
   DO CASE
   CASE cOp == "append"
      IF !hb_HHasKey( hArgs, "text" ) .OR. Empty( hArgs[ "text" ] )
         RETURN "Error: memory 'append' requires 'text'"
      ENDIF
      cCur := iif( hb_FileExists( cMemPath ), hb_MemoRead( cMemPath ), "" )
      IF !Empty( cCur ) .AND. !( Right( cCur, 1 ) == Chr(10) )
         cCur += Chr(10)
      ENDIF
      hb_MemoWrit( cMemPath, cCur + hb_CStr( hArgs[ "text" ] ) + Chr(10) )
      RETURN "Remembered."
   CASE cOp == "read"
      cCur := iif( hb_FileExists( cMemPath ), ;
                   AllTrim( hb_CStr( hb_MemoRead( cMemPath ) ) ), "" )
      RETURN iif( Empty( cCur ), "(memory is empty)", cCur )
   CASE cOp == "clear"
      hb_MemoWrit( cMemPath, "" )
      RETURN "Memory cleared."
   ENDCASE
   RETURN "Error: memory: unknown operation '" + cOp + "'"
```

- [ ] **Step 5: Run test to verify it passes**

Build and run the test runner.
Expected: PASS — all `memory:` assertions pass, `fail: 0`, no regressions.

- [ ] **Step 6: Commit**

```bash
git add src/dstools_memory.prg tests/test_memory.prg cc.hbp tests/tests.hbp tests/run_tests.prg
git commit -m "feat: memory tool over a persistent memory.md"
```

---

## Task 2: Register the tool and its permission

**Files:**
- Modify: `src/dstools.prg`
- Modify: `src/dssettings.prg`
- Test: `tests/test_tools.prg`, `tests/test_settings.prg`

- [ ] **Step 1: Write the failing tests**

In `tests/test_tools.prg`, append inside `Test_Tools()` before its `RETURN NIL`:

```harbour
   // the memory tool is registered
   oReg := DSTools_Registry()
   T_Equal( hb_HHasKey( oReg, "memory" ), .T., "tools: memory registered" )
```

In `tests/test_settings.prg`, append inside `Test_Settings()` before its `RETURN NIL`:

```harbour
   hL := DSSettings_Defaults()
   T_Equal( hL[ "permissions" ][ "memory" ], "allow", "settings: memory perm" )
```

(`oReg` and `hL` are already LOCALs in those test functions — verify; add if missing.)

- [ ] **Step 2: Run tests to verify they fail**

Build and run the test runner.
Expected: FAIL — `memory` not in the registry; no `memory` permission default.

- [ ] **Step 3: Register the tool**

In `src/dstools.prg`, `DSTools_Registry` currently ends its builtin registrations with `DSTools_Register( oReg, DSTool_GithubWrite( hb_HGetDef( hKeys, "github", "" ) ) )` before `RETURN oReg`. Add one line directly after that registration and before `RETURN oReg`:

```harbour
   DSTools_Register( oReg, DSTool_Memory( "memory.md" ) )
```

- [ ] **Step 4: Add the default permission**

In `src/dssettings.prg`, `DSSettings_Defaults()` has a `permissions` hash. It currently ends `... "github_read" => "allow", "github_write" => "ask" } }`. Add `memory`:

```harbour
            "permissions"    => { "read"  => "allow", "glob"  => "allow", ;
                                  "grep"  => "allow", "write" => "ask", ;
                                  "edit"  => "ask",   "shell" => "ask", ;
                                  "web_search"   => "ask",   "web_fetch"    => "ask", ;
                                  "github_read"  => "allow", "github_write" => "ask", ;
                                  "memory" => "allow" } }
```

- [ ] **Step 5: Run tests to verify they pass**

Build and run the test runner.
Expected: PASS — `tools: memory registered` and `settings: memory perm` pass, `fail: 0`, no regressions.

- [ ] **Step 6: Commit**

```bash
git add src/dstools.prg src/dssettings.prg tests/test_tools.prg tests/test_settings.prg
git commit -m "feat: register the memory tool with an allow permission"
```

---

## Task 3: Load memory.md into the system prompt and rename CLAUDE.md to CC.md

**Files:**
- Modify: `src/dsui.prg`
- Test: `tests/test_ui.prg`

- [ ] **Step 1: Write the failing test**

Append inside `Test_UI()` in `tests/test_ui.prg`, before its `RETURN NIL`:

```harbour
   // CLAUDE.md renamed to CC.md
   T_Assert( "CC.md" $ DSUI_InitPrompt(), "ui: init prompt names CC.md" )
   T_Assert( !( "CLAUDE.md" $ DSUI_InitPrompt() ), "ui: init prompt drops CLAUDE.md" )
   T_Assert( "memory" $ Lower( DSUI_SystemPrompt() ) .OR. ;
             ValType( DSUI_MemoryContext() ) == "C", "ui: memory context available" )
   T_Equal( ValType( DSUI_MemoryContext() ), "C", "ui: memory context returns a string" )
```

- [ ] **Step 2: Run test to verify it fails**

Build and run the test runner.
Expected: FAIL — `DSUI_InitPrompt` still says `CLAUDE.md`; `DSUI_MemoryContext` undefined.

- [ ] **Step 3: Rename CLAUDE.md to CC.md**

In `src/dsui.prg`:

(a) Replace `DSUI_InitPrompt` with (every `CLAUDE.md` → `CC.md`):

```harbour
FUNCTION DSUI_InitPrompt()
   RETURN "Analyse this project and create a CC.md file in the working " + ;
          "directory. Use your tools to explore the repository: its layout, " + ;
          "how it is built and run, and its coding conventions. CC.md " + ;
          "should concisely cover: what the project is, how to build and run " + ;
          "it, the key directories, and the coding conventions to follow. " + ;
          "Keep it short. Write the file with your write tool, then confirm."
```

(b) In `DSUI_ProjectContext`, change the two `CLAUDE.md` literals to `CC.md`:

```harbour
// Reads project instructions from a CC.md file in the current directory.
// Returns "" when the file is absent or empty.
FUNCTION DSUI_ProjectContext()
   LOCAL cText := ""
   IF File( "CC.md" )
      cText := hb_MemoRead( "CC.md" )
   ENDIF
   RETURN AllTrim( hb_CStr( cText ) )
```

- [ ] **Step 4: Add `DSUI_MemoryContext` and load memory into the system prompt**

In `src/dsui.prg`, add this function directly after `DSUI_ProjectContext`:

```harbour
// Reads the agent's persisted memory from memory.md in the current directory.
// Returns "" when the file is absent or empty.
FUNCTION DSUI_MemoryContext()
   LOCAL cText := ""
   IF File( "memory.md" )
      cText := hb_MemoRead( "memory.md" )
   ENDIF
   RETURN AllTrim( hb_CStr( cText ) )
```

Then replace `DSUI_SystemPrompt` with (the `CLAUDE.md` wording becomes `CC.md`, and a memory section is appended):

```harbour
FUNCTION DSUI_SystemPrompt()
   LOCAL cBase, cProj, cMem
   cBase := "You are CCHarbour, a terminal coding assistant. " + ;
            "You have tools to read, write and edit files, search with glob and " + ;
            "grep, and run shell commands. Use them to help the user with coding " + ;
            "tasks. Be concise. " + ;
            "End every reply with a final line in the exact form " + ;
            "'Suggested next: <a short prompt the user might send next>'."
   cProj := DSUI_ProjectContext()
   IF !Empty( cProj )
      cBase += Chr(10) + Chr(10) + ;
         "The following project instructions come from the CC.md file in " + ;
         "the working directory. Treat them as authoritative and follow them:" + ;
         Chr(10) + Chr(10) + cProj
   ENDIF
   cMem := DSUI_MemoryContext()
   IF !Empty( cMem )
      cBase += Chr(10) + Chr(10) + ;
         "The following is your own memory, persisted from previous sessions " + ;
         "in this project. Use it, and keep it current with the memory tool:" + ;
         Chr(10) + Chr(10) + cMem
   ENDIF
   RETURN cBase
```

- [ ] **Step 5: Run test to verify it passes**

Build and run the test runner.
Expected: PASS — the `ui:` CC.md / memory assertions pass, `fail: 0`, no regressions. If a pre-existing test still asserts `DSUI_InitPrompt`/`DSUI_SystemPrompt` contains `CLAUDE.md`, update that assertion to `CC.md`.

- [ ] **Step 6: Build the app**

Run `build.bat`. Expected: `Build OK -> cc.exe`.

- [ ] **Step 7: Commit**

```bash
git add src/dsui.prg tests/test_ui.prg
git commit -m "feat: load memory.md into the system prompt; rename CLAUDE.md to CC.md"
```

---

## Task 4: Update the docs

**Files:**
- Modify: `pages/*.md` (whichever mention `CLAUDE.md`)

- [ ] **Step 1: Find and update CLAUDE.md references**

Search the docs for `CLAUDE.md`: across `pages/` (and `README.md`). For every prose reference to the project-context file `CLAUDE.md`, change it to `CC.md`. Also, where the docs list the tools or describe the agent, add a short mention of the new `memory` tool and the `memory.md` file (the agent's persistent per-project memory, updated via the `memory` tool) — matching the existing docs' tone and the page that documents tools/configuration.

Do not change occurrences of `CLAUDE.md` that refer to Claude Code itself (if any) — only the ones describing CCHarbour's own project-context file.

- [ ] **Step 2: Verify the MkDocs build (if available)**

If `mkdocs` is installed, run `mkdocs build --strict` from the repo root and confirm no warnings. If not installed, skip and note it.

- [ ] **Step 3: Commit**

```bash
git add pages README.md
git commit -m "docs: rename CLAUDE.md to CC.md and document the memory tool"
```

---

## Self-review notes

- **Spec coverage:** the `memory` tool with append/read/clear (T1); registration + the `allow` permission (T2); `memory.md` loaded into the system prompt and the `CLAUDE.md`→`CC.md` rename in `DSUI_ProjectContext`/`DSUI_InitPrompt`/`DSUI_SystemPrompt` (T3); doc updates (T4). Every spec section maps to a task.
- **Placeholder scan:** no TBD/TODO; all code complete. T4 Step 1 is a search-and-replace task with a clear rule rather than a fixed file list, because the exact set of `pages/` files mentioning `CLAUDE.md` must be discovered — the rule (change CCHarbour's own context-file references, leave Claude-Code references) is explicit.
- **Type consistency:** the tool is `{name,description,parameters,handler}` like every other CCHarbour tool; `DSTool_Memory( cMemPath )` captures the path; `DSTool_MemoryRun( hArgs, cMemPath )` is the handler; `DSUI_MemoryContext()` mirrors `DSUI_ProjectContext()` (reads a file, returns a trimmed string or `""`). `DSTools_Registry` passes the literal `"memory.md"`.
- **Permission:** `memory => "allow"` added to `DSSettings_Defaults`; the destructive `clear` runs under it by design (per the spec).
- **No regression risk:** the rename only changes which filename `DSUI_ProjectContext` looks for; a project with no `CC.md` simply has no project context (as before with a missing `CLAUDE.md`).

# Persistent Todo Lists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `todo_write` agent tool that maintains a session task list, rendered when updated and re-shown at the idle prompt until every item is completed.

**Architecture:** A pure normaliser plus in-memory list state in a new `src/cctodo.prg`; a pure renderer `CCUI_TodoBlock` in `src/ccui.prg`; the `todo_write` tool in a new `src/cctools_todo.prg`. The REPL re-shows the list at idle when items remain open.

**Tech Stack:** Harbour 3.2, the project's `T_Equal`/`T_Assert` test harness, the existing tool-registry and permission-gate machinery.

---

## Background — conventions an implementer needs

- **Building tests (Windows):** run `cmd /c "tests\build_tests.bat"` via the PowerShell tool from the repo root. Then `cd C:\CCHarbour\tests; .\run_tests.exe`. The last line reads `pass: N   fail: M`. Baseline before this plan: `pass: 413   fail: 0`.
- **Building the app (Windows):** run `cmd /c ".\build.bat"` via the PowerShell tool. Exit 0 + `Build OK -> cc.exe` means success.
- Both `.bat` files only work invoked exactly as shown via the PowerShell tool (they set up the Visual Studio environment).
- **A new `src/*.prg` file must be registered in four project files:** `cc.hbp`, `cc_linux.hbp`, `cc_mac.hbp` (path `src/xxx.prg`) and `tests/tests.hbp` (path `../src/xxx.prg`). Missing one causes a link error.
- **Test harness:** each `Test_X()` lives in `tests/test_x.prg` and is called from `Main()` in `tests/run_tests.prg`. `T_Equal( actual, expected, name )` and `T_Assert( cond, name )` record pass/fail.
- **Tool registry:** `CCTOOLS_Registry` in `src/cctools.prg` registers each builtin. A tool is a hash `{ name, description, parameters, handler }`; `handler` is a codeblock `{| hArgs | ... }` returning a string. See `src/cctools_ask.prg` for the closest analogue (`ask_user`).
- **Permission gate:** `CCPERM_Decide` in `src/ccperm.prg` already has a bypass `IF cName == "ask_user"` — UI-only tools skip the gate.
- **Colour:** `CCUI_Color( cText, cSGR )` wraps text in an SGR escape, or returns it unchanged when colour is off (the default in the test build). `CCUI_Pal( "bold" | "dim" | "accent" )` returns SGR codes.
- **Harbour notes:** `ValType( x )` returns `"A"` array, `"H"` hash, `"C"` string. `hb_HHasKey( h, k )` tests a hash key. `FOR EACH ... NEXT` iterates; `LOOP` skips to the next iteration.

---

## Task 1: `cctodo.prg` — list state and normaliser

**Files:**
- Create: `src/cctodo.prg`
- Modify: `cc.hbp`, `cc_linux.hbp`, `cc_mac.hbp`, `tests/tests.hbp`
- Create: `tests/test_todo.prg`
- Modify: `tests/run_tests.prg`

- [ ] **Step 1: Create `src/cctodo.prg`**

```harbour
// cctodo: the session todo list maintained by the todo_write tool. Holds the
// pure normaliser plus the in-memory list state. Knows nothing about
// rendering or the REPL.

STATIC s_aTodos := {}

// True when cStatus is one of the three valid task statuses.
STATIC FUNCTION CCTODO_ValidStatus( cStatus )
   RETURN cStatus == "pending" .OR. cStatus == "in_progress" .OR. ;
          cStatus == "completed"

// Returns a cleaned copy of aTodos. Each element must be a hash with a string
// "text"; others are dropped. A "status" that is missing or not one of the
// three valid values becomes "pending". Returns an array of
// { "text" => <string>, "status" => <valid status> } hashes.
FUNCTION CCTODO_Norm( aTodos )
   LOCAL aOut := {}, hItem, cStatus
   IF ValType( aTodos ) != "A"
      RETURN aOut
   ENDIF
   FOR EACH hItem IN aTodos
      IF ValType( hItem ) != "H" .OR. !hb_HHasKey( hItem, "text" ) .OR. ;
         ValType( hItem[ "text" ] ) != "C"
         LOOP
      ENDIF
      cStatus := iif( hb_HHasKey( hItem, "status" ) .AND. ;
                      ValType( hItem[ "status" ] ) == "C", ;
                      hItem[ "status" ], "pending" )
      IF !CCTODO_ValidStatus( cStatus )
         cStatus := "pending"
      ENDIF
      AAdd( aOut, { "text" => hItem[ "text" ], "status" => cStatus } )
   NEXT
   RETURN aOut

// Normalises aTodos and stores it as the session list. Returns the stored list.
FUNCTION CCTODO_Set( aTodos )
   s_aTodos := CCTODO_Norm( aTodos )
   RETURN s_aTodos

// Returns the stored session list (an empty array before the first Set).
FUNCTION CCTODO_Get()
   RETURN s_aTodos

// True when the stored list is non-empty and at least one item is not done.
FUNCTION CCTODO_HasOpen()
   LOCAL hItem
   FOR EACH hItem IN s_aTodos
      IF hItem[ "status" ] != "completed"
         RETURN .T.
      ENDIF
   NEXT
   RETURN .F.
```

- [ ] **Step 2: Register `cctodo.prg` in the four project files**

In `cc.hbp`, `cc_linux.hbp`, `cc_mac.hbp`: add the line `src/cctodo.prg` directly after the `src/ccselect.prg` line.

In `tests/tests.hbp`: add the line `../src/cctodo.prg` directly after the `../src/ccselect.prg` line.

- [ ] **Step 3: Create `tests/test_todo.prg`**

```harbour
FUNCTION Test_Todo()
   LOCAL aNorm, aList

   // --- CCTODO_Norm ---
   aNorm := CCTODO_Norm( { { "text" => "a", "status" => "bogus" } } )
   T_Equal( aNorm[ 1 ][ "status" ], "pending", "todo: bad status -> pending" )

   aNorm := CCTODO_Norm( { { "text" => "a", "status" => "in_progress" } } )
   T_Equal( aNorm[ 1 ][ "status" ], "in_progress", "todo: valid status kept" )

   aNorm := CCTODO_Norm( { "not a hash", { "text" => "ok", "status" => "pending" } } )
   T_Equal( Len( aNorm ), 1, "todo: non-hash element dropped" )

   aNorm := CCTODO_Norm( { { "status" => "pending" } } )
   T_Equal( Len( aNorm ), 0, "todo: element missing text dropped" )

   aNorm := CCTODO_Norm( "not an array" )
   T_Equal( Len( aNorm ), 0, "todo: non-array input -> empty list" )

   // --- CCTODO_Set / CCTODO_Get round-trip ---
   CCTODO_Set( { { "text" => "first", "status" => "pending" }, ;
                 { "text" => "second", "status" => "completed" } } )
   aList := CCTODO_Get()
   T_Equal( Len( aList ), 2, "todo: set/get round-trips the list" )
   T_Equal( aList[ 1 ][ "text" ], "first", "todo: get keeps item text" )

   // --- CCTODO_HasOpen ---
   CCTODO_Set( { { "text" => "a", "status" => "pending" } } )
   T_Equal( CCTODO_HasOpen(), .T., "todo: pending item -> has open" )

   CCTODO_Set( { { "text" => "a", "status" => "in_progress" } } )
   T_Equal( CCTODO_HasOpen(), .T., "todo: in_progress item -> has open" )

   CCTODO_Set( { { "text" => "a", "status" => "completed" }, ;
                 { "text" => "b", "status" => "completed" } } )
   T_Equal( CCTODO_HasOpen(), .F., "todo: all completed -> no open" )

   CCTODO_Set( {} )
   T_Equal( CCTODO_HasOpen(), .F., "todo: empty list -> no open" )

   RETURN NIL
```

- [ ] **Step 4: Register the test**

In `tests/run_tests.prg`, add `Test_Todo()` inside `Main()` directly after the `Test_Select()` call.

In `tests/tests.hbp`, add the line `test_todo.prg` directly after the `test_select.prg` line.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cmd /c "tests\build_tests.bat"` then `cd C:\CCHarbour\tests; .\run_tests.exe`
Expected: all new `ok   - todo:` lines, `fail: 0`. (The implementation in Step 1 is complete, so these pass on the first run. To confirm the tests genuinely exercise the code, temporarily change `CCTODO_Norm` to skip the `cStatus := "pending"` fallback, rebuild, see `FAIL - todo: bad status -> pending`, then restore it.)

- [ ] **Step 6: Commit**

```bash
git add src/cctodo.prg tests/test_todo.prg tests/run_tests.prg tests/tests.hbp cc.hbp cc_linux.hbp cc_mac.hbp
git commit -m "feat: add cctodo session list state and normaliser"
```

---

## Task 2: `CCUI_TodoBlock` — the renderer

**Files:**
- Modify: `src/ccui.prg` (add a function after `CCUI_QuestionBlock`)
- Test: `tests/test_ui.prg`

- [ ] **Step 1: Write the failing test**

Add inside `Test_UI()` in `tests/test_ui.prg`, before its final `RETURN`. Add `cTodoBlk` to the `LOCAL` list at the top of `Test_UI`:

```harbour
   // --- CCUI_TodoBlock ---
   cTodoBlk := CCUI_TodoBlock( { { "text" => "wash up", "status" => "completed" }, ;
                                 { "text" => "cook", "status" => "in_progress" }, ;
                                 { "text" => "sleep", "status" => "pending" } } )
   T_Assert( "Todos:" $ cTodoBlk, "ui: todo block has a header" )
   T_Assert( "wash up" $ cTodoBlk, "ui: todo block shows completed item text" )
   T_Assert( "cook" $ cTodoBlk, "ui: todo block shows in_progress item text" )
   T_Assert( "sleep" $ cTodoBlk, "ui: todo block shows pending item text" )
   T_Assert( Chr(226) + Chr(136) + Chr(154) $ cTodoBlk, ;
             "ui: todo block has the completed glyph" )
   T_Assert( Chr(226) + Chr(150) + Chr(160) $ cTodoBlk, ;
             "ui: todo block has the in_progress glyph" )
   T_Assert( Chr(226) + Chr(150) + Chr(161) $ cTodoBlk, ;
             "ui: todo block has the pending glyph" )
   T_Assert( Right( cTodoBlk, 1 ) == Chr(10), "ui: todo block ends in LF" )
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cmd /c "tests\build_tests.bat"` then `cd C:\CCHarbour\tests; .\run_tests.exe`
Expected: build/link error or `FAIL` — `CCUI_TodoBlock` does not exist yet.

- [ ] **Step 3: Add the implementation**

Add to `src/ccui.prg`, immediately after the `CCUI_QuestionBlock` function (after its `RETURN`):

```harbour
// Renders a todo list to a printable block: a "Todos:" header, then one line
// per item -- a status glyph and the item text. completed = "√" (dim),
// in_progress = "■" (accent), pending = "□". Each line ends in LF. Pure.
FUNCTION CCUI_TodoBlock( aTodos )
   LOCAL cOut := CCUI_Color( "Todos:", CCUI_Pal( "bold" ) ) + Chr(10)
   LOCAL hItem, cGlyph
   LOCAL cDone := Chr(226) + Chr(136) + Chr(154)   // U+221A √
   LOCAL cProg := Chr(226) + Chr(150) + Chr(160)   // U+25A0 ■
   LOCAL cPend := Chr(226) + Chr(150) + Chr(161)   // U+25A1 □
   FOR EACH hItem IN aTodos
      DO CASE
      CASE hItem[ "status" ] == "completed"
         cGlyph := CCUI_Color( cDone, CCUI_Pal( "dim" ) )
      CASE hItem[ "status" ] == "in_progress"
         cGlyph := CCUI_Color( cProg, CCUI_Pal( "accent" ) )
      OTHERWISE
         cGlyph := cPend
      ENDCASE
      cOut += "  " + cGlyph + " " + hItem[ "text" ] + Chr(10)
   NEXT
   RETURN cOut
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cmd /c "tests\build_tests.bat"` then `cd C:\CCHarbour\tests; .\run_tests.exe`
Expected: all new `ok   - ui: todo block...` lines, `fail: 0`.

- [ ] **Step 5: Commit**

```bash
git add src/ccui.prg tests/test_ui.prg
git commit -m "feat: add CCUI_TodoBlock renderer"
```

---

## Task 3: `todo_write` tool

**Files:**
- Create: `src/cctools_todo.prg`
- Modify: `cc.hbp`, `cc_linux.hbp`, `cc_mac.hbp`, `tests/tests.hbp`, `src/cctools.prg`, `src/ccperm.prg`, `tests/test_tools.prg`

- [ ] **Step 1: Create `src/cctools_todo.prg`**

```harbour
// todo_write: the agent maintains a visible session task list. Each call
// replaces the whole list; the rendered list is returned so the model and
// the user both see the current state.
FUNCTION CCTool_TodoWrite()
   RETURN { "name" => "todo_write", ;
            "description" => "Maintain a visible task list for multi-step " + ;
               "work. Call with the full list every time -- it replaces the " + ;
               "previous list. Mark each item pending, in_progress or " + ;
               "completed; keep exactly one item in_progress while working.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "todos" => { "type" => "array", ;
                     "description" => "The full task list", ;
                     "items" => { "type" => "object", ;
                        "properties" => { ;
                           "text" => { "type" => "string", ;
                              "description" => "The task description" }, ;
                           "status" => { "type" => "string", ;
                              "description" => "pending, in_progress or completed" } }, ;
                        "required" => { "text", "status" } } } }, ;
               "required" => { "todos" } }, ;
            "handler" => {| hArgs | CCTool_TodoWriteRun( hArgs ) } }

STATIC FUNCTION CCTool_TodoWriteRun( hArgs )
   IF ValType( hArgs[ "todos" ] ) != "A"
      RETURN "Error: 'todos' must be an array"
   ENDIF
   CCTODO_Set( hArgs[ "todos" ] )
   RETURN CCUI_TodoBlock( CCTODO_Get() )
```

- [ ] **Step 2: Register `cctools_todo.prg` in the four project files**

In `cc.hbp`, `cc_linux.hbp`, `cc_mac.hbp`: add the line `src/cctools_todo.prg` directly after the `src/cctools_ask.prg` line.

In `tests/tests.hbp`: add the line `../src/cctools_todo.prg` directly after the `../src/cctools_ask.prg` line.

- [ ] **Step 3: Register the tool in the registry**

In `src/cctools.prg`, in `CCTOOLS_Registry`, add this line directly after the `CCTool_AskUser()` registration line:

```harbour
   CCTOOLS_Register( oReg, CCTool_TodoWrite() )
```

- [ ] **Step 4: Bypass the permission gate for `todo_write`**

In `src/ccperm.prg`, in `CCPERM_Decide`, find the existing bypass:

```harbour
   // asking the user a question is inherently consented -- never gated
   IF cName == "ask_user"
      RETURN Eval( bInner, cName, cArgsJson )
   ENDIF
```

Replace it with:

```harbour
   // ask_user / todo_write only drive the UI -- inherently consented, never gated
   IF cName == "ask_user" .OR. cName == "todo_write"
      RETURN Eval( bInner, cName, cArgsJson )
   ENDIF
```

- [ ] **Step 5: Update the builtin-count test and add a registration assertion**

In `tests/test_tools.prg`, find the builtin-count assertion (search for `builtins`):

```harbour
   // end-to-end: the default registry exposes all twelve builtin tools
   aSchemas := CCTOOLS_Schemas( CCTOOLS_Registry() )
   T_Equal( Len( aSchemas ), 12, "tools: registry has twelve builtins" )
```

Replace those three lines with:

```harbour
   // end-to-end: the default registry exposes all thirteen builtin tools
   aSchemas := CCTOOLS_Schemas( CCTOOLS_Registry() )
   T_Equal( Len( aSchemas ), 13, "tools: registry has thirteen builtins" )
```

Then find the `ask_user` registration assertion (search for `ask_user is registered`) and add directly after it:

```harbour
   T_Assert( hb_HHasKey( CCTOOLS_Registry(), "todo_write" ), ;
             "tools: todo_write is registered" )
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cmd /c "tests\build_tests.bat"` then `cd C:\CCHarbour\tests; .\run_tests.exe`
Expected: `ok   - tools: todo_write is registered`, `ok   - tools: registry has thirteen builtins`, `fail: 0`. A link error here usually means a project file in Step 2 was missed — check all four.

- [ ] **Step 7: Commit**

```bash
git add src/cctools_todo.prg src/cctools.prg src/ccperm.prg tests/test_tools.prg tests/tests.hbp cc.hbp cc_linux.hbp cc_mac.hbp
git commit -m "feat: add todo_write agent tool"
```

---

## Task 4: idle re-display in the REPL

**Files:**
- Modify: `src/ccrepl.prg`

This task touches the REPL's main loop, which is not exercised by the test suite. It is verified by building the app and a manual run.

- [ ] **Step 1: Re-show the list at the idle prompt**

In `src/ccrepl.prg`, in `CCREPL_Run`, find where the rotating tip is emitted in box mode:

```harbour
      IF oPrompt != NIL
         CCREPL_Out( CCUI_TipLine( CCUI_TipAt( ++s_nTipIdx ) ) )
         cLine := CCREPL_PromptIdle( oPrompt )
```

Replace those three lines with:

```harbour
      IF oPrompt != NIL
         IF CCTODO_HasOpen()
            CCREPL_Out( CCUI_TodoBlock( CCTODO_Get() ) )
         ENDIF
         CCREPL_Out( CCUI_TipLine( CCUI_TipAt( ++s_nTipIdx ) ) )
         cLine := CCREPL_PromptIdle( oPrompt )
```

When the session todo list still has an open item, the list is printed above the input box on each return to idle. Once every item is `completed` (or the list is empty), `CCTODO_HasOpen()` is false and nothing is shown. The cooked / piped path (`oPrompt == NIL`) is left untouched.

- [ ] **Step 2: Build the app**

Run: `cmd /c ".\build.bat"`
Expected: build succeeds, `Build OK -> cc.exe`.

- [ ] **Step 3: Manual verification**

Run `cc.exe`. Ask the agent to do a multi-step task and to track it with a todo list (e.g. *"Make a 3-item todo list for refactoring a function, then mark the first item done."*). Confirm: the list renders when `todo_write` is called (status glyphs `√` / `■` / `□`); the list re-appears above the input box at each idle prompt while items remain open; once all items are `completed`, the list stops appearing at idle.

- [ ] **Step 4: Commit**

```bash
git add src/ccrepl.prg
git commit -m "feat: re-show the todo list at the idle prompt"
```

---

## Self-Review notes

- **Spec coverage:** `cctodo.prg` state + normaliser → Task 1. `CCUI_TodoBlock` → Task 2. `todo_write` tool + registration + gate bypass → Task 3. Idle re-display → Task 4. Every spec section maps to a task.
- **Type consistency:** a todo item is the hash `{ "text" => <string>, "status" => <"pending"|"in_progress"|"completed"> }` everywhere — produced by `CCTODO_Norm`, stored by `CCTODO_Set`, consumed by `CCTODO_HasOpen`, `CCUI_TodoBlock`, and the `todo_write` executor. `CCTODO_Get()` returns the array of these hashes. Names and signatures are consistent across all four tasks.
- **Placeholder scan:** every code step contains complete code; no TBD/TODO.

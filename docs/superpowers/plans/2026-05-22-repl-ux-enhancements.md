# REPL UX Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three console front-end improvements to the CCHarbour REPL — `/clear` wiping the terminal screen, a two-panel startup banner, and an `ask_user` agent tool for interactive multiple-choice questions.

**Architecture:** Pure render/logic helpers live in `ccui.prg` and a new `ccselect.prg`, mirroring the existing `ccprompt.prg` split (pure logic separate from console I/O). The pure helpers are unit-tested through the existing `tests/run_tests.prg` harness; the raw-key I/O loops and VT-emitting glue are verified by manual run. The `ask_user` tool plugs into the existing tool registry and bypasses the permission gate.

**Tech Stack:** Harbour 3.2, the project's `T_Equal`/`T_Assert` test harness, ANSI/VT escape sequences, `hbmk2` build projects.

---

## Background — conventions an implementer needs

- **Test harness:** `tests/run_tests.prg` defines `Main()`, which calls one `Test_<Name>()` function per module. `T_Equal( actual, expected, name )` and `T_Assert( cond, name )` record pass/fail. Each `Test_<Name>` lives in its own `tests/test_<name>.prg`.
- **Building tests (Windows):** run `tests\build_tests.bat` from the repo root. It builds `tests/run_tests.exe` via `tests/tests.hbp`. Then run `tests\run_tests.exe`; the last line reads `pass: N   fail: M`.
- **Building the app (Windows):** run `build.bat` from the repo root (produces `cc.exe`). Manual verification means launching `cc.exe`.
- **A new `src/*.prg` file must be added to four project files** to link everywhere: `cc.hbp`, `cc_linux.hbp`, `cc_mac.hbp`, and `tests/tests.hbp`. In `tests.hbp` the path is prefixed with `../src/`.
- **Colour:** `CCUI_Color( cText, cSGR )` wraps text in an SGR escape, or returns it unchanged when colour is off (the default in the test build). `CCUI_ColorOn()` reports the state. `CCUI_Pal( name )` maps palette names (`accent`, `dim`, `bold`, ...) to SGR codes.
- **Glyphs:** `CCUI_Glyph( name )` returns UTF-8 box-drawing bytes (`tl tr bl br h v`).
- **`CCUI_PadCell( cText, nWidth, cAlign )`** pads/truncates to `nWidth` display columns counting UTF-8 characters; `cAlign` is `"L"`, `"C"`, or `"R"`. It is `STATIC` to `ccui.prg` — only code in `ccui.prg` may call it.
- **Key codes** from `CCCON_ReadKey()`: `-1` Enter, `-2` Backspace, `-9` Up, `-10` Down, `-13` Esc; positive values are character codes (digit `1` is 49). `CCCON_KeyPending()` is a non-blocking check. `CCCON_HasConsole()` is false for piped/non-interactive input.
- **Raw console writes:** `FWrite( hb_GetStdOut(), cText )` writes bytes straight to stdout, bypassing `CCREPL_Out` (which rewrites line endings). Used for absolute cursor control — see `CCPROMPT_Raw` in `ccprompt.prg`.

---

## Feature A — `/clear` clears the terminal screen

### Task A1: `CCUI_ClearScreenSeq` helper

**Files:**
- Modify: `src/ccui.prg` (add a new function near `CCUI_VT`, around line 357)
- Test: `tests/test_ui.prg` (add assertions inside `Test_UI`)

- [ ] **Step 1: Write the failing test**

Add to `tests/test_ui.prg`, inside the `Test_UI()` function body (before its final `RETURN`):

```harbour
   // --- CCUI_ClearScreenSeq ---
   T_Equal( CCUI_ClearScreenSeq(), ;
            Chr(27) + "[3J" + Chr(27) + "[2J" + Chr(27) + "[H", ;
            "ui: clear-screen sequence is 3J + 2J + H" )
```

Note: the test build has colour off, so `CCUI_ColorOn()` is false and this asserts the colour-off branch returns the sequence anyway. The sequence must NOT be gated on colour — gating happens in the REPL caller (Task A2). Correct that expectation only if the implementation in Step 3 differs.

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: build fails to link, or the run reports `FAIL - ui: clear-screen sequence...` — `CCUI_ClearScreenSeq` does not exist yet.

- [ ] **Step 3: Add the implementation**

Add to `src/ccui.prg`, immediately after the `CCUI_VT` function (after its `RETURN` near line 356):

```harbour
// The VT sequence that wipes the terminal: ESC[3J clears scrollback,
// ESC[2J clears the visible screen, ESC[H homes the cursor. Returned
// unconditionally; callers decide whether the terminal can accept it.
FUNCTION CCUI_ClearScreenSeq()
   RETURN Chr(27) + "[3J" + Chr(27) + "[2J" + Chr(27) + "[H"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: `ok   - ui: clear-screen sequence is 3J + 2J + H`, `fail: 0`.

- [ ] **Step 5: Commit**

```bash
git add src/ccui.prg tests/test_ui.prg
git commit -m "feat: add CCUI_ClearScreenSeq helper"
```

### Task A2: `/clear` wipes the screen

**Files:**
- Modify: `src/ccrepl.prg` (add `CCREPL_ClearScreen`; change the `/clear` case near line 106)

- [ ] **Step 1: Add the `CCREPL_ClearScreen` helper**

Add to `src/ccrepl.prg`, as a new `STATIC FUNCTION` near the other `STATIC` REPL helpers (e.g. just before `CCREPL_AccumUsage`, around line 244):

```harbour
// Wipes the terminal screen for /clear. Skipped when there is no console or
// colour/VT output is off (piped input) -- the escape bytes would be garbage.
// When the persistent box is mounted, ESC[2J also clears it, so the box and
// its scroll region are rebuilt with CCPROMPT_Activate.
STATIC FUNCTION CCREPL_ClearScreen( oPrompt )
   IF !CCCON_HasConsole() .OR. !CCUI_ColorOn()
      RETURN NIL
   ENDIF
   FWrite( hb_GetStdOut(), CCUI_ClearScreenSeq() )
   IF oPrompt != NIL
      CCPROMPT_Activate( oPrompt )
   ENDIF
   RETURN NIL
```

- [ ] **Step 2: Call it from the `/clear` case**

In `src/ccrepl.prg`, find the `/clear` case (around line 106):

```harbour
      CASE hAction[ "type" ] == "clear"
         aMsgs := { { "role" => "system", "content" => CCUI_SystemPrompt() } }
         s_hSessionUsage := {=>}
         CCREPL_Out( CCUI_Color( "[conversation reset]", "90" ) + Chr(10) )
```

Replace it with:

```harbour
      CASE hAction[ "type" ] == "clear"
         CCREPL_ClearScreen( oPrompt )
         aMsgs := { { "role" => "system", "content" => CCUI_SystemPrompt() } }
         s_hSessionUsage := {=>}
         CCREPL_Out( CCUI_Color( "[conversation reset]", "90" ) + Chr(10) )
```

- [ ] **Step 3: Build the app**

Run: `build.bat`
Expected: build succeeds, `cc.exe` produced.

- [ ] **Step 4: Manual verification**

Run `cc.exe`. Send a message so the screen has content and scrollback. Type `/clear`. Confirm: the visible screen and scrollback are wiped, the input box is redrawn at the bottom, `[conversation reset]` is printed, and the screen is otherwise **bare** (no banner). Type a follow-up to confirm the conversation truly reset (the model has no memory of the earlier message).

- [ ] **Step 5: Commit**

```bash
git add src/ccrepl.prg
git commit -m "feat: /clear also wipes the terminal screen"
```

---

## Feature B — two-panel startup banner

### Task B1: `CCUI_ReleaseTagline` — first line of release notes

**Files:**
- Modify: `src/ccui.prg` (add near `CCUI_Version`, around line 465)
- Test: `tests/test_ui.prg`

- [ ] **Step 1: Write the failing test**

Add inside `Test_UI()` in `tests/test_ui.prg`:

```harbour
   // --- CCUI_ReleaseTagline ---
   T_Equal( CCUI_ReleaseTagline( "first line" + Chr(10) + "second", "FB" ), ;
            "first line", "ui: tagline takes the first line" )
   T_Equal( CCUI_ReleaseTagline( Chr(10) + Chr(10) + "  real  " + Chr(10), "FB" ), ;
            "real", "ui: tagline skips blank lines and trims" )
   T_Equal( CCUI_ReleaseTagline( "", "FB" ), ;
            "FB", "ui: empty text falls back" )
   T_Equal( CCUI_ReleaseTagline( "  " + Chr(13) + Chr(10), "FB" ), ;
            "FB", "ui: whitespace-only text falls back" )
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: build/link error or `FAIL` lines — `CCUI_ReleaseTagline` does not exist yet.

- [ ] **Step 3: Add the implementation**

Add to `src/ccui.prg`, immediately after the `CCUI_Version` function (after its `RETURN` near line 465):

```harbour
// Returns the first non-empty, trimmed line of cText (CR stripped). When no
// such line exists, returns cFallback. Used for the banner's "What's new".
FUNCTION CCUI_ReleaseTagline( cText, cFallback )
   LOCAL cLine
   FOR EACH cLine IN hb_ATokens( hb_CStr( cText ), Chr(10) )
      cLine := AllTrim( StrTran( cLine, Chr(13), "" ) )
      IF !Empty( cLine )
         RETURN cLine
      ENDIF
   NEXT
   RETURN hb_CStr( cFallback )
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: the four new `ok   - ui: tagline...` lines, `fail: 0`.

- [ ] **Step 5: Commit**

```bash
git add src/ccui.prg tests/test_ui.prg
git commit -m "feat: add CCUI_ReleaseTagline helper"
```

### Task B2: `CCUI_WhatsNew` — locate and read `releasenotes.md`

**Files:**
- Modify: `src/ccui.prg` (add directly after `CCUI_ReleaseTagline`)

- [ ] **Step 1: Add the implementation**

This function does file I/O (locating `releasenotes.md`), so it is verified manually rather than unit-tested. Add to `src/ccui.prg` after `CCUI_ReleaseTagline`:

```harbour
// The "What's new" line for the banner: the first line of releasenotes.md,
// looked up beside the executable first, then in the working directory. When
// the file is absent or empty, falls back to "CCHarbour v<version>".
FUNCTION CCUI_WhatsNew()
   LOCAL cFallback := "CCHarbour v" + CCUI_Version()
   LOCAL cPath := hb_DirBase() + "releasenotes.md"
   IF !hb_FileExists( cPath )
      cPath := "releasenotes.md"
   ENDIF
   IF hb_FileExists( cPath )
      RETURN CCUI_ReleaseTagline( hb_MemoRead( cPath ), cFallback )
   ENDIF
   RETURN cFallback
```

- [ ] **Step 2: Build the app to confirm it compiles**

Run: `build.bat`
Expected: build succeeds. (Full banner behaviour is verified in Task B4.)

- [ ] **Step 3: Commit**

```bash
git add src/ccui.prg
git commit -m "feat: add CCUI_WhatsNew releasenotes lookup"
```

### Task B3: `CCUI_BannerJoin` — join two panel columns

**Files:**
- Modify: `src/ccui.prg` (add `CCUI_Cell`, `CCUI_PanelRow`, `CCUI_BannerJoin` near `CCUI_Banner`, around line 466)
- Test: `tests/test_ui.prg`

A "cell" is a hash `{ "text" => <string>, "align" => "L"|"C"|"R", "sgr" => <SGR code or ""> }`.

- [ ] **Step 1: Write the failing test**

Add inside `Test_UI()` in `tests/test_ui.prg`:

```harbour
   // --- CCUI_BannerJoin ---
   LOCAL aJL := { CCUI_Cell( "A", "L", "" ) }
   LOCAL aJR := { CCUI_Cell( "B", "L", "" ), CCUI_Cell( "C", "L", "" ) }
   LOCAL aJoined := CCUI_BannerJoin( aJL, aJR, 5, 5 )
   T_Equal( Len( aJoined ), 2, "ui: bannerjoin pads to the taller column" )
   T_Equal( hb_UTF8Len( aJoined[ 1 ] ), 13, ;
            "ui: bannerjoin row width is left + 3 divider + right" )
   T_Equal( hb_UTF8Len( aJoined[ 2 ] ), 13, ;
            "ui: bannerjoin pads the short column with blanks" )
   T_Assert( "A" $ aJoined[ 1 ] .AND. "B" $ aJoined[ 1 ], ;
             "ui: bannerjoin row 1 holds both cells" )
```

Add `LOCAL aJL, aJR, aJoined` to the existing `LOCAL` declarations at the top of `Test_UI()` if `LOCAL` mid-function is not accepted by the build — Harbour allows `LOCAL` anywhere, but match the file's existing style.

Note: the test build has colour off, so the divider (`" " + │ + " "`) is 3 display columns and `CCUI_Color` adds no bytes — making `hb_UTF8Len` equal to display width.

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: build/link error or `FAIL` — `CCUI_Cell` / `CCUI_BannerJoin` do not exist.

- [ ] **Step 3: Add the implementation**

Add to `src/ccui.prg`, immediately before `FUNCTION CCUI_Banner` (around line 471):

```harbour
// Builds a banner cell: text, alignment ("L"/"C"/"R"), and an SGR code ("" = none).
FUNCTION CCUI_Cell( cText, cAlign, cSGR )
   RETURN { "text" => hb_CStr( cText ), ;
            "align" => iif( Empty( cAlign ), "L", cAlign ), ;
            "sgr" => hb_CStr( cSGR ) }

// Renders one cell to nWidth display columns, padded then colour-wrapped.
STATIC FUNCTION CCUI_PanelRow( hCell, nWidth )
   LOCAL cCell := CCUI_PadCell( hCell[ "text" ], nWidth, hCell[ "align" ] )
   IF !Empty( hCell[ "sgr" ] )
      cCell := CCUI_Color( cCell, hCell[ "sgr" ] )
   ENDIF
   RETURN cCell

// Joins a left and a right column of cells row-for-row into finished banner
// lines: left cell, a dim vertical divider with a space each side, right cell.
// The shorter column is padded with blank cells so both reach equal height.
FUNCTION CCUI_BannerJoin( aLeft, aRight, nLeftW, nRightW )
   LOCAL aOut := {}, nRows, i, hL, hR
   LOCAL hBlank := CCUI_Cell( "", "L", "" )
   LOCAL cDiv := " " + CCUI_Color( CCUI_Glyph( "v" ), CCUI_Pal( "dim" ) ) + " "
   nRows := Max( Len( aLeft ), Len( aRight ) )
   FOR i := 1 TO nRows
      hL := iif( i <= Len( aLeft ),  aLeft[ i ],  hBlank )
      hR := iif( i <= Len( aRight ), aRight[ i ], hBlank )
      AAdd( aOut, CCUI_PanelRow( hL, nLeftW ) + cDiv + CCUI_PanelRow( hR, nRightW ) )
   NEXT
   RETURN aOut
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: the new `ok   - ui: bannerjoin...` lines, `fail: 0`.

- [ ] **Step 5: Commit**

```bash
git add src/ccui.prg tests/test_ui.prg
git commit -m "feat: add CCUI_BannerJoin two-column banner helper"
```

### Task B4: rewrite `CCUI_Banner` as two panels

**Files:**
- Modify: `src/ccui.prg` (replace the body of `CCUI_Banner`, lines 471-522)
- Test: `tests/test_ui.prg`

- [ ] **Step 1: Write the failing test**

Add inside `Test_UI()` in `tests/test_ui.prg`:

```harbour
   // --- CCUI_Banner two-panel layout ---
   LOCAL cBan := CCUI_Banner( "test-model", "c:\proj", "Tester" )
   T_Assert( "Welcome back, Tester!" $ cBan, ;
             "ui: banner greets the user by name" )
   T_Assert( "Tips for getting started" $ cBan, ;
             "ui: banner shows the tips panel header" )
   T_Assert( "What's new" $ cBan, ;
             "ui: banner shows the what's-new header" )
   T_Assert( "model: test-model" $ cBan, ;
             "ui: banner shows the model" )
```

Add `LOCAL cBan` per the file's style.

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: `FAIL - ui: banner shows the tips panel header` (and the others) — the current single-panel banner has no tips panel.

- [ ] **Step 3: Replace `CCUI_Banner`**

In `src/ccui.prg`, replace the entire `CCUI_Banner` function (from `FUNCTION CCUI_Banner` through its `RETURN cOut`, lines 471-522) with:

```harbour
// Builds the two-panel startup banner inside one rounded box, 99 columns wide
// (matching the input frame). Left panel: a "Welcome back" line, the six-row
// block "CC" logo, the name+version and the model. Right panel: a "Tips for
// getting started" list and a "What's new" line from releasenotes.md. The
// shorter panel is blank-padded to equal height. Returns the banner ending in LF.
FUNCTION CCUI_Banner( cModel, cCwd, cUser )
   LOCAL nInner := 95, nLeftW := 44, nRightW := 48
   LOCAL cH := CCUI_Glyph( "h" ), cV, cName, aLogo, aLeft, aRight, aRows, cOut, i

   cModel := hb_CStr( cModel )
   cCwd   := hb_CStr( cCwd )
   cName  := AllTrim( hb_CStr( cUser ) )
   IF Empty( cName )
      cName := AllTrim( hb_CStr( hb_GetEnv( "USER" ) ) )
   ENDIF
   cV := CCUI_Color( CCUI_Glyph( "v" ), CCUI_Pal( "dim" ) )

   // the "CC" logo, six rows of block-drawing glyphs
   aLogo := { ;
      "  ██████╗ ██████╗ ", ;
      " ██╔════╝██╔════╝ ", ;
      " ██║     ██║      ", ;
      " ██║     ██║      ", ;
      " ╚██████╗╚██████╗ ", ;
      "  ╚═════╝ ╚═════╝ " }

   // left panel: welcome, logo (6), name+version, model
   aLeft := {}
   AAdd( aLeft, CCUI_Cell( iif( Empty( cName ), "Welcome back!", ;
                                "Welcome back, " + cName + "!" ), "C", "" ) )
   FOR i := 1 TO 6
      AAdd( aLeft, CCUI_Cell( aLogo[ i ], "C", "" ) )
   NEXT
   AAdd( aLeft, CCUI_Cell( "CCHarbour  v" + CCUI_Version(), "C", CCUI_Pal( "accent" ) ) )
   AAdd( aLeft, CCUI_Cell( "model: " + cModel, "C", "" ) )

   // right panel: tips list, divider, what's new (9 rows, matching the left)
   aRight := {}
   AAdd( aRight, CCUI_Cell( "Tips for getting started", "L", CCUI_Pal( "bold" ) ) )
   AAdd( aRight, CCUI_Cell( "", "L", "" ) )
   AAdd( aRight, CCUI_Cell( "Type a request to begin", "L", "" ) )
   AAdd( aRight, CCUI_Cell( "Run /help to list commands", "L", "" ) )
   AAdd( aRight, CCUI_Cell( "Run /init to create a CC.md file", "L", "" ) )
   AAdd( aRight, CCUI_Cell( Replicate( cH, nRightW ), "L", CCUI_Pal( "dim" ) ) )
   AAdd( aRight, CCUI_Cell( "What's new", "L", CCUI_Pal( "bold" ) ) )
   AAdd( aRight, CCUI_Cell( CCUI_WhatsNew(), "L", CCUI_Pal( "dim" ) ) )
   AAdd( aRight, CCUI_Cell( "cwd: " + cCwd, "L", CCUI_Pal( "dim" ) ) )

   aRows := CCUI_BannerJoin( aLeft, aRight, nLeftW, nRightW )

   cOut := CCUI_Color( CCUI_Glyph( "tl" ) + Replicate( cH, nInner + 2 ) + ;
           CCUI_Glyph( "tr" ), CCUI_Pal( "dim" ) ) + Chr(10)
   FOR i := 1 TO Len( aRows )
      cOut += cV + " " + aRows[ i ] + " " + cV + Chr(10)
   NEXT
   cOut += CCUI_Color( CCUI_Glyph( "bl" ) + Replicate( cH, nInner + 2 ) + ;
           CCUI_Glyph( "br" ), CCUI_Pal( "dim" ) ) + Chr(10)
   RETURN cOut
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: all four `ok   - ui: banner...` lines, `fail: 0`.

- [ ] **Step 5: Build the app and verify manually**

Run: `build.bat`, then `cc.exe`.
Expected: the startup banner is one rounded box with two panels side by side — left has "Welcome back, <you>!", the CC logo, version and model; right has "Tips for getting started", three tips, a divider, "What's new" and the first line of `releasenotes.md`. The box is 99 columns wide and the two panels are vertically aligned.

- [ ] **Step 6: Commit**

```bash
git add src/ccui.prg tests/test_ui.prg
git commit -m "feat: two-panel startup banner"
```

---

## Feature C — `ask_user` interactive question tool

### Task C1: `ccselect.prg` pure state helpers

**Files:**
- Create: `src/ccselect.prg`
- Modify: `cc.hbp`, `cc_linux.hbp`, `cc_mac.hbp`, `tests/tests.hbp`
- Create: `tests/test_select.prg`
- Modify: `tests/run_tests.prg`

- [ ] **Step 1: Create `src/ccselect.prg` with the pure helpers**

Create `src/ccselect.prg`:

```harbour
// ccselect: the interactive multiple-choice selector used by the ask_user
// tool. This file holds the pure state logic and the raw-key I/O loop. The
// block rendering (CCUI_QuestionBlock) lives in ccui.prg so it can reuse the
// static CCUI_PadCell helper.

// Builds a fresh selector state. aOptions is the list of answer strings; the
// literal "Other" is appended so the user is never boxed in. The cursor
// starts on the first option.
FUNCTION CCSEL_New( cQuestion, aOptions )
   LOCAL aOpts := {}, x
   IF ValType( aOptions ) == "A"
      FOR EACH x IN aOptions
         AAdd( aOpts, hb_CStr( x ) )
      NEXT
   ENDIF
   AAdd( aOpts, "Other" )
   RETURN { "question" => hb_CStr( cQuestion ), ;
            "options"  => aOpts, ;
            "cursor"   => 1 }

// Moves the cursor to nIndex, clamped to 1..Len(options). Returns oSel.
FUNCTION CCSEL_SetCursor( oSel, nIndex )
   LOCAL nMax := Len( oSel[ "options" ] )
   IF nIndex < 1
      nIndex := 1
   ELSEIF nIndex > nMax
      nIndex := nMax
   ENDIF
   oSel[ "cursor" ] := nIndex
   RETURN oSel

// Moves the cursor by nDelta rows, clamped. Returns oSel.
FUNCTION CCSEL_Move( oSel, nDelta )
   RETURN CCSEL_SetCursor( oSel, oSel[ "cursor" ] + nDelta )
```

- [ ] **Step 2: Register `ccselect.prg` in the four project files**

In `cc.hbp`, `cc_linux.hbp`, and `cc_mac.hbp`, add this line right after `src/ccprompt.prg`:

```
src/ccselect.prg
```

In `tests/tests.hbp`, add this line right after `../src/ccprompt.prg`:

```
../src/ccselect.prg
```

- [ ] **Step 3: Create `tests/test_select.prg` with the failing tests**

Create `tests/test_select.prg`:

```harbour
FUNCTION Test_Select()
   LOCAL oSel

   // --- CCSEL_New ---
   oSel := CCSEL_New( "Pick one", { "Red", "Green" } )
   T_Equal( oSel[ "question" ], "Pick one", "select: stores the question" )
   T_Equal( Len( oSel[ "options" ] ), 3, "select: appends Other to options" )
   T_Equal( oSel[ "options" ][ 3 ], "Other", "select: Other is last" )
   T_Equal( oSel[ "cursor" ], 1, "select: cursor starts at 1" )

   oSel := CCSEL_New( "Q", NIL )
   T_Equal( Len( oSel[ "options" ] ), 1, "select: nil options -> just Other" )

   // --- CCSEL_SetCursor clamps ---
   oSel := CCSEL_New( "Q", { "A", "B" } )   // 3 options with Other
   CCSEL_SetCursor( oSel, 2 )
   T_Equal( oSel[ "cursor" ], 2, "select: set cursor in range" )
   CCSEL_SetCursor( oSel, 99 )
   T_Equal( oSel[ "cursor" ], 3, "select: set cursor clamps to max" )
   CCSEL_SetCursor( oSel, -5 )
   T_Equal( oSel[ "cursor" ], 1, "select: set cursor clamps to min" )

   // --- CCSEL_Move clamps ---
   oSel := CCSEL_New( "Q", { "A", "B" } )
   CCSEL_Move( oSel, 1 )
   T_Equal( oSel[ "cursor" ], 2, "select: move down" )
   CCSEL_Move( oSel, -1 )
   T_Equal( oSel[ "cursor" ], 1, "select: move up" )
   CCSEL_Move( oSel, -1 )
   T_Equal( oSel[ "cursor" ], 1, "select: move up stops at top" )
   CCSEL_Move( oSel, 99 )
   T_Equal( oSel[ "cursor" ], 3, "select: move down stops at bottom" )

   RETURN NIL
```

- [ ] **Step 4: Register the test in `tests/run_tests.prg`**

In `tests/run_tests.prg`, add a call inside `Main()`, right after `Test_Prompt()`:

```harbour
   Test_Select()
```

And add `test_select.prg` to `tests/tests.hbp`, right after `test_prompt.prg`:

```
test_select.prg
```

- [ ] **Step 5: Run the tests to verify they fail**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: build error or `FAIL` lines if the helper bodies are wrong. With the implementation from Step 1 present, the tests should actually pass — in that case confirm the test file is genuinely exercising new code by temporarily breaking `CCSEL_New` (skip appending `"Other"`), seeing `FAIL - select: appends Other to options`, then restoring it.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: all `ok   - select: ...` lines, `fail: 0`.

- [ ] **Step 7: Commit**

```bash
git add src/ccselect.prg tests/test_select.prg tests/run_tests.prg tests/tests.hbp cc.hbp cc_linux.hbp cc_mac.hbp
git commit -m "feat: add ccselect pure state helpers"
```

### Task C2: `CCUI_QuestionBlock` — render the question block

**Files:**
- Modify: `src/ccui.prg` (add near the banner helpers)
- Test: `tests/test_ui.prg`

- [ ] **Step 1: Write the failing test**

Add inside `Test_UI()` in `tests/test_ui.prg`:

```harbour
   // --- CCUI_QuestionBlock ---
   LOCAL oQ := CCSEL_New( "Choose a colour", { "Red", "Green" } )
   LOCAL cQB := CCUI_QuestionBlock( oQ )
   T_Assert( "Choose a colour" $ cQB, "ui: question block shows the question" )
   T_Assert( "1. Red" $ cQB, "ui: question block numbers options" )
   T_Assert( "3. Other" $ cQB, "ui: question block lists Other" )
   T_Equal( Len( hb_ATokens( cQB, Chr(10) ) ), 5, ;
            "ui: question block is question + 3 options + trailing line" )
```

Add `LOCAL oQ, cQB` per the file's style. (`hb_ATokens` on a string ending in `Chr(10)` yields one trailing empty token, so 4 content lines produce 5 tokens.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: build/link error or `FAIL` — `CCUI_QuestionBlock` does not exist.

- [ ] **Step 3: Add the implementation**

Add to `src/ccui.prg`, after `CCUI_BannerJoin`:

```harbour
// Renders a CCSEL selector state to a printable block: a "●" bullet and the
// question, then one numbered row per option. The row at the cursor is marked
// with a "❯" arrow and inverse video; other rows get two leading spaces.
// Each line ends in LF. Pure -- no console I/O.
FUNCTION CCUI_QuestionBlock( oSel )
   LOCAL cOut, i, aOpts := oSel[ "options" ], cRow
   LOCAL cBullet := Chr(226) + Chr(151) + Chr(143)   // U+25CF ●
   LOCAL cArrow  := Chr(226) + Chr(157) + Chr(175)   // U+276F ❯
   cOut := CCUI_Color( cBullet, CCUI_Pal( "accent" ) ) + " " + ;
           CCUI_Color( oSel[ "question" ], CCUI_Pal( "bold" ) ) + Chr(10)
   FOR i := 1 TO Len( aOpts )
      cRow := iif( i == oSel[ "cursor" ], cArrow + " ", "  " ) + ;
              LTrim( Str( i ) ) + ". " + aOpts[ i ]
      IF i == oSel[ "cursor" ]
         cRow := CCUI_Color( cRow, "7" )   // inverse video
      ENDIF
      cOut += cRow + Chr(10)
   NEXT
   RETURN cOut
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: the new `ok   - ui: question block...` lines, `fail: 0`.

- [ ] **Step 5: Commit**

```bash
git add src/ccui.prg tests/test_ui.prg
git commit -m "feat: add CCUI_QuestionBlock renderer"
```

### Task C3: `CCSEL_Run` — the interactive key loop

**Files:**
- Modify: `src/ccselect.prg` (add the I/O functions)

These functions drive raw console I/O and are verified by manual run (Task C5), not unit-tested.

- [ ] **Step 1: Add the I/O functions to `src/ccselect.prg`**

Append to `src/ccselect.prg`:

```harbour
// Writes bytes straight to stdout, bypassing CCREPL_Out's line rewriting --
// needed for absolute cursor positioning.
STATIC FUNCTION CCSEL_Raw( cText )
   FWrite( hb_GetStdOut(), cText )
   RETURN NIL

// Paints the question block. On a repaint, first moves the cursor up over the
// previous block (question line + one line per option) so the new block
// overwrites it. Every row is a constant display width across repaints -- only
// the marker and inverse video change -- so no explicit clearing is needed.
STATIC FUNCTION CCSEL_Paint( oSel, lRepaint )
   LOCAL nLines := Len( oSel[ "options" ] ) + 1
   IF lRepaint
      CCSEL_Raw( Chr(27) + "[" + LTrim( Str( nLines ) ) + "A" )
   ENDIF
   CCSEL_Raw( CCUI_QuestionBlock( oSel ) )
   RETURN NIL

// Reads a free-text answer for the "Other" option: prints a prompt, then
// collects printable characters until Enter. Backspace deletes the last char.
STATIC FUNCTION CCSEL_ReadOther()
   LOCAL cBuf := "", nKey
   CCSEL_Raw( Chr(10) + "Other (type your answer, Enter to confirm): " )
   DO WHILE .T.
      DO WHILE !CCCON_KeyPending()
         hb_idleSleep( 0.02 )
      ENDDO
      nKey := CCCON_ReadKey()
      DO CASE
      CASE nKey == -1                       // Enter -> done
         EXIT
      CASE nKey == -2                       // Backspace
         IF !Empty( cBuf )
            cBuf := hb_UTF8SubStr( cBuf, 1, hb_UTF8Len( cBuf ) - 1 )
            CCSEL_Raw( Chr(8) + " " + Chr(8) )
         ENDIF
      CASE nKey > 0                         // a printable character
         cBuf += CCIN_Utf8Chr( nKey )
         CCSEL_Raw( CCIN_Utf8Chr( nKey ) )
      ENDCASE
   ENDDO
   CCSEL_Raw( Chr(10) )
   RETURN AllTrim( cBuf )

// Runs the selector interactively and returns the chosen answer string.
// Up/Down move the highlight, a digit key (1-9) jumps to and selects that
// option, Enter confirms the highlighted option. Choosing "Other" drops to a
// free-text prompt. With no console (piped input) it cannot prompt, so it
// returns the first option as a default.
FUNCTION CCSEL_Run( oSel )
   LOCAL nKey, cAnswer, lDone := .F.
   IF !CCCON_HasConsole()
      RETURN oSel[ "options" ][ 1 ]
   ENDIF
   CCSEL_Paint( oSel, .F. )
   DO WHILE !lDone
      DO WHILE !CCCON_KeyPending()
         hb_idleSleep( 0.02 )
      ENDDO
      nKey := CCCON_ReadKey()
      DO CASE
      CASE nKey == -9                       // Up
         CCSEL_Move( oSel, -1 )
      CASE nKey == -10                      // Down
         CCSEL_Move( oSel, 1 )
      CASE nKey >= 49 .AND. nKey <= 57      // digit 1-9 -> jump and select
         CCSEL_SetCursor( oSel, nKey - 48 )
         lDone := .T.
      CASE nKey == -1                       // Enter -> confirm
         lDone := .T.
      ENDCASE
      IF !lDone
         CCSEL_Paint( oSel, .T. )
      ENDIF
   ENDDO
   cAnswer := oSel[ "options" ][ oSel[ "cursor" ] ]
   IF cAnswer == "Other"
      cAnswer := CCSEL_ReadOther()
   ENDIF
   RETURN cAnswer
```

`CCIN_Utf8Chr` is the existing helper from `ccinput.prg` that converts a key code to its UTF-8 character (used the same way in `CCPROMPT_Poll`).

- [ ] **Step 2: Build the app to confirm it compiles**

Run: `build.bat`
Expected: build succeeds. (Behaviour is verified in Task C5 once the tool is wired up.)

- [ ] **Step 3: Commit**

```bash
git add src/ccselect.prg
git commit -m "feat: add CCSEL_Run interactive selector loop"
```

### Task C4: `ask_user` tool and permission bypass

**Files:**
- Create: `src/cctools_ask.prg`
- Modify: `cc.hbp`, `cc_linux.hbp`, `cc_mac.hbp`, `tests/tests.hbp`
- Modify: `src/cctools.prg` (register the tool)
- Modify: `src/ccperm.prg` (bypass the gate for `ask_user`)
- Modify: `src/ccui.prg` (`CCUI_Help` — list the new tool's nothing; no change needed)

- [ ] **Step 1: Create `src/cctools_ask.prg`**

Create `src/cctools_ask.prg`:

```harbour
// ask_user: asks the user a multiple-choice question through an interactive
// selector and returns their chosen answer to the model.
FUNCTION CCTool_AskUser()
   RETURN { "name" => "ask_user", ;
            "description" => "Ask the user a multiple-choice question and " + ;
               "return their selected answer. Use this when you need the " + ;
               "user to make a decision before continuing. Provide 2 to 4 " + ;
               "short, distinct options.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "question" => { "type" => "string", ;
                                  "description" => "The question to ask the user" }, ;
                  "options" => { "type" => "array", ;
                                 "items" => { "type" => "string" }, ;
                                 "description" => "2 to 4 answer choices" } }, ;
               "required" => { "question", "options" } }, ;
            "handler" => {| hArgs | CCTool_AskUserRun( hArgs ) } }

STATIC FUNCTION CCTool_AskUserRun( hArgs )
   LOCAL oSel, cAnswer
   IF ValType( hArgs[ "options" ] ) != "A" .OR. Len( hArgs[ "options" ] ) < 2
      RETURN "Error: 'options' must be an array of at least 2 strings"
   ENDIF
   oSel := CCSEL_New( hb_CStr( hArgs[ "question" ] ), hArgs[ "options" ] )
   cAnswer := CCSEL_Run( oSel )
   RETURN "The user selected: " + cAnswer
```

- [ ] **Step 2: Register `cctools_ask.prg` in the four project files**

In `cc.hbp`, `cc_linux.hbp`, and `cc_mac.hbp`, add this line right after `src/cctools_memory.prg`:

```
src/cctools_ask.prg
```

In `tests/tests.hbp`, add this line right after `../src/cctools_memory.prg`:

```
../src/cctools_ask.prg
```

- [ ] **Step 3: Register the tool in the registry**

In `src/cctools.prg`, in `CCTOOLS_Registry`, add this line right after the `CCTool_Memory` registration:

```harbour
   CCTOOLS_Register( oReg, CCTool_AskUser() )
```

- [ ] **Step 4: Bypass the permission gate for `ask_user`**

In `src/ccperm.prg`, in `CCPERM_Decide`, add a bypass at the very top of the function body, before `cMode := ...`:

```harbour
   // asking the user a question is inherently consented -- never gated
   IF cName == "ask_user"
      RETURN Eval( bInner, cName, cArgsJson )
   ENDIF
```

- [ ] **Step 5: Add a test that the tool is registered**

In `tests/test_tools.prg`, inside `Test_Tools()`, add (place it near other registry assertions — search the file for `CCTOOLS_Registry` to find them):

```harbour
   T_Assert( hb_HHasKey( CCTOOLS_Registry(), "ask_user" ), ;
             "tools: ask_user is registered" )
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `tests\build_tests.bat` then `tests\run_tests.exe`
Expected: `ok   - tools: ask_user is registered`, `fail: 0`. (A link error here usually means a project file from Step 2 was missed.)

- [ ] **Step 7: Commit**

```bash
git add src/cctools_ask.prg src/cctools.prg src/ccperm.prg tests/test_tools.prg tests/tests.hbp cc.hbp cc_linux.hbp cc_mac.hbp
git commit -m "feat: add ask_user agent tool"
```

### Task C5: end-to-end manual verification

**Files:** none — verification only.

- [ ] **Step 1: Build the app**

Run: `build.bat`
Expected: build succeeds.

- [ ] **Step 2: Verify the selector**

Run `cc.exe`. Ask the model something that forces a decision, e.g. *"Ask me whether to use tabs or spaces, then say which I picked."* The model should call `ask_user`. Confirm:
- The question renders with a `●` bullet and numbered options plus a final `Other`.
- Up/Down moves the highlighted row (inverse video, `❯` marker), repainting in place.
- Pressing a digit jumps to and immediately selects that option.
- Enter confirms the highlighted option.
- Choosing `Other` shows the free-text prompt; the typed text becomes the answer.
- After selection the model receives and reports the chosen answer.
- The persistent input box is still intact at the bottom afterwards.

- [ ] **Step 3: Commit (only if Step 2 required fixes)**

```bash
git add -A
git commit -m "fix: ask_user selector manual-test corrections"
```

---

## Documentation

### Task D1: update the README and help text

**Files:**
- Modify: `src/ccui.prg` (`CCUI_Help` — no new command, no change required; confirm only)
- Modify: `README.md` (Tools section — add `ask_user`)

- [ ] **Step 1: Add `ask_user` to the README Tools section**

In `README.md`, find the Tools section (added in commit `57f8d78`). Add an entry describing `ask_user` consistent with the existing entries' wording and format: a tool that asks the user a multiple-choice question and returns the selected answer. Update any tool count in the surrounding prose (e.g. "eleven tools" becomes "twelve tools").

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document the ask_user tool"
```

---

## Self-Review notes

- **Spec coverage:** A → Tasks A1-A2. B → Tasks B1-B4. C → Tasks C1-C5. Docs → D1. Every spec section maps to a task.
- **Type consistency:** the cell hash `{ text, align, sgr }` is produced by `CCUI_Cell` and consumed by `CCUI_PanelRow`/`CCUI_BannerJoin`. The selector state `{ question, options, cursor }` is produced by `CCSEL_New` and consumed by `CCSEL_SetCursor`/`CCSEL_Move`/`CCSEL_Run`/`CCUI_QuestionBlock`. Names are consistent across tasks.
- **Known soft spot:** `CCSEL_Paint`'s in-place repaint assumes the question block fits within the visible scroll region and that the cursor sits directly below the block between keypresses. If manual testing (C5) shows drift, the fix is local to `CCSEL_Paint`/`CCSEL_Run` — adjust there.
```

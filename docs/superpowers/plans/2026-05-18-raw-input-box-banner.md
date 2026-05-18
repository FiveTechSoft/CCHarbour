# Raw-mode Input Box and Banner Logo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace cc.exe's cooked-mode main prompt with a raw-mode single-line input box that has side borders and full in-line editing, and give the startup banner a "CC" logo and a version.

**Architecture:** A new `src/dsinput.prg` holds the editor (pure buffer-state operations + a thin raw-mode I/O loop). `src/dsconsole.c` gains raw key reading. `src/dsrepl.prg` calls the editor for an interactive console and falls back to the cooked reader for piped input. `src/dsui.prg` gets the banner logo and a version function.

**Tech Stack:** Harbour, the Windows console API (C extension). `src/dsui.prg` and the pure parts of `src/dsinput.prg` are unit-tested; the C extension and the raw I/O loop are verified by `build.bat` + manual smoke test.

**Spec:** `docs/superpowers/specs/2026-05-18-raw-input-box-banner-design.md`

---

## Build & test commands

- Build cc.exe: `build.bat` from the repo root → `Build OK -> cc.exe`.
- Build the test runner: from `tests/`, `call` the MSVC `vcvars64.bat` (e.g. `C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat`), then `set "HB_USER_CFLAGS=-MD"`, `set "HB_USER_LDFLAGS=/NODEFAULTLIB:libcmt.lib /NODEFAULTLIB:libucrt.lib /NODEFAULTLIB:libvcruntime.lib msvcrt.lib ucrt.lib vcruntime.lib"`, then `"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp` (`tests/build_tests.bat` has a bug — if it fails, write your own .bat). Run `run_tests.exe` from `tests/`; last line `pass: N   fail: M`, fail must be 0.

---

## Task 1: Raw console key reading in `dsconsole.c`

**Files:**
- Modify: `src/dsconsole.c`

This task only ADDS C functions — `DSCON_PrefillInput` stays for now (removed in Task 4 together with its caller). No unit test; verified by `build.bat`.

- [ ] **Step 1: Add the three console functions**

In `src/dsconsole.c`, after the existing `DSCON_PREFILLINPUT` function, add:

```c
/* Raw-mode console input for the CCHarbour line editor. */

/* DSCON_HasConsole() -> .T. when stdin is a real interactive console. */
HB_FUNC( DSCON_HASCONSOLE )
{
   DWORD mode;
   HANDLE h = GetStdHandle( STD_INPUT_HANDLE );
   hb_retl( h != INVALID_HANDLE_VALUE && h != NULL && GetConsoleMode( h, &mode ) );
}

static DWORD    s_dscon_savedMode = 0;
static HB_BOOL  s_dscon_modeSaved = HB_FALSE;

/* DSCON_RawMode( lOn ) -- lOn .T. disables line-input/echo/processed-input on
 * the console (so keystrokes and Ctrl+C arrive as raw events); .F. restores
 * the previously saved mode. Returns .T. on success, .F. on any failure. */
HB_FUNC( DSCON_RAWMODE )
{
   HB_BOOL fOn = hb_parl( 1 );
   HANDLE  h   = GetStdHandle( STD_INPUT_HANDLE );
   HB_BOOL fOk = HB_FALSE;

   if( h != INVALID_HANDLE_VALUE && h != NULL )
   {
      if( fOn )
      {
         DWORD mode;
         if( GetConsoleMode( h, &mode ) )
         {
            s_dscon_savedMode = mode;
            s_dscon_modeSaved = HB_TRUE;
            mode &= ~( ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT );
            if( SetConsoleMode( h, mode ) )
               fOk = HB_TRUE;
         }
      }
      else if( s_dscon_modeSaved )
      {
         if( SetConsoleMode( h, s_dscon_savedMode ) )
            fOk = HB_TRUE;
      }
   }

   hb_retl( fOk );
}

/* DSCON_ReadKey() -- blocks for one key-down event and returns an int:
 *   > 0  the Unicode codepoint of a printable character
 *     0  end of input
 *    -1 Enter  -2 Backspace  -3 Left  -4 Right  -5 Home  -6 End
 *    -7 Delete  -8 Ctrl+C   -99 an unmapped key (caller ignores it). */
HB_FUNC( DSCON_READKEY )
{
   HANDLE       h = GetStdHandle( STD_INPUT_HANDLE );
   INPUT_RECORD rec;
   DWORD        nRead;
   int          result = -99;
   HB_BOOL      done = HB_FALSE;

   if( h == INVALID_HANDLE_VALUE || h == NULL )
   {
      hb_retni( 0 );
      return;
   }

   while( ! done )
   {
      if( ! ReadConsoleInputW( h, &rec, 1, &nRead ) || nRead == 0 )
      {
         result = 0;
         break;
      }
      if( rec.EventType != KEY_EVENT || ! rec.Event.KeyEvent.bKeyDown )
         continue;
      {
         WORD  vk   = rec.Event.KeyEvent.wVirtualKeyCode;
         WCHAR ch   = rec.Event.KeyEvent.uChar.UnicodeChar;
         DWORD cks  = rec.Event.KeyEvent.dwControlKeyState;
         HB_BOOL ctrl = ( cks & ( LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED ) ) != 0;

         if( ctrl && vk == 'C' )         { result = -8; done = HB_TRUE; }
         else if( vk == VK_RETURN )      { result = -1; done = HB_TRUE; }
         else if( vk == VK_BACK )        { result = -2; done = HB_TRUE; }
         else if( vk == VK_LEFT )        { result = -3; done = HB_TRUE; }
         else if( vk == VK_RIGHT )       { result = -4; done = HB_TRUE; }
         else if( vk == VK_HOME )        { result = -5; done = HB_TRUE; }
         else if( vk == VK_END )         { result = -6; done = HB_TRUE; }
         else if( vk == VK_DELETE )      { result = -7; done = HB_TRUE; }
         else if( ch >= 32 )             { result = ( int ) ch; done = HB_TRUE; }
         /* else: a non-printable key with no mapping -> read the next event */
      }
   }

   hb_retni( result );
}
```

- [ ] **Step 2: Build**

Run `build.bat` from the repo root.
Expected: `Build OK -> cc.exe` — `dsconsole.c` compiles with the three new functions.

- [ ] **Step 3: Commit**

```bash
git add src/dsconsole.c
git commit -m "feat: raw console key reading for the line editor"
```

---

## Task 2: Editor buffer operations — `dsinput.prg`

**Files:**
- Create: `src/dsinput.prg`
- Create: `tests/test_input.prg`
- Modify: `cc.hbp`, `tests/tests.hbp`, `tests/run_tests.prg`

This task adds only the pure, unit-tested operations. The raw I/O loop is Task 3.

- [ ] **Step 1: Wire the new files into the build and test harness**

In `cc.hbp`, add `src/dsinput.prg` on the line after `src/dsmarkdown.prg`.

In `tests/tests.hbp`: add `test_input.prg` on the line after `test_markdown.prg`, and add `../src/dsinput.prg` on the line after `../src/dsmarkdown.prg`.

In `tests/run_tests.prg`, in `Main()`, add a call to `Test_Input()` immediately after the existing `Test_Markdown()` call.

- [ ] **Step 2: Write the failing test**

Create `tests/test_input.prg`:

```harbour
FUNCTION Test_Input()
   LOCAL oSt, hW

   // new state: cursor at the end of the initial text
   oSt := DSIN_New( "abc" )
   T_Equal( oSt[ "buf" ], "abc", "input: new keeps initial buf" )
   T_Equal( oSt[ "cursor" ], 3, "input: new cursor at end" )

   // insert at the cursor
   oSt := DSIN_New( "" )
   DSIN_Insert( oSt, "x" )
   DSIN_Insert( oSt, "y" )
   T_Equal( oSt[ "buf" ], "xy", "input: insert appends" )
   T_Equal( oSt[ "cursor" ], 2, "input: insert advances cursor" )

   // insert in the middle
   oSt := DSIN_New( "ac" )
   DSIN_Left( oSt )
   DSIN_Insert( oSt, "b" )
   T_Equal( oSt[ "buf" ], "abc", "input: insert mid-buffer" )

   // backspace
   oSt := DSIN_New( "abc" )
   DSIN_Backspace( oSt )
   T_Equal( oSt[ "buf" ], "ab", "input: backspace removes before cursor" )
   oSt := DSIN_New( "abc" )
   DSIN_Home( oSt )
   DSIN_Backspace( oSt )
   T_Equal( oSt[ "buf" ], "abc", "input: backspace at start is a no-op" )

   // delete
   oSt := DSIN_New( "abc" )
   DSIN_Home( oSt )
   DSIN_Delete( oSt )
   T_Equal( oSt[ "buf" ], "bc", "input: delete removes at cursor" )
   oSt := DSIN_New( "abc" )
   DSIN_Delete( oSt )
   T_Equal( oSt[ "buf" ], "abc", "input: delete at end is a no-op" )

   // cursor movement clamps
   oSt := DSIN_New( "ab" )
   DSIN_Left( oSt ) ; DSIN_Left( oSt ) ; DSIN_Left( oSt )
   T_Equal( oSt[ "cursor" ], 0, "input: left clamps at 0" )
   DSIN_Right( oSt ) ; DSIN_Right( oSt ) ; DSIN_Right( oSt )
   T_Equal( oSt[ "cursor" ], 2, "input: right clamps at len" )
   DSIN_Home( oSt )
   T_Equal( oSt[ "cursor" ], 0, "input: home" )
   DSIN_End( oSt )
   T_Equal( oSt[ "cursor" ], 2, "input: end" )

   // window: buffer fits -> whole buffer
   oSt := DSIN_New( "hello" )
   hW := DSIN_Window( oSt, 73 )
   T_Equal( hW[ "text" ], "hello", "input: window fits -> whole buffer" )
   T_Equal( hW[ "col" ], 5, "input: window fits -> cursor col" )

   // window: buffer wider than width -> scrolls, cursor stays visible
   oSt := DSIN_New( Replicate( "x", 100 ) )
   hW := DSIN_Window( oSt, 73 )
   T_Equal( Len( hW[ "text" ] ), 73, "input: window scrolled width" )
   T_Equal( hW[ "col" ], 73, "input: window scrolled cursor col" )

   // utf-8 codepoint -> char
   T_Equal( DSIN_Utf8Chr( 65 ), "A", "input: utf8chr ascii" )
   T_Equal( DSIN_Utf8Chr( 233 ), Chr(195)+Chr(169), "input: utf8chr 2-byte (e-acute)" )

   RETURN NIL
```

- [ ] **Step 3: Run test to verify it fails**

Build and run the test runner.
Expected: FAIL — `DSIN_New` and the other `DSIN_*` functions are undefined.

- [ ] **Step 4: Write minimal implementation**

Create `src/dsinput.prg`:

```harbour
// Raw-mode single-line input editor for the main prompt. This file holds the
// pure buffer-state operations; the raw-mode I/O loop (DSIN_ReadLine) is added
// in a later task. State: { "buf" => <utf-8 text>, "cursor" => <char index> }.
// All operations count UTF-8 characters, not bytes.

// A fresh editor state, cursor at the end of the initial text.
FUNCTION DSIN_New( cInitial )
   cInitial := hb_CStr( cInitial )
   RETURN { "buf" => cInitial, "cursor" => hb_UTF8Len( cInitial ) }

// Inserts cChar at the cursor and advances the cursor.
FUNCTION DSIN_Insert( oSt, cChar )
   LOCAL n := oSt[ "cursor" ], cBuf := oSt[ "buf" ]
   oSt[ "buf" ] := hb_UTF8SubStr( cBuf, 1, n ) + cChar + ;
                   hb_UTF8SubStr( cBuf, n + 1, hb_UTF8Len( cBuf ) - n )
   oSt[ "cursor" ] := n + 1
   RETURN oSt

// Deletes the character before the cursor; moves the cursor back. No-op at 0.
FUNCTION DSIN_Backspace( oSt )
   LOCAL n := oSt[ "cursor" ], cBuf := oSt[ "buf" ]
   IF n > 0
      oSt[ "buf" ] := hb_UTF8SubStr( cBuf, 1, n - 1 ) + ;
                      hb_UTF8SubStr( cBuf, n + 1, hb_UTF8Len( cBuf ) - n )
      oSt[ "cursor" ] := n - 1
   ENDIF
   RETURN oSt

// Deletes the character at the cursor. No-op at the end.
FUNCTION DSIN_Delete( oSt )
   LOCAL n := oSt[ "cursor" ], cBuf := oSt[ "buf" ], nLen := hb_UTF8Len( oSt[ "buf" ] )
   IF n < nLen
      oSt[ "buf" ] := hb_UTF8SubStr( cBuf, 1, n ) + ;
                      hb_UTF8SubStr( cBuf, n + 2, nLen - n - 1 )
   ENDIF
   RETURN oSt

// Cursor movement, all clamped to [0, len].
FUNCTION DSIN_Left( oSt )
   IF oSt[ "cursor" ] > 0
      oSt[ "cursor" ] := oSt[ "cursor" ] - 1
   ENDIF
   RETURN oSt

FUNCTION DSIN_Right( oSt )
   IF oSt[ "cursor" ] < hb_UTF8Len( oSt[ "buf" ] )
      oSt[ "cursor" ] := oSt[ "cursor" ] + 1
   ENDIF
   RETURN oSt

FUNCTION DSIN_Home( oSt )
   oSt[ "cursor" ] := 0
   RETURN oSt

FUNCTION DSIN_End( oSt )
   oSt[ "cursor" ] := hb_UTF8Len( oSt[ "buf" ] )
   RETURN oSt

// Returns { "text" => <slice that fits nWidth columns>, "col" => <cursor
// column within the slice> }. When the buffer fits, the slice is the whole
// buffer. When it is wider, it scrolls so the cursor stays visible.
FUNCTION DSIN_Window( oSt, nWidth )
   LOCAL nLen := hb_UTF8Len( oSt[ "buf" ] ), nCur := oSt[ "cursor" ], nOff
   IF nLen <= nWidth
      RETURN { "text" => oSt[ "buf" ], "col" => nCur }
   ENDIF
   nOff := iif( nCur > nWidth, nCur - nWidth, 0 )
   RETURN { "text" => hb_UTF8SubStr( oSt[ "buf" ], nOff + 1, nWidth ), ;
            "col" => nCur - nOff }

// Encodes a Unicode codepoint (BMP) as a UTF-8 character string.
FUNCTION DSIN_Utf8Chr( n )
   DO CASE
   CASE n < 128
      RETURN Chr( n )
   CASE n < 2048
      RETURN Chr( hb_bitOr( 192, hb_bitShift( n, -6 ) ) ) + ;
             Chr( hb_bitOr( 128, hb_bitAnd( n, 63 ) ) )
   OTHERWISE
      RETURN Chr( hb_bitOr( 224, hb_bitShift( n, -12 ) ) ) + ;
             Chr( hb_bitOr( 128, hb_bitAnd( hb_bitShift( n, -6 ), 63 ) ) ) + ;
             Chr( hb_bitOr( 128, hb_bitAnd( n, 63 ) ) )
   ENDCASE
   RETURN ""
```

- [ ] **Step 5: Run test to verify it passes**

Build and run the test runner.
Expected: PASS — all `input:` assertions pass, `fail: 0`, no regressions.

- [ ] **Step 6: Commit**

```bash
git add src/dsinput.prg tests/test_input.prg cc.hbp tests/tests.hbp tests/run_tests.prg
git commit -m "feat: input editor buffer operations"
```

---

## Task 3: Input-box rendering helper + the raw I/O loop

**Files:**
- Modify: `src/dsui.prg`
- Modify: `src/dsinput.prg`
- Modify: `tests/tests.hbp`
- Test: `tests/test_ui.prg`

- [ ] **Step 1: Write the failing test for the box-line helper**

Append inside `Test_UI()` in `tests/test_ui.prg`, before its `RETURN NIL`:

```harbour
   // input box: inner width and the framed prompt line
   DSUI_SetColor( .F. )
   T_Equal( DSUI_InputInnerWidth(), 73, "ui: input inner width" )
   T_Equal( hb_UTF8Len( DSUI_InputBoxLine( "hi" ) ), 79, "ui: input box line is 79 columns" )
   T_Assert( "> hi" $ DSUI_InputBoxLine( "hi" ), "ui: input box line has the prompt + text" )
   T_Assert( DSUI_Glyph( "v" ) $ DSUI_InputBoxLine( "hi" ), "ui: input box line has side borders" )
```

- [ ] **Step 2: Run test to verify it fails**

Build and run the test runner.
Expected: FAIL — `DSUI_InputInnerWidth` / `DSUI_InputBoxLine` undefined.

- [ ] **Step 3: Add the box-line helpers to `dsui.prg`**

In `src/dsui.prg`, add these two functions directly after `DSUI_InputHint()`:

```harbour
// The text-column width available inside the input box (79 total: 2 borders,
// 2 inside spaces, the "> " prompt = 6 of overhead, leaving 73).
FUNCTION DSUI_InputInnerWidth()
   RETURN 73

// One framed input-box prompt line: side borders, the "> " prompt, and cText
// padded (or truncated) to the inner width. 79 display columns wide.
FUNCTION DSUI_InputBoxLine( cText )
   LOCAL cV := DSUI_Color( DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) )
   RETURN cV + " " + DSUI_Color( "> ", "1;36" ) + ;
          DSUI_PadCell( hb_CStr( cText ), DSUI_InputInnerWidth(), "L" ) + ;
          " " + cV
```

- [ ] **Step 4: Run test to verify it passes**

Build and run the test runner.
Expected: PASS — the `ui: input ...` assertions pass, `fail: 0`.

Note: `DSUI_InputBoxLine` is checked with `hb_UTF8Len` for 79 columns — with colour off there are no ANSI codes, so the count is the corner/border glyphs (1 each) + spaces + `> ` + the 73-column padded cell = 79.

- [ ] **Step 5: Add the raw I/O loop to `dsinput.prg`**

`src/dsinput.prg` calls the `DSCON_*` functions from `src/dsconsole.c`, so the test build must link that C file. In `tests/tests.hbp`, add `../src/dsconsole.c` on the line after `../src/dsinput.prg`.

Then append to `src/dsinput.prg`:

```harbour
// Reads one line through the raw-mode input box. cInitial pre-fills the buffer
// (the suggested next prompt). Returns the typed string, or NIL on Ctrl-C /
// end of input. Returns the sentinel hash { "no_console" => .T. } when there
// is no interactive console, so the caller can fall back to a cooked reader.
FUNCTION DSIN_ReadLine( cInitial )
   LOCAL oSt, nKey, hW, cResult := NIL, lDone := .F.

   IF !DSCON_RawMode( .T. )
      RETURN { "no_console" => .T. }
   ENDIF

   oSt := DSIN_New( hb_CStr( cInitial ) )

   // draw the box: top border, prompt line, bottom border, hint; then move
   // the cursor up onto the prompt line (hint -> bottom -> prompt = up 2).
   hW := DSIN_Window( oSt, DSUI_InputInnerWidth() )
   DSREPL_Out( Chr(10) + DSUI_FrameTop() + Chr(10) + ;
               DSUI_InputBoxLine( hW[ "text" ] ) + Chr(10) + ;
               DSUI_FrameBottom() + Chr(10) + ;
               DSUI_InputHint() + DSUI_VT( "2A" ) )

   DO WHILE !lDone
      // place the terminal cursor at the editing column: column 1 is the
      // left border, then a space, then "> " -> text starts at column 5.
      hW := DSIN_Window( oSt, DSUI_InputInnerWidth() )
      DSREPL_Out( DSUI_VT( "1G" ) + ;
                  DSUI_VT( LTrim( Str( 5 + hW[ "col" ] ) ) + "G" ) )
      nKey := DSCON_ReadKey()
      DO CASE
      CASE nKey == 0 .OR. nKey == -8     // EOF or Ctrl-C
         cResult := NIL
         lDone := .T.
      CASE nKey == -1                    // Enter
         cResult := oSt[ "buf" ]
         lDone := .T.
      CASE nKey == -2                    // Backspace
         DSIN_Backspace( oSt )
      CASE nKey == -3                    // Left
         DSIN_Left( oSt )
      CASE nKey == -4                    // Right
         DSIN_Right( oSt )
      CASE nKey == -5                    // Home
         DSIN_Home( oSt )
      CASE nKey == -6                    // End
         DSIN_End( oSt )
      CASE nKey == -7                    // Delete
         DSIN_Delete( oSt )
      CASE nKey > 0                      // a printable character
         DSIN_Insert( oSt, DSIN_Utf8Chr( nKey ) )
      // nKey == -99 (an unmapped key) falls through and is ignored
      ENDCASE
      // redraw the prompt line in place
      hW := DSIN_Window( oSt, DSUI_InputInnerWidth() )
      DSREPL_Out( DSUI_VT( "1G" ) + DSUI_InputBoxLine( hW[ "text" ] ) )
   ENDDO

   DSCON_RawMode( .F. )
   // step the cursor below the box (prompt -> bottom -> hint -> next line)
   DSREPL_Out( DSUI_VT( "2B" ) + Chr(10) )
   RETURN cResult
```

Note: `DSREPL_Out` and `DSUI_VT`/`DSUI_FrameTop`/`DSUI_FrameBottom`/`DSUI_InputHint` already exist. `DSREPL_Out` is a `STATIC FUNCTION` in `src/dsrepl.prg` — it is NOT visible from `dsinput.prg`. Therefore: in `src/dsrepl.prg`, change `DSREPL_Out`'s declaration from `STATIC FUNCTION DSREPL_Out(` to `FUNCTION DSREPL_Out(` (make it public) so `dsinput.prg` can call it. Change only that one keyword.

- [ ] **Step 6: Build and verify**

Run `build.bat` from the repo root. Expected: `Build OK -> cc.exe`.
Build and run the test runner. Expected: `fail: 0` (the test build now links `dsconsole.c`; `dsinput.prg`'s pure-op tests still pass; nothing calls the I/O loop in tests).

- [ ] **Step 7: Commit**

```bash
git add src/dsui.prg src/dsinput.prg src/dsrepl.prg tests/tests.hbp tests/test_ui.prg
git commit -m "feat: input-box rendering and the raw-mode editor loop"
```

---

## Task 4: Wire the editor into the REPL

**Files:**
- Modify: `src/dsrepl.prg`
- Modify: `src/dsconsole.c`

`src/dsrepl.prg` is not in the test build — verified by `build.bat` and a manual smoke test.

- [ ] **Step 1: Use the editor for the main prompt**

In `src/dsrepl.prg`, `DSREPL_Run`'s loop currently, near the top of the `DO WHILE .T.`, has: a `cSuggest` prefill block that calls `DSCON_PrefillInput`, then an `IF DSUI_ColorOn() ... ELSE ... ENDIF` block that draws the input frame and the `"> "` prompt, then `cLine := DSREPL_ReadLine()`.

Replace from the `IF !Empty( cSuggest )` prefill block through the `cLine := DSREPL_ReadLine()` line with:

```harbour
      IF DSCON_HasConsole()
         cLine := DSIN_ReadLine( cSuggest )
         IF ValType( cLine ) == "H"   // { "no_console" => .T. } -- shouldn't happen here
            cLine := DSREPL_ReadLine()
         ENDIF
      ELSE
         // piped / non-interactive input: the cooked reader, no box
         DSREPL_Out( Chr(10) + DSUI_FrameTop() + Chr(10) + "> " )
         cLine := DSREPL_ReadLine()
      ENDIF
      cSuggest := ""
```

The suggested prompt is now the editor's initial buffer (`DSIN_ReadLine( cSuggest )`); the separate `DSCON_PrefillInput` call is gone. `cSuggest` is cleared after use.

- [ ] **Step 2: Remove the now-dead second frame block**

After `cLine := DSREPL_ReadLine()` the loop currently has a second `IF DSUI_ColorOn() ... ELSE ... ENDIF` block that emits `Chr(10)` (colour) or `DSUI_FrameBottom() + Chr(10)` (plain) after the line was read. With the editor owning the box, that block is only needed for the cooked fallback. Replace that whole `IF DSUI_ColorOn() ... ENDIF` block with:

```harbour
      IF !DSCON_HasConsole()
         DSREPL_Out( DSUI_FrameBottom() + Chr(10) )
      ENDIF
```

(The interactive editor already stepped the cursor below its box.)

- [ ] **Step 3: Remove `DSCON_PrefillInput`**

In `src/dsconsole.c`, delete the entire `DSCON_PREFILLINPUT` function and its leading comment block. First confirm with a repo-wide search for `DSCON_PrefillInput` / `DSCON_PREFILLINPUT` that nothing else references it — after Step 1 there is no caller. Update the file's top comment so it describes the console module generally rather than only prefill, e.g.:

```c
/* Windows console support for CCHarbour: console detection, raw-mode
 * toggling, and raw key reading for the line editor. */
```

- [ ] **Step 4: Build**

Run `build.bat` from the repo root. Expected: `Build OK -> cc.exe`.

- [ ] **Step 5: Manual smoke test**

Run `cc.exe` in an interactive terminal with a `DEEPSEEK_API_KEY` set. Verify: the prompt is a rounded box with **side borders** (`│ … │`); typing shows characters inside the box; Left/Right/Home/End move the cursor; Backspace and Delete edit; a long line scrolls horizontally inside the box; Enter submits; after a turn the suggested next prompt is pre-filled in the box and is editable; Ctrl-C cancels the line. Also run `echo a request | cc.exe` (piped) and confirm it still works via the cooked fallback and does not hang. Record the outcome in the task report.

- [ ] **Step 6: Commit**

```bash
git add src/dsrepl.prg src/dsconsole.c
git commit -m "feat: raw-mode input box for the REPL prompt"
```

---

## Task 5: Banner logo and version

**Files:**
- Modify: `src/dsui.prg`
- Test: `tests/test_ui.prg`

- [ ] **Step 1: Write the failing test**

Append inside `Test_UI()` in `tests/test_ui.prg`, before its `RETURN NIL`:

```harbour
   // version + banner
   T_Equal( DSUI_Version(), "0.2.0", "ui: version string" )
   DSUI_SetColor( .F. )
   T_Assert( "v0.2.0" $ DSUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the version" )
   T_Assert( "CCHarbour" $ DSUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the name" )
   T_Assert( "model: deepseek-v4-flash" $ DSUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the model" )
   T_Assert( "cwd: C:\proj" $ DSUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the cwd" )
   T_Assert( DSUI_Glyph( "tl" ) $ DSUI_Banner( "m", "c", "u" ), ;
             "ui: banner has the rounded box" )
```

- [ ] **Step 2: Run test to verify it fails**

Build and run the test runner.
Expected: FAIL — `DSUI_Version` undefined; the banner has no `v0.2.0`.

- [ ] **Step 3: Add `DSUI_Version` and rebuild the banner**

In `src/dsui.prg`, add directly before `DSUI_Banner`:

```harbour
// The CCHarbour version string.
FUNCTION DSUI_Version()
   RETURN "0.2.0"
```

Then replace the entire `DSUI_Banner` function with:

```harbour
// Builds the Claude Code-style startup banner: a single-panel rounded box with
// a block-letter "CC" logo (accent colour) on the left and the name+version,
// a tagline, the /help hint, the model and the working directory on the right.
// Returns the whole banner as one string ending in LF.
FUNCTION DSUI_Banner( cModel, cCwd, cUser )
   LOCAL nInner := 75, cH := DSUI_Glyph( "h" ), cV
   LOCAL cAccent := Chr(226)+Chr(156)+Chr(187)   // U+273B
   LOCAL aLogo, aInfo, aRows, cOut, i, cText, cSGR, cCell

   HB_SYMBOL_UNUSED( cUser )
   cModel := hb_CStr( cModel )
   cCwd   := hb_CStr( cCwd )
   cV     := DSUI_Color( DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) )

   // the "CC" logo, six rows of block-drawing glyphs
   aLogo := { ;
      "  ██████╗ ██████╗ ", ;
      " ██╔════╝██╔════╝ ", ;
      " ██║     ██║      ", ;
      " ██║     ██║      ", ;
      " ╚██████╗╚██████╗ ", ;
      "  ╚═════╝ ╚═════╝ " }

   // the info column, paired row-for-row with the logo
   aInfo := { ;
      cAccent + " CCHarbour  v" + DSUI_Version(), ;
      "terminal coding assistant " + Chr(226)+Chr(128)+Chr(183) + ;
         " Claude Code-style", ;
      "", ;
      "/help for help", ;
      "model: " + cModel, ;
      "cwd: " + cCwd }

   // each row: { plain text, SGR code or "" }. The logo is accent-coloured;
   // the first info row (name + version) is accent; the rest are plain/dim.
   aRows := {}
   FOR i := 1 TO 6
      cText := DSUI_PadCell( aLogo[ i ], 18, "L" ) + " " + aInfo[ i ]
      cSGR  := iif( i == 1, DSUI_Pal( "accent" ), "" )
      AAdd( aRows, { cText, cSGR } )
   NEXT

   cOut := DSUI_Color( DSUI_Glyph( "tl" ) + Replicate( cH, nInner + 2 ) + ;
           DSUI_Glyph( "tr" ), DSUI_Pal( "dim" ) ) + Chr(10)
   FOR i := 1 TO Len( aRows )
      cText := aRows[ i ][ 1 ]
      cSGR  := aRows[ i ][ 2 ]
      cCell := DSUI_PadCell( cText, nInner, "L" )
      IF !Empty( cSGR )
         cCell := DSUI_Color( cCell, cSGR )
      ENDIF
      cOut += cV + " " + cCell + " " + cV + Chr(10)
   NEXT
   cOut += DSUI_Color( DSUI_Glyph( "bl" ) + Replicate( cH, nInner + 2 ) + ;
           DSUI_Glyph( "br" ), DSUI_Pal( "dim" ) ) + Chr(10)
   RETURN cOut
```

Note: each logo row is padded to 18 columns so the info column lines up; the whole content cell is then padded to `nInner` (75). The logo is accent-coloured only on the first row in this layout — to colour the whole logo block, each row carries the logo text and the accent SGR is applied per cell; since the logo and info share a cell, row 1 (name+version) is accent and rows 2-6 are left default. This keeps the cell-padding/colour rule simple and avoids nested ANSI. The logo glyphs still render; they are simply in the default foreground on rows 2-6.

If a fully accent-coloured logo is wanted, that needs per-segment colouring (colour the logo substring, leave the info substring default) — out of scope here; the row-level colouring above is the chosen approach.

- [ ] **Step 4: Run test to verify it passes**

Build and run the test runner.
Expected: PASS — the `ui:` version/banner assertions pass, `fail: 0`, no regressions. (The pre-existing banner assertions for `Welcome to CCHarbour` were replaced — if `tests/test_ui.prg` still asserts the old `"Welcome to CCHarbour"` text, update that assertion to check `"CCHarbour"` instead, since the new banner says `✻ CCHarbour v0.2.0` rather than `Welcome to CCHarbour`.)

- [ ] **Step 5: Build the app**

Run `build.bat`. Expected: `Build OK -> cc.exe`.

- [ ] **Step 6: Commit**

```bash
git add src/dsui.prg tests/test_ui.prg
git commit -m "feat: banner CC logo and version string"
```

---

## Self-review notes

- **Spec coverage:** raw key reading + console detection + raw-mode toggle (T1); editor buffer operations (T2); the box-line rendering helper + the raw I/O loop with full editing and horizontal scroll (T3); REPL wiring with the cooked fallback and `DSCON_PrefillInput` removal (T4); banner logo + `DSUI_Version` (T5). Every spec section maps to a task.
- **Working intermediate state:** T1 only adds C functions (`DSCON_PrefillInput` kept). T2 adds pure ops. T3 adds the loop and makes `DSREPL_Out` public. T4 rewires the REPL and removes `DSCON_PrefillInput` together with its last caller — no broken commit.
- **Test-build linkage:** `dsinput.prg` references `DSCON_*`; T3 adds `../src/dsconsole.c` to `tests/tests.hbp` so the test build links. T2's `dsinput.prg` has only pure ops (no `DSCON_*`), so it links fine before T3.
- **`DSREPL_Out` visibility:** it is `STATIC` in `dsrepl.prg`; T3 makes it public so `dsinput.prg` can call it. Flagged explicitly in T3 Step 5.
- **Type consistency:** the editor state is `{ "buf", "cursor" }` throughout; `DSIN_Window` returns `{ "text", "col" }`; `DSIN_ReadLine` returns a string, `NIL`, or `{ "no_console" => .T. }`; `DSCON_ReadKey` returns the integer codes T1 defines and T3's loop consumes. `DSUI_InputInnerWidth()` (73) is used by both `DSUI_InputBoxLine` and `DSIN_Window`.
- **Deliberate scope note:** the logo is accent-coloured at row granularity (row 1), not per-segment, to avoid nested ANSI — stated in T5 Step 3.

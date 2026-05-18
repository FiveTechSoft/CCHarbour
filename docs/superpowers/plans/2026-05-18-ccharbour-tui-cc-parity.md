# CCHarbour Terminal UI — Claude Code Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the native CCHarbour terminal UI to visual parity with Claude Code — a Claude Code-style banner and input frame, full markdown rendering of the assistant's streamed reply, Claude Code glyphs/colours, and a model-proposed next prompt prefilled into the input line.

**Architecture:** Keep the existing cooked-mode line input and event-driven rendering. Add a streaming line-buffered markdown→ANSI renderer (`src/dsmarkdown.prg`) and a small C extension that prefills the Windows console input buffer (`src/dsconsole.c`). Restyle `src/dsui.prg` and wire the new pieces into `src/dsrepl.prg`.

**Tech Stack:** Harbour 3.2, MSVC C toolchain, the Windows console API. Tests run through the existing `tests/run_tests.prg` harness.

**Spec:** `docs/superpowers/specs/2026-05-18-ccharbour-tui-cc-parity-design.md`

---

## Build & test commands

- Build the app: run `build.bat` from the repo root → `cc.exe`.
- Build the test runner: from `tests/`, the Harbour + MSVC toolchain must be on the environment. `tests/build_tests.bat` exists but has a pre-existing redirection bug; if it fails, run the build directly. The toolchain (mirroring `build.bat`):
  1. `call "<vcvars64.bat>"` (e.g. `C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat`)
  2. `set "HB_USER_CFLAGS=-MD"`
  3. `set "HB_USER_LDFLAGS=/NODEFAULTLIB:libcmt.lib /NODEFAULTLIB:libucrt.lib /NODEFAULTLIB:libvcruntime.lib msvcrt.lib ucrt.lib vcruntime.lib"`
  4. `"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp`
- Run the tests: from `tests/`, run `run_tests.exe`. The last line reads `pass: N   fail: M`; `fail` must be 0.

---

## Task 1: Streaming markdown renderer

**Files:**
- Create: `src/dsmarkdown.prg`
- Create: `tests/test_markdown.prg`
- Modify: `cc.hbp`, `tests/tests.hbp`, `tests/run_tests.prg`

- [ ] **Step 1: Wire the new files into the build and test harness**

In `cc.hbp`, add `src/dsmarkdown.prg` on the line directly after `src/dsui.prg`.

In `tests/tests.hbp`, add `test_markdown.prg` on the line after `test_ui.prg`, and add `../src/dsmarkdown.prg` on the line after `../src/dsui.prg`.

In `tests/run_tests.prg`, in `Main()`, add a call to `Test_Markdown()` immediately after the existing `Test_UI()` call.

- [ ] **Step 2: Write the failing test**

Create `tests/test_markdown.prg`:

```harbour
FUNCTION Test_Markdown()
   LOCAL oSt, cOut

   DSUI_SetColor( .F. )

   // a line is rendered only once complete (split across two feeds)
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "hello " ), "", "md: partial line buffered" )
   T_Equal( DSMD_Feed( oSt, "world" + Chr(10) ), "hello world" + Chr(10), ;
            "md: completed line emitted" )

   // a blank line passes through
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, Chr(10) ), Chr(10), "md: blank line" )

   // inline markers are stripped when colour is off
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "a **b** c" + Chr(10) ), "a b c" + Chr(10), ;
            "md: bold markers stripped, colour off" )
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "x `code` y" + Chr(10) ), "x code y" + Chr(10), ;
            "md: code markers stripped, colour off" )
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "an *it* word" + Chr(10) ), "an it word" + Chr(10), ;
            "md: italic markers stripped, colour off" )

   // heading: marks removed
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "## Title" + Chr(10) ), "Title" + Chr(10), ;
            "md: heading marks removed" )

   // bullet list: marker becomes a bullet glyph, indented
   oSt := DSMD_New()
   cOut := DSMD_Feed( oSt, "- item" + Chr(10) )
   T_Equal( cOut, "  " + Chr(226)+Chr(128)+Chr(162) + " item" + Chr(10), ;
            "md: bullet list item" )

   // numbered list: number kept
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "3. third" + Chr(10) ), "  3. third" + Chr(10), ;
            "md: numbered list item" )

   // fenced code block: fence lines vanish, content kept verbatim and indented
   oSt := DSMD_New()
   cOut := DSMD_Feed( oSt, "```js" + Chr(10) + "let x" + Chr(10) + "```" + Chr(10) )
   T_Equal( cOut, "  let x" + Chr(10), "md: fenced block content only" )

   // a line inside a fence is not inline-formatted
   oSt := DSMD_New()
   cOut := DSMD_Feed( oSt, "```" + Chr(10) + "a **b**" + Chr(10) + "```" + Chr(10) )
   T_Equal( cOut, "  a **b**" + Chr(10), "md: no inline parsing inside a fence" )

   // suggested-prompt marker: captured, produces no output
   oSt := DSMD_New()
   cOut := DSMD_Feed( oSt, "done." + Chr(10) + "Suggested next: run the tests" + Chr(10) )
   T_Equal( cOut, "done." + Chr(10), "md: suggestion line not printed" )
   T_Equal( DSMD_Suggestion( oSt ), "run the tests", "md: suggestion captured" )

   // flush renders a final unterminated line
   oSt := DSMD_New()
   DSMD_Feed( oSt, "tail" )
   T_Equal( DSMD_Flush( oSt ), "tail" + Chr(10), "md: flush renders partial line" )

   // colour on: bold emits the ANSI bold code
   DSUI_SetColor( .T. )
   oSt := DSMD_New()
   cOut := DSMD_Feed( oSt, "**x**" + Chr(10) )
   T_Assert( Chr(27) + "[1m" $ cOut, "md: bold emits ANSI when colour on" )
   DSUI_SetColor( .F. )

   RETURN NIL
```

- [ ] **Step 3: Run test to verify it fails**

Build the test runner (see Build & test commands).
Expected: FAIL — `DSMD_New` / `DSMD_Feed` / `DSMD_Flush` / `DSMD_Suggestion` undefined.

- [ ] **Step 4: Write minimal implementation**

Create `src/dsmarkdown.prg`:

```harbour
// Streaming, line-buffered markdown-to-ANSI renderer for the assistant's
// reply. The reply arrives as text deltas; this renders each line once it is
// complete, mirroring the SSE parser pattern. It also captures the
// "Suggested next:" marker line. Never throws: unrecognised text is emitted
// unchanged, and with colour off (DSUI_ColorOn() false) markers are stripped
// but no ANSI codes are produced.

// Creates a fresh render state.
FUNCTION DSMD_New()
   RETURN { "buf" => "", "fence" => .F., "suggestion" => "" }

// Appends a chunk; renders every line completed by a newline. Returns the
// rendered ANSI text for those lines ("" when only a partial line is buffered).
FUNCTION DSMD_Feed( oSt, cChunk )
   LOCAL cOut := "", nNL, cLine
   oSt[ "buf" ] += hb_CStr( cChunk )
   DO WHILE ( nNL := At( Chr(10), oSt[ "buf" ] ) ) > 0
      cLine := Left( oSt[ "buf" ], nNL - 1 )
      oSt[ "buf" ] := SubStr( oSt[ "buf" ], nNL + 1 )
      cOut += DSMD_RenderLine( oSt, cLine )
   ENDDO
   RETURN cOut

// Renders any buffered partial line (call at end of stream).
FUNCTION DSMD_Flush( oSt )
   LOCAL cOut := ""
   IF Len( oSt[ "buf" ] ) > 0
      cOut := DSMD_RenderLine( oSt, oSt[ "buf" ] )
      oSt[ "buf" ] := ""
   ENDIF
   RETURN cOut

// Returns the captured suggested next prompt, or "".
FUNCTION DSMD_Suggestion( oSt )
   RETURN oSt[ "suggestion" ]

// Renders one line (no trailing newline supplied); the result ends in LF.
STATIC FUNCTION DSMD_RenderLine( oSt, cLine )
   LOCAL cTrim, cRest, nH, cList
   cLine := StrTran( cLine, Chr(13), "" )
   cTrim := AllTrim( cLine )

   // suggested-prompt marker -> captured, never printed
   IF Len( cTrim ) >= 15 .AND. Lower( Left( cTrim, 15 ) ) == "suggested next:"
      oSt[ "suggestion" ] := AllTrim( SubStr( cTrim, 16 ) )
      RETURN ""
   ENDIF

   // fenced code block toggle (``` optionally followed by a language tag)
   IF Left( cTrim, 3 ) == "```"
      oSt[ "fence" ] := !oSt[ "fence" ]
      RETURN ""
   ENDIF
   IF oSt[ "fence" ]
      RETURN "  " + DSUI_Color( cLine, "90" ) + Chr(10)
   ENDIF

   // blank line
   IF Empty( cTrim )
      RETURN Chr(10)
   ENDIF

   // heading
   nH := DSMD_HeadingLevel( cTrim )
   IF nH > 0
      cRest := AllTrim( SubStr( cTrim, nH + 1 ) )
      RETURN DSUI_Color( cRest, "1" ) + Chr(10)
   ENDIF

   // list item
   cList := DSMD_ListRender( cTrim )
   IF cList != NIL
      RETURN cList + Chr(10)
   ENDIF

   // paragraph
   RETURN DSMD_Inline( cLine ) + Chr(10)

// Returns the heading level 1..6 for a "# " .. "###### " line, else 0.
STATIC FUNCTION DSMD_HeadingLevel( cTrim )
   LOCAL n := 0
   DO WHILE SubStr( cTrim, n + 1, 1 ) == "#"
      n++
   ENDDO
   IF n >= 1 .AND. n <= 6 .AND. SubStr( cTrim, n + 1, 1 ) == " "
      RETURN n
   ENDIF
   RETURN 0

// Renders a bullet ("- ", "* ", "+ ") or numbered ("<digits>. ") list item,
// or NIL when the line is not a list item.
STATIC FUNCTION DSMD_ListRender( cTrim )
   LOCAL cMark := Left( cTrim, 2 ), nDot := 0, i, c
   LOCAL cBullet := Chr(226)+Chr(128)+Chr(162)   // U+2022 bullet
   IF cMark == "- " .OR. cMark == "* " .OR. cMark == "+ "
      RETURN "  " + DSUI_Color( cBullet, "90" ) + " " + ;
             DSMD_Inline( SubStr( cTrim, 3 ) )
   ENDIF
   FOR i := 1 TO Len( cTrim )
      c := SubStr( cTrim, i, 1 )
      IF IsDigit( c )
         LOOP
      ENDIF
      IF c == "." .AND. i > 1 .AND. SubStr( cTrim, i + 1, 1 ) == " "
         nDot := i
      ENDIF
      EXIT
   NEXT
   IF nDot > 0
      RETURN "  " + DSUI_Color( Left( cTrim, nDot ), "90" ) + " " + ;
             DSMD_Inline( SubStr( cTrim, nDot + 2 ) )
   ENDIF
   RETURN NIL

// Applies inline formatting: **bold**, `code`, *italic*. Order matters:
// ** before * so a bold pair is not split by the italic pass.
STATIC FUNCTION DSMD_Inline( cText )
   cText := DSMD_Span( cText, "**", "1" )
   cText := DSMD_Span( cText, "`", "96" )
   cText := DSMD_Span( cText, "*", "3" )
   RETURN cText

// Wraps every cDelim..cDelim span in cText with the ANSI colour cSGR.
// An unmatched trailing delimiter is left as literal text.
STATIC FUNCTION DSMD_Span( cText, cDelim, cSGR )
   LOCAL nDL := Len( cDelim ), nOpen, nClose, cResult := ""
   LOCAL cInner, cBefore
   DO WHILE ( nOpen := At( cDelim, cText ) ) > 0
      nClose := At( cDelim, SubStr( cText, nOpen + nDL ) )
      IF nClose == 0
         EXIT
      ENDIF
      cBefore := Left( cText, nOpen - 1 )
      cInner  := SubStr( cText, nOpen + nDL, nClose - 1 )
      cResult += cBefore + DSUI_Color( cInner, cSGR )
      cText := SubStr( cText, nOpen + nDL + nClose - 1 + nDL )
   ENDDO
   RETURN cResult + cText
```

Note: `_italic_` is intentionally not supported — a single underscore is common inside identifiers (`my_var`), and treating it as italic would mangle code. Only `*italic*` is rendered. This is a deliberate deviation from the spec's inline list, made for correctness.

- [ ] **Step 5: Run test to verify it passes**

Build and run the test runner.
Expected: PASS — all `md:` assertions pass, `fail: 0`, no regressions.

- [ ] **Step 6: Commit**

```bash
git add src/dsmarkdown.prg tests/test_markdown.prg cc.hbp tests/tests.hbp tests/run_tests.prg
git commit -m "feat: streaming markdown renderer for the terminal UI"
```

---

## Task 2: Claude Code colour palette and tool glyph

**Files:**
- Modify: `src/dsui.prg`
- Test: `tests/test_ui.prg` (extend `Test_UI`)

- [ ] **Step 1: Write the failing test**

Append inside `Test_UI()` in `tests/test_ui.prg`, before its `RETURN NIL`:

```harbour
   // colour palette: codes returned regardless of colour state
   T_Equal( DSUI_Pal( "accent" ), "38;5;215", "ui: accent palette code" )
   T_Equal( DSUI_Pal( "dim" ), "90", "ui: dim palette code" )
   T_Equal( DSUI_Pal( "error" ), "31", "ui: error palette code" )
   T_Equal( DSUI_Pal( "bold" ), "1", "ui: bold palette code" )
   T_Equal( DSUI_Pal( "nope" ), "0", "ui: unknown palette name -> reset" )
```

`hA` is already a LOCAL in `Test_UI()`; these assertions need no new locals.

- [ ] **Step 2: Run test to verify it fails**

Build and run the test runner.
Expected: FAIL — `DSUI_Pal` undefined.

- [ ] **Step 3: Write minimal implementation**

In `src/dsui.prg`, add this function directly after `DSUI_ColorOn()`:

```harbour
// The Claude Code-style colour palette: maps a name to an ANSI SGR code so
// the codes live in one place. Unknown names return "0" (reset).
FUNCTION DSUI_Pal( cName )
   DO CASE
   CASE cName == "accent"     ; RETURN "38;5;215"   // tan/orange
   CASE cName == "dim"        ; RETURN "90"         // grey borders / secondary
   CASE cName == "bold"       ; RETURN "1"
   CASE cName == "error"      ; RETURN "31"
   CASE cName == "tool"       ; RETURN "1;36"       // bright cyan tool label
   CASE cName == "warn"       ; RETURN "33"
   CASE cName == "diff_add"   ; RETURN "42"
   CASE cName == "diff_del"   ; RETURN "48;5;52"
   ENDCASE
   RETURN "0"
```

Then change the tool-call glyph: in `DSUI_RenderEvent`, the `tool_call` case currently builds its label with `Chr(226)+Chr(151)+Chr(143)` (●). Replace that glyph expression with `Chr(226)+Chr(143)+Chr(186)` (⏺, U+23FA), keeping the rest of the line unchanged.

- [ ] **Step 4: Run test to verify it passes**

Build and run the test runner.
Expected: PASS — the `ui:` palette assertions pass, `fail: 0`, no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/dsui.prg tests/test_ui.prg
git commit -m "feat: Claude Code colour palette and tool glyph"
```

---

## Task 3: Claude Code-style banner

**Files:**
- Modify: `src/dsui.prg` (`DSUI_Banner`)
- Test: `tests/test_ui.prg` (extend `Test_UI`)

- [ ] **Step 1: Write the failing test**

Append inside `Test_UI()` in `tests/test_ui.prg`, before its `RETURN NIL`:

```harbour
   // banner: single-panel Claude Code-style box
   DSUI_SetColor( .F. )
   hA := NIL  // reuse not needed; banner returns a string
   T_Assert( "Welcome to CCHarbour" $ DSUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has welcome line" )
   T_Assert( "model: deepseek-chat" $ DSUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has model line" )
   T_Assert( "cwd: C:\proj" $ DSUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has cwd line" )
   T_Assert( "/help for help" $ DSUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has help hint" )
   T_Assert( DSUI_Glyph( "tl" ) $ DSUI_Banner( "m", "c", "u" ), ;
             "ui: banner has a rounded top-left corner" )
```

- [ ] **Step 2: Run test to verify it fails**

Build and run the test runner.
Expected: FAIL — the banner still produces the old two-panel text; the `model:`/`cwd:`/welcome assertions fail.

- [ ] **Step 3: Write minimal implementation**

In `src/dsui.prg`, replace the entire `DSUI_Banner` function (the current two-panel implementation) with:

```harbour
// Builds the Claude Code-style startup banner: a single-panel rounded box
// with an accent welcome line, the /help hint, and the model and working
// directory. Returns the whole banner as one string ending in LF.
FUNCTION DSUI_Banner( cModel, cCwd, cUser )
   LOCAL nInner := 75, cH := DSUI_Glyph( "h" ), cV
   LOCAL cAccent := Chr(226)+Chr(156)+Chr(187)   // U+273B sextile glyph
   LOCAL aRows, cOut, i, cText, cSGR, cCell

   HB_SYMBOL_UNUSED( cUser )
   cModel := hb_CStr( cModel )
   cCwd   := hb_CStr( cCwd )
   cV     := DSUI_Color( DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) )

   // each row: { plain text, SGR code or "" }
   aRows := { ;
      { cAccent + " Welcome to CCHarbour", DSUI_Pal( "accent" ) }, ;
      { "",                                "" }, ;
      { "  /help for help",                DSUI_Pal( "dim" ) }, ;
      { "",                                "" }, ;
      { "  model: " + cModel,              "" }, ;
      { "  cwd: " + cCwd,                  "" } }

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

The old banner's helper `DSUI_BanRow` is no longer called. Leave it in place only if other code uses it; a project-wide search for `DSUI_BanRow` will show no other callers, so delete the now-dead `DSUI_BanRow` function.

- [ ] **Step 4: Run test to verify it passes**

Build and run the test runner.
Expected: PASS — the `ui:` banner assertions pass, `fail: 0`, no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/dsui.prg tests/test_ui.prg
git commit -m "feat: Claude Code-style single-panel banner"
```

---

## Task 4: Input-frame helpers and the suggested-prompt instruction

**Files:**
- Modify: `src/dsui.prg`
- Test: `tests/test_ui.prg` (extend `Test_UI`)

- [ ] **Step 1: Write the failing test**

Append inside `Test_UI()` in `tests/test_ui.prg`, before its `RETURN NIL`:

```harbour
   // input frame helpers
   DSUI_SetColor( .F. )
   T_Equal( hb_UTF8Len( DSUI_FrameTop() ), 79, "ui: frame top is 79 columns" )
   T_Equal( hb_UTF8Len( DSUI_FrameBottom() ), 79, "ui: frame bottom is 79 columns" )
   T_Assert( DSUI_Glyph( "tl" ) $ DSUI_FrameTop(), "ui: frame top rounded corner" )
   T_Assert( DSUI_Glyph( "bl" ) $ DSUI_FrameBottom(), "ui: frame bottom rounded corner" )
   T_Assert( "/help" $ DSUI_InputHint(), "ui: input hint mentions /help" )

   // system prompt asks for a suggested next prompt
   T_Assert( "Suggested next:" $ DSUI_SystemPrompt(), ;
             "ui: system prompt requests a suggested next line" )
```

- [ ] **Step 2: Run test to verify it fails**

Build and run the test runner.
Expected: FAIL — `DSUI_FrameTop` / `DSUI_FrameBottom` / `DSUI_InputHint` undefined; `DSUI_SystemPrompt` lacks the marker.

- [ ] **Step 3: Write minimal implementation**

In `src/dsui.prg`, add these three functions directly after `DSUI_Rule()`:

```harbour
// The rounded top border of the input frame, 79 columns wide.
FUNCTION DSUI_FrameTop()
   RETURN DSUI_Color( DSUI_Glyph( "tl" ) + ;
          Replicate( DSUI_Glyph( "h" ), 77 ) + DSUI_Glyph( "tr" ), ;
          DSUI_Pal( "dim" ) )

// The rounded bottom border of the input frame, 79 columns wide.
FUNCTION DSUI_FrameBottom()
   RETURN DSUI_Color( DSUI_Glyph( "bl" ) + ;
          Replicate( DSUI_Glyph( "h" ), 77 ) + DSUI_Glyph( "br" ), ;
          DSUI_Pal( "dim" ) )

// The dim hint line shown beneath the input frame.
FUNCTION DSUI_InputHint()
   RETURN DSUI_Color( "  /help for commands  " + Chr(226)+Chr(128)+Chr(162) + ;
          "  /exit to quit", DSUI_Pal( "dim" ) )
```

Note: `DSUI_FrameTop`/`DSUI_FrameBottom` are tested with `hb_UTF8Len` for a 79-column width — the corner and `─` glyphs each count as one UTF-8 character; the colour codes are absent because the test runs with colour off.

Then, in `DSUI_SystemPrompt`, the base prompt string `cBase` ends with `"Be concise."`. Extend `cBase` so it also instructs the model to propose a next prompt — change the assignment so `cBase` reads:

```harbour
   cBase := "You are CCHarbour, a terminal coding assistant. " + ;
            "You have tools to read, write and edit files, search with glob and " + ;
            "grep, and run shell commands. Use them to help the user with coding " + ;
            "tasks. Be concise. " + ;
            "End every reply with a final line in the exact form " + ;
            "'Suggested next: <a short prompt the user might send next>'."
```

- [ ] **Step 4: Run test to verify it passes**

Build and run the test runner.
Expected: PASS — the `ui:` frame and system-prompt assertions pass, `fail: 0`, no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/dsui.prg tests/test_ui.prg
git commit -m "feat: input-frame helpers and suggested-prompt instruction"
```

---

## Task 5: Console-prefill C extension

**Files:**
- Create: `src/dsconsole.c`
- Modify: `cc.hbp`

This task has no Harbour unit test — the function drives the live Windows console and is exercised by the manual smoke test in Task 6. The check here is that it compiles and links into `cc.exe`.

- [ ] **Step 1: Write the C extension**

Create `src/dsconsole.c`:

```c
/* Console-input prefill for CCHarbour.
 *
 * DSCON_PrefillInput( cText ) injects cText (UTF-8) into the Windows console
 * input buffer as key events, so the cooked-mode line editor shows the text
 * as editable pending input. Returns .T. on success, .F. on any failure --
 * it never aborts the program.
 */
#include "hbapi.h"
#include <windows.h>

HB_FUNC( DSCON_PREFILLINPUT )
{
   const char * szUtf8 = hb_parc( 1 );
   HB_BOOL fOk = HB_FALSE;

   if( szUtf8 )
   {
      int nWide = MultiByteToWideChar( CP_UTF8, 0, szUtf8, -1, NULL, 0 );

      if( nWide > 1 )
      {
         WCHAR * pWide = ( WCHAR * ) hb_xgrab( nWide * sizeof( WCHAR ) );

         MultiByteToWideChar( CP_UTF8, 0, szUtf8, -1, pWide, nWide );
         {
            HANDLE hIn = GetStdHandle( STD_INPUT_HANDLE );
            int n = nWide - 1;   /* drop the terminating NUL */
            INPUT_RECORD * pRec = ( INPUT_RECORD * ) hb_xgrab( n * sizeof( INPUT_RECORD ) );
            DWORD nWritten = 0;
            int i;

            for( i = 0; i < n; i++ )
            {
               pRec[ i ].EventType = KEY_EVENT;
               pRec[ i ].Event.KeyEvent.bKeyDown = TRUE;
               pRec[ i ].Event.KeyEvent.wRepeatCount = 1;
               pRec[ i ].Event.KeyEvent.wVirtualKeyCode = 0;
               pRec[ i ].Event.KeyEvent.wVirtualScanCode = 0;
               pRec[ i ].Event.KeyEvent.dwControlKeyState = 0;
               pRec[ i ].Event.KeyEvent.uChar.UnicodeChar = pWide[ i ];
            }

            if( hIn != INVALID_HANDLE_VALUE && hIn != NULL &&
                WriteConsoleInputW( hIn, pRec, ( DWORD ) n, &nWritten ) )
               fOk = HB_TRUE;

            hb_xfree( pRec );
         }
         hb_xfree( pWide );
      }
   }

   hb_retl( fOk );
}
```

- [ ] **Step 2: Wire it into the build**

In `cc.hbp`, add `src/dsconsole.c` on its own line after `src/dsmarkdown.prg`.

Do **not** add `src/dsconsole.c` to `tests/tests.hbp` — the function is called only from `src/dsrepl.prg`, which is not part of the test build.

- [ ] **Step 3: Verify it builds**

Run `build.bat` from the repo root.
Expected: `Build OK -> cc.exe` — `dsconsole.c` compiles and links with no errors.

- [ ] **Step 4: Commit**

```bash
git add src/dsconsole.c cc.hbp
git commit -m "feat: console-input prefill C extension"
```

---

## Task 6: Wire the input frame, markdown rendering, and suggested-prompt prefill into the REPL

**Files:**
- Modify: `src/dsrepl.prg`

This task has no unit test — `dsrepl.prg` is not in the test build. It is verified by the build and the manual smoke test below.

- [ ] **Step 1: Add the markdown-aware render callback**

In `src/dsrepl.prg`, add this STATIC function directly after `DSREPL_Run` (before `DSREPL_Out`):

```harbour
// Renders one agent event. A text_delta is fed to the per-turn markdown
// renderer oMd; every other event goes through DSUI_RenderEvent unchanged.
STATIC FUNCTION DSREPL_RenderEv( hEv, oMd )
   IF ValType( hEv ) == "H" .AND. hb_HHasKey( hEv, "type" ) .AND. ;
      hEv[ "type" ] == "text_delta"
      DSREPL_Out( DSMD_Feed( oMd, hb_CStr( hEv[ "text" ] ) ) )
   ELSE
      DSREPL_Out( DSUI_RenderEvent( hEv ) )
   ENDIF
   RETURN NIL
```

- [ ] **Step 2: Draw the input frame**

In `DSREPL_Run`, the loop currently draws the prompt with two calls to `DSUI_Rule()` (the colour branch and the plain branch of an `IF DSUI_ColorOn()`). Replace that whole prompt-drawing `IF DSUI_ColorOn() ... ELSE ... ENDIF` block (the first one in the loop, which ends with the `"> "` prompt) with:

```harbour
      IF DSUI_ColorOn()
         // top border, blank prompt line, bottom border, hint; then move the
         // cursor back up onto the prompt line so the frame is fully drawn
         // before the user types.
         DSREPL_Out( Chr(10) + DSUI_FrameTop() + Chr(10) + ;
                     Chr(10) + ;
                     DSUI_FrameBottom() + Chr(10) + ;
                     DSUI_InputHint() + ;
                     DSUI_VT( "2A" ) + DSUI_VT( "1G" ) + ;
                     DSUI_Color( "> ", "1;36" ) )
      ELSE
         DSREPL_Out( Chr(10) + DSUI_FrameTop() + Chr(10) + "> " )
      ENDIF
```

The second `IF DSUI_ColorOn()` block in the loop (drawn after the line is read) currently emits `Chr(10)` in the colour branch and `DSUI_Rule()` in the plain branch. Replace that block with:

```harbour
      IF DSUI_ColorOn()
         DSREPL_Out( Chr(10) )
      ELSE
         DSREPL_Out( DSUI_FrameBottom() + Chr(10) )
      ENDIF
```

- [ ] **Step 3: Use the markdown render callback and prefill the suggestion**

In `DSREPL_Run`, the line near the top that creates `bRender` is currently
`bRender := {| hEv | DSREPL_Out( DSUI_RenderEvent( hEv ) ) }`. Delete that line.

Add a `LOCAL` for the per-turn markdown state and the pending suggestion: extend the `LOCAL` declaration at the top of `DSREPL_Run` to also declare `oMd` and `cSuggest`, and initialise `cSuggest := ""` right after the `aMsgs := ...` line.

At the very start of the `DO WHILE .T.` loop, before the prompt is drawn, prefill any pending suggestion:

```harbour
   DO WHILE .T.
      IF !Empty( cSuggest )
         DSCON_PrefillInput( cSuggest )
         cSuggest := ""
      ENDIF
```

In the `"message" .OR. "init"` case, replace the `DS_AgentRun(...)` call and the lines around it so the turn uses a fresh markdown renderer and captures the suggestion. The current code is:

```harbour
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => cMsg } )
         hRes := DS_AgentRun( oClient, aTurn, ;
            { "model" => cModel, ;
              "tools" => DSTools_Schemas( oReg ), ;
              "tool_executor" => bGate, ;
              "max_iterations" => nMaxIter }, ;
            bRender )
         DSREPL_Out( Chr(10) )
```

Replace it with:

```harbour
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => cMsg } )
         oMd := DSMD_New()
         hRes := DS_AgentRun( oClient, aTurn, ;
            { "model" => cModel, ;
              "tools" => DSTools_Schemas( oReg ), ;
              "tool_executor" => bGate, ;
              "max_iterations" => nMaxIter }, ;
            {| hEv | DSREPL_RenderEv( hEv, oMd ) } )
         DSREPL_Out( DSMD_Flush( oMd ) )
         DSREPL_Out( Chr(10) )
         cSuggest := DSMD_Suggestion( oMd )
```

- [ ] **Step 4: Verify it builds**

Run `build.bat` from the repo root.
Expected: `Build OK -> cc.exe`.

- [ ] **Step 5: Manual smoke test**

Run `cc.exe` with a valid `DEEPSEEK_API_KEY` and verify:
- The startup banner is the single-panel rounded box with the welcome, `/help`, `model:` and `cwd:` lines.
- The input prompt is framed by a rounded top border and a bottom border with a dim hint line.
- An assistant reply with markdown (ask it to "reply with a heading, a bold word, a bullet list and a fenced code block") renders the heading bold, the bold word bold, the list with `•` bullets, and the code block indented and dimmed — no raw `#`, `**`, or ``` ``` ``` markers.
- After the reply, the next prompt line is prefilled with the model's suggested next prompt and is editable (you can backspace/extend it) and runs on Enter.
- The literal text `Suggested next:` never appears in the visible reply.

Record the smoke-test outcome in the task report. If any step fails, fix it before committing.

- [ ] **Step 6: Run the full test suite**

Build and run the test runner.
Expected: PASS — `fail: 0`; all tests from Tasks 1-4 still pass.

- [ ] **Step 7: Commit**

```bash
git add src/dsrepl.prg
git commit -m "feat: Claude Code-style input frame, markdown output, suggested prompt"
```

---

## Self-review notes

- **Spec coverage:** markdown renderer incl. fenced blocks and suggestion capture (T1); colour palette + `⏺` glyph (T2); single-panel banner (T3); input-frame helpers + `DSUI_SystemPrompt` instruction (T4); `DSCON_PrefillInput` C extension (T5); REPL wiring — input frame, per-turn markdown callback, suggestion prefill (T6). Every spec section maps to a task.
- **Deliberate spec deviation:** `_italic_` is not rendered (only `*italic*`) — a bare underscore inside identifiers would be mis-rendered. Noted in Task 1.
- **Cooked-mode honesty:** the input "frame" is a top border + prompt line + bottom border + hint, with no side borders — side borders cannot be maintained while the OS cooked editor handles typing. This matches the spec's described frame.
- **Type consistency:** `DSMD_New` returns the state hash consumed by `DSMD_Feed`/`DSMD_Flush`/`DSMD_Suggestion`; the REPL holds it as `oMd` per turn. `DSUI_Pal` returns SGR strings used by the banner, frame helpers, and markdown renderer. `DSREPL_RenderEv( hEv, oMd )` matches the closure passed to `DS_AgentRun`.
- **Test build:** `src/dsmarkdown.prg` is added to both `cc.hbp` and `tests/tests.hbp`; `src/dsconsole.c` is added only to `cc.hbp` (it is called solely from `dsrepl.prg`, which is outside the test build).
- **No regression risk to A:** none of the web/github tools, the agent loop, or the HTTP layer are touched.

# CCHarbour Terminal UI — Raw-mode Input Box and Banner Logo (round 3)

**Date:** 2026-05-18
**Status:** Approved design, ready for implementation plan
**Scope:** Native CCHarbour (`cc.exe`) only.

## Goal

Two TUI changes that close the last visible gap with Claude Code:

1. **Raw-mode input box** — replace the cooked-mode line reader for the main
   prompt with a raw-mode single-line editor that draws a bordered box with
   side borders (`│ > … │`) and supports full in-line editing
   (Left/Right/Home/End/Delete/Backspace). The cooked reader stays as the
   fallback when input is not a real console (piped) and for the small y/n
   prompts.
2. **Banner logo + version** — give the startup banner a block-letter "CC"
   logo and show the CCHarbour version.

## Background

CCHarbour's main prompt currently uses `DSREPL_ReadLine`, a byte-at-a-time
reader over the console's cooked (line-input) mode. The OS line editor owns the
buffer, so the input "box" can only be a top border + prompt line + bottom
border — no side borders, because the right `│` cannot stay aligned while the
OS echoes typing. Claude Code's box has side borders because it reads keys raw
and redraws. This spec adds that raw-mode editor.

## Architecture

A new module `src/dsinput.prg` holds the editor: pure buffer-state operations
plus a thin raw-mode I/O loop. The C extension `src/dsconsole.c` gains raw key
reading. `src/dsrepl.prg` calls the editor for the main prompt. `src/dsui.prg`
gets the banner logo and a version function.

### Files

New:
- `src/dsinput.prg` — the raw-mode single-line box editor.
- `tests/test_input.prg` — tests for the editor's pure operations.

Modified:
- `src/dsconsole.c` — add `DSCON_RawMode` and `DSCON_ReadKey`; remove the now-unused `DSCON_PrefillInput`.
- `src/dsrepl.prg` — the main prompt uses the editor; the suggested prompt is passed as the editor's initial buffer.
- `src/dsui.prg` — banner logo + `DSUI_Version`.
- `cc.hbp` — add `src/dsinput.prg`.
- `tests/tests.hbp`, `tests/run_tests.prg` — register `test_input.prg`.
- `tests/test_ui.prg` — banner assertions.

## C extension — `src/dsconsole.c`

Two new Harbour-callable functions; `DSCON_PrefillInput` is removed (the editor
takes an initial buffer instead, so the WriteConsoleInput trick is no longer
needed).

- `DSCON_RawMode( lOn )` — when `.T.`, clears `ENABLE_LINE_INPUT` and
  `ENABLE_ECHO_INPUT` on the console input handle (`GetStdHandle(STD_INPUT_HANDLE)`),
  saving the previous mode; when `.F.`, restores the saved mode. Returns `.T.`
  on success, `.F.` when there is no real console (e.g. piped stdin) or the API
  fails — it never aborts.
- `DSCON_ReadKey()` — blocks for one key-down event via `ReadConsoleInputW`,
  ignoring key-up and non-key events, and returns an integer describing it:
  - a positive value — the Unicode codepoint of a printable character;
  - `0` — end of input;
  - negative codes for control keys: `-1` Enter, `-2` Backspace, `-3` Left,
    `-4` Right, `-5` Home, `-6` End, `-7` Delete, `-8` Ctrl-C.
  Keys not in that set (other arrows, function keys, modifiers alone) return a
  sentinel `-99` that the editor ignores.

The numeric-code contract keeps the Harbour/C boundary trivial — no structs.

## The editor — `src/dsinput.prg`

### Pure state and operations (unit-tested)

The editor state is a hash `{ "buf" => "", "cursor" => 0 }` — `buf` is the
current text, `cursor` is the insertion index (0 = before the first character,
`Len(buf)` = at the end). Pure functions, each taking and returning the state,
all unit-tested:

- `DSIN_New( cInitial )` — fresh state; `buf` = `cInitial` (default `""`),
  `cursor` at the end.
- `DSIN_Insert( oSt, cChar )` — insert `cChar` at the cursor; advance the cursor.
- `DSIN_Backspace( oSt )` — delete the character before the cursor; move the
  cursor back one. No-op at the start.
- `DSIN_Delete( oSt )` — delete the character at the cursor. No-op at the end.
- `DSIN_Left( oSt )` / `DSIN_Right( oSt )` — move the cursor one, clamped.
- `DSIN_Home( oSt )` / `DSIN_End( oSt )` — cursor to 0 / to `Len(buf)`.
- `DSIN_Window( oSt, nWidth )` — returns `{ text, cursorCol }`: the slice of
  `buf` that fits in `nWidth` display columns around the cursor (horizontal
  scroll), and the cursor's column within that slice. When `buf` fits, the
  slice is the whole buffer.

These operate on UTF-8 text by **character** (`hb_UTF8*` functions), so
multi-byte input is handled correctly.

### The I/O loop

`DSIN_ReadLine( cInitial )` — draws the box and runs the editor; returns the
typed string, or `NIL` at end of input / Ctrl-C.

1. Call `DSCON_RawMode( .T. )`. If it returns `.F.` (no console), return a
   sentinel so the caller falls back to the cooked reader (see REPL changes).
2. Draw the box: a rounded top border, the prompt line, a rounded bottom
   border, and the dim hint line — reusing `DSUI_FrameTop`/`DSUI_FrameBottom`/
   `DSUI_InputHint`, but the prompt line is now `│ > <text> │` with side
   borders.
3. Loop: `DSCON_ReadKey()` → apply the matching `DSIN_*` operation → redraw the
   prompt line in place (carriage return to column 1, reprint
   `│ > <DSIN_Window slice> │`, place the terminal cursor at the window cursor
   column via a VT sequence). Enter → break. Ctrl-C / EOF → set a NIL result,
   break.
4. Call `DSCON_RawMode( .F. )` to restore the console, always — including on
   the abort paths.
5. Return the buffer (or `NIL`).

The prompt line is redrawn only (the top/bottom borders are static), so the
side borders stay aligned on every keystroke. Text wider than the inner width
scrolls horizontally via `DSIN_Window`.

## REPL changes — `src/dsrepl.prg`

- The main-prompt read in `DSREPL_Run` becomes: if input is an interactive
  console, call `DSIN_ReadLine( cSuggest )` — the suggested next prompt is the
  editor's initial buffer; otherwise fall back to the existing cooked
  `DSREPL_ReadLine` (piped stdin, EOF-driven). `DSIN_ReadLine` signals the
  "no console" case so the REPL can choose the fallback.
- The current `DSCON_PrefillInput( cSuggest )` call is removed — the suggestion
  is now passed into `DSIN_ReadLine`. The `cSuggest`-clearing logic stays.
- The old top-border / bottom-border / hint drawing for the cooked path is kept
  only for the cooked fallback; the interactive path's box is drawn by
  `DSIN_ReadLine`.
- `DSREPL_ReadLine` is retained — used by the cooked fallback and by
  `DSREPL_AskPerm` and `DSREPL_AskExtend` (the y/n prompts stay cooked).

## Banner — `src/dsui.prg`

- New `DSUI_Version()` returns the version string `"0.2.0"`.
- `DSUI_Banner` is rebuilt: a block-letter "CC" logo (figlet "ANSI Shadow"
  style, drawn with block-drawing glyphs) on the left in the accent colour, and
  on the right `✻ CCHarbour v<version>`, a one-line tagline, `/help for help`,
  the `model:` line and the `cwd:` line — all inside the existing rounded box,
  79 columns wide. The accent colour is the coral from round 2.

## Error handling

- `DSCON_RawMode`/`DSCON_ReadKey` never abort: no console → `.F.` / `0`, and
  the REPL falls back to the cooked reader.
- Raw mode is always restored: `DSIN_ReadLine` calls `DSCON_RawMode(.F.)` on
  every exit path, and `Main`'s existing `BEGIN SEQUENCE` error net plus a
  restore call guard against a mid-turn crash leaving the console raw.
- Unknown keys (`-99`) are ignored by the editor loop.

## Testing

`src/dsinput.prg`'s pure operations are unit-tested in `tests/test_input.prg`
(`Test_Input`): `DSIN_Insert`/`Backspace`/`Delete` at the start, middle, end;
`DSIN_Left`/`Right`/`Home`/`End` with clamping; `DSIN_Window` when the buffer
fits and when it must scroll (cursor near the start, middle, end); UTF-8
multi-byte characters counted as one.

`src/dsui.prg`: `tests/test_ui.prg` asserts the banner contains the version
string, `CCHarbour`, `model:`, `cwd:`, and the rounded-box glyphs, and that
`DSUI_Version()` returns `"0.2.0"`.

The C extension and the raw-mode I/O loop / redraw are not unit-testable;
verified by `build.bat` and a manual smoke test in an interactive terminal
(box renders with side borders, typing/editing/scroll work, the suggested
prompt is prefilled and editable, Ctrl-C and piped-stdin fallback behave).

## Out of scope

- Multi-line input (the box growing vertically) — single-line only; long text
  scrolls horizontally.
- Command-history recall, tab completion, a `/`-command autocomplete popup.
- Bracketed-paste handling beyond ordinary character input.
- Any change to the web playground.

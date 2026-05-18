# CCHarbour Terminal UI — Claude Code Parity (sub-project)

**Date:** 2026-05-18
**Status:** Approved design, ready for implementation plan
**Scope:** The native CCHarbour terminal UI only. Make it look as close to the
Claude Code terminal interface as possible — "visual polish" depth: styling,
markdown rendering, and a suggested-next-prompt prefill, all within the
existing cooked-mode line-input architecture. No raw-mode TUI rewrite, no
animated spinner, no live-editing input box, no slash-command autocomplete
popup — those are explicitly deferred.

## Goal

Bring the CCHarbour console interface (`src/dsui.prg`, `src/dsrepl.prg`) to
visual parity with Claude Code: a Claude Code-style welcome banner and input
frame, full markdown rendering of the assistant's streamed text, Claude
Code-style tool/result glyphs and colors, and a suggested next prompt that the
model proposes and CCHarbour prefills into the input line after each turn.

## Constraints

- CCHarbour is a Windows console application. Input is read in the console's
  default cooked mode by `DSREPL_ReadLine` (a byte-at-a-time stdin reader). The
  OS owns the line editor.
- The assistant's reply arrives as a stream of `text_delta` events; the UI
  prints each delta as it arrives. Any markdown rendering must work on this
  stream, not on a complete message.
- Output is written straight to stdout by `DSREPL_Out`, which normalizes line
  endings to CRLF. ANSI colour/cursor codes are emitted only when
  `DSUI_ColorOn()` is true (a VT-capable terminal with colour enabled).

## Architecture

The work follows the existing architecture — keep cooked-mode input and
event-driven rendering. Add one new Harbour module and one small C extension;
restyle `dsui.prg`; extend `dsrepl.prg`.

### Files

New:

- `src/dsmarkdown.prg` — a streaming, line-buffered markdown-to-ANSI renderer,
  which also captures the suggested-next-prompt marker.
- `src/dsconsole.c` — a small C extension exposing `DSCON_PrefillInput()`,
  which injects text into the Windows console input buffer.
- `tests/test_markdown.prg` — tests for the markdown renderer.

Modified:

- `src/dsui.prg` — Claude Code-style banner, input-frame helpers, tool/result
  glyphs, a named colour palette; `DSUI_SystemPrompt` gains the suggested-prompt
  instruction.
- `src/dsrepl.prg` — draw the input frame; hold a per-turn markdown render
  state in the event callback; prefill the suggested prompt before reading the
  next line.
- `cc.hbp` — add `src/dsmarkdown.prg` and `src/dsconsole.c`.
- `tests/tests.hbp`, `tests/run_tests.prg` — register `test_markdown.prg`.
- `tests/test_ui.prg` — assertions for the new banner and input-frame helpers.

## The markdown renderer (`src/dsmarkdown.prg`)

The assistant reply streams in as `text_delta` chunks. A complete-message
renderer cannot be used. The renderer is therefore **streaming and
line-buffered**, mirroring the SSE parser pattern in `src/dssse.prg`:

- `DSMD_New()` returns a fresh render state (a hash): a pending-line buffer, a
  fenced-code-block flag, and a captured-suggestion slot.
- `DSMD_Feed( oState, cChunk )` appends the chunk to the buffer and, for every
  **complete** line (terminated by `\n`), renders that line and returns the
  accumulated ANSI text. A partial trailing line stays buffered.
- `DSMD_Flush( oState )` renders any buffered partial line (end of stream).
- `DSMD_Suggestion( oState )` returns the captured suggested prompt, or `""`.

Because a line is only rendered once complete, inline markdown within it is
unambiguous. Per-line rendering:

- **Fenced code block:** a line whose trimmed text is ```` ``` ```` (optionally
  with a language tag) toggles the fenced state. Lines inside a fence are
  emitted verbatim, indented two spaces, in the dim colour — no inline parsing.
- **Heading:** a line matching `#`…`######` followed by a space renders the
  heading text in bold (bright colour), without the `#` marks.
- **List item:** a line matching `- `, `* `, `+ ` or `<digits>. ` renders with
  a `•` bullet (or the kept number) and a two-space indent; the item text gets
  inline formatting.
- **Blank line:** emitted as-is.
- **Paragraph line:** inline formatting applied.

Inline formatting, applied to non-fence line text:

- `**bold**` → ANSI bold.
- `*italic*` / `_italic_` → ANSI italic (SGR 3).
- `` `code` `` → the code span in an inverse/coloured style.

Markdown rendering **never throws**: any text that does not match a rule is
emitted unchanged. When colour is off (`DSUI_ColorOn()` false) the renderer
strips the markers but emits no ANSI codes, so plain terminals stay readable.

### Suggested-prompt capture

The renderer is the only component that sees complete assistant lines while the
reply is still streaming, so it also detects the suggestion marker. When a
completed line's trimmed text begins with `Suggested next:` (case-insensitive),
the renderer stores the remainder (trimmed) as the suggestion and emits
**nothing** for that line — the line was buffered and never printed, so it never
reaches the screen. `DSMD_Flush` applies the same check to a final unterminated
line. The captured suggestion is read after the turn via `DSMD_Suggestion`.

## The console-prefill C extension (`src/dsconsole.c`)

Prefilling the cooked-mode input line means placing characters into the Windows
console input buffer so the OS line editor shows them as editable pending
input. The API is `WriteConsoleInputW`, which takes an array of `INPUT_RECORD`
structs — impractical to build through `hb_dynCall`. A small C extension is the
robust path; CCHarbour already builds with the MSVC toolchain and `cc.hbp`
already compiles a `.c` file.

`src/dsconsole.c` exposes one Harbour function:

- `DSCON_PrefillInput( cText )` — for each character of `cText`, builds a
  key-down `INPUT_RECORD` and calls `WriteConsoleInputW` on the console input
  handle (`GetStdHandle(STD_INPUT_HANDLE)`). It returns `.T.` on success and
  `.F.` if the console handle or API call fails — it never aborts the program.

When the next `DSREPL_ReadLine` runs, the cooked editor consumes those events
as if typed: the text appears on the prompt line and the user can edit it or
press Enter.

## REPL changes (`src/dsrepl.prg`)

- **Input frame:** replace the two-rule prompt framing in `DSREPL_Run` with a
  Claude Code-style rounded input box drawn by new `dsui.prg` helpers — a top
  border, the `> ` prompt line the user types on, a bottom border, and a dim
  hint line beneath.
- **Per-turn markdown state:** the render callback passed to `DS_AgentRun` is
  currently `{| hEv | DSREPL_Out( DSUI_RenderEvent( hEv ) ) }`. It becomes a
  closure holding a `DSMD_New()` state: a `text_delta` event feeds the markdown
  renderer (`DSMD_Feed`) and prints its output; every other event is rendered
  by `DSUI_RenderEvent` as before. A fresh markdown state is created per agent
  turn; `DSMD_Flush` runs when the turn ends.
- **Suggested prompt:** after a successful `DS_AgentRun`, the REPL reads
  `DSMD_Suggestion` from the turn's render state. If non-empty, it calls
  `DSCON_PrefillInput( suggestion )` immediately before the next
  `DSREPL_ReadLine`, so the suggestion appears prefilled and editable on the
  prompt line.

## UI changes (`src/dsui.prg`)

- **Banner:** `DSUI_Banner` becomes a single-panel rounded box in the Claude
  Code style: an accent glyph and `Welcome to CCHarbour`, a blank line,
  `/help for help`, a blank line, and the `model:` and `cwd:` lines. The
  current two-panel welcome/tips box is replaced.
- **Input-frame helpers:** new functions returning the rounded box's top
  border, bottom border, and the dim hint line, sized like the banner.
- **Glyphs:** the tool-call marker becomes `⏺` (U+23FA); the result tree keeps
  `⎿`. `DSUI_ToolLabel` and `DSUI_ResultBlock` keep their structure with
  spacing/colour aligned to Claude Code.
- **Colour palette:** named helpers for the Claude Code palette — a tan/orange
  accent, dim grey for borders and secondary text, the existing red for errors,
  and the diff add/remove backgrounds — so SGR codes are defined in one place
  rather than scattered as string literals.
- **System prompt:** `DSUI_SystemPrompt` gains a final instruction: end the
  reply with a line `Suggested next: <a short next prompt>` proposing what the
  user might do next. The line is captured and suppressed by the markdown
  renderer, so it never appears in the visible output.

## Data flow

1. `DSREPL_Run` draws the Claude Code-style banner, then the rounded input box.
2. The user types into the cooked-mode line; `DSREPL_ReadLine` returns it.
3. For a message turn, `DS_AgentRun` streams events to the REPL's render
   callback, which holds a fresh `DSMD_New()` state.
4. `text_delta` events feed `DSMD_Feed`; completed lines render to ANSI markdown
   and print; a `Suggested next:` line is captured and not printed. `tool_call`,
   `tool_result`, and `error` events render through `DSUI_RenderEvent`.
5. At turn end the callback runs `DSMD_Flush`; the REPL reads `DSMD_Suggestion`.
6. If a suggestion was captured, `DSCON_PrefillInput` injects it; the next
   prompt line shows it prefilled and editable.

## Error handling

- The markdown renderer never throws; unrecognized text is emitted unchanged,
  and with colour off it emits markers stripped but no ANSI codes.
- `DSCON_PrefillInput` returns `.F.` and does nothing harmful if the console
  input handle or `WriteConsoleInputW` is unavailable; the REPL ignores the
  result and simply shows an empty prompt.
- A turn that produces no `Suggested next:` line leaves the next prompt empty —
  normal behavior.

## Testing

- `tests/test_markdown.prg` (`Test_Markdown`) — fed through the existing
  Harbour test harness:
  - a line split across two `DSMD_Feed` chunks renders only once complete;
  - headings, bold, italic, inline code, bullet and numbered lists each render
    to the expected ANSI;
  - a fenced code block across multiple lines renders verbatim and dim;
  - a `Suggested next: X` line is captured by `DSMD_Suggestion` and produces no
    output;
  - with colour off, markers are stripped and no ANSI codes appear.
- `tests/test_ui.prg` — assertions that `DSUI_Banner` contains the welcome text,
  `cwd:`, and `model:` lines and the rounded-box glyphs, and that the new
  input-frame helpers return correctly sized bordered strings.
- `src/dsconsole.c` / `DSCON_PrefillInput` and the live input-frame drawing are
  verified by manual smoke testing — running `cc.exe`, confirming the banner
  and input box render, markdown output is formatted, and after a turn the
  suggested prompt appears prefilled and editable.
- `node`-style isolation does not apply here; all automated tests run through
  the existing `tests/run_tests.prg` harness, and `cc.exe` must build via
  `build.bat`.

## Out of scope

- Raw-mode input: live cursor editing, an in-box editing experience, multi-line
  input, key-chord handling.
- An animated spinner / thinking indicator with token count and elapsed time.
- A slash-command autocomplete popup.
- Syntax highlighting inside fenced code blocks.
- Any change to the web playground (sub-project B) — if its UI later mirrors
  this, that is a separate effort.

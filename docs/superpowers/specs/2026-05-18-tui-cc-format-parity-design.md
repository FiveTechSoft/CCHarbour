# CCHarbour Terminal UI — Claude Code Format Parity (round 2)

**Date:** 2026-05-18
**Status:** Approved design, ready for implementation plan
**Scope:** Native CCHarbour (`cc.exe`) terminal output only.

## Goal

Close the remaining format gaps between cc.exe's terminal output and Claude
Code's interactive TUI, found by running the same task through both. Five
changes (A–E):

- **A** — render a tool's result as a compact, tool-aware one-line summary
  (`Read 130 lines`) instead of dumping the whole result; keep the coloured
  diff block when a result is diff-formatted.
- **B** — prefix each assistant text segment with the `⏺` bullet.
- **C** — drop the inline `[tokens: …]` line printed after every turn.
- **D** — drop the `bye` line printed on exit.
- **E** — match Claude Code's colours: the tool-call line is no longer bold
  cyan; the accent colour becomes a truecolor coral.

The model still receives the full, unmodified tool output — only the on-screen
rendering changes.

## Background

A read-only comparison run (`Read README.md and summarize`) showed cc.exe
dumping the entire 130-line file under the `⎿` result glyph, whereas Claude
Code shows `⎿  Read 130 lines`. cc.exe also prints the tool-call line in bold
cyan (Claude Code uses its accent colour, not cyan), shows a per-turn token
line, and prints `bye` on exit — none of which Claude Code does.

## A — Tool-aware result summary

The render layer must know which tool produced a result. The `tool_call` event
carries `name` + `id`; the `tool_result` event carries `id` + `content`. The
REPL render layer correlates them through an `id → name` map (see "Render
state" below).

New function in `src/dsui.prg`:

```
FUNCTION DSUI_ResultSummary( cToolName, cContent ) -> cRenderedBlock
```

It returns the block to print under the `⎿` glyph:

1. **Diff-formatted content** — if `cContent` contains diff lines (detected with
   the existing `DSUI_DiffMark`), render the coloured diff block: lines kept,
   added lines on a green background, removed lines on a dark-red background,
   capped at 50 lines with a `… (N more lines)` marker. This is the existing
   `DSUI_ResultBlock` behavior and it is **retained**.
2. **Error content** — if `cContent` begins with `Error:`, show its first line.
3. **Otherwise, a tool-aware one-line summary:**
   - `read` → `Read <N> lines` (N = line count of `cContent`).
   - `write`, `edit` — the tool already returns a summary string
     (`Wrote <path>`, `Edited <path>`); show it unchanged.
   - `glob` → `Listed <N> files`, or the content unchanged when it is
     `No matches for …`.
   - `grep` → `Found <N> matches`, or the content unchanged when it is
     `No matches for …`.
   - `shell` → the first line of output followed by ` (<N> lines)` when there
     is more than one line; the content unchanged when it is a single line.
   - `web_search`, `web_fetch`, `github_read`, `github_write` → `<N> lines`.
   - Unknown tool → `<N> lines`.

The summary line is dimmed and prefixed with the `⎿` tree glyph and the same
indentation `DSUI_ResultBlock` uses today.

`DSUI_DiffMark` and the diff-block rendering are kept (reused by case 1).
`DSUI_ResultBlock` is either kept and called by `DSUI_ResultSummary` for the
diff case, or its diff-block logic is folded into `DSUI_ResultSummary` — the
implementation plan picks whichever is cleaner; the diff capability must remain.

## B — Assistant bullet

Claude Code prefixes every assistant text segment with `⏺`. cc.exe streams
assistant text with no prefix. The REPL render layer prints `⏺ ` (in the accent
colour) before the first `text_delta` of each contiguous assistant-text run. A
run ends at any non-`text_delta` event (`tool_call`, `tool_result`,
`iteration_start`, `error`); the next `text_delta` after such an event starts a
new run and gets a fresh bullet. This is tracked by an `inText` flag in the
render state.

## C — Drop the inline token line

`DSREPL_Run` currently prints `[tokens: prompt N, completion N]` after every
turn. Claude Code shows no such inline line. Remove it. The supporting code
that exists only to feed it — the `hUsage` accumulator, `DSREPL_MergeUsage`,
and `DSREPL_UsageLine` — is then dead and is removed as well. (Token usage is
still returned by `DS_AgentRun`; nothing displays it. A future `/context`-style
command could surface it, but that is out of scope.)

## D — Drop the exit line

`DSREPL_Run` ends by printing `bye`. Claude Code prints nothing on exit. Remove
that final `DSREPL_Out` line.

## E — Colours

- **Tool-call line:** `DSUI_RenderEvent`'s `tool_call` case currently colours
  the whole `⏺ Tool(args)` label bold cyan (`1;36`). Change it so the `⏺`
  glyph is in the accent colour and the `Tool(args)` label is in the default
  foreground (no cyan).
- **Accent colour:** `DSUI_Pal("accent")` becomes the truecolor coral
  `38;2;217;119;87` (approximating Claude Code's accent — the exact theme value
  is not extractable, this is a close match). The accent is used by the banner
  `✻`, the tool-call `⏺`, and the assistant `⏺` bullet.
- The result glyph `⎿` and summary line stay dim (`DSUI_Pal("dim")`).

## Render state

`DSREPL_RenderEv` currently receives `(hEv, oMd)` — a markdown renderer. It is
widened to receive a render-state hash created by a new `DSREPL_RenderNew()`:

```
{ "md" => DSMD_New(), "tools" => {=>}, "inText" => .F. }
```

- `md` — the streaming markdown renderer (as today).
- `tools` — the `id → name` map; populated on each `tool_call` event.
- `inText` — the assistant-bullet run flag (B).

`DSREPL_RenderEv( hEv, oRender )`:
- `text_delta` — if `oRender["inText"]` is false, print the accent `⏺ ` bullet
  and set it true; feed the text to `oRender["md"]` and print the result.
- `tool_call` — set `inText` false; record `oRender["tools"][id] := name`;
  render the tool-call line (accent `⏺` + plain label).
- `tool_result` — set `inText` false; look up the tool name from
  `oRender["tools"]` by `id`; render via `DSUI_ResultSummary`.
- `iteration_start`, `error`, other — set `inText` false; render as today.

The message-case and the iteration-cap continuation loop in `DSREPL_Run` create
the render state with `DSREPL_RenderNew()` instead of `DSMD_New()`, and pass
`{| hEv | DSREPL_RenderEv( hEv, oRender ) }`. `DSMD_Flush`/`DSMD_Suggestion` are
called on `oRender["md"]`.

## Error handling

Unchanged. `DSUI_ResultSummary` never throws — unrecognized content falls
through to the line-count summary; an empty content yields `0 lines`.

## Testing

`src/dsui.prg` is in the Harbour test build, so the pure functions are tested
in `tests/test_ui.prg` (`Test_UI`):

- `DSUI_ResultSummary` — `read` content of N lines → `Read N lines`; `write`/
  `edit` summary strings pass through; `grep` matches → `Found N matches`;
  `grep`/`glob` `No matches` pass through; `shell` multi-line → first line +
  `(N lines)`; an `Error:` content → its first line; diff-formatted content →
  a block containing the diff lines (with colour off, the markers are visible).

`src/dsrepl.prg` is not in the test build (the render-state wiring, the bullet,
the removed token/`bye` lines): verified by `build.bat` and a manual smoke
test against the live API.

## Out of scope

- A side-bordered input box (needs raw-mode input — previously excluded).
- A status line / `/context` command to surface token usage.
- Changing the banner text or layout (already Claude Code-style).
- Any change to the web playground.

# CCHarbour — Always-Visible Prompt with Mid-Turn Input

**Date:** 2026-05-19
**Status:** Approved design, ready for implementation plan
**Scope:** Native CCHarbour (`cc.exe`) only — no web playground change.

## Goal

Keep the prompt input box visible at all times, including while the agent is
working. The user can type at any moment. A message submitted mid-turn is
queued and answered when the current turn finishes; pressing `Esc`, or
submitting a line that starts with `/btw `, interrupts the current turn
instead.

## Background

Today the input box (`CCIN_ReadLine`, raw-mode editor in `src/ccinput.prg`) is
only shown between turns. While a turn runs (`CC_AgentRun` in
`src/ccagent.prg`, streaming through the `bOnEvent` callback), the user cannot
type. The only mid-turn interaction is the `Esc` key, polled by `CCCON_PeekEsc`
before each tool call, which opens a pause prompt (Enter / `c` / `a`).

This feature makes the input box persistent and lets the user type whenever
they want.

## Behavior

- **Always visible.** The input box is pinned to the bottom rows of the
  terminal. Agent output scrolls in the region above it; the box stays put.
- **Queue by default.** A plain message submitted with `Enter` mid-turn is
  appended to a FIFO queue. The current turn runs to completion, then each
  queued message is processed as its own turn, in order, until the queue is
  empty. A dim `[queued: <summary>]` line is printed when a message is
  queued.
- **`/btw` interrupts with a message.** A submitted line beginning with
  `/btw ` interrupts the current turn immediately; the text after `/btw ` (the
  remainder of the line) becomes the next user message and is answered at
  once.
- **`Esc` interrupts.** Pressing `Esc` interrupts the current turn with no
  new message; control returns to the idle prompt. The old `Esc` pause prompt
  (Enter / `c` / `a`) is removed.
- **Interrupted work is kept.** On interruption (either `Esc` or `/btw`), the
  partial assistant content and any tool results already produced this turn
  remain in the conversation history, so the agent keeps that context when it
  handles the next message.

## Architecture

### New module `src/ccprompt.prg`

Owns the persistent bottom input box and the message queue. State object
`oPrompt` (a hash):

- `editor` — a raw-mode editor state from `CCIN_New()`.
- `queue` — array of pending message strings (FIFO).
- `region` — `{ "rows", "cols", "top", "bottom" }`: the scroll-region bounds.
- `interrupt` — interruption state: `NIL` when none, otherwise a hash
  `{ "kind" => "esc" | "btw", "text" => <string> }` (`text` empty for `esc`).

Functions:

- `CCPROMPT_New()` — query `CCCON_Size()`, compute `region`, set the VT scroll
  region, draw the empty box, return `oPrompt`.
- `CCPROMPT_Poll( oPrompt )` — non-blocking. While `CCCON_KeyPending()` is
  true, read a key with `CCCON_ReadKey()` and feed it to the editor (using the
  existing `CCIN_Insert/Backspace/Delete/Left/Right/Home/End` operations). On
  `Enter`, classify the buffer with `CCPROMPT_Classify` and act (enqueue, or
  set `interrupt`). On `Esc`, set `interrupt` to the `esc` kind. Redraw the
  box. Returns an action string: `"none"`, `"queued"`, or `"interrupt"`.
- `CCPROMPT_Classify( cLine )` — pure. Returns a hash describing a submitted
  line: `{ "action" => "queue" | "btw", "text" => <string> }`. A line starting
  with `/btw ` (case-insensitive) yields `btw` with `text` = the trimmed
  remainder; anything else yields `queue` with `text` = the line.
- `CCPROMPT_Region( nRows, nCols )` — pure. Given a console size, returns the
  `region` hash; the box is the bottom 3 rows, the scroll region is rows
  `1 .. nRows-3`.
- `CCPROMPT_Enqueue( oPrompt, cText )` / `CCPROMPT_Dequeue( oPrompt )` — FIFO
  queue operations. `Dequeue` returns `NIL` when the queue is empty.
- `CCPROMPT_Redraw( oPrompt )` — render the box on the bottom rows, using
  cursor save/restore (`ESC[s` / `ESC[u`) so output position is preserved.
- `CCPROMPT_Interrupted( oPrompt )` — returns `.T.` when `interrupt` is set.
- `CCPROMPT_Teardown( oPrompt )` — reset the scroll region (`ESC[r`) and clear
  the box.

### New C functions in `src/ccconsole.c`

- `CCCON_Size()` — returns `{ "rows" => <n>, "cols" => <n> }` from
  `GetConsoleScreenBufferInfo` (the visible window size).
- `CCCON_KeyPending()` — returns `.T.` when a key-down event is waiting in the
  console input queue, without consuming it (non-blocking; peek of the input
  buffer for a `KEY_EVENT` key-down record).

### `src/ccagent.prg`

`CC_AgentRun` gains an optional `interrupt_check` entry in `hOpts` — a
codeblock evaluated for a logical result. The agent loop evaluates it at the
top of each iteration and before each tool call. When it returns `.T.`, the
loop stops and sets `hResult[ "stop_reason" ] := "interrupted"` (no extra
message appended; whatever is already in `aMessages` stays). The existing
`CCCON_PeekEsc` pause flow (the Enter / `c` / `a` prompt) is removed.

### `src/ccrepl.prg`

`Main`'s REPL loop is reworked:

1. `CCPROMPT_New()` — box visible, scroll region set (when on an interactive
   VT console; see Fallback).
2. Idle: poll the prompt in a light sleep loop until a message is submitted
   (queued with an empty turn running counts as the first message) — i.e. the
   first non-`/btw` submission, or a `/btw` submission, starts a turn.
3. Run the turn through `CCREPL_RunTurn` → `CC_AgentRun`, passing
   `interrupt_check => {|| CCPROMPT_Interrupted( oPrompt ) }`. The `bOnEvent`
   render callback also calls `CCPROMPT_Poll( oPrompt )` on every event.
4. When the turn ends:
   - interrupted with a `/btw` message → that text is the next user message,
     processed immediately;
   - interrupted by `Esc` → clear the interrupt, return to idle;
   - ended naturally → if the queue is non-empty, `CCPROMPT_Dequeue` and run
     the next turn; repeat until the queue is empty.
5. On exit, `CCPROMPT_Teardown`.

## Fallback

When output is not an interactive VT console — `CCCON_HasConsole()` is `.F.`
or `CCUI_ColorOn()` is `.F.` — or the terminal is shorter than 8 rows, the
pinned box and scroll region are not used and the REPL behaves as it does
today (the cooked/`CCIN_ReadLine` path between turns; no mid-turn typing).
The test runner always takes this path.

## Edge cases

- **Resize mid-turn.** `CCPROMPT_Redraw` recomputes `region` from a fresh
  `CCCON_Size()` each redraw, so a resize is picked up on the next event.
- **Blocking tool (e.g. `shell`).** Keys are not polled while a tool blocks;
  they are drained at the first event after the tool returns. Accepted for
  this version.
- **Output and the box.** All turn output goes through `CCREPL_Out` and lands
  inside the scroll region; the box is only ever drawn by `CCPROMPT_Redraw`
  with cursor save/restore, so output never corrupts it.
- **Empty submission.** An empty line (just `Enter`) is ignored — not queued,
  not an interrupt.

## Testing

`tests/test_prompt.prg` (`Test_Prompt`) — pure logic, no console:

- `CCPROMPT_Classify` — a plain line → `queue` with the line as `text`; a
  `/btw fix typo` line → `btw` with `text` = `"fix typo"`; case-insensitive
  `/BTW `; a bare `/btw` with no text → still `btw` with empty `text`.
- `CCPROMPT_Enqueue` / `CCPROMPT_Dequeue` — FIFO order; `Dequeue` on an empty
  queue returns `NIL`.
- `CCPROMPT_Region` — given `{ rows: 30, cols: 100 }`, the box is the bottom
  3 rows and the scroll region is `1..27`; a tiny console (rows < 8) is
  reported as fallback (no region).

The scroll region, `CCCON_Size`, `CCCON_KeyPending`, and box redraw are
verified by a manual smoke test, since the test runner has no real console.
Editor key operations are already covered by `tests/test_input.prg`.

## Files

New:
- `src/ccprompt.prg` — the persistent box and message queue.
- `tests/test_prompt.prg` — tests for the pure logic.

Modified:
- `src/ccconsole.c` — `CCCON_Size()`, `CCCON_KeyPending()`.
- `src/ccagent.prg` — `interrupt_check` option; `stop_reason => "interrupted"`;
  removal of the old `Esc` pause prompt.
- `src/ccrepl.prg` — reworked `Main` loop: prompt lifecycle, per-event polling,
  queue draining, `/btw` and `Esc` handling.
- `cc.hbp`, `tests/tests.hbp`, `tests/run_tests.prg` — wire in the new files.
- `pages/commands.md` — document `/btw`, the mid-turn queue, and `Esc`
  interrupt.
- `README.md` — update the key-bindings table.

## Out of scope

- Polling keys while a blocking tool runs (the `shell` tool's own loop could
  poll later — not now).
- Editing or reordering already-queued messages.
- Resuming an interrupted turn where it left off — interruption ends the turn;
  the kept history is context for the next turn, not a resume point.
- Any web playground change.

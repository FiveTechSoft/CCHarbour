# Persistent Todo Lists — Design

Date: 2026-05-22

A `todo_write` agent tool that lets the model maintain a visible task list
during a session. The list is rendered when updated and re-shown at the idle
prompt until every item is completed.

## Goal

Give the LLM agent a way to track multi-step work and keep that progress
visible to the user — matching Claude Code's TodoWrite. The list persists (in
view, at the idle prompt) until all its items are `completed`.

## Tool `todo_write`

A new tool, schema:

- `todos` — array, required. Each element is an object with:
  - `text` — string, the task description.
  - `status` — string, one of `pending`, `in_progress`, `completed`.

Every call replaces the whole list (full-list replace — no incremental merge).

New file `src/cctools_todo.prg` holds `CCTool_TodoWrite()` (the schema) and a
`STATIC CCTool_TodoWriteRun( hArgs )` executor. The executor:

1. Rejects a missing or non-array `todos` with an error string.
2. Normalises the list with `CCTODO_Norm`.
3. Stores it with `CCTODO_Set`.
4. Returns the rendered block — `CCUI_TodoBlock( CCTODO_Get() )` — as the tool
   result, so the model and the user both see the current list.

`todo_write` bypasses the permission gate. It only updates display state and
has no filesystem, network, or shell effect — there is nothing to approve.
This reuses the existing `ask_user` bypass mechanism in `CCPERM_Decide`.

## State module `src/cctodo.prg`

Holds the current list in a module-level `STATIC`, in memory for the session
(no disk persistence). Functions:

- `CCTODO_Norm( aTodos )` — pure. Returns a cleaned list: each element must be
  a hash with a string `text`; elements that are not are dropped. A `status`
  that is not one of the three valid values becomes `pending`. Returns an
  array of `{ "text" => <string>, "status" => <valid status> }` hashes.
- `CCTODO_Set( aTodos )` — runs `CCTODO_Norm` and stores the result.
- `CCTODO_Get()` — returns the stored list (an empty array before the first
  `CCTODO_Set`).
- `CCTODO_HasOpen()` — returns `.T.` when the stored list is non-empty and at
  least one item's `status` is not `completed`.

`CCTODO_Norm` is pure and unit-tested. `CCTODO_Set`/`Get`/`HasOpen` carry the
`STATIC` state and are tested through round-trip assertions.

## Renderer `CCUI_TodoBlock( aTodos )`

A pure render-to-string function in `src/ccui.prg`, alongside
`CCUI_QuestionBlock`. Produces a `Todos:` header line, then one line per item:
a status glyph, a space, and the item text. Each line ends in LF; the whole
block ends in LF.

Status glyphs (UTF-8, built from raw bytes like the other `CCUI_Glyph`
entries):

- `completed` → `√` (U+221A), dim colour.
- `in_progress` → `■` (U+25A0), accent colour.
- `pending` → `□` (U+25A1), default colour.

An empty list renders as just the `Todos:` header (it will not actually be
rendered in that case — see Display).

## Display points

The list appears in two places:

1. **On a `todo_write` call.** The executor returns `CCUI_TodoBlock(...)` as
   its tool result; the REPL's existing tool-result rendering prints it. No
   new REPL code path is needed for this.

2. **At the idle prompt.** In `CCREPL_Run`, at the same point where the
   rotating tip line is emitted (box mode, just before `CCREPL_PromptIdle`):
   if `CCTODO_HasOpen()` is true, emit `CCREPL_Out( CCUI_TodoBlock(
   CCTODO_Get() ) )` before the tip line. When every item is `completed`, or
   the list is empty, or it was replaced by an empty list, `CCTODO_HasOpen()`
   is false and nothing is shown. This is what "persistent until completed"
   means: the list stays in view at idle until the work is done.

The cooked / piped path (`oPrompt == NIL`) does not show the idle list, the
same as the rotating tip.

## Components and boundaries

- `src/cctodo.prg` — owns the list state and the pure normaliser. Knows
  nothing about rendering or the REPL.
- `CCUI_TodoBlock` (`ccui.prg`) — owns rendering. Pure; takes a list, returns
  a string.
- `src/cctools_todo.prg` — the tool. Wires the schema to `CCTODO_Set` +
  `CCUI_TodoBlock`.
- `CCREPL_Run` — the only consumer of the idle re-display, gated on
  `CCTODO_HasOpen()`.

## Registration

- `src/cctodo.prg` and `src/cctools_todo.prg` are added to `cc.hbp`,
  `cc_linux.hbp`, `cc_mac.hbp` (as `src/...`) and `tests/tests.hbp` (as
  `../src/...`).
- `todo_write` is registered in `CCTOOLS_Registry` (`src/cctools.prg`).
- `CCPERM_Decide` (`src/ccperm.prg`) bypasses the gate for `todo_write`,
  alongside the existing `ask_user` bypass.

## Testing

Unit tests:

- `tests/test_todo.prg` (new, `Test_Todo()`, registered in `run_tests.prg`):
  - `CCTODO_Norm` — a bad `status` becomes `pending`; a non-hash element is
    dropped; an element missing `text` is dropped; a valid list passes
    through unchanged.
  - `CCTODO_Set` / `CCTODO_Get` — round-trip stores and returns the list.
  - `CCTODO_HasOpen` — `.T.` with a `pending` or `in_progress` item; `.F.`
    when every item is `completed`; `.F.` for an empty list.
- `tests/test_ui.prg`:
  - `CCUI_TodoBlock` — output contains the `Todos:` header, every item's
    text, and the correct glyph per status.
- `tests/test_tools.prg`:
  - `todo_write` is registered; the builtin tool count goes from 12 to 13.

The idle re-display and the tool executor's interactive path are verified by
a manual run.

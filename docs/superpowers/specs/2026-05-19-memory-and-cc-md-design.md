# CCHarbour — Agent Memory and the CC.md Rename

**Date:** 2026-05-19
**Status:** Approved design, ready for implementation plan
**Scope:** Native CCHarbour (`cc.exe`) only.

## Goal

Give CCHarbour a persistent agent memory: a `memory.md` file the model
maintains across sessions through a dedicated `memory` tool, loaded into the
system prompt at the start of every session. As part of the same work, rename
the project-context file CCHarbour reads from `CLAUDE.md` to `CC.md`, so
running CCHarbour in a directory that already holds a Claude Code `CLAUDE.md`
does not cross-contaminate the two tools.

## Background

CCHarbour already reads a `CLAUDE.md` from the working directory
(`DSUI_ProjectContext`) and appends it to the system prompt
(`DSUI_SystemPrompt`); the `/init` command (`DSUI_InitPrompt`) asks the model
to create one. That file is read-only project context — it is never updated by
the agent. `memory.md` is the complement: agent-authored, agent-updated,
persisted between runs.

## The `memory` tool

A new tool `memory`, defined in a new module `src/dstools_memory.prg`. The tool
factory `DSTool_Memory( cMemPath )` captures the path to the memory file
(`memory.md`), so the path is injectable and the tool is unit-testable with a
temporary file. The registry passes `"memory.md"` (a working-directory,
per-project path).

Schema — one parameter object:
- `operation` — string, required: one of `append`, `read`, `clear`.
- `text` — string, required for `append`: the memory entry to add.

Behavior:
- `append` — appends `text` as a new line to `memory.md`, creating the file if
  it does not exist. Returns `"Remembered."`. A missing `text` returns
  `"Error: memory 'append' requires 'text'"`.
- `read` — returns the full current contents of `memory.md`, or
  `"(memory is empty)"` when the file is absent or empty.
- `clear` — empties `memory.md` (truncates it to zero length; the file may be
  left existing-but-empty). Returns `"Memory cleared."`.
- An unknown `operation` returns `"Error: memory: unknown operation '<op>'"`.
- The handler never throws; any file error is returned as an `"Error: ..."`
  string.

The tool is registered in `DSTools_Registry` (`src/dstools.prg`) alongside the
existing tools. `read` is offered even though `memory.md` is auto-loaded into
the system prompt, so the model can re-inspect it after its own `append`/`clear`
within a session.

## memory.md in the system prompt

`DSUI_SystemPrompt` currently builds: a base instruction, then the `CC.md`
project context (see the rename below). It gains a third section: the contents
of `memory.md`, when present and non-empty, appended under a clear heading that
tells the model this is its own persisted memory from previous sessions and
that it may update it with the `memory` tool. A new helper `DSUI_MemoryContext()`
reads `memory.md` (returns `""` when absent/empty), mirroring
`DSUI_ProjectContext`.

So every session's system prompt = base instructions + `CC.md` project context
+ `memory.md` agent memory.

## The CLAUDE.md → CC.md rename

In `src/dsui.prg`:
- `DSUI_ProjectContext` reads `CC.md` instead of `CLAUDE.md`.
- `DSUI_InitPrompt` instructs the model to create `CC.md` (not `CLAUDE.md`).
- The `DSUI_SystemPrompt` wording that refers to "the CLAUDE.md file" becomes
  "the CC.md file".

Documentation references to `CLAUDE.md` in `pages/` (the MkDocs site) are
updated to `CC.md` so the docs match the code.

There is no migration of an existing `CLAUDE.md` — a user who has one renames
it themselves; CCHarbour simply looks for `CC.md` from now on.

## Permissions

`src/dssettings.prg` `DSSettings_Defaults` gains a default permission for the
new tool: `memory => "allow"`. The memory tool is the agent's own
self-maintained file; gating it behind an "ask" prompt would defeat the
"updates itself" purpose. The `clear` operation is destructive but runs under
the same single `allow` permission — this is accepted: managing (including
clearing) its own memory is the agent's job, consistent with how the tool is
meant to work.

## Files

New:
- `src/dstools_memory.prg` — the `memory` tool.
- `tests/test_memory.prg` — tests for the tool.

Modified:
- `src/dstools.prg` — register `memory` in `DSTools_Registry`.
- `src/dsui.prg` — `DSUI_ProjectContext` reads `CC.md`; new `DSUI_MemoryContext`;
  `DSUI_SystemPrompt` appends memory; `DSUI_InitPrompt` says `CC.md`.
- `src/dssettings.prg` — `memory => "allow"` default permission.
- `cc.hbp` — add `src/dstools_memory.prg`.
- `tests/tests.hbp`, `tests/run_tests.prg` — register `test_memory.prg`.
- `pages/*.md` — `CLAUDE.md` references updated to `CC.md`.

## Error handling

- Every `memory` operation returns a string; file errors become `"Error: ..."`
  strings, never thrown (consistent with the other tools).
- `read`/`DSUI_MemoryContext` on an absent `memory.md` is not an error — empty
  memory, returns the empty-state value.
- A missing `text` on `append` returns the validation error string.

## Testing

`tests/test_memory.prg` (`Test_Memory`) — the tool is built with a temporary
memory-file path so tests do not touch a real `memory.md`:
- the tool schema (name `memory`, `operation` required);
- `append` to a non-existent file creates it and stores the entry; a second
  `append` adds a second line;
- `read` returns the stored content; `read` on an absent file returns the
  empty-state string;
- `clear` empties the file; a following `read` returns the empty-state string;
- `append` with no `text` returns the validation error;
- an unknown `operation` returns the unknown-operation error.

`tests/test_ui.prg` — assertions that `DSUI_InitPrompt` now says `CC.md` (not
`CLAUDE.md`), and that `DSUI_SystemPrompt`'s wording refers to `CC.md`.

The `memory.md` registry wiring and the live system-prompt assembly are
exercised by the existing suite plus a manual check.

## Out of scope

- A global (cross-project) memory file — `memory.md` is per-project only.
- Structured memory (entries with metadata, an index) — `memory.md` is a plain
  append-only-style markdown file; `clear` and `edit` cover the rest.
- Automatic migration of an existing `CLAUDE.md`.
- Any change to the web playground.

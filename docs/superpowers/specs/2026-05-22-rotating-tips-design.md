# Rotating Tips — Design

Date: 2026-05-22

A small REPL UX feature: surface short usage tips, both on the startup banner
and rotating on each return to the idle prompt.

## Goal

Help users discover CCHarbour's commands and features through brief tips,
without adding noise. One tip on the startup banner; a fresh tip each time the
prompt returns to idle, cycling sequentially through a fixed pool.

## Tip pool

A new function `CCUI_Tips()` in `src/ccui.prg` returns a hardcoded array of
short, single-line tip strings. Initial pool:

- `Use /clear to start fresh when switching topics`
- `Press Esc to interrupt the agent mid-turn`
- `Type /btw <note> to add context without interrupting`
- `/init writes a CC.md so the agent learns project conventions`
- `/cost shows token usage and estimated spend`
- `/save and /load keep conversations across sessions`
- `Edit per-tool permissions in .ccharbour/settings.json`

Two pure helper functions, also in `src/ccui.prg`:

- `CCUI_TipAt( nIndex )` — returns the tip at a 1-based index, wrapping modulo
  the pool length so any integer (including 0 and values past the end) maps to
  a valid tip. Concretely: `aTips[ ( ( nIndex - 1 ) % Len ) + 1 ]` with the
  modulo normalised to a non-negative result.
- `CCUI_TipLine( cTip )` — formats one tip as a dim-coloured line `Tip: <text>`
  ending in LF, using `CCUI_Color` with the `dim` palette entry.

All three are pure (no I/O) and unit-testable.

## Banner

The banner's right panel is nine rows, aligned row-for-row with the left
panel. The current rows are: header, blank, three getting-started lines,
divider, "What's new" header, the release tagline, and the cwd line.

Replace the third getting-started line (`Run /init to create a CC.md file`)
with a rotating tip line: `Tip: <text>`, where the tip is chosen at random
when the banner is built (`CCUI_TipAt` with a random index). The panel stays
nine rows, so the two-panel alignment is unchanged. The `/init` advice is not
lost — it is one of the tips in the pool.

## Idle tip line

The REPL (`src/ccrepl.prg`) keeps a module-level `STATIC s_nTipIdx := 0`.

Each time the prompt returns to idle in box mode — that is, in `CCREPL_Run`
just before `CCREPL_PromptIdle` is called — the REPL advances the index and
prints one tip:

```
CCREPL_Out( CCUI_TipLine( CCUI_TipAt( ++s_nTipIdx ) ) )
```

This emits a dim `Tip: ...` line into the scroll region above the persistent
input box. Because `s_nTipIdx` increments every idle and `CCUI_TipAt` wraps,
the tips cycle sequentially through the pool with no repeats until the pool is
exhausted.

The tip is shown only in interactive box mode (`oPrompt != NIL`). In the
cooked / piped / non-interactive path there is no benefit to printing tips, so
they are skipped there.

## Components and boundaries

- `CCUI_Tips()` — owns the tip pool. Pure.
- `CCUI_TipAt( nIndex )` — index-to-tip mapping with wraparound. Pure.
- `CCUI_TipLine( cTip )` — tip-to-display-line formatting. Pure.
- `CCUI_Banner` — consumes `CCUI_TipAt` for the banner tip line.
- `CCREPL_Run` — owns `s_nTipIdx` and the per-idle emission. The only stateful
  and I/O-bearing part.

## Testing

Unit tests in `tests/test_ui.prg`:

- `CCUI_Tips()` returns a non-empty array of strings.
- `CCUI_TipAt` wraps: index 1 and `Len+1` return the same tip; index 0 and
  index `Len` return the same tip; a large index returns a valid pool member.
- `CCUI_TipLine` output contains `Tip: ` and the supplied text and ends in LF.

The banner tip line and the per-idle emission are verified by manual run.

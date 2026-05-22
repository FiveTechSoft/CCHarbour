# REPL UX Enhancements — Design

Date: 2026-05-22

Three related improvements to the CCHarbour REPL front-end:

- **A.** `/clear` also wipes the terminal screen.
- **B.** A two-panel startup banner.
- **C.** An `ask_user` agent tool for interactive multiple-choice questions.

All three are console/UI changes. They share no state and can be built and
reviewed independently.

---

## A. `/clear` clears the terminal screen

### Current behaviour

`/clear` is parsed in `CCUI_ParseCommand` (`src/ccui.prg`) and handled in
`CCREPL_Run` (`src/ccrepl.prg`). It resets `aMsgs` to a fresh system-prompt
message, clears `s_hSessionUsage`, and prints `[conversation reset]`. The
terminal scrollback is left untouched.

### Change

Before the conversation reset, wipe the screen. A new helper:

```
STATIC FUNCTION CCREPL_ClearScreen( oPrompt )
```

- Gated on `CCCON_HasConsole() .AND. CCUI_ColorOn()`. When input is piped or
  colour is off, emitting VT codes would produce garbage — skip the wipe and
  only perform the conversation reset.
- Emits the VT sequence `ESC[3J` (clear scrollback) + `ESC[2J` (clear visible
  screen) + `ESC[H` (home cursor). The project already uses VT escapes
  (`src/ccprompt.prg`), so this is consistent with the existing console model.
- When `oPrompt != NIL` (the persistent input box is mounted), call
  `CCPROMPT_Activate( oPrompt )` after the wipe. `ESC[2J` clears the whole
  screen regardless of the scroll region, so the region, the output anchor
  (`ESC[s`), and the box itself must be re-established. `CCPROMPT_Activate`
  already does exactly that.

The screen is left **bare** after the wipe — the banner is **not** re-printed.

### Flow

The `/clear` case in `CCREPL_Run` calls `CCREPL_ClearScreen( oPrompt )` first,
then runs the existing reset (`aMsgs`, `s_hSessionUsage`, `[conversation
reset]` message). `[conversation reset]` is printed through `CCREPL_Out`,
which restores to the output anchor set by `CCPROMPT_Activate`, so the message
lands correctly inside the scroll region.

---

## B. Two-panel startup banner

### Current behaviour

`CCUI_Banner( cModel, cCwd, cUser )` builds a single-panel rounded box: a
six-row block-letter "CC" logo on the left, paired row-for-row with an info
column (name+version, tagline, `/help` hint, model, cwd). `cUser` is accepted
but unused (`HB_SYMBOL_UNUSED`).

### Change

Rewrite `CCUI_Banner` to render two side-by-side panels inside one rounded box,
99 display columns wide (matching the input frame). The content area between
the outer borders is split into a **left column (44 cols)**, a vertical divider
`│`, and a **right column (48 cols)**.

The shorter panel is padded with blank rows so both columns have equal height.
A new helper joins the two column row-arrays:

```
STATIC FUNCTION CCUI_BannerJoin( aLeft, aRight )
```

reusing `CCUI_PadCell` for per-cell width/alignment.

#### Left panel (cells centred)

- `Welcome back, <user>!` — `cUser` is now used. Fallback chain: `cUser`, then
  the `USER` environment variable (POSIX), then a generic `Welcome back!`.
- The existing six-row block "CC" logo, unchanged art, accent colour.
- `CCHarbour  v<version>` — accent colour.
- `model: <model>`

#### Right panel (cells left-aligned)

- `Tips for getting started` — header.
- blank
- `Type a request to begin`
- `Run /help to list commands`
- `Run /init to create a CC.md file`
- a divider line of horizontal glyphs
- `What's new` — header.
- the first line of `releasenotes.md`, truncated to the column width.

#### `releasenotes.md` lookup

Try `hb_DirBase() + "releasenotes.md"` (beside the executable) first, then the
file in the current working directory. If neither exists or the file is empty,
fall back to a static tagline (`CCHarbour v<version>`).

Caveat: a shipped binary only shows the live "What's new" line when
`releasenotes.md` sits beside `cc.exe`; otherwise the static fallback is shown.
This is acceptable — the fallback is always meaningful.

---

## C. `ask_user` agent tool — interactive multiple-choice questions

### Goal

Give the LLM agent a tool to ask the user a multiple-choice question, rendered
as an interactive selectable list, matching Claude Code's `AskUserQuestion`.

### Tool schema

New tool `ask_user`:

- `question` — string, required.
- `options` — array of 2-4 strings, required.

The model calls it; the REPL renders an interactive selector; the chosen string
is returned to the model as the tool result.

### New module `src/ccselect.prg`

Mirrors the `ccprompt.prg` split — pure logic separate from console I/O.

- `CCSEL_New( cQuestion, aOptions )` → state hash
  `{ question, options, cursor }`. The literal `"Other"` is appended to
  `options` automatically, so the user is never boxed in.
- `CCSEL_Move( oSel, nDelta )` — moves `cursor`, clamped to range. Pure.
- `CCSEL_SetCursor( oSel, nIndex )` — for digit-key jumps. Pure.
- `CCUI_QuestionBlock( oSel )` — pure render-to-string: a `●` bullet + the
  question, then one numbered row per option; the row at `cursor` is marked
  with a `❯` prefix and inverse video.
- `CCSEL_Run( oSel )` — the raw-key I/O loop. Reads keys via `CCCON_ReadKey`:
  Up/Down move the highlight, a digit key jumps to and selects that option,
  Enter confirms. When the confirmed option is `"Other"`, drop to an inline
  one-line text input; the typed text becomes the answer. Returns the selected
  (or typed) string.

### Tool file `src/cctools_ask.prg`

Holds the `ask_user` schema and its executor. The executor builds a selector
with `CCSEL_New`, runs `CCSEL_Run`, and returns the chosen text as the tool
result.

### Permission

`ask_user` bypasses the permission gate. Asking the user a question is
inherently consented — there is nothing to approve.

### Rendering and input ownership

The selector draws in the scroll region, above the persistent prompt box. The
tool executor runs synchronously inside tool execution — no SSE streaming runs
concurrently, so `CCPROMPT_Poll` does not compete for keystrokes. The selector
owns the keyboard for the duration of `CCSEL_Run`. The prompt box is left
intact and is not torn down.

### Non-interactive fallback

When there is no console (`CCCON_HasConsole()` is false — piped or
non-interactive input), the executor cannot prompt. It returns option 1 as the
default answer and notes in the result text that the choice was auto-selected.

### Registration

- Add the `ask_user` schema to the tool registry surfaced by
  `CCTOOLS_Schemas` (`src/cctools.prg`).
- Add `ccselect.prg` and `cctools_ask.prg` to the three build-project files:
  `cc.hbp`, `cc_linux.hbp`, `cc_mac.hbp`.

---

## Testing

- **A.** Unit-test `CCREPL_ClearScreen`'s gating logic (no-console path emits
  nothing). The VT emission itself is verified by manual run.
- **B.** Unit-test `CCUI_BannerJoin` (equal-height output, correct widths) and
  the `releasenotes.md` lookup/fallback. Snapshot-test `CCUI_Banner` output
  width.
- **C.** Unit-test the pure `ccselect.prg` helpers — `CCSEL_New` appends
  `"Other"`, `CCSEL_Move`/`CCSEL_SetCursor` clamp correctly,
  `CCUI_QuestionBlock` marks the cursor row. The `CCSEL_Run` key loop and the
  `cctools_ask` executor are verified by manual run.

Follow the existing test layout under `tests/`.

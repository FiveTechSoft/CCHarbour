CCHarbour v0.8.4 — Plan mode, expanded skill library, wider banner and input box.

## New since v0.8.3

- **Plan mode (`/plan`)** — a new command puts the session in "plan mode":
  the `write`, `edit`, `shell` and `github_write` tools are locked at the
  permission gate, the `writing-plans` skill is auto-activated, and the
  status line shows a `[plan-mode]` badge. The agent can read, grep, glob,
  fetch and reason freely but cannot modify the codebase until the user
  approves. `/plan <text>` enters plan mode AND submits `<text>` as the
  first planning prompt; `/plan accept` (or `/plan go`/`/plan approve`)
  unlocks the gate and tells the agent to proceed step by step;
  `/plan cancel` (or `/plan off`) drops the plan and unlocks.
- **Skills library expanded** — five new process-discipline skills
  shipped under `.ccharbour/skills/`:
  - `brainstorming` — explore intent and design before coding (clarify
    goal, list constraints, sketch alternatives, pick one with reason).
  - `writing-plans` — turn an approved approach into an ordered,
    verifiable, multi-step plan with a done criterion per step.
  - `tdd` — red/green/refactor with CCHarbour-specific test commands.
  - `debugging` — reproduce, isolate, hypothesise, verify; no guessing
    patches, root cause only.
  - `code-review` — checklist for correctness, scope creep, security,
    test coverage, readability before commit.
  Each has triggers (English + Spanish), so the agent auto-activates the
  matching skill when its description fits the request.
- **Wider banner and input box** — the welcome banner and the persistent
  input frame grew from 99 columns wide to 123, giving the model 117
  text columns inside the input box (was 93). The CC logo is unchanged
  but now has more breathing room.

## v0.8.3 — Unified tool-call block, ask_user selector polish, and richer mid-question controls.

### New since v0.8.2

- **Unified tool-call block** — every tool call now renders as a single
  block: a cyan-violet rule the full terminal width, the tool's display
  label ("Bash command", "Edit", "Read", "Glob", "Web fetch", ...) on its
  own line, the primary argument (command / path / pattern / url / query)
  indented in bright green, and any narration the model produced on a soft
  white line below.
- **`ask_user` block** — the selector now paints separator, " Ask user",
  blank, question, blank, options, blank, hint as one absolute-positioned
  block right above the input box. Up/Down navigate with wrap-around (Down
  on the last option lands on the first, Up on the first lands on the
  last); each repaint lands in the same rows so the screen no longer
  jitters or scrolls.
- **Hint tail** — every question lists `Esc to cancel · Tab to amend ·
  ctrl+e to explain` in dim under the options.
- **Mid-question keys** —
  - **Tab** (amend) drops the highlighted option into the input box
    pre-filled, so the user can edit and submit a tweaked version.
  - **Esc** cancels the question; the tool returns "User cancelled" so the
    model drops that line of questioning.
  - **Ctrl+E** asks the model to explain; the tool returns a sentinel the
    model interprets as "elaborate and re-ask".
- **Type in the box during a question** — printable keys, backspace,
  cursor keys, Home/End, Delete, Shift+Enter all edit the input box even
  while the selector is up. Enter on a non-empty box submits the line
  (cancelling the selector and queuing the message for the next turn);
  `/exit` or `/quit` quits cc immediately; `/btw <text>` records a mid-turn
  interrupt that the agent picks up at the next boundary.
- **Box prompt history** — Up/Down in the input box now navigate the
  history, matching the cooked-mode editor.
- **Cursor follows the box** — while the selector waits for a key, the
  visible cursor parks inside the input box rather than blinking above the
  options.
- **Content preserved** — when the question block first paints, the
  scroll region scrolls up by exactly the block's height so any model
  output above remains visible instead of being overwritten.

## v0.8.2 — Project skills: process-discipline checklists the model can load on demand, with a status line and an auto-trigger.

### New since v0.8.1

- **Project skills** — `.md` files under `.ccharbour/skills/` describe a
  checklist or set of instructions the model can pull in for the turn. Each
  skill has a name and a one-line description in YAML frontmatter; the model
  sees the list at session start and activates one with the new `use_skill`
  tool.
- **Status line** — the input box gained a fourth row that lists the
  currently active skills as bracketed orange tags (e.g. `[superpowers]`),
  so it is always clear which discipline is in effect.
- **Auto-trigger** — a skill can declare a `triggers:` line of
  comma-separated regex patterns in its frontmatter; if the user's input
  matches, the skill activates automatically, its body is injected into the
  conversation as a system note, and a `[skill 'X' auto-activated]` line is
  printed in the scroll. No regex match → no activation.
- **`/caveman` command** — first-class slash command that activates the
  caveman skill (ultra-compressed terse replies). Generalises to any skill
  via the same `CCREPL_ActivateSkill` path.
- **Sample skills shipped** — `.ccharbour/skills/superpowers.md`
  (brainstorm → plan → execute → verify checklist) and
  `.ccharbour/skills/caveman.md` (terse-mode rules).
- **System prompt awareness** — the available skills are listed in the
  system prompt so the model knows what is on offer without loading every
  body up front.

## v0.8.1 — Input box polish: white user echo and translucent-green "Suggested next".

### New since v0.8.0

- **User prompt echoed in white** — every submitted prompt is now reprinted
  in bright white in the scroll above the input box, so the transcript shows
  what was asked alongside the model's reply. Mid-turn queued messages are
  echoed the same way when they get handled.
- **"Suggested next" pre-filled in the box** — the model's `Suggested next:`
  line is loaded into the input box as a translucent green suggestion. Press
  Tab to accept it as the message, Backspace/Delete to clear it, or just
  start typing to replace it. The cooked-mode fallback already had this; box
  mode now matches.

## v0.8.0 — Linux and macOS support: cc now builds and runs on all three platforms.

### New since v0.7.0

- **Linux & macOS builds** — new `cc_linux.hbp` / `cc_mac.hbp` project files,
  a `build_cc_linux.sh` script, and `build-linux` / `build-mac` CI workflows.
  Every tagged release now ships a Windows, Linux and macOS binary.
- **POSIX console backend** — `ccconsole_mac.c` renamed to `ccconsole_posix.c`
  and shared by the Linux and macOS builds (termios/select, no OS-specific
  code). Added the `CCCON_Size` and `CCCON_KeyPending` functions it lacked.
- **Cross-platform shell tool** — the `shell` tool ran commands only through
  `cmd.exe`; it now uses `/bin/sh` on Linux and macOS. Without this every
  shell command failed on those platforms.
- **Auto-created settings** — on first run CCHarbour writes a default
  `.ccharbour/settings.json` so the configuration is there to discover and
  edit.
- **Build-project fix** — `cc_mac.hbp` was missing `ccprompt.prg`, leaving
  the macOS build broken since the always-visible prompt landed.

## v0.7.0 — Shell command timeouts with a live countdown, plus reliability fixes.

### New since v0.6.0

- **Shell timeout** — the `shell` tool now bounds how long a command may run.
  Set it with the `shell_timeout` setting (default 30s), an optional per-call
  `timeout` argument, or — when `shell_timeout` is 0 — an automatic
  per-command estimate.
- **Live countdown** — while a shell command runs, the REPL shows the
  configured timeout and the seconds still left, updated in place.
- **Reliability fixes** — repaired the timed-shell path: a missing
  `fileio.ch` include (`F_ERROR` undefined), an undefined `hb_TempFile()`
  link error, and a broken exit-code marker. Completion detection and the
  real exit code now come from `hb_processValue`.
- **UTF-8 sanitising** — tool results are scrubbed of invalid Unicode
  (`CC_SanitizeUTF8`) so they cannot break the API request JSON.
- **Better API errors** — API failure messages now include a dump of the
  HTTP response body.
- **Docs** — documented the shell timeout; corrected web search to DuckDuckGo.

## v0.6.0 — Massive refactor: all files and functions renamed from ds* to cc* prefix.

## New since v0.5.1

- **File renaming** — all source files renamed from `ds*.prg` to `cc*.prg` (e.g. `dsui.prg` → `ccui.prg`)
- **Function prefix change** — all public and static functions renamed from `DS*` to `CC*`
  (e.g. `DSUI_Version()` → `CCUI_Version()`, `DSREPL_Out()` → `CCREPL_Out()`)
- **Build system updated** — `.hbp`, `.bat`, test files and README all reflect the new names
- All 340 tests pass with 0 failures

## v0.5.1 — Playground fixes and updated documentation.

### New since v0.5.0
- **Playground fixes** — removed unused parameter in `web.js`, fixed registry test sort order
- **Documentation** — updated module table in README with detailed descriptions for all components

## v0.5.0 — DuckDuckGo web search (no API key needed), refactored REPL, Harbour ship logo, and more.

### New since v0.4.0
- **DuckDuckGo web search** — replaced Tavily with DuckDuckGo Instant Answer API, no API key required
- **REPL refactor** — cleaner multi-turn agent loop, fixed `LoadSession` bug, portable paths
- **Harbour-style ship logo** — new project branding in the startup banner
- **Spinner throttle** — slowed down from 30 ms to 100 ms for less flicker
- **Default model fix** — restored to `deepseek-v4-flash`

## Previous features (v0.1.0 — v0.4.0)
- Pause tool execution with Escape, web & GitHub tools, memory tool, web playground,
  conversation persistence, token cost tracking, multi-line input, Ctrl+C cancel,
  animated reasoning spinner, co_author setting, diff improvements, CI/CD

## Usage
```
REM Windows
set DEEPSEEK_API_KEY=sk-...
cc.exe
```
```
# Linux / macOS
export DEEPSEEK_API_KEY=sk-...
chmod +x cc-linux && ./cc-linux
```

This release ships three standalone x64 binaries: `cc.exe` (Windows, no DLLs
required), `cc-linux` (Linux) and `cc-macos` (macOS).

CCHarbour v0.8.1 — Input box polish: white user echo and translucent-green "Suggested next".

## New since v0.8.0

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

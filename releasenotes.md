CCHarbour v0.7.0 — Shell command timeouts with a live countdown, plus reliability fixes.

## New since v0.6.0

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
set DEEPSEEK_API_KEY=sk-...
cc.exe
```

The attached `cc.exe` is a standalone Windows x64 binary (no DLLs required).

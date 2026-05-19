CCHarbour v0.5.1 — Playground fixes and updated documentation.

## New since v0.5.0

- **Playground fixes** — removed unused parameter in `web.js`, fixed registry test sort order
- **Documentation** — updated module table in README with detailed descriptions for all components

## v0.5.0 — DuckDuckGo web search (no API key needed), refactored REPL, Harbour ship logo, and more.

### New since v0.4.0

- **DuckDuckGo web search** — replaced Tavily with DuckDuckGo Instant Answer API, no API key required
  - Works in both the terminal client (`cc.exe`) and the web playground
- **REPL refactor** — cleaner multi-turn agent loop, fixed `LoadSession` bug, portable path handling, deduplicated event emission
- **Harbour-style ship logo** — new project branding in the startup banner
- **Spinner throttle** — slowed down from 30 ms to 100 ms for less flicker
- **Default model fix** — restored to `deepseek-v4-flash` (was inadvertently changed to `deepseek-chat`)
- **Web playground** — DuckDuckGo integration, removed unused parameters, test sort-order fix

## Previous features (v0.1.0 — v0.4.0)

- **Pause tool execution** — press **Esc** before a tool runs to see a pause menu
- **Web tools** — `web_search` and `web_fetch` for searching and fetching web content
- **GitHub tools** — `github_read` and `github_write` for interacting with GitHub repos
- **Memory tool** — persistent memory across sessions
- **Web playground** — try CCHarbour in the browser at https://fivetechsoft.github.io/CCHarbour/playground/
- **Documentation site** — full docs at https://fivetechsoft.github.io/CCHarbour/
- **Conversation persistence** — `/save` and `/load` commands
- **Token cost tracking** — `/cost` command with per-turn and session summaries
- **Multi-line input** — Shift+Enter for newlines, paste detection
- **Ctrl+C cancel** — cancel a running stream mid-response
- **Animated reasoning spinner** — shows elapsed time and estimated tokens
- **co_author setting** — automatic Co-authored-by trailer in commits
- **Diff improvements** — better colour rendering, wider padding
- **CI/CD** — GitHub Actions builds cc.exe and auto-publishes releases on tags

## Usage
```
set DEEPSEEK_API_KEY=sk-...
cc.exe
```

The attached `cc.exe` is a standalone Windows x64 binary (no DLLs required).

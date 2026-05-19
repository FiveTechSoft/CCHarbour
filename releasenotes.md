CCHarbour v0.4.0 — Pause tool execution with Escape, plus all previous features.

## New since v0.3.0

- **Pause tool execution** — press **Esc** before a tool runs to see a pause menu:
  - **Enter** — continue with the tool
  - **c** — skip all remaining tools in this turn
  - **a** — abort the entire turn
- **Non-blocking Esc detection** — checks console input buffer between tool calls
- **Pause UI** — yellow box with clear options, no disruption to output flow

## Previous features (v0.1.0 — v0.3.0)

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

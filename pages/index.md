# CCHarbour

A terminal coding assistant — a Claude Code-style agent — written in
[Harbour](https://harbour.github.io/).

CCHarbour talks to an LLM, streams its replies, and lets the model use tools to
read, write and edit files, search the project, and run shell commands — all
from a single console executable.

```
╭─────────────────────────────────────────────────────────────────────────────╮
│                                        │ Tips for getting started           │
│      Welcome to CCHarbour, Anto!       │                                    │
│                \  |  /                 │ Type a request to begin            │
│              -- (CC) --                │ Run /help to list commands         │
│                /  |  \                 │ ────────────────────────────────── │
│          model: deepseek-chat          │ What's new ...                     │
╰─────────────────────────────────────────────────────────────────────────────╯
```

Try the **[Web Playground](playground/index.html)** — a browser-based version
of the assistant that runs entirely in the browser. You will need your own
[DeepSeek API key](https://platform.deepseek.com/api_keys) to use it.

## Highlights

- DeepSeek / OpenAI-compatible API client with SSE streaming
- Tool-using agent loop: read, write, edit, glob, grep, shell
- Permission gate — `allow` / `deny` / `ask`, with session upgrade
- `settings.json` configuration and `CLAUDE.md` project context
- UTF-8 console, auto-detected ANSI colour, Claude Code-style terminal UI

[Get started](getting-started.md){ .md-button .md-button--primary }

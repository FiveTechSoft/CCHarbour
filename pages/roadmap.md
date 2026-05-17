# Roadmap

## Status

### Done

- DeepSeek / OpenAI-compatible API client with SSE streaming
- Agent loop with tool calls and an iteration cap
- Tools: read, write, edit, glob, grep, shell
- Permission gate — `allow` / `deny` / `ask`, with session upgrade
- `settings.json` loading and `CLAUDE.md` project-instruction loading
- Diff rendering on edit / write
- UTF-8 console, auto-detected ANSI colour, Claude Code-style banner,
  framed prompt and tool-call rendering
- Commands: `/help`, `/init`, `/model`, `/clear`, `/exit`
- `build.bat` build script and GitHub Actions CI

### Missing

- REPL line editing — no arrow keys, no input history, no `Ctrl+C` to cancel
  a running stream
- Conversation persistence — history is lost on exit; no resume
- Multi-line / pasted-block input
- More commands — `/cost`, `/tools`, user-defined commands
- More tools — task list, web fetch
- Multi-provider support — DeepSeek only today

## Planned releases

| Version  | Theme            | Highlights                                            |
|----------|------------------|-------------------------------------------------------|
| **v0.1** | Current          | Streaming agent, tools, permissions, settings, UI     |
| **v0.2** | REPL experience  | Line editor, input history, `Ctrl+C` cancel, multiline |
| **v0.3** | Persistence      | Save and resume conversations, `/cost` summary        |
| **v0.4** | Tools & commands | Task-list tool, web fetch, `/tools`, custom commands  |
| **v0.5** | Providers        | Pluggable backends, `CLAUDE.md` directory discovery   |

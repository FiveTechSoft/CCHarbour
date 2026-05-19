# CCHarbour

A terminal coding assistant — a Claude Code-style agent — written in
[Harbour](https://harbour.github.io/). CCHarbour talks to an LLM, streams its
replies, and lets the model use tools to read, write and edit files, search the
project, and run shell commands, all from a single console executable.

**Documentation:** <https://fivetechsoft.github.io/CCHarbour/>  
**Web Playground:** <https://fivetechsoft.github.io/CCHarbour/playground/>

```
╭─────────────────────────────────────────────────────────────────────────────╮
│                                        │ Tips for getting started           │
│      Welcome to CCHarbour, Anto!       │                                    │
│                \  |  /                 │ Type a request to begin            │
│              -- (CC) --                │ Run /help to list commands         │
│                /  |  \                 │ ────────────────────────────────── │
│        model: deepseek-v4-flash        │ What's new ...                     │
╰─────────────────────────────────────────────────────────────────────────────╯
```

## How it works

The REPL reads a line, sends the conversation to the LLM, and streams the
response. When the model emits a tool call, CCHarbour runs it through a
permission gate and feeds the result back, looping until the model produces a
final answer or hits the iteration cap.

The default backend is the [DeepSeek](https://api.deepseek.com) chat API
(OpenAI-compatible).

## Requirements

- **Harbour** 3.2 — installed at `C:\harbour` (adjust `build.bat` otherwise).
- **Visual Studio** C++ toolchain (2019 Build Tools or 2022) — provides the
  MSVC linker and CRT the `msvc64` Harbour libraries need.
- Windows. The console layer uses Win32 APIs directly.

## Build

```bat
build.bat
```

`build.bat` locates a Visual Studio toolchain and forces dynamic-CRT linking —
the shipped `msvc64` Harbour libraries were built against `/MD`, so a default
static-CRT link leaves CRT import symbols unresolved. It produces `cc.exe`.

**Hot-swap:** `update_cc.bat` replaces `cc.exe` with a freshly-built copy
(`cc_new.exe`) without needing to stop a running REPL session.

## Run

```bat
set DEEPSEEK_API_KEY=sk-...
cc.exe
```

Optional: `cc.exe <model>` overrides the model; `DEEPSEEK_MODEL` does the same
via the environment.

### Commands

| Command         | Action                                          |
|-----------------|-------------------------------------------------|
| `/help`         | show the command list                           |
| `/init`         | analyse the project and write `CC.md`           |
| `/model [name]` | show the current model, or switch to `<name>`   |
| `/clear`        | reset the conversation                          |
| `/cost`         | show token usage and estimated cost             |
| `/save [file]`  | save the conversation to disk                   |
| `/load [file]`  | load a saved conversation                       |
| `/exit`         | quit (alias `/quit`)                            |

Anything else is sent to the assistant.

### Key bindings (raw-mode input box)

| Key           | Action                        |
|---------------|-------------------------------|
| ← / →         | move cursor left / right      |
| ↑ / ↓         | navigate input history        |
| Home / End    | jump to start / end of line   |
| Delete        | delete character at cursor    |
| Backspace     | delete character before cursor|
| Ctrl+C        | cancel a running stream       |
| Shift+Enter   | insert a newline (multi-line) |
| Enter         | submit the line               |

### Configuration

Settings load from `.ccharbour/settings.json` under the working directory (or
the path in `CCHARBOUR_CONFIG`), merged over the defaults:

| Key              | Default                     | Meaning                          |
|------------------|-----------------------------|----------------------------------|
| `model`          | `deepseek-v4-flash`         | model name                       |
| `base_url`       | `https://api.deepseek.com`  | API endpoint                     |
| `max_iterations` | `25`                        | tool-call loop cap per turn      |
| `color`          | `true`                      | ANSI colour output               |
| `permissions`    | see below                   | per-tool gate                    |

Each tool maps to `allow`, `deny` or `ask`. Defaults: `read`, `glob`, `grep`,
`github_read` and `memory` are `allow`; `write`, `edit`, `shell`, `web_search`,
`web_fetch` and `github_write` are `ask`. A `CC.md` file in the working
directory is appended to the system prompt as project instructions.

## Project layout

| File                   | Responsibility                              |
|------------------------|---------------------------------------------|
| `src/dsrepl.prg`       | entry point, REPL loop, console setup       |
| `src/dsui.prg`         | banner, prompt, command parsing, rendering  |
| `src/dsagent.prg`      | agent loop — tool-call orchestration        |
| `src/dsapi.prg`        | DeepSeek/OpenAI-compatible API client       |
| `src/dshttp.prg`       | HTTP client                                 |
| `src/dssse.prg`        | server-sent-events stream parsing           |
| `src/dstools*.prg`     | tool registry + file / search / shell tools |
| `src/dsdiff.prg`       | unified-diff rendering for edits            |
| `src/dssettings.prg`   | `settings.json` loading                     |
| `src/dsperm.prg`       | permission gate (allow / deny / ask)        |
| `src/dsconfig.prg`     | API-key resolution                          |
| `src/dsinput.prg`      | raw-mode line editor with input history     |
| `src/dsconsole.c`      | Win32 console layer (raw mode, key reading) |
| `tests/`               | test suite (`test_*.prg`)                   |
| `docs/superpowers/`    | design specs and implementation plans       |

## Status

### Done

- DeepSeek / OpenAI-compatible API client with SSE streaming
- Agent loop with tool calls and an iteration cap with extend prompt
- Tools: read, write, edit, glob, grep, shell, web, github, memory
- Permission gate — `allow` / `deny` / `ask`, with session upgrade
- `settings.json` loading with defaults
- `CC.md` project-instruction loading
- Diff rendering on edit / write
- UTF-8 console, auto-detected ANSI colour, Claude Code-style banner,
  framed prompt and tool-call rendering
- Raw-mode line editor with input history (↑/↓), cursor keys, Home/End, Delete,
  multi-line input with Shift+Enter and paste detection
- `Ctrl+C` to cancel a running stream
- Conversation persistence — `/save` and `/load` commands
- `/cost` command showing token usage and estimated cost per turn and session
- Animated spinner with estimated token count during model reasoning
- Compact token-usage bar displayed after each turn
- Commands: `/help`, `/init`, `/model`, `/clear`, `/cost`, `/save`, `/load`, `/exit`
- `build.bat` build script
- `update_cc.bat` hot-swap script to replace `cc.exe` without stopping the REPL
- Test suite (340+ tests, 0 failures)

### Missing

- Multi-provider support — DeepSeek only today
- `CC.md` discovery from parent and home directories
- More tools — task list, web fetch result formatting
- More commands — `/tools`, user-defined commands

## Roadmap

**v0.3 — current.** `Ctrl+C` to cancel a stream, multi-line input
for pasted code, `/save` & `/load` conversation persistence, `/cost`
token/cost summary, animated reasoning spinner with token estimate.

**v0.4 — tools & commands.** Task-list tool, `/tools`, and user-defined
slash commands.

**v0.5 — providers.** Pluggable backends beyond DeepSeek; `CC.md` discovery
up the directory tree and from the home directory.

## Ideas

A running scratch list of UI/UX ideas to explore — terminal tricks, status
display, and ergonomics borrowed from Claude Code — is kept in
[`todo.txt`](todo.txt).

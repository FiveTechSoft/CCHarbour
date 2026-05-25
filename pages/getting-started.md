# Getting started

This guide walks you from "I just heard about CCHarbour" to a productive
first session in about five minutes. Three ways to run it:

1. [Download a release binary](#download) — fastest, no toolchain needed.
2. [Try the web playground](https://fivetechsoft.github.io/CCHarbour/playground/) — runs in your browser, no install.
3. [Build from source](#build-from-source) — if you want to hack on it.

## Pick a provider and get an API key

CCHarbour talks to any OpenAI-compatible chat API. The default backend is
DeepSeek; you can also point it at GLM (Zhipu), Moonshot Kimi, OpenAI, or
any other compatible endpoint by changing `base_url` in `settings.json`
and the model name. See the [Providers](configuration.md#providers)
section in Configuration for sign-up links, indicative pricing and
benchmark scores to help you choose.

## Download

The [latest release](https://github.com/FiveTechSoft/CCHarbour/releases/latest)
ships three binaries built fully static — no DLLs, no shared libs, no
runtime dependencies.

| File         | Platform                         | Size          |
|--------------|----------------------------------|---------------|
| `cc.exe`     | Windows x64 (MSVC mingw-w64)     | ~2.2&nbsp;MB  |
| `cc-linux`   | Linux x64 (glibc, dynamic-link)  | ~2.0&nbsp;MB  |
| `cc-macos`   | macOS Intel x64 (clang)          | ~1.6&nbsp;MB  |

Drop it anywhere on your `PATH` (or run it from a project directory).

## First run

=== "Linux / macOS"

    ```bash
    chmod +x cc-linux      # or cc-macos
    export DEEPSEEK_API_KEY=sk-...
    ./cc-linux
    ```

=== "Windows (cmd)"

    ```bat
    set DEEPSEEK_API_KEY=sk-...
    cc.exe
    ```

=== "Windows (PowerShell)"

    ```powershell
    $env:DEEPSEEK_API_KEY = "sk-..."
    .\cc.exe
    ```

The banner appears with your username, the model, and the current
working directory. Type a request and the agent gets to work.

!!! tip "Override the model on the fly"
    `cc deepseek-v3.2` (or any chat model your backend serves). Setting
    the `DEEPSEEK_MODEL` env var does the same thing.

## Your first session

Try this in order — each command exercises a different feature.

1. **Ask a question about the project.**
   *"What languages does this repo use, and where is the entry point?"*
   The agent reads files with `glob` / `grep` / `read`, then answers.
2. **Make a small edit.** *"Add a top-line comment to every .prg file
   explaining what the module does."* The first `edit` call prompts
   because `edit` defaults to `ask`. Hit `y` once, or `a` to allow for
   the rest of the session.
3. **Try a slash command.** Type `/help` for the full list.
4. **Save the conversation.** `/save my-session` writes it to disk;
   `/load my-session` resumes it next time.

## Common next steps

- **Tell the agent about your project once.** Run `/init` to have it
  inspect the repo and write a `CC.md`; future sessions will load that
  automatically.
- **Pin a discipline.** `/caveman` for ultra-terse replies. `/plan`
  before a refactor — the agent describes the plan, you approve, only
  then can it `write`/`edit`/`shell`.
- **Pin a goal.** `/goal <text>` arms a "keep working until the
  condition is met" loop: the agent emits `GOAL COMPLETE` when done,
  otherwise the REPL auto-feeds `Continue toward the goal.` between
  turns (capped at 25 auto-iterations).
- **Save tokens.** `/lean` trims the system prompt for long sessions.
- **Watch the spend.** `/cost` shows token usage and estimated price.
- **Snapshot the session.** `/save [name]` writes the full state to
  JSON — messages, model, usage, goal, modes, skills, timer and the
  pending suggestion. `/load [name]` round-trips the whole thing.
- **Background subagents.** When the model calls
  `dispatch_agent_background`, the subagent runs on a worker thread
  and the parent keeps going. Inspect with `/tasks`, view with
  `/tasks view bg1`, cancel with `/tasks kill bg1`.
- **Skills.** Drop your own checklists under `.ccharbour/skills/` —
  see the seven that ship by default.

## Build from source

Need to hack on CCHarbour itself, or build for a platform we don't
publish? You'll need **Harbour 3.2** (with `hbmk2` on `PATH`) and a C
compiler.

=== "Windows"

    Requires the **Visual Studio C++ build tools** (2019 or 2022).
    The shipped `msvc64` Harbour libraries link against `/MD`, so
    `build.bat` forces dynamic-CRT linking to keep the link clean.

    ```bat
    build.bat
    ```

    Produces `cc.exe` in the working directory. `update_cc.bat`
    hot-swaps a fresh build into place without stopping a running REPL.

=== "Linux"

    Requires `gcc`.

    ```bash
    ./build_cc_linux.sh
    ```

    Wraps `hbmk2 cc_linux.hbp` and produces `cc`.

=== "macOS"

    Requires `clang` from the Xcode command-line tools.

    ```bash
    hbmk2 cc_mac.hbp
    ```

    Produces `cc`. The console layer (`ccconsole_posix.c`) is shared
    with the Linux build.

## Stuck?

- Read the [Commands](commands.md) reference for every slash command and tool.
- Check [Configuration](configuration.md) for `settings.json`, the permission gate, skills, and the `CC.md` / `memory.md` files.
- The [roadmap](roadmap.md) lists what is shipped and what's coming next.
- Open an [issue](https://github.com/FiveTechSoft/CCHarbour/issues) on GitHub.

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

The input box stays visible at all times, including while the agent is working.
A plain message submitted with Enter mid-turn is queued and answered after the
current turn finishes (multiple messages queue in order). A line beginning with
`/btw <text>` interrupts the current turn immediately and is answered next.
Pressing `Esc` also interrupts the current turn (with no new message); any
partial work and tool results already produced are kept in the conversation.

| Key              | Action                                                  |
|------------------|---------------------------------------------------------|
| ← / →            | move cursor left / right                                |
| ↑ / ↓            | navigate input history                                  |
| Home / End       | jump to start / end of line                             |
| Delete           | delete character at cursor                              |
| Backspace        | delete character before cursor                          |
| Ctrl+C           | cancel a running stream                                 |
| Shift+Enter      | insert a newline (multi-line)                           |
| Enter            | submit the line (queued if agent is busy)               |
| Esc              | interrupt the running turn (no new message)             |
| `/btw <text>`    | interrupt the running turn; answer `<text>` next        |

### Configuration

Settings load from `.ccharbour/settings.json` under the working directory (or
the path in `CCHARBOUR_CONFIG`), merged over the defaults:

| Key              | Default                     | Meaning                          |
|------------------|-----------------------------|----------------------------------|
| `model`          | `deepseek-v4-flash`         | model name                       |
| `base_url`       | `https://api.deepseek.com`  | API endpoint                     |
| `max_iterations` | `25`                        | tool-call loop cap per turn      |
| `color`          | `true`                      | ANSI colour output               |
| `co_author`      | *(none)*                    | `Co-authored-by` trailer auto-added to `git commit` |
| `shell_timeout`  | `30`                        | max seconds a shell command may run (0 = auto-estimate) |
| `permissions`    | see below                   | per-tool gate                    |

Each tool maps to `allow`, `deny` or `ask`. Defaults: `read`, `glob`, `grep`,
`github_read` and `memory` are `allow`; `write`, `edit`, `shell`, `web_search`,
`web_fetch` and `github_write` are `ask`. A `CC.md` file in the working
directory is appended to the system prompt as project instructions.

## Project layout

| Módulo (`src/`)       | Propósito |
|-----------------------|-----------|
| `ccrepl.prg`          | Punto de entrada (`Main`), bucle REPL interactivo, manejo de comandos `/`, ejecución de turnos del agente, renderizado de eventos, barra de tokens, spinner animado, carga/guardo de sesiones |
| `ccagent.prg`         | Bucle multi-turno del agente: llama a la API DeepSeek, ejecuta herramientas, maneja pausa por Esc, límite de iteraciones con opción de extender |
| `ccapi.prg`           | Cliente de la API DeepSeek (Chat Completions con streaming SSE), construcción del cuerpo de la petición, clasificación de errores HTTP/API/red |
| `cchttp.prg`          | Transporte HTTP vía subproceso `curl.exe` (streaming y fetch), parseo del código de estado HTTP desde dump de cabeceras, soporte cancelación vía Ctrl+C |
| `ccsse.prg`           | Parser SSE (Server-Sent Events): extrae `text_delta`, `reasoning_delta`, `tool_call_delta`, `finish`, `usage` y `[DONE]` del stream |
| `ccconfig.prg`        | Resolución de API key y base URL (precedencia: parámetro → entorno → archivo) |
| `ccsettings.prg`      | Carga de `settings.json` fusionado sobre valores por defecto; permisos, modelo, color, `co_author` |
| `cctools.prg`         | Registro y despacho de herramientas: crea el registry, genera schemas OpenAI, ejecuta el handler con validación de argumentos y captura de errores |
| `cctools_file.prg`    | Herramientas `read` (con line-numbered output, offset, max_lines), `write` (crea directorios, muestra diff), `edit` (reemplazo exacto con `replace_all`) |
| `cctools_search.prg`  | Herramientas `glob` (lista archivos con máscara recursiva) y `grep` (regex sobre contenidos) |
| `cctools_shell.prg`   | Herramienta `shell`: ejecuta comandos vía `cmd.exe /c`, inyecta automáticamente `Co-authored-by` en `git commit` |
| `cctools_web.prg`     | Herramientas `web_fetch` (GET vía HTTP) y `web_search` (DuckDuckGo Instant Answer API sin API key) |
| `cctools_github.prg`  | Herramientas `github_read` (repo, file, list, issues, issue, prs, pr, search) y `github_write` (create_issue, comment, create_pr) |
| `cctools_memory.prg`  | Herramienta `memory`: operaciones `append`/`read`/`clear` sobre `memory.md`, persistente entre sesiones |
| `ccperm.prg`          | Puerta de permisos: envuelve el executor raw con lógica `allow`/`deny`/`ask`; opción "a" (allow siempre) dura lo que dura la sesión |
| `ccdiff.prg`          | Diff línea por línea vía LCS (Longest Common Subsequence): detecta líneas añadidas/eliminadas con 3 líneas de contexto, formato Claude Code-style |
| `ccmarkdown.prg`      | Renderizado Markdown → ANSI en streaming: headings, listas, código (fence e inline), **bold**, *italic*, captura de "Suggested next:" |
| `ccui.prg`            | UI completa: banner con logo "CC", parseo de comandos `/`, colores ANSI, palette, system prompt con CC.md + memory.md, resumen de tool calls, diff coloreado, caja de input con marco |
| `ccinput.prg`         | Editor multilínea en raw-mode: cursor keys, Home/End, Delete, historial (↑/↓), paste detection (<50ms), sugerencias vía Tab, Shift+Enter para nueva línea |
| `ccconsole.c`         | Soporte nativo Windows (Win32 API): detección de consola, raw mode, lectura de teclas, detección no-bloqueante de Ctrl+C y Escape |
| `tests/`               | Suite de tests (340+ tests, 0 fallos) |
| `docs/superpowers/`    | Especificaciones de diseño y planes de implementación |

## Status

### Done (v0.5.0)

- DeepSeek / OpenAI-compatible API client with SSE streaming
- Agent loop with tool calls, iteration cap with extend prompt; **Esc interrupts the turn**, `/btw` interrupts and queues a reply, plain mid-turn input queues for after the turn
- Tools: read, write, edit, glob, grep, shell, web (search & fetch), github (read & write), memory
- **DuckDuckGo web search** — no API key required (replaced Tavily)
- Permission gate — `allow` / `deny` / `ask`, with session upgrade
- `settings.json` loading with defaults and `co_author` setting
- `CC.md` project-instruction loading
- Diff rendering on edit / write
- UTF-8 console, auto-detected ANSI colour, Claude Code-style banner with
  **Harbour ship logo**, framed prompt and tool-call rendering
- Raw-mode line editor with input history (↑/↓), cursor keys, Home/End, Delete,
  multi-line input with Shift+Enter and paste detection
- `Ctrl+C` to cancel a running stream
- Conversation persistence — `/save` and `/load` commands
- `/cost` command showing token usage and estimated cost per turn and session
- Animated reasoning spinner with estimated token count during model reasoning
- Compact token-usage bar displayed after each turn
- Web playground at <https://fivetechsoft.github.io/CCHarbour/playground/>
- Documentation site at <https://fivetechsoft.github.io/CCHarbour/>
- CI build with GitHub Actions; auto-publish releases on tag push
- Commands: `/help`, `/init`, `/model`, `/clear`, `/cost`, `/save`, `/load`, `/exit`
- `build.bat` build script (MSVC) and CI build (mingw-w64)
- `update_cc.bat` hot-swap script to replace `cc.exe` without stopping the REPL
- Test suite (340+ tests, 0 failures)

### Missing / planned

- Multi-provider support — DeepSeek only today
- `CC.md` discovery from parent and home directories
- More tools — task list, web fetch result formatting
- More commands — `/tools`, user-defined commands

## Releases

**v0.7.0 — current.** Shell command timeouts (`shell_timeout` setting, per-call `timeout`, auto-estimate) with a live countdown, timed-shell reliability fixes, UTF-8 tool-result sanitising, and richer API error messages, plus all features from v0.6.0.

**v0.6.0 — previous.** Massive refactor: all files and functions renamed from ds* to cc* prefix (e.g. `dsui.prg` → `ccui.prg`, `DSUI_Version()` → `CCUI_Version()`), plus all features from v0.5.1.

**v0.5.1 — previous.** Playground fixes and updated documentation,
plus all features from v0.5.0.

**v0.5.0 — previous.** DuckDuckGo web search (no API key needed),
REPL refactor (fixed `LoadSession` bug, portable paths, deduplicated events),
Harbour ship logo, spinner throttle, plus all features from v0.4.0 and v0.3.0.

**v0.4.0 — previous.** Pause tool execution with Escape key, plus all v0.3.0 features.

**v0.3.0 — previous.** Web & GitHub tools, memory tool, web playground,
animated reasoning spinner, conversation persistence (`/save`, `/load`),
`/cost`, multi-line input, `Ctrl+C` cancel, `co_author` setting.

**v0.6 (planned).** Pluggable backends beyond DeepSeek; `CC.md` discovery
up the directory tree and from the home directory.

## Ideas

A running scratch list of UI/UX ideas to explore — terminal tricks, status
display, and ergonomics borrowed from Claude Code — is kept in
[`todo.txt`](todo.txt).

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

CCHarbour builds on **Windows, Linux and macOS**. The console layer has a
native Win32 backend (`ccconsole.c`) and a shared POSIX backend
(`ccconsole_posix.c`, termios/select); everything else is the same Harbour
source on every platform.

- **Harbour** 3.2 — `hbmk2` on `PATH`.
- A C compiler:
  - Windows — Visual Studio C++ toolchain (2019/2022 Build Tools) for
    `build.bat`, or mingw-w64 (used by CI).
  - Linux — gcc.
  - macOS — clang (Xcode command-line tools).

## Build

### Windows

```bat
build.bat
```

`build.bat` locates a Visual Studio toolchain and forces dynamic-CRT linking —
the shipped `msvc64` Harbour libraries were built against `/MD`, so a default
static-CRT link leaves CRT import symbols unresolved. It produces `cc.exe`.

**Hot-swap:** `update_cc.bat` replaces `cc.exe` with a freshly-built copy
(`cc_new.exe`) without needing to stop a running REPL session.

### Linux

```sh
./build_cc_linux.sh
```

Wraps `hbmk2 cc_linux.hbp` and produces `cc`. Needs Harbour and gcc.

### macOS

```sh
hbmk2 cc_mac.hbp
```

Produces `cc`. Needs Harbour and clang.

## Run

```bat
REM Windows
set DEEPSEEK_API_KEY=sk-...
cc.exe
```

```sh
# Linux / macOS
export DEEPSEEK_API_KEY=sk-...
./cc
```

Optional: `cc <model>` overrides the model; `DEEPSEEK_MODEL` does the same
via the environment.

### Commands

| Command         | Action                                          |
|-----------------|-------------------------------------------------|
| `/help`         | show the command list                           |
| `/init`         | analyse the project and write `CC.md`           |
| `/model [name]` | show the current model, or switch to `<name>`   |
| `/clear`        | wipe the screen + scrollback and reset the conversation |
| `/cost`         | show token usage and estimated cost             |
| `/save [file]`  | save the conversation to disk                   |
| `/load [file]`  | load a saved conversation                       |
| `/caveman`      | activate the caveman skill (ultra-compressed terse replies) |
| `/plan [text]`  | enter plan mode (locks write/edit/shell); `/plan accept` proceeds, `/plan cancel` drops |
| `/lean [on\|off]` | toggle lean mode — trims system prompt to save tokens |
| `/btw <text>`   | interrupt the running turn; answer `<text>` next |
| `/exit`         | quit (alias `/quit`)                            |

Anything else is sent to the assistant.

### `/clear`

`/clear` is a hard reset of the current session. It (1) wipes the visible
screen and the scrollback buffer above it and rebuilds the input box, (2)
drops the message history sent to the model and rebuilds a fresh system
prompt (so updated `CC.md`, `memory.md` and installed skills are picked up
on the next turn), (3) resets the session token counter so `/cost` reports
from zero again, and (4) prints `[conversation reset]`. It does **not**
touch persistent `memory.md`, `settings.json`, saved sessions on disk, the
input-box history, or the skills currently active in the status line.

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
| Tab              | accept the model's "Suggested next" prompt              |
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

## Skills

Skills are markdown files under `.ccharbour/skills/` that hold a checklist or
set of instructions the agent can load on demand. Each file has a YAML
frontmatter block with `name:`, `description:`, and an optional `triggers:`
line of comma-separated regex patterns. The descriptions are listed in the
system prompt so the model knows what is available without loading every
body up front.

Three ways a skill activates:

- **Model decision** — the model calls the `use_skill` tool with the skill
  name; the body is returned to it and the name is pinned to the status line
  under the input box.
- **Auto-trigger** — if the user's message matches any of a skill's
  `triggers:` regex patterns, the skill activates automatically, its body is
  injected as a system message, and a notice is printed in the scroll.
- **Slash command** — `/caveman` is a shortcut for activating the caveman
  skill; the same `CCREPL_ActivateSkill` path supports any future skill
  shortcut.

The active skills appear as bracketed tags in orange in the status line
below the input box, so the discipline in effect is always visible. Sample
skills shipped: `superpowers` (brainstorm → plan → execute → verify) and
`caveman` (ultra-compressed terse replies).

## Tools

The agent works through these fourteen tools. Each is gated by the
permission shown (`allow` runs without asking, `ask` prompts, `deny`
blocks). Parameters marked ★ are required; the rest are optional.

| Tool | Gate | Purpose and parameters |
|------|------|------------------------|
| `read` | allow | Read a text file; returns line-numbered content. `path`★, `offset` (leading lines to skip), `max_lines` (default 2000). |
| `write` | ask | Write content to a file, overwriting it. `path`★, `content`★. |
| `edit` | ask | Replace an exact string in a file. `path`★, `old_string`★, `new_string`★, `replace_all` (replace every occurrence). |
| `glob` | allow | List files matching a filename pattern, recursively. `pattern`★ (e.g. `*.prg`, `**/*.txt`), `path` (root directory, default cwd). |
| `grep` | allow | Search file contents with a regular expression; returns `file:line:text` matches. `pattern`★, `path` (root directory), `glob` (filename mask filter). |
| `shell` | ask | Run a shell command; returns its combined output and exit code. `command`★, `timeout` (max seconds, 0 = no limit). |
| `web_fetch` | ask | Fetch the raw content of a URL. `url`★. |
| `web_search` | ask | Search the web via the DuckDuckGo API (no API key). `query`★, `max_results` (default 8). |
| `github_read` | allow | Read from GitHub. `operation`★ (`repo`/`file`/`list`/`issues`/`issue`/`prs`/`pr`/`search`), `repo` (`owner/name`), `path`, `number`, `query`. |
| `github_write` | ask | Write to GitHub; needs `GITHUB_TOKEN`. `operation`★ (`create_issue`/`comment`/`create_pr`), `repo`★, `number`, `title`, `body`, `head`, `base`. |
| `memory` | allow | The agent's persistent memory across sessions, stored in `memory.md`. `operation`★ (`append`/`read`/`clear`), `text` (entry to add, for `append`). |
| `ask_user` | allow | Ask the user a multiple-choice question and return their selected answer. Renders an interactive selector (arrow keys or number, plus an "Other" free-text option). `question`★, `options`★ (2–4 choices). Never gated — asking is inherently consented. |
| `todo_write` | allow | Replace the visible session task list. `todos`★ (array of items); each item has `text`★, `status`★ (`pending`/`in_progress`/`completed`), and optional `id`, `active_form` (label shown while in_progress), and `blocked_by` (array of ids this task depends on). |
| `use_skill` | allow | Activate a project skill from `.ccharbour/skills/`; returns the skill's body and pins its name to the status line. `name`★. |

## Disclaimer

Read this before using CCHarbour.

**Token usage and cost.** CCHarbour is an autonomous agent. Every turn sends
the whole conversation to a third-party LLM API, and the agent may loop
through many tool calls before it answers. This can consume a **large and
unpredictable number of API tokens, billed to you by your API provider**.
Long sessions, large files and broad tool use all increase that cost. Watch
your usage with the `/cost` command and set spending limits with your
provider. You alone are responsible for every charge that CCHarbour incurs
on your account.

**Use at your own risk.** Through its tools CCHarbour can read, modify and
delete files and run arbitrary shell commands on your machine. The permission
gate (`allow` / `deny` / `ask`) is the only safeguard; setting a tool to
`allow` lets the agent act with no confirmation. Run CCHarbour only against
code you have backed up or under version control, review the permission
settings before each session, and do not grant `allow` to `shell` for
prompts or projects you do not trust.

**No warranty.** CCHarbour is provided "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
OR OTHER LIABILITY — INCLUDING, WITHOUT LIMITATION, API CHARGES, DATA LOSS OR
BUSINESS INTERRUPTION — WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE. By using CCHarbour you accept these terms.

**Third parties.** CCHarbour is not affiliated with, endorsed by or sponsored
by DeepSeek, Anthropic or any other API provider. Your use of an LLM API is
additionally governed by that provider's own terms of service. "Claude Code"
is referenced only to describe the project's style and remains a trademark of
its respective owner.

See the [`LICENSE`](LICENSE) file for the full licence terms.

## Project layout

| Módulo (`src/`)       | Propósito |
|-----------------------|-----------|
| `ccrepl.prg`          | Punto de entrada (`Main`), bucle REPL interactivo, manejo de comandos `/`, ejecución de turnos del agente, renderizado de eventos, barra de tokens, spinner animado, carga/guardo de sesiones |
| `ccagent.prg`         | Bucle multi-turno del agente: llama a la API DeepSeek, ejecuta herramientas, soporta interrupción mid-turn (`interrupt_check`), límite de iteraciones con opción de extender |
| `ccapi.prg`           | Cliente de la API DeepSeek (Chat Completions con streaming SSE), construcción del cuerpo de la petición, clasificación de errores HTTP/API/red |
| `cchttp.prg`          | Transporte HTTP vía subproceso `curl.exe` (streaming y fetch), parseo del código de estado HTTP desde dump de cabeceras, soporte cancelación vía Ctrl+C |
| `ccsse.prg`           | Parser SSE (Server-Sent Events): extrae `text_delta`, `reasoning_delta`, `tool_call_delta`, `finish`, `usage` y `[DONE]` del stream |
| `ccconfig.prg`        | Resolución de API key y base URL (precedencia: parámetro → entorno → archivo) |
| `ccsettings.prg`      | Carga de `settings.json` fusionado sobre valores por defecto; permisos, modelo, color, `co_author` |
| `cctools.prg`         | Registro y despacho de herramientas: crea el registry, genera schemas OpenAI, ejecuta el handler con validación de argumentos y captura de errores |
| `cctools_file.prg`    | Herramientas `read` (con line-numbered output, offset, max_lines), `write` (crea directorios, muestra diff), `edit` (reemplazo exacto con `replace_all`) |
| `cctools_search.prg`  | Herramientas `glob` (lista archivos con máscara recursiva) y `grep` (regex sobre contenidos) |
| `cctools_shell.prg`   | Herramienta `shell`: ejecuta comandos vía `cmd.exe /c` (Windows) o `/bin/sh` (Linux/macOS), inyecta automáticamente `Co-authored-by` en `git commit` |
| `cctools_web.prg`     | Herramientas `web_fetch` (GET vía HTTP) y `web_search` (DuckDuckGo Instant Answer API sin API key) |
| `cctools_github.prg`  | Herramientas `github_read` (repo, file, list, issues, issue, prs, pr, search) y `github_write` (create_issue, comment, create_pr) |
| `cctools_memory.prg`  | Herramienta `memory`: operaciones `append`/`read`/`clear` sobre `memory.md`, persistente entre sesiones |
| `cctools_ask.prg`     | Herramienta `ask_user`: pregunta de opción múltiple resuelta con un selector interactivo |
| `ccselect.prg`        | Selector interactivo de opción múltiple: estado puro (cursor, opciones) y bucle de teclas raw (flechas, dígitos, "Other") |
| `ccperm.prg`          | Puerta de permisos: envuelve el executor raw con lógica `allow`/`deny`/`ask`; opción "a" (allow siempre) dura lo que dura la sesión |
| `ccdiff.prg`          | Diff línea por línea vía LCS (Longest Common Subsequence): detecta líneas añadidas/eliminadas con 3 líneas de contexto, formato Claude Code-style |
| `ccmarkdown.prg`      | Renderizado Markdown → ANSI en streaming: headings, listas, código (fence e inline), **bold**, *italic*, captura de "Suggested next:" |
| `ccui.prg`            | UI completa: banner con logo "CC", parseo de comandos `/`, colores ANSI, palette, system prompt con CC.md + memory.md, resumen de tool calls, diff coloreado, caja de input con marco |
| `ccinput.prg`         | Editor multilínea en raw-mode: cursor keys, Home/End, Delete, historial (↑/↓), paste detection (<50ms), sugerencias vía Tab, Shift+Enter para nueva línea |
| `ccconsole.c`         | Soporte nativo Windows (Win32 API): detección de consola, raw mode, lectura de teclas, detección no-bloqueante de Ctrl+C y Escape |
| `ccconsole_posix.c`   | Equivalente POSIX (termios/select) compartido por las compilaciones de Linux y macOS |
| `tests/`               | Suite de tests (340+ tests, 0 fallos) |
| `docs/superpowers/`    | Especificaciones de diseño y planes de implementación |

## Status

### Done (v0.5.0)

- DeepSeek / OpenAI-compatible API client with SSE streaming
- Agent loop with tool calls, iteration cap with extend prompt; **Esc interrupts the turn**, `/btw` interrupts and queues a reply, plain mid-turn input queues for after the turn
- **Action narration** — the agent describes what it is about to do, in one or two lines, just before a non-obvious tool call such as a shell command
- Tools: read, write, edit, glob, grep, shell, web (search & fetch), github (read & write), memory, ask_user
- **DuckDuckGo web search** — no API key required (replaced Tavily)
- Permission gate — `allow` / `deny` / `ask`, with session upgrade
- `settings.json` loading with defaults and `co_author` setting
- `CC.md` project-instruction loading
- Diff rendering on edit / write
- UTF-8 console, auto-detected ANSI colour, Claude Code-style banner with
  **Harbour ship logo**, framed prompt and tool-call rendering
- Raw-mode line editor with input history (↑/↓), cursor keys, Home/End, Delete,
  multi-line input with Shift+Enter and paste detection
- **User prompt echoed in white** above the input box so the scroll keeps a
  clear transcript of what was asked
- **"Suggested next" pre-filled in the input box** in translucent green;
  press Tab to accept it as-is, or start typing to replace it
- **Project skills** — checklists under `.ccharbour/skills/`, activated by
  the `use_skill` tool, the `/caveman` shortcut, or auto-trigger regex; the
  active set is shown as orange bracketed tags in a status line below the
  input box
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

**v0.8.6 — current.** `/lean` — token-saving mode. The system prompt is
trimmed (no skills section, no `CC.md`, no `memory.md`, no narration
block); per-turn input drops by ~500-800 tokens. A `[lean]` badge shows
in the status line. Toggle with `/lean off`.

**v0.8.5 — previous.** Richer `todo_write` — three new optional fields:
`id` (task identifier), `active_form` (present-continuous label shown
while an item is `in_progress`), and `blocked_by` (array of ids this
task depends on). Blocked items render indented, dimmed, with a `↳`
glyph and a `(blocked)` suffix; once every blocker is `completed` they
return to their normal style. Backwards compatible.

**v0.8.4 — previous.** Plan mode (`/plan`) — locks write/edit/shell at the
permission gate, auto-activates the `writing-plans` skill, and shows a
`[plan-mode]` badge in the status line; `/plan <text>` also dispatches
`<text>` as the first planning prompt. Expanded skill library:
`brainstorming`, `writing-plans`, `tdd`, `debugging`, `code-review` (each
with EN+ES auto-triggers). Banner and input box widened from 99 to 123
columns (117 inside the box).

**v0.8.3 — previous.** Unified tool-call block (cyan-violet rule, label,
green command, soft-white narration) for every tool. `ask_user` selector
gets its own absolute-positioned block: wrap-around Up/Down, no scroll
jitter, prior model output preserved. Mid-question controls: Tab amends
the highlight in the input box, Esc cancels, Ctrl+E asks the model to
explain. While the selector is up the input box stays editable (with
history, `/btw`, `/exit`); the cursor parks in the box.

**v0.8.2 — previous.** Project skills — `.md` files under
`.ccharbour/skills/` describe a checklist or set of instructions the model
can pull in on demand, via the new `use_skill` tool, via the `/caveman`
slash command, or via auto-trigger regex patterns in the skill frontmatter.
A new status line under the input box lists the currently active skills as
orange bracketed tags. Sample skills shipped: `superpowers` and `caveman`.

**v0.8.1 — previous.** Input box polish — every submitted prompt is echoed
in bright white in the scroll above the box, so the transcript shows what
was asked. The model's `Suggested next:` line is pre-filled into the box as
a translucent-green suggestion; Tab accepts it, Backspace/Delete cancel it,
or start typing to replace it.

**v0.8.0 — previous.** Linux and macOS support — `cc` builds and runs on all
three platforms. New `cc_linux.hbp` / `cc_mac.hbp` projects, a
`build_cc_linux.sh` script, and `build-linux` / `build-mac` CI workflows;
every tagged release ships a Windows, Linux and macOS binary. The console
backend `ccconsole_mac.c` is renamed `ccconsole_posix.c` and shared by both
POSIX builds; the `shell` tool now runs via `/bin/sh` off Windows; and a
default `.ccharbour/settings.json` is auto-created on first run.

**v0.7.0 — previous.** Shell command timeouts (`shell_timeout` setting, per-call `timeout`, auto-estimate) with a live countdown, timed-shell reliability fixes, UTF-8 tool-result sanitising, and richer API error messages, plus all features from v0.6.0.

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

## License

CCHarbour is released under the [MIT License](LICENSE) —
Copyright (c) 2026 FiveTech Software. See the [Disclaimer](#disclaimer) for
the warranty and liability terms and an important note on API token cost.

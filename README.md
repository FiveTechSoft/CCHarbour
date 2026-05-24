<h1 align="center">CCHarbour</h1>

<p align="center">
  <strong>A Claude Code-style agentic coding assistant — in your terminal, in a single ~2 MB binary that runs on Windows, macOS and Linux, written in Harbour.</strong>
</p>

<p align="center">
  <a href="https://github.com/FiveTechSoft/CCHarbour/releases/latest"><img alt="latest release" src="https://img.shields.io/github/v/release/FiveTechSoft/CCHarbour?style=flat-square&color=blue"></a>
  <a href="https://github.com/FiveTechSoft/CCHarbour/actions/workflows/build.yml"><img alt="Windows build" src="https://img.shields.io/github/actions/workflow/status/FiveTechSoft/CCHarbour/build.yml?branch=master&label=windows&style=flat-square"></a>
  <a href="https://github.com/FiveTechSoft/CCHarbour/actions/workflows/build-linux.yml"><img alt="Linux build" src="https://img.shields.io/github/actions/workflow/status/FiveTechSoft/CCHarbour/build-linux.yml?branch=master&label=linux&style=flat-square"></a>
  <a href="https://github.com/FiveTechSoft/CCHarbour/actions/workflows/build-mac.yml"><img alt="macOS build" src="https://img.shields.io/github/actions/workflow/status/FiveTechSoft/CCHarbour/build-mac.yml?branch=master&label=macos&style=flat-square"></a>
  <a href="LICENSE"><img alt="MIT licence" src="https://img.shields.io/github/license/FiveTechSoft/CCHarbour?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://fivetechsoft.github.io/CCHarbour/">📚&nbsp;Documentation</a>
  &nbsp;·&nbsp;
  <a href="https://fivetechsoft.github.io/CCHarbour/playground/">🌐&nbsp;Web&nbsp;Playground</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/FiveTechSoft/CCHarbour/releases/latest">⬇&nbsp;Download</a>
  &nbsp;·&nbsp;
  <a href="releasenotes.md">📝&nbsp;Release&nbsp;notes</a>
</p>

```
╭─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│                   Welcome back, Anto!                    │ Tips for getting started                                     │
│                      ██████╗ ██████╗                     │                                                              │
│                     ██╔════╝██╔════╝                     │ Type a request to begin                                      │
│                     ██║     ██║                          │ Run /help to list commands                                   │
│                     ██║     ██║                          │ Tip: /caveman for ultra-compressed replies                   │
│                     ╚██████╗╚██████╗                     │ ──────────────────────────────────────────────────────────── │
│                      ╚═════╝ ╚═════╝                     │ What's new                                                   │
│                    CCHarbour  v0.8.14                    │ v0.8.14 — shell countdown above box + diff polish            │
│                 model: deepseek-v4-flash                 │ cwd: ~/projects/myrepo                                       │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ > how is the codebase organised?                                                                                        │
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  [superpowers] [tdd]
```

## Why CCHarbour

- 🦾 **Real agentic loop** — multi-iteration tool calls, streaming SSE, mid-turn interrupts, subagent dispatch.
- 📦 **One file, ~2 MB** — single console executable, no Python / Node / Docker. Drop it on a server, on a USB stick, in a CI runner.
- 🪟 **Truly cross-platform** — Windows (MSVC or mingw-w64), Linux (gcc), macOS (clang). The same Harbour source on every platform.
- 🧠 **Skills & Plan mode** — drop a Markdown file under `.ccharbour/skills/` to give the agent a checklist; `/plan` locks file writes until you approve.
- 🛡 **Permission gate** — `allow` / `ask` / `deny` per tool; `shell` and `edit` always prompt by default.
- 🎯 **Subagents with a user gate** — `propose_agents` lets you review and approve batches of subagents before any of them runs.
- 🪶 **Lean mode** — `/lean` trims the system prompt by ~500–800 tokens per turn for marathon sessions or pricey models.
- ✂️ **Paste detection** — multi-line paste collapses to `[pasted N lines text]` so the box stays readable.

## Quick start

Download a release binary (Windows / Linux / macOS) from the
[releases page](https://github.com/FiveTechSoft/CCHarbour/releases/latest),
then:

```sh
export DEEPSEEK_API_KEY=sk-...        # or set on Windows: set DEEPSEEK_API_KEY=...
./cc                                  # Linux / macOS  (or cc.exe on Windows)
```

That's it. Type a request and the agent goes to work.

## How it works

The REPL reads a line, sends the conversation to the LLM, and streams the
response. When the model emits a tool call, CCHarbour runs it through a
permission gate and feeds the result back, looping until the model produces a
final answer or hits the iteration cap.

The default backend is the [DeepSeek](https://api.deepseek.com) chat API
(OpenAI-compatible).

## Building from source

CCHarbour builds on **Windows, Linux and macOS**. The console layer has a
native Win32 backend (`ccconsole.c`) and a shared POSIX backend
(`ccconsole_posix.c`, termios/select); everything else is the same Harbour
source on every platform.

You need **Harbour 3.2** (`hbmk2` on `PATH`) and a C compiler:

| Platform | Toolchain                                      | Command                  |
|----------|------------------------------------------------|--------------------------|
| Windows  | MSVC (VS 2019 / 2022 Build Tools) or mingw-w64 | `build.bat`              |
| Linux    | gcc                                            | `./build_cc_linux.sh`    |
| macOS    | clang (Xcode CLT)                              | `hbmk2 cc_mac.hbp`       |

> **Hot-swap (Windows):** `update_cc.bat` replaces `cc.exe` with a freshly
> built `cc_new.exe` without needing to stop a running REPL session.

## Configuration in 30 seconds

1. **API key** — set `DEEPSEEK_API_KEY` (or put `{"api_key": "..."}` in
   `.ccharbour/settings.json`). `DEEPSEEK_MODEL` overrides the model.
2. **Project context** — drop a `CC.md` in the working directory and the
   agent picks it up on every run.
3. **Skills** — markdown files under `.ccharbour/skills/` (ship with
   `superpowers`, `caveman`, `brainstorming`, `writing-plans`, `tdd`,
   `debugging`, `code-review`).
4. **Permissions** — edit `.ccharbour/settings.json` to flip any tool
   between `allow`, `ask` and `deny`.

## Commands

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
| `/provider [args]` | configure the LLM backend at runtime (see below) |
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

The agent works through these sixteen tools. Each is gated by the
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
| `dispatch_agent` | allow | Spawn an isolated subagent on a focused subtask; returns only its final reply. `prompt`★, `agent_type` (`explore` read-only / `general` full toolset; default `explore`), `timeout_s` (default 120, max 600). Cancellable mid-run with Esc. |
| `propose_agents` | allow | Batch 2+ proposed subagents past a user-review selector before any dispatch. `agents`★ (array of `{ agent_type, prompt }`). Returns approved JSON list; the agent then iterates and dispatches each. The second consecutive `dispatch_agent` without going through this gate is rejected. |

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

### Done (v0.8.8)

**Agent core**

- DeepSeek / OpenAI-compatible API client with SSE streaming
- Multi-iteration agent loop with iteration cap + user-resume extension
- 16 builtin tools: `read`, `write`, `edit`, `glob`, `grep`, `shell`,
  `web_search`, `web_fetch`, `github_read`, `github_write`, `memory`,
  `ask_user`, `todo_write`, `use_skill`, `dispatch_agent`, `propose_agents`
- Subagents with isolated context (`dispatch_agent`), filtered tool registry
  per type (`explore` / `general`), wall-clock `timeout_s`, Esc cancel, and
  a per-turn second-dispatch interceptor that redirects through
  `propose_agents`
- Permission gate — `allow` / `ask` / `deny` per tool, session upgrade
- `todo_write` with `id`, `active_form` (label while in_progress) and
  `blocked_by` dependency graph
- `memory.md` per-project memory loaded into the system prompt and
  maintained by the agent via the `memory` tool
- `CC.md` project-instruction file loaded into the system prompt
- Action-narration rule in the system prompt — agent explains the *why*
  before every non-trivial tool call
- Tool-result UTF-8 sanitising; rich API error messages

**Skills**

- `.ccharbour/skills/<name>.md` markdown skills with YAML frontmatter
  (`name`, `description`, optional `triggers` regex list)
- Auto-trigger — a skill whose `triggers` match the user's input is
  activated automatically; status line shows the active set
- Manual activation via the `use_skill` tool and via shortcut commands
- Ships 7 skills: `superpowers`, `caveman`, `brainstorming`,
  `writing-plans`, `tdd`, `debugging`, `code-review`

**Modes & commands**

- `/plan` — locks `write` / `edit` / `shell` until `/plan accept`; auto-activates the `writing-plans` skill; `/plan <text>` enters and dispatches the prompt
- `/lean` — trims the system prompt by ~500–800 tokens per turn
- `/caveman` — activates the caveman skill (ultra-compressed terse output)
- `/btw <text>` — interrupts the running turn, queues `<text>` as the next message
- `/clear`, `/help`, `/init`, `/model`, `/cost`, `/save`, `/load`, `/exit`

**Terminal UI**

- Persistent input box pinned to the bottom; scroll region above it
- Unified tool-call block (cyan-violet rule, label, green command,
  soft-white narration) for every tool
- `ask_user` interactive selector with checkbox-style toggle, wrap-around
  Up/Down, Tab amend (edit highlighted option in the box), Esc cancel,
  Ctrl+E "explain"
- `propose_agents` multi-row selector for batch approval before subagents dispatch
- Status line under the box shows active skills + plan/lean badges in coral
- Raw-mode editor: input history (↑/↓), cursor keys, Home/End, Delete,
  multi-line via Shift+Enter, paste detection
- **Paste collapse** — multi-line paste becomes `[pasted N lines text]`;
  Enter expands it, Backspace clears it
- User prompt echoed in bright white above the box
- "Suggested next" pre-filled in translucent green; Tab accepts
- Dynamic input box width (adapts to terminal columns, clamped 76..200)
- Animated reasoning spinner with token-count estimate; compact
  token-usage bar after each turn
- `Esc` interrupts the turn; `Ctrl+C` cancels a running stream;
  `Ctrl+E` asks the model to explain a question

**Cross-platform**

- Builds on Windows (MSVC / mingw-w64), Linux (gcc), macOS (clang)
- Shared POSIX console backend (termios/select) for Linux + macOS;
  native Win32 backend on Windows
- `shell` tool routes through `cmd.exe` on Windows and `/bin/sh` elsewhere
- CI builds and publishes Windows + Linux + macOS binaries per tag

**Project & infrastructure**

- Web playground at <https://fivetechsoft.github.io/CCHarbour/playground/>
- Documentation site at <https://fivetechsoft.github.io/CCHarbour/>
- 443-test suite, GitHub Actions CI for all 3 platforms
- `update_cc.bat` hot-swap on Windows; `build_cc_linux.sh` on Linux

### Missing / planned

- Parallel subagent dispatch (current `dispatch_agent` is synchronous)
- Multi-provider support — DeepSeek by default; OpenAI-compatible only
- `CC.md` discovery from parent and home directories
- Hooks (`PreToolUse` / `PostToolUse` / `UserPromptSubmit`) configurable
  in `settings.json`
- Conversation auto-compaction when context fills up
- More commands — `/tools`, user-defined commands

## Releases

**v0.8.14 — current.** Shell command countdown (`timeout 300s · 252s
left`) lands on the scroll-region anchor above the box instead of
overwriting the input row. Diff bars all pad to the same width
(longest added/removed line, floor 110) so red and green bars line
up cleanly. Both diff line markers now render text in bright white
(SGR 97) for matching contrast.

**v0.8.13 — previous.** Dynamic-box paint hardening and live timing.
Banner anchored at row 1 (clear-screen before paint). Box paint uses
absolute cursor jumps per row instead of CRLF chains, so pressing
Esc near the terminal bottom no longer stacks leftover `╭` frames.
Wipe rule rewritten around the actual write-row range, so the
FlushPending bullet survives and stale tops from multi-line writes
are caught. When the box pins to its floor the VT scroll region
expands up to row 1 so the banner finally rolls off the top. Spinner
appends elapsed seconds (`⠦ Thinking... [32 tok] 7s`). Token bar
shows per-turn and per-session seconds. `dispatch_agent` repaints
the elapsed-time line at ~2 Hz via the new `CCREPL_OverwriteAtAnchor`
helper. `/provider key` is now picked up on the next turn without
restarting (`CCCFG_Resolve` falls back to `settings.json`).

**v0.8.12 — previous.** Starts without an API key — banner + box come
up and a yellow warning under the banner tells the user to configure
a backend. New `/provider` slash command sets the backend at runtime
(presets for `deepseek`, `glm`, `moonshot`, `openai`; sub-commands
`key <secret>`, `model <name>`, `clear`). Settings persist to
`.ccharbour/settings.json`.

**v0.8.11 — previous.** Stability fixes for the dynamic input box:
scroll region spans the full band regardless of box position,
interactive selectors force-pin the box before painting, the
wipe never erases the just-written user echo or streamed reply,
visual-row counting accounts for auto-wrap, and every CCREPL_Out
write clears to the end of each line so old frame chars cannot
leak past the new content.

**v0.8.10 — previous.** Dynamic input box position — the box starts
right below the banner and "follows" the content down a row per
agent reply line, only pinning to the floor when it reaches the
bottom. Native CC logo renders with a per-character truecolor
gradient (magenta → violet). Banner width adapts to the terminal
columns. Clean exit cursor (wipes the box rows and parks cursor
at box_top before returning). Playground gains a tip line,
Suggested-next pre-fill, Settings Close button, and JS ports of
`dispatch_agent` + `propose_agents`.

**v0.8.9 — previous.** Multi-provider API keys — `CCCFG_Resolve` tries
`DEEPSEEK_API_KEY` → `CCHARBOUR_API_KEY` → `GLM_API_KEY` →
`MOONSHOT_API_KEY` → `OPENAI_API_KEY` → `settings.json`. Any
OpenAI-compatible endpoint works once `base_url` and `model` are set.
Documentation site overhaul (MkDocs Material with light/dark palette,
tabbed nav, code copy, a richer landing, per-OS tabbed install
instructions, and a Providers table with sign-up links, indicative
pricing and coding tiers). Premium playground theme (animated mesh
background, glassmorphism, cyan → violet logo shimmer, gradient
buttons). Playground gains JS ports of `memory`, `todo_write` and
`ask_user` (with a glass modal).

**v0.8.8 — previous.** `propose_agents` gate (review batch of subagents in
an interactive selector before dispatch), second-dispatch interceptor
(redirects single-shot multi-dispatch through the gate), Agent block
visualisation, subagent `timeout_s` + Esc cancel, paste collapse
(`[pasted N lines text]`), dynamic input-box width, defensive
bullet-run split in `CCMD`, and stricter list-formatting rules in the
system prompt. Adds skills `brainstorming`, `writing-plans`, `tdd`,
`debugging`, `code-review`, plus the `/lean` token-saving command.

**v0.8.7 — previous.** `dispatch_agent` — the agent can spawn an isolated
subagent on a focused subtask. The subagent has its own conversation
and a filtered tool registry; the parent only receives the final reply,
so its context stays small. Two agent types: `explore` (read-only) and
`general` (full toolset, no further dispatch). No recursion (the
subagent's registry strips `dispatch_agent`). Synchronous v1; parallel
multi-agent dispatch comes later.

**v0.8.6 — previous.** `/lean` — token-saving mode. The system prompt is
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

## License

CCHarbour is released under the [MIT License](LICENSE) —
Copyright (c) 2026 FiveTech Software. See the [Disclaimer](#disclaimer) for
the warranty and liability terms and an important note on API token cost.

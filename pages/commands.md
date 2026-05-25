# Commands

A line that starts with `/` is a command. Anything else is sent to the
assistant.

| Command         | Action                                          |
|-----------------|-------------------------------------------------|
| `/help`         | show the command list                           |
| `/init`         | analyse the project and write `CC.md`           |
| `/model [name]` | show the current model, or switch to `<name>`   |
| `/cost`         | show session token usage and estimated cost     |
| `/clear`        | wipe the screen and reset the conversation      |
| `/save [name]`  | save the session (messages + state + suggestion) to JSON |
| `/load [name]`  | load a saved session (no name lists them)       |
| `/caveman`      | activate the caveman skill (terse replies)      |
| `/plan [text]`  | enter plan mode (locks write/edit/shell)        |
| `/lean [on\|off]` | toggle lean mode (trims system prompt to save tokens) |
| `/provider [args]` | configure the LLM backend at runtime               |
| `/goal [args]`  | set a goal — keep working until the condition is met |
| `/tasks [args]` | inspect background subagent tasks (list / view / kill / clear) |
| `/compact`      | summarise older turns to free context (last 4 + system kept verbatim) |
| `/btw <text>`   | interrupt the running turn; answer `<text>` next |
| `/exit`         | quit (alias `/quit`)                            |

## Input box

The input box is visible at all times, including while the agent is working.

| Key / input      | Action                                                      |
|------------------|-------------------------------------------------------------|
| ← / →            | move cursor left / right                                    |
| ↑ / ↓            | navigate input history                                      |
| Home / End       | jump to start / end of line                                 |
| Delete           | delete character at cursor                                  |
| Backspace        | delete character before cursor                              |
| Ctrl+C           | cancel a running stream                                     |
| Shift+Enter      | insert a newline (multi-line input)                         |
| Enter            | submit the line (queued if the agent is busy)               |
| Esc              | interrupt the running turn (no new message)                 |
| `/btw <text>`    | interrupt the running turn; answer `<text>` next            |

**Mid-turn input.** A message submitted with Enter while the agent is working is
queued and answered after the current turn finishes. Multiple messages queue in
order. A line beginning with `/btw <text>` interrupts immediately and is answered
next. Pressing Esc interrupts the current turn with no new message. In both
interrupt cases, any partial work and tool results already produced are kept in
the conversation history.

## /init

`/init` asks the agent to inspect the repository — its layout, build process
and conventions — and write a `CC.md` file. That file is then loaded as
project context on every later run.

## /model

`/model` with no argument prints the active model. `/model <name>` switches it;
the new model takes effect on the next message.

## /clear

`/clear` is a hard reset of the *current session* state. It does four things:

1. **Wipes the terminal.** Clears the visible screen, the scrollback buffer
   above it, and (when the input box is mounted) rebuilds the box and its
   scroll region from scratch. Skipped on a non-VT terminal so the raw escape
   bytes do not appear as garbage.
2. **Resets the conversation.** Drops the entire message history sent to the
   model and rebuilds a fresh system prompt from scratch (so any updated
   `CC.md`, `memory.md`, or installed skills are picked up on the next turn).
3. **Resets the session token counter.** `/cost` reports from zero again.
4. Prints `[conversation reset]` in dim grey as confirmation.

What `/clear` does **not** touch: persistent `memory.md`, `.ccharbour/settings.json`,
saved sessions on disk, input-box history (Up/Down still recalls earlier prompts),
and skills currently active in the status line.

## /caveman

`/caveman` activates the `caveman` skill — the model switches to ultra-compressed,
terse, fragment-style replies (code and command output stay verbatim). The skill
name shows up in the status line under the input box. Cancel by `/clear` or by
asking the model to "stop caveman" / "normal mode".

## /plan

`/plan` puts the session into plan mode: the permission gate locks the
`write`, `edit`, `shell` and `github_write` tools, the `writing-plans` skill
is auto-activated, and the status line shows a `[plan-mode]` badge. The agent
can still read, glob, grep, fetch, search and use memory while it plans, but
cannot modify the codebase or run commands. Forms:

- `/plan` — enter plan mode and wait for the next message.
- `/plan <text>` — enter plan mode AND submit `<text>` as the first planning
  prompt.
- `/plan accept` (alias `/plan go` / `/plan approve`) — exit plan mode and
  add a system note telling the agent to proceed step by step.
- `/plan cancel` (alias `/plan off`) — exit plan mode and tell the agent to
  drop the plan and wait for the next instruction.

Use it for non-trivial work where you want to review the approach before any
file is touched.

## /lean

`/lean` toggles a token-saving "lean mode". While active, `CCUI_SystemPrompt`
returns a minimal version of the prompt: no skills section, no `CC.md`, no
`memory.md`, no narration block. Per-turn input drops by ~500-800 tokens
(roughly 2900 → 2100 on a vanilla "hi"). A `[lean]` badge shows up in the
status line.

Use it late in long sessions when context is filling up, or against a
pricier model (Claude, GPT) where every input token matters. The model
loses access to your CC.md project context and memory.md while lean is on,
so answer quality on project-specific questions degrades — turn it off
(`/lean off`) before resuming complex work.

Forms:

- `/lean` (or `/lean on`) — enter lean mode.
- `/lean off` — restore the full system prompt.

Toggling rebuilds the first system message in place, so the next turn
immediately sees the new state without needing `/clear`.

## /provider

CCHarbour now starts even when no API key is configured. The banner and
input box appear with a yellow warning under the banner; `/provider` is
how you set the backend at runtime.

| Form | What it does |
|------|--------------|
| `/provider` | Show current `base_url`, `model`, and whether the API key is set. Print the four presets. |
| `/provider deepseek` | Apply the DeepSeek preset (`api.deepseek.com` + `deepseek-v4-flash`), persist to `settings.json`, rebuild the API client. |
| `/provider glm` | Apply the GLM / Zhipu preset (`open.bigmodel.cn/api/paas/v4` + `glm-4.6`). |
| `/provider moonshot` | Apply the Moonshot preset (`api.moonshot.cn/v1` + `kimi-k2`). |
| `/provider openai` | Apply the OpenAI preset (`api.openai.com/v1` + `gpt-5`). |
| `/provider key <secret>` | Save the API key to `settings.json` for the active backend. |
| `/provider model <name>` | Switch the model only (without changing `base_url`). |
| `/provider clear` | Remove the stored API key. |

The key is stored in plain text in `.ccharbour/settings.json`, the same
way most OpenAI-compatible CLIs handle their credentials. That folder is
in `.gitignore` by default, so the key is not committed.

## /save and /load

`/save [name]` writes the current session to
`.ccharbour/sessions/<name>.json` (auto-named `session_YYYY-MM-DD_HHMMSS`
when no name is given). The file is a single JSON document that
round-trips the **full session state**, not just the conversation:

| Field      | What it carries |
|------------|-----------------|
| `model`    | the active model name at save time |
| `saved_at` | ISO timestamp |
| `usage`    | accumulated `prompt_tokens` / `completion_tokens` for `/cost` |
| `messages` | the full message array (system + user + assistant + tool calls) |
| `state`    | `goal`, `goal_looping`, `session_turn_ms`, `plan_mode`, `lean_mode`, `skills` |
| `suggest`  | the pending "Suggested next:" prompt for the editor |

`/load [name]` reads the JSON and reapplies every field on top of the
running REPL: messages replace the conversation, `state` reactivates
the goal / plan-mode / lean-mode / skills, `suggest` re-seeds the
green Tab-acceptable preview, and `usage` restores `/cost`. With no
argument `/load` lists the saved sessions. Legacy files that lack the
`state` or `suggest` field still load — the missing pieces fall back
to current defaults.

## /goal

`/goal` pins a session-wide objective the agent keeps working toward
across turns. The injected system note teaches the model to emit a
literal `GOAL COMPLETE` sentinel when the condition is met; while the
sentinel is absent the REPL auto-feeds `Continue toward the goal.` and
runs another turn (capped at 25 auto-iterations per user turn).

| Form          | What it does |
|---------------|--------------|
| `/goal`       | show the current goal (or `(none)`) and whether the auto-continue loop is on |
| `/goal <text>` | set the goal, inject the keep-working system note, arm the auto-continue loop |
| `/goal stop`  | pause the auto-continue loop without dropping the goal text (badge stays on) |
| `/goal clear` (alias `/goal off`) | drop the goal entirely and disarm the loop |

A `[goal]` badge appears in the status line whenever a goal is set.
Pressing Esc mid-loop pauses the auto-continue without clearing the
goal — send another message (or `/goal <text>`) to restart it.

## /tasks

`/tasks` is the user's window into the background subagent registry.
A subagent is spawned in the background when the model calls the
`dispatch_agent_background` tool: it returns a task-id (`bg1`,
`bg2`, ...) IMMEDIATELY and a worker thread runs `CC_AgentRun`
without blocking the parent. The worker writes status / reply /
error into a mutex-protected hash (`src/ccbg.prg`); the worker
never touches the terminal (that would corrupt the dynamic input
box).

| Form               | What it does |
|--------------------|--------------|
| `/tasks`           | tabular list: id, status, elapsed, type, prompt summary |
| `/tasks view <id>` | full record for one task (prompt, iterations, reply or error) |
| `/tasks kill <id>` | request cancellation; worker exits at the next agent-loop boundary |
| `/tasks clear`     | drop every finished / failed / cancelled / timed-out record |

Status values: `queued`, `running`, `done`, `failed`, `cancelled`,
`timed_out`. The status updates live as the worker progresses —
re-run `/tasks` to refresh.

`dispatch_agent_background` is removed from a subagent's tool
registry by `CCTOOLS_FilterForAgent`, so a background subagent
cannot spawn its own background subagents.

## /compact

`/compact` summarises the older part of the conversation into one
synthetic system note, keeping the original system prompt and the
last 4 turns verbatim. A stateless one-shot call with a strict
"preserve exact paths / identifiers / errors / code verbatim, no
paraphrase, no preamble" instruction. The handler refuses to compact
when the very last assistant turn has a dangling `tool_call` (no
matching `tool` response yet), so a compaction cannot orphan a tool
call mid-cycle.

After every successful turn the REPL prints a one-shot soft warning
when `prompt_tokens` cross `compact_threshold` (default `0.7`) of
the model's context window:

    [context 78% full -- run /compact to summarise old turns and free up space]

It NEVER auto-runs. The hint re-arms on `/clear` or after a successful
`/compact`. Tunable via `compact_threshold` in `settings.json`. Per-
model context sizes are read from a table inside `CCREPL_ModelContext`
(deepseek-v4-flash / deepseek-v4-pro = 128k, kimi-k2 = 200k, gpt-5 =
400k, fallback 32k).

## /btw

`/btw <text>` interrupts the running turn and queues `<text>` as the next
user message. Without `<text>` it interrupts with no follow-up (like Esc).
Also works while a question selector (`ask_user`) is on screen: the
selector is cancelled and the interrupt is processed at the next agent
boundary.

## Tools

The agent uses these tools when it decides a tool call will help answer your
request. Each tool is subject to the [permission gate](configuration.md).

### read

Read a file from disk and return its contents.

| Parameter | Type   | Required | Description             |
|-----------|--------|----------|-------------------------|
| `path`    | string | yes      | path to the file        |
| `offset`  | integer| no       | line to start from      |
| `limit`   | integer| no       | maximum lines to return |

### write

Create or overwrite a file with new content.

| Parameter | Type   | Required | Description      |
|-----------|--------|----------|------------------|
| `path`    | string | yes      | destination path |
| `content` | string | yes      | file content     |

### edit

Replace an exact substring inside a file without rewriting the whole file.

| Parameter    | Type   | Required | Description           |
|--------------|--------|----------|-----------------------|
| `path`       | string | yes      | target file           |
| `old_string` | string | yes      | text to find          |
| `new_string` | string | yes      | replacement text      |

### glob

List files whose paths match a glob pattern.

| Parameter | Type   | Required | Description                           |
|-----------|--------|----------|---------------------------------------|
| `pattern` | string | yes      | glob pattern (e.g. `**/*.prg`)        |
| `path`    | string | no       | directory to search (default: cwd)    |

### grep

Search file contents for a regular-expression pattern.

| Parameter | Type   | Required | Description                        |
|-----------|--------|----------|------------------------------------|
| `pattern` | string | yes      | regular expression                 |
| `path`    | string | no       | directory or file to search        |
| `glob`    | string | no       | filter files by glob pattern       |

### shell

Run a shell command via `cmd.exe` and return its combined output and exit code.

| Parameter | Type   | Required | Description                         |
|-----------|--------|----------|-------------------------------------|
| `command` | string | yes      | command to execute                  |
| `timeout` | number | no       | max seconds to run (`0` = no limit) |

When `timeout` is omitted, the `shell_timeout` setting — or an automatic
per-command estimate — applies (see [configuration](configuration.md)).

### web_search

Search the web via the DuckDuckGo Instant Answer API and return a list of
results. No API key required.

| Parameter    | Type    | Required | Description                          |
|--------------|---------|----------|--------------------------------------|
| `query`      | string  | yes      | search query                         |
| `max_results`| integer | no       | maximum results to return (default 5)|

### web_fetch

Fetch the raw content of a URL and return it as text.

| Parameter | Type   | Required | Description      |
|-----------|--------|----------|------------------|
| `url`     | string | yes      | URL to fetch     |

### github_read

Read-only queries against the GitHub API. Works without a token, but is
rate-limited to 60 requests/hour unauthenticated (see
[configuration](configuration.md)).

| Parameter   | Type    | Required | Description                                                       |
|-------------|---------|----------|-------------------------------------------------------------------|
| `operation` | string  | yes      | one of: `repo`, `file`, `list`, `issues`, `issue`, `prs`, `pr`, `search` |
| `repo`      | string  | yes (except `search`) | repository in `owner/name` form              |
| `path`      | string  | no       | file or directory path (for `file` and `list`)                    |
| `number`    | integer | no       | issue or PR number (for `issue` and `pr`)                         |
| `query`     | string  | no       | search query (for `search`)                                       |

### github_write

GitHub mutations: create issues, add comments, open pull requests. Requires a
GitHub token (see [configuration](configuration.md)).

| Parameter   | Type    | Required | Description                                          |
|-------------|---------|----------|------------------------------------------------------|
| `operation` | string  | yes      | one of: `create_issue`, `comment`, `create_pr`       |
| `repo`      | string  | yes      | repository in `owner/name` form                      |
| `number`    | integer | no       | issue or PR number (for `comment`)                   |
| `title`     | string  | no       | title (for `create_issue` and `create_pr`)           |
| `body`      | string  | no       | body text                                            |
| `head`      | string  | no       | source branch (for `create_pr`)                      |
| `base`      | string  | no       | target branch (for `create_pr`)                      |

### memory

Read, append to, or clear the agent's persistent per-project memory file
(`memory.md` in the working directory). The agent uses this to remember
decisions and context across sessions. Defaults to `allow`.

| Parameter   | Type   | Required | Description                              |
|-------------|--------|----------|------------------------------------------|
| `operation` | string | yes      | one of: `append`, `read`, `clear`        |
| `text`      | string | no       | text to append (required for `append`)   |

### use_skill

Activate a project skill from `.ccharbour/skills/`. The skill body is
returned to the model and its name pinned to the status line.

| Parameter | Type   | Required | Description                |
|-----------|--------|----------|----------------------------|
| `name`    | string | yes      | the skill name to activate |

### dispatch_agent

Spawn an isolated subagent on a focused subtask. The subagent has its own
conversation and a filtered tool registry; the parent receives only the
final reply. Cancellable mid-run with Esc on the parent's input box.

| Parameter    | Type    | Required | Description                                                       |
|--------------|---------|----------|-------------------------------------------------------------------|
| `prompt`     | string  | yes      | the task for the subagent                                         |
| `agent_type` | string  | no       | `explore` (read-only, default) or `general` (full toolset)        |
| `timeout_s`  | number  | no       | wall-clock seconds before auto-cancel (default 120, max 600)      |

The second consecutive `dispatch_agent` call without going through
`propose_agents` is rejected with a redirect; an approved `propose_agents`
batch tops up an allowance equal to the approved count, so a sanctioned
multi-dispatch goes through.

### propose_agents

Batch two or more proposed subagents past a user-review selector before
any dispatch happens. Each row is toggleable (Space), the user can accept
all (A) or reject all (N), confirm (Enter) or cancel (Esc). The tool
returns a JSON array of the approved items; the agent then iterates over
it and calls `dispatch_agent` once per item.

| Parameter | Type  | Required | Description                                                                                  |
|-----------|-------|----------|----------------------------------------------------------------------------------------------|
| `agents`  | array | yes      | the proposed subagents, each an object with `agent_type` (string) and `prompt` (string)      |

### todo_write

Replace the visible session task list. Each item supports `id`,
`active_form` (label shown while in_progress) and `blocked_by` (ids this
item depends on; while any blocker is pending the item renders indented,
dimmed, with a `↳` glyph).

| Parameter | Type  | Required | Description                                                                                                            |
|-----------|-------|----------|------------------------------------------------------------------------------------------------------------------------|
| `todos`   | array | yes      | the full task list. Each item: `text` (string, required), `status` (`pending`/`in_progress`/`completed`, required), and optional `id`, `active_form`, `blocked_by`. |

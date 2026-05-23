# Commands

A line that starts with `/` is a command. Anything else is sent to the
assistant.

| Command         | Action                                          |
|-----------------|-------------------------------------------------|
| `/help`         | show the command list                           |
| `/init`         | analyse the project and write `CC.md`           |
| `/model [name]` | show the current model, or switch to `<name>`   |
| `/clear`        | wipe the screen and reset the conversation      |
| `/caveman`      | activate the caveman skill (terse replies)      |
| `/plan [text]`  | enter plan mode (locks write/edit/shell)        |
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

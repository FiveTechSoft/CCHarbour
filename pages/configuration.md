# Configuration

## settings.json

Settings load from `.ccharbour/settings.json` under the working directory, or
from the path in the `CCHARBOUR_CONFIG` environment variable. Values are merged
over the built-in defaults:

| Key               | Default                     | Meaning                       |
|-------------------|-----------------------------|-------------------------------|
| `model`           | `deepseek-v4-flash`         | model name                    |
| `base_url`        | `https://api.deepseek.com`  | API endpoint                  |
| `max_iterations`  | `25`                        | tool-call loop cap per turn   |
| `color`           | `true`                      | ANSI colour output            |
| `co_author`       | *(none)*                    | `Co-authored-by` trailer auto-added to `git commit` |
| `shell_timeout`   | `30`                        | max seconds a shell command may run (0 = auto-estimate) |
| `permissions`     | see below                   | per-tool gate                 |
| `github_token`    | *(none)*                    | GitHub token for `github_read`/`github_write` — overridden by `GITHUB_TOKEN` env var |

A missing or malformed file falls back to the pure defaults.

## Permissions

Each tool maps to one of three modes:

- `allow` — run without asking
- `deny` — never run
- `ask` — prompt before each run (the prompt offers a session-wide upgrade)

Defaults: `read`, `glob`, `grep`, `github_read` and `memory` are `allow`;
`write`, `edit`, `shell`, `web_search`, `web_fetch` and `github_write` are
`ask`.

```json
{
  "permissions": {
    "write": "allow",
    "shell": "deny"
  }
}
```

`web_search` uses the DuckDuckGo Instant Answer API and needs no credentials.

`github_write` requires a GitHub personal access token (`GITHUB_TOKEN` env var
or `github_token` in `settings.json`); without it the tool returns
`"Error: GITHUB_TOKEN not set"` at call time. `github_read` works without a
token but is rate-limited. The environment variable takes precedence over the
value in `settings.json`.

## Shell timeout

The `shell` tool bounds how long a command may run, so a hung command cannot
freeze the agent. The limit is chosen in this order:

1. A `timeout` argument the model passes with the call (seconds; `0` = no limit).
2. The `shell_timeout` setting (default `30`).
3. When `shell_timeout` is `0`, an automatic per-command estimate — fast
   commands like `echo` or `dir` get a few seconds; builds and network
   commands get more.

A command that exceeds its limit is abandoned and its output ends with
`[timed out after N seconds]`.

## CC.md

A `CC.md` file in the working directory is appended to the system prompt as
project instructions, so the agent honours per-project conventions. The REPL
prints `[loaded CC.md project instructions]` at startup when it is found.
Run [`/init`](commands.md) to generate one.

## memory.md

`memory.md` is the agent's per-project persistent memory. Unlike `CC.md`
(which you write and the agent only reads), `memory.md` is maintained by the
agent itself via the `memory` tool — it can append notes, read them back, or
clear the file. The contents are loaded into the system prompt each session,
giving the agent continuity across conversations.

## API key

The API key is read from the `DEEPSEEK_API_KEY` environment variable. CCHarbour
exits with an error if it is not set.

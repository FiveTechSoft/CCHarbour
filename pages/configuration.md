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
| `permissions`     | see below                   | per-tool gate                 |
| `tavily_api_key`  | *(none)*                    | Tavily API key for `web_search` — overridden by `TAVILY_API_KEY` env var |
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

Two tools need credentials to operate:

- `web_search` — requires a Tavily API key (`TAVILY_API_KEY` env var or
  `tavily_api_key` in `settings.json`). Without it the tool returns
  `"Error: TAVILY_API_KEY not set"` at call time.
- `github_write` — requires a GitHub personal access token (`GITHUB_TOKEN`
  env var or `github_token` in `settings.json`). Without it the tool returns
  `"Error: GITHUB_TOKEN not set"` at call time.

For both keys the environment variable takes precedence over the value in
`settings.json`.

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

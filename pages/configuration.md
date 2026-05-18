# Configuration

## settings.json

Settings load from `.ccharbour/settings.json` under the working directory, or
from the path in the `CCHARBOUR_CONFIG` environment variable. Values are merged
over the built-in defaults:

| Key               | Default                     | Meaning                       |
|-------------------|-----------------------------|-------------------------------|
| `model`           | `deepseek-chat`             | model name                    |
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

Defaults: `read`, `glob`, `grep` and `github_read` are `allow`; `write`,
`edit`, `shell`, `web_search`, `web_fetch` and `github_write` are `ask`.

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

## CLAUDE.md

A `CLAUDE.md` file in the working directory is appended to the system prompt as
project instructions, so the agent honours per-project conventions. The REPL
prints `[loaded CLAUDE.md project instructions]` at startup when it is found.
Run [`/init`](commands.md) to generate one.

## API key

The API key is read from the `DEEPSEEK_API_KEY` environment variable. CCHarbour
exits with an error if it is not set.

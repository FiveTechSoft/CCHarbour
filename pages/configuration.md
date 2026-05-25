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

### Ask-prompt timeout

When a tool is gated `ask`, the REPL prints `Allow? [y/n/a]` and waits
for input. Two safety nets keep that wait from becoming an indefinite
hang when no human is at the keyboard:

- **Non-interactive stdin auto-denies.** If `stdin` is not a TTY
  (piped input, `script -c`, a background SSH `exec_command`, a CI
  job), the prompt is skipped and the call is denied immediately.
  The REPL prints `[non-interactive stdin -- '<tool>' denied]` so the
  reason is visible in logs.
- **`CCHARBOUR_ASK_TIMEOUT` env var.** Set to a positive integer
  number of seconds to bound the wait even when stdin *is* a TTY.
  When the deadline elapses with no answer typed, the REPL prints
  `[no response in Ns -- denied]` and treats the call as denied.
  Default (unset or `0`) keeps the original blocking behaviour for
  interactive sessions where you do want to be asked.

Both fall back to *deny*, never *allow* — a missing human can never
silently approve a tool call.

## Shell timeout

The `shell` tool bounds how long a command may run, so a hung command cannot
freeze the agent. The limit is chosen in this order:

1. A `timeout` argument the model passes with the call (seconds; `0` = no limit).
2. The `shell_timeout` setting (default `30`).
3. When `shell_timeout` is `0`, an automatic per-command estimate — fast
   commands like `echo` or `dir` get a few seconds; builds and network
   commands get more.

While a command runs, the REPL shows a live countdown — the configured
timeout and the seconds still left. A command that exceeds its limit is
abandoned and its output ends with `[timed out after N seconds]`.

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

CCHarbour reads the API key from the first of these sources that is set,
in order:

1. `DEEPSEEK_API_KEY` env var (default DeepSeek backend)
2. `CCHARBOUR_API_KEY` env var (generic — use for any provider)
3. `GLM_API_KEY` or `ZHIPU_API_KEY` env var (Zhipu / GLM)
4. `MOONSHOT_API_KEY` env var (Moonshot Kimi)
5. `OPENAI_API_KEY` env var (OpenAI)
6. `"api_key"` field in `settings.json`

CCHarbour exits with an error if none of them is set. The same key is
sent to the configured `base_url`, so set both to match your provider.

## Providers

Any OpenAI-compatible Chat Completions endpoint works. Below are the
ones tested with CCHarbour, with sign-up links, **indicative pricing**
(prices change — always verify on the provider's site) and a quick read
on **coding benchmark** level (SWE-bench Verified / LiveCodeBench /
HumanEval).

| Provider     | Sign up                                                         | `base_url`                                | Example model       | Input $ / 1M tok | Output $ / 1M tok | Coding tier |
|--------------|-----------------------------------------------------------------|-------------------------------------------|---------------------|------------------|-------------------|-------------|
| **DeepSeek** | <https://platform.deepseek.com/>                                | `https://api.deepseek.com`                | `deepseek-v3.2`     | $0.27            | $1.10             | Strong      |
| **DeepSeek** | (same)                                                          | (same)                                    | `deepseek-reasoner` | $0.55            | $2.19             | Top open    |
| **GLM (Zhipu)** | <https://open.bigmodel.cn/>                                  | `https://open.bigmodel.cn/api/paas/v4`    | `glm-4.6`           | $0.60            | $2.20             | Top closed-source open-weights |
| **Moonshot** | <https://platform.moonshot.cn/>                                 | `https://api.moonshot.cn/v1`              | `kimi-k2`           | $0.15            | $2.50             | Strong      |
| **OpenAI**   | <https://platform.openai.com/>                                  | `https://api.openai.com/v1`               | `gpt-5`             | $1.25            | $10.00            | Top         |

!!! note "Anthropic Claude"
    Claude's API is not OpenAI-compatible (different message
    structure), so it does not work out of the box with CCHarbour.
    Multi-provider support is on the [roadmap](roadmap.md).

### Picking a model for coding

- **Cheapest strong option** — DeepSeek `deepseek-v3.2`. Quality is
  excellent for the price; default for a reason.
- **Best Chinese open-weight** — GLM `glm-4.6` is currently the
  strongest open-weight coder, very close to closed-source SOTA on
  SWE-bench Verified.
- **Lowest input-token cost on a frontier coder** — Moonshot `kimi-k2`.
  Output is pricier; great for short-prompt + lots-of-iteration
  workflows.
- **Absolute top, regardless of cost** — OpenAI `gpt-5` (or the latest
  o-series). Best for hardest debugging and complex multi-file
  refactors, at ~10× the price of DeepSeek.

!!! tip "Switching provider in one minute"
    Set the right env var (or put the key in `settings.json`), then
    update `base_url` and `model` in `.ccharbour/settings.json`:

    ```json
    {
      "base_url": "https://open.bigmodel.cn/api/paas/v4",
      "model": "glm-4.6"
    }
    ```

    Run `cc` — the banner now shows the new model. Switch back any time.

# DeepSeek API Client — Design (Sub-project #1)

Date: 2026-05-16
Status: Approved for planning
Language: Harbour (MT build, hbmk2)
Dependencies: `hbcurl` (libcurl with SSL), `hbjson`

## Context

This is sub-project #1 of a larger effort: a Claude Code-style agentic
CLI written in Harbour. The full effort decomposes into:

1. **DeepSeek API client** (this spec)
2. Agent loop — conversation state, multi-turn, tool-call handling
3. Tool system — registry, schemas, execution (Read/Write/Edit/Bash/Glob/Grep)
4. Terminal UI — input prompt, output rendering, streaming display
5. Permissions + config — allow/deny, settings.json, session history
6. MCP, hooks
6.5 Thread pool + subagent scheduler

Each sub-project gets its own spec → plan → implementation cycle. This
document covers #1 only.

## Goal

A reusable Harbour library that performs streaming chat completions
against the DeepSeek API (OpenAI-compatible). It exposes a small public
surface, streams response deltas to a caller-supplied callback, returns
a structured result, and never throws uncaught exceptions. It is
reentrant and pool-safe so later sub-projects can run many concurrent
requests on worker threads.

## Non-goals

- No agent loop, no tool execution (sub-projects #2, #3).
- No automatic retry/backoff — the result flags `retryable`; the caller decides.
- No terminal UI (sub-project #4).
- No persistence of conversation history (sub-project #5).

## API target

- Endpoint: `POST https://api.deepseek.com/chat/completions` (base URL configurable).
- Format: OpenAI-compatible. Request `tools` / response `tool_calls`.
- Streaming: SSE. Chunks arrive as `data: {json}` lines, terminated by `data: [DONE]`.
- Model id is configurable (passed by caller). The id `deepseek-v4-flash`
  is not verified as valid; no model id is hardcoded.
- Auth: header `Authorization: Bearer <key>`.

## Architecture

Four modules, isolated by layer. `dshttp` knows nothing of SSE;
`dssse` knows nothing of HTTP; `dsapi` orchestrates.

```
dsapi.prg     Public API
  DS_Client( hOpts ) -> oClient
  DS_ChatCompletion( oClient, aMessages, hParams, bOnEvent ) -> hResult
dssse.prg     Incremental SSE parser (OpenAI format), pure, no I/O
  DSSSE_New() -> oParser
  DSSSE_Feed( oParser, cChunk, bEmit )
dsconfig.prg  API key + base URL resolution
dshttp.prg    hbcurl wrapper: POST, headers, write-callback, cancellation
```

### Chosen approach

hbcurl with a Harbour codeblock write-callback (`HB_CURLOPT_WRITEFUNCTION`).
`curl_easy_perform` blocks and invokes the callback once per received
chunk on the calling thread. Streaming needs no extra thread at this layer.

Fallback if the installed hbcurl build does not expose a codeblock
write-callback: spawn `curl.exe --no-buffer` as a subprocess and read
stdout incrementally. Implementation plan must verify the callback
exists before committing to the primary approach.

## Public surface

### `DS_Client( hOpts ) -> oClient`

`hOpts` keys (all optional except where noted):
- `model` — model id string (required at call time, may be set here).
- `base_url` — defaults to `https://api.deepseek.com`.
- `api_key` — explicit override; normally resolved by `dsconfig`.
- `timeout` — seconds; default 120.

`oClient` holds only immutable data (URL, key, model, timeout). Safe to
share read-only across pool threads. It holds no curl handle.

### `DS_ChatCompletion( oClient, aMessages, hParams, bOnEvent ) -> hResult`

- `aMessages` — array of `{ "role" => ..., "content" => ... }` hashes.
- `hParams` — per-call overrides: `model`, `temperature`, `max_tokens`,
  `tools`, `tool_choice`, `stream` (default `.T.`).
- `bOnEvent` — codeblock `{ |hEvent| ... }` invoked per parsed SSE event.

Event types passed to `bOnEvent`:
- `{ "type" => "text_delta", "text" => ... }`
- `{ "type" => "tool_call_delta", "index" => n, "id" => ..., "name" => ..., "arguments" => ... }`
- `{ "type" => "done" }`
- `{ "type" => "error", "error_type" => ..., "message" => ... }`

### `hResult` (assembled return value)

- `success` — logical.
- `content` — full assembled assistant text.
- `tool_calls` — assembled array (OpenAI shape) or empty.
- `finish_reason` — string or NIL.
- `usage` — hash (`prompt_tokens`, `completion_tokens`) or NIL.
- `error_type` — `"network" | "api" | "stream_incomplete" | "config"` or NIL.
- `status` — HTTP status (api errors).
- `curl_code` — libcurl code (network errors).
- `retryable` — logical (`.T.` for 429 / transient).
- `message` — human-readable error string.

## Data flow

1. `dsconfig` resolves API key: env `DEEPSEEK_API_KEY` first, then config
   file fallback. Missing key → fail fast, `error_type:"config"`, no HTTP.
2. `dsapi` builds the request JSON body with `hb_jsonEncode` (`stream:.T.`).
3. `dshttp` creates a fresh curl easy handle, sets URL/headers/body and
   the write-callback, calls `curl_easy_perform`.
4. Each received chunk → `DSSSE_Feed`, which buffers partial lines,
   splits complete `data:` lines, JSON-decodes each, and emits events
   through `bEmit` (wired to the caller's `bOnEvent`).
5. `dsapi` accumulates `text_delta` and `tool_call_delta` events into
   `hResult`; `[DONE]` (or non-stream completion) finalizes.
6. The curl handle is cleaned up before return.

## Concurrency / pool-safety

- No global mutable state. All state lives in `oClient` (immutable) and
  per-call locals (`oParser`, `hResult`, curl handle).
- **Each `DS_ChatCompletion` call creates its own curl easy handle.**
  libcurl easy handles are not safe to share across threads.
- N pool threads (sub-project #6.5) can run N `DS_ChatCompletion` calls
  on the same shared `oClient` concurrently with no contention.
- Cancellation: `dshttp` installs a progress callback that checks a
  caller-supplied cancel flag (shared variable guarded by a mutex) and
  aborts `curl_easy_perform` when set.

## Error handling

- **Network:** hbcurl non-zero code → `success:.F.`, `error_type:"network"`,
  `curl_code`, `message`. No automatic retry.
- **HTTP non-2xx:** parse DeepSeek JSON error body → `error_type:"api"`,
  `status`, `code`, `message`. 429 and 5xx set `retryable:.T.`.
- **Malformed SSE:** unparseable JSON chunk → buffered (a chunk split
  mid-JSON across reads is normal, not an error). Error only if the
  stream closes without `[DONE]`: `error_type:"stream_incomplete"`.
- **Missing key:** `dsconfig` finds no key → fail before HTTP,
  `error_type:"config"`.
- **Rule:** no layer throws an uncaught exception. Every failure becomes
  an `hResult`, and `bOnEvent` receives an `{ "type" => "error" }` event.

## Testing

- **dssse.prg** — pure, no network. Core of the suite. Cases: JSON split
  mid-object across two chunks, multiple `data:` lines in one chunk,
  `[DONE]`, `tool_calls` deltas, empty keep-alive lines.
- **dsconfig.prg** — key resolution: env only, config only, both
  (env precedence), neither.
- **dshttp.prg / dsapi.prg** — need a transport. Two paths:
  - (a) opt-in real integration test, runs only when `DEEPSEEK_API_KEY` is set.
  - (b) injectable transport: `dshttp` accepts a transport codeblock that
    returns fixed chunks, so `dsapi` is fully testable offline.
- Runner: `tests.prg` — Harbour program that compiles and runs asserts,
  TAP-ish output, non-zero exit code on failure.

Injectable transport is the key isolation seam: it makes the entire
`dsapi` path testable without network access.

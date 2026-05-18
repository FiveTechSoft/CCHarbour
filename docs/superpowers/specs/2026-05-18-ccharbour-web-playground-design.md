# CCHarbour Web Playground (sub-project B)

**Date:** 2026-05-18
**Status:** Approved design, ready for implementation plan
**Scope:** Sub-project B of a two-part effort. Sub-project A (the native `web`
and `github` tools) is complete and merged. This spec covers the browser
playground only.

## Goal

A browser-based playground, hosted on the project's GitHub Pages site, where a
visitor can try CCHarbour without installing anything. It reimplements the
CCHarbour agent loop in JavaScript: the user supplies their own DeepSeek API
key, the page runs a multi-turn tool-using conversation against the DeepSeek
API, and the model can use file, web, and GitHub tools — mirroring the native
executable's behavior.

## What it is and is not

- It **is** a faithful client-side reimplementation of the CCHarbour agent
  loop and tool set, for evaluation and demonstration.
- It is **not** the native product. The `shell` tool is omitted entirely (a
  browser cannot run OS processes). File tools operate on an in-memory virtual
  file system, not the user's real disk.
- It runs entirely in the browser. There is no backend server. API calls go
  directly from the browser to `api.deepseek.com`, `api.tavily.com`, and
  `api.github.com`; all three permit browser-origin requests (CORS verified).

## Architecture

A vanilla single-page application: ES modules, no build step, no framework, no
bundler. The JavaScript modules mirror the native CCHarbour source modules so
behavior stays in parity and the native specs/tests transfer conceptually.

### File layout

The app is published; tests are not.

```
pages/playground/
  index.html
  style.css
  js/
    app.js            Entry point: loads config, builds the registry, wires UI to the agent.
    config.js         API-key + model storage in localStorage.
    sse.js            Incremental Server-Sent-Events parser.
    deepseek.js       One streaming chat completion against the DeepSeek API.
    agent.js          The multi-turn agent loop.
    vfs.js            In-memory virtual file system.
    demo-project.js   The sample project tree seeded into the vfs.
    system-prompt.js  The system message text.
    tools/
      file.js         read, write, edit, glob, grep — over the vfs.
      web.js          web_search (Tavily), web_fetch.
      github.js       github_read, github_write.
      registry.js     OpenAI tool-schema array + executor + permission gate.
    ui.js             Terminal-style REPL rendering and input.
playground-tests/
  sse.test.js
  agent.test.js
  vfs.test.js
  tools-file.test.js
  tools-web.test.js
  tools-github.test.js
```

`pages/playground/` sits inside the MkDocs `docs_dir` (`pages/`), so
`mkdocs build` copies it verbatim into `site/playground/`. The existing `docs`
workflow deploys it at `https://fivetechsoft.github.io/CCHarbour/playground/`.
No second deploy workflow is needed. `playground-tests/` lives at the repo root,
outside `pages/`, so it is never published.

### Hosting and navigation

The MkDocs site links to the playground. Add a "Playground" entry to the
`mkdocs.yml` nav pointing at the playground page (an external-style link to
`playground/index.html`, since the playground is raw HTML, not a Markdown
page). The playground page links back to the docs home.

## Modules

Each module has one responsibility and a small, testable interface. Logic
modules accept an injectable `fetch` (or transport) so tests run with no
network.

### sse.js

`createSSEParser()` returns a parser with a `feed(chunk)` method that takes raw
text chunks and returns an array of parsed events. Event types mirror the
native `dssse.prg`: `text_delta` (`{text}`), `tool_call_delta`
(`{index,id,name,arguments}`), `finish` (`{finish_reason}`), `usage`
(`{usage}`), `done`. The parser buffers partial lines across chunks. Pure — no
I/O.

### deepseek.js

`chatCompletion({ apiKey, baseUrl, model, messages, tools, temperature,
maxTokens, fetchImpl }, onEvent)` performs one streaming chat completion:

- POSTs to `${baseUrl}/chat/completions` with `stream: true` and
  `stream_options: { include_usage: true }`, header `Authorization: Bearer
  <apiKey>`.
- Reads the response body as a stream, feeds each chunk to an `sse.js` parser,
  forwards every event to `onEvent`, and accumulates `content`, `tool_calls`
  (merged by `index`), `finish_reason`, and `usage`.
- Returns `{ success, content, toolCalls, finishReason, usage, errorType,
  message }`. Non-2xx → `errorType: "api"` with the API error message;
  network/CORS failure → `errorType: "network"`; missing key/model →
  `errorType: "config"`.
- `fetchImpl` defaults to the global `fetch`; tests pass a fake.

This mirrors `DS_ChatCompletion` in `src/dsapi.prg`.

### agent.js

`runAgent({ messages, model, tools, toolExecutor, maxIterations, deepseekOpts },
onEvent)` runs the loop, mirroring `DS_AgentRun` in `src/dsagent.prg`:

- Deep-copies the input messages.
- Each iteration: emit `iteration_start`; call `chatCompletion`; append the
  assistant message. If there are no tool calls, stop. Otherwise run each tool
  call through `toolExecutor`, emit `tool_call` and `tool_result`, append a
  `tool` message per call, and loop.
- `maxIterations` defaults to 25. Reaching it sets `stopReason:
  "max_iterations"`.
- Returns `{ success, messages, content, stopReason, iterations, usage,
  errorType, message }`. A failed `chatCompletion` ends the loop with
  `stopReason: "error"`.

### vfs.js

`createVfs(seedTree)` returns an in-memory file system: a `Map` of POSIX-style
path → string content. Methods: `read(path)`, `write(path, content)`,
`exists(path)`, `list(dir)`, `glob(pattern)` (filename-mask match, recursive),
`grep(regex, { path, glob })` (returns `file:line:text` matches). `seedTree`
comes from `demo-project.js`. No persistence — a page reload restores the seed.
The UI exposes a "Reset project" action that re-seeds.

### tools/file.js

Five tools — `read`, `write`, `edit`, `glob`, `grep` — each a factory returning
`{ name, description, parameters, handler }`, operating on a vfs instance
passed in. Schemas and result semantics match the native tools in
`src/dstools_file.prg` / `src/dstools_search.prg` (including the
truncation/`[output truncated]` conventions where applicable).

### tools/web.js

`web_search` (Tavily) and `web_fetch`, mirroring `src/dstools_web.prg`.
`web_search` takes the Tavily key (captured at registry-build time; empty key →
`"Error: TAVILY_API_KEY not set"` at call time). Both use the injectable
`fetch`. `web_fetch` is subject to the target site's CORS policy — when a fetch
is blocked, it returns an `Error:` string explaining the site disallowed
browser access.

### tools/github.js

`github_read` and `github_write`, mirroring `src/dstools_github.prg`. The
GitHub token is captured at registry-build time. `github_read` works without a
token (rate-limited); `github_write` without a token returns `"Error:
GITHUB_TOKEN not set"`.

### tools/registry.js

`buildRegistry({ vfs, tavilyKey, githubToken, confirmWrite })` assembles:
- the OpenAI-format `tools` array (every tool's schema),
- an `executor(name, argsJson)` that decodes arguments, validates required
  params, runs the handler, and returns a result string (errors become
  `"Error: ..."` strings — never thrown), and
- a permission gate: every tool runs automatically **except** `github_write`,
  which calls `confirmWrite(name, args)` (a UI callback returning a promise of
  a boolean) before executing. A declined call returns `"Error: tool
  'github_write' denied by user"`.

The `shell` tool is not registered.

### config.js

Reads/writes `localStorage` keys: `ccharbour_deepseek_key`,
`ccharbour_tavily_key`, `ccharbour_github_token`, `ccharbour_model` (default
`deepseek-chat`). Provides plain getters/setters. No encryption — see Security.

### system-prompt.js

Exports the system message: states the assistant is CCHarbour running in a
browser playground, lists the available tools, and notes that the file tools
operate on an in-memory demo project (with its top-level layout).

### ui.js

Renders the terminal REPL and owns all DOM interaction:
- A welcome panel echoing the native CCHarbour banner.
- A collapsible settings panel for the three keys and the model, with the
  security warning.
- A scrollback that renders, per turn: the user's line, the assistant's
  streaming text, tool-call chips (tool name + arguments, with a collapsible
  result), inline `github_write` confirmation prompts, and error lines.
- A running token-usage display.
- An input box + send control; disabled while a turn is in flight.
- A "Reset project" control that re-seeds the vfs.

`ui.js` subscribes to agent `onEvent` callbacks; it holds no agent logic.

### app.js

Entry point: loads config, seeds the vfs from `demo-project.js`, builds the
registry, constructs the system prompt, and wires UI input to `agent.runAgent`,
streaming events back to `ui.js`. Refuses to start a turn when no DeepSeek key
is set, prompting the user to open settings.

## Data flow

1. User submits a line. `app.js` appends a `user` message to the conversation.
2. `app.js` calls `agent.runAgent` with the conversation, the registry's tools
   and executor, and an `onEvent` callback.
3. `agent.js` calls `deepseek.chatCompletion`, which streams SSE events;
   `text_delta` events render incrementally in `ui.js`.
4. If the model emits tool calls, the executor runs each (the permission gate
   prompts for `github_write`); `ui.js` shows a tool-call chip and its result.
5. Tool results are appended as `tool` messages; the loop continues until the
   model returns a final answer or the iteration cap is hit.
6. `ui.js` renders the final assistant text and the accumulated token usage.

## Error handling

- **Config:** no DeepSeek key → the turn never starts; the UI points the user
  to settings. Missing Tavily key / GitHub token surface only when the
  corresponding tool is invoked, as `Error:` strings.
- **API:** non-2xx from DeepSeek (401 bad key, 429 rate limit, 5xx) → an error
  line in the terminal carrying the API message; the turn ends.
- **Network / CORS:** a failed `fetch` → a clear network-error line. `web_fetch`
  against a CORS-restricted site returns a tool `Error:` string rather than
  ending the turn.
- **Tool errors:** every tool returns `"Error: ..."` strings (matching the
  native tools); these are fed back to the model so it can react.
- **Iteration cap:** hitting `maxIterations` shows a notice that the loop
  stopped.

## Security

The playground is fully client-side. API keys are entered by the user and held
in `localStorage` on their own machine; they are sent only to the respective
official API endpoints over HTTPS, never to any other server. The settings
panel displays a warning: keys persist in browser storage, this is a
client-side playground, and it should not be used on a shared or untrusted
computer. `github_write` performs real mutations on real repositories and is
therefore gated behind an explicit per-call confirmation.

## Testing

`node --test playground-tests/` runs the suite headlessly with no network —
every logic module takes an injectable `fetch`/transport. Coverage:

- **sse.test.js** — line buffering across chunk boundaries; each event type;
  partial/multi-event chunks.
- **agent.test.js** — single-turn stop; multi-turn with tool calls; the
  iteration cap; a failed completion ending the loop; usage accumulation.
- **vfs.test.js** — read/write/exists/list; `glob` patterns; `grep` matches.
- **tools-file.test.js** — each file tool's schema shape and behavior over a
  seeded vfs, including error cases.
- **tools-web.test.js** — `web_search` missing-key error, response formatting,
  non-2xx; `web_fetch` body return and error paths — all with a fake `fetch`.
- **tools-github.test.js** — `github_read` operation dispatch and validation;
  `github_write` missing-token, the confirmation gate, and success — with a
  fake `fetch`.

`ui.js` and `app.js` are thin DOM glue and are not unit-tested; they are
verified by manual smoke testing against the live DeepSeek API.

A new CI workflow `.github/workflows/playground.yml` runs `node --test
playground-tests/` on every push that touches `pages/playground/**` or
`playground-tests/**`, so regressions in the playground logic fail CI.

## Out of scope

- The `shell` tool.
- Real-disk file access (File System Access API) — the vfs is in-memory only.
- Persisting the vfs or conversation across page reloads.
- Authentication, accounts, server-side storage, usage metering.
- Mobile-optimized layout — desktop browser is the target.

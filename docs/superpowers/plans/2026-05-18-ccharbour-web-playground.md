# CCHarbour Web Playground — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a browser playground, hosted on the CCHarbour GitHub Pages site, that reimplements the CCHarbour agent loop in JavaScript so visitors can try it with their own DeepSeek API key.

**Architecture:** A vanilla ES-module single-page app — no build step, no framework. JS modules mirror the native CCHarbour modules (`sse`, `agent`, `deepseek`, tools). File tools run on an in-memory virtual file system; `shell` is omitted. Logic modules take an injectable `fetch` so tests run headlessly.

**Tech Stack:** Vanilla JavaScript (ES modules), the DeepSeek / Tavily / GitHub HTTP APIs, `node --test` for the test suite, MkDocs for hosting.

**Spec:** `docs/superpowers/specs/2026-05-18-ccharbour-web-playground-design.md`

---

## Conventions

- App source lives in `pages/playground/`; tests live in `playground-tests/` (repo root, not published).
- Run the full test suite from the repo root: `node --test playground-tests/`. A single file: `node --test playground-tests/sse.test.js`. Node 18+ required.
- Test files import app modules with relative paths, e.g. `import { createSSEParser } from "../pages/playground/js/sse.js";`.
- Every tool returns result **strings**; errors are `"Error: ..."` strings, never thrown.

---

## Task 1: SSE parser + test infrastructure

**Files:**
- Create: `pages/playground/js/sse.js`
- Create: `playground-tests/helpers.js`
- Create: `playground-tests/sse.test.js`
- Create: `.github/workflows/playground.yml`

- [ ] **Step 1: Create the test helpers**

Create `playground-tests/helpers.js`:

```js
// Fake HTTP responses for headless tests — no network.

// A streaming Response: getReader() yields the chunks, decoded by the caller.
export function fakeStreamResponse(chunks, { status = 200 } = {}) {
  let i = 0;
  const enc = new TextEncoder();
  return {
    ok: status >= 200 && status < 300,
    status,
    body: {
      getReader() {
        return {
          read() {
            if (i < chunks.length) {
              return Promise.resolve({ value: enc.encode(chunks[i++]), done: false });
            }
            return Promise.resolve({ value: undefined, done: true });
          },
        };
      },
    },
    async text() { return chunks.join(""); },
    async json() { return JSON.parse(chunks.join("")); },
  };
}

// A non-streaming Response carrying a JSON object or a raw string.
export function fakeJsonResponse(obj, { status = 200 } = {}) {
  const text = typeof obj === "string" ? obj : JSON.stringify(obj);
  return {
    ok: status >= 200 && status < 300,
    status,
    async text() { return text; },
    async json() { return JSON.parse(text); },
  };
}
```

- [ ] **Step 2: Write the failing test**

Create `playground-tests/sse.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { createSSEParser } from "../pages/playground/js/sse.js";

function dataLine(obj) { return "data: " + JSON.stringify(obj) + "\n\n"; }

test("sse: text deltas across a split chunk", () => {
  const p = createSSEParser();
  const full = dataLine({ choices: [{ delta: { content: "hello" } }] });
  const a = p.feed(full.slice(0, 7));
  const b = p.feed(full.slice(7));
  assert.equal(a.length, 0);
  assert.deepEqual(b, [{ type: "text_delta", text: "hello" }]);
});

test("sse: [DONE] yields a done event", () => {
  const p = createSSEParser();
  assert.deepEqual(p.feed("data: [DONE]\n\n"), [{ type: "done" }]);
});

test("sse: tool_call delta", () => {
  const p = createSSEParser();
  const ev = p.feed(dataLine({
    choices: [{ delta: { tool_calls: [
      { index: 0, id: "c1", function: { name: "read", arguments: '{"p"' } },
    ] } }],
  }));
  assert.deepEqual(ev, [{
    type: "tool_call_delta", index: 0, id: "c1", name: "read", arguments: '{"p"',
  }]);
});

test("sse: finish and usage", () => {
  const p = createSSEParser();
  const ev = p.feed(dataLine({ choices: [{ delta: {}, finish_reason: "stop" }], usage: { total_tokens: 5 } }));
  assert.deepEqual(ev, [
    { type: "usage", usage: { total_tokens: 5 } },
    { type: "finish", finish_reason: "stop" },
  ]);
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `node --test playground-tests/sse.test.js`
Expected: FAIL — cannot find module `sse.js`.

- [ ] **Step 4: Write minimal implementation**

Create `pages/playground/js/sse.js`:

```js
// Incremental Server-Sent-Events parser for the DeepSeek streaming API.
// createSSEParser() returns an object whose feed(chunk) takes a raw text
// chunk and returns an array of parsed events. Partial lines are buffered
// across calls. Pure — no I/O.

export function createSSEParser() {
  let buffer = "";
  return {
    feed(chunk) {
      buffer += chunk;
      const events = [];
      let nl;
      while ((nl = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, nl).replace(/\r$/, "");
        buffer = buffer.slice(nl + 1);
        if (!line.startsWith("data:")) continue;
        const data = line.slice(5).trim();
        if (data === "[DONE]") { events.push({ type: "done" }); continue; }
        let json;
        try { json = JSON.parse(data); } catch { continue; }
        for (const ev of eventsFromChunk(json)) events.push(ev);
      }
      return events;
    },
  };
}

function eventsFromChunk(json) {
  const out = [];
  if (json.usage) out.push({ type: "usage", usage: json.usage });
  const choice = json.choices && json.choices[0];
  if (!choice) return out;
  const delta = choice.delta || {};
  if (typeof delta.content === "string" && delta.content.length) {
    out.push({ type: "text_delta", text: delta.content });
  }
  if (Array.isArray(delta.tool_calls)) {
    for (const tc of delta.tool_calls) {
      out.push({
        type: "tool_call_delta",
        index: tc.index,
        id: tc.id ?? null,
        name: (tc.function && tc.function.name) ?? null,
        arguments: (tc.function && tc.function.arguments) ?? null,
      });
    }
  }
  if (choice.finish_reason) {
    out.push({ type: "finish", finish_reason: choice.finish_reason });
  }
  return out;
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test playground-tests/sse.test.js`
Expected: PASS — 4 tests pass.

- [ ] **Step 6: Create the CI workflow**

Create `.github/workflows/playground.yml`:

```yaml
name: playground

on:
  push:
    paths:
      - 'pages/playground/**'
      - 'playground-tests/**'
      - '.github/workflows/playground.yml'
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '22'
      - name: Run playground tests
        run: node --test playground-tests/
```

- [ ] **Step 7: Commit**

```bash
git add pages/playground/js/sse.js playground-tests/helpers.js playground-tests/sse.test.js .github/workflows/playground.yml
git commit -m "feat: playground SSE parser and test infrastructure"
```

---

## Task 2: Virtual file system

**Files:**
- Create: `pages/playground/js/vfs.js`
- Create: `playground-tests/vfs.test.js`

- [ ] **Step 1: Write the failing test**

Create `playground-tests/vfs.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { createVfs } from "../pages/playground/js/vfs.js";

const seed = {
  "README.md": "hello\nworld\n",
  "src/main.js": "import x\n",
  "src/util.js": "export const x = 1\n",
};

test("vfs: read and exists", () => {
  const vfs = createVfs(seed);
  assert.equal(vfs.read("README.md"), "hello\nworld\n");
  assert.equal(vfs.exists("src/main.js"), true);
  assert.equal(vfs.read("missing.txt"), null);
});

test("vfs: write overwrites and creates", () => {
  const vfs = createVfs(seed);
  vfs.write("new.txt", "data");
  assert.equal(vfs.read("new.txt"), "data");
  vfs.write("README.md", "changed");
  assert.equal(vfs.read("README.md"), "changed");
});

test("vfs: list a directory", () => {
  const vfs = createVfs(seed);
  assert.deepEqual(vfs.list(""), ["README.md", "src/"]);
  assert.deepEqual(vfs.list("src"), ["main.js", "util.js"]);
});

test("vfs: glob by filename mask", () => {
  const vfs = createVfs(seed);
  assert.deepEqual(vfs.glob("*.js"), ["src/main.js", "src/util.js"]);
});

test("vfs: grep returns file:line:text", () => {
  const vfs = createVfs(seed);
  assert.deepEqual(vfs.grep("world"), { matches: ["README.md:2:world"] });
});

test("vfs: grep with an invalid regex", () => {
  const vfs = createVfs(seed);
  assert.deepEqual(vfs.grep("("), { error: "invalid regex" });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test playground-tests/vfs.test.js`
Expected: FAIL — cannot find module `vfs.js`.

- [ ] **Step 3: Write minimal implementation**

Create `pages/playground/js/vfs.js`:

```js
// In-memory virtual file system: a Map of POSIX path -> string content.
// createVfs(seedTree) seeds it from an object of { path: content }.

export function createVfs(seedTree) {
  const files = new Map();

  function norm(p) {
    return String(p).replace(/^\.?\//, "").replace(/\/+/g, "/");
  }

  if (seedTree) {
    for (const [p, c] of Object.entries(seedTree)) files.set(norm(p), String(c));
  }

  function maskToRegex(mask) {
    const name = String(mask).split("/").pop();
    const esc = name
      .replace(/[.+^${}()|[\]\\]/g, "\\$&")
      .replace(/\*/g, ".*")
      .replace(/\?/g, ".");
    return new RegExp("^" + esc + "$");
  }

  return {
    read(path) {
      const p = norm(path);
      return files.has(p) ? files.get(p) : null;
    },
    write(path, content) {
      files.set(norm(path), String(content));
    },
    exists(path) {
      return files.has(norm(path));
    },
    paths() {
      return [...files.keys()].sort();
    },
    list(dir) {
      const d = norm(dir).replace(/\/$/, "");
      const prefix = d ? d + "/" : "";
      const names = new Set();
      for (const p of files.keys()) {
        if (!p.startsWith(prefix)) continue;
        const rest = p.slice(prefix.length);
        const slash = rest.indexOf("/");
        names.add(slash < 0 ? rest : rest.slice(0, slash) + "/");
      }
      return [...names].sort();
    },
    glob(pattern) {
      const re = maskToRegex(pattern);
      return [...files.keys()].filter((p) => re.test(p.split("/").pop())).sort();
    },
    grep(regexStr, opts = {}) {
      let re;
      try { re = new RegExp(regexStr); } catch { return { error: "invalid regex" }; }
      const globRe = opts.glob ? maskToRegex(opts.glob) : null;
      const matches = [];
      for (const p of [...files.keys()].sort()) {
        if (globRe && !globRe.test(p.split("/").pop())) continue;
        files.get(p).split("\n").forEach((ln, i) => {
          if (re.test(ln)) matches.push(`${p}:${i + 1}:${ln}`);
        });
      }
      return { matches };
    },
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test playground-tests/vfs.test.js`
Expected: PASS — 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add pages/playground/js/vfs.js playground-tests/vfs.test.js
git commit -m "feat: playground virtual file system"
```

---

## Task 3: DeepSeek streaming client

**Files:**
- Create: `pages/playground/js/deepseek.js`
- Create: `playground-tests/deepseek.test.js`

- [ ] **Step 1: Write the failing test**

Create `playground-tests/deepseek.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { chatCompletion } from "../pages/playground/js/deepseek.js";
import { fakeStreamResponse, fakeJsonResponse } from "./helpers.js";

function dataLine(obj) { return "data: " + JSON.stringify(obj) + "\n\n"; }

test("deepseek: streams text and reports success", async () => {
  const chunks = [
    dataLine({ choices: [{ delta: { content: "Hi" } }] }),
    dataLine({ choices: [{ delta: { content: " there" } }], finish_reason: "stop" }),
    "data: [DONE]\n\n",
  ];
  const fetchImpl = async () => fakeStreamResponse(chunks);
  const res = await chatCompletion(
    { apiKey: "k", model: "deepseek-chat", messages: [{ role: "user", content: "hi" }], fetchImpl });
  assert.equal(res.success, true);
  assert.equal(res.content, "Hi there");
  assert.equal(res.finishReason, "stop");
});

test("deepseek: accumulates a tool call", async () => {
  const chunks = [
    dataLine({ choices: [{ delta: { tool_calls: [
      { index: 0, id: "c1", function: { name: "read", arguments: '{"path":' } } ] } }] }),
    dataLine({ choices: [{ delta: { tool_calls: [
      { index: 0, function: { arguments: '"a.txt"}' } } ] } }], finish_reason: "tool_calls" }),
    "data: [DONE]\n\n",
  ];
  const res = await chatCompletion(
    { apiKey: "k", model: "m", messages: [{ role: "user", content: "x" }],
      fetchImpl: async () => fakeStreamResponse(chunks) });
  assert.equal(res.toolCalls.length, 1);
  assert.equal(res.toolCalls[0].name, "read");
  assert.equal(res.toolCalls[0].arguments, '{"path":"a.txt"}');
});

test("deepseek: non-2xx becomes an api error", async () => {
  const res = await chatCompletion(
    { apiKey: "bad", model: "m", messages: [{ role: "user", content: "x" }],
      fetchImpl: async () => fakeJsonResponse({ error: { message: "Unauthorized" } }, { status: 401 }) });
  assert.equal(res.success, false);
  assert.equal(res.errorType, "api");
  assert.equal(res.message, "Unauthorized");
});

test("deepseek: missing key is a config error", async () => {
  const res = await chatCompletion({ model: "m", messages: [{ role: "user", content: "x" }] });
  assert.equal(res.errorType, "config");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test playground-tests/deepseek.test.js`
Expected: FAIL — cannot find module `deepseek.js`.

- [ ] **Step 3: Write minimal implementation**

Create `pages/playground/js/deepseek.js`:

```js
// One streaming chat completion against the DeepSeek API.
// Mirrors DS_ChatCompletion in the native src/dsapi.prg.

import { createSSEParser } from "./sse.js";

export async function chatCompletion(opts, onEvent) {
  const {
    apiKey,
    baseUrl = "https://api.deepseek.com",
    model,
    messages,
    tools,
    temperature,
    maxTokens,
    fetchImpl = fetch,
  } = opts;

  const result = {
    success: false, content: "", toolCalls: [], finishReason: null,
    usage: null, errorType: null, message: null,
  };

  if (!apiKey) { result.errorType = "config"; result.message = "No DeepSeek API key"; return result; }
  if (!model) { result.errorType = "config"; result.message = "No model id"; return result; }

  const body = { model, messages, stream: true, stream_options: { include_usage: true } };
  if (tools) body.tools = tools;
  if (temperature != null) body.temperature = temperature;
  if (maxTokens != null) body.max_tokens = maxTokens;

  let resp;
  try {
    resp = await fetchImpl(baseUrl + "/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
        "Authorization": "Bearer " + apiKey,
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    result.errorType = "network";
    result.message = String((e && e.message) || e);
    emit(onEvent, { type: "error", errorType: "network", message: result.message });
    return result;
  }

  if (!resp.ok) {
    result.errorType = "api";
    result.message = apiErrorMessage(await safeText(resp), resp.status);
    emit(onEvent, { type: "error", errorType: "api", message: result.message });
    return result;
  }

  const parser = createSSEParser();
  const state = { content: "", tools: [], finish: null, usage: null };
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    for (const ev of parser.feed(decoder.decode(value, { stream: true }))) {
      foldEvent(ev, state);
      emit(onEvent, ev);
    }
  }

  result.success = true;
  result.content = state.content;
  result.toolCalls = state.tools.map((t) => ({ id: t.id, name: t.name, arguments: t.arguments }));
  result.finishReason = state.finish;
  result.usage = state.usage;
  return result;
}

function foldEvent(ev, state) {
  if (ev.type === "text_delta") state.content += ev.text;
  else if (ev.type === "tool_call_delta") accTool(state.tools, ev);
  else if (ev.type === "finish") state.finish = ev.finish_reason;
  else if (ev.type === "usage") state.usage = ev.usage;
}

function accTool(tools, ev) {
  let t = tools.find((x) => x.index === ev.index);
  if (!t) { t = { index: ev.index, id: "", name: "", arguments: "" }; tools.push(t); }
  if (ev.id) t.id = ev.id;
  if (ev.name) t.name = ev.name;
  if (ev.arguments) t.arguments += ev.arguments;
}

function apiErrorMessage(text, status) {
  try {
    const j = JSON.parse(text);
    if (j && j.error && j.error.message) return j.error.message;
  } catch { /* fall through */ }
  return "HTTP " + status;
}

async function safeText(resp) {
  try { return await resp.text(); } catch { return ""; }
}

function emit(cb, ev) { if (cb) cb(ev); }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test playground-tests/deepseek.test.js`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add pages/playground/js/deepseek.js playground-tests/deepseek.test.js
git commit -m "feat: playground DeepSeek streaming client"
```

---

## Task 4: Agent loop

**Files:**
- Create: `pages/playground/js/agent.js`
- Create: `playground-tests/agent.test.js`

- [ ] **Step 1: Write the failing test**

Create `playground-tests/agent.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { runAgent } from "../pages/playground/js/agent.js";
import { fakeStreamResponse } from "./helpers.js";

function dataLine(obj) { return "data: " + JSON.stringify(obj) + "\n\n"; }
const DONE = "data: [DONE]\n\n";

function textTurn(text) {
  return [dataLine({ choices: [{ delta: { content: text } }], finish_reason: "stop" }), DONE];
}
function toolTurn(name, args) {
  return [
    dataLine({ choices: [{ delta: { tool_calls: [
      { index: 0, id: "c1", function: { name, arguments: args } } ] } }], finish_reason: "tool_calls" }),
    DONE,
  ];
}

// A fetchImpl that returns a scripted streaming response per call.
function scriptedFetch(turns) {
  let i = 0;
  return async () => fakeStreamResponse(turns[i++]);
}

test("agent: single text turn stops", async () => {
  const res = await runAgent({
    messages: [{ role: "user", content: "hi" }],
    model: "m",
    deepseekOpts: { apiKey: "k", fetchImpl: scriptedFetch([textTurn("done")]) },
  });
  assert.equal(res.success, true);
  assert.equal(res.stopReason, "stop");
  assert.equal(res.content, "done");
  assert.equal(res.iterations, 1);
});

test("agent: a tool call then a final answer", async () => {
  const calls = [];
  const res = await runAgent({
    messages: [{ role: "user", content: "read it" }],
    model: "m",
    tools: [{ type: "function", function: { name: "read" } }],
    toolExecutor: async (name, args) => { calls.push([name, args]); return "file body"; },
    deepseekOpts: { apiKey: "k", fetchImpl: scriptedFetch([
      toolTurn("read", '{"path":"a.txt"}'),
      textTurn("the file says hello"),
    ]) },
  });
  assert.equal(res.iterations, 2);
  assert.equal(res.content, "the file says hello");
  assert.deepEqual(calls, [["read", '{"path":"a.txt"}']]);
});

test("agent: iteration cap", async () => {
  const res = await runAgent({
    messages: [{ role: "user", content: "loop" }],
    model: "m",
    maxIterations: 2,
    toolExecutor: async () => "again",
    deepseekOpts: { apiKey: "k", fetchImpl: scriptedFetch([
      toolTurn("read", "{}"), toolTurn("read", "{}"),
    ]) },
  });
  assert.equal(res.stopReason, "max_iterations");
  assert.equal(res.iterations, 2);
});

test("agent: a failed completion ends the loop", async () => {
  const res = await runAgent({
    messages: [{ role: "user", content: "x" }],
    model: "m",
    deepseekOpts: { apiKey: "", fetchImpl: scriptedFetch([textTurn("never")]) },
  });
  assert.equal(res.stopReason, "error");
  assert.equal(res.errorType, "config");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test playground-tests/agent.test.js`
Expected: FAIL — cannot find module `agent.js`.

- [ ] **Step 3: Write minimal implementation**

Create `pages/playground/js/agent.js`:

```js
// The multi-turn agent loop. Mirrors DS_AgentRun in the native src/dsagent.prg.

import { chatCompletion } from "./deepseek.js";

export async function runAgent(opts, onEvent) {
  const {
    messages,
    model,
    tools,
    toolExecutor,
    maxIterations = 25,
    deepseekOpts = {},
  } = opts;

  const result = {
    success: false, messages: [], content: "", stopReason: null,
    iterations: 0, usage: {}, errorType: null, message: null,
  };

  if (!Array.isArray(messages) || messages.length === 0) {
    result.errorType = "config";
    result.message = "messages must be a non-empty array";
    result.stopReason = "error";
    return result;
  }

  const msgs = JSON.parse(JSON.stringify(messages));
  const usage = {};
  let iter = 0;

  while (iter < maxIterations) {
    iter++;
    emit(onEvent, { type: "iteration_start", n: iter });

    const chat = await chatCompletion(
      { ...deepseekOpts, model, messages: msgs, tools }, onEvent);

    if (!chat.success) {
      result.messages = msgs;
      result.iterations = iter;
      result.usage = usage;
      result.errorType = chat.errorType;
      result.message = chat.message;
      result.stopReason = "error";
      return result;
    }

    addUsage(usage, chat.usage);
    msgs.push(assistantMessage(chat));

    if (!chat.toolCalls || chat.toolCalls.length === 0) {
      result.stopReason = "stop";
      break;
    }

    if (typeof toolExecutor !== "function") {
      result.messages = msgs;
      result.iterations = iter;
      result.usage = usage;
      result.errorType = "config";
      result.message = "model requested a tool but no toolExecutor was provided";
      result.stopReason = "error";
      return result;
    }

    for (const tc of chat.toolCalls) {
      emit(onEvent, { type: "tool_call", id: tc.id, name: tc.name, arguments: tc.arguments });
      const res = await toolExecutor(tc.name, tc.arguments);
      emit(onEvent, { type: "tool_result", id: tc.id, content: res });
      msgs.push({ role: "tool", tool_call_id: tc.id, content: res });
    }
  }

  if (result.stopReason == null) result.stopReason = "max_iterations";

  result.success = true;
  result.messages = msgs;
  result.iterations = iter;
  result.usage = usage;
  result.content = lastAssistantText(msgs);
  return result;
}

function assistantMessage(chat) {
  const m = { role: "assistant", content: chat.content || "" };
  if (chat.toolCalls && chat.toolCalls.length) {
    m.tool_calls = chat.toolCalls.map((tc) => ({
      id: tc.id, type: "function",
      function: { name: tc.name, arguments: tc.arguments },
    }));
  }
  return m;
}

function lastAssistantText(msgs) {
  for (let i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i].role === "assistant") return msgs[i].content || "";
  }
  return "";
}

function addUsage(usage, u) {
  if (!u || typeof u !== "object") return;
  for (const k of Object.keys(u)) {
    if (typeof u[k] === "number") usage[k] = (usage[k] || 0) + u[k];
  }
}

function emit(cb, ev) { if (cb) cb(ev); }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test playground-tests/agent.test.js`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add pages/playground/js/agent.js playground-tests/agent.test.js
git commit -m "feat: playground agent loop"
```

---

## Task 5: File tools

**Files:**
- Create: `pages/playground/js/tools/file.js`
- Create: `playground-tests/tools-file.test.js`

- [ ] **Step 1: Write the failing test**

Create `playground-tests/tools-file.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileTools } from "../pages/playground/js/tools/file.js";
import { createVfs } from "../pages/playground/js/vfs.js";

function tools() {
  const vfs = createVfs({ "a.txt": "one\ntwo\n", "src/x.js": "const x = 1\n" });
  const map = new Map(fileTools(vfs).map((t) => [t.name, t]));
  return { vfs, map };
}

test("file: the five tools are present", () => {
  const { map } = tools();
  for (const n of ["read", "write", "edit", "glob", "grep"]) {
    assert.equal(map.has(n), true, n);
  }
});

test("file: read returns content, missing file errors", () => {
  const { map } = tools();
  assert.equal(map.get("read").handler({ path: "a.txt" }), "one\ntwo\n");
  assert.match(map.get("read").handler({ path: "no.txt" }), /^Error: file not found/);
});

test("file: write creates a file", () => {
  const { vfs, map } = tools();
  const r = map.get("write").handler({ path: "new.txt", content: "hi" });
  assert.match(r, /^Wrote /);
  assert.equal(vfs.read("new.txt"), "hi");
});

test("file: edit replaces, reports missing old_string", () => {
  const { vfs, map } = tools();
  assert.match(map.get("edit").handler({ path: "a.txt", old_string: "one", new_string: "ONE" }), /^Edited /);
  assert.equal(vfs.read("a.txt"), "ONE\ntwo\n");
  assert.match(map.get("edit").handler({ path: "a.txt", old_string: "zzz", new_string: "x" }), /not found/);
});

test("file: glob and grep", () => {
  const { map } = tools();
  assert.equal(map.get("glob").handler({ pattern: "*.js" }), "src/x.js");
  assert.equal(map.get("grep").handler({ pattern: "two" }), "a.txt:2:two");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test playground-tests/tools-file.test.js`
Expected: FAIL — cannot find module `tools/file.js`.

- [ ] **Step 3: Write minimal implementation**

Create `pages/playground/js/tools/file.js`:

```js
// File tools operating on a virtual file system instance. Each tool is
// { name, description, parameters, handler }. Schemas mirror the native
// src/dstools_file.prg and src/dstools_search.prg.

function cap(s) {
  return s.length > 30000 ? s.slice(0, 30000) + "\n[output truncated]\n" : s;
}

export function fileTools(vfs) {
  return [
    {
      name: "read",
      description: "Read a file's contents from the project.",
      parameters: {
        type: "object",
        properties: { path: { type: "string", description: "File path" } },
        required: ["path"],
      },
      handler(args) {
        const c = vfs.read(args.path);
        return c == null ? "Error: file not found: " + args.path : cap(c);
      },
    },
    {
      name: "write",
      description: "Create or overwrite a file with the given contents.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path" },
          content: { type: "string", description: "File contents" },
        },
        required: ["path", "content"],
      },
      handler(args) {
        vfs.write(args.path, args.content ?? "");
        return "Wrote " + args.path;
      },
    },
    {
      name: "edit",
      description: "Replace the first occurrence of a string in a file.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path" },
          old_string: { type: "string", description: "Text to replace" },
          new_string: { type: "string", description: "Replacement text" },
        },
        required: ["path", "old_string", "new_string"],
      },
      handler(args) {
        const c = vfs.read(args.path);
        if (c == null) return "Error: file not found: " + args.path;
        if (!c.includes(args.old_string)) {
          return "Error: old_string not found in " + args.path;
        }
        vfs.write(args.path, c.replace(args.old_string, args.new_string));
        return "Edited " + args.path;
      },
    },
    {
      name: "glob",
      description: "List files matching a filename pattern (e.g. *.js).",
      parameters: {
        type: "object",
        properties: { pattern: { type: "string", description: "Filename mask" } },
        required: ["pattern"],
      },
      handler(args) {
        const m = vfs.glob(args.pattern);
        return m.length ? cap(m.join("\n")) : "No matches for " + args.pattern;
      },
    },
    {
      name: "grep",
      description: "Search file contents with a regular expression. Returns file:line:text matches.",
      parameters: {
        type: "object",
        properties: {
          pattern: { type: "string", description: "Regular expression" },
          glob: { type: "string", description: "Filename mask filter" },
        },
        required: ["pattern"],
      },
      handler(args) {
        const r = vfs.grep(args.pattern, { glob: args.glob });
        if (r.error) return "Error: " + r.error;
        return r.matches.length
          ? cap(r.matches.join("\n"))
          : "No matches for " + args.pattern;
      },
    },
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test playground-tests/tools-file.test.js`
Expected: PASS — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add pages/playground/js/tools/file.js playground-tests/tools-file.test.js
git commit -m "feat: playground file tools"
```

---

## Task 6: Web tools

**Files:**
- Create: `pages/playground/js/tools/web.js`
- Create: `playground-tests/tools-web.test.js`

- [ ] **Step 1: Write the failing test**

Create `playground-tests/tools-web.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { webTools } from "../pages/playground/js/tools/web.js";
import { fakeJsonResponse } from "./helpers.js";

function map(tavilyKey, fetchImpl) {
  return new Map(webTools(tavilyKey, fetchImpl).map((t) => [t.name, t]));
}

test("web_search: missing key", async () => {
  const r = await map("", async () => {}).get("web_search").handler({ query: "x" });
  assert.equal(r, "Error: TAVILY_API_KEY not set");
});

test("web_search: formats results", async () => {
  const fetchImpl = async () => fakeJsonResponse({ results: [
    { title: "T1", url: "U1", content: "C1" } ] });
  const r = await map("k", fetchImpl).get("web_search").handler({ query: "x" });
  assert.ok(r.includes("T1") && r.includes("U1") && r.includes("C1"));
});

test("web_search: non-2xx", async () => {
  const fetchImpl = async () => fakeJsonResponse({}, { status: 401 });
  const r = await map("k", fetchImpl).get("web_search").handler({ query: "x" });
  assert.equal(r, "Error: web_search HTTP 401");
});

test("web_fetch: returns body", async () => {
  const fetchImpl = async () => fakeJsonResponse("page text", { status: 200 });
  const r = await map("", fetchImpl).get("web_fetch").handler({ url: "https://x" });
  assert.equal(r, "page text");
});

test("web_fetch: blocked fetch becomes an error", async () => {
  const fetchImpl = async () => { throw new Error("blocked by CORS"); };
  const r = await map("", fetchImpl).get("web_fetch").handler({ url: "https://x" });
  assert.match(r, /^Error: web_fetch failed/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test playground-tests/tools-web.test.js`
Expected: FAIL — cannot find module `tools/web.js`.

- [ ] **Step 3: Write minimal implementation**

Create `pages/playground/js/tools/web.js`:

```js
// Web tools: web_search (Tavily) and web_fetch. Mirrors src/dstools_web.prg.

function cap(s) {
  return s.length > 30000 ? s.slice(0, 30000) + "\n[output truncated]\n" : s;
}

export function webTools(tavilyKey, fetchImpl = fetch) {
  return [
    {
      name: "web_search",
      description: "Search the web via the Tavily API. Returns ranked title/url/snippet results.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "The search query" },
          max_results: { type: "integer", description: "Maximum number of results (default 5)" },
        },
        required: ["query"],
      },
      async handler(args) {
        if (!tavilyKey) return "Error: TAVILY_API_KEY not set";
        let resp;
        try {
          resp = await fetchImpl("https://api.tavily.com/search", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              api_key: tavilyKey,
              query: String(args.query),
              max_results: typeof args.max_results === "number" ? args.max_results : 5,
              search_depth: "basic",
            }),
          });
        } catch (e) {
          return "Error: web_search failed: " + ((e && e.message) || e);
        }
        if (resp.status < 200 || resp.status >= 300) {
          return "Error: web_search HTTP " + resp.status;
        }
        let body;
        try { body = await resp.json(); } catch { return "Error: web_search: unexpected response"; }
        if (!body || !Array.isArray(body.results)) {
          return "Error: web_search: unexpected response";
        }
        const out = body.results
          .map((r) => `${r.title}\n${r.url}\n${r.content}`)
          .join("\n\n");
        return out ? cap(out) : "No results for " + args.query;
      },
    },
    {
      name: "web_fetch",
      description: "Fetch the raw content of a URL (text or HTML, not converted).",
      parameters: {
        type: "object",
        properties: { url: { type: "string", description: "The URL to fetch" } },
        required: ["url"],
      },
      async handler(args) {
        let resp;
        try {
          resp = await fetchImpl(String(args.url));
        } catch (e) {
          return "Error: web_fetch failed (the site may block browser access): " +
            ((e && e.message) || e);
        }
        if (resp.status < 200 || resp.status >= 300) {
          return "Error: web_fetch HTTP " + resp.status;
        }
        let text;
        try { text = await resp.text(); }
        catch (e) { return "Error: web_fetch failed: " + ((e && e.message) || e); }
        return cap(text);
      },
    },
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test playground-tests/tools-web.test.js`
Expected: PASS — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add pages/playground/js/tools/web.js playground-tests/tools-web.test.js
git commit -m "feat: playground web tools"
```

---

## Task 7: GitHub tools

**Files:**
- Create: `pages/playground/js/tools/github.js`
- Create: `playground-tests/tools-github.test.js`

- [ ] **Step 1: Write the failing test**

Create `playground-tests/tools-github.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { githubTools } from "../pages/playground/js/tools/github.js";
import { fakeJsonResponse } from "./helpers.js";

function map(token, fetchImpl) {
  return new Map(githubTools(token, fetchImpl).map((t) => [t.name, t]));
}

test("github_read: validation errors", async () => {
  const m = map("", async () => {});
  assert.equal(await m.get("github_read").handler({ operation: "repo" }),
    "Error: github_read 'repo' requires 'repo'");
  assert.equal(await m.get("github_read").handler({ operation: "search" }),
    "Error: github_read 'search' requires 'query'");
  assert.equal(await m.get("github_read").handler({ operation: "bogus", repo: "a/b" }),
    "Error: github_read: unknown operation 'bogus'");
});

test("github_read: file decodes base64", async () => {
  const content = Buffer.from("hello world").toString("base64");
  const fetchImpl = async () => fakeJsonResponse({ content });
  const r = await map("", fetchImpl).get("github_read")
    .handler({ operation: "file", repo: "a/b", path: "README.md" });
  assert.equal(r, "hello world");
});

test("github_read: non-2xx surfaces the API message", async () => {
  const fetchImpl = async () => fakeJsonResponse({ message: "Not Found" }, { status: 404 });
  const r = await map("", fetchImpl).get("github_read").handler({ operation: "repo", repo: "a/b" });
  assert.equal(r, "Error: github_read HTTP 404: Not Found");
});

test("github_write: missing token", async () => {
  const r = await map("", async () => {}).get("github_write")
    .handler({ operation: "create_issue", repo: "a/b", title: "T" });
  assert.equal(r, "Error: GITHUB_TOKEN not set");
});

test("github_write: create_issue reports the URL", async () => {
  const fetchImpl = async (url, init) => {
    assert.equal(init.method, "POST");
    return fakeJsonResponse({ html_url: "https://github.com/a/b/issues/7" }, { status: 201 });
  };
  const r = await map("tok", fetchImpl).get("github_write")
    .handler({ operation: "create_issue", repo: "a/b", title: "Bug", body: "d" });
  assert.equal(r, "Created: https://github.com/a/b/issues/7");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test playground-tests/tools-github.test.js`
Expected: FAIL — cannot find module `tools/github.js`.

- [ ] **Step 3: Write minimal implementation**

Create `pages/playground/js/tools/github.js`:

```js
// GitHub tools: github_read and github_write. Mirrors src/dstools_github.prg.

const GH = "https://api.github.com";

function cap(s) {
  return s.length > 30000 ? s.slice(0, 30000) + "\n[output truncated]\n" : s;
}

function ghHeaders(token) {
  const h = {
    "Accept": "application/vnd.github+json",
    "Content-Type": "application/json",
  };
  if (token) h["Authorization"] = "Bearer " + token;
  return h;
}

function apiMessage(body) {
  try { const j = JSON.parse(body); if (j && j.message) return j.message; } catch { /* ignore */ }
  return "";
}

async function safeText(resp) {
  try { return await resp.text(); } catch { return ""; }
}

function encodePath(p) {
  return String(p).split("/").map(encodeURIComponent).join("/");
}

function formatRead(op, body) {
  if (op === "file") {
    try {
      const j = JSON.parse(body);
      if (j && j.content) return cap(atob(j.content.replace(/\n/g, "")));
    } catch { /* fall through */ }
    return cap(body);
  }
  if (op === "list") {
    try {
      const j = JSON.parse(body);
      if (Array.isArray(j)) {
        return cap(j.filter((e) => e && e.name)
          .map((e) => `${e.type || ""}  ${e.name}`).join("\n"));
      }
    } catch { /* fall through */ }
    return cap(body);
  }
  return cap(body);
}

export function githubTools(token, fetchImpl = fetch) {
  return [
    {
      name: "github_read",
      description: "Read from GitHub: repo info, file content, directory listing, issues, pull requests, code search.",
      parameters: {
        type: "object",
        properties: {
          operation: { type: "string", description: "One of: repo, file, list, issues, issue, prs, pr, search" },
          repo: { type: "string", description: "Repository as owner/name (every operation except search)" },
          path: { type: "string", description: "File or directory path (file, list)" },
          number: { type: "integer", description: "Issue or PR number (issue, pr)" },
          query: { type: "string", description: "Code search query (search)" },
        },
        required: ["operation"],
      },
      async handler(args) {
        const op = String(args.operation || "").toLowerCase();
        let url;
        if (op === "search") {
          if (!args.query) return "Error: github_read 'search' requires 'query'";
          url = `${GH}/search/code?q=${encodeURIComponent(args.query)}`;
        } else {
          if (!args.repo) return `Error: github_read '${op}' requires 'repo'`;
          const repo = String(args.repo);
          if (op === "repo") {
            url = `${GH}/repos/${repo}`;
          } else if (op === "file" || op === "list") {
            if (!args.path) return `Error: github_read '${op}' requires 'path'`;
            url = `${GH}/repos/${repo}/contents/${encodePath(args.path)}`;
          } else if (op === "issues") {
            url = `${GH}/repos/${repo}/issues`;
          } else if (op === "issue") {
            if (typeof args.number !== "number") return "Error: github_read 'issue' requires a numeric 'number'";
            url = `${GH}/repos/${repo}/issues/${args.number}`;
          } else if (op === "prs") {
            url = `${GH}/repos/${repo}/pulls`;
          } else if (op === "pr") {
            if (typeof args.number !== "number") return "Error: github_read 'pr' requires a numeric 'number'";
            url = `${GH}/repos/${repo}/pulls/${args.number}`;
          } else {
            return `Error: github_read: unknown operation '${op}'`;
          }
        }
        let resp;
        try { resp = await fetchImpl(url, { headers: ghHeaders(token) }); }
        catch (e) { return "Error: github_read failed: " + ((e && e.message) || e); }
        const body = await safeText(resp);
        if (resp.status < 200 || resp.status >= 300) {
          return `Error: github_read HTTP ${resp.status}: ${apiMessage(body)}`;
        }
        return formatRead(op, body);
      },
    },
    {
      name: "github_write",
      description: "Write to GitHub: create an issue, comment on an issue, or open a pull request. Requires a GitHub token.",
      parameters: {
        type: "object",
        properties: {
          operation: { type: "string", description: "One of: create_issue, comment, create_pr" },
          repo: { type: "string", description: "Repository as owner/name" },
          number: { type: "integer", description: "Issue number (comment)" },
          title: { type: "string", description: "Title (create_issue, create_pr)" },
          body: { type: "string", description: "Body text" },
          head: { type: "string", description: "Source branch (create_pr)" },
          base: { type: "string", description: "Target branch (create_pr)" },
        },
        required: ["operation", "repo"],
      },
      async handler(args) {
        if (!token) return "Error: GITHUB_TOKEN not set";
        const op = String(args.operation || "").toLowerCase();
        const repo = String(args.repo);
        let url, payload;
        if (op === "create_issue") {
          if (!args.title) return "Error: github_write 'create_issue' requires 'title'";
          url = `${GH}/repos/${repo}/issues`;
          payload = { title: String(args.title), body: args.body ? String(args.body) : "" };
        } else if (op === "comment") {
          if (typeof args.number !== "number") return "Error: github_write 'comment' requires 'number'";
          url = `${GH}/repos/${repo}/issues/${args.number}/comments`;
          payload = { body: args.body ? String(args.body) : "" };
        } else if (op === "create_pr") {
          if (!args.title || !args.head || !args.base) {
            return "Error: github_write 'create_pr' requires 'title', 'head', 'base'";
          }
          url = `${GH}/repos/${repo}/pulls`;
          payload = {
            title: String(args.title), head: String(args.head),
            base: String(args.base), body: args.body ? String(args.body) : "",
          };
        } else {
          return `Error: github_write: unknown operation '${op}'`;
        }
        let resp;
        try {
          resp = await fetchImpl(url, {
            method: "POST", headers: ghHeaders(token), body: JSON.stringify(payload),
          });
        } catch (e) { return "Error: github_write failed: " + ((e && e.message) || e); }
        const body = await safeText(resp);
        if (resp.status < 200 || resp.status >= 300) {
          return `Error: github_write HTTP ${resp.status}: ${apiMessage(body)}`;
        }
        try { const j = JSON.parse(body); if (j && j.html_url) return "Created: " + j.html_url; }
        catch { /* ignore */ }
        return "OK";
      },
    },
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test playground-tests/tools-github.test.js`
Expected: PASS — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add pages/playground/js/tools/github.js playground-tests/tools-github.test.js
git commit -m "feat: playground github tools"
```

---

## Task 8: Tool registry

**Files:**
- Create: `pages/playground/js/tools/registry.js`
- Create: `playground-tests/registry.test.js`

- [ ] **Step 1: Write the failing test**

Create `playground-tests/registry.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { buildRegistry } from "../pages/playground/js/tools/registry.js";
import { createVfs } from "../pages/playground/js/vfs.js";
import { fakeJsonResponse } from "./helpers.js";

function reg(extra = {}) {
  return buildRegistry({
    vfs: createVfs({ "a.txt": "body" }),
    tavilyKey: "",
    githubToken: "tok",
    fetchImpl: async () => fakeJsonResponse({ html_url: "https://x/1" }, { status: 201 }),
    confirmWrite: async () => true,
    ...extra,
  });
}

test("registry: schemas cover all ten tools, no shell", () => {
  const { schemas } = reg();
  const names = schemas.map((s) => s.function.name).sort();
  assert.deepEqual(names, [
    "edit", "github_read", "github_write", "glob", "grep",
    "read", "web_fetch", "web_search", "write",
  ].sort());
  assert.equal(names.includes("shell"), false);
});

test("registry: executor runs a file tool", async () => {
  const { executor } = reg();
  assert.equal(await executor("read", '{"path":"a.txt"}'), "body");
});

test("registry: executor rejects bad JSON and missing args", async () => {
  const { executor } = reg();
  assert.equal(await executor("read", "{bad"), "Error: invalid arguments JSON");
  assert.equal(await executor("read", "{}"), "Error: missing required argument 'path'");
  assert.equal(await executor("nope", "{}"), "Error: unknown tool 'nope'");
});

test("registry: github_write runs when confirmed", async () => {
  const { executor } = reg({ confirmWrite: async () => true });
  const r = await executor("github_write", '{"operation":"create_issue","repo":"a/b","title":"T"}');
  assert.equal(r, "Created: https://x/1");
});

test("registry: github_write denied when not confirmed", async () => {
  const { executor } = reg({ confirmWrite: async () => false });
  const r = await executor("github_write", '{"operation":"create_issue","repo":"a/b","title":"T"}');
  assert.equal(r, "Error: tool 'github_write' denied by user");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test playground-tests/registry.test.js`
Expected: FAIL — cannot find module `tools/registry.js`.

- [ ] **Step 3: Write minimal implementation**

Create `pages/playground/js/tools/registry.js`:

```js
// Assembles the tool registry: OpenAI tool schemas, an executor, and the
// permission gate. Mirrors src/dstools.prg. The shell tool is not included.

import { fileTools } from "./file.js";
import { webTools } from "./web.js";
import { githubTools } from "./github.js";

export function buildRegistry({ vfs, tavilyKey, githubToken, confirmWrite, fetchImpl }) {
  const tools = [
    ...fileTools(vfs),
    ...webTools(tavilyKey || "", fetchImpl),
    ...githubTools(githubToken || "", fetchImpl),
  ];
  const byName = new Map(tools.map((t) => [t.name, t]));

  const schemas = tools.map((t) => ({
    type: "function",
    function: { name: t.name, description: t.description, parameters: t.parameters },
  }));

  async function executor(name, argsJson) {
    const tool = byName.get(name);
    if (!tool) return "Error: unknown tool '" + name + "'";

    let args;
    try { args = JSON.parse(argsJson || "{}"); }
    catch { return "Error: invalid arguments JSON"; }
    if (typeof args !== "object" || args == null) return "Error: invalid arguments JSON";

    for (const req of tool.parameters.required || []) {
      if (!(req in args)) return "Error: missing required argument '" + req + "'";
    }

    // Permission gate: github_write mutates real repositories, so it needs
    // an explicit per-call confirmation. Every other tool runs automatically.
    if (name === "github_write") {
      const ok = confirmWrite ? await confirmWrite(name, args) : false;
      if (!ok) return "Error: tool 'github_write' denied by user";
    }

    try { return await tool.handler(args); }
    catch (e) { return "Error: tool '" + name + "' failed: " + ((e && e.message) || e); }
  }

  return { schemas, executor };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test playground-tests/registry.test.js`
Expected: PASS — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add pages/playground/js/tools/registry.js playground-tests/registry.test.js
git commit -m "feat: playground tool registry and permission gate"
```

---

## Task 9: Config, demo project, system prompt

**Files:**
- Create: `pages/playground/js/config.js`
- Create: `pages/playground/js/demo-project.js`
- Create: `pages/playground/js/system-prompt.js`
- Create: `playground-tests/system-prompt.test.js`

- [ ] **Step 1: Write the failing test**

Create `playground-tests/system-prompt.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { systemPrompt } from "../pages/playground/js/system-prompt.js";
import { DEMO_PROJECT } from "../pages/playground/js/demo-project.js";
import { createVfs } from "../pages/playground/js/vfs.js";

test("system prompt names CCHarbour and lists the demo files", () => {
  const vfs = createVfs(DEMO_PROJECT);
  const p = systemPrompt(vfs);
  assert.match(p, /CCHarbour/);
  assert.match(p, /README\.md/);
  assert.match(p, /shell/);
});

test("demo project is a non-empty object of string contents", () => {
  const entries = Object.entries(DEMO_PROJECT);
  assert.ok(entries.length > 0);
  for (const [, c] of entries) assert.equal(typeof c, "string");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test playground-tests/system-prompt.test.js`
Expected: FAIL — cannot find module `system-prompt.js`.

- [ ] **Step 3: Write minimal implementation**

Create `pages/playground/js/demo-project.js`:

```js
// The sample project seeded into the virtual file system.
export const DEMO_PROJECT = {
  "README.md":
    "# Demo Project\n\n" +
    "A tiny sample project for the CCHarbour playground. Ask the assistant " +
    "to read, search, or edit these files.\n",
  "package.json":
    "{\n  \"name\": \"demo\",\n  \"version\": \"1.0.0\",\n" +
    "  \"type\": \"module\"\n}\n",
  "src/main.js":
    "import { greet } from './greet.js';\n\n" +
    "console.log(greet('world'));\n",
  "src/greet.js":
    "export function greet(name) {\n" +
    "  return 'Hello, ' + name + '!';\n" +
    "}\n",
};
```

Create `pages/playground/js/system-prompt.js`:

```js
// Builds the system message for the playground agent.
export function systemPrompt(vfs) {
  return [
    "You are CCHarbour, a terminal coding assistant, running in a browser playground.",
    "You can use tools to read, write and edit files, search the project, search the",
    "web, and read or write GitHub. The file tools operate on an in-memory demo",
    "project — they do not touch the user's real disk. The shell tool is not",
    "available in this playground.",
    "",
    "The demo project contains these files:",
    vfs.paths().join("\n"),
  ].join("\n");
}
```

Create `pages/playground/js/config.js`:

```js
// API-key and model storage, backed by the browser's localStorage.

const KEYS = {
  deepseek: "ccharbour_deepseek_key",
  tavily: "ccharbour_tavily_key",
  github: "ccharbour_github_token",
  model: "ccharbour_model",
};

export function loadConfig() {
  return {
    deepseekKey: localStorage.getItem(KEYS.deepseek) || "",
    tavilyKey: localStorage.getItem(KEYS.tavily) || "",
    githubToken: localStorage.getItem(KEYS.github) || "",
    model: localStorage.getItem(KEYS.model) || "deepseek-chat",
  };
}

export function saveConfig(cfg) {
  localStorage.setItem(KEYS.deepseek, cfg.deepseekKey || "");
  localStorage.setItem(KEYS.tavily, cfg.tavilyKey || "");
  localStorage.setItem(KEYS.github, cfg.githubToken || "");
  localStorage.setItem(KEYS.model, cfg.model || "deepseek-chat");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test playground-tests/system-prompt.test.js`
Expected: PASS — 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add pages/playground/js/config.js pages/playground/js/demo-project.js pages/playground/js/system-prompt.js playground-tests/system-prompt.test.js
git commit -m "feat: playground config, demo project, and system prompt"
```

---

## Task 10: Terminal UI

**Files:**
- Create: `pages/playground/index.html`
- Create: `pages/playground/style.css`
- Create: `pages/playground/js/ui.js`

This task has no unit tests — `ui.js` is DOM glue, verified by manual smoke testing in Task 11.

- [ ] **Step 1: Create the HTML shell**

Create `pages/playground/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>CCHarbour Playground</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div id="app">
    <header id="banner">
      <pre class="logo">  \  |  /
-- (CC) --
  /  |  \</pre>
      <div class="banner-text">
        <strong>CCHarbour Playground</strong>
        <span>A browser playground for the CCHarbour coding assistant.
          <a href="../">Documentation</a></span>
      </div>
      <button id="settings-toggle" type="button">Settings</button>
    </header>

    <section id="settings" class="hidden">
      <h2>Settings</h2>
      <label>DeepSeek API key
        <input id="key-deepseek" type="password" autocomplete="off"></label>
      <label>Tavily API key — optional, enables web_search
        <input id="key-tavily" type="password" autocomplete="off"></label>
      <label>GitHub token — optional, enables github_write
        <input id="key-github" type="password" autocomplete="off"></label>
      <label>Model
        <input id="model" type="text" autocomplete="off"></label>
      <p class="warn">Keys are stored in this browser's localStorage and are sent
        only to the official DeepSeek, Tavily and GitHub APIs. This is a
        client-side playground — do not use it on a shared or untrusted computer.</p>
      <button id="settings-save" type="button">Save</button>
    </section>

    <main id="scrollback"></main>

    <footer>
      <div class="status">
        <span id="usage">no usage yet</span>
        <button id="reset" type="button">Reset project</button>
      </div>
      <form id="input-form">
        <input id="input" type="text" autocomplete="off"
          placeholder="Type a request, then press Enter…">
        <button id="send" type="submit">Send</button>
      </form>
    </footer>
  </div>
  <script type="module" src="js/app.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create the stylesheet**

Create `pages/playground/style.css`:

```css
:root {
  --bg: #0d1117; --fg: #c9d1d9; --dim: #8b949e; --accent: #2dba9e;
  --panel: #161b22; --border: #30363d; --err: #f85149;
}
* { box-sizing: border-box; }
html, body { margin: 0; height: 100%; }
body {
  background: var(--bg); color: var(--fg);
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 14px;
}
#app { display: flex; flex-direction: column; height: 100vh; }

#banner {
  display: flex; align-items: center; gap: 16px;
  padding: 10px 16px; border-bottom: 1px solid var(--border); background: var(--panel);
}
#banner .logo { color: var(--accent); margin: 0; font-size: 11px; line-height: 1.1; }
.banner-text { display: flex; flex-direction: column; }
.banner-text span { color: var(--dim); font-size: 12px; }
.banner-text a { color: var(--accent); }
#banner button { margin-left: auto; }

#settings {
  display: flex; flex-direction: column; gap: 8px;
  padding: 16px; border-bottom: 1px solid var(--border); background: var(--panel);
}
#settings.hidden { display: none; }
#settings h2 { margin: 0 0 4px; font-size: 14px; }
#settings label { display: flex; flex-direction: column; gap: 4px; color: var(--dim); }
#settings input {
  background: var(--bg); color: var(--fg);
  border: 1px solid var(--border); border-radius: 4px; padding: 6px; font: inherit;
}
.warn { color: var(--err); font-size: 12px; margin: 4px 0; }

#scrollback { flex: 1; overflow-y: auto; padding: 16px; }
.turn { margin-bottom: 14px; white-space: pre-wrap; word-break: break-word; }
.turn.user { color: var(--accent); }
.turn.assistant { color: var(--fg); }
.turn.error { color: var(--err); }
.turn .label { color: var(--dim); user-select: none; }

.tool {
  border: 1px solid var(--border); border-radius: 4px;
  margin: 6px 0; padding: 6px 8px; background: var(--panel);
}
.tool summary { cursor: pointer; color: var(--accent); }
.tool pre { margin: 6px 0 0; white-space: pre-wrap; color: var(--dim); }

.confirm { border: 1px solid var(--err); border-radius: 4px; padding: 8px; margin: 6px 0; }
.confirm button { margin-right: 8px; }

footer { border-top: 1px solid var(--border); background: var(--panel); padding: 8px 16px; }
.status { display: flex; gap: 12px; align-items: center; color: var(--dim);
  font-size: 12px; margin-bottom: 6px; }
#input-form { display: flex; gap: 8px; }
#input {
  flex: 1; background: var(--bg); color: var(--fg);
  border: 1px solid var(--border); border-radius: 4px; padding: 8px; font: inherit;
}
button {
  background: var(--accent); color: #04231d; border: 0;
  border-radius: 4px; padding: 6px 12px; font: inherit; cursor: pointer;
}
button:disabled { opacity: 0.5; cursor: default; }
```

- [ ] **Step 3: Create the UI module**

Create `pages/playground/js/ui.js`:

```js
// Terminal-style REPL rendering and input. Owns all DOM interaction; holds no
// agent logic. createUI(handlers) wires DOM events to the supplied callbacks
// and returns render methods the app calls in response to agent events.

export function createUI(handlers) {
  const $ = (id) => document.getElementById(id);
  const scrollback = $("scrollback");
  const input = $("input");
  const sendBtn = $("send");

  let assistantEl = null;       // current streaming assistant turn
  const toolEls = new Map();    // tool call id -> details element

  function add(cls, text) {
    const el = document.createElement("div");
    el.className = "turn " + cls;
    el.textContent = text;
    scrollback.appendChild(el);
    scrollback.scrollTop = scrollback.scrollHeight;
    return el;
  }

  // --- input form ---
  $("input-form").addEventListener("submit", (e) => {
    e.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    handlers.onSubmit(text);
  });

  // --- settings panel ---
  $("settings-toggle").addEventListener("click", () => {
    $("settings").classList.toggle("hidden");
  });
  $("settings-save").addEventListener("click", () => {
    handlers.onSaveSettings({
      deepseekKey: $("key-deepseek").value.trim(),
      tavilyKey: $("key-tavily").value.trim(),
      githubToken: $("key-github").value.trim(),
      model: $("model").value.trim() || "deepseek-chat",
    });
    $("settings").classList.add("hidden");
  });
  $("reset").addEventListener("click", () => handlers.onReset());

  return {
    // Populate the settings inputs from a config object.
    fillSettings(cfg) {
      $("key-deepseek").value = cfg.deepseekKey || "";
      $("key-tavily").value = cfg.tavilyKey || "";
      $("key-github").value = cfg.githubToken || "";
      $("model").value = cfg.model || "deepseek-chat";
    },
    openSettings() { $("settings").classList.remove("hidden"); },

    addUserLine(text) { add("user", "› " + text); },
    addNotice(text) { add("assistant", text); },
    addError(text) { add("error", "✗ " + text); },

    // Begin a fresh streaming assistant turn.
    startAssistant() {
      assistantEl = add("assistant", "");
    },
    appendAssistant(text) {
      if (!assistantEl) this.startAssistant();
      assistantEl.textContent += text;
      scrollback.scrollTop = scrollback.scrollHeight;
    },
    endAssistant() { assistantEl = null; },

    // Render a tool call as a collapsible block; fill its result later.
    addToolCall(id, name, args) {
      const d = document.createElement("details");
      d.className = "tool";
      const s = document.createElement("summary");
      s.textContent = `tool: ${name} ${args || ""}`.trim();
      const pre = document.createElement("pre");
      pre.textContent = "running…";
      d.appendChild(s);
      d.appendChild(pre);
      scrollback.appendChild(d);
      scrollback.scrollTop = scrollback.scrollHeight;
      toolEls.set(id, pre);
    },
    setToolResult(id, content) {
      const pre = toolEls.get(id);
      if (pre) pre.textContent = content;
    },

    // Inline confirmation for github_write. Returns a Promise<boolean>.
    confirmWrite(name, args) {
      return new Promise((resolve) => {
        const box = document.createElement("div");
        box.className = "confirm";
        const msg = document.createElement("div");
        msg.textContent = `Allow ${name}? ${JSON.stringify(args)}`;
        const yes = document.createElement("button");
        yes.textContent = "Allow";
        const no = document.createElement("button");
        no.textContent = "Deny";
        const done = (v) => { yes.disabled = no.disabled = true; resolve(v); };
        yes.addEventListener("click", () => done(true));
        no.addEventListener("click", () => done(false));
        box.append(msg, yes, no);
        scrollback.appendChild(box);
        scrollback.scrollTop = scrollback.scrollHeight;
      });
    },

    setUsage(usage) {
      const t = usage && usage.total_tokens;
      $("usage").textContent = t ? `tokens used: ${t}` : "no usage yet";
    },

    setBusy(busy) {
      input.disabled = busy;
      sendBtn.disabled = busy;
      if (!busy) input.focus();
    },
  };
}
```

- [ ] **Step 4: Verify the files are well-formed**

Run: `node --check pages/playground/js/ui.js`
Expected: no output, exit 0 (the file is syntactically valid JavaScript).

- [ ] **Step 5: Commit**

```bash
git add pages/playground/index.html pages/playground/style.css pages/playground/js/ui.js
git commit -m "feat: playground terminal UI"
```

---

## Task 11: Application wiring

**Files:**
- Create: `pages/playground/js/app.js`

This task has no unit tests — `app.js` is the DOM entry point, verified by the manual smoke test in Step 3.

- [ ] **Step 1: Write the application entry point**

Create `pages/playground/js/app.js`:

```js
// Entry point: loads config, seeds the vfs, builds the registry, and wires the
// UI to the agent loop.

import { loadConfig, saveConfig } from "./config.js";
import { createVfs } from "./vfs.js";
import { DEMO_PROJECT } from "./demo-project.js";
import { systemPrompt } from "./system-prompt.js";
import { buildRegistry } from "./tools/registry.js";
import { runAgent } from "./agent.js";
import { createUI } from "./ui.js";

let config = loadConfig();
let vfs = createVfs(DEMO_PROJECT);
let conversation = [{ role: "system", content: systemPrompt(vfs) }];
let running = false;

const ui = createUI({
  onSubmit: handleSubmit,
  onSaveSettings: handleSaveSettings,
  onReset: handleReset,
});

ui.fillSettings(config);
ui.addNotice("Welcome to the CCHarbour playground. " +
  (config.deepseekKey ? "Type a request to begin."
    : "Open Settings and add your DeepSeek API key to begin."));
if (!config.deepseekKey) ui.openSettings();

function buildRegistryForRun() {
  return buildRegistry({
    vfs,
    tavilyKey: config.tavilyKey,
    githubToken: config.githubToken,
    confirmWrite: (name, args) => ui.confirmWrite(name, args),
    fetchImpl: (...a) => fetch(...a),
  });
}

async function handleSubmit(text) {
  if (running) return;
  if (!config.deepseekKey) {
    ui.addError("No DeepSeek API key. Open Settings to add one.");
    ui.openSettings();
    return;
  }
  ui.addUserLine(text);
  conversation.push({ role: "user", content: text });

  const { schemas, executor } = buildRegistryForRun();
  running = true;
  ui.setBusy(true);

  const result = await runAgent(
    {
      messages: conversation,
      model: config.model,
      tools: schemas,
      toolExecutor: executor,
      deepseekOpts: { apiKey: config.deepseekKey },
    },
    onEvent,
  );

  ui.endAssistant();
  if (result.success) {
    conversation = result.messages;
    ui.setUsage(result.usage);
    if (result.stopReason === "max_iterations") {
      ui.addNotice("[stopped: reached the iteration limit]");
    }
  } else {
    ui.addError(result.message || "the request failed");
  }
  running = false;
  ui.setBusy(false);
}

function onEvent(ev) {
  if (ev.type === "iteration_start") {
    ui.endAssistant();
  } else if (ev.type === "text_delta") {
    ui.appendAssistant(ev.text);
  } else if (ev.type === "tool_call") {
    ui.endAssistant();
    ui.addToolCall(ev.id, ev.name, ev.arguments);
  } else if (ev.type === "tool_result") {
    ui.setToolResult(ev.id, ev.content);
  } else if (ev.type === "error") {
    ui.addError(ev.message || ev.errorType);
  }
}

function handleSaveSettings(next) {
  config = next;
  saveConfig(config);
  ui.addNotice("Settings saved.");
}

function handleReset() {
  vfs = createVfs(DEMO_PROJECT);
  conversation = [{ role: "system", content: systemPrompt(vfs) }];
  ui.addNotice("Project and conversation reset.");
}
```

- [ ] **Step 2: Verify the file is well-formed**

Run: `node --check pages/playground/js/app.js`
Expected: no output, exit 0.

- [ ] **Step 3: Manual smoke test**

Serve the playground locally and exercise it against the real DeepSeek API:

```bash
python -m http.server 8000 --directory pages/playground
```

Open `http://localhost:8000/`, then verify:
- The settings panel opens automatically when no key is stored; saving a real DeepSeek key persists it across a reload.
- A plain request (e.g. "say hello") streams an assistant reply.
- A request that needs a tool (e.g. "read README.md") shows a tool-call block with the file contents and then a final answer.
- "Reset project" clears the conversation.
- With no Tavily key, asking the model to search the web yields the `TAVILY_API_KEY not set` error in the tool block.

Record the smoke-test outcome in the task report. If any step fails, fix it before committing.

- [ ] **Step 4: Run the full test suite**

Run: `node --test playground-tests/`
Expected: PASS — every test from Tasks 1-9 still passes (exit 0).

- [ ] **Step 5: Commit**

```bash
git add pages/playground/js/app.js
git commit -m "feat: playground application wiring"
```

---

## Task 12: Hosting and documentation

**Files:**
- Modify: `mkdocs.yml`
- Modify: `pages/index.md`
- Modify: `README.md`

- [ ] **Step 1: Add the playground to the MkDocs navigation**

Read `mkdocs.yml`. In its `nav:` list, add a Playground entry after `Home`:

```yaml
nav:
  - Home: index.md
  - Playground: playground/index.html
  - Getting started: getting-started.md
  - Commands: commands.md
  - Configuration: configuration.md
  - Roadmap: roadmap.md
```

`pages/playground/` is inside `docs_dir` (`pages/`), so `mkdocs build` copies it verbatim into `site/playground/`; the nav entry links straight to the static page.

- [ ] **Step 2: Link the playground from the docs home and the README**

Read `pages/index.md` and add a short paragraph (matching the page's existing tone) introducing the playground and linking to `playground/index.html` — note that it runs entirely in the browser and needs the visitor's own DeepSeek API key.

Read `README.md` and add a line near the top, beside the existing documentation link, pointing to the playground URL
`https://fivetechsoft.github.io/CCHarbour/playground/`.

- [ ] **Step 3: Verify the MkDocs build**

If `mkdocs` is available, run `mkdocs build --strict` from the repo root and confirm it completes with no warnings (a broken nav target or link fails `--strict`). If `mkdocs` is not installed, skip this step and note it in the task report.

- [ ] **Step 4: Commit**

```bash
git add mkdocs.yml pages/index.md README.md
git commit -m "docs: add the web playground to the site and README"
```

---

## Self-review notes

- **Spec coverage:** sse.js (T1), vfs.js (T2), deepseek.js (T3), agent.js (T4), file tools (T5), web tools (T6), github tools (T7), registry + permission gate (T8), config/demo/system-prompt (T9), UI + index.html + style.css (T10), app.js wiring (T11), hosting + docs + CI workflow (T1 creates `playground.yml`, T12 wires nav/docs). Every spec section maps to a task.
- **Shell omitted:** no `shell` tool is defined or registered anywhere; the registry test asserts its absence.
- **Injectable fetch:** `deepseek.js`, `web.js`, `github.js`, and `buildRegistry` all accept a `fetchImpl`/transport, so every test runs with no network.
- **Type consistency:** `chatCompletion` returns `{ success, content, toolCalls, finishReason, usage, errorType, message }`; `runAgent` consumes `chat.success`/`chat.toolCalls`/`chat.content`/`chat.usage` and returns `{ success, messages, content, stopReason, iterations, usage, errorType, message }`; tools are `{ name, description, parameters, handler }` throughout; `buildRegistry` returns `{ schemas, executor }`; `createUI` returns the render methods `app.js` calls. Names are consistent across tasks.
- **CI:** `playground.yml` runs `node --test playground-tests/` on changes under `pages/playground/**` or `playground-tests/**`.
- **Browser/Node globals:** `fetch`, `TextDecoder`, `TextEncoder`, `atob` are all available both in modern browsers and in Node 18+; `config.js`/`ui.js`/`app.js` use `localStorage`/DOM only inside functions, and are never imported by the Node test suite.

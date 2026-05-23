import { test } from "node:test";
import assert from "node:assert/strict";
import { buildRegistry } from "../pages/playground/js/tools/registry.js";
import { createVfs } from "../pages/playground/js/vfs.js";
import { fakeJsonResponse } from "./helpers.js";

function reg(extra = {}) {
  return buildRegistry({
    vfs: createVfs({ "a.txt": "body" }),
    githubToken: "tok",
    fetchImpl: async () => fakeJsonResponse({ html_url: "https://x/1" }, { status: 201 }),
    confirmWrite: async () => true,
    ...extra,
  });
}

test("registry: schemas cover the full browser toolset, no shell", () => {
  const { schemas } = reg({
    getModel: () => "m", getApiKey: () => "k", getBaseUrl: () => "u",
  });
  const names = schemas.map((s) => s.function.name).sort();
  assert.deepEqual(names, [
    "ask_user", "dispatch_agent", "edit", "github_read", "github_write",
    "glob", "grep", "memory", "propose_agents", "read", "todo_write",
    "web_fetch", "web_search", "write",
  ]);
});

test("registry: dispatch_agent is skipped when no API key callbacks are provided", () => {
  const { schemas } = reg();
  const names = schemas.map((s) => s.function.name).sort();
  assert.ok(!names.includes("dispatch_agent"),
    "dispatch_agent must not appear without getModel/getApiKey");
  assert.ok(names.includes("propose_agents"),
    "propose_agents still ships (it does not need the model)");
});

test("registry: executor dispatches tool calls", async () => {
  const { executor } = reg();
  const r = await executor("read", JSON.stringify({ path: "a.txt" }));
  assert.ok(r.includes("body"));
});

test("registry: executor unknown tool", async () => {
  const { executor } = reg();
  assert.equal(await executor("nope", "{}"), "Error: unknown tool 'nope'");
});

test("registry: executor invalid JSON", async () => {
  const { executor } = reg();
  assert.equal(await executor("read", "bad"), "Error: invalid arguments JSON");
});

test("registry: executor missing required arg", async () => {
  const { executor } = reg();
  assert.equal(await executor("read", "{}"), "Error: missing required argument 'path'");
});

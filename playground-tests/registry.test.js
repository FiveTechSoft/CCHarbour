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

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

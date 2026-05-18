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

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

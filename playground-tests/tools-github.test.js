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

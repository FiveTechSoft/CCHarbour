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

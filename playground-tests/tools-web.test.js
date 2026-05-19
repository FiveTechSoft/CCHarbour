import { test } from "node:test";
import assert from "node:assert/strict";
import { webTools } from "../pages/playground/js/tools/web.js";
import { fakeJsonResponse } from "./helpers.js";

function map(fetchImpl) {
  return new Map(webTools(fetchImpl).map((t) => [t.name, t]));
}

test("web_search: formats DuckDuckGo results (AbstractText + Results)", async () => {
  const fetchImpl = async () => fakeJsonResponse({
    AbstractText: "Instant answer text",
    AbstractURL: "https://example.com/answer",
    AbstractSource: "Wikipedia",
    Results: [
      { Text: "Result title", FirstURL: "https://example.com/result" },
    ],
    RelatedTopics: [],
  });
  const r = await map(fetchImpl).get("web_search").handler({ query: "test" });
  assert.ok(r.includes(">> Instant answer text"));
  assert.ok(r.includes("https://example.com/answer"));
  assert.ok(r.includes("Result title"));
  assert.ok(r.includes("https://example.com/result"));
});

test("web_search: non-2xx", async () => {
  const fetchImpl = async () => fakeJsonResponse({}, { status: 401 });
  const r = await map(fetchImpl).get("web_search").handler({ query: "x" });
  assert.equal(r, "Error: web_search HTTP 401");
});

test("web_search: no results", async () => {
  const fetchImpl = async () => fakeJsonResponse({ AbstractText: "", Results: [], RelatedTopics: [] });
  const r = await map(fetchImpl).get("web_search").handler({ query: "zzz" });
  assert.ok(r.includes("No results for"));
});

test("web_search: max_results clamping", async () => {
  const fetchImpl = async () => fakeJsonResponse({
    AbstractText: "",
    Results: [
      { Text: "R1", FirstURL: "U1" },
      { Text: "R2", FirstURL: "U2" },
      { Text: "R3", FirstURL: "U3" },
    ],
    RelatedTopics: [],
  });
  const r = await map(fetchImpl).get("web_search").handler({ query: "x", max_results: 2 });
  assert.ok(r.includes("R1") && r.includes("R2"));
  assert.ok(!r.includes("R3"));
});

test("web_fetch: returns body", async () => {
  const fetchImpl = async () => fakeJsonResponse("page text", { status: 200 });
  const r = await map(fetchImpl).get("web_fetch").handler({ url: "https://x" });
  assert.equal(r, "page text");
});

test("web_fetch: blocked fetch becomes an error", async () => {
  const fetchImpl = async () => { throw new Error("blocked by CORS"); };
  const r = await map(fetchImpl).get("web_fetch").handler({ url: "https://x" });
  assert.match(r, /^Error: web_fetch failed/);
});

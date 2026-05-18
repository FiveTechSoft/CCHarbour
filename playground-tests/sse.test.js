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

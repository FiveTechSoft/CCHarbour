import { test } from "node:test";
import assert from "node:assert/strict";
import { runAgent } from "../pages/playground/js/agent.js";
import { fakeStreamResponse } from "./helpers.js";

function dataLine(obj) { return "data: " + JSON.stringify(obj) + "\n\n"; }
const DONE = "data: [DONE]\n\n";

function textTurn(text) {
  return [dataLine({ choices: [{ delta: { content: text }, finish_reason: "stop" }] }), DONE];
}
function toolTurn(name, args) {
  return [
    dataLine({ choices: [{ delta: { tool_calls: [
      { index: 0, id: "c1", function: { name, arguments: args } } ] }, finish_reason: "tool_calls" }] }),
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

test("agent: reasoning_content rides the tool-call message", async () => {
  const reasoningToolTurn = [
    dataLine({ choices: [{ delta: { reasoning_content: "think" } }] }),
    dataLine({ choices: [{ delta: { tool_calls: [
      { index: 0, id: "c1", function: { name: "noop", arguments: "{}" } } ] }, finish_reason: "tool_calls" }] }),
    DONE,
  ];
  const res = await runAgent({
    messages: [{ role: "user", content: "go" }],
    model: "m",
    tools: [{ type: "function", function: { name: "noop" } }],
    toolExecutor: async () => "ok",
    deepseekOpts: { apiKey: "k", fetchImpl: scriptedFetch([reasoningToolTurn, textTurn("done")]) },
  });
  const asst = res.messages.find((m) => m.role === "assistant" && m.tool_calls);
  assert.ok(asst, "an assistant message with tool_calls exists");
  assert.equal(asst.reasoning_content, "think");
});

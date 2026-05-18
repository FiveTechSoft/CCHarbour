import { test } from "node:test";
import assert from "node:assert/strict";
import { chatCompletion } from "../pages/playground/js/deepseek.js";
import { fakeStreamResponse, fakeJsonResponse } from "./helpers.js";

function dataLine(obj) { return "data: " + JSON.stringify(obj) + "\n\n"; }

test("deepseek: streams text and reports success", async () => {
  const chunks = [
    dataLine({ choices: [{ delta: { content: "Hi" } }] }),
    dataLine({ choices: [{ delta: { content: " there" }, finish_reason: "stop" }] }),
    "data: [DONE]\n\n",
  ];
  const fetchImpl = async () => fakeStreamResponse(chunks);
  const res = await chatCompletion(
    { apiKey: "k", model: "deepseek-chat", messages: [{ role: "user", content: "hi" }], fetchImpl });
  assert.equal(res.success, true);
  assert.equal(res.content, "Hi there");
  assert.equal(res.finishReason, "stop");
});

test("deepseek: accumulates a tool call", async () => {
  const chunks = [
    dataLine({ choices: [{ delta: { tool_calls: [
      { index: 0, id: "c1", function: { name: "read", arguments: '{"path":' } } ] } }] }),
    dataLine({ choices: [{ delta: { tool_calls: [
      { index: 0, function: { arguments: '"a.txt"}' } } ] }, finish_reason: "tool_calls" }] }),
    "data: [DONE]\n\n",
  ];
  const res = await chatCompletion(
    { apiKey: "k", model: "m", messages: [{ role: "user", content: "x" }],
      fetchImpl: async () => fakeStreamResponse(chunks) });
  assert.equal(res.toolCalls.length, 1);
  assert.equal(res.toolCalls[0].name, "read");
  assert.equal(res.toolCalls[0].arguments, '{"path":"a.txt"}');
});

test("deepseek: non-2xx becomes an api error", async () => {
  const res = await chatCompletion(
    { apiKey: "bad", model: "m", messages: [{ role: "user", content: "x" }],
      fetchImpl: async () => fakeJsonResponse({ error: { message: "Unauthorized" } }, { status: 401 }) });
  assert.equal(res.success, false);
  assert.equal(res.errorType, "api");
  assert.equal(res.message, "Unauthorized");
});

test("deepseek: missing key is a config error", async () => {
  const res = await chatCompletion({ model: "m", messages: [{ role: "user", content: "x" }] });
  assert.equal(res.errorType, "config");
});

test("deepseek: captures usage from the final chunk", async () => {
  const chunks = [
    dataLine({ choices: [{ delta: { content: "ok" }, finish_reason: "stop" }] }),
    dataLine({ choices: [], usage: { total_tokens: 42 } }),
    "data: [DONE]\n\n",
  ];
  const res = await chatCompletion(
    { apiKey: "k", model: "m", messages: [{ role: "user", content: "x" }],
      fetchImpl: async () => fakeStreamResponse(chunks) });
  assert.equal(res.success, true);
  assert.equal(res.usage.total_tokens, 42);
});

test("deepseek: no opts is a config error, not a throw", async () => {
  const res = await chatCompletion();
  assert.equal(res.success, false);
  assert.equal(res.errorType, "config");
});

test("deepseek: captures reasoning_content", async () => {
  const chunks = [
    dataLine({ choices: [{ delta: { reasoning_content: "think " } }] }),
    dataLine({ choices: [{ delta: { reasoning_content: "more" } }] }),
    dataLine({ choices: [{ delta: { content: "answer" }, finish_reason: "stop" }] }),
    "data: [DONE]\n\n",
  ];
  const res = await chatCompletion(
    { apiKey: "k", model: "m", messages: [{ role: "user", content: "x" }],
      fetchImpl: async () => fakeStreamResponse(chunks) });
  assert.equal(res.reasoningContent, "think more");
  assert.equal(res.content, "answer");
});

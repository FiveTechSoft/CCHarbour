// The multi-turn agent loop. Mirrors DS_AgentRun in the native src/dsagent.prg.

import { chatCompletion } from "./deepseek.js";

export async function runAgent(opts, onEvent) {
  const {
    messages,
    model,
    tools,
    toolExecutor,
    maxIterations = 25,
    deepseekOpts = {},
  } = opts;

  const result = {
    success: false, messages: [], content: "", stopReason: null,
    iterations: 0, usage: {}, errorType: null, message: null,
  };

  if (!Array.isArray(messages) || messages.length === 0) {
    result.errorType = "config";
    result.message = "messages must be a non-empty array";
    result.stopReason = "error";
    return result;
  }

  const msgs = JSON.parse(JSON.stringify(messages));
  const usage = {};
  let iter = 0;

  while (iter < maxIterations) {
    iter++;
    emit(onEvent, { type: "iteration_start", n: iter });

    const chat = await chatCompletion(
      { ...deepseekOpts, model, messages: msgs, tools }, onEvent);

    if (!chat.success) {
      result.messages = msgs;
      result.iterations = iter;
      result.usage = usage;
      result.errorType = chat.errorType;
      result.message = chat.message;
      result.stopReason = "error";
      return result;
    }

    addUsage(usage, chat.usage);
    msgs.push(assistantMessage(chat));

    if (!chat.toolCalls || chat.toolCalls.length === 0) {
      result.stopReason = "stop";
      break;
    }

    if (typeof toolExecutor !== "function") {
      result.messages = msgs;
      result.iterations = iter;
      result.usage = usage;
      result.errorType = "config";
      result.message = "model requested a tool but no toolExecutor was provided";
      result.stopReason = "error";
      return result;
    }

    for (const tc of chat.toolCalls) {
      emit(onEvent, { type: "tool_call", id: tc.id, name: tc.name, arguments: tc.arguments });
      const res = await toolExecutor(tc.name, tc.arguments);
      emit(onEvent, { type: "tool_result", id: tc.id, content: res });
      msgs.push({ role: "tool", tool_call_id: tc.id, content: res });
    }
  }

  if (result.stopReason == null) result.stopReason = "max_iterations";

  result.success = true;
  result.messages = msgs;
  result.iterations = iter;
  result.usage = usage;
  result.content = lastAssistantText(msgs);
  return result;
}

function assistantMessage(chat) {
  const m = { role: "assistant", content: chat.content || "" };
  if (chat.toolCalls && chat.toolCalls.length) {
    m.tool_calls = chat.toolCalls.map((tc) => ({
      id: tc.id, type: "function",
      function: { name: tc.name, arguments: tc.arguments },
    }));
  }
  return m;
}

function lastAssistantText(msgs) {
  for (let i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i].role === "assistant") return msgs[i].content || "";
  }
  return "";
}

function addUsage(usage, u) {
  if (!u || typeof u !== "object") return;
  for (const k of Object.keys(u)) {
    if (typeof u[k] === "number") usage[k] = (usage[k] || 0) + u[k];
  }
}

function emit(cb, ev) { if (cb) cb(ev); }

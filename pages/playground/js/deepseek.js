// One streaming chat completion against the DeepSeek API.
// Mirrors DS_ChatCompletion in the native src/dsapi.prg.

import { createSSEParser } from "./sse.js";

export async function chatCompletion(opts, onEvent) {
  const {
    apiKey,
    baseUrl = "https://api.deepseek.com",
    model,
    messages,
    tools,
    temperature,
    maxTokens,
    fetchImpl = fetch,
  } = opts;

  const result = {
    success: false, content: "", toolCalls: [], finishReason: null,
    usage: null, errorType: null, message: null,
  };

  if (!apiKey) { result.errorType = "config"; result.message = "No DeepSeek API key"; return result; }
  if (!model) { result.errorType = "config"; result.message = "No model id"; return result; }

  const body = { model, messages, stream: true, stream_options: { include_usage: true } };
  if (tools) body.tools = tools;
  if (temperature != null) body.temperature = temperature;
  if (maxTokens != null) body.max_tokens = maxTokens;

  let resp;
  try {
    resp = await fetchImpl(baseUrl + "/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
        "Authorization": "Bearer " + apiKey,
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    result.errorType = "network";
    result.message = String((e && e.message) || e);
    emit(onEvent, { type: "error", errorType: "network", message: result.message });
    return result;
  }

  if (!resp.ok) {
    result.errorType = "api";
    result.message = apiErrorMessage(await safeText(resp), resp.status);
    emit(onEvent, { type: "error", errorType: "api", message: result.message });
    return result;
  }

  const parser = createSSEParser();
  const state = { content: "", tools: [], finish: null, usage: null };
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    for (const ev of parser.feed(decoder.decode(value, { stream: true }))) {
      foldEvent(ev, state);
      emit(onEvent, ev);
    }
  }

  result.success = true;
  result.content = state.content;
  result.toolCalls = state.tools.map((t) => ({ id: t.id, name: t.name, arguments: t.arguments }));
  result.finishReason = state.finish;
  result.usage = state.usage;
  return result;
}

function foldEvent(ev, state) {
  if (ev.type === "text_delta") state.content += ev.text;
  else if (ev.type === "tool_call_delta") accTool(state.tools, ev);
  else if (ev.type === "finish") state.finish = ev.finish_reason;
  else if (ev.type === "usage") state.usage = ev.usage;
}

function accTool(tools, ev) {
  let t = tools.find((x) => x.index === ev.index);
  if (!t) { t = { index: ev.index, id: "", name: "", arguments: "" }; tools.push(t); }
  if (ev.id) t.id = ev.id;
  if (ev.name) t.name = ev.name;
  if (ev.arguments) t.arguments += ev.arguments;
}

function apiErrorMessage(text, status) {
  try {
    const j = JSON.parse(text);
    if (j && j.error && j.error.message) return j.error.message;
  } catch { /* fall through */ }
  return "HTTP " + status;
}

async function safeText(resp) {
  try { return await resp.text(); } catch { return ""; }
}

function emit(cb, ev) { if (cb) cb(ev); }

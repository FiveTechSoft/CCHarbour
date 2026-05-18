// Incremental Server-Sent-Events parser for the DeepSeek streaming API.
// createSSEParser() returns an object whose feed(chunk) takes a raw text
// chunk and returns an array of parsed events. Partial lines are buffered
// across calls. Pure — no I/O.

export function createSSEParser() {
  let buffer = "";
  return {
    feed(chunk) {
      buffer += chunk;
      const events = [];
      let nl;
      while ((nl = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, nl).replace(/\r$/, "");
        buffer = buffer.slice(nl + 1);
        if (!line.startsWith("data:")) continue;
        const data = line.slice(5).trim();
        if (data === "[DONE]") { events.push({ type: "done" }); continue; }
        let json;
        try { json = JSON.parse(data); } catch { continue; }
        for (const ev of eventsFromChunk(json)) events.push(ev);
      }
      return events;
    },
  };
}

function eventsFromChunk(json) {
  const out = [];
  if (json.usage) out.push({ type: "usage", usage: json.usage });
  const choice = json.choices && json.choices[0];
  if (!choice) return out;
  const delta = choice.delta || {};
  if (typeof delta.content === "string" && delta.content.length) {
    out.push({ type: "text_delta", text: delta.content });
  }
  if (Array.isArray(delta.tool_calls)) {
    for (const tc of delta.tool_calls) {
      out.push({
        type: "tool_call_delta",
        index: tc.index,
        id: tc.id ?? null,
        name: (tc.function && tc.function.name) ?? null,
        arguments: (tc.function && tc.function.arguments) ?? null,
      });
    }
  }
  if (choice.finish_reason) {
    out.push({ type: "finish", finish_reason: choice.finish_reason });
  }
  return out;
}

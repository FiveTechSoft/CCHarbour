// Fake HTTP responses for headless tests — no network.

// A streaming Response: getReader() yields the chunks, decoded by the caller.
export function fakeStreamResponse(chunks, { status = 200 } = {}) {
  let i = 0;
  const enc = new TextEncoder();
  return {
    ok: status >= 200 && status < 300,
    status,
    body: {
      getReader() {
        return {
          read() {
            if (i < chunks.length) {
              return Promise.resolve({ value: enc.encode(chunks[i++]), done: false });
            }
            return Promise.resolve({ value: undefined, done: true });
          },
        };
      },
    },
    async text() { return chunks.join(""); },
    async json() { return JSON.parse(chunks.join("")); },
  };
}

// A non-streaming Response carrying a JSON object or a raw string.
export function fakeJsonResponse(obj, { status = 200 } = {}) {
  const text = typeof obj === "string" ? obj : JSON.stringify(obj);
  return {
    ok: status >= 200 && status < 300,
    status,
    async text() { return text; },
    async json() { return JSON.parse(text); },
  };
}

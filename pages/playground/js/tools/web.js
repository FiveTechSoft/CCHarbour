// Web tools: web_search (Tavily) and web_fetch. Mirrors src/dstools_web.prg.

function cap(s) {
  return s.length > 30000 ? s.slice(0, 30000) + "\n[output truncated]\n" : s;
}

export function webTools(tavilyKey, fetchImpl = fetch) {
  return [
    {
      name: "web_search",
      description: "Search the web via the Tavily API. Returns ranked title/url/snippet results.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "The search query" },
          max_results: { type: "integer", description: "Maximum number of results (default 5)" },
        },
        required: ["query"],
      },
      async handler(args) {
        if (!tavilyKey) return "Error: TAVILY_API_KEY not set";
        let resp;
        try {
          resp = await fetchImpl("https://api.tavily.com/search", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              api_key: tavilyKey,
              query: String(args.query),
              max_results: typeof args.max_results === "number" ? args.max_results : 5,
              search_depth: "basic",
            }),
          });
        } catch (e) {
          return "Error: web_search failed: " + ((e && e.message) || e);
        }
        if (resp.status < 200 || resp.status >= 300) {
          return "Error: web_search HTTP " + resp.status;
        }
        let body;
        try { body = await resp.json(); } catch { return "Error: web_search: unexpected response"; }
        if (!body || !Array.isArray(body.results)) {
          return "Error: web_search: unexpected response";
        }
        const out = body.results
          .map((r) => `${r.title}\n${r.url}\n${r.content}`)
          .join("\n\n");
        return out ? cap(out) : "No results for " + args.query;
      },
    },
    {
      name: "web_fetch",
      description: "Fetch the raw content of a URL (text or HTML, not converted).",
      parameters: {
        type: "object",
        properties: { url: { type: "string", description: "The URL to fetch" } },
        required: ["url"],
      },
      async handler(args) {
        let resp;
        try {
          resp = await fetchImpl(String(args.url));
        } catch (e) {
          return "Error: web_fetch failed (the site may block browser access): " +
            ((e && e.message) || e);
        }
        if (resp.status < 200 || resp.status >= 300) {
          return "Error: web_fetch HTTP " + resp.status;
        }
        let text;
        try { text = await resp.text(); }
        catch (e) { return "Error: web_fetch failed: " + ((e && e.message) || e); }
        return cap(text);
      },
    },
  ];
}

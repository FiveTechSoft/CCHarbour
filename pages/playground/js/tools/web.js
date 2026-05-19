// Web tools: web_search (DuckDuckGo) and web_fetch. Mirrors src/dstools_web.prg.

function cap(s) {
  return s.length > 30000 ? s.slice(0, 30000) + "\n[output truncated]\n" : s;
}

// Percent-encodes a string for safe URL query parameters.
function urlEncode(s) {
  return encodeURIComponent(String(s)).replace(/%20/g, "+");
}

export function webTools(_unused, fetchImpl = fetch) {
  return [
    {
      name: "web_search",
      description: "Search the web via the DuckDuckGo API. " +
        "No API key required. Returns ranked title/url/snippet results.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "The search query" },
          max_results: { type: "integer", description: "Maximum number of results (default 8)" },
        },
        required: ["query"],
      },
      async handler(args) {
        const query = String(args.query);
        const maxResults = typeof args.max_results === "number" ? Math.min(Math.max(1, args.max_results), 20) : 8;
        const url = "https://api.duckduckgo.com/?q=" + urlEncode(query) +
                    "&format=json&no_html=1&skip_disambig=1";
        let resp;
        try {
          resp = await fetchImpl(url);
        } catch (e) {
          return "Error: web_search failed: " + ((e && e.message) || e);
        }
        if (resp.status < 200 || resp.status >= 300) {
          return "Error: web_search HTTP " + resp.status;
        }
        let body;
        try { body = await resp.json(); } catch { return "Error: web_search: unexpected response"; }
        if (!body || typeof body !== "object") {
          return "Error: web_search: unexpected response format";
        }

        const out = [];
        let shown = 0;

        // 1. Instant Answer (AbstractText)
        if (body.AbstractText) {
          out.push(">> " + body.AbstractText);
          if (body.AbstractURL) out.push("   " + body.AbstractURL);
          if (body.AbstractSource) out.push("   Source: " + body.AbstractSource);
          out.push("");
          shown++;
        }

        // 2. Results array
        if (Array.isArray(body.Results)) {
          for (const r of body.Results) {
            if (shown >= maxResults) break;
            out.push(r.Text || "");
            out.push(r.FirstURL || "");
            out.push("");
            shown++;
          }
        }

        // 3. RelatedTopics
        if (shown < maxResults && Array.isArray(body.RelatedTopics)) {
          for (const t of body.RelatedTopics) {
            if (shown >= maxResults) break;
            if (t && typeof t === "object") {
              if (Array.isArray(t.Topics)) {
                for (const sub of t.Topics) {
                  if (shown >= maxResults) break;
                  out.push(sub.Text || "");
                  out.push(sub.FirstURL || "");
                  out.push("");
                  shown++;
                }
              } else if (t.Text) {
                out.push(t.Text);
                out.push(t.FirstURL || "");
                out.push("");
                shown++;
              }
            }
          }
        }

        const result = out.join("\n");
        return result ? cap(result) : "No results for " + query;
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

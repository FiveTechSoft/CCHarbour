// GitHub tools: github_read and github_write. Mirrors src/dstools_github.prg.

const GH = "https://api.github.com";

function cap(s) {
  return s.length > 30000 ? s.slice(0, 30000) + "\n[output truncated]\n" : s;
}

function ghHeaders(token) {
  const h = {
    "Accept": "application/vnd.github+json",
    "Content-Type": "application/json",
  };
  if (token) h["Authorization"] = "Bearer " + token;
  return h;
}

function apiMessage(body) {
  try { const j = JSON.parse(body); if (j && j.message) return j.message; } catch { /* ignore */ }
  return "";
}

async function safeText(resp) {
  try { return await resp.text(); } catch { return ""; }
}

function encodePath(p) {
  return String(p).split("/").map(encodeURIComponent).join("/");
}

function formatRead(op, body) {
  if (op === "file") {
    try {
      const j = JSON.parse(body);
      if (j && j.content) return cap(atob(j.content.replace(/\n/g, "")));
    } catch { /* fall through */ }
    return cap(body);
  }
  if (op === "list") {
    try {
      const j = JSON.parse(body);
      if (Array.isArray(j)) {
        return cap(j.filter((e) => e && e.name)
          .map((e) => `${e.type || ""}  ${e.name}`).join("\n"));
      }
    } catch { /* fall through */ }
    return cap(body);
  }
  return cap(body);
}

export function githubTools(token, fetchImpl = fetch) {
  return [
    {
      name: "github_read",
      description: "Read from GitHub: repo info, file content, directory listing, issues, pull requests, code search.",
      parameters: {
        type: "object",
        properties: {
          operation: { type: "string", description: "One of: repo, file, list, issues, issue, prs, pr, search" },
          repo: { type: "string", description: "Repository as owner/name (every operation except search)" },
          path: { type: "string", description: "File or directory path (file, list)" },
          number: { type: "integer", description: "Issue or PR number (issue, pr)" },
          query: { type: "string", description: "Code search query (search)" },
        },
        required: ["operation"],
      },
      async handler(args) {
        const op = String(args.operation || "").toLowerCase();
        let url;
        if (op === "search") {
          if (!args.query) return "Error: github_read 'search' requires 'query'";
          url = `${GH}/search/code?q=${encodeURIComponent(args.query)}`;
        } else {
          if (!args.repo) return `Error: github_read '${op}' requires 'repo'`;
          const repo = String(args.repo);
          if (op === "repo") {
            url = `${GH}/repos/${repo}`;
          } else if (op === "file" || op === "list") {
            if (!args.path) return `Error: github_read '${op}' requires 'path'`;
            url = `${GH}/repos/${repo}/contents/${encodePath(args.path)}`;
          } else if (op === "issues") {
            url = `${GH}/repos/${repo}/issues`;
          } else if (op === "issue") {
            if (typeof args.number !== "number") return "Error: github_read 'issue' requires a numeric 'number'";
            url = `${GH}/repos/${repo}/issues/${args.number}`;
          } else if (op === "prs") {
            url = `${GH}/repos/${repo}/pulls`;
          } else if (op === "pr") {
            if (typeof args.number !== "number") return "Error: github_read 'pr' requires a numeric 'number'";
            url = `${GH}/repos/${repo}/pulls/${args.number}`;
          } else {
            return `Error: github_read: unknown operation '${op}'`;
          }
        }
        let resp;
        try { resp = await fetchImpl(url, { headers: ghHeaders(token) }); }
        catch (e) { return "Error: github_read failed: " + ((e && e.message) || e); }
        const body = await safeText(resp);
        if (resp.status < 200 || resp.status >= 300) {
          return `Error: github_read HTTP ${resp.status}: ${apiMessage(body)}`;
        }
        return formatRead(op, body);
      },
    },
    {
      name: "github_write",
      description: "Write to GitHub: create an issue, comment on an issue, or open a pull request. Requires a GitHub token.",
      parameters: {
        type: "object",
        properties: {
          operation: { type: "string", description: "One of: create_issue, comment, create_pr" },
          repo: { type: "string", description: "Repository as owner/name" },
          number: { type: "integer", description: "Issue number (comment)" },
          title: { type: "string", description: "Title (create_issue, create_pr)" },
          body: { type: "string", description: "Body text" },
          head: { type: "string", description: "Source branch (create_pr)" },
          base: { type: "string", description: "Target branch (create_pr)" },
        },
        required: ["operation", "repo"],
      },
      async handler(args) {
        if (!token) return "Error: GITHUB_TOKEN not set";
        const op = String(args.operation || "").toLowerCase();
        const repo = String(args.repo);
        let url, payload;
        if (op === "create_issue") {
          if (!args.title) return "Error: github_write 'create_issue' requires 'title'";
          url = `${GH}/repos/${repo}/issues`;
          payload = { title: String(args.title), body: args.body ? String(args.body) : "" };
        } else if (op === "comment") {
          if (typeof args.number !== "number") return "Error: github_write 'comment' requires 'number'";
          url = `${GH}/repos/${repo}/issues/${args.number}/comments`;
          payload = { body: args.body ? String(args.body) : "" };
        } else if (op === "create_pr") {
          if (!args.title || !args.head || !args.base) {
            return "Error: github_write 'create_pr' requires 'title', 'head', 'base'";
          }
          url = `${GH}/repos/${repo}/pulls`;
          payload = {
            title: String(args.title), head: String(args.head),
            base: String(args.base), body: args.body ? String(args.body) : "",
          };
        } else {
          return `Error: github_write: unknown operation '${op}'`;
        }
        let resp;
        try {
          resp = await fetchImpl(url, { method: "POST", headers: ghHeaders(token), body: JSON.stringify(payload) });
        } catch (e) { return "Error: github_write failed: " + ((e && e.message) || e); }
        const body = await safeText(resp);
        if (resp.status < 200 || resp.status >= 300) {
          return `Error: github_write HTTP ${resp.status}: ${apiMessage(body)}`;
        }
        try { const j = JSON.parse(body); if (j && j.html_url) return "Created: " + j.html_url; }
        catch { /* ignore */ }
        return "OK";
      },
    },
  ];
}

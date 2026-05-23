// dispatch_agent (browser port) -- runs a CCHarbour subagent loop with
// an isolated message list and a filtered tool registry. Returns the
// subagent's final reply only; tool blocks render via the regular
// tool-call UI.

import { fileTools } from "./file.js";
import { webTools } from "./web.js";
import { githubTools } from "./github.js";
import { memoryTools } from "./memory.js";
import { todoTools } from "./todo.js";
import { askTools } from "./ask.js";
import { runAgent } from "../agent.js";

const SYSTEM = (kind) =>
  `You are a CCHarbour subagent of type '${kind}'. Complete the task ` +
  `using the tools you have, then return a SHORT synthesis -- at most ` +
  `10-15 lines, ideally fewer. ` +
  `NEVER dump raw tool output to the parent: process, count, summarise. ` +
  `When asked to list items return COUNTS and at most 5 representative ` +
  `examples, not every match. No preamble, no 'Suggested next' line. ` +
  `Start with the answer.`;

export function dispatchTools(ctx) {
  const { vfs, githubToken, fetchImpl, getModel, getApiKey, getBaseUrl } = ctx;
  return [
    {
      name: "dispatch_agent",
      description:
        "Launch an isolated subagent on a focused subtask. The subagent " +
        "has its own conversation and a filtered tool registry; only its " +
        "final reply is returned. agent_type: 'explore' (read-only: read, " +
        "glob, grep, github_read, memory) or 'general' (full browser " +
        "toolset, no further dispatch). If you plan 2+ subagents in a " +
        "row, call propose_agents first instead.",
      parameters: {
        type: "object",
        properties: {
          prompt: { type: "string", description: "The task for the subagent" },
          agent_type: { type: "string", description: "explore (default) or general" },
          timeout_s: { type: "number", description: "default 120, max 600" },
        },
        required: ["prompt"],
      },
      async handler(args) {
        const prompt = String(args.prompt || "");
        if (!prompt) return "Error: dispatch_agent requires 'prompt'";
        const agentType = String(args.agent_type || "explore").toLowerCase();
        if (agentType !== "explore" && agentType !== "general") {
          return "Error: agent_type must be 'explore' or 'general'";
        }
        const apiKey = getApiKey();
        const model = getModel();
        const baseUrl = getBaseUrl ? getBaseUrl() : undefined;
        if (!apiKey) return "Error: no API key configured";

        let subTools;
        if (agentType === "explore") {
          subTools = [
            ...fileTools(vfs).filter((t) => ["read", "glob", "grep"].includes(t.name)),
            ...githubTools(githubToken || "", fetchImpl).filter((t) => t.name === "github_read"),
            ...memoryTools(),
          ];
        } else {
          subTools = [
            ...fileTools(vfs),
            ...webTools(fetchImpl),
            ...githubTools(githubToken || "", fetchImpl),
            ...memoryTools(),
            ...todoTools(),
            ...askTools(),
          ];
        }

        const schemas = subTools.map((t) => ({
          type: "function",
          function: { name: t.name, description: t.description, parameters: t.parameters },
        }));
        const byName = new Map(subTools.map((t) => [t.name, t]));
        async function subExec(name, json) {
          const tool = byName.get(name);
          if (!tool) return "Error: unknown tool '" + name + "'";
          let parsed;
          try { parsed = JSON.parse(json || "{}"); }
          catch { return "Error: invalid arguments JSON"; }
          try { return await tool.handler(parsed); }
          catch (e) { return "Error: tool '" + name + "' failed: " + ((e && e.message) || e); }
        }

        const messages = [
          { role: "system", content: SYSTEM(agentType) },
          { role: "user", content: prompt },
        ];

        const res = await runAgent({
          messages, model, tools: schemas, toolExecutor: subExec,
          maxIterations: 10,
          deepseekOpts: { apiKey, baseUrl },
        }, () => {});

        if (!res.success) {
          return "Subagent failed: " +
                 (res.errorType || "?") + ": " + (res.message || "");
        }
        const text = (res.content || "").trim();
        return text.length > 0 ? text : "[subagent returned no text]";
      },
    },
  ];
}

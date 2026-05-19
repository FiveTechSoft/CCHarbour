// Assembles the tool registry: OpenAI tool schemas, an executor, and the
// permission gate. Mirrors src/dstools.prg. The shell tool is not included.

import { fileTools } from "./file.js";
import { webTools } from "./web.js";
import { githubTools } from "./github.js";

export function buildRegistry({ vfs, githubToken, confirmWrite, fetchImpl }) {
  const tools = [
    ...fileTools(vfs),
    ...webTools(fetchImpl),
    ...githubTools(githubToken || "", fetchImpl),
  ];
  const byName = new Map(tools.map((t) => [t.name, t]));

  const schemas = tools.map((t) => ({
    type: "function",
    function: { name: t.name, description: t.description, parameters: t.parameters },
  }));

  async function executor(name, argsJson) {
    const tool = byName.get(name);
    if (!tool) return "Error: unknown tool '" + name + "'";

    let args;
    try { args = JSON.parse(argsJson || "{}"); }
    catch { return "Error: invalid arguments JSON"; }
    if (typeof args !== "object" || args == null) return "Error: invalid arguments JSON";

    for (const req of tool.parameters.required || []) {
      if (!(req in args)) return "Error: missing required argument '" + req + "'";
    }

    // Permission gate: github_write mutates real repositories, so it needs
    // an explicit per-call confirmation. Every other tool runs automatically.
    if (name === "github_write") {
      const ok = confirmWrite ? await confirmWrite(name, args) : false;
      if (!ok) return "Error: tool 'github_write' denied by user";
    }

    try { return await tool.handler(args); }
    catch (e) { return "Error: tool '" + name + "' failed: " + ((e && e.message) || e); }
  }

  return { schemas, executor };
}

// Entry point: loads config, seeds the vfs, builds the registry, and wires the
// UI to the agent loop.

import { loadConfig, saveConfig } from "./config.js";
import { createVfs } from "./vfs.js";
import { DEMO_PROJECT } from "./demo-project.js";
import { systemPrompt } from "./system-prompt.js";
import { buildRegistry } from "./tools/registry.js";
import { runAgent } from "./agent.js";
import { createUI } from "./ui.js";

let config = loadConfig();
let vfs = createVfs(DEMO_PROJECT);
let conversation = [{ role: "system", content: systemPrompt(vfs) }];
let running = false;

const ui = createUI({
  onSubmit: handleSubmit,
  onSaveSettings: handleSaveSettings,
  onReset: handleReset,
});

ui.fillSettings(config);
ui.addNotice("Welcome to the CCHarbour playground. " +
  (config.deepseekKey ? "Type a request to begin."
    : "Open Settings and add your DeepSeek API key to begin."));
if (!config.deepseekKey) ui.openSettings();

function buildRegistryForRun() {
  return buildRegistry({
    vfs,
    githubToken: config.githubToken,
    confirmWrite: (name, args) => ui.confirmWrite(name, args),
    fetchImpl: (...a) => fetch(...a),
  });
}

async function handleSubmit(text) {
  if (running) return;
  if (!config.deepseekKey) {
    ui.addError("No DeepSeek API key. Open Settings to add one.");
    ui.openSettings();
    return;
  }
  ui.addUserLine(text);
  conversation.push({ role: "user", content: text });

  const { schemas, executor } = buildRegistryForRun();
  running = true;
  ui.setBusy(true);

  try {
    let result = await runAgent(
      {
        messages: conversation,
        model: config.model,
        tools: schemas,
        toolExecutor: executor,
        deepseekOpts: { apiKey: config.deepseekKey },
      },
      onEvent,
    );
    ui.endAssistant();

    const totalUsage = {};
    mergeUsage(totalUsage, result.usage);

    // when the turn hit the iteration cap, offer to resume it with 25 more
    // iterations — repeatably, until done or the user stops.
    while (result.success && result.stopReason === "max_iterations") {
      if (!(await ui.confirmExtend())) break;
      result = await runAgent(
        {
          messages: result.messages,
          model: config.model,
          tools: schemas,
          toolExecutor: executor,
          maxIterations: 25,
          deepseekOpts: { apiKey: config.deepseekKey },
        },
        onEvent,
      );
      ui.endAssistant();
      mergeUsage(totalUsage, result.usage);
    }

    if (result.success) {
      conversation = result.messages;
      ui.setUsage(totalUsage);
      if (result.stopReason === "max_iterations") {
        ui.addNotice("[stopped: reached the iteration limit]");
      }
    } else {
      ui.addError(result.message || "the request failed");
    }
  } catch (e) {
    ui.endAssistant();
    ui.addError("unexpected error: " + ((e && e.message) || e));
  } finally {
    running = false;
    ui.setBusy(false);
  }
}

function onEvent(ev) {
  if (ev.type === "iteration_start") {
    ui.endAssistant();
  } else if (ev.type === "text_delta") {
    ui.appendAssistant(ev.text);
  } else if (ev.type === "tool_call") {
    ui.endAssistant();
    ui.addToolCall(ev.id, ev.name, ev.arguments);
  } else if (ev.type === "tool_result") {
    ui.setToolResult(ev.id, ev.content);
  } else if (ev.type === "error") {
    ui.addError(ev.message || ev.errorType);
  }
}

function handleSaveSettings(next) {
  config = next;
  saveConfig(config);
  ui.addNotice("Settings saved.");
}

function handleReset() {
  vfs = createVfs(DEMO_PROJECT);
  conversation = [{ role: "system", content: systemPrompt(vfs) }];
  ui.addNotice("Project and conversation reset.");
}

// Sums the numeric token counts of `usage` into the accumulator `acc`.
function mergeUsage(acc, usage) {
  if (usage && typeof usage === "object") {
    for (const k of Object.keys(usage)) {
      if (typeof usage[k] === "number") acc[k] = (acc[k] || 0) + usage[k];
    }
  }
}

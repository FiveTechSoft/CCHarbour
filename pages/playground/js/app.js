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
// Cumulative usage for this browser session. /cost reads it; /clear and
// /reset zero it. Each successful turn merges its usage hash here.
let lastUsageTotals = {};
// /rewind snapshot stack. Each entry is { messages, preview, usage }, pushed
// before a model turn starts and popped by /rewind. Capped at REWIND_MAX
// (oldest falls off the bottom); cleared by /clear.
const REWIND_MAX = 20;
let rewindStack = [];
// /loop state. When loopTimer is non-null the browser re-issues loopPrompt
// every loopMs milliseconds. /loop stop clears the timer (keeps the prompt
// text so /loop status can still show it); /loop clear drops both.
let loopTimer = null;
let loopPrompt = "";
let loopMs = 0;

const ui = createUI({
  onSubmit: handleSubmit,
  onSaveSettings: handleSaveSettings,
  onCancelSettings: handleCancelSettings,
  onReset: handleReset,
});

ui.fillSettings(config);
ui.addNotice("Welcome to the CCHarbour playground. " +
  (config.apiKey ? "Type a request to begin."
    : "Open Settings, pick a provider, and add an API key to begin."));
ui.showTip();
if (!config.apiKey) ui.openSettings();

function buildRegistryForRun() {
  return buildRegistry({
    vfs,
    githubToken: config.githubToken,
    confirmWrite: (name, args) => ui.confirmWrite(name, args),
    fetchImpl: (...a) => fetch(...a),
    getModel:   () => config.model,
    getApiKey:  () => config.apiKey,
    getBaseUrl: () => config.baseUrl,
  });
}

async function handleSubmit(text) {
  if (running) return;
  // Slash-command short-circuit: parse before checking the API key so /help
  // works even when no provider is configured. Anything not recognised
  // falls through to the model.
  if (text.startsWith("/")) {
    if (handleSlashCommand(text)) return;
  }
  if (!config.apiKey) {
    ui.addError("No API key. Open Settings, pick a provider, and add one.");
    ui.openSettings();
    return;
  }
  ui.addUserLine(text);
  pushRewindSnapshot(text);
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
        deepseekOpts: { apiKey: config.apiKey, baseUrl: config.baseUrl },
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
          deepseekOpts: { apiKey: config.apiKey, baseUrl: config.baseUrl },
        },
        onEvent,
      );
      ui.endAssistant();
      mergeUsage(totalUsage, result.usage);
    }

    if (result.success) {
      conversation = result.messages;
      mergeUsage(lastUsageTotals, totalUsage);
      ui.setUsage(totalUsage);
      if (result.stopReason === "max_iterations") {
        ui.addNotice("[stopped: reached the iteration limit]");
      }
      // Pre-fill the input with the model's "Suggested next:" prompt
      // so the user can Tab-accept or just press Enter to send it.
      const sg = extractSuggested(result.content || "");
      if (sg) {
        ui.setSuggestion(sg);
        ui.stripSuggestedLine();
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

// Browser-side slash commands. Returns .T. when the input was consumed
// (so the caller skips the model dispatch). Anything unrecognised returns
// .F. and the message is sent to the agent as usual.
function handleSlashCommand(line) {
  const t = line.trim();
  const sp = t.indexOf(" ");
  const cmd = (sp === -1 ? t : t.slice(0, sp)).toLowerCase();
  const arg = (sp === -1 ? "" : t.slice(sp + 1)).trim();
  switch (cmd) {
    case "/help":
      ui.addNotice(
        "Commands available in this browser playground:\n" +
        "  /help            show this list\n" +
        "  /clear           reset the conversation and the virtual project\n" +
        "  /cost            show token usage for this session\n" +
        "  /model [name]    show or switch the active model\n" +
        "  /provider        open the Settings panel (provider + API key)\n" +
        "  /reset           alias of /clear\n" +
        "  /rewind [N]      undo the last conversation turn (or N turns)\n" +
        "  /loop <int> <p>  re-run prompt <p> every <int> (e.g. 30s, 5m, 1h)\n" +
        "  /loop status     show the active loop (if any)\n" +
        "  /loop stop       stop the loop, keep the prompt text\n" +
        "  /loop clear      drop the loop entirely\n" +
        "\n" +
        "Native binary only (download from Releases): /init, /save, /load,\n" +
        "/caveman, /plan, /lean, /goal, /tasks, /compact, /btw, /exit,\n" +
        "plus the shell, dispatch_agent, dispatch_agent_background,\n" +
        "propose_agents and use_skill tools."
      );
      return true;
    case "/clear":
    case "/reset":
      handleReset();
      return true;
    case "/cost": {
      const totals = lastUsageTotals || {};
      const ti = totals.prompt_tokens || 0;
      const to = totals.completion_tokens || 0;
      ui.addNotice(
        ti + to === 0
          ? "No usage yet this session."
          : `tokens in: ${ti}  out: ${to}  total: ${ti + to}`
      );
      return true;
    }
    case "/model":
      if (!arg) {
        ui.addNotice("model: " + (config.model || "(unset)"));
      } else {
        config.model = arg;
        saveConfig(config);
        ui.fillSettings(config);
        ui.addNotice("[model -> " + arg + "]");
      }
      return true;
    case "/provider":
      ui.openSettings();
      return true;
    case "/exit":
    case "/quit":
      ui.addNotice("/exit only works in the native binary -- close the browser tab instead.");
      return true;
    case "/rewind":
      handleRewind(arg);
      return true;
    case "/loop":
      handleLoop(arg);
      return true;
  }
  return false;
}

// Pushes a snapshot of the current conversation onto the rewind stack just
// before a user-issued turn modifies it. cPreview is shown by /rewind when
// the snapshot is restored. The stack is capped at REWIND_MAX entries --
// the oldest entry falls off the bottom so memory stays bounded.
function pushRewindSnapshot(cPreview) {
  const snap = {
    // deep-clone the message array so later mutations on `conversation`
    // do not leak back into the snapshot
    messages: conversation.map(m => ({ ...m })),
    preview: (cPreview || "").slice(0, 60),
    usage:   { ...lastUsageTotals },
  };
  rewindStack.push(snap);
  while (rewindStack.length > REWIND_MAX) rewindStack.shift();
}

function handleRewind(arg) {
  let n = 1;
  const t = (arg || "").trim();
  if (t) {
    if (!/^\d+$/.test(t)) {
      ui.addNotice("[/rewind takes a count -- e.g. /rewind 3]");
      return;
    }
    n = Math.max(1, parseInt(t, 10));
  }
  if (rewindStack.length === 0) {
    ui.addNotice("[no turns to rewind]");
    return;
  }
  const pops = Math.min(n, rewindStack.length);
  // discard pops-1 entries on top, restore the one underneath
  for (let i = 0; i < pops - 1; i++) rewindStack.pop();
  const snap = rewindStack.pop();
  conversation = snap.messages.map(m => ({ ...m }));
  lastUsageTotals = { ...snap.usage };
  ui.setUsage(lastUsageTotals);
  ui.clearSuggestion();
  ui.addNotice("[rewound " + pops + " turn" + (pops === 1 ? "" : "s") +
               " -- restored before: " + snap.preview + "]");
}

// Parses "30s" / "5m" / "1h" / bare seconds into milliseconds. Returns 0
// on parse failure or non-positive duration.
function parseInterval(s) {
  const m = String(s || "").trim().toLowerCase().match(/^(\d+)([smh]?)$/);
  if (!m) return 0;
  const n = parseInt(m[1], 10);
  if (!(n > 0)) return 0;
  const unit = m[2] || "s";
  if (unit === "s") return n * 1000;
  if (unit === "m") return n * 60 * 1000;
  if (unit === "h") return n * 60 * 60 * 1000;
  return 0;
}

function formatInterval(ms) {
  const s = Math.round(ms / 1000);
  if (s >= 3600 && s % 3600 === 0) return (s / 3600) + "h";
  if (s >= 60   && s % 60   === 0) return (s / 60)   + "m";
  return s + "s";
}

function handleLoop(arg) {
  const t = (arg || "").trim();
  const low = t.toLowerCase();
  if (!t || low === "status") {
    if (!loopPrompt) {
      ui.addNotice("[no loop -- /loop <interval> <prompt> to arm (e.g. /loop 5m check CI)]");
    } else {
      ui.addNotice("[loop: every " + formatInterval(loopMs) + " -> " + loopPrompt +
                   "  (" + (loopTimer ? "ON" : "stopped") + ")]");
    }
    return;
  }
  if (low === "stop" || low === "off") {
    if (!loopTimer) { ui.addNotice("[loop already stopped]"); return; }
    clearInterval(loopTimer); loopTimer = null;
    ui.addNotice("[loop stopped]");
    return;
  }
  if (low === "clear") {
    if (!loopPrompt) { ui.addNotice("[no loop to clear]"); return; }
    if (loopTimer) { clearInterval(loopTimer); loopTimer = null; }
    loopPrompt = ""; loopMs = 0;
    ui.addNotice("[loop cleared]");
    return;
  }
  const sp = t.indexOf(" ");
  if (sp < 0) {
    ui.addNotice("[/loop needs <interval> <prompt> -- e.g. /loop 5m check CI]");
    return;
  }
  const intervalStr = t.slice(0, sp);
  const prompt = t.slice(sp + 1).trim();
  const ms = parseInterval(intervalStr);
  if (!ms) {
    ui.addNotice("[bad interval '" + intervalStr + "' -- use 30s / 5m / 1h]");
    return;
  }
  if (!prompt) {
    ui.addNotice("[/loop needs a prompt after the interval]");
    return;
  }
  if (loopTimer) clearInterval(loopTimer);
  loopPrompt = prompt;
  loopMs = ms;
  loopTimer = setInterval(() => {
    // skip a tick if a turn is still running; the next tick will catch up
    if (running) return;
    handleSubmit(loopPrompt);
  }, ms);
  ui.addNotice("[loop armed: every " + formatInterval(ms) + " -> " + prompt +
               " -- /loop stop to end]");
}

function handleSaveSettings(next) {
  config = next;
  saveConfig(config);
  ui.addNotice("Settings saved.");
}

function handleCancelSettings() {
  // restore the inputs so reopening the panel shows the live values
  ui.fillSettings(config);
}

function handleReset() {
  vfs = createVfs(DEMO_PROJECT);
  conversation = [{ role: "system", content: systemPrompt(vfs) }];
  lastUsageTotals = {};
  rewindStack = [];
  if (loopTimer) { clearInterval(loopTimer); loopTimer = null; }
  loopPrompt = ""; loopMs = 0;
  ui.clearSuggestion();
  ui.setUsage({});
  ui.addNotice("Project, conversation and usage counter reset.");
  ui.showTip();
}

// Extracts the "Suggested next:" prompt from the final assistant text,
// or returns "" when none is present. Tolerates optional markdown bold
// around the label or the prompt, optional surrounding quotes, and the
// label appearing anywhere in the last lines of the reply.
function extractSuggested(text) {
  if (!text) return "";
  const re = /[*_]{0,2}\s*suggested\s+next\s*[:\-]?\s*[*_]{0,2}\s*['"]?(.+?)['"]?[*_]{0,2}\s*$/im;
  const lines = String(text).split(/\r?\n/);
  // scan from the bottom up
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i].trim();
    if (!line) continue;
    const m = line.match(re);
    if (m && m[1] && /suggested\s+next/i.test(line)) {
      return m[1].replace(/[*_'"`]+$/g, "").trim();
    }
  }
  return "";
}

// Sums the numeric token counts of `usage` into the accumulator `acc`.
function mergeUsage(acc, usage) {
  if (usage && typeof usage === "object") {
    for (const k of Object.keys(usage)) {
      if (typeof usage[k] === "number") acc[k] = (acc[k] || 0) + usage[k];
    }
  }
}

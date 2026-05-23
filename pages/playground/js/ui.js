// Terminal-style REPL rendering and input. Owns all DOM interaction; holds no
// agent logic. createUI(handlers) wires DOM events to the supplied callbacks
// and returns render methods the app calls in response to agent events.

export function createUI(handlers) {
  const $ = (id) => document.getElementById(id);
  const scrollback = $("scrollback");
  const input = $("input");
  const sendBtn = $("send");

  let assistantEl = null;       // current streaming assistant turn
  let lastAssistantEl = null;   // last completed assistant turn (for post-hoc strip)
  const toolEls = new Map();    // tool call id -> details element

  function add(cls, text) {
    const el = document.createElement("div");
    el.className = "turn " + cls;
    el.textContent = text;
    scrollback.appendChild(el);
    scrollback.scrollTop = scrollback.scrollHeight;
    return el;
  }

  // --- input form ---
  $("input-form").addEventListener("submit", (e) => {
    e.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    input.classList.remove("suggestion");
    handlers.onSubmit(text);
  });

  // Suggestion handling: typing any printable key clears the pre-fill;
  // Tab accepts (just removes the dim style and keeps the value).
  input.addEventListener("keydown", (e) => {
    if (!input.classList.contains("suggestion")) return;
    if (e.key === "Tab") {
      e.preventDefault();
      input.classList.remove("suggestion");
      input.setSelectionRange(input.value.length, input.value.length);
      return;
    }
    // Any non-modifier printable key, Backspace or Delete clears the pre-fill
    if (e.key.length === 1 || e.key === "Backspace" || e.key === "Delete") {
      input.value = "";
      input.classList.remove("suggestion");
    }
  });

  // --- tip pool ---
  const TIPS = [
    "Type /help to see what slash commands are available.",
    "Drop your own checklist under .ccharbour/skills/ in the native build.",
    "Use Tab to accept the model's Suggested-next prompt.",
    "Settings stores keys in this browser's localStorage only.",
    "The browser playground talks straight to the provider you configured.",
    "Reset wipes the virtual project; your conversation continues.",
    "Open the native binary for shell, subagents, plan-mode and lean-mode.",
    "Models with cheaper input (kimi-k2) suit short-prompt + iterative work.",
    "GLM-4.6 is currently the strongest open-weight code model.",
    "Press Esc twice to clear the input box.",
  ];
  let tipIdx = Math.floor(Math.random() * TIPS.length);
  function nextTip() {
    tipIdx = (tipIdx + 1) % TIPS.length;
    return TIPS[tipIdx];
  }
  function tipEl(text) {
    const el = document.createElement("div");
    el.className = "turn tip";
    el.textContent = "💡 Tip: " + text;
    return el;
  }

  // --- settings panel ---
  $("settings-toggle").addEventListener("click", () => {
    $("settings").classList.toggle("hidden");
  });
  $("settings-save").addEventListener("click", () => {
    handlers.onSaveSettings({
      deepseekKey: $("key-deepseek").value.trim(),
      githubToken: $("key-github").value.trim(),
      model: $("model").value.trim() || "deepseek-v4-flash",
    });
    $("settings").classList.add("hidden");
  });
  $("settings-cancel").addEventListener("click", () => {
    // close without saving; the displayed values are not committed back
    $("settings").classList.add("hidden");
    // restore the inputs from the last-saved config so reopening shows
    // the live values, not the user's abandoned edits
    if (typeof handlers.onCancelSettings === "function") {
      handlers.onCancelSettings();
    }
  });
  $("reset").addEventListener("click", () => handlers.onReset());

  return {
    // Populate the settings inputs from a config object.
    fillSettings(cfg) {
      $("key-deepseek").value = cfg.deepseekKey || "";
      $("key-github").value = cfg.githubToken || "";
      $("model").value = cfg.model || "deepseek-v4-flash";
    },
    openSettings() { $("settings").classList.remove("hidden"); },

    addUserLine(text) { add("user", "› " + text); },
    addNotice(text) { add("assistant", text); },
    addError(text) { add("error", "✗ " + text); },

    // Begin a fresh streaming assistant turn.
    startAssistant() {
      assistantEl = add("assistant", "");
    },
    appendAssistant(text) {
      if (!assistantEl) this.startAssistant();
      assistantEl.textContent += text;
      scrollback.scrollTop = scrollback.scrollHeight;
    },
    endAssistant() {
      if (assistantEl) lastAssistantEl = assistantEl;
      assistantEl = null;
    },

    // Removes the trailing "Suggested next: <text>" line from the last
    // assistant turn after the suggestion has been lifted into the input
    // box, so it does not also clutter the scrollback.
    stripSuggestedLine() {
      if (!lastAssistantEl) return;
      const cleaned = lastAssistantEl.textContent.replace(
        /\s*\n?\s*suggested\s+next:[^\n]*\s*$/i, "");
      if (cleaned !== lastAssistantEl.textContent) {
        lastAssistantEl.textContent = cleaned.replace(/\s+$/, "");
      }
    },

    // Render a tool call as a collapsible block; fill its result later.
    addToolCall(id, name, args) {
      const d = document.createElement("details");
      d.className = "tool";
      const s = document.createElement("summary");
      s.textContent = `tool: ${name} ${args || ""}`.trim();
      const pre = document.createElement("pre");
      pre.textContent = "running…";
      d.appendChild(s);
      d.appendChild(pre);
      scrollback.appendChild(d);
      scrollback.scrollTop = scrollback.scrollHeight;
      toolEls.set(id, pre);
    },
    setToolResult(id, content) {
      const pre = toolEls.get(id);
      if (pre) pre.textContent = content;
    },

    // Inline confirmation for github_write. Returns a Promise<boolean>.
    confirmWrite(name, args) {
      return new Promise((resolve) => {
        const box = document.createElement("div");
        box.className = "confirm";
        const msg = document.createElement("div");
        msg.textContent = `Allow ${name}? ${JSON.stringify(args)}`;
        const yes = document.createElement("button");
        yes.textContent = "Allow";
        const no = document.createElement("button");
        no.textContent = "Deny";
        const done = (v) => { yes.disabled = no.disabled = true; resolve(v); };
        yes.addEventListener("click", () => done(true));
        no.addEventListener("click", () => done(false));
        box.append(msg, yes, no);
        scrollback.appendChild(box);
        scrollback.scrollTop = scrollback.scrollHeight;
      });
    },

    // Inline prompt to continue a turn that hit the iteration cap.
    // Returns a Promise<boolean>.
    confirmExtend() {
      return new Promise((resolve) => {
        const box = document.createElement("div");
        box.className = "confirm";
        const msg = document.createElement("div");
        msg.textContent =
          "Iteration cap reached — continue with 25 more iterations?";
        const yes = document.createElement("button");
        yes.textContent = "Continue";
        const no = document.createElement("button");
        no.textContent = "Stop";
        const done = (v) => { yes.disabled = no.disabled = true; resolve(v); };
        yes.addEventListener("click", () => done(true));
        no.addEventListener("click", () => done(false));
        box.append(msg, yes, no);
        scrollback.appendChild(box);
        scrollback.scrollTop = scrollback.scrollHeight;
      });
    },

    setUsage(usage) {
      const t = usage && usage.total_tokens;
      $("usage").textContent = t ? `tokens used: ${t}` : "no usage yet";
    },

    setBusy(busy) {
      input.disabled = busy;
      sendBtn.disabled = busy;
      if (!busy) input.focus();
    },

    // Pre-fill the input box with the model's Suggested-next prompt; the
    // visible value renders dimmed/italic until the user accepts (Tab) or
    // starts typing (which clears it).
    setSuggestion(text) {
      const t = String(text || "").trim();
      if (!t) return;
      input.value = t;
      input.classList.add("suggestion");
      input.setSelectionRange(0, t.length);
    },
    clearSuggestion() {
      input.value = "";
      input.classList.remove("suggestion");
    },

    // Drops a tip line into the scrollback. Cycles through the pool.
    showTip(text) {
      scrollback.appendChild(tipEl(text || nextTip()));
      scrollback.scrollTop = scrollback.scrollHeight;
    },
  };
}

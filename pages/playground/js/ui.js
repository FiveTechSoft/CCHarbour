// Terminal-style REPL rendering and input. Owns all DOM interaction; holds no
// agent logic. createUI(handlers) wires DOM events to the supplied callbacks
// and returns render methods the app calls in response to agent events.

export function createUI(handlers) {
  const $ = (id) => document.getElementById(id);
  const scrollback = $("scrollback");
  const input = $("input");
  const sendBtn = $("send");

  let assistantEl = null;       // current streaming assistant turn
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
    handlers.onSubmit(text);
  });

  // --- settings panel ---
  $("settings-toggle").addEventListener("click", () => {
    $("settings").classList.toggle("hidden");
  });
  $("settings-save").addEventListener("click", () => {
    handlers.onSaveSettings({
      deepseekKey: $("key-deepseek").value.trim(),
      tavilyKey: $("key-tavily").value.trim(),
      githubToken: $("key-github").value.trim(),
      model: $("model").value.trim() || "deepseek-v4-flash",
    });
    $("settings").classList.add("hidden");
  });
  $("reset").addEventListener("click", () => handlers.onReset());

  return {
    // Populate the settings inputs from a config object.
    fillSettings(cfg) {
      $("key-deepseek").value = cfg.deepseekKey || "";
      $("key-tavily").value = cfg.tavilyKey || "";
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
    endAssistant() { assistantEl = null; },

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
  };
}

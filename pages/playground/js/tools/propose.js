// propose_agents (browser port) -- opens a modal with each proposed
// subagent as a row with a checkbox. User toggles, accepts all (A) /
// rejects all (N), confirms (Enter) or cancels (Esc). Returns the
// approved list as JSON so the agent can iterate and dispatch.

function buildModal(proposals) {
  const overlay = document.createElement("div");
  overlay.className = "ask-overlay";
  const inner = document.createElement("div");
  inner.className = "ask-modal";
  inner.setAttribute("role", "dialog");
  inner.setAttribute("aria-modal", "true");

  const q = document.createElement("div");
  q.className = "ask-q";
  q.textContent = "The agent proposes " + proposals.length + " subagents. " +
                  "Toggle the ones you want, then Confirm.";
  inner.appendChild(q);

  const opts = document.createElement("div");
  opts.className = "ask-opts";
  proposals.forEach((p, idx) => {
    const row = document.createElement("label");
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.value = String(idx);
    cb.checked = true;
    const span = document.createElement("span");
    span.innerHTML =
      '<strong style="color:var(--accent-bright);">' +
      String(idx + 1) + ". " + (p.agent_type || "explore") + "</strong> · " +
      escapeHtml(p.prompt);
    row.appendChild(cb);
    row.appendChild(span);
    opts.appendChild(row);
  });
  inner.appendChild(opts);

  const hint = document.createElement("div");
  hint.style.cssText = "color:var(--dim);font-size:11.5px;";
  hint.textContent = "Space toggles · A accepts all · N rejects all · Enter confirms · Esc cancels";
  inner.appendChild(hint);

  const actions = document.createElement("div");
  actions.className = "ask-actions";
  const cancel = document.createElement("button");
  cancel.className = "ask-cancel";
  cancel.textContent = "Cancel";
  const ok = document.createElement("button");
  ok.className = "ask-ok";
  ok.textContent = "Confirm";
  actions.appendChild(cancel);
  actions.appendChild(ok);
  inner.appendChild(actions);

  overlay.appendChild(inner);
  return overlay;
}

function escapeHtml(s) {
  return String(s || "")
    .replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

export function proposeTools() {
  return [
    {
      name: "propose_agents",
      description:
        "Propose a batch of 2+ subagents for the user to review BEFORE " +
        "any dispatch happens. The user toggles each row on/off and " +
        "confirms; the tool returns the approved list as JSON. Iterate " +
        "that list and call dispatch_agent once per item.",
      parameters: {
        type: "object",
        properties: {
          agents: {
            type: "array",
            items: {
              type: "object",
              properties: {
                agent_type: { type: "string" },
                prompt: { type: "string" },
              },
              required: ["agent_type", "prompt"],
            },
          },
        },
        required: ["agents"],
      },
      async handler(args) {
        if (!Array.isArray(args.agents)) {
          return "Error: propose_agents requires 'agents' (array)";
        }
        const proposals = args.agents
          .filter((p) => p && typeof p.prompt === "string" && p.prompt.length > 0)
          .map((p) => ({
            agent_type: (p.agent_type || "explore"),
            prompt: p.prompt,
          }));
        if (proposals.length === 0) {
          return "Error: no valid proposals (each needs agent_type and prompt)";
        }

        const overlay = buildModal(proposals);
        document.body.appendChild(overlay);
        const inputs = [...overlay.querySelectorAll('input[type="checkbox"]')];

        const approved = await new Promise((resolve) => {
          overlay.querySelector(".ask-cancel").addEventListener("click", () => resolve(null));
          overlay.querySelector(".ask-ok").addEventListener("click", () => {
            const out = inputs
              .filter((cb) => cb.checked)
              .map((cb) => proposals[Number(cb.value)]);
            resolve(out);
          });
          overlay.addEventListener("keydown", (ev) => {
            if (ev.key === "Escape") { resolve(null); return; }
            if (ev.key === "Enter")  {
              ev.preventDefault();
              overlay.querySelector(".ask-ok").click();
              return;
            }
            if (ev.key.toLowerCase() === "a") {
              inputs.forEach((cb) => cb.checked = true);
              return;
            }
            if (ev.key.toLowerCase() === "n") {
              inputs.forEach((cb) => cb.checked = false);
              return;
            }
          });
        });
        overlay.remove();

        if (approved == null) {
          return "[cancelled] User cancelled the batch. Wait for new " +
                 "instructions; do not dispatch anything.";
        }
        if (approved.length === 0) {
          return "[empty] User confirmed but rejected every proposal. " +
                 "Do not dispatch. Ask the user how to proceed.";
        }
        const lines = approved.map((a, i) =>
          (i ? "," : "") + "\n  { " +
          '"agent_type": "' + a.agent_type + '", ' +
          '"prompt": ' + JSON.stringify(a.prompt) + " }"
        ).join("");
        return "User approved " + approved.length + " of " + proposals.length +
               " proposals. Call dispatch_agent ONCE per item below, in order:\n[" +
               lines + "\n]";
      },
    },
  ];
}

// ask_user -- opens an in-page modal with the question and 2-4 options
// plus an "Other" free-text answer. Returns a promise that resolves to
// "The user selected: <text>" once they confirm. Mirrors the native
// src/cctools_ask.prg behaviour (no console version -> the modal is the
// console).

function buildModal(question, options) {
  const overlay = document.createElement("div");
  overlay.className = "ask-overlay";
  overlay.innerHTML = `
    <div class="ask-modal" role="dialog" aria-modal="true">
      <div class="ask-q"></div>
      <div class="ask-opts"></div>
      <div class="ask-other-row">
        <label>
          <input type="radio" name="ask-pick" value="__other__">
          Other:
        </label>
        <input type="text" class="ask-other" placeholder="type your own answer">
      </div>
      <div class="ask-actions">
        <button type="button" class="ask-cancel">Cancel</button>
        <button type="button" class="ask-ok">Confirm</button>
      </div>
    </div>
  `;
  overlay.querySelector(".ask-q").textContent = question;
  const optsBox = overlay.querySelector(".ask-opts");
  options.slice(0, 4).forEach((opt, idx) => {
    const id = "ask-opt-" + idx;
    const label = document.createElement("label");
    label.setAttribute("for", id);
    label.innerHTML = `
      <input type="radio" name="ask-pick" id="${id}" value="${idx}"${idx === 0 ? " checked" : ""}>
      <span></span>
    `;
    label.querySelector("span").textContent = String(idx + 1) + ". " + opt;
    optsBox.appendChild(label);
  });
  return overlay;
}

export function askTools() {
  return [
    {
      name: "ask_user",
      description:
        "Ask the user a multiple-choice question and return their " +
        "selected answer. Use this when you need the user to make a " +
        "decision before continuing. Provide 2 to 4 short, distinct " +
        "options.",
      parameters: {
        type: "object",
        properties: {
          question: { type: "string", description: "The question to ask" },
          options: {
            type: "array",
            items: { type: "string" },
            description: "2 to 4 answer choices",
          },
        },
        required: ["question", "options"],
      },
      async handler(args) {
        const question = String(args.question || "").trim();
        const options = Array.isArray(args.options) ? args.options.map(String) : [];
        if (!question) return "Error: ask_user requires 'question'";
        if (options.length < 2) {
          return "Error: ask_user requires 2 to 4 options";
        }
        const overlay = buildModal(question, options);
        document.body.appendChild(overlay);
        const otherInput = overlay.querySelector(".ask-other");
        const radioOther = overlay.querySelector('input[value="__other__"]');
        otherInput.addEventListener("focus", () => { radioOther.checked = true; });
        otherInput.addEventListener("input", () => { radioOther.checked = true; });
        // hand focus to the first option for keyboard users
        overlay.querySelector('input[name="ask-pick"]').focus();
        const choice = await new Promise((resolve) => {
          overlay.querySelector(".ask-cancel").addEventListener("click", () => resolve(null));
          overlay.querySelector(".ask-ok").addEventListener("click", () => {
            const picked = overlay.querySelector('input[name="ask-pick"]:checked');
            if (!picked) return resolve(null);
            if (picked.value === "__other__") {
              const txt = otherInput.value.trim();
              return resolve(txt || null);
            }
            const idx = Number(picked.value);
            resolve(options[idx]);
          });
          overlay.addEventListener("keydown", (ev) => {
            if (ev.key === "Escape") resolve(null);
            if (ev.key === "Enter" && ev.target.tagName !== "BUTTON") {
              ev.preventDefault();
              overlay.querySelector(".ask-ok").click();
            }
          });
        });
        overlay.remove();
        if (choice == null) return "User cancelled the question.";
        return "The user selected: " + choice;
      },
    },
  ];
}

// Persistent config via localStorage. Keys are stored only in the browser.
const KEYS = {
  deepseek: "ccharbour_deepseek_key",
  github: "ccharbour_github_token",
  model: "ccharbour_model",
};

export function loadConfig() {
  return {
    deepseekKey: localStorage.getItem(KEYS.deepseek) || "",
    githubToken: localStorage.getItem(KEYS.github) || "",
    model: localStorage.getItem(KEYS.model) || "deepseek-chat",
  };
}

export function saveConfig(cfg) {
  localStorage.setItem(KEYS.deepseek, cfg.deepseekKey || "");
  localStorage.setItem(KEYS.github, cfg.githubToken || "");
  localStorage.setItem(KEYS.model, cfg.model || "deepseek-chat");
}

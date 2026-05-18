// API-key and model storage, backed by the browser's localStorage.

const KEYS = {
  deepseek: "ccharbour_deepseek_key",
  tavily: "ccharbour_tavily_key",
  github: "ccharbour_github_token",
  model: "ccharbour_model",
};

export function loadConfig() {
  return {
    deepseekKey: localStorage.getItem(KEYS.deepseek) || "",
    tavilyKey: localStorage.getItem(KEYS.tavily) || "",
    githubToken: localStorage.getItem(KEYS.github) || "",
    model: localStorage.getItem(KEYS.model) || "deepseek-chat",
  };
}

export function saveConfig(cfg) {
  localStorage.setItem(KEYS.deepseek, cfg.deepseekKey || "");
  localStorage.setItem(KEYS.tavily, cfg.tavilyKey || "");
  localStorage.setItem(KEYS.github, cfg.githubToken || "");
  localStorage.setItem(KEYS.model, cfg.model || "deepseek-chat");
}

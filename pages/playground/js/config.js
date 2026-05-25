// Persistent config via localStorage. Keys are stored only in the browser.
//
// The playground talks to any OpenAI-compatible chat API. The provider map
// below is the same set of presets the native CLI exposes via /provider:
// DeepSeek, GLM (Zhipu), Moonshot, OpenAI. A provider id is stored
// separately so a user who switched away from DeepSeek does not have to
// re-enter their key when they switch back.
const KEYS = {
  provider: "ccharbour_provider",
  model: "ccharbour_model",
  baseUrl: "ccharbour_base_url",
  github: "ccharbour_github_token",
};

// Each provider gets its own localStorage slot for the API key so users can
// keep several configured side-by-side.
const PROVIDER_KEY_STORAGE = {
  deepseek: "ccharbour_key_deepseek",
  glm:      "ccharbour_key_glm",
  moonshot: "ccharbour_key_moonshot",
  openai:   "ccharbour_key_openai",
  custom:   "ccharbour_key_custom",
};

export const PROVIDERS = {
  deepseek: {
    id: "deepseek",
    label: "DeepSeek",
    baseUrl: "https://api.deepseek.com",
    model: "deepseek-v4-flash",
    keyEnv: "DEEPSEEK_API_KEY",
    signup: "https://platform.deepseek.com/",
    note: "Strong coding tier. Pricing currently ~$0.27 / $1.10 per 1M tokens.",
  },
  glm: {
    id: "glm",
    label: "GLM (Zhipu)",
    baseUrl: "https://open.bigmodel.cn/api/paas/v4",
    model: "glm-4.6",
    keyEnv: "GLM_API_KEY",
    signup: "https://open.bigmodel.cn/",
    note: "Top closed-source open-weights. ~$0.60 / $2.20 per 1M tokens.",
  },
  moonshot: {
    id: "moonshot",
    label: "Moonshot (Kimi)",
    baseUrl: "https://api.moonshot.cn/v1",
    model: "kimi-k2",
    keyEnv: "MOONSHOT_API_KEY",
    signup: "https://platform.moonshot.cn/",
    note: "Strong long-context. ~$0.15 / $2.50 per 1M tokens.",
  },
  openai: {
    id: "openai",
    label: "OpenAI",
    baseUrl: "https://api.openai.com/v1",
    model: "gpt-4o-mini",
    keyEnv: "OPENAI_API_KEY",
    signup: "https://platform.openai.com/",
    note: "Top tier. Higher prices; verify on the provider's pricing page.",
  },
  custom: {
    id: "custom",
    label: "Custom (OpenAI-compatible)",
    baseUrl: "",
    model: "",
    keyEnv: "",
    signup: "",
    note: "Point baseUrl at any /chat/completions endpoint.",
  },
};

export function loadConfig() {
  const providerId = localStorage.getItem(KEYS.provider) || "deepseek";
  const preset = PROVIDERS[providerId] || PROVIDERS.deepseek;
  const storedKey = localStorage.getItem(PROVIDER_KEY_STORAGE[preset.id]) || "";
  // legacy migration: pull any previously-stored DeepSeek key into the new slot
  if (!storedKey && preset.id === "deepseek") {
    const old = localStorage.getItem("ccharbour_deepseek_key");
    if (old) {
      localStorage.setItem(PROVIDER_KEY_STORAGE.deepseek, old);
      localStorage.removeItem("ccharbour_deepseek_key");
    }
  }
  return {
    providerId: preset.id,
    provider: preset,
    apiKey: localStorage.getItem(PROVIDER_KEY_STORAGE[preset.id]) || "",
    githubToken: localStorage.getItem(KEYS.github) || "",
    model: localStorage.getItem(KEYS.model) || preset.model,
    baseUrl: localStorage.getItem(KEYS.baseUrl) || preset.baseUrl,
  };
}

export function saveConfig(cfg) {
  const provId = cfg.providerId || "deepseek";
  const preset = PROVIDERS[provId] || PROVIDERS.deepseek;
  localStorage.setItem(KEYS.provider, provId);
  localStorage.setItem(KEYS.model, cfg.model || preset.model);
  localStorage.setItem(KEYS.baseUrl, cfg.baseUrl || preset.baseUrl);
  localStorage.setItem(KEYS.github, cfg.githubToken || "");
  if (PROVIDER_KEY_STORAGE[provId]) {
    localStorage.setItem(PROVIDER_KEY_STORAGE[provId], cfg.apiKey || "");
  }
}

// Returns the API key stored for a specific provider id (used by the
// settings UI to re-fill the key field when the user switches provider).
export function keyFor(providerId) {
  const slot = PROVIDER_KEY_STORAGE[providerId];
  return slot ? localStorage.getItem(slot) || "" : "";
}

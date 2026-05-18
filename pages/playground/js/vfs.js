// In-memory virtual file system: a Map of POSIX path -> string content.
// createVfs(seedTree) seeds it from an object of { path: content }.

export function createVfs(seedTree) {
  const files = new Map();

  function norm(p) {
    return String(p).replace(/^\.?\//, "").replace(/\/+/g, "/");
  }

  if (seedTree) {
    for (const [p, c] of Object.entries(seedTree)) files.set(norm(p), String(c));
  }

  function maskToRegex(mask) {
    const name = String(mask).split("/").pop();
    const esc = name
      .replace(/[.+^${}()|[\]\\]/g, "\\$&")
      .replace(/\*/g, ".*")
      .replace(/\?/g, ".");
    return new RegExp("^" + esc + "$");
  }

  return {
    read(path) {
      const p = norm(path);
      return files.has(p) ? files.get(p) : null;
    },
    write(path, content) {
      files.set(norm(path), String(content));
    },
    exists(path) {
      return files.has(norm(path));
    },
    paths() {
      return [...files.keys()].sort();
    },
    list(dir) {
      const d = norm(dir).replace(/\/$/, "");
      const prefix = d ? d + "/" : "";
      const names = new Set();
      for (const p of files.keys()) {
        if (!p.startsWith(prefix)) continue;
        const rest = p.slice(prefix.length);
        const slash = rest.indexOf("/");
        names.add(slash < 0 ? rest : rest.slice(0, slash) + "/");
      }
      return [...names].sort();
    },
    glob(pattern) {
      const re = maskToRegex(pattern);
      return [...files.keys()].filter((p) => re.test(p.split("/").pop())).sort();
    },
    grep(regexStr, opts = {}) {
      let re;
      try { re = new RegExp(regexStr); } catch { return { error: "invalid regex" }; }
      const globRe = opts.glob ? maskToRegex(opts.glob) : null;
      const matches = [];
      for (const p of [...files.keys()].sort()) {
        if (globRe && !globRe.test(p.split("/").pop())) continue;
        files.get(p).split("\n").forEach((ln, i) => {
          if (re.test(ln)) matches.push(`${p}:${i + 1}:${ln}`);
        });
      }
      return { matches };
    },
  };
}

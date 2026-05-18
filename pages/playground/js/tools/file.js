// File tools operating on a virtual file system instance. Each tool is
// { name, description, parameters, handler }. Schemas mirror the native
// src/dstools_file.prg and src/dstools_search.prg.

function cap(s) {
  return s.length > 30000 ? s.slice(0, 30000) + "\n[output truncated]\n" : s;
}

export function fileTools(vfs) {
  return [
    {
      name: "read",
      description: "Read a file's contents from the project.",
      parameters: {
        type: "object",
        properties: { path: { type: "string", description: "File path" } },
        required: ["path"],
      },
      handler(args) {
        const c = vfs.read(args.path);
        return c == null ? "Error: file not found: " + args.path : cap(c);
      },
    },
    {
      name: "write",
      description: "Create or overwrite a file with the given contents.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path" },
          content: { type: "string", description: "File contents" },
        },
        required: ["path", "content"],
      },
      handler(args) {
        vfs.write(args.path, args.content ?? "");
        return "Wrote " + args.path;
      },
    },
    {
      name: "edit",
      description: "Replace the first occurrence of a string in a file.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path" },
          old_string: { type: "string", description: "Text to replace" },
          new_string: { type: "string", description: "Replacement text" },
        },
        required: ["path", "old_string", "new_string"],
      },
      handler(args) {
        const c = vfs.read(args.path);
        if (c == null) return "Error: file not found: " + args.path;
        if (!c.includes(args.old_string)) {
          return "Error: old_string not found in " + args.path;
        }
        vfs.write(args.path, c.replace(args.old_string, args.new_string));
        return "Edited " + args.path;
      },
    },
    {
      name: "glob",
      description: "List files matching a filename pattern (e.g. *.js).",
      parameters: {
        type: "object",
        properties: { pattern: { type: "string", description: "Filename mask" } },
        required: ["pattern"],
      },
      handler(args) {
        const m = vfs.glob(args.pattern);
        return m.length ? cap(m.join("\n")) : "No matches for " + args.pattern;
      },
    },
    {
      name: "grep",
      description: "Search file contents with a regular expression. Returns file:line:text matches.",
      parameters: {
        type: "object",
        properties: {
          pattern: { type: "string", description: "Regular expression" },
          glob: { type: "string", description: "Filename mask filter" },
        },
        required: ["pattern"],
      },
      handler(args) {
        const r = vfs.grep(args.pattern, { glob: args.glob });
        if (r.error) return "Error: " + r.error;
        return r.matches.length
          ? cap(r.matches.join("\n"))
          : "No matches for " + args.pattern;
      },
    },
  ];
}

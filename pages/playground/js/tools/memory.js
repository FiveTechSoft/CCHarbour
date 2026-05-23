// Persistent per-project memory backed by the browser's localStorage.
// Mirrors src/cctools_memory.prg.

const KEY = "ccharbour.playground.memory";

export function memoryTools() {
  return [
    {
      name: "memory",
      description:
        "Your persistent memory across sessions. " +
        "operation 'append' adds a fact, 'read' returns the whole memory, " +
        "'clear' empties it.",
      parameters: {
        type: "object",
        properties: {
          operation: { type: "string", description: "One of: append, read, clear" },
          text: { type: "string", description: "The memory entry to add (operation append)" },
        },
        required: ["operation"],
      },
      handler(args) {
        const op = String(args.operation || "").toLowerCase();
        const current = localStorage.getItem(KEY) || "";
        if (op === "append") {
          if (!args.text) return "Error: memory 'append' requires 'text'";
          const sep = current.length > 0 && !current.endsWith("\n") ? "\n" : "";
          localStorage.setItem(KEY, current + sep + String(args.text) + "\n");
          return "Remembered.";
        }
        if (op === "read") {
          const trimmed = current.trim();
          return trimmed.length === 0 ? "(memory is empty)" : trimmed;
        }
        if (op === "clear") {
          localStorage.removeItem(KEY);
          return "Memory cleared.";
        }
        return "Error: memory: unknown operation '" + op + "'";
      },
    },
  ];
}

// todo_write -- replaces the visible session task list. The list is kept in
// a module-local array and the rendered block is returned to the model.
// Mirrors src/cctools_todo.prg / src/cctodo.prg, but skips the in-DOM
// status line (playground has no persistent box -- the rendered block
// shows up in the scrollback).

let todos = [];

function normaliseStatus(s) {
  return s === "in_progress" || s === "completed" ? s : "pending";
}

function isBlocked(item, all) {
  if (!Array.isArray(item.blocked_by) || item.blocked_by.length === 0) return false;
  for (const id of item.blocked_by) {
    const other = all.find((x) => x.id === id);
    if (other && other.status !== "completed") return true;
  }
  return false;
}

function render(list) {
  const lines = ["Todos:"];
  for (const t of list) {
    const blocked = t.status !== "completed" && isBlocked(t, list);
    const label = t.status === "in_progress" && t.active_form ? t.active_form : t.text;
    const glyph =
      t.status === "completed" ? "√" :
      t.status === "in_progress" ? "■" :
      blocked ? "↳" : "□";
    lines.push((blocked ? "    " : "  ") + glyph + " " + label + (blocked ? " (blocked)" : ""));
  }
  return lines.join("\n");
}

export function todoTools() {
  return [
    {
      name: "todo_write",
      description:
        "Maintain a visible task list for multi-step work. Call with the " +
        "full list every time -- it replaces the previous list. Mark each " +
        "item pending, in_progress or completed; keep exactly one item " +
        "in_progress while working. Optional 'id' lets later items list " +
        "blockers in 'blocked_by'; optional 'active_form' is the " +
        "present-continuous label shown while in_progress. Example: " +
        "{ todos: [ " +
        "{ id: 'build', text: 'Build the binary', active_form: 'Building', status: 'in_progress' }, " +
        "{ id: 'test', text: 'Run the test suite', status: 'pending', blocked_by: ['build'] } " +
        "] }",
      parameters: {
        type: "object",
        properties: {
          todos: {
            type: "array",
            description: "The full task list",
            items: {
              type: "object",
              properties: {
                text: { type: "string" },
                status: { type: "string", description: "pending, in_progress or completed" },
                id: { type: "string" },
                active_form: { type: "string" },
                blocked_by: { type: "array", items: { type: "string" } },
              },
              required: ["text", "status"],
            },
          },
        },
        required: ["todos"],
      },
      handler(args) {
        if (!Array.isArray(args.todos)) return "Error: 'todos' must be an array";
        todos = args.todos
          .filter((t) => t && typeof t.text === "string")
          .map((t) => ({
            text: t.text,
            status: normaliseStatus(typeof t.status === "string" ? t.status : "pending"),
            id: typeof t.id === "string" ? t.id : "",
            active_form: typeof t.active_form === "string" ? t.active_form : "",
            blocked_by: Array.isArray(t.blocked_by)
              ? t.blocked_by.filter((x) => typeof x === "string" && x.length > 0)
              : [],
          }));
        return render(todos);
      },
    },
  ];
}

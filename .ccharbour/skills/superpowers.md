---
name: superpowers
description: Discipline checklist for non-trivial coding tasks — brainstorm intent first, plan multi-step work, verify before claiming done.
triggers: implement, implementa, add (feature|support|tool), añade (feature|funcionalidad|soporte), refactor, refactoriza, fix (bug|issue), arregla (bug|fallo), debug, depura, plan (the|how|out), planifica, design (the|a new), build (a|the) (feature|module|system), construye (un|una)
---

# Superpowers — process discipline

Use this skill before touching code on any task that is more than a one-line
edit or a direct factual question. It costs a minute up front and saves a
rewrite later. Follow each section in order.

## 1. Brainstorm

Before writing code:

- Restate the goal in your own words. What is the *user's* outcome (not the
  immediate request)?
- List the constraints you already know (existing files, conventions, perf
  budgets, deadlines).
- Sketch 2–3 alternative approaches in one line each, with their main
  tradeoff. Pick one and say why.
- If anything is ambiguous, ask a short clarifying question instead of
  guessing.

Skip this section only if the change is genuinely trivial (rename, typo,
single-line fix in a well-known spot).

## 2. Plan

For multi-step work:

- Break the task into 3–8 concrete steps with a clear "done" criterion each.
- Order them so each step leaves the codebase in a working state if
  possible.
- Identify the risky step up front and decide how you'll verify it.

Track the plan with the `todo_write` tool so the user can see progress.

## 3. Execute

- Do one step at a time. Mark it in progress before starting, completed when
  the verification of that step passes.
- Prefer editing existing files over creating new ones.
- Don't add features, refactors, or abstractions beyond what the step
  requires.

## 4. Verify before claiming done

Before saying "done", "fixed", "ready", or committing:

- Run the relevant build/test command. Quote the actual output.
- For UI changes, describe what you observed in the running app (or say
  explicitly that you couldn't run it).
- For bug fixes, confirm the bug no longer reproduces using the same input
  that triggered it.

"It should work" is not verification. Evidence before assertions.

## 5. Receive code review

If the user pushes back:

- Re-read the code with their concern in mind before defending.
- If you still disagree, say so with the specific reason, not "ok I'll
  change it" — sycophancy wastes their time.
- If you were wrong, name what you missed and fix it.

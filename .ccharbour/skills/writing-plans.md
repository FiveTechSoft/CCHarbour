---
name: writing-plans
description: Turn an approved approach into an ordered, verifiable, multi-step plan with a clear done criterion per step.
triggers: write (a|the) plan, plan (it|this|the implementation), planifica, paso a paso, step.?by.?step, multi.?step, implementation plan
---

# Writing plans — break work into verifiable steps

Use this AFTER brainstorming, when the approach is settled, BEFORE
touching code. Produces a written plan the user can read in one screen
and that you can execute step by step.

## Checklist

1. **State the goal in one sentence.** The same goal that came out of the
   brainstorming pass.
2. **List 3 to 8 concrete steps.** Each step:
   - Is independently understandable.
   - Has a clear, verifiable "done" criterion (a test passes, a command
     prints expected output, a file exists with a specific shape).
   - Leaves the codebase in a working state when possible.
3. **Order steps so failure is detected early.** Risky / uncertain work
   first; mechanical work last.
4. **Name the verification command for each step.** `hbmk2 ...`,
   `./run_tests`, `gh pr view`, `cc.exe < input`, etc. Concrete.
5. **Flag the riskiest step.** One sentence on the failure mode and a
   plan B if the chosen approach turns out wrong.
6. **List files you intend to touch.** Reading is fine off-list; writing
   should not surprise the user.

## Output shape

A markdown checklist:

```
## Plan: <one-sentence goal>

- [ ] **Step 1** — <what + done criterion>
      verify: `<command>`
- [ ] **Step 2** — ...
...

Riskiest: Step <N> — <why> — fallback: <plan B>
Files: src/foo.prg, tests/test_foo.prg, ...
```

Hand the plan to the user. After they approve, track it with the
`todo_write` tool and execute step by step (use the executing-plans
skill).

## Anti-patterns

- One giant step that hides everything — split it.
- A step whose "done" is "it works" — name a real check.
- Steps that depend on something you haven't read yet — read first, plan
  second.

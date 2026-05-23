---
name: brainstorming
description: Explore intent and design before any code is written — clarify the goal, list constraints, sketch 2-3 alternatives, pick one with reason.
triggers: brainstorm, lluvia de ideas, design (a|the) (feature|system|api), diseña (un|una), explora opciones, what.{1,20}options, qué opciones, cómo enfocar, how should (we|i) approach
---

# Brainstorming — explore before code

Use this BEFORE writing code on any creative or non-trivial task: new
features, new commands, new tools, redesigns, "how should we approach X"
questions. Skip only for one-line edits, typo fixes, or direct factual
questions.

Output must be a short brainstorming pass, not code. The user reviews it
and confirms before you implement anything.

## Checklist

1. **Restate the goal in your own words.** What outcome does the user
   actually want? Strip the immediate request to the underlying need.
2. **List constraints already known.**
   - Existing files / modules that will be touched.
   - Project conventions (naming, style, structure).
   - Performance, memory, dependency, or platform limits.
   - Deadlines or release-window constraints if any.
3. **Sketch 2 to 3 alternative approaches.** One line each, with the main
   tradeoff. Avoid straw-man options — each should be plausible.
4. **Pick one.** Say which and why. The "why" must reference at least one
   constraint or tradeoff from steps 2 and 3.
5. **Identify the riskiest step.** One sentence on what could go wrong and
   how you'll catch it (test, manual check, review).
6. **Ask a clarifying question** if any of steps 1-5 left you guessing.
   Don't fabricate an answer for the user.

## Stop conditions

- The user said "skip brainstorm" / "just do it" / "you decide" — proceed.
- The task is genuinely trivial — say so and proceed.
- You finished steps 1-5 with confidence — present the result and wait
  for the user's go-ahead.

## Output shape

A short markdown block with the five sections, ~5-10 lines total. Do not
include code yet. Wait for the user to approve the chosen approach before
moving to the writing-plans skill or executing.

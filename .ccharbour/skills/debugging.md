---
name: debugging
description: Systematic debugging — reproduce, isolate, hypothesise, verify. No guessing patches. Find the root cause, then fix.
triggers: bug, broken, crash, doesn't work, no funciona, fails?, falla, error message, depura, debug (this|the), why (does|is) (it|this).{1,40}(fail|crash|return|throw), why am i (getting|seeing)
---

# Debugging — find the root cause, do not guess

Use this for any bug report, test failure, or "X is not working" task.
The goal is to *understand* before you change code. A patch that
silences the symptom without explaining why is not a fix.

## Method

1. **Reproduce the bug deterministically.**
   - Reduce to the smallest input or sequence of steps that triggers it.
   - Capture exact output (error message, stack trace, return value).
     Quote it verbatim — never paraphrase an error.
   - If the bug is intermittent, find the trigger before continuing.
2. **Isolate the surface.**
   - Read the code path from entry point to failure.
   - Identify the boundary where expected and actual behaviour diverge.
   - State that boundary as "before line X the state is Y; at line X it
     becomes Z which is wrong".
3. **Hypothesise the cause.**
   - One sentence: "I think X because Y." Y must reference real code or
     observed output, not "feels wrong".
   - List 1-2 alternative hypotheses so you don't tunnel-vision.
4. **Verify the hypothesis cheaply BEFORE patching.**
   - Add a print, run a single test, inspect a variable, read related
     code. Confirm the cause is what you said it is.
   - If verification disproves your hypothesis, go back to step 2.
5. **Fix the root cause.**
   - The fix must explain why the bug happened, not just hide its
     visible symptom.
   - Prefer a small, local fix. If the fix would require restructuring,
     stop and go back to brainstorming.
6. **Add a regression test.**
   - One test that fails before the fix and passes after.
   - The test name should describe the bug, not the implementation.
7. **Verify the full suite.** Quote the pass/fail counts in your reply.

## Anti-patterns

- Adding a `try { ... } catch { ... }` to make an error stop showing up.
  The error is information; suppressing it loses the diagnostic.
- Patching every callsite of a function instead of fixing the function.
- "It works on my machine" without reproducing the user's exact input.
- Removing the test that catches the bug instead of fixing the code.
- Skipping reproduction because "obviously it's X" — twice out of three
  it isn't.

## When the bug is in tooling, not your code

- Reproduce against the *upstream* tool's documented behaviour.
- Cite the version, the command, and the exact output.
- A workaround is fine as long as the comment names the upstream bug.

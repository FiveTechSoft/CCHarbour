---
name: tdd
description: Test-driven development — write the failing test first, watch it fail, write the smallest code that passes, refactor.
triggers: tdd, test.?driven, write tests? for, escribe (tests?|pruebas?), añade tests?, add (a |the )?test, failing test, unit test
---

# TDD — red, green, refactor

Use this for any new feature or bug fix where the behaviour can be
expressed as a test. Skip only when there is genuinely no executable
check (UI tweaks, doc-only changes).

## Cycle

For each unit of behaviour:

1. **Red — write the failing test first.**
   - Name the behaviour, not the implementation. `test_undo_reverts_last_write`
     not `test_undoStackPop`.
   - Make assertions concrete (exact value, exact substring, exact count).
   - Run the test. Confirm it fails for the *expected* reason. A test that
     fails because of a syntax error or missing file does not count.
2. **Green — write the smallest change that makes it pass.**
   - No extra features, no premature abstraction, no unrelated cleanup.
   - If the change requires touching code unrelated to the failing test,
     stop and revisit the plan.
   - Re-run the test. Confirm it passes.
   - Re-run the full suite. Confirm nothing else regressed.
3. **Refactor — only after green.**
   - Improve names, factor duplication, tighten types.
   - The suite must stay green after every refactor step.

Loop until the feature is complete.

## Stop conditions

- Test passes for the wrong reason (e.g. asserting on a default). Tighten
  the assertion before continuing.
- A test you wrote depends on global state set by another test — isolate
  it.
- You find yourself adding production code without a failing test. Stop,
  write the test, then continue.

## Anti-patterns

- Writing all tests first then all code — that is not TDD, that is
  test-after batching. Cycle one behaviour at a time.
- Writing code first and a test after to "lock in" the behaviour. The
  test then locks in whatever the code happens to do, including bugs.
- Skipping the failing-for-the-right-reason check. Without it you do not
  know if the test is really testing what you think.

## CCHarbour specifics

- Test files live under `tests/`. Add `Test_Xxx()` calls in
  `tests/run_tests.prg` `Main()`.
- Build tests: `tests/build_tests.bat` (Windows) or run `hbmk2
  tests/tests.hbp`.
- Run: `tests/run_tests.exe` — last line shows `pass: N   fail: M`.
- Use `T_Equal`, `T_Assert`, `T_Equal( ValType( x ), "C", ... )`.

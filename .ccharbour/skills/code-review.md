---
name: code-review
description: Review a diff or a finished change — correctness, scope creep, security, test coverage, readability — before commit or PR.
triggers: code review, revisa (el|este) (cambio|diff|código), review (this|the) (diff|change|pr), audit (the )?code, audita, lgtm\?, ready to (commit|merge)
---

# Code review — gate before commit

Use this after a meaningful change is implemented and BEFORE a commit
or PR. Skip for trivial edits (typo, rename, one-line config).

The aim is not to find anything possible to nitpick — it is to catch
the issues a reviewer would actually flag.

## Checklist

Review the diff against each section. For each finding, give the file
and line, the problem in one sentence, and the suggested fix.

### 1. Correctness

- Does the code do what the plan / commit message said?
- Off-by-one, null checks, error paths, edge cases (empty input, max
  size, concurrent calls).
- Resource handling: files closed, locks released, sockets shut down.

### 2. Scope creep

- Are there unrelated changes mixed in? (Renames, reformatting, drive-by
  refactors.) Flag them and suggest a separate commit.
- New abstractions / generics introduced "for the future"? Push back —
  YAGNI.

### 3. Security

- Untrusted input reaching `shell`, `eval`, SQL, file paths, URLs?
- Secrets in code, log lines, or commit messages?
- Permission gate appropriate for new tools?

### 4. Tests

- New behaviour has at least one new test.
- Test name describes the behaviour, not the implementation.
- Tests are deterministic (no current time, no random, no network unless
  mocked).
- Existing tests still pass — verify by running the suite.

### 5. Readability

- Identifier names match what the code does.
- No comments restating the obvious; comments only where the *why* is
  non-obvious.
- File is consistent with the rest of the module's style.

### 6. Failure modes

- Errors surfaced clearly, with enough context to act on them.
- No `catch { /* swallow */ }` that hides a real problem.

## Output shape

```
## Review

**Blocking** (must fix before commit):
- path/to/file.prg:NN — <problem>. Fix: <suggestion>.

**Non-blocking** (consider):
- path:NN — ...

**Looks good:** <one line summary of what landed cleanly>
```

If there are no blocking issues, say so explicitly. If there are, do
not commit until they are resolved or explicitly overruled by the user.

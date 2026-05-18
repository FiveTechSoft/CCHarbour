# Prompt to extend the iteration cap

**Date:** 2026-05-18
**Status:** Approved design, ready for implementation plan
**Scope:** Native CCHarbour (`cc.exe`) and the web playground.

## Goal

When an agent turn stops because it reached the iteration cap, ask the user
whether to continue with 25 more iterations instead of silently giving up. If
the user agrees, the agent resumes from where it left off; if it caps again,
ask again. The user stays in control turn after turn.

## Background

The agent loop (`DS_AgentRun` in `src/dsagent.prg`; `runAgent` in
`pages/playground/js/agent.js`) runs at most `max_iterations` LLM rounds. When
it reaches that cap while the model is still emitting tool calls, it returns
`stop_reason`/`stopReason` = `max_iterations`. Today the REPL/app just prints a
notice and the turn ends, leaving the task half-finished.

## Approach

A continuation loop in the orchestration layer (the REPL for native, `app.js`
for the playground). The agent core is unchanged: `DS_AgentRun`/`runAgent`
already accept being called on an existing message history with a given cap,
and they return the full transcript (`messages`). To continue, the orchestrator
re-invokes the agent on the returned transcript with a fresh budget of 25
iterations. No interactive concern is threaded into the agent core.

"+25" means: each continuation runs the agent with `max_iterations` = 25 on the
accumulated conversation.

## Native — `src/dsrepl.prg`

### New helper `DSREPL_AskExtend()`

Prints a prompt — `[iteration cap reached — continue with 25 more? y/n] ` in
the warn colour (`DSUI_Pal("warn")`) — and reads one line with
`DSREPL_ReadLine`. Returns `.T.` when the trimmed, lowercased answer starts with
`"y"`, `.F.` otherwise. End-of-input (`DSREPL_ReadLine` returns `NIL`, e.g.
piped stdin) yields `.F.` — the run stops, it never hangs. This mirrors
`DSREPL_AskPerm`'s `NIL` → `"n"` handling.

### Continuation loop in `DSREPL_Run`

In the `"message" / "init"` case, the single `DS_AgentRun` call becomes a loop:

1. Run the agent the first time with `max_iterations => nMaxIter` (the settings
   value), a fresh `DSMD_New()` markdown renderer, flushing it after.
2. While the run succeeded **and** `stop_reason == "max_iterations"`:
   - Call `DSREPL_AskExtend()`. If it returns `.F.`, leave the loop.
   - Otherwise re-run `DS_AgentRun( oClient, hRes["messages"], { model, tools,
     tool_executor, max_iterations => 25 }, render )` with a fresh `DSMD_New()`,
     flushing after.
3. Token usage is accumulated across every run of the turn (sum
   `prompt_tokens` and `completion_tokens`), so the final `[tokens: …]` line
   reflects the whole turn, not just the last continuation.
4. `cSuggest` is taken from the final run's markdown renderer.
5. After the loop, `aMsgs` becomes the final `hRes["messages"]`. If
   `stop_reason` is still `max_iterations` (the user declined), print
   `[stopped: iteration cap]` exactly as today.

If a continuation run fails (`hRes["success"]` is false), the loop condition is
false, the loop exits, and the existing error branch reports it.

## Playground — `pages/playground/js/ui.js` and `app.js`

### New UI method `confirmExtend()`

`ui.js` gains `confirmExtend()`, modelled on the existing `confirmWrite`: it
appends an inline box reading "Iteration cap reached — continue with 25 more
iterations?" with two buttons, Continue and Stop, and returns a
`Promise<boolean>` resolved by the button click. Both buttons disable on
resolve.

### Continuation loop in `app.js` `handleSubmit`

After the first `runAgent` call, wrap the cap handling in a loop:

```
let result = await runAgent({ messages: conversation, model, tools,
                              toolExecutor, deepseekOpts }, onEvent);
ui.endAssistant();
while (result.success && result.stopReason === "max_iterations") {
  if (!(await ui.confirmExtend())) break;
  result = await runAgent({ messages: result.messages, model, tools,
                            toolExecutor, maxIterations: 25, deepseekOpts },
                          onEvent);
  ui.endAssistant();
}
```

The first call uses `runAgent`'s default cap (25); each continuation passes
`maxIterations: 25`. After the loop, on success `conversation` is set to
`result.messages`; token usage is the sum across every run of the turn; and if
`stopReason` is still `max_iterations` the existing
`[stopped: reached the iteration limit]` notice is shown. The whole loop stays
inside the existing `try/finally`, so `running`/`setBusy` are always cleared.

## Error handling

- A failed continuation run drops out of the loop via the `success` condition;
  the existing error path handles it.
- Native non-interactive (piped stdin): `DSREPL_AskExtend` reads end-of-input,
  returns `.F.`, the turn stops with the usual notice — no hang.
- The playground `confirmExtend` only resolves on a button click; while it is
  pending the input stays disabled (the turn is still "running").

## Testing

This feature lives entirely in orchestration layers that have no automated
tests: `src/dsrepl.prg` is not part of the Harbour test build, and `app.js` /
`ui.js` are DOM glue. No new unit tests are added. Verification:

- Native: `build.bat` produces `cc.exe` with no errors; a manual smoke test
  confirms the prompt appears on a capped turn, "y" continues, "n" stops, and
  piped stdin stops cleanly.
- Playground: `node --check` passes on `app.js` and `ui.js`; the existing
  `node --test playground-tests/*.test.js` suite still passes (the agent core
  is untouched); a manual browser smoke test confirms the Continue/Stop box.

The agent core (`DS_AgentRun` / `runAgent`) is not modified, so its existing
test coverage of the iteration cap remains valid.

## Out of scope

- Changing the default `max_iterations` (it stays as configured).
- A configurable continuation increment — the increment is fixed at 25.
- Asking how many iterations to add — the prompt is a plain yes/no.

# Extend the Iteration Cap on Demand — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an agent turn stops at the iteration cap, ask the user whether to continue with 25 more iterations, and resume the turn if they agree — repeatably.

**Architecture:** A continuation loop in the orchestration layer. When `DS_AgentRun`/`runAgent` returns `stop_reason`/`stopReason` = `max_iterations`, the REPL (native) / `app.js` (playground) prompts the user and, on yes, re-invokes the agent on the returned transcript with a 25-iteration budget. The agent core is unchanged.

**Tech Stack:** Harbour (native `cc.exe`), vanilla JS (the playground). No new automated tests — the changed files (`dsrepl.prg`, `app.js`, `ui.js`) are orchestration/DOM layers outside the test suites; verification is build + `node --check` + the existing test suite + manual smoke.

**Spec:** `docs/superpowers/specs/2026-05-18-extend-iteration-cap-design.md`

---

## Build & verify commands

- Native: `build.bat` from the repo root → `Build OK -> cc.exe`. (`dsrepl.prg` is not in the Harbour test build, so there is no unit test to run; the existing test runner is unaffected.)
- Playground: `node --check pages/playground/js/app.js` and `node --check pages/playground/js/ui.js` (exit 0); `node --test playground-tests/*.test.js` (still `fail 0` — the agent core is untouched).

---

## Task 1: Native — continuation prompt in the REPL

**Files:**
- Modify: `src/dsrepl.prg`

`dsrepl.prg` is not part of the Harbour test build, so this task has no unit test. It is verified by `build.bat` and the manual smoke test in Step 4.

- [ ] **Step 1: Add the two STATIC helpers**

In `src/dsrepl.prg`, add these two functions directly after the `DSREPL_RenderEv` function (before `DSREPL_Out`):

```harbour
// Asks whether to continue a capped turn with 25 more iterations.
// Returns .T. for a "y" answer; end-of-input (piped stdin) -> .F. (no hang).
STATIC FUNCTION DSREPL_AskExtend()
   LOCAL cLine
   DSREPL_Out( Chr(10) + DSUI_Color( ;
      "[iteration cap reached -- continue with 25 more? y/n] ", ;
      DSUI_Pal( "warn" ) ) )
   cLine := DSREPL_ReadLine()
   IF cLine == NIL
      RETURN .F.
   ENDIF
   RETURN Lower( Left( AllTrim( cLine ), 1 ) ) == "y"

// Adds the numeric token counts of xUsage into the accumulator hash hAcc.
STATIC FUNCTION DSREPL_MergeUsage( hAcc, xUsage )
   LOCAL cKey
   IF ValType( xUsage ) == "H"
      FOR EACH cKey IN hb_HKeys( xUsage )
         IF ValType( xUsage[ cKey ] ) == "N"
            hAcc[ cKey ] := iif( hb_HHasKey( hAcc, cKey ), hAcc[ cKey ], 0 ) + ;
                            xUsage[ cKey ]
         ENDIF
      NEXT
   ENDIF
   RETURN hAcc
```

- [ ] **Step 2: Declare the new local**

In `DSREPL_Run`, the `LOCAL` line currently reads:

```harbour
   LOCAL aMsgs, cLine, hAction, aTurn, hRes, cMsg, oMd, cSuggest
```

Change it to add `hUsage`:

```harbour
   LOCAL aMsgs, cLine, hAction, aTurn, hRes, cMsg, oMd, cSuggest, hUsage
```

- [ ] **Step 3: Replace the message-case body with the continuation loop**

In `DSREPL_Run`, the `CASE hAction[ "type" ] == "message" .OR. hAction[ "type" ] == "init"` branch currently is:

```harbour
      CASE hAction[ "type" ] == "message" .OR. hAction[ "type" ] == "init"
         cMsg := iif( hAction[ "type" ] == "init", ;
                      DSUI_InitPrompt(), hAction[ "text" ] )
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => cMsg } )
         oMd := DSMD_New()
         hRes := DS_AgentRun( oClient, aTurn, ;
            { "model" => cModel, ;
              "tools" => DSTools_Schemas( oReg ), ;
              "tool_executor" => bGate, ;
              "max_iterations" => nMaxIter }, ;
            {| hEv | DSREPL_RenderEv( hEv, oMd ) } )
         DSREPL_Out( DSMD_Flush( oMd ) )
         DSREPL_Out( Chr(10) )
         cSuggest := DSMD_Suggestion( oMd )
         IF hRes[ "success" ]
            aMsgs := hRes[ "messages" ]
            IF hRes[ "stop_reason" ] == "max_iterations"
               DSREPL_Out( DSUI_Color( "[stopped: iteration cap]", "33" ) + Chr(10) )
            ENDIF
            DSREPL_Out( DSUI_Color( DSREPL_UsageLine( hRes[ "usage" ] ), "90" ) + Chr(10) )
         ELSE
            DSREPL_Out( DSUI_Color( "!! error: " + hb_CStr( hRes[ "error_type" ] ) + ": " + ;
                    hb_CStr( hRes[ "message" ] ), "31" ) + Chr(10) )
         ENDIF
```

Replace that entire branch with:

```harbour
      CASE hAction[ "type" ] == "message" .OR. hAction[ "type" ] == "init"
         cMsg := iif( hAction[ "type" ] == "init", ;
                      DSUI_InitPrompt(), hAction[ "text" ] )
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => cMsg } )
         hUsage := {=>}
         oMd := DSMD_New()
         hRes := DS_AgentRun( oClient, aTurn, ;
            { "model" => cModel, ;
              "tools" => DSTools_Schemas( oReg ), ;
              "tool_executor" => bGate, ;
              "max_iterations" => nMaxIter }, ;
            {| hEv | DSREPL_RenderEv( hEv, oMd ) } )
         DSREPL_Out( DSMD_Flush( oMd ) )
         DSREPL_Out( Chr(10) )
         DSREPL_MergeUsage( hUsage, hRes[ "usage" ] )
         // when the turn stopped on the iteration cap, offer to resume it
         // with 25 more iterations -- repeatably, until done or declined.
         DO WHILE hRes[ "success" ] .AND. ;
                  hRes[ "stop_reason" ] == "max_iterations" .AND. ;
                  DSREPL_AskExtend()
            oMd := DSMD_New()
            hRes := DS_AgentRun( oClient, hRes[ "messages" ], ;
               { "model" => cModel, ;
                 "tools" => DSTools_Schemas( oReg ), ;
                 "tool_executor" => bGate, ;
                 "max_iterations" => 25 }, ;
               {| hEv | DSREPL_RenderEv( hEv, oMd ) } )
            DSREPL_Out( DSMD_Flush( oMd ) )
            DSREPL_Out( Chr(10) )
            DSREPL_MergeUsage( hUsage, hRes[ "usage" ] )
         ENDDO
         cSuggest := DSMD_Suggestion( oMd )
         IF hRes[ "success" ]
            aMsgs := hRes[ "messages" ]
            IF hRes[ "stop_reason" ] == "max_iterations"
               DSREPL_Out( DSUI_Color( "[stopped: iteration cap]", "33" ) + Chr(10) )
            ENDIF
            DSREPL_Out( DSUI_Color( DSREPL_UsageLine( hUsage ), "90" ) + Chr(10) )
         ELSE
            DSREPL_Out( DSUI_Color( "!! error: " + hb_CStr( hRes[ "error_type" ] ) + ": " + ;
                    hb_CStr( hRes[ "message" ] ), "31" ) + Chr(10) )
         ENDIF
```

Notes for the engineer:
- Harbour's `.AND.` is short-circuit, so `DSREPL_AskExtend()` in the `DO WHILE` condition is only evaluated (and only prompts) when the run succeeded and stopped on the cap.
- The first run uses `nMaxIter` (the settings value); every continuation uses `25`.
- `hUsage` accumulates token counts across the first run and all continuations; the final `[tokens: …]` line is built from `hUsage` rather than a single run's `usage`.

- [ ] **Step 4: Build and smoke-test**

Run `build.bat` from the repo root. Expected: `Build OK -> cc.exe`.

Manual smoke test (best effort — needs a `DEEPSEEK_API_KEY`):
- Set a low cap to trigger it quickly: create/edit `.ccharbour/settings.json` in the working directory with `{ "max_iterations": 2 }`, run `cc.exe`, and give it a task that needs several tool rounds (e.g. "read every file in src/ one at a time").
- Confirm the `[iteration cap reached -- continue with 25 more? y/n]` prompt appears, that `y` resumes the turn, that `n` ends it with `[stopped: iteration cap]`.
- Confirm piped stdin does not hang: `echo a request | cc.exe` — at end of input the turn stops with the notice, the program exits.
Record the smoke-test outcome (or that it could not be run without a key) in the task report. Restore `.ccharbour/settings.json` to `{ "max_iterations": 50 }` afterwards.

- [ ] **Step 5: Commit**

```bash
git add src/dsrepl.prg
git commit -m "feat: offer to extend the iteration cap when a turn caps out"
```

---

## Task 2: Playground — continuation prompt in the app

**Files:**
- Modify: `pages/playground/js/ui.js`
- Modify: `pages/playground/js/app.js`

`ui.js` and `app.js` are DOM glue with no unit tests. Verified by `node --check` and the unchanged `node --test` suite.

- [ ] **Step 1: Add `confirmExtend` to the UI**

In `pages/playground/js/ui.js`, the returned object already has a `confirmWrite` method. Add a `confirmExtend` method directly after `confirmWrite` (keep the trailing comma structure intact):

```js
    // Inline prompt to continue a turn that hit the iteration cap.
    // Returns a Promise<boolean>.
    confirmExtend() {
      return new Promise((resolve) => {
        const box = document.createElement("div");
        box.className = "confirm";
        const msg = document.createElement("div");
        msg.textContent =
          "Iteration cap reached — continue with 25 more iterations?";
        const yes = document.createElement("button");
        yes.textContent = "Continue";
        const no = document.createElement("button");
        no.textContent = "Stop";
        const done = (v) => { yes.disabled = no.disabled = true; resolve(v); };
        yes.addEventListener("click", () => done(true));
        no.addEventListener("click", () => done(false));
        box.append(msg, yes, no);
        scrollback.appendChild(box);
        scrollback.scrollTop = scrollback.scrollHeight;
      });
    },
```

- [ ] **Step 2: Add the `mergeUsage` helper to `app.js`**

In `pages/playground/js/app.js`, add this function at the end of the file (after `handleReset`):

```js
// Sums the numeric token counts of `usage` into the accumulator `acc`.
function mergeUsage(acc, usage) {
  if (usage && typeof usage === "object") {
    for (const k of Object.keys(usage)) {
      if (typeof usage[k] === "number") acc[k] = (acc[k] || 0) + usage[k];
    }
  }
}
```

- [ ] **Step 3: Replace the run logic in `handleSubmit` with the continuation loop**

In `pages/playground/js/app.js`, the `try` block of `handleSubmit` currently is:

```js
  try {
    const result = await runAgent(
      {
        messages: conversation,
        model: config.model,
        tools: schemas,
        toolExecutor: executor,
        deepseekOpts: { apiKey: config.deepseekKey },
      },
      onEvent,
    );

    ui.endAssistant();
    if (result.success) {
      conversation = result.messages;
      ui.setUsage(result.usage);
      if (result.stopReason === "max_iterations") {
        ui.addNotice("[stopped: reached the iteration limit]");
      }
    } else {
      ui.addError(result.message || "the request failed");
    }
  } catch (e) {
```

Replace it (the `try {` line down to, but NOT including, the `} catch (e) {` line) with:

```js
  try {
    let result = await runAgent(
      {
        messages: conversation,
        model: config.model,
        tools: schemas,
        toolExecutor: executor,
        deepseekOpts: { apiKey: config.deepseekKey },
      },
      onEvent,
    );
    ui.endAssistant();

    const totalUsage = {};
    mergeUsage(totalUsage, result.usage);

    // when the turn hit the iteration cap, offer to resume it with 25 more
    // iterations — repeatably, until done or the user stops.
    while (result.success && result.stopReason === "max_iterations") {
      if (!(await ui.confirmExtend())) break;
      result = await runAgent(
        {
          messages: result.messages,
          model: config.model,
          tools: schemas,
          toolExecutor: executor,
          maxIterations: 25,
          deepseekOpts: { apiKey: config.deepseekKey },
        },
        onEvent,
      );
      ui.endAssistant();
      mergeUsage(totalUsage, result.usage);
    }

    if (result.success) {
      conversation = result.messages;
      ui.setUsage(totalUsage);
      if (result.stopReason === "max_iterations") {
        ui.addNotice("[stopped: reached the iteration limit]");
      }
    } else {
      ui.addError(result.message || "the request failed");
    }
  } catch (e) {
```

Notes:
- `result` changes from `const` to `let` because the loop reassigns it.
- The first `runAgent` uses its default cap (25); each continuation passes `maxIterations: 25`.
- The loop is inside the existing `try`, so the existing `catch`/`finally` still clear `running`/`setBusy`.
- `totalUsage` accumulates across the first run and every continuation; `ui.setUsage` receives the sum.

- [ ] **Step 4: Verify**

Run:
- `node --check pages/playground/js/ui.js` — expect exit 0.
- `node --check pages/playground/js/app.js` — expect exit 0.
- `node --test playground-tests/*.test.js` — expect `fail 0` (the agent core is untouched, so every existing test still passes).

Manual smoke test (best effort): serve `pages/playground/` over HTTP, set a low `Model` is not enough — there is no UI control for the cap, so a true cap smoke test needs a task that genuinely exceeds 25 iterations. At minimum confirm the page still loads and a normal turn works; note that the cap path needs a live, long task to exercise.

- [ ] **Step 5: Commit**

```bash
git add pages/playground/js/ui.js pages/playground/js/app.js
git commit -m "feat: offer to extend the iteration cap when a turn caps out"
```

---

## Self-review notes

- **Spec coverage:** native `DSREPL_AskExtend` + continuation loop + usage accumulation (Task 1); playground `confirmExtend` + continuation loop + usage accumulation (Task 2). Both repeatable (the `DO WHILE` / `while` re-evaluate after each continuation). Non-interactive native stop (`DSREPL_AskExtend` returns `.F.` on `NIL`) — Task 1 Step 1. Agent core unchanged — confirmed, no task touches `dsagent.prg`/`agent.js`. Every spec section maps to a task.
- **Placeholder scan:** no TBD/TODO; all code is complete.
- **Type consistency:** native uses `hRes["success"]`, `hRes["stop_reason"]`, `hRes["messages"]`, `hRes["usage"]` (the `DS_AgentRun` result shape) and `DSREPL_UsageLine`/`DSREPL_ReadLine`/`DSUI_Pal`/`DSMD_New`/`DSMD_Flush`/`DSMD_Suggestion`/`DSREPL_RenderEv` (all existing). Playground uses `result.success`/`result.stopReason`/`result.messages`/`result.usage` (the `runAgent` result shape) and `ui.confirmExtend`/`ui.endAssistant`/`ui.setUsage`/`ui.addNotice`/`ui.addError` (existing UI methods plus the new `confirmExtend`). `runAgent`'s `maxIterations` option already exists.
- **No automated tests:** stated in the spec and the plan header — the changed files are outside both test suites; the agent core (which has cap tests) is not modified.

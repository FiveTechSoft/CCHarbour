# CCHarbour Terminal UI — Claude Code Format Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring cc.exe's terminal output to Claude Code format parity — compact tool-aware result summaries, an assistant bullet, no inline token line, no `bye`, and Claude Code's colours.

**Architecture:** New pure render helpers in `src/dsui.prg` (tool-call line, result summary) plus a palette change; then the REPL render layer (`src/dsrepl.prg`) is widened to a render-state object that correlates tool ids to names and tracks the assistant-bullet run.

**Tech Stack:** Harbour. `src/dsui.prg` is in the Harbour test build (its pure functions are unit-tested); `src/dsrepl.prg` is not (verified by `build.bat` + manual smoke).

**Spec:** `docs/superpowers/specs/2026-05-18-tui-cc-format-parity-design.md`

---

## Build & test commands

- Build cc.exe: `build.bat` from the repo root → `Build OK -> cc.exe`.
- Build the test runner: from `tests/`, `call` the MSVC `vcvars64.bat` (e.g. `C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat`), then `set "HB_USER_CFLAGS=-MD"`, `set "HB_USER_LDFLAGS=/NODEFAULTLIB:libcmt.lib /NODEFAULTLIB:libucrt.lib /NODEFAULTLIB:libvcruntime.lib msvcrt.lib ucrt.lib vcruntime.lib"`, then `"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp`. `tests/build_tests.bat` has a redirection bug — if it fails, write your own .bat. Run `run_tests.exe` from `tests/`; last line `pass: N   fail: M`, fail must be 0.

---

## Task 1: New render helpers in `dsui.prg`

This task only ADDS to `src/dsui.prg` (and changes one palette value) — it leaves all existing rendering working. The wiring happens in Task 2.

**Files:**
- Modify: `src/dsui.prg`
- Test: `tests/test_ui.prg` (extend `Test_UI`)

- [ ] **Step 1: Write the failing test**

Append inside `Test_UI()` in `tests/test_ui.prg`, before its `RETURN NIL`:

```harbour
   // --- tool-call line + result summary ---
   DSUI_SetColor( .F. )
   T_Assert( "Read(x.prg)" $ DSUI_ToolCallLine( "read", '{"path":"x.prg"}' ), ;
             "ui: tool-call line has the label" )
   T_Assert( ( Chr(226)+Chr(143)+Chr(186) ) $ DSUI_ToolCallLine( "read", "{}" ), ;
             "ui: tool-call line has the dot glyph" )

   T_Equal( "  " + Chr(226)+Chr(142)+Chr(191) + "  Read 3 lines" + Chr(10), ;
            DSUI_ResultSummary( "read", "a" + Chr(10) + "b" + Chr(10) + "c" + Chr(10) ), ;
            "ui: read result summary" )
   T_Assert( "Found 2 matches" $ ;
             DSUI_ResultSummary( "grep", "f:1:x" + Chr(10) + "f:2:y" + Chr(10) ), ;
             "ui: grep result summary" )
   T_Assert( "No matches for zzz" $ ;
             DSUI_ResultSummary( "grep", "No matches for zzz" ), ;
             "ui: grep no-matches passthrough" )
   T_Assert( "Wrote a.prg" $ DSUI_ResultSummary( "write", "Wrote a.prg" ), ;
             "ui: write result passthrough" )
   T_Assert( "Listed 2 files" $ ;
             DSUI_ResultSummary( "glob", "a.prg" + Chr(10) + "b.prg" + Chr(10) ), ;
             "ui: glob result summary" )
   T_Assert( "Error: file not found" $ ;
             DSUI_ResultSummary( "read", "Error: file not found: x" ), ;
             "ui: error result shows the error line" )
   T_Assert( "+ added" $ DSUI_ResultSummary( "edit", ;
             "     1 + added" + Chr(10) + "     2   kept" + Chr(10) ), ;
             "ui: diff content keeps the diff block" )
```

- [ ] **Step 2: Run test to verify it fails**

Build and run the test runner.
Expected: FAIL — `DSUI_ToolCallLine` / `DSUI_ResultSummary` undefined.

- [ ] **Step 3: Write the implementation**

In `src/dsui.prg`, add these three functions directly after the `DSUI_ResultBlock` function (and before `DSUI_DiffMark`):

```harbour
// The Claude Code-style tool-call line: an accent dot, then Tool(args). The
// dot is accent-coloured; the label is left in the default foreground.
FUNCTION DSUI_ToolCallLine( cName, cArgsJson )
   RETURN Chr(10) + ;
          DSUI_Color( Chr(226)+Chr(143)+Chr(186), DSUI_Pal( "accent" ) ) + ;
          " " + DSUI_ToolLabel( cName, cArgsJson ) + Chr(10)

// True when any line of cText is diff-formatted (per DSUI_DiffMark).
STATIC FUNCTION DSUI_HasDiff( cText )
   LOCAL cLine
   FOR EACH cLine IN hb_ATokens( cText, Chr(10) )
      IF !Empty( DSUI_DiffMark( cLine ) )
         RETURN .T.
      ENDIF
   NEXT
   RETURN .F.

// Renders the block printed under a tool call. Diff-formatted content keeps
// the coloured diff block; otherwise a compact tool-aware one-line summary.
// Result ends in LF.
FUNCTION DSUI_ResultSummary( cToolName, cContent )
   LOCAL cClean, aLines, nLines, cFirst, cSum
   cToolName := Lower( hb_CStr( cToolName ) )
   cContent  := hb_CStr( cContent )
   cClean    := StrTran( cContent, Chr(13), "" )

   IF DSUI_HasDiff( cClean )
      RETURN DSUI_Color( DSUI_ResultBlock( cContent ), DSUI_Pal( "dim" ) ) + Chr(10)
   ENDIF

   IF Left( cClean, 6 ) == "Error:"
      cSum := DSUI_Summarize( cClean, 200 )
   ELSE
      aLines := hb_ATokens( cClean, Chr(10) )
      DO WHILE Len( aLines ) > 1 .AND. Empty( ATail( aLines ) )
         hb_ADel( aLines, Len( aLines ), .T. )
      ENDDO
      nLines := Len( aLines )
      cFirst := Left( iif( nLines > 0, aLines[ 1 ], "" ), 120 )
      DO CASE
      CASE cToolName == "read"
         cSum := "Read " + LTrim( Str( nLines ) ) + " lines"
      CASE cToolName == "write" .OR. cToolName == "edit"
         cSum := cFirst
      CASE cToolName == "glob"
         cSum := iif( Left( cFirst, 11 ) == "No matches ", cFirst, ;
                      "Listed " + LTrim( Str( nLines ) ) + " files" )
      CASE cToolName == "grep"
         cSum := iif( Left( cFirst, 11 ) == "No matches ", cFirst, ;
                      "Found " + LTrim( Str( nLines ) ) + " matches" )
      CASE cToolName == "shell"
         cSum := iif( nLines > 1, ;
                      cFirst + " (" + LTrim( Str( nLines ) ) + " lines)", cFirst )
      OTHERWISE
         cSum := LTrim( Str( nLines ) ) + " lines"
      ENDCASE
   ENDIF

   RETURN DSUI_Color( "  " + Chr(226)+Chr(142)+Chr(191) + "  " + cSum, ;
                      DSUI_Pal( "dim" ) ) + Chr(10)
```

Then change the accent palette entry. In `DSUI_Pal`, the line:

```harbour
   CASE cName == "accent"     ; RETURN "38;5;215"   // tan/orange
```

becomes:

```harbour
   CASE cName == "accent"     ; RETURN "38;2;217;119;87"   // Claude Code coral
```

Do NOT change `DSUI_RenderEvent` in this task — it is rewired in Task 2.

- [ ] **Step 4: Run test to verify it passes**

Build and run the test runner.
Expected: PASS — the new `ui:` assertions pass, `fail: 0`, no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/dsui.prg tests/test_ui.prg
git commit -m "feat: tool-call line, result summary helpers, coral accent"
```

---

## Task 2: Wire the render layer and drop the token/bye lines

**Files:**
- Modify: `src/dsrepl.prg`
- Modify: `src/dsui.prg` (`DSUI_RenderEvent`)
- Modify: `tests/test_ui.prg`

`src/dsrepl.prg` is not in the test build; the `dsrepl.prg` parts are verified by `build.bat` and a manual smoke test. The `dsui.prg`/`test_ui.prg` parts are verified by the test runner.

- [ ] **Step 1: Slim `DSUI_RenderEvent` and update its tests**

In `src/dsui.prg`, `DSUI_RenderEvent` currently has `text_delta`, `tool_call`, `tool_result`, and `error` cases. The `tool_call` and `tool_result` rendering moves into the REPL render layer (Step 3), so remove those two cases. The function becomes exactly:

```harbour
// Maps one agent/SSE event hash to display text ("" when the event is ignored).
// tool_call and tool_result are rendered by the REPL render layer, which has
// the tool-name state they need.
FUNCTION DSUI_RenderEvent( hEv )
   LOCAL cType
   IF ValType( hEv ) != "H" .OR. !hb_HHasKey( hEv, "type" )
      RETURN ""
   ENDIF
   cType := hEv[ "type" ]
   DO CASE
   CASE cType == "text_delta"
      RETURN hb_CStr( hEv[ "text" ] )
   CASE cType == "error"
      RETURN Chr(10) + DSUI_Color( "!! error: " + hb_CStr( hEv[ "message" ] ), ;
             "31" ) + Chr(10)
   ENDCASE
   RETURN ""
```

In `tests/test_ui.prg`, the `// DSUI_RenderEvent` block has assertions for `text_delta`, `tool_call` (two: `Read(x)` label and the dot glyph), `tool_result` (`line two`), `error`, and `iteration_start`. Remove the two `tool_call` assertions and the one `tool_result` assertion (those event types are no longer handled by `DSUI_RenderEvent`). Keep the `text_delta`, `error`, and `iteration_start` assertions.

- [ ] **Step 2: Run the test runner to confirm it still passes**

Build and run the test runner.
Expected: PASS, `fail: 0` — `DSUI_RenderEvent` still renders `text_delta`/`error`/unknown; the removed assertions are gone; Task 1's new tests still pass.

- [ ] **Step 3: Rewrite the REPL render layer**

In `src/dsrepl.prg`, replace the `DSREPL_RenderEv` function (currently the `text_delta`-vs-everything-else function with its leading comment) with a render-state constructor plus a full dispatcher:

```harbour
// Creates a per-turn render state: the markdown renderer, an id->tool-name
// map (to label tool results), and the assistant-bullet run flag.
STATIC FUNCTION DSREPL_RenderNew()
   RETURN { "md" => DSMD_New(), "tools" => {=>}, "inText" => .F. }

// Renders one agent event into the terminal, using the render state oRender.
STATIC FUNCTION DSREPL_RenderEv( hEv, oRender )
   LOCAL cType, cId
   IF ValType( hEv ) != "H" .OR. !hb_HHasKey( hEv, "type" )
      RETURN NIL
   ENDIF
   cType := hEv[ "type" ]
   DO CASE
   CASE cType == "text_delta"
      IF !oRender[ "inText" ]
         DSREPL_Out( DSUI_Color( Chr(226)+Chr(143)+Chr(186) + " ", ;
                                 DSUI_Pal( "accent" ) ) )
         oRender[ "inText" ] := .T.
      ENDIF
      DSREPL_Out( DSMD_Feed( oRender[ "md" ], hb_CStr( hEv[ "text" ] ) ) )
   CASE cType == "tool_call"
      DSREPL_Out( DSMD_Flush( oRender[ "md" ] ) )
      oRender[ "inText" ] := .F.
      IF hb_HHasKey( hEv, "id" )
         oRender[ "tools" ][ hb_CStr( hEv[ "id" ] ) ] := hb_CStr( hEv[ "name" ] )
      ENDIF
      DSREPL_Out( DSUI_ToolCallLine( hEv[ "name" ], hEv[ "arguments" ] ) )
   CASE cType == "tool_result"
      DSREPL_Out( DSMD_Flush( oRender[ "md" ] ) )
      oRender[ "inText" ] := .F.
      cId := hb_CStr( hb_HGetDef( hEv, "id", "" ) )
      DSREPL_Out( DSUI_ResultSummary( ;
         hb_HGetDef( oRender[ "tools" ], cId, "" ), ;
         hb_CStr( hEv[ "content" ] ) ) )
   OTHERWISE
      DSREPL_Out( DSMD_Flush( oRender[ "md" ] ) )
      oRender[ "inText" ] := .F.
      DSREPL_Out( DSUI_RenderEvent( hEv ) )
   ENDCASE
   RETURN NIL
```

- [ ] **Step 4: Update `DSREPL_Run` — render state, drop the token line**

In `DSREPL_Run`:

(a) The `LOCAL` line currently is:
```harbour
   LOCAL aMsgs, cLine, hAction, aTurn, hRes, cMsg, oMd, cSuggest, hUsage
```
Change it to drop `oMd` and `hUsage`, add `oRender`:
```harbour
   LOCAL aMsgs, cLine, hAction, aTurn, hRes, cMsg, cSuggest, oRender
```

(b) The `"message" / "init"` case currently is exactly:
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

Replace that entire branch with exactly:
```harbour
      CASE hAction[ "type" ] == "message" .OR. hAction[ "type" ] == "init"
         cMsg := iif( hAction[ "type" ] == "init", ;
                      DSUI_InitPrompt(), hAction[ "text" ] )
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => cMsg } )
         oRender := DSREPL_RenderNew()
         hRes := DS_AgentRun( oClient, aTurn, ;
            { "model" => cModel, ;
              "tools" => DSTools_Schemas( oReg ), ;
              "tool_executor" => bGate, ;
              "max_iterations" => nMaxIter }, ;
            {| hEv | DSREPL_RenderEv( hEv, oRender ) } )
         DSREPL_Out( DSMD_Flush( oRender[ "md" ] ) )
         DSREPL_Out( Chr(10) )
         // when the turn stopped on the iteration cap, offer to resume it
         // with 25 more iterations -- repeatably, until done or declined.
         DO WHILE hRes[ "success" ] .AND. ;
                  hRes[ "stop_reason" ] == "max_iterations" .AND. ;
                  DSREPL_AskExtend()
            oRender := DSREPL_RenderNew()
            hRes := DS_AgentRun( oClient, hRes[ "messages" ], ;
               { "model" => cModel, ;
                 "tools" => DSTools_Schemas( oReg ), ;
                 "tool_executor" => bGate, ;
                 "max_iterations" => 25 }, ;
               {| hEv | DSREPL_RenderEv( hEv, oRender ) } )
            DSREPL_Out( DSMD_Flush( oRender[ "md" ] ) )
            DSREPL_Out( Chr(10) )
         ENDDO
         cSuggest := DSMD_Suggestion( oRender[ "md" ] )
         IF hRes[ "success" ]
            aMsgs := hRes[ "messages" ]
            IF hRes[ "stop_reason" ] == "max_iterations"
               DSREPL_Out( DSUI_Color( "[stopped: iteration cap]", "33" ) + Chr(10) )
            ENDIF
         ELSE
            DSREPL_Out( DSUI_Color( "!! error: " + hb_CStr( hRes[ "error_type" ] ) + ": " + ;
                    hb_CStr( hRes[ "message" ] ), "31" ) + Chr(10) )
         ENDIF
```

(This drops the `hUsage` accumulator, the two `DSREPL_MergeUsage` calls, and the `DSREPL_UsageLine` token line — gap C.)

- [ ] **Step 5: Drop the `bye` line and the dead usage helpers**

In `DSREPL_Run`, the loop is followed by:
```harbour
   ENDDO
   DSREPL_Out( Chr(10) + DSUI_Color( "bye", "90" ) + Chr(10) )
   RETURN NIL
```
Remove the `bye` line so it reads:
```harbour
   ENDDO
   RETURN NIL
```

Then delete two now-unused STATIC functions from `src/dsrepl.prg`: `DSREPL_MergeUsage` (and its leading comment) and `DSREPL_UsageLine` (and its leading comment). Confirm with a repo-wide search that nothing else references them — they are only used by the code removed in Step 4.

- [ ] **Step 6: Build, test, smoke**

Run `build.bat` from the repo root. Expected: `Build OK -> cc.exe`.

Build and run the test runner. Expected: `fail: 0`.

Manual smoke test (best effort — needs a `DEEPSEEK_API_KEY`): run `cc.exe`, ask it to read a file. Confirm: the tool call shows `⏺ Read(file)` with a coral dot (not cyan); the result shows a one-line `⎿  Read N lines` summary (not the file dump); the assistant's answer is prefixed with a coral `⏺`; no `[tokens: …]` line appears; `/exit` prints no `bye`. Record the outcome (or that it could not be run without a key) in the task report.

- [ ] **Step 7: Commit**

```bash
git add src/dsrepl.prg src/dsui.prg tests/test_ui.prg
git commit -m "feat: Claude Code-style tool results, assistant bullet, drop token/bye lines"
```

---

## Self-review notes

- **Spec coverage:** A — `DSUI_ResultSummary` with the diff path (T1) wired into `DSREPL_RenderEv`'s `tool_result` case (T2). B — the `⏺` bullet on the first `text_delta` of a run, tracked by `oRender["inText"]` (T2). C — token line + `hUsage`/`DSREPL_MergeUsage`/`DSREPL_UsageLine` removed (T2 Steps 4-5). D — `bye` removed (T2 Step 5). E — `DSUI_ToolCallLine` (accent dot, plain label, no cyan) + the coral accent palette value (T1), used by the tool-call render and the assistant bullet (T2). Render state with the `id→name` map (T2 Step 3). Every spec section maps to a task.
- **Working intermediate state:** Task 1 only adds functions + changes one palette constant — cc.exe still builds and renders as before. Task 2 does the rewire and the removals together, so there is no broken commit.
- **Type consistency:** `DSREPL_RenderNew()` returns `{ md, tools, inText }`; `DSREPL_RenderEv( hEv, oRender )` consumes exactly those keys; `DSMD_Flush`/`DSMD_Suggestion` are called on `oRender["md"]`. `DSUI_ToolCallLine( cName, cArgsJson )` and `DSUI_ResultSummary( cToolName, cContent )` signatures match their call sites. `DSUI_RenderEvent` keeps `text_delta`/`error` only, reached via `DSREPL_RenderEv`'s `OTHERWISE`.
- **Diff path preserved:** `DSUI_DiffMark` and `DSUI_ResultBlock` are untouched; `DSUI_ResultSummary` routes diff-formatted content through them, so the coloured `edit`/diff display is retained.

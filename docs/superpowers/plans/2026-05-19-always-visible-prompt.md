# Always-Visible Prompt with Mid-Turn Input — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the CCHarbour input box pinned to the bottom of the terminal at all times; let the user type while the agent works — a plain message queues, `Esc` or a `/btw …` line interrupts.

**Architecture:** A new `ccprompt.prg` module owns a persistent bottom input box (drawn inside a VT scroll region) and a FIFO message queue. The agent loop (`CC_AgentRun`) gains an `interrupt_check` codeblock; its per-event `bOnEvent` callback polls the prompt for keystrokes. The REPL `Main` loop drives the prompt lifecycle and drains the queue.

**Tech Stack:** Harbour (`.prg`), a small C extension (`ccconsole.c`), MSVC `hbmk2` build. Tested through `tests/run_tests.prg`.

**Spec:** `docs/superpowers/specs/2026-05-19-always-visible-prompt-design.md`

---

## Build & test commands

- **Build cc.exe:** from the repo root, `build.bat` → expect `Build OK -> cc.exe`. If a link error mentions a locked `cc.exe`, run `Get-Process cc | Stop-Process -Force` (PowerShell) and retry.
- **Build + run the test runner:** from `tests/`, run a `cmd` that does: `call` the MSVC `vcvars64.bat` (under `C:\Program Files*\Microsoft Visual Studio\...\VC\Auxiliary\Build\`), `set "HB_USER_CFLAGS=-MD"`, `set "HB_USER_LDFLAGS=/NODEFAULTLIB:libcmt.lib /NODEFAULTLIB:libucrt.lib /NODEFAULTLIB:libvcruntime.lib msvcrt.lib ucrt.lib vcruntime.lib"`, then `"C:\harbour\bin\win\msvc64\hbmk2.exe" -comp=msvc64 tests.hbp`. Run `tests\run_tests.exe`; last line `pass: N   fail: M` — `fail` must be 0.

The current suite passes at **345 tests**. `src/ccrepl.prg` and `src/ccprompt.prg`'s console I/O are NOT exercised by the test runner (no real console); their console paths are checked by `build.bat` compiling and a manual smoke test.

## File structure

- **`src/ccprompt.prg`** (new) — the persistent bottom input box and the message queue. Pure logic (`CCPROMPT_Classify`, `CCPROMPT_Region`, `CCPROMPT_Enqueue`, `CCPROMPT_Dequeue`, `CCPROMPT_Interrupted`, `CCPROMPT_New`) plus console I/O (`CCPROMPT_Poll`, `CCPROMPT_Redraw`, `CCPROMPT_Activate`, `CCPROMPT_Teardown`).
- **`src/ccconsole.c`** — add `CCCON_Size()`, `CCCON_KeyPending()`, and an `Esc` mapping to `CCCON_ReadKey()`.
- **`src/ccagent.prg`** — `CC_AgentRun` honours an `interrupt_check` option; the old `Esc` pause prompt is removed.
- **`src/ccrepl.prg`** — `CCREPL_Run` reworked around the persistent prompt.
- **`tests/test_prompt.prg`** (new) — unit tests for the pure logic.

---

## Task 1: ccprompt.prg — pure logic and the message queue

**Files:**
- Create: `src/ccprompt.prg`
- Create: `tests/test_prompt.prg`
- Modify: `cc.hbp`, `tests/tests.hbp`, `tests/run_tests.prg`

- [ ] **Step 1: Wire the new files into the build and test harness**

In `cc.hbp`, add `src/ccprompt.prg` on the line after `src/ccinput.prg`.

In `tests/tests.hbp`: add `test_prompt.prg` on the line after `test_input.prg`, and add `../src/ccprompt.prg` on the line after `../src/ccinput.prg`.

In `tests/run_tests.prg`, in `Main()`, add a call to `Test_Prompt()` immediately after the existing `Test_Input()` call.

- [ ] **Step 2: Write the failing test**

Create `tests/test_prompt.prg`:

```harbour
FUNCTION Test_Prompt()
   LOCAL oP, hC, hR, x

   // --- CCPROMPT_Classify ---
   hC := CCPROMPT_Classify( "fix the bug" )
   T_Equal( hC[ "action" ], "queue", "prompt: plain line -> queue" )
   T_Equal( hC[ "text" ], "fix the bug", "prompt: queue keeps text" )

   hC := CCPROMPT_Classify( "  spaced  " )
   T_Equal( hC[ "text" ], "spaced", "prompt: classify trims" )

   hC := CCPROMPT_Classify( "" )
   T_Equal( hC[ "action" ], "empty", "prompt: blank line -> empty" )
   hC := CCPROMPT_Classify( "    " )
   T_Equal( hC[ "action" ], "empty", "prompt: whitespace -> empty" )

   hC := CCPROMPT_Classify( "/btw also rename it" )
   T_Equal( hC[ "action" ], "btw", "prompt: /btw -> btw" )
   T_Equal( hC[ "text" ], "also rename it", "prompt: btw extracts text" )

   hC := CCPROMPT_Classify( "/BTW shout" )
   T_Equal( hC[ "action" ], "btw", "prompt: /btw is case-insensitive" )

   hC := CCPROMPT_Classify( "/btw" )
   T_Equal( hC[ "action" ], "btw", "prompt: bare /btw -> btw" )
   T_Equal( hC[ "text" ], "", "prompt: bare /btw has empty text" )

   hC := CCPROMPT_Classify( "/btweak something" )
   T_Equal( hC[ "action" ], "queue", "prompt: /btweak is not /btw" )

   // --- CCPROMPT_Region ---
   hR := CCPROMPT_Region( 30, 100 )
   T_Equal( hR[ "active" ], .T., "prompt: 30-row console is active" )
   T_Equal( hR[ "scroll_bottom" ], 27, "prompt: scroll region ends at rows-3" )
   T_Equal( hR[ "box_top" ], 28, "prompt: box starts at rows-2" )

   hR := CCPROMPT_Region( 6, 100 )
   T_Equal( hR[ "active" ], .F., "prompt: a 6-row console falls back" )

   // --- queue: FIFO ---
   oP := CCPROMPT_New( { "rows" => 30, "cols" => 100 } )
   T_Equal( CCPROMPT_Interrupted( oP ), .F., "prompt: new prompt not interrupted" )
   T_Equal( CCPROMPT_Dequeue( oP ), NIL, "prompt: dequeue empty -> NIL" )

   CCPROMPT_Enqueue( oP, "first" )
   CCPROMPT_Enqueue( oP, "second" )
   T_Equal( CCPROMPT_Dequeue( oP ), "first", "prompt: dequeue is FIFO (1)" )
   T_Equal( CCPROMPT_Dequeue( oP ), "second", "prompt: dequeue is FIFO (2)" )
   T_Equal( CCPROMPT_Dequeue( oP ), NIL, "prompt: dequeue drained -> NIL" )

   // --- interrupt state ---
   oP := CCPROMPT_New( { "rows" => 30, "cols" => 100 } )
   oP[ "interrupt" ] := { "kind" => "esc", "text" => "" }
   T_Equal( CCPROMPT_Interrupted( oP ), .T., "prompt: interrupt set -> .T." )

   x := CCPROMPT_New( { "rows" => 30, "cols" => 100 } )
   T_Equal( ValType( x[ "editor" ] ), "H", "prompt: new has an editor state" )
   T_Equal( ValType( x[ "queue" ] ), "A", "prompt: new has a queue array" )

   RETURN NIL
```

- [ ] **Step 3: Run the test runner to verify it FAILS**

Build and run the test runner. Expected: FAIL — `CCPROMPT_*` undefined.

- [ ] **Step 4: Write the implementation**

Create `src/ccprompt.prg` with the pure logic (the console I/O functions are added in Task 4 — leave them out for now):

```harbour
#include "fileio.ch"

// ccprompt: the persistent bottom input box and the mid-turn message queue.
// This file holds the pure logic; the console I/O (Poll, Redraw, Activate,
// Teardown) is added on top of it.

// The input box occupies the bottom THREE rows of the terminal.
#define CCPROMPT_BOX_ROWS  3
// Below this many rows there is no room for the box -> fallback mode.
#define CCPROMPT_MIN_ROWS  8

// Builds a fresh prompt state. hSize is an optional { rows, cols } hash; when
// omitted the console is queried with CCCON_Size(). region/editor/queue are
// always present so the pure helpers work without a console.
FUNCTION CCPROMPT_New( hSize )
   LOCAL nRows, nCols
   IF ValType( hSize ) == "H"
      nRows := hSize[ "rows" ]
      nCols := hSize[ "cols" ]
   ELSE
      hSize := CCCON_Size()
      nRows := hSize[ "rows" ]
      nCols := hSize[ "cols" ]
   ENDIF
   RETURN { "editor"    => CCIN_New( "" ), ;
            "queue"     => {}, ;
            "interrupt" => NIL, ;
            "region"    => CCPROMPT_Region( nRows, nCols ) }

// Computes the screen layout for a console of nRows x nCols. The box is the
// bottom 3 rows; the scroll region is rows 1 .. nRows-3. A console shorter
// than CCPROMPT_MIN_ROWS is reported inactive (the caller falls back).
FUNCTION CCPROMPT_Region( nRows, nCols )
   RETURN { "rows"          => nRows, ;
            "cols"          => nCols, ;
            "active"        => ( nRows >= CCPROMPT_MIN_ROWS ), ;
            "scroll_bottom" => nRows - CCPROMPT_BOX_ROWS, ;
            "box_top"       => nRows - CCPROMPT_BOX_ROWS + 1 }

// Classifies a submitted line. Returns { action, text }:
//   action "empty" -> blank line, ignore
//   action "btw"   -> /btw line, text is the remainder (an interrupt)
//   action "queue" -> a normal message to queue
FUNCTION CCPROMPT_Classify( cLine )
   LOCAL cTrim := AllTrim( hb_CStr( cLine ) )
   IF Empty( cTrim )
      RETURN { "action" => "empty", "text" => "" }
   ENDIF
   IF Lower( cTrim ) == "/btw"
      RETURN { "action" => "btw", "text" => "" }
   ENDIF
   IF Lower( Left( cTrim, 5 ) ) == "/btw "
      RETURN { "action" => "btw", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   ENDIF
   RETURN { "action" => "queue", "text" => cTrim }

// Appends a message to the FIFO queue.
FUNCTION CCPROMPT_Enqueue( oPrompt, cText )
   AAdd( oPrompt[ "queue" ], hb_CStr( cText ) )
   RETURN oPrompt

// Removes and returns the oldest queued message, or NIL when the queue is
// empty.
FUNCTION CCPROMPT_Dequeue( oPrompt )
   LOCAL cFirst
   IF Empty( oPrompt[ "queue" ] )
      RETURN NIL
   ENDIF
   cFirst := oPrompt[ "queue" ][ 1 ]
   hb_ADel( oPrompt[ "queue" ], 1, .T. )
   RETURN cFirst

// Returns .T. when an interruption (Esc or /btw) is pending.
FUNCTION CCPROMPT_Interrupted( oPrompt )
   RETURN oPrompt[ "interrupt" ] != NIL
```

- [ ] **Step 5: Run the test runner to verify it PASSES**

Build and run the test runner. Expected: all `prompt:` assertions pass; `pass: N   fail: 0`; no regressions.

(The `CCPROMPT_New` no-argument path calls `CCCON_Size`, which does not exist yet — but `Test_Prompt` only ever calls `CCPROMPT_New` with an explicit `hSize`, so the test build links and runs. `CCCON_Size` arrives in Task 2.)

- [ ] **Step 6: Commit**

```
git add src/ccprompt.prg tests/test_prompt.prg cc.hbp tests/tests.hbp tests/run_tests.prg
git commit -m "feat: ccprompt module — message queue and prompt classification"
```
End the commit body with: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

---

## Task 2: Console functions — CCCON_Size, CCCON_KeyPending, Esc key

**Files:**
- Modify: `src/ccconsole.c`

This task adds C functions that need a real console; they are verified by `build.bat` compiling cleanly and by the Task 5 manual smoke test. There is no unit test.

- [ ] **Step 1: Add `CCCON_Size`, `CCCON_KeyPending`, and an Esc mapping**

In `src/ccconsole.c`, add two new `HB_FUNC` blocks (place them after `CCCON_PEEKESC`):

```c
/* CCCON_Size() -> { "rows" => <n>, "cols" => <n> } : the visible console
 * window size. Falls back to 24x80 when there is no console. */
HB_FUNC( CCCON_SIZE )
{
   HANDLE h = GetStdHandle( STD_OUTPUT_HANDLE );
   CONSOLE_SCREEN_BUFFER_INFO csbi;
   int rows = 24, cols = 80;
   PHB_ITEM pHash;

   if( h != INVALID_HANDLE_VALUE && h != NULL &&
       GetConsoleScreenBufferInfo( h, &csbi ) )
   {
      rows = csbi.srWindow.Bottom - csbi.srWindow.Top + 1;
      cols = csbi.srWindow.Right  - csbi.srWindow.Left + 1;
      if( rows < 1 ) rows = 24;
      if( cols < 1 ) cols = 80;
   }

   pHash = hb_hashNew( NULL );
   hb_hashAddNew( pHash, hb_itemPutC( NULL, "rows" ), hb_itemPutNI( NULL, rows ) );
   hb_hashAddNew( pHash, hb_itemPutC( NULL, "cols" ), hb_itemPutNI( NULL, cols ) );
   hb_itemReturnRelease( pHash );
}

/* CCCON_KeyPending() -> .T. when a key-down event is waiting in the console
 * input queue. Non-blocking; does NOT consume the event. */
HB_FUNC( CCCON_KEYPENDING )
{
   HANDLE h = GetStdHandle( STD_INPUT_HANDLE );
   DWORD  nEvents = 0, nRead, i;
   INPUT_RECORD recs[ 32 ];

   if( h == INVALID_HANDLE_VALUE || h == NULL ||
       ! GetNumberOfConsoleInputEvents( h, &nEvents ) || nEvents == 0 )
   {
      hb_retl( HB_FALSE );
      return;
   }
   if( nEvents > 32 ) nEvents = 32;
   if( PeekConsoleInputW( h, recs, nEvents, &nRead ) && nRead > 0 )
   {
      for( i = 0; i < nRead; i++ )
      {
         if( recs[ i ].EventType == KEY_EVENT && recs[ i ].Event.KeyEvent.bKeyDown )
         {
            hb_retl( HB_TRUE );
            return;
         }
      }
   }
   hb_retl( HB_FALSE );
}
```

- [ ] **Step 2: Add the Esc mapping to `CCCON_ReadKey`**

In `src/ccconsole.c`, in `HB_FUNC( CCCON_READKEY )`, add an `Esc` case. After the `VK_TAB` line:

```c
         else if( vk == VK_TAB )          { result = -12; done = HB_TRUE; }
         else if( vk == VK_ESCAPE )       { result = -13; done = HB_TRUE; }
```

Also update the comment block above `CCCON_READKEY` so the key table lists `-13 Esc`.

- [ ] **Step 3: Build cc.exe to verify it compiles and links**

Run `build.bat`. Expected: `Build OK -> cc.exe`.

- [ ] **Step 4: Build and run the test runner**

Expected: `pass: N   fail: 0` — no regressions (the new C functions are not yet called by any test, but the test build compiles `ccconsole.c`).

- [ ] **Step 5: Commit**

```
git add src/ccconsole.c
git commit -m "feat: CCCON_Size and CCCON_KeyPending; map Esc in CCCON_ReadKey"
```
End the commit body with: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

---

## Task 3: Agent interrupt_check

**Files:**
- Modify: `src/ccagent.prg`
- Test: `tests/test_agent.prg`

- [ ] **Step 1: Write the failing test**

In `tests/test_agent.prg`, inside `Test_Agent()`, before its final `RETURN NIL`, append:

```harbour
   // interrupt_check: a check that returns .T. stops the loop before the
   // first API call, with stop_reason "interrupted" and success .T.
   hR := CC_AgentRun( NIL, ;
      { { "role" => "user", "content" => "hello" } }, ;
      { "interrupt_check" => {|| .T. } }, ;
      NIL )
   T_Equal( hR[ "success" ], .T., "agent: interrupt -> success" )
   T_Equal( hR[ "stop_reason" ], "interrupted", "agent: interrupt stop_reason" )
   T_Equal( hR[ "iterations" ], 0, "agent: interrupt before any iteration" )
```

(`hR` is already a LOCAL in `Test_Agent`; if not, add it.)

- [ ] **Step 2: Build and run the test runner to verify it FAILS**

Expected: FAIL — without the feature the run reaches `CC_ChatCompletion` (no transport) and reports an error rather than `stop_reason => "interrupted"`.

- [ ] **Step 3: Implement `interrupt_check` and remove the old Esc pause**

In `src/ccagent.prg`, `CC_AgentRun`:

(a) After the `nMax := ...` / `hUsage := {=>}` lines and before `DO WHILE nIter < nMax`, add a local for the check (extend the existing `LOCAL` line to include `bInterrupt`):

```harbour
   bInterrupt := iif( hb_HHasKey( hOpts, "interrupt_check" ) .AND. ;
                      ValType( hOpts[ "interrupt_check" ] ) == "B", ;
                      hOpts[ "interrupt_check" ], NIL )
```

(b) At the very top of the `DO WHILE nIter < nMax` body — before `nIter++` — add the loop-level check:

```harbour
   DO WHILE nIter < nMax
      IF bInterrupt != NIL .AND. Eval( bInterrupt )
         hResult[ "stop_reason" ] := "interrupted"
         EXIT
      ENDIF
      nIter++
```

(c) Replace the entire per-tool Esc block. The current code, inside `FOR EACH tc IN hChat[ "tool_calls" ]`, starts with `IF CCCON_PeekEsc()` and runs the `DO WHILE .T.` pause prompt (Enter / `c` / `a`) through to its closing `ENDIF` just before `CC_Emit( bOnEvent, { "type" => "tool_call", ... } )`. Delete that whole `IF CCCON_PeekEsc() ... ENDIF` block and put this in its place:

```harbour
      FOR EACH tc IN hChat[ "tool_calls" ]
         // honour an interruption requested mid-turn
         IF bInterrupt != NIL .AND. Eval( bInterrupt )
            hResult[ "stop_reason" ] := "interrupted"
            EXIT
         ENDIF
         CC_Emit( bOnEvent, { "type" => "tool_call", "id" => tc[ "id" ], ;
                                   "name" => tc[ "name" ], ;
                                   "arguments" => tc[ "arguments" ] } )
```

(d) After the `FOR EACH ... NEXT` tool loop, the existing code has `IF hResult[ "stop_reason" ] == "paused"` / `EXIT` / `ENDIF`. Change that condition so an interruption also breaks the outer loop:

```harbour
      IF hResult[ "stop_reason" ] == "paused" .OR. ;
         hResult[ "stop_reason" ] == "interrupted"
         EXIT
      ENDIF
```

The `"paused"` branch and the `cRes`/`CCREPL_ReadLine`/`CCUI_PausePrompt` machinery are no longer reachable from the deleted block; leave the rest of the function (the `paused` handling at the end) intact — `paused` is simply never set now, which is harmless.

When the loop exits with `stop_reason => "interrupted"`, the function continues to its normal tail: `hResult[ "success" ] := .T.`, `messages := aMsgs` (the partial history is kept — spec requirement), `iterations`, `usage`, `content`. No change needed there.

- [ ] **Step 4: Build and run the test runner to verify it PASSES**

Expected: the three `agent: interrupt …` assertions pass; `pass: N   fail: 0`; no regressions.

- [ ] **Step 5: Commit**

```
git add src/ccagent.prg tests/test_agent.prg
git commit -m "feat: CC_AgentRun honours an interrupt_check; drop the Esc pause prompt"
```
End the commit body with: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

---

## Task 4: ccprompt.prg — console I/O (scroll region, poll, redraw)

**Files:**
- Modify: `src/ccprompt.prg`

This task adds the console-facing functions. They cannot be unit-tested (no console in the test runner); they are verified by `build.bat` and the Task 5 manual smoke test. Keep them in `ccprompt.prg`, after the pure logic from Task 1.

- [ ] **Step 1: Add the console I/O functions**

Append to `src/ccprompt.prg`:

```harbour
// Writes a string straight to stdout, bypassing CCREPL_Out (which strips CR
// and rewrites LF). Needed for absolute cursor positioning.
STATIC FUNCTION CCPROMPT_Raw( cText )
   FWrite( hb_GetStdOut(), cText )
   RETURN NIL

// Activates the pinned box: sets the VT scroll region to rows 1..scroll_bottom
// so agent output scrolls above the box, parks the cursor at the bottom of
// that region, and draws the (empty) box. No-op when the region is inactive
// (small console / fallback).
FUNCTION CCPROMPT_Activate( oPrompt )
   LOCAL hReg := oPrompt[ "region" ]
   IF !hReg[ "active" ]
      RETURN oPrompt
   ENDIF
   // ESC[1;<bottom>r  -> set scroll region; cursor then homes to (1,1)
   CCPROMPT_Raw( Chr(27) + "[1;" + LTrim( Str( hReg[ "scroll_bottom" ] ) ) + "r" )
   // park the cursor on the last row of the scroll region
   CCPROMPT_Raw( Chr(27) + "[" + LTrim( Str( hReg[ "scroll_bottom" ] ) ) + ";1H" )
   CCPROMPT_Redraw( oPrompt )
   RETURN oPrompt

// Restores the terminal: clears the scroll region (full screen scrollable
// again) and drops the cursor below where the box was.
FUNCTION CCPROMPT_Teardown( oPrompt )
   LOCAL hReg := oPrompt[ "region" ]
   IF !hReg[ "active" ]
      RETURN oPrompt
   ENDIF
   CCPROMPT_Raw( Chr(27) + "[r" )   // reset scroll region to the whole screen
   RETURN oPrompt

// Redraws the box on the bottom three rows: top frame, the editor line, the
// bottom frame. Recomputes the region from a fresh CCCON_Size() so a resize
// is picked up. Cursor is saved and restored around the draw.
FUNCTION CCPROMPT_Redraw( oPrompt )
   LOCAL hReg, hW, hSz
   hSz := CCCON_Size()
   oPrompt[ "region" ] := CCPROMPT_Region( hSz[ "rows" ], hSz[ "cols" ] )
   hReg := oPrompt[ "region" ]
   IF !hReg[ "active" ]
      RETURN oPrompt
   ENDIF
   hW := CCIN_Window( oPrompt[ "editor" ], CCUI_InputInnerWidth() )
   CCPROMPT_Raw( ;
      Chr(27) + "[s" + ;                                            // save cursor
      Chr(27) + "[" + LTrim( Str( hReg[ "box_top" ] ) ) + ";1H" + ; // to box row 1
      CCUI_FrameTop() + Chr(13) + Chr(10) + ;
      CCUI_InputBoxLine( hW[ "text" ] ) + Chr(13) + Chr(10) + ;
      CCUI_FrameBottom() + ;
      Chr(27) + "[u" )                                              // restore cursor
   RETURN oPrompt

// Non-blocking: drains every pending key into the editor, then redraws the
// box. On Enter the buffer is classified; on Esc an interrupt is recorded.
// Returns an action string: "none", "queued", or "interrupt".
FUNCTION CCPROMPT_Poll( oPrompt )
   LOCAL oEd := oPrompt[ "editor" ], nKey, hC, cAction := "none"
   DO WHILE CCCON_KeyPending()
      nKey := CCCON_ReadKey()
      DO CASE
      CASE nKey == -13                       // Esc -> interrupt, no message
         oPrompt[ "interrupt" ] := { "kind" => "esc", "text" => "" }
         cAction := "interrupt"
      CASE nKey == -1                        // Enter -> classify the buffer
         hC := CCPROMPT_Classify( oEd[ "buf" ] )
         DO CASE
         CASE hC[ "action" ] == "empty"
            // ignore
         CASE hC[ "action" ] == "btw"
            oPrompt[ "interrupt" ] := { "kind" => "btw", "text" => hC[ "text" ] }
            cAction := "interrupt"
         OTHERWISE
            CCPROMPT_Enqueue( oPrompt, hC[ "text" ] )
            cAction := "queued"
         ENDCASE
         oPrompt[ "editor" ] := CCIN_New( "" )
         oEd := oPrompt[ "editor" ]
      CASE nKey == -2 ; CCIN_Backspace( oEd )
      CASE nKey == -3 ; CCIN_Left( oEd )
      CASE nKey == -4 ; CCIN_Right( oEd )
      CASE nKey == -5 ; CCIN_Home( oEd )
      CASE nKey == -6 ; CCIN_End( oEd )
      CASE nKey == -7 ; CCIN_Delete( oEd )
      CASE nKey == -11 ; CCIN_Insert( oEd, Chr(10) )   // Shift+Enter -> newline
      CASE nKey > 0 ; CCIN_Insert( oEd, CCIN_Utf8Chr( nKey ) )
      // other keys (Tab, Up, Down, Ctrl+C, unmapped) are ignored mid-prompt
      ENDCASE
      IF cAction == "interrupt"
         EXIT   // stop draining once an interrupt is seen
      ENDIF
   ENDDO
   CCPROMPT_Redraw( oPrompt )
   RETURN cAction
```

Note for the implementer: `CCIN_New`, `CCIN_Insert`, `CCIN_Backspace`, `CCIN_Delete`, `CCIN_Left`, `CCIN_Right`, `CCIN_Home`, `CCIN_End`, `CCIN_Window`, `CCIN_Utf8Chr` are existing public functions in `src/ccinput.prg`; `CCUI_FrameTop`, `CCUI_FrameBottom`, `CCUI_InputBoxLine`, `CCUI_InputInnerWidth` are existing public functions in `src/ccui.prg`. The editor state hash has a `"buf"` key (the text). Do not reimplement any of them.

- [ ] **Step 2: Build cc.exe to verify it compiles**

Run `build.bat`. Expected: `Build OK -> cc.exe`.

- [ ] **Step 3: Build and run the test runner**

Expected: `pass: N   fail: 0` — the Task 1 `prompt:` tests still pass; the new functions are not unit-tested but the test build compiles `ccprompt.prg`.

- [ ] **Step 4: Commit**

```
git add src/ccprompt.prg
git commit -m "feat: ccprompt console I/O — scroll region, poll, redraw"
```
End the commit body with: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

---

## Task 5: Wire the persistent prompt into the REPL

**Files:**
- Modify: `src/ccrepl.prg`

`src/ccrepl.prg` is not in the test build; this task is verified by `build.bat` and a manual smoke test. The REPL keeps its existing fallback path for non-VT / piped input unchanged.

- [ ] **Step 1: Add a prompt-driven input helper**

In `src/ccrepl.prg`, add a new static function (place it near `CCREPL_RunTurn`). It owns the persistent box for the interactive VT path: it idles, polling the prompt, until the user submits something, and returns the submitted line. It also exposes the live `oPrompt` so the turn loop can poll it.

```harbour
// Idles on the persistent box until the user submits a line (Enter on a
// non-empty buffer, or a /btw line). Returns the submitted text. The
// classification (queue vs btw) is irrelevant while idle — any submission
// starts a turn — so the raw buffer text is returned.
STATIC FUNCTION CCREPL_PromptIdle( oPrompt )
   LOCAL cAction
   DO WHILE .T.
      cAction := CCPROMPT_Poll( oPrompt )
      IF cAction == "queued"
         RETURN CCPROMPT_Dequeue( oPrompt )
      ELSEIF cAction == "interrupt"
         // a /btw or Esc submitted while idle: btw carries the text,
         // Esc (empty) just loops again
         IF oPrompt[ "interrupt" ][ "kind" ] == "btw" .AND. ;
            !Empty( oPrompt[ "interrupt" ][ "text" ] )
            cAction := oPrompt[ "interrupt" ][ "text" ]
            oPrompt[ "interrupt" ] := NIL
            RETURN cAction
         ENDIF
         oPrompt[ "interrupt" ] := NIL
      ENDIF
      hb_IdleSleep( 0.02 )
   ENDDO
   RETURN NIL
```

- [ ] **Step 2: Rework `CCREPL_Run` to drive the persistent prompt**

The interactive VT branch of `CCREPL_Run` currently calls `CCIN_ReadLine`. Replace the loop so that, when on a VT console (`CCCON_HasConsole() .AND. CCUI_ColorOn()`), it uses a persistent `oPrompt`:

- Build `oPrompt := CCPROMPT_New()` and `CCPROMPT_Activate( oPrompt )` once, after the banner, before the `DO WHILE .T.` loop.
- In the loop, get the next message from `CCREPL_PromptIdle( oPrompt )` instead of `CCIN_ReadLine`. The non-VT / no-console branch keeps `CCREPL_ReadLine` (cooked) exactly as today.
- Pass the prompt into `CCREPL_RunTurn` so the agent's `bOnEvent` callback can poll it; `CCREPL_RunTurn` gains an `oPrompt` parameter and passes `"interrupt_check" => {|| CCPROMPT_Interrupted( oPrompt ) }` into `CC_AgentRun`, and its render callback also calls `CCPROMPT_Poll( oPrompt )` each event.
- After a turn returns:
  - if `oPrompt[ "interrupt" ]` is a `btw` with text → that text becomes the next message immediately (set it as the line to process, clear `interrupt`);
  - if `interrupt` is `esc` (or btw with empty text) → clear `interrupt`, return to idle;
  - else (natural end) → after handling, while `CCPROMPT_Dequeue( oPrompt )` returns non-NIL, process each queued message as another turn.
- On loop exit, call `CCPROMPT_Teardown( oPrompt )`.

Concretely, change `CCREPL_RunTurn`'s signature and its `CC_AgentRun` options. Current:

```harbour
STATIC FUNCTION CCREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, aMessages )
   LOCAL hRes, oRender
   oRender := CCREPL_RenderNew()
   hRes := CC_AgentRun( oClient, aMessages, ;
      { "model" => cModel, ;
        "tools" => CCTOOLS_Schemas( oReg ), ;
        "tool_executor" => bGate, ;
        "max_iterations" => nMaxIter }, ;
      {| hEv | CCREPL_RenderEv( hEv, oRender ) } )
```

becomes:

```harbour
STATIC FUNCTION CCREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, aMessages, oPrompt )
   LOCAL hRes, oRender, hOpts
   oRender := CCREPL_RenderNew()
   hOpts := { "model" => cModel, ;
              "tools" => CCTOOLS_Schemas( oReg ), ;
              "tool_executor" => bGate, ;
              "max_iterations" => nMaxIter }
   IF oPrompt != NIL
      hOpts[ "interrupt_check" ] := {|| CCPROMPT_Interrupted( oPrompt ) }
   ENDIF
   hRes := CC_AgentRun( oClient, aMessages, hOpts, ;
      {| hEv | CCREPL_RenderEv( hEv, oRender ), ;
               iif( oPrompt != NIL, CCPROMPT_Poll( oPrompt ), NIL ) } )
```

All existing `CCREPL_RunTurn(...)` call sites must pass the new `oPrompt` argument (the VT path passes the live prompt; the cooked path passes `NIL`). The `max_iterations` resume call inside `CCREPL_Run` also gets the `oPrompt` argument.

When `bOnEvent` is a codeblock that evaluates two expressions, the block must use the comma form shown above so both run; `CCREPL_RenderEv`'s return value is what callers expect, so keep it as the first expression. (A codeblock returns its last expression — here `CCPROMPT_Poll`'s result or `NIL` — which `CC_AgentRun`'s `CC_Emit` ignores, so this is safe.)

- [ ] **Step 3: Handle interrupt and queue draining after a turn**

In `CCREPL_Run`, in the `message`/`init` case, after the turn (and the existing `max_iterations` resume loop) completes, add — for the VT path only (`oPrompt != NIL`):

```harbour
         // a /btw interrupt carries the next message; an Esc interrupt just
         // returns to idle. Then drain any messages queued during the turn.
         DO WHILE oPrompt != NIL
            IF CCPROMPT_Interrupted( oPrompt )
               cMsg := iif( oPrompt[ "interrupt" ][ "kind" ] == "btw", ;
                            oPrompt[ "interrupt" ][ "text" ], "" )
               oPrompt[ "interrupt" ] := NIL
            ELSE
               cMsg := hb_CStr( CCPROMPT_Dequeue( oPrompt ) )
            ENDIF
            IF Empty( cMsg )
               EXIT
            ENDIF
            CCREPL_Out( CCUI_Color( "[handling: " + ;
                        CCUI_Summarize( cMsg, 60 ) + "]", "90" ) + Chr(10) )
            aTurn := AClone( aMsgs )
            AAdd( aTurn, { "role" => "user", "content" => cMsg } )
            hTurn := CCREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, aTurn, oPrompt )
            hRes  := hTurn[ "result" ]
            IF hRes[ "success" ]
               aMsgs := hRes[ "messages" ]
            ENDIF
         ENDDO
```

Place this immediately after the existing `IF hRes[ "success" ] ... ELSE ... ENDIF` block that reports the turn outcome, still inside the `message`/`init` `CASE`. (`CCUI_Summarize` is an existing `ccui.prg` function — first line, truncated. `aTurn`, `hTurn`, `cMsg`, `hRes`, `aMsgs` are already locals of `CCREPL_Run`.)

When a plain message is submitted mid-turn it is enqueued by `CCPROMPT_Poll`; this drain loop processes the queue once the current turn ends. A `[queued: …]` notice is shown when the message is enqueued — add that to `CCPROMPT_Poll`'s `"queued"` branch is NOT done there (it has no console-format dependency); instead, emit it from the render callback is unnecessary. Keep it simple: the `[handling: …]` line above is the only notice. (YAGNI — no separate queued notice.)

- [ ] **Step 4: Build cc.exe**

Run `build.bat`. Expected: `Build OK -> cc.exe`.

- [ ] **Step 5: Build and run the test runner**

Expected: `pass: N   fail: 0`. `ccrepl.prg` is not in the test build, so this only confirms the rest of the suite still passes.

- [ ] **Step 6: Manual smoke test**

Run `cc.exe` in a real terminal with `DEEPSEEK_API_KEY` set. Verify:
1. The input box is drawn at the bottom and stays there.
2. Ask the agent something that takes a while (e.g. "list and read three files"). While it works, type a few characters — they appear in the box.
3. Press `Enter` on a plain message mid-turn — it is queued; after the current turn ends, the `[handling: …]` line appears and the queued message is answered.
4. Type `/btw stop and just say hi` + `Enter` mid-turn — the turn is interrupted and the `/btw` text is answered next.
5. Press `Esc` mid-turn — the turn stops and control returns to the box.
6. Run in a redirected / piped context (`echo hi | cc.exe`) — the cooked fallback path still works, no scroll-region escape codes leak.

Report the smoke-test results.

- [ ] **Step 7: Commit**

```
git add src/ccrepl.prg
git commit -m "feat: persistent always-visible prompt with mid-turn queue and interrupt"
```
End the commit body with: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

---

## Task 6: Documentation

**Files:**
- Modify: `pages/commands.md`, `README.md`

- [ ] **Step 1: Document the behaviour**

In `pages/commands.md`, in the key-bindings / input section, add that:
- the input box is always visible, including while the agent works;
- a message submitted with `Enter` while the agent is working is queued and answered after the current turn;
- a line starting with `/btw ` interrupts the current turn and is answered immediately;
- `Esc` interrupts the current turn.

In `README.md`, update the "Key bindings (raw-mode input box)" table: change the `Ctrl+C` / `Esc` rows to reflect that `Esc` now interrupts the running turn, and add a row noting `/btw <text>` interrupts with a message. Match the existing table style.

- [ ] **Step 2: Commit**

```
git add pages/commands.md README.md
git commit -m "docs: document the always-visible prompt, mid-turn queue and /btw"
```
End the commit body with: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

---

## Self-review notes

- **Spec coverage:** `ccprompt.prg` pure logic + queue (T1); `CCCON_Size`/`CCCON_KeyPending`/Esc (T2); `interrupt_check` + removal of the old Esc pause (T3); console I/O — scroll region, poll, redraw, activate, teardown (T4); REPL integration — persistent box, per-event poll, `/btw`/Esc handling, queue drain, fallback preserved (T5); docs (T6). Every spec section maps to a task.
- **Placeholder scan:** no TBD/TODO. T2, T4, T5 console code is verified by `build.bat` + a manual smoke test because the test runner has no console — this is stated explicitly, not a placeholder. The pure logic (T1) and the agent change (T3) are fully TDD-tested.
- **Type consistency:** `oPrompt` is the hash `{ editor, queue, interrupt, region }` throughout; `region` is `{ rows, cols, active, scroll_bottom, box_top }` from `CCPROMPT_Region`; `interrupt` is `NIL` or `{ kind, text }` with `kind` in `"esc"`/`"btw"`. `CCPROMPT_Classify` returns `{ action, text }` with `action` in `"empty"`/`"btw"`/`"queue"`; `CCPROMPT_Poll` returns `"none"`/`"queued"`/`"interrupt"`. `CC_AgentRun`'s new option is `interrupt_check` (a codeblock); the new `stop_reason` is `"interrupted"`. `CCREPL_RunTurn` gains a trailing `oPrompt` parameter, `NIL` on the cooked path. These names are used consistently across tasks.
- **Risk:** Task 5 (scroll-region interleaving) is the integration risk and is covered by the manual smoke test in Step 6, including the piped-fallback check.

# Rotating Tips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface short usage tips in CCHarbour — one random tip on the startup banner, and a tip cycling sequentially on each return to the idle prompt.

**Architecture:** A hardcoded tip pool plus two pure helpers live in `src/ccui.prg` and are unit-tested. The banner consumes one tip; `src/ccrepl.prg` holds a `STATIC` cycle counter and prints one tip per idle. No new files.

**Tech Stack:** Harbour 3.2, the project's `T_Equal`/`T_Assert` test harness, ANSI colour.

---

## Background — conventions an implementer needs

- **Building tests (Windows):** run `cmd /c "tests\build_tests.bat"` via the PowerShell tool from the repo root (it sets up the Visual Studio environment). Then run `cd C:\CCHarbour\tests; .\run_tests.exe`. The last line reads `pass: N   fail: M`. Baseline before this plan: `pass: 403   fail: 0`.
- **Building the app (Windows):** run `cmd /c ".\build.bat"` via the PowerShell tool. Exit 0 and `Build OK -> cc.exe` means success.
- **Test harness:** `tests/test_ui.prg` defines `Test_UI()`; `T_Equal( actual, expected, name )` and `T_Assert( cond, name )` record pass/fail. `Test_UI` declares its `LOCAL`s at the top of the function — add any new ones there.
- **Colour:** `CCUI_Color( cText, cSGR )` wraps text in an SGR escape, or returns it unchanged when colour is off (the default in the test build). `CCUI_Pal( "dim" )` returns the dim-grey SGR code.
- **Banner cells:** `CCUI_Cell( cText, cAlign, cSGR )` builds a `{text,align,sgr}` hash; the banner's right panel is an array of these.
- **Harbour notes:** `%` (modulo) follows the sign of the dividend, so `( -1 ) % 7` is `-1`, not `6` — negative results must be normalised. `hb_Random( nMax )` returns a float in `0 .. nMax`. `++nVar` increments and yields the new value.

---

## Task 1: Tip pool and pure helpers

**Files:**
- Modify: `src/ccui.prg` (add three functions near `CCUI_Version`, around line 465)
- Test: `tests/test_ui.prg` (add assertions inside `Test_UI`)

- [ ] **Step 1: Write the failing tests**

Add inside `Test_UI()` in `tests/test_ui.prg`, before its final `RETURN`. Add `aTips, cTipLn` to the `LOCAL` list at the top of `Test_UI`:

```harbour
   // --- CCUI_Tips / CCUI_TipAt ---
   aTips := CCUI_Tips()
   T_Equal( ValType( aTips ), "A", "ui: tips pool is an array" )
   T_Assert( Len( aTips ) > 0, "ui: tips pool is non-empty" )
   T_Equal( ValType( CCUI_TipAt( 1 ) ), "C", "ui: tip at index is a string" )
   T_Equal( CCUI_TipAt( 1 ), CCUI_TipAt( Len( aTips ) + 1 ), ;
            "ui: tip index wraps past the end" )
   T_Equal( CCUI_TipAt( 0 ), CCUI_TipAt( Len( aTips ) ), ;
            "ui: tip index 0 wraps to the last" )
   T_Assert( CCUI_TipAt( 999 ) $ ArrayToStr( aTips ), ;
             "ui: a large tip index still maps into the pool" )

   // --- CCUI_TipLine ---
   cTipLn := CCUI_TipLine( "hello world" )
   T_Assert( "Tip: hello world" $ cTipLn, "ui: tip line shows Tip: prefix and text" )
   T_Assert( Right( cTipLn, 1 ) == Chr(10), "ui: tip line ends in LF" )
```

Add this helper function to the top of `tests/test_ui.prg` (above `FUNCTION Test_UI`), used only by the test above to flatten the pool for a membership check:

```harbour
STATIC FUNCTION ArrayToStr( aArr )
   LOCAL cOut := "", x
   FOR EACH x IN aArr
      cOut += hb_CStr( x ) + Chr(10)
   NEXT
   RETURN cOut
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cmd /c "tests\build_tests.bat"` then `cd C:\CCHarbour\tests; .\run_tests.exe`
Expected: build/link error or `FAIL` lines — `CCUI_Tips`, `CCUI_TipAt`, `CCUI_TipLine` do not exist yet.

- [ ] **Step 3: Add the implementation**

Add to `src/ccui.prg`, immediately after the `CCUI_Version` function (after its `RETURN` near line 465):

```harbour
// The pool of short usage tips shown on the banner and at the idle prompt.
FUNCTION CCUI_Tips()
   RETURN { ;
      "Use /clear to start fresh when switching topics", ;
      "Press Esc to interrupt the agent mid-turn", ;
      "Type /btw <note> to add context without interrupting", ;
      "/init writes a CC.md so the agent learns project conventions", ;
      "/cost shows token usage and estimated spend", ;
      "/save and /load keep conversations across sessions", ;
      "Edit per-tool permissions in .ccharbour/settings.json" }

// Returns the tip at a 1-based index, wrapping modulo the pool length so any
// integer -- including 0 and values past the end -- maps to a valid tip.
FUNCTION CCUI_TipAt( nIndex )
   LOCAL aTips := CCUI_Tips()
   LOCAL nMod  := ( nIndex - 1 ) % Len( aTips )
   IF nMod < 0
      nMod += Len( aTips )
   ENDIF
   RETURN aTips[ nMod + 1 ]

// Formats one tip as a dim-coloured "Tip: <text>" line ending in LF.
FUNCTION CCUI_TipLine( cTip )
   RETURN CCUI_Color( "Tip: " + hb_CStr( cTip ), CCUI_Pal( "dim" ) ) + Chr(10)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cmd /c "tests\build_tests.bat"` then `cd C:\CCHarbour\tests; .\run_tests.exe`
Expected: all new `ok   - ui: tip...` lines, `fail: 0`.

- [ ] **Step 5: Commit**

```bash
git add src/ccui.prg tests/test_ui.prg
git commit -m "feat: add CCUI_Tips pool and tip helpers"
```

---

## Task 2: Banner tip line

**Files:**
- Modify: `src/ccui.prg` (one line inside `CCUI_Banner`'s right-panel block)
- Test: `tests/test_ui.prg`

- [ ] **Step 1: Write the failing test**

Add inside `Test_UI()` in `tests/test_ui.prg`. Add `cBanTip` to the `LOCAL` list:

```harbour
   // --- banner shows a rotating tip, not the old static /init line ---
   cBanTip := CCUI_Banner( "m", "c", "u" )
   T_Assert( "Tip: " $ cBanTip, "ui: banner shows a Tip line" )
   T_Assert( !( "Run /init to create a CC.md file" $ cBanTip ), ;
             "ui: banner no longer shows the static /init line" )
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cmd /c "tests\build_tests.bat"` then `cd C:\CCHarbour\tests; .\run_tests.exe`
Expected: `FAIL - ui: banner shows a Tip line` and `FAIL - ui: banner no longer shows the static /init line` — the banner still has the old static line.

- [ ] **Step 3: Replace the static /init line with a tip line**

In `src/ccui.prg`, inside `CCUI_Banner`, find this line in the right-panel block:

```harbour
   AAdd( aRight, CCUI_Cell( "Run /init to create a CC.md file", "L", "" ) )
```

Replace it with:

```harbour
   AAdd( aRight, CCUI_Cell( "Tip: " + ;
         CCUI_TipAt( Int( hb_Random( Len( CCUI_Tips() ) ) ) + 1 ), "L", "" ) )
```

This picks a random tip when the banner is built. `CCUI_TipAt` wraps, so even if `hb_Random` returns its maximum and the index lands one past the end, it maps to a valid tip. The right panel still has nine rows, so the two-panel alignment is unchanged.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cmd /c "tests\build_tests.bat"` then `cd C:\CCHarbour\tests; .\run_tests.exe`
Expected: both new `ok   - ui: banner...` lines, `fail: 0`.

- [ ] **Step 5: Commit**

```bash
git add src/ccui.prg tests/test_ui.prg
git commit -m "feat: show a random tip on the startup banner"
```

---

## Task 3: Idle tip line in the REPL

**Files:**
- Modify: `src/ccrepl.prg` (add a `STATIC`; add one line before `CCREPL_PromptIdle` is called)

This task touches the REPL's main loop, which is not exercised by the test suite. It is verified by building the app and a manual run.

- [ ] **Step 1: Add the cycle-counter STATIC**

In `src/ccrepl.prg`, near the other module-level `STATIC` declarations at the top of the file (around lines 5-16, e.g. next to `STATIC s_oBoxPrompt := NIL`), add:

```harbour
STATIC s_nTipIdx := 0
```

- [ ] **Step 2: Print a tip on each idle return**

In `src/ccrepl.prg`, in `CCREPL_Run`, find where the idle prompt is read in box mode:

```harbour
      IF oPrompt != NIL
         cLine := CCREPL_PromptIdle( oPrompt )
```

Replace those two lines with:

```harbour
      IF oPrompt != NIL
         CCREPL_Out( CCUI_TipLine( CCUI_TipAt( ++s_nTipIdx ) ) )
         cLine := CCREPL_PromptIdle( oPrompt )
```

Each time the prompt returns to idle in box mode, `s_nTipIdx` advances and one dim `Tip: ...` line is printed into the scroll region above the box. `CCUI_TipAt` wraps, so the tips cycle sequentially. The cooked / piped path (`oPrompt == NIL`) is left untouched — no tips there.

- [ ] **Step 3: Build the app**

Run: `cmd /c ".\build.bat"`
Expected: build succeeds, `Build OK -> cc.exe`.

- [ ] **Step 4: Manual verification**

Run `cc.exe`. Confirm: the startup banner shows a `Tip: ...` line in the right panel. A dim `Tip: ...` line appears above the input box on first idle. Send a message; when the turn finishes and the prompt returns to idle, a *different* tip is shown. Repeated turns cycle through the pool in order and wrap around.

- [ ] **Step 5: Commit**

```bash
git add src/ccrepl.prg
git commit -m "feat: cycle a tip on each idle prompt"
```

---

## Self-Review notes

- **Spec coverage:** tip pool + `CCUI_TipAt` + `CCUI_TipLine` → Task 1. Banner tip → Task 2. Idle tip line + `s_nTipIdx` → Task 3. Every spec section maps to a task.
- **Type consistency:** `CCUI_Tips()` returns an array of strings; `CCUI_TipAt( nIndex )` returns one string; `CCUI_TipLine( cTip )` returns a string. The banner and the REPL both consume `CCUI_TipAt`; the REPL also consumes `CCUI_TipLine`. Names and signatures are consistent across all three tasks.
- **Modulo edge case:** `CCUI_TipAt` normalises a negative `%` result, so index 0 and negative indices map correctly — covered by a Task 1 test.

# Permissions and Config — Design (Sub-project #5)

Date: 2026-05-16
Status: Approved for planning
Language: Harbour (MT build, hbmk2)
Depends on: #3 (`DSTools_Executor`), #4 (`dsrepl.prg` wiring). Produced
artifacts plug into #2 (`DS_AgentRun`).

## Context

Sub-project #5 of a Claude Code-style agentic client in Harbour. Sub-projects
#1–#4 produced a working `cc.exe`, but every tool runs unguarded — `shell`,
`write` and `edit` execute whatever the model asks. #5 adds a permission gate
and a settings file.

The gate sits on the existing executor seam: `DSPerm_Gate` wraps the raw
executor from #3 and returns a new executor with the identical
`{|cName,cArgsJson|->cString}` contract, so #2/#4 plug it in unchanged. Each
tool has a mode — `allow`, `deny`, or `ask` — read from `settings.json` with
safe built-in defaults.

## Architecture

Two new modules, both pure (no I/O beyond `dssettings` reading one file):

```
src/dssettings.prg   Load and default the settings.json file
src/dsperm.prg       The permission gate (wraps an executor)
tests/test_settings.prg   Unit tests for dssettings
tests/test_perm.prg       Unit tests for dsperm
```

Modified: `src/dsrepl.prg` (wires settings + gate into `Main`), `cc.hbp` (adds
the two source files), `tests/tests.hbp` and `tests/run_tests.prg` (add the
tests).

Layers stay clean: `dsperm` knows nothing of concrete tools — it wraps any
executor; `dssettings` knows nothing of runtime permission decisions — it only
produces data; `dsrepl` orchestrates. `dsconfig` (#1) is untouched: it still
resolves the API key. `dssettings` resolves everything else.

### dssettings.prg API (pure)

```
DSSettings_Defaults()    -> hSettings    the built-in default hash
DSSettings_Load( cPath ) -> hSettings    file values merged over the defaults
```

`hSettings` shape:

```
{ "model"          => "deepseek-chat",
  "base_url"       => "https://api.deepseek.com",
  "max_iterations" => 25,
  "permissions"    => { "read"  => "allow", "glob" => "allow", "grep" => "allow",
                        "write" => "ask",   "edit" => "ask",   "shell" => "ask" } }
```

`DSSettings_Load`:
- `cPath` omitted/empty -> resolve in order: env `CCHARBOUR_CONFIG`, else
  `.ccharbour/settings.json` under the current directory.
- File absent -> return the pure defaults.
- File present -> decode JSON; merge top-level keys over the defaults; the
  `permissions` sub-hash is merged per tool, so a file that sets only
  `shell` still keeps the default modes for the other tools.
- Malformed JSON (decode does not yield a hash) -> ignore the file, return the
  pure defaults. Never throws.

### dsperm.prg API (pure)

```
DSPerm_Gate( bInner, hPermissions, bAsk ) -> bGated
```

- `bInner` — the raw executor from #3, `{|cName,cArgsJson|->cString}`.
- `hPermissions` — a hash `{ toolName => "allow"|"deny"|"ask" }`. The gate works
  on its own copy and never mutates the caller's hash.
- `bAsk` — an injectable codeblock `{|cName,cArgsJson|->"y"|"n"|"a"}`. May be
  `NIL`.
- `bGated` — a new executor with the same contract; plugs into
  `DS_AgentRun`'s `hOpts["tool_executor"]` exactly where the raw one did.

## Gate Flow

`bGated`, per call `(cName, cArgsJson)`:

```
1. cMode := hPerm[cName] if present, else "ask"      // safe default
   if cMode not in {allow,deny,ask} -> cMode := "ask" // unknown value -> ask
2. DO CASE
   CASE cMode == "allow"
      RETURN Eval( bInner, cName, cArgsJson )

   CASE cMode == "deny"
      RETURN "Error: tool '<cName>' denied by policy"

   CASE cMode == "ask"
      cAns := iif( bAsk == NIL, "n", normalised Eval( bAsk, cName, cArgsJson ) )
      DO CASE
      CASE cAns == "y"  -> RETURN Eval( bInner, cName, cArgsJson )
      CASE cAns == "a"  -> hPerm[cName] := "allow"   // session upgrade
                           RETURN Eval( bInner, cName, cArgsJson )
      OTHERWISE         -> RETURN "Error: tool '<cName>' denied by user"
      ENDCASE
   ENDCASE
```

- `hPerm` is the gate's own copy. `"a"` mutates that copy, so later calls to the
  same tool in the session pass straight through without asking again.
- The answer from `bAsk` is normalised: trimmed, lower-cased, first character
  taken. Anything that is not `y` or `a` is a deny.
- `bAsk == NIL` makes `ask` behave as deny — a gate with no UI fails closed.
- A deny returns an error string as the tool result. It enters the conversation
  (the error-as-tool-result rule from #2); the model sees it and can adapt. The
  agent loop never aborts on a permission decision.
- `bInner` already traps its own errors (#3); the gate adds no `BEGIN SEQUENCE`
  — it only decides allow/deny.

### Wiring in dsrepl.prg

`Main` builds the settings and the gated executor:

```
hSet    := DSSettings_Load()
oClient := DS_Client( { "model" => hSet["model"], "base_url" => hSet["base_url"] } )
oReg    := DSTools_Registry()
bAsk    := {| cName, cArgs | DSREPL_AskPerm( cName, cArgs ) }
bGate   := DSPerm_Gate( DSTools_Executor( oReg ), hSet["permissions"], bAsk )
```

`DSREPL_Run` then passes `bGate` as `hOpts["tool_executor"]` and
`hSet["max_iterations"]` as `hOpts["max_iterations"]` to `DS_AgentRun`.
`DSREPL_AskPerm` prints `Tool '<name>' wants to run: <args>. Allow? [y/n/a]`,
reads one line, and returns its first character. It is wrapped so it never
throws.

## Error Handling

**dssettings.prg:**
- File absent -> pure defaults. Not an error.
- Malformed JSON (decode does not yield a hash) -> ignore the file, return pure
  defaults. Never throws.
- Partial keys -> each missing key takes its default; a partial `permissions`
  sub-hash is merged per tool.
- Wrong-typed value (e.g. `max_iterations` as a string) -> loaded as is; the
  consumer (#2) already validates the type and falls back to its own default.

**dsperm.prg:**
- Invalid mode value (e.g. `"maybe"`) -> treated as `ask` (fails safe).
- `bAsk` returns something odd (NIL, a number) -> normalisation treats it as a
  deny (fails closed).
- `bAsk` throwing is the callback's bug, not the gate's — the gate does not trap
  it; `dsrepl`'s `DSREPL_AskPerm` is written so it never throws.
- Unknown `cName` -> default mode `ask`; on `y`/`a` it reaches `bInner`, which
  returns `"Error: unknown tool ..."` (#3). No double handling.

**Safety rule:** the gate always fails closed — any doubt resolves to deny or
ask, never to allow. No `bAsk` -> deny. Invalid mode -> ask. Ambiguous answer
-> deny.

**dsrepl.prg:** `Main` already runs `DSREPL_Run` inside a `BEGIN SEQUENCE` (#4);
an unforeseen exception prints a short trace and exits 1.

## Testing

`dssettings` and `dsperm` are pure and unit-tested. Reuses the #1–#4 harness:
`tests/run_tests.prg` (`T_Assert` / `T_Equal`), new `Test_Settings()` and
`Test_Perm()` entry points, and new `tests/test_settings.prg` /
`tests/test_perm.prg`.

**Test_Settings:**
- `DSSettings_Defaults()` has `model`, `base_url`, `max_iterations`, and a
  `permissions` hash covering all six tools.
- `DSSettings_Load()` with a non-existent path returns the defaults.
- A temp JSON file overriding `model` and one permission: the result takes
  `model` from the file, keeps the other top-level keys at their defaults, and
  the `permissions` hash keeps the default modes for tools the file did not
  mention while applying the file's override.
- A malformed JSON file -> the defaults.

**Test_Perm** (using codeblocks that close over counters to observe whether
`bInner` / `bAsk` were called):
- `allow` mode -> `bInner` is called, its result is returned.
- `deny` mode -> `"... denied by policy"`, `bInner` is not called.
- `ask` with `bAsk` -> `"y"` -> `bInner` is called.
- `ask` with `bAsk` -> `"n"` -> `"... denied by user"`, `bInner` not called.
- `ask` with `bAsk` -> `"a"` -> `bInner` is called, and a second call to the
  same tool does not invoke `bAsk` again (session upgrade; `bAsk` call count
  stays at 1).
- `bAsk == NIL` with `ask` mode -> deny (fails closed).
- An invalid mode value -> treated as `ask`.
- The caller's `hPermissions` hash is not mutated by the gate.

`dsrepl.prg` wiring is verified by a documented manual smoke test: with a
`settings.json` setting `shell` to `deny`, ask the agent to run a shell command
and observe the policy refusal; with no settings file, defaults apply and
`shell` prompts.

Build: add `test_settings.prg`, `test_perm.prg`, `../src/dssettings.prg` and
`../src/dsperm.prg` to `tests/tests.hbp`; add `Test_Settings()` and
`Test_Perm()` to the runner. Add `src/dssettings.prg` and `src/dsperm.prg` to
`cc.hbp`.

## Self-Review

- **Scope**: two pure modules plus REPL wiring — one focused implementation
  plan.
- **Decomposition honoured**: the gate wraps the existing executor seam; #3's
  tool layer and #2's loop are untouched. Argument-pattern rules and
  user-level settings files are deliberately left out (YAGNI; future
  extensions).
- **Deferred (out of scope for #5)**: argument-pattern permission rules;
  user-level / merged settings files; persisting a session `"a"` upgrade back
  to `settings.json`; MCP and hooks (#6); thread pool (#6.5).
- **Type consistency**: `hSettings` keys (`model` / `base_url` /
  `max_iterations` / `permissions`), the permission mode strings
  (`allow` / `deny` / `ask`), the gate signature
  `DSPerm_Gate( bInner, hPermissions, bAsk )`, the executor contract
  `{|cName,cArgsJson|->cString}`, and the `bAsk` contract
  `{|cName,cArgsJson|->"y"|"n"|"a"}` are used identically throughout, and the
  gated executor matches `DS_AgentRun`'s `hOpts["tool_executor"]` input from #2.
- **Placeholder scan**: no TBD / TODO; every mode, default, and error string is
  concrete.

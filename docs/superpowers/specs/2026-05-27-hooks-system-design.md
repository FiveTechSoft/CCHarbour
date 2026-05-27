# Hooks System — Design Spec

**Date:** 2026-05-27
**Status:** Draft
**Author:** Antonio Linares (co-authored with Claude)

## Problem

CCHarbour has no way to run a user-supplied side effect when a turn finishes. Users who launch long-running agent loops have to alt-tab back to the terminal to notice completion. A beep, toast, or other notify command would close the loop, but there is no extension point to wire one in. More generally, CCHarbour lacks a mechanism for users to hook into REPL lifecycle events.

## Goal

Add a minimal hooks system that fires user-defined shell commands when the current turn finishes. Scope is intentionally narrow: one event (`turn_complete`), fire-and-forget execution, env-var context. Surface a `/hook` REPL command for CRUD and a config block in `.ccharbour/settings.json` for persistence.

Non-goals (deferred):
- Other lifecycle events (`session_start`, `pre_tool_use`, etc.) — extension point but not implemented.
- Sync hooks that can abort/modify the turn.
- JSON-on-stdin context passing (Claude Code style).
- Log rotation.
- Per-hook timeout or working-directory overrides.

## Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Single event in MVP: `turn_complete` | YAGNI — solves the immediate need (notify); extending later is additive. |
| 2 | Fire-and-forget async (`hb_processOpen` detach) | REPL must not block on user shell commands. No need for exit-code handling. |
| 3 | Optional append-only log (`hooks_log: false` by default) | Debuggability without forcing disk writes when not wanted. |
| 4 | Context as env vars with `CCHARBOUR_` prefix | Simpler than JSON-on-stdin; sufficient for filtering/formatting in shell hooks. |
| 5 | Hook config as array of strings | Avoids the `{ "command": ... }` boilerplate for the 99% case. Migrating to a hybrid (string-or-object) form later stays backward compatible. |
| 6 | Fire on every turn status (success/error/interrupted), expose status via env | Notify is useful on failure too; hook can filter on `$env:CCHARBOUR_STATUS`. |
| 7 | Reload settings on every fire | Editing JSON takes effect on the next turn — no restart, no `/reload` command needed. ~1 ms cost. |
| 8 | `/hook` REPL command with full CRUD + `test` + `log` subcommands | User asked for it; CRUD avoids hand-editing JSON for common changes; `test` aids debugging. |

## Architecture

### Module layout

New module: `src/cchooks.prg`.

```harbour
// Returns the canonical list of supported events.
FUNCTION CCHOOKS_ValidEvents()      // -> { "turn_complete" }

// True if cEvent is in the canonical list.
FUNCTION CCHOOKS_IsValidEvent( cEvent )

// Fire all hooks for cEvent asynchronously.
// hContext keys: "status", "model", "tokens", "duration_ms"
FUNCTION CCHOOKS_Run( cEvent, hContext )

// Return array of hook command strings for cEvent (or all if cEvent NIL).
FUNCTION CCHOOKS_List( hSet, cEvent )

// Mutate hSet: append cCmd to hSet["hooks"][cEvent].
// Returns .T. on success, .F. on invalid event.
FUNCTION CCHOOKS_Add( hSet, cEvent, cCmd )

// Mutate hSet: remove 1-based nIdx from hSet["hooks"][cEvent].
// Returns .T. on success, .F. if event missing or idx out of range.
FUNCTION CCHOOKS_Remove( hSet, cEvent, nIdx )

// Mutate hSet: replace 1-based nIdx with cCmd.
FUNCTION CCHOOKS_Edit( hSet, cEvent, nIdx, cCmd )

// Absolute path to the log file (".ccharbour/hooks.log" by default).
FUNCTION CCHOOKS_LogPath()

// Append cLine to the log if hooks_log is enabled in settings.
FUNCTION CCHOOKS_Log( cLine )
```

### Integration points

- **`src/ccrepl.prg` line ~408** (inside `CCREPL_RunTurn`, after `nTurnMs := hb_MilliSeconds() - nTurnStartMs`): call `CCHOOKS_Run( "turn_complete", { ... } )` with status, model, tokens, duration.
- **`src/ccrepl.prg`** add slash-command handler `CCREPL_HandleHook( cArg, oPrompt )` mirroring the `CCREPL_HandleProvider` structure.
- **`src/ccsettings.prg`** — `CCSETTINGS_Defaults` adds `"hooks" => {=>}` and `"hooks_log" => .F.`; `CCSETTINGS_Load` extends the merge loop to handle the `hooks` sub-hash analogously to `permissions`.

### Settings shape

```json
{
  "model": "...",
  "base_url": "...",
  "hooks": {
    "turn_complete": [
      "powershell -c \"[console]::beep(800,200)\""
    ]
  },
  "hooks_log": false
}
```

- `hooks` absent or `{}` → no-op (entire system silently disabled).
- `hooks_log: true` → append to `.ccharbour/hooks.log`.

### Env vars passed to each hook

| Var | Value |
|-----|-------|
| `CCHARBOUR_EVENT` | `turn_complete` |
| `CCHARBOUR_STATUS` | `success`, `error`, or `interrupted` |
| `CCHARBOUR_MODEL` | active model name |
| `CCHARBOUR_TOKENS` | total tokens of the turn (0 if pre-response error) |
| `CCHARBOUR_DURATION_MS` | milliseconds the turn took |
| `CCHARBOUR_CWD` | CCHarbour working directory |

Set with `hb_SetEnv` before each `hb_processOpen` call. The child inherits the env at spawn time; subsequent fires overwrite the same vars in CCHarbour's own process — acceptable since hooks are pure side effects.

## Command surface (`/hook`)

```
/hook                              List all hooks grouped by event.
/hook list [event]                 Same as above; optional event filter.
/hook add <event> <cmd...>         Append a hook (everything after <event> is the cmd, unquoted).
/hook remove <event> <idx>         Remove the 1-based idx-th hook from the event.
/hook edit <event> <idx> <cmd...>  Replace the idx-th hook with <cmd>.
/hook test <event>                 Fire hooks for <event> with dummy env vars (status=success, model=test, tokens=0, duration_ms=0).
/hook log                          If hooks_log is enabled, print the path and tail of the last 20 lines. Otherwise print a hint.
```

### Argument parsing

- `add` / `edit`: tokenise the first 1-2 words (`<event>`, optional `<idx>`); the remainder is the raw command string, no shell quoting required at the REPL boundary. The command is stored verbatim in JSON and passed verbatim to `hb_processOpen`.
- Unknown subcommand → error with usage block.
- Unknown event → error listing valid events (`turn_complete`).

## Data flow

### `turn_complete` fire

```
CCREPL_RunTurn() ends
  → nTurnMs computed
  → CCHOOKS_Run( "turn_complete", hCtx )
     → hSet := CCSETTINGS_Load()              # fresh read
     → IF empty(hSet["hooks"][cEvent]) RETURN
     → FOR EACH cCmd IN array:
        hb_SetEnv( "CCHARBOUR_EVENT", cEvent )
        hb_SetEnv( "CCHARBOUR_STATUS", hCtx["status"] )
        ... (other env vars)
        hb_processOpen( cCmd, ..., .T. /* detach */ )
        IF hooks_log: CCHOOKS_Log( "event=... cmd=..." )
     NEXT
  → return immediately
```

### `/hook add` flow

```
REPL parses "/hook add turn_complete <cmd...>"
  → CCREPL_HandleHook( "add turn_complete <cmd>" )
  → hSet := CCSETTINGS_Load()
  → CCHOOKS_Add( hSet, "turn_complete", cCmd )
  → CCSETTINGS_Save( hSet )
  → echo "[hook added → turn_complete: <cmd>]"
```

### `/hook test` flow

```
REPL parses "/hook test turn_complete"
  → CCHOOKS_Run( "turn_complete", {
       "status"=>"success", "model"=>"test",
       "tokens"=>0, "duration_ms"=>0 } )
  → echo "[fired N hook(s) — check log if hooks_log enabled]"
```

## Error handling

### Runtime (`CCHOOKS_Run`)

| Case | Behaviour |
|------|-----------|
| `hooks` key absent or `{}` | No-op, silent. |
| Event key absent in `hooks` | No-op, silent. |
| Event not in `CCHOOKS_ValidEvents()` (corrupt config) | Log warning to `hooks.log` if enabled; skip. |
| `hb_processOpen` raises | Caught, logged if enabled, continue with next hook. |
| Child process crashes | Ignored — fire-and-forget. |
| Malformed settings.json | Already handled by `CCSETTINGS_Load` (returns defaults — no hooks → no-op). |

### Interactive (`/hook`)

| Case | Message |
|------|---------|
| `/hook add foo bar` (invalid event) | `error: unknown event 'foo'. Valid: turn_complete` |
| `/hook remove turn_complete 99` (idx out of range) | `error: index 99 out of range (1..N)` |
| `/hook edit` missing cmd | `usage: /hook edit <event> <idx> <cmd>` |
| Empty cmd in add/edit | `error: command empty` |
| `/hook test foo` | `error: unknown event 'foo'` |
| `/hook log` with `hooks_log: false` | `[hooks_log disabled — set "hooks_log": true in .ccharbour/settings.json]` |
| `/hook log` enabled | `[log: <path>]` + tail of last 20 lines |

### Log format (when `hooks_log: true`)

Append line per fire:
```
[2026-05-27 14:23:11] event=turn_complete status=success cmd=powershell -c "[console]::beep(800,200)"
```

Spawn failures:
```
[2026-05-27 14:23:11] event=turn_complete ERROR spawn-failed cmd=<cmd>
```

Path: `.ccharbour/hooks.log` (relative to CCHarbour cwd). Append-only. No rotation in MVP — documented as future TODO.

## Testing

File: `tests/test_hooks.prg`, registered in `tests/run_tests.prg`.

### Unit tests (pure functions)

| Test | Verifies |
|------|----------|
| `test_valid_event` | `CCHOOKS_IsValidEvent("turn_complete")` true; `("foo")` false. |
| `test_list_empty` | Settings without `hooks` → empty array. |
| `test_list_event` | Settings with 2 hooks under `turn_complete` → length 2, order preserved. |
| `test_add` | hSet without hooks → after add, length 1 with correct cmd. |
| `test_add_appends` | hSet with 1 hook → add → length 2, order preserved. |
| `test_remove_valid` | 3 hooks → remove idx 2 → length 2; idx 1 & 3 survive. |
| `test_remove_out_of_range` | remove idx 99 → returns `.F.` and hSet unchanged. |
| `test_edit_valid` | edit idx 1 → new cmd at position 1; others unchanged. |
| `test_log_path` | Returns expected absolute path. |

### Integration tests (`CCHOOKS_Run`)

| Test | Verifies |
|------|----------|
| `test_run_no_hooks` | No config → returns immediately, no error. |
| `test_run_unknown_event` | Event not registered in settings → no-op. |
| `test_run_spawn` | Hook writes to a temp file; file exists within 500 ms. |
| `test_run_env_vars` | Hook echoes `$CCHARBOUR_STATUS` to a file → contents match. |
| `test_run_log_enabled` | `hooks_log=true` → log file grows after fire. |
| `test_run_log_disabled` | `hooks_log=false` → log file not created. |

### REPL handler tests

| Test | Verifies |
|------|----------|
| `test_handle_list` | Parses `/hook` (no args) → output lists hooks with 1-based indices. |
| `test_handle_add_invalid_event` | Error message contains valid event list. |
| `test_handle_test_dispatches` | `/hook test turn_complete` → `CCHOOKS_Run` invoked with dummy env. |

### Cross-platform setup

Spawn-based tests use `iif( hb_OsIsWin(), "cmd /c ...", "sh -c '...'" )`. The same suite must pass on Windows (dev box) and Linux (gpuserver).

Each test creates a temp settings.json under `tests/tmp_hooks/` and removes it on teardown.

## Open questions

None — all decisions captured above.

## Future work (out of scope for this spec)

- Additional events: `session_start`, `session_end`, `user_prompt_submit`, `pre_tool_use`, `post_tool_use`.
- JSON-on-stdin context (Claude Code parity).
- Per-hook timeout / working-directory / env-var overrides.
- Hook conditions (`on_status: ["success","error"]`).
- Log rotation.
- `/hook export` / `/hook import` for sharing hook profiles.

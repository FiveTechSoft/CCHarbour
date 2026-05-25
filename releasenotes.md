CCHarbour v0.8.18 — Background subagents: dispatch_agent_background tool + /tasks slash command.

## New since v0.8.17

- **`dispatch_agent_background` tool.** Fire-and-forget variant of
  `dispatch_agent`. Returns a task-id (`bg1`, `bg2`, ...) IMMEDIATELY
  without blocking the parent. A fresh `hb_threadStart` worker runs
  `CC_AgentRun` in the background and writes progress into an in-
  memory registry; the parent agent can chain its next step right
  away.
- **Background-task registry** (`src/ccbg.prg`). Mutex-protected
  hash keyed by task id. Each record carries `id`, `type`, `prompt`,
  `timeout`, `status` (`queued` / `running` / `done` / `failed` /
  `cancelled` / `timed_out`), `started_ms`, `ended_ms`,
  `iterations`, `reply`, `error`, `cancel_requested`. Public API:
  `CCBG_NextId / Add / Update / Get / List / Kill / CancelRequested /
  ClearFinished`. Workers MUST NOT touch the terminal (that would
  corrupt the dynamic input box); the main REPL polls the registry.
- **`/tasks` slash command.** The user's only window into the
  registry:
    - `/tasks` -- tabular list (id, status, elapsed, type, prompt
      summary).
    - `/tasks view <id>` -- full record including reply / error.
    - `/tasks kill <id>` -- request cancel; worker exits at next
      agent-loop boundary.
    - `/tasks clear` -- drop every finished / failed / cancelled
      / timed-out record.
- **Subagent filter widened.** `CCTOOLS_FilterForAgent` removes BOTH
  `dispatch_agent` and `dispatch_agent_background` from a subagent's
  registry, so a subagent cannot spawn its own subagents (no
  unbounded recursion).
- **Help, README and `pages/commands.md` updated** with the new
  command rows.

## v0.8.17 — /save and /load now round-trip the full session state: goal, modes, skills, timer, and the pending suggestion.

### New since v0.8.16

- **/save / /load preserve every REPL-level static, not just the
  conversation.** Saved JSON now carries a new `state` block plus a
  `suggest` string in addition to `model` / `usage` / `messages`.
  `/load` restores them on top of the conversation so a reload is
  truly a full snapshot.
- **`state` block.** `CCREPL_StateExport()` packs the current
  `goal`, `goal_looping`, `session_turn_ms`, `plan_mode`, `lean_mode`,
  and `skills` (active skill names) into a primitive hash.
  `CCREPL_StateImport( hState )` reapplies them, silently skipping
  missing keys so legacy session files still load cleanly.
- **`suggest` field.** The pending "Suggested next:" prompt that the
  model emitted on its last turn is persisted alongside the messages
  and re-seeded into the editor on the first idle frame after
  `/load`, so the green Tab-acceptable preview survives a restart.
- **`CCSKILL_ClearAll()`.** New helper that drops every active skill
  in one shot; called by `CCREPL_StateImport` before re-activating the
  loaded skill list so the restored set takes over from whatever was
  active.

## v0.8.16 — /goal turns into "keep working until the condition is met": auto-continue loop + GOAL COMPLETE sentinel.

### New since v0.8.15

- **/goal redesigned around "keep working until the condition is met".**
  Setting a goal now arms an auto-continue loop in the main REPL:
  after every user-initiated turn the loop scans the last assistant
  reply for a literal `GOAL COMPLETE` sentinel. If absent it auto-
  feeds `Continue toward the goal. ...reply with ONLY the literal
  sentinel...` as the next user message and runs another turn.
- **GOAL COMPLETE sentinel.** The injected system note teaches the
  model to emit `GOAL COMPLETE` on its own line when the condition
  is met. `CCREPL_GoalDone( cReply )` checks the substring.
- **CC_GOAL_AUTO_CAP = 25.** Hard cap on auto-iterations per user
  turn so a stubborn model cannot loop forever; the REPL prints
  `[goal auto-continue cap (25) hit ...]` when it trips.
- **Esc pauses the loop.** `CCREPL_RunGoalLoop` drains the
  `CCPROMPT_Interrupted` flag and disarms `s_lGoalLooping` without
  dropping the goal text -- `[goal auto-continue paused by Esc --
  /goal <text> or a new message to restart]`.
- **`/goal stop`.** New sub-command that pauses the auto-continue
  loop without clearing the goal text (so the badge stays on).
  `/goal clear` still drops the goal entirely and disarms the loop.
- **Per-iteration progress line.** `[goal auto-continue N/25]` prints
  before each automatic turn so the user can see the loop ticking.

## v0.8.15 — /goal slash command: pin a session-wide objective the agent carries through every turn.

### New since v0.8.14

- **`/goal` slash command.** Pins a session-wide objective the agent
  carries through every subsequent turn until it is changed or
  cleared:
    - `/goal` — show the current goal (or `(none)`).
    - `/goal <text>` — store the goal AND inject it into the
      conversation as a system note, so the model sees the intent on
      the very next request without re-sending the goal on every
      turn.
    - `/goal clear` (alias `/goal off`) — drop the goal and tell the
      model to stop treating it as a constraint.
- **`[goal]` badge.** When a goal is set, the status line under the
  input box shows a `[goal]` tag alongside `[plan-mode]` / `[lean]`.
- **`/clear` resets the goal too.** Resetting the conversation also
  clears the session goal and the session-turn timer accumulator, so
  the next session starts blank.

## v0.8.14 — Shell countdown lands above the box, diff bars equal width + bright-white text.

### New since v0.8.13

- **Shell command countdown no longer painted inside the input box.**
  `CCTool_ShowCountdown` / `CCTool_ClearCountdown` route through the
  `CCREPL_OverwriteAtAnchor` helper when the persistent box is
  mounted, so `timeout 300s · 252s left` lands on the scroll-region
  anchor above the box and a trailing `CCREPL_Out( Chr(10) )` bakes
  the final value in for the result summary. The plain-CR fallback
  is kept for cooked / non-VT terminals.
- **Diff bars are all the same width.** `CCUI_ResultBlock` scans the
  diff once for the widest added/removed line (floor 110), then pads
  every coloured bar to that width via `CCUI_DiffPad( cLine, nWidth )`
  -- no more ragged edges when one line is longer than the rest.
- **Diff text rendered in bright white.** Added lines go from SGR
  `37;42` to `97;42`, removed from `48;5;52` to `97;48;5;52` -- the
  red bar now matches the green bar's contrast.

## v0.8.13 — Dynamic-box paint hardening, live timing in the spinner / token bar, /provider key picked up on the next turn.

### New since v0.8.12

- **Banner anchored at row 1.** `CCREPL_Run` emits `ESC[H ESC[2J`
  before printing the banner so it is always at rows 1..N and the
  `CCPROMPT_Activate( nHeaderRows + 1 )` anchor lands exactly below it.
  Previously the banner started at the cursor's row (often row 2 after
  the shell `cc` line), so subsequent writes overwrote the banner's
  bottom border.
- **Box paint uses absolute cursor jumps.** `CCPROMPT_Redraw` now
  positions every row of the four-row box with an absolute `ESC[<row>;1H`
  instead of chaining CRLFs. The CRLF chain scrolled the screen up by
  one row each time the box sat near the terminal bottom, which is how
  pressing Esc at the idle prompt could stack 10+ leftover `╭` frames
  above the box.
- **Wipe rule rewritten.** The old-box-frame wipe in `CCPROMPT_Redraw`
  is now `[oldBoxTop .. min(oldBoxTop+3, newBoxTop-1)] minus the rows
  just written`. `CCREPL_Out` stashes `last_write_start` and a trailing
  -LF flag so Redraw knows where the chunk actually wrote. Fixes the
  FlushPending bullet (`"\n + glyph + 2sp"`, no trailing LF) being
  wiped right after it was painted, and the stale top-frame left
  behind by multi-line writes (paragraph breaks in the streamed reply).
- **Banner scrolls when the box pins.** `CCPROMPT_Region` sets
  `scroll_top` to 1 once `box_top == nFloor`, so the VT scroll region
  expands up to the top of the screen and the banner finally rolls off
  the top edge as new content arrives. While the box is still
  travelling the banner is still pinned (current behaviour).
- **Spinner shows elapsed seconds.** `iteration_start` stamps a wall-
  clock in `oRender[ "spinnerStartMs" ]`; `CCREPL_SpinnerShow` appends
  ` Ns` to the spinner line (e.g. `⠦ Thinking... [32 tok] 7s`).
- **Token bar shows turn / session seconds.** `CCREPL_RunTurn` times
  each turn with `hb_MilliSeconds()`, accumulates into a session-wide
  static, and passes the per-turn ms to `CCREPL_ShowTokenBar`. The bar
  now reads `▒ tokens in: 3670  out: 83  total: 3753  turn: 1.4s
  session: 7.2s`. `/clear` resets the session counter.
- **dispatch_agent timer ticks down.** The opening Agent block prints
  the separator / header / prompt and then drops a live elapsed-time
  line via the new `CCREPL_OverwriteAtAnchor` helper. The
  `interrupt_check` callback refreshes the line at ~2 Hz so the user
  sees `Ns elapsed / Ms timeout · press Esc on the input box to cancel`
  tick in place. A final `CCREPL_Out` bakes the value in and lets the
  "Agent done in X.Xs" line land below.
- **/provider key picked up on the next turn.** `CCCFG_Resolve` now
  falls back to `$CCHARBOUR_CONFIG` (or `.ccharbour/settings.json`)
  when the env vars are empty, so a freshly-saved api_key reaches the
  next chat call without rebuilding the client.

## v0.8.12 — Start without an API key, configure the backend interactively with /provider.

### New since v0.8.11

- **Starts even with no API key configured.** The session no longer
  exits with an error when `DEEPSEEK_API_KEY` is missing; the banner
  and the input box come up normally and a yellow warning under the
  banner tells the user to set up a backend.
- **`/provider` slash command** — configure the backend at runtime:
    - `/provider` — show current `base_url` / `model` / key state and
      list the four presets.
    - `/provider deepseek|glm|moonshot|openai` — apply the preset's
      `base_url` and default model, persist to `settings.json`, and
      rebuild the API client in place.
    - `/provider key <secret>` — store the API key in `settings.json`.
    - `/provider model <name>` — switch the model only.
    - `/provider clear` — wipe the stored API key.
- **Turn skipped (not crashed) when no key.** Submitting a message
  before a key is configured prints the warning again instead of
  erroring out.
- **`CCSETTINGS_Save`** is now public so `/provider` (and any future
  runtime configuration) can persist updates without poking the file
  directly.

## v0.8.11 — Dynamic input box stability fixes.

### New since v0.8.10

- **Scroll region spans the full band** regardless of where the dynamic
  box currently sits (`scroll_bottom = nFloor - 1` always), so an early
  write between banner and box does not scroll content out of the
  banner.
- **Interactive selectors force-pin the box** before painting. ask_user
  and propose_agents now call a new `CCPROMPT_ForcePin` that drops the
  box to the floor first, giving the selector a stable position right
  above it and avoiding overlap with a still-travelling box.
- **Wipe never erases the just-written content.** The old-box-frame
  wipe in `CCPROMPT_Redraw` is now clamped to
  `[max(oldBoxTop, contentRow) .. newBoxTop - 1]`, so the rows that
  hold the new user echo or the streamed reply are preserved.
- **Visual-row counting (auto-wrap).** `CCREPL_Out` now advances
  `content_row` by the visual rows a chunk consumes (LFs + wrapped
  printable runs + ANSI sequences skipped), not just `\n` count, so a
  long line that wraps doesn't sit under the redrawn box.
- **Clear-to-end-of-line on every write.** Each line break in a
  CCREPL_Out chunk is preceded by `ESC[K`; trailing junk on a row
  (such as the right tail of the old box top frame) is wiped, so a
  short content line never leaves a `> hola─────────╮` artifact.

## v0.8.10 — Dynamic input box, native CC logo gradient, banner adapts to terminal width, clean exit, playground polish.

### New since v0.8.9

- **Dynamic input box position** — the box no longer hard-pins at the
  bottom of the terminal. After the banner paints it sits right below
  the logo; each agent reply pushes it down one row per line. When the
  box reaches the floor it "pins" and the scroll region takes over so
  later output scrolls between the banner and the box. The banner stays
  visible for as long as content allows.
- **Native CC logo gradient** — the six-row block-drawing logo in the
  banner renders with a per-character magenta → violet truecolor
  gradient (fuchsia-300 → violet-600). Falls back to plain padding
  when colour is off.
- **Banner adapts to terminal width** — `CCUI_Banner` reads
  `CCREPL_Cols()` and sizes its inner frame to fit, clamped to
  [80, 200], with the left/right panels rebalanced so the logo stays
  centred.
- **Clean exit cursor** — `CCPROMPT_Teardown` now wipes the four box
  rows and parks the cursor at `box_top` before returning. The shell
  prompt that takes over appears right under the agent's last visible
  output instead of below an orphan box.
- **Playground premium UX additions** — a 💡 tip line cycled from a
  pool of 10 entries (shown at startup and after Reset), a
  Suggested-next pre-fill in the input (teal-italic; Tab accepts, any
  printable key replaces, Enter sends), and a Close button on the
  Settings panel that hides it without committing the typed values.
  System prompt now instructs the agent to emit a `Suggested next:`
  line, which the playground strips from the visible reply once it
  has been lifted into the input.
- **Playground subagents** — JS ports of `dispatch_agent` (reuses
  `runAgent` with isolated messages + filtered tool registry) and
  `propose_agents` (glass modal with checkbox per row, A/N bulk
  toggle, Enter/Esc shortcuts). Browser toolset is now 14 tools.
- **CC logo cyan → violet** in the playground (matched the native
  gradient direction).

## v0.8.9 — Multi-provider API support, modernised docs site, premium playground theme.

### New since v0.8.8

- **Multi-provider API keys** — `CCCFG_Resolve` now tries
  `DEEPSEEK_API_KEY` → `CCHARBOUR_API_KEY` → `GLM_API_KEY` /
  `ZHIPU_API_KEY` → `MOONSHOT_API_KEY` → `OPENAI_API_KEY` →
  `settings.json` in order. Any OpenAI-compatible Chat Completions
  endpoint (DeepSeek, GLM-4.6 / Zhipu, Moonshot Kimi, OpenAI, …) works
  once `base_url` and `model` are set in `settings.json`.
- **Docs site overhaul** — MkDocs Material now ships with a light/dark
  palette toggle, sticky tabbed navigation, search suggest /
  highlight / share, code copy + annotation, content tabs, social
  icons, and a richer pymdownx set (tabbed, details, mark, keys,
  tasklist, tilde, caret, betterem). The landing page becomes a hero
  with badges, an ASCII screenshot, a card grid of features, a
  tabbed 30-second tour, and use cases. Getting Started is rewritten
  per-OS (Linux/macOS, cmd, PowerShell) with first-session walkthrough
  and per-platform build instructions. Configuration adds a Providers
  section with sign-up links, indicative pricing per 1M tokens, and
  coding-tier ratings.
- **Playground premium theme** —
  - Animated mesh-gradient background that drifts subtly behind the
    glass panels.
  - Glassmorphism on banner, footer, settings and tool cards
    (`backdrop-filter blur + saturate`).
  - CC logo rendered with a cyan → violet gradient and an 8 s
    background-position shimmer.
  - Pill-shaped version chip, pulsing "online" status dot, gradient
    border-mask on the footer, breathing focus glow on the input.
  - Primary button is a teal linear gradient that lifts on hover;
    Settings and Reset get an outline "ghost" look.
  - Mobile breakpoint at 760 px.
- **Playground gains tools** — JS ports of `memory` (localStorage),
  `todo_write` (with `id` / `active_form` / `blocked_by`) and
  `ask_user` (in-page modal with radio options, Other free-text,
  Cancel / Confirm, Esc / Enter shortcuts). The browser playground
  now exposes file / web / github / memory / todo_write / ask_user
  tools.
- **README refresh** — centred hero with badges, "Why CCHarbour"
  highlights, quick start, 30-second configuration guide. The
  in-source feature inventory is updated from "Done (v0.5.0)" to
  the current v0.8.9 set, listing all 16 builtin tools, skills,
  plan / lean modes, subagents, paste collapse and dynamic box.

## v0.8.8 — propose_agents gate, paste collapse, dynamic input box, bullet split, broader list of skills, and other UX polish.

### New since v0.8.7

- **`propose_agents` tool** — the agent batches 2+ planned subagents and
  the user reviews them in an interactive multi-row selector. Space
  toggles each row, A / N flip all on/off, Enter approves the filtered
  list, Esc cancels the batch. The returned JSON is iterated by the
  agent to call `dispatch_agent` once per approved item. Inherently
  consented (the user is the gate).
- **Second-dispatch interceptor** — if the agent calls `dispatch_agent`
  twice in a row without going through `propose_agents`, the second call
  is rejected with a redirect message asking it to batch via
  `propose_agents`. Approved batches top up an allowance equal to the
  number of approved items, so a sanctioned batch dispatches without
  the gate firing again. Both counters reset at the start of each
  REPL turn.
- **Agent block** — every `dispatch_agent` call now renders an
  absolute-positioned block (rule, " Agent <type> working ", short
  prompt summary, timeout + Esc hint). When the subagent finishes the
  block closes with "Agent done in X.Xs (N iterations)" so wall-clock
  and effort are visible.
- **Subagent timeout + Esc cancel** — every `dispatch_agent` accepts a
  `timeout_s` (default 120, max 600); the subagent is interrupted at
  the boundary and returns `[subagent timed out after Ns]`. The user
  can also press Esc on the input box mid-run; the subagent returns
  `[subagent cancelled by user]`.
- **Paste collapse** — pasting multi-line text into the box now stashes
  the real content in a sidecar and shows a tidy
  `[pasted N lines text]` placeholder. Enter expands the placeholder
  back transparently; Backspace clears the paste entirely.
- **Dynamic input box width** — `CCUI_InputInnerWidth` and the frame
  borders read the terminal column count and adapt (clamped to
  [76, 200] inner). Wider terminals get a wider box without rebuilding.
  Fixed sizes only kick in below 76 cols or above 200.
- **Bullet-run split (CCMD)** — when a model emits an entire list on a
  single line joined by `- ` markers (no newlines), `CCMD_SplitBulletRun`
  splits it into one virtual line per item before rendering. The split
  applies both mid-stream (CCMD_Feed) and at end-of-turn (CCMD_Flush).
- **Stricter list formatting in the system prompt** — both the parent
  agent and subagents are told to put each list item on its own line
  with `- ` and to leave a space around `**bold**` so the surrounding
  whitespace survives.
- **5 new skills shipped under `.ccharbour/skills/`** — `brainstorming`,
  `writing-plans`, `tdd`, `debugging`, `code-review` (each with EN+ES
  auto-trigger patterns).
- **`/lean`** — toggles a minimal system prompt (no skills section, no
  CC.md, no memory.md, no narration block) to save ~500-800 tokens
  per turn. `[lean]` badge in the status line.

## v0.8.7 — Subagents: dispatch_agent tool with isolated context and filtered tool registry.

### New since v0.8.6

- **`dispatch_agent` tool** — the agent can now spawn an isolated
  subagent on a self-contained subtask. The subagent has its own
  conversation, its own (filtered) tool registry, and the parent only
  receives the subagent's final reply. The parent's context stays small
  while exploration / multi-file searches / focused investigations run
  in the subagent.
- **Two agent types:**
  - `explore` (default) — read-only toolset: `read`, `glob`, `grep`,
    `github_read`, `memory`, `use_skill`. Cannot modify the codebase or
    run shell commands. Ideal for "where is X used?" and survey tasks.
  - `general` — full toolset (write, edit, shell, github_write, web_*,
    todo_write, ask_user). Subagent can perform real work in isolation.
- **No recursion** — `dispatch_agent` is always filtered out of a
  subagent's registry, so a subagent cannot spawn another one (yet).
- **Inherently consented** — `dispatch_agent`, like `use_skill`,
  `ask_user` and `todo_write`, bypasses the permission gate; the user
  asked for the work, the agent just delegates a piece of it.
- **Synchronous v1** — the parent blocks until the subagent finishes.
  Parallel multi-agent dispatch is a future enhancement once the thread
  model is in place.

## v0.8.6 — Lean mode (`/lean`) for token-saving sessions.

### New since v0.8.5

- **`/lean`** — toggles lean-mode. While active, `CCUI_SystemPrompt`
  returns a minimal prompt (no skills section, no `CC.md`, no `memory.md`,
  no narration block). Per-turn input drops by ~500-800 tokens (from
  ~2900 down to ~2100 on a vanilla "hi"). Useful late in long sessions
  when context is filling up or when working against an expensive model
  (Claude, GPT) where each input token matters.
- **`/lean off`** — restores the full system prompt. The first system
  message in the conversation is updated in place so the next turn sees
  the change immediately.
- **`[lean]` badge** — appears in the status line under the input box
  while lean-mode is active, alongside any other badges (`plan-mode`,
  active skills).
- Auto-cleared by `/clear`: a session reset rebuilds the system prompt
  from scratch and always uses the lean state in effect at that moment.

## v0.8.5 — Richer todo_write: ids, blockers and present-continuous active labels.

### New since v0.8.4

- **`todo_write` got three new optional fields:**
  - **`id`** — a string identifier for the task. Other tasks can refer to
    it from their `blocked_by` list to declare a dependency.
  - **`active_form`** — the present-continuous label rendered in place of
    `text` while that task is `in_progress` (e.g. `"Running tests"` instead
    of `"Run tests"`).
  - **`blocked_by`** — an array of `id` strings naming the tasks this one
    depends on. If any of those is still pending or in_progress, the
    blocked task renders indented, dimmed, with a `↳` glyph and the
    `(blocked)` suffix; once every blocker is completed, it returns to its
    normal style.
- **Renderer upgrade** — `CCUI_TodoBlock` now honours `active_form` for
  in_progress items and visually differentiates blocked items so the
  dependency chain is obvious at a glance.
- **Backwards compatible** — items that omit the new fields render
  exactly as before.
- **Tool description** carries a concrete example call so the model
  picks up the new shape without extra prompting.

## v0.8.4 — Plan mode, expanded skill library, wider banner and input box.

### New since v0.8.3

- **Plan mode (`/plan`)** — a new command puts the session in "plan mode":
  the `write`, `edit`, `shell` and `github_write` tools are locked at the
  permission gate, the `writing-plans` skill is auto-activated, and the
  status line shows a `[plan-mode]` badge. The agent can read, grep, glob,
  fetch and reason freely but cannot modify the codebase until the user
  approves. `/plan <text>` enters plan mode AND submits `<text>` as the
  first planning prompt; `/plan accept` (or `/plan go`/`/plan approve`)
  unlocks the gate and tells the agent to proceed step by step;
  `/plan cancel` (or `/plan off`) drops the plan and unlocks.
- **Skills library expanded** — five new process-discipline skills
  shipped under `.ccharbour/skills/`:
  - `brainstorming` — explore intent and design before coding (clarify
    goal, list constraints, sketch alternatives, pick one with reason).
  - `writing-plans` — turn an approved approach into an ordered,
    verifiable, multi-step plan with a done criterion per step.
  - `tdd` — red/green/refactor with CCHarbour-specific test commands.
  - `debugging` — reproduce, isolate, hypothesise, verify; no guessing
    patches, root cause only.
  - `code-review` — checklist for correctness, scope creep, security,
    test coverage, readability before commit.
  Each has triggers (English + Spanish), so the agent auto-activates the
  matching skill when its description fits the request.
- **Wider banner and input box** — the welcome banner and the persistent
  input frame grew from 99 columns wide to 123, giving the model 117
  text columns inside the input box (was 93). The CC logo is unchanged
  but now has more breathing room.

## v0.8.3 — Unified tool-call block, ask_user selector polish, and richer mid-question controls.

### New since v0.8.2

- **Unified tool-call block** — every tool call now renders as a single
  block: a cyan-violet rule the full terminal width, the tool's display
  label ("Bash command", "Edit", "Read", "Glob", "Web fetch", ...) on its
  own line, the primary argument (command / path / pattern / url / query)
  indented in bright green, and any narration the model produced on a soft
  white line below.
- **`ask_user` block** — the selector now paints separator, " Ask user",
  blank, question, blank, options, blank, hint as one absolute-positioned
  block right above the input box. Up/Down navigate with wrap-around (Down
  on the last option lands on the first, Up on the first lands on the
  last); each repaint lands in the same rows so the screen no longer
  jitters or scrolls.
- **Hint tail** — every question lists `Esc to cancel · Tab to amend ·
  ctrl+e to explain` in dim under the options.
- **Mid-question keys** —
  - **Tab** (amend) drops the highlighted option into the input box
    pre-filled, so the user can edit and submit a tweaked version.
  - **Esc** cancels the question; the tool returns "User cancelled" so the
    model drops that line of questioning.
  - **Ctrl+E** asks the model to explain; the tool returns a sentinel the
    model interprets as "elaborate and re-ask".
- **Type in the box during a question** — printable keys, backspace,
  cursor keys, Home/End, Delete, Shift+Enter all edit the input box even
  while the selector is up. Enter on a non-empty box submits the line
  (cancelling the selector and queuing the message for the next turn);
  `/exit` or `/quit` quits cc immediately; `/btw <text>` records a mid-turn
  interrupt that the agent picks up at the next boundary.
- **Box prompt history** — Up/Down in the input box now navigate the
  history, matching the cooked-mode editor.
- **Cursor follows the box** — while the selector waits for a key, the
  visible cursor parks inside the input box rather than blinking above the
  options.
- **Content preserved** — when the question block first paints, the
  scroll region scrolls up by exactly the block's height so any model
  output above remains visible instead of being overwritten.

## v0.8.2 — Project skills: process-discipline checklists the model can load on demand, with a status line and an auto-trigger.

### New since v0.8.1

- **Project skills** — `.md` files under `.ccharbour/skills/` describe a
  checklist or set of instructions the model can pull in for the turn. Each
  skill has a name and a one-line description in YAML frontmatter; the model
  sees the list at session start and activates one with the new `use_skill`
  tool.
- **Status line** — the input box gained a fourth row that lists the
  currently active skills as bracketed orange tags (e.g. `[superpowers]`),
  so it is always clear which discipline is in effect.
- **Auto-trigger** — a skill can declare a `triggers:` line of
  comma-separated regex patterns in its frontmatter; if the user's input
  matches, the skill activates automatically, its body is injected into the
  conversation as a system note, and a `[skill 'X' auto-activated]` line is
  printed in the scroll. No regex match → no activation.
- **`/caveman` command** — first-class slash command that activates the
  caveman skill (ultra-compressed terse replies). Generalises to any skill
  via the same `CCREPL_ActivateSkill` path.
- **Sample skills shipped** — `.ccharbour/skills/superpowers.md`
  (brainstorm → plan → execute → verify checklist) and
  `.ccharbour/skills/caveman.md` (terse-mode rules).
- **System prompt awareness** — the available skills are listed in the
  system prompt so the model knows what is on offer without loading every
  body up front.

## v0.8.1 — Input box polish: white user echo and translucent-green "Suggested next".

### New since v0.8.0

- **User prompt echoed in white** — every submitted prompt is now reprinted
  in bright white in the scroll above the input box, so the transcript shows
  what was asked alongside the model's reply. Mid-turn queued messages are
  echoed the same way when they get handled.
- **"Suggested next" pre-filled in the box** — the model's `Suggested next:`
  line is loaded into the input box as a translucent green suggestion. Press
  Tab to accept it as the message, Backspace/Delete to clear it, or just
  start typing to replace it. The cooked-mode fallback already had this; box
  mode now matches.

## v0.8.0 — Linux and macOS support: cc now builds and runs on all three platforms.

### New since v0.7.0

- **Linux & macOS builds** — new `cc_linux.hbp` / `cc_mac.hbp` project files,
  a `build_cc_linux.sh` script, and `build-linux` / `build-mac` CI workflows.
  Every tagged release now ships a Windows, Linux and macOS binary.
- **POSIX console backend** — `ccconsole_mac.c` renamed to `ccconsole_posix.c`
  and shared by the Linux and macOS builds (termios/select, no OS-specific
  code). Added the `CCCON_Size` and `CCCON_KeyPending` functions it lacked.
- **Cross-platform shell tool** — the `shell` tool ran commands only through
  `cmd.exe`; it now uses `/bin/sh` on Linux and macOS. Without this every
  shell command failed on those platforms.
- **Auto-created settings** — on first run CCHarbour writes a default
  `.ccharbour/settings.json` so the configuration is there to discover and
  edit.
- **Build-project fix** — `cc_mac.hbp` was missing `ccprompt.prg`, leaving
  the macOS build broken since the always-visible prompt landed.

## v0.7.0 — Shell command timeouts with a live countdown, plus reliability fixes.

### New since v0.6.0

- **Shell timeout** — the `shell` tool now bounds how long a command may run.
  Set it with the `shell_timeout` setting (default 30s), an optional per-call
  `timeout` argument, or — when `shell_timeout` is 0 — an automatic
  per-command estimate.
- **Live countdown** — while a shell command runs, the REPL shows the
  configured timeout and the seconds still left, updated in place.
- **Reliability fixes** — repaired the timed-shell path: a missing
  `fileio.ch` include (`F_ERROR` undefined), an undefined `hb_TempFile()`
  link error, and a broken exit-code marker. Completion detection and the
  real exit code now come from `hb_processValue`.
- **UTF-8 sanitising** — tool results are scrubbed of invalid Unicode
  (`CC_SanitizeUTF8`) so they cannot break the API request JSON.
- **Better API errors** — API failure messages now include a dump of the
  HTTP response body.
- **Docs** — documented the shell timeout; corrected web search to DuckDuckGo.

## v0.6.0 — Massive refactor: all files and functions renamed from ds* to cc* prefix.

## New since v0.5.1

- **File renaming** — all source files renamed from `ds*.prg` to `cc*.prg` (e.g. `dsui.prg` → `ccui.prg`)
- **Function prefix change** — all public and static functions renamed from `DS*` to `CC*`
  (e.g. `DSUI_Version()` → `CCUI_Version()`, `DSREPL_Out()` → `CCREPL_Out()`)
- **Build system updated** — `.hbp`, `.bat`, test files and README all reflect the new names
- All 340 tests pass with 0 failures

## v0.5.1 — Playground fixes and updated documentation.

### New since v0.5.0
- **Playground fixes** — removed unused parameter in `web.js`, fixed registry test sort order
- **Documentation** — updated module table in README with detailed descriptions for all components

## v0.5.0 — DuckDuckGo web search (no API key needed), refactored REPL, Harbour ship logo, and more.

### New since v0.4.0
- **DuckDuckGo web search** — replaced Tavily with DuckDuckGo Instant Answer API, no API key required
- **REPL refactor** — cleaner multi-turn agent loop, fixed `LoadSession` bug, portable paths
- **Harbour-style ship logo** — new project branding in the startup banner
- **Spinner throttle** — slowed down from 30 ms to 100 ms for less flicker
- **Default model fix** — restored to `deepseek-v4-flash`

## Previous features (v0.1.0 — v0.4.0)
- Pause tool execution with Escape, web & GitHub tools, memory tool, web playground,
  conversation persistence, token cost tracking, multi-line input, Ctrl+C cancel,
  animated reasoning spinner, co_author setting, diff improvements, CI/CD

## Usage
```
REM Windows
set DEEPSEEK_API_KEY=sk-...
cc.exe
```
```
# Linux / macOS
export DEEPSEEK_API_KEY=sk-...
chmod +x cc-linux && ./cc-linux
```

This release ships three standalone x64 binaries: `cc.exe` (Windows, no DLLs
required), `cc-linux` (Linux) and `cc-macos` (macOS).

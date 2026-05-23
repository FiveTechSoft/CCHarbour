---
hide:
  - navigation
  - toc
---

<style>
.cc-hero { text-align: center; margin: 2rem 0 1.5rem; }
.cc-hero h1 { font-size: 3rem; margin: 0; letter-spacing: -0.02em; }
.cc-hero p.tagline { font-size: 1.15rem; opacity: 0.85; margin: 0.5rem 0 1.25rem; }
.cc-hero .cc-cta { display: inline-flex; gap: 0.5rem; flex-wrap: wrap; justify-content: center; }
.cc-badges { text-align: center; margin: 0.5rem 0 2rem; }
.cc-badges img { margin: 0 0.15rem; vertical-align: middle; }
.cc-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1rem; margin: 1.5rem 0 3rem; }
.cc-card { padding: 1.1rem 1.2rem; border: 1px solid var(--md-default-fg-color--lightest); border-radius: 0.5rem; background: var(--md-code-bg-color); }
.cc-card h3 { margin: 0 0 0.4rem; font-size: 1.05rem; }
.cc-card p { margin: 0; font-size: 0.92rem; opacity: 0.85; }
.cc-screenshot { background: #0d1117; color: #c9d1d9; padding: 1rem 1.2rem; border-radius: 0.5rem; font-family: var(--md-code-font); font-size: 0.82rem; overflow-x: auto; line-height: 1.45; }
.cc-screenshot .accent { color: #4ec9b0; }
.cc-screenshot .dim    { color: #6b7280; }
.cc-screenshot .user   { color: #f5f5f5; }
.cc-screenshot .green  { color: #5bd07a; }
</style>

<div class="cc-hero" markdown>

# CCHarbour

<p class="tagline">A Claude Code-style agentic coding assistant — in your terminal, in a single ~2 MB binary that runs on Windows, macOS and Linux, written in Harbour.</p>

<p class="cc-cta">
<a class="md-button md-button--primary" href="getting-started/">Get started</a>
<a class="md-button" href="https://github.com/FiveTechSoft/CCHarbour/releases/latest">Download</a>
<a class="md-button" href="playground/index.html">Try in browser</a>
</p>

</div>

<div class="cc-badges" markdown>
[![latest release](https://img.shields.io/github/v/release/FiveTechSoft/CCHarbour?style=flat-square&color=teal)](https://github.com/FiveTechSoft/CCHarbour/releases/latest)
[![windows](https://img.shields.io/github/actions/workflow/status/FiveTechSoft/CCHarbour/build.yml?branch=master&label=windows&style=flat-square)](https://github.com/FiveTechSoft/CCHarbour/actions/workflows/build.yml)
[![linux](https://img.shields.io/github/actions/workflow/status/FiveTechSoft/CCHarbour/build-linux.yml?branch=master&label=linux&style=flat-square)](https://github.com/FiveTechSoft/CCHarbour/actions/workflows/build-linux.yml)
[![macos](https://img.shields.io/github/actions/workflow/status/FiveTechSoft/CCHarbour/build-mac.yml?branch=master&label=macos&style=flat-square)](https://github.com/FiveTechSoft/CCHarbour/actions/workflows/build-mac.yml)
[![licence](https://img.shields.io/github/license/FiveTechSoft/CCHarbour?style=flat-square)](https://github.com/FiveTechSoft/CCHarbour/blob/master/LICENSE)
</div>

<pre class="cc-screenshot">
<span class="dim">╭─────────────────────────────────────────────────────────────────────────────╮</span>
<span class="dim">│</span>      Welcome back, <span class="accent">Anto</span>!              <span class="dim">│</span> Tips for getting started           <span class="dim">│</span>
<span class="dim">│</span>            <span class="accent">██████╗ ██████╗</span>              <span class="dim">│</span> Type a request to begin            <span class="dim">│</span>
<span class="dim">│</span>           <span class="accent">██╔════╝██╔════╝</span>             <span class="dim">│</span> Run /help to list commands         <span class="dim">│</span>
<span class="dim">│</span>           <span class="accent">██║     ██║     </span>             <span class="dim">│</span> /caveman for terse replies         <span class="dim">│</span>
<span class="dim">│</span>           <span class="accent">╚██████╗╚██████╗</span>             <span class="dim">│</span> ────────────────────────────────── <span class="dim">│</span>
<span class="dim">│</span>            <span class="accent">╚═════╝ ╚═════╝</span>              <span class="dim">│</span> What's new                         <span class="dim">│</span>
<span class="dim">│</span>           CCHarbour  <span class="accent">v0.8.8</span>              <span class="dim">│</span> propose_agents + paste collapse    <span class="dim">│</span>
<span class="dim">╰─────────────────────────────────────────────────────────────────────────────╯</span>

<span class="dim">╭─────────────────────────────────────────────────────────────────────────────╮</span>
<span class="dim">│</span> > <span class="green">how is the codebase organised?</span>                                            <span class="dim">│</span>
<span class="dim">╰─────────────────────────────────────────────────────────────────────────────╯</span>
  <span class="accent">[superpowers]</span> <span class="accent">[tdd]</span>
</pre>

## Why CCHarbour

<div class="cc-grid" markdown>

<div class="cc-card" markdown>
### 🦾 Real agentic loop
Multi-iteration tool calls, streaming SSE, mid-turn interrupts, subagent dispatch. Stops only on a final answer or the iteration cap.
</div>

<div class="cc-card" markdown>
### 📦 One file, ~2 MB
A single console executable. No Python, no Node, no Docker. Drop it on a server, on a USB stick, in a CI runner.
</div>

<div class="cc-card" markdown>
### 🪟 Truly cross-platform
Windows (MSVC or mingw-w64), Linux (gcc), macOS (clang). The same Harbour source on every platform; a Win32 + POSIX console layer underneath.
</div>

<div class="cc-card" markdown>
### 🧠 Skills & Plan mode
Drop a Markdown checklist under `.ccharbour/skills/` and the agent picks it up. `/plan` locks file writes until you approve the approach.
</div>

<div class="cc-card" markdown>
### 🛡 Permission gate
Every tool is `allow`, `ask` or `deny`. `shell` and `edit` prompt by default; you can flip any tool per project in `settings.json`.
</div>

<div class="cc-card" markdown>
### 🎯 Subagents with a user gate
`propose_agents` lets you review and approve batches of subagents before any of them runs. Each subagent has its own isolated context.
</div>

<div class="cc-card" markdown>
### 🪶 Lean mode
`/lean` trims the system prompt by ~500–800 tokens per turn for marathon sessions or pricier models.
</div>

<div class="cc-card" markdown>
### ✂️ Paste-aware input
Multi-line paste collapses to a tidy `[pasted N lines text]` placeholder. The full content is restored transparently on submit.
</div>

</div>

## 30-second tour

=== "Linux / macOS"

    ```bash
    # download cc-linux or cc-macos from the latest release
    chmod +x cc-linux
    export DEEPSEEK_API_KEY=sk-...
    ./cc-linux
    ```

=== "Windows"

    ```bat
    REM download cc.exe from the latest release
    set DEEPSEEK_API_KEY=sk-...
    cc.exe
    ```

Once running, type a request. The agent reads, edits, runs commands and replies inline. See [**Getting started**](getting-started.md) for the full walkthrough.

## Common use cases

- **Refactoring** — explore a foreign codebase, plan the change with `/plan`, watch the agent execute and diff every edit.
- **Code review** — activate the `code-review` skill, paste a diff, get a structured report with blocking and non-blocking findings.
- **Bug hunting** — the `debugging` skill enforces reproduce → isolate → hypothesise → verify before any patch lands.
- **Project bootstrap** — `/init` writes a `CC.md` so future runs already know your conventions.
- **CI lint runner** — pipe a prompt into `cc` in non-interactive mode; permissions stay strict, output goes to logs.

## Try it without installing

The [**web playground**](playground/index.html) runs a JavaScript port of CCHarbour entirely in the browser — file, web, github, memory and todo tools — using your own DeepSeek API key. Great for kicking the tyres before downloading anything.

---

CCHarbour is released under the [MIT licence](https://github.com/FiveTechSoft/CCHarbour/blob/master/LICENSE).
Read the [disclaimer](https://github.com/FiveTechSoft/CCHarbour#disclaimer) before granting `shell` permission on a machine you care about.

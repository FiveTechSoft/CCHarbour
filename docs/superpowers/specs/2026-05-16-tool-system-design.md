# Tool System — Design (Sub-project #3)

Date: 2026-05-16
Status: Approved for planning
Language: Harbour (MT build, hbmk2)
Depends on: nothing at runtime. Produced artifacts plug into sub-project #2
(`DS_AgentRun`).

## Context

Sub-project #3 of a Claude Code-style agentic client in Harbour. The agent loop
(#2) drives the model and, when the model requests a tool, calls an injectable
`tool_executor` codeblock `{| cToolName, cArgumentsJson | -> cResultString }`.
#2 also accepts a `tools` array of OpenAI function schemas.

#3 builds the real tool system: a registry of tool definitions, the six builtin
tools (`read`, `write`, `edit`, `glob`, `grep`, `shell`), and the two functions
that turn a registry into exactly the artifacts #2 expects — the schema array
and the executor codeblock.

Permissions are sub-project #5. #3 tools execute directly. Until #5 lands,
`shell` / `write` / `edit` run unguarded — acceptable for incremental build.

## Architecture

Four new modules, no runtime dependency on #1/#2 — an independent layer that #4
(UI) wires to the agent.

```
src/dstools.prg         Registry core: Registry, Register, Schemas, Executor
src/dstools_file.prg     read, write, edit tool handlers
src/dstools_search.prg   glob, grep tool handlers
src/dstools_shell.prg    shell tool handler
```

### Registry API

```
DSTools_Registry()             -> oReg    hash; registers the 6 builtins
DSTools_Register( oReg, hTool )            adds a tool (also for custom tools)
DSTools_Schemas( oReg )        -> aArray   OpenAI "tools" array for the API
DSTools_Executor( oReg )       -> bExec    codeblock {|cName,cArgsJson|->cString}
```

The registry `oReg` is a hash `{ toolName => hTool }`. No global state — each
`DSTools_Registry()` call returns a fresh, independent registry (pool-safe).

### Tool record

Each `hTool`:

```
{ "name"        => "read",
  "description" => "Read a file from disk ...",
  "parameters"  => { "type" => "object",
                     "properties" => { ... },
                     "required" => { "path" } },
  "handler"     => {| hArgs | -> cResultString } }
```

`parameters` is an OpenAI/JSON-schema hash. `handler` is a codeblock receiving
the parsed arguments hash and returning a result string.

### DSTools_Schemas

Returns an array, one entry per registered tool, in OpenAI function-tool form:

```
{ "type" => "function",
  "function" => { "name" => hTool.name,
                  "description" => hTool.description,
                  "parameters" => hTool.parameters } }
```

This array plugs straight into `DS_AgentRun`'s `hOpts["tools"]`.

### DSTools_Executor

Returns a codeblock `{| cName, cArgsJson | -> cResultString }` closing over
`oReg`. It plugs straight into `DS_AgentRun`'s `hOpts["tool_executor"]`. Per
invocation:

1. Look up `cName` in `oReg`. Missing -> return
   `"Error: unknown tool '<cName>'"`.
2. `hb_jsonDecode( cArgsJson )`. Not a hash -> return
   `"Error: invalid arguments JSON"`.
3. Validate each entry of the tool's `parameters.required` is present in the
   decoded hash. Missing -> return
   `"Error: missing required argument '<arg>'"`.
4. Call `handler( hArgs )` inside a `BEGIN SEQUENCE` net. An uncaught exception
   -> return `"Error: tool '<cName>' failed: <description>"`.
5. Return the handler's string.

The executor never throws.

## The Six Tools

Every handler catches its own domain errors and returns an error string; it
never throws. Argument hashes come pre-decoded from the executor.

### read — `{ path, offset?, max_lines? }`

Reads a text file. Output is line-numbered: `<6-wide right-justified n>` + tab +
line text. `offset` (default 0) skips that many leading lines. `max_lines`
(default 2000) caps emitted lines; lines longer than 2000 characters are cut
with a trailing `…`. When capped, a final line `[truncated: <N> more lines]` is
appended.
- File missing -> `"Error: file not found: <path>"`.

### write — `{ path, content }`

Writes `content` to `path`, overwriting. Creates missing parent directories.
- Success -> `"Wrote <N> bytes to <path>"`.
- Write failure -> `"Error: cannot write <path>: <reason>"`.

### edit — `{ path, old_string, new_string, replace_all? }`

Exact-string replacement. `old_string` must occur exactly once unless
`replace_all` is `.T.`.
- Success -> `"Edited <path> (<N> replacement(s))"`.
- File missing -> `"Error: file not found: <path>"`.
- `old_string` absent -> `"Error: old_string not found in <path>"`.
- `old_string` not unique without `replace_all` ->
  `"Error: old_string not unique (<N> matches); set replace_all or add context"`.

### glob — `{ pattern, path? }`

Matches a glob `pattern` (e.g. `**/*.prg`) under `path` (default current
directory). Returns one matching path per line, capped at 200; when capped a
final `[truncated: more matches]` line is appended.
- `path` missing -> `"Error: directory not found: <path>"`.
- No matches -> `"No matches for <pattern>"`.

### grep — `{ pattern, path?, glob? }`

Searches file contents with a regular expression. `path` (default current
directory) is the search root; `glob` optionally filters which files are
scanned. Returns one match per line as `<file>:<lineno>:<line text>`, capped at
200 matches; when capped a final `[truncated: more matches]` line is appended.
- Invalid regex -> `"Error: invalid regex: <pattern>"`.
- `path` missing -> `"Error: path not found: <path>"`.
- No matches -> `"No matches for <pattern>"`.

### shell — `{ command, shell?, timeout? }`

Runs `command` through `cmd.exe /c` by default; `shell` overrides the
interpreter (e.g. `powershell`). stdout and stderr are captured combined.
`timeout` (default 120) is in seconds. Output is capped at ~30000 bytes; when
capped a `[output truncated]` marker is inserted. The result string ends with a
final line `[exit code: <N>]`.
- Spawn failure -> `"Error: cannot run shell: <reason>"`.
- Timeout -> `"Error: command timed out after <N>s"`.

## Error Handling

The executor never throws — every path returns a string. Errors are reported as
strings the model reads and can act on (the error-as-tool-result decision from
#2). Three levels:

- **Executor level**: unknown tool, invalid arguments JSON, missing required
  argument, and a `BEGIN SEQUENCE` last-resort net around the handler call.
- **Handler level**: each tool catches its own domain errors (file not found,
  non-unique edit target, invalid regex, timeout, spawn failure) and returns the
  specific error strings listed above.
- **Partial arguments**: an optional argument of the wrong type (e.g.
  `max_lines` given as a string) is ignored and the default used — no failure.

No tool ever aborts the agent loop. The loop stops only on API failure or the
iteration cap, both already handled in #2.

## Testing

Reuses the #1/#2 harness: `tests/run_tests.prg` (`T_Assert` / `T_Equal`), a new
`Test_Tools()` entry point, and a new `tests/test_tools.prg`.

No network. File tools operate on temp files under `hb_DirTemp()`. The `shell`
tool runs the real `cmd.exe` with trivial commands (e.g. `echo`).

Test cases:

- **Registry**: `DSTools_Registry()` holds 6 tools; `DSTools_Schemas()` returns
  6 entries each with `type`/`function.name`/`function.parameters`;
  `DSTools_Register()` adds a custom tool that the executor can then dispatch.
- **Executor**: unknown tool -> error string; non-JSON / non-object arguments ->
  error string; missing required argument -> error string; valid call reaches
  the handler and returns its result.
- **read**: write a temp file, read it back with line numbers; `offset` skips
  leading lines; `max_lines` truncates and appends the truncation note; missing
  file -> error string.
- **write**: write a temp file, verify the bytes on disk; a path with a missing
  parent directory still succeeds (directory created).
- **edit**: unique replacement succeeds; non-unique target without `replace_all`
  -> error string; `replace_all` replaces every occurrence; missing file ->
  error string.
- **glob**: build a temp directory tree, match a pattern, verify the result and
  the 200-cap behaviour.
- **grep**: build temp files, match a regex, verify the `file:line:text` format,
  the `glob` filter, and that an invalid regex -> error string.
- **shell**: `echo hello` via `cmd` -> output contains `hello` and ends with
  `[exit code: 0]`; a failing command -> a non-zero exit code is captured in the
  result string.
- **End-to-end**: build the executor from a registry, call it with a JSON
  argument string exactly as the agent would, and verify the returned string.

Build: add `test_tools.prg` and the four `../src/dstools*.prg` files to
`tests/tests.hbp`; add a `Test_Tools()` call to the runner's `Main()`.

## Self-Review

- **Scope**: one registry plus six small tools — one coherent implementation
  plan. Focused.
- **Decomposition honoured**: #3 produces exactly the two artifacts #2 consumes
  (schema array, executor codeblock) and nothing else; permissions stay in #5;
  UI wiring stays in #4.
- **Deferred (out of scope for #3)**: permission gating of `shell`/`write`/`edit`
  (#5); terminal UI (#4); subagents and the thread pool (#6.5). MCP-provided
  tools (#6) will register through the same `DSTools_Register` seam.
- **Type consistency**: the `hTool` record (`name` / `description` /
  `parameters` / `handler`), the executor contract
  (`{|cName,cArgsJson|->cString}`), and the schema entry shape
  (`type` / `function`) are used identically throughout, and the executor and
  schema outputs match the `hOpts["tool_executor"]` / `hOpts["tools"]` inputs of
  `DS_AgentRun` from #2.
- **Placeholder scan**: no TBD / TODO; every tool and error string is concrete.

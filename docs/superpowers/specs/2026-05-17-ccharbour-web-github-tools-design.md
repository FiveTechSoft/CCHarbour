# CCHarbour — `web` and `github` tools (sub-project A)

**Date:** 2026-05-17
**Status:** Approved design, ready for implementation plan
**Scope:** Sub-project A of a two-part effort. Part B (a browser playground on
GitHub Pages that mirrors CCHarbour) is a separate spec, written after A.

## Goal

Add four new tools to native CCHarbour so the agent can search the web and
read/write GitHub:

- `web_search` — web search via the Tavily API.
- `web_fetch` — fetch the raw content of a URL.
- `github_read` — read-only GitHub queries (repo, files, issues, PRs, code search).
- `github_write` — GitHub mutations (create issue, comment, open PR).

These tools define the tool contract that sub-project B (the playground) will
mirror in JavaScript.

## Why grouped this way

Read and write GitHub operations are split into two tools so the permission
gate (`DSPerm_Gate`, keyed by tool name) can default `github_read` to `allow`
and `github_write` to `ask`. A single `github` tool would force write
operations through the same permission as reads. Within each tool, an
`operation` enum selects the specific call — keeping the registered tool list
compact, consistent with the project's minimal-surface style
(`src/dstools_shell.prg`).

## Files

New:

- `src/dstools_web.prg` — `web_search`, `web_fetch` tool factories + handlers.
- `src/dstools_github.prg` — `github_read`, `github_write` tool factories + handlers.
- `tests/test_web.prg` — tests for the web tools.
- `tests/test_github.prg` — tests for the github tools.

Modified:

- `src/dshttp.prg` — add `DSHTTP_Fetch()` (non-streaming GET/POST/PATCH).
- `src/dstools.prg` — `DSTools_Registry()` accepts optional `hKeys`; register the four new tools.
- `src/dssettings.prg` — add default permissions for the four new tools.
- `src/dsconfig.prg` — add `DSCFG_ResolveKey()` to resolve the Tavily key and GitHub token.
- `src/dsrepl.prg` (or the `Main` call site) — resolve keys, build `hKeys`, pass it to `DSTools_Registry()`.
- `cc.hbp` — add `src/dstools_web.prg`, `src/dstools_github.prg`.
- `tests/tests.hbp` — add `test_web.prg`, `test_github.prg`, and the two new src files.
- `tests/run_tests.prg` — call `Test_Web()` and `Test_Github()` from `Main()`.
- `pages/commands.md` (or the relevant docs page) — document the new tools.

## HTTP layer — `DSHTTP_Fetch`

The existing `DSHTTP_Post` is POST-only and streams chunks to a callback. The
new tools need whole-response GET/POST/PATCH. Add a sibling function; leave
`DSHTTP_Post` untouched.

```
FUNCTION DSHTTP_Fetch( hReq ) -> hResult
```

`hReq` keys:

- `url` — request URL (required).
- `method` — `"GET"` | `"POST"` | `"PATCH"` (default `"GET"`).
- `headers` — array of `"Key: Value"` strings (default `{}`).
- `body` — request body string (optional; sent for POST/PATCH).
- `timeout` — seconds (default `60`).
- `transport` — optional codeblock `{| hReq | -> hResult }` overriding curl, for tests.

`hResult` keys: `{ ok, status, body, error }`.

Implementation mirrors `DSHTTP_CurlPost`: spawn `curl.exe` with `-X <method>`,
`-D <headerfile>` for status, headers via `-H`, body via `--data-binary @-` on
stdin for POST/PATCH. Accumulate the full stdout into `body` instead of
streaming. Parse status with the existing `DSHTTP_ParseStatus` helper. When
`transport` is supplied, call it and return its result.

## `web_search`

- Endpoint: `POST https://api.tavily.com/search`.
- Header: `content-type: application/json`.
- Body JSON: `{ "api_key": <key>, "query": <query>, "max_results": <n>, "search_depth": "basic" }`.
- Schema params:
  - `query` — string, required.
  - `max_results` — integer, optional, default `5`.
- Handler: if the Tavily key is empty, return `"Error: TAVILY_API_KEY not set"`.
  Otherwise call `DSHTTP_Fetch`, decode the JSON, and format each result as
  `title` / `url` / `content` snippet, one block per result. Cap total output
  at 30000 bytes. On non-2xx status or transport failure, return an `Error:` string.

## `web_fetch`

- `GET <url>` via `DSHTTP_Fetch`.
- Schema params: `url` — string, required.
- Handler: return the response body, capped at 30000 bytes (matching
  `DSTool_ShellRun`), with a `[output truncated]` marker when capped. Raw
  text/HTML — no HTML-to-text conversion (Harbour has no HTML parser; documented
  in the tool description). Non-2xx status → `Error:` string including the status code.

## `github_read`

- Base: `https://api.github.com`.
- Headers: `Accept: application/vnd.github+json`, `User-Agent: CCHarbour`,
  and `Authorization: Bearer <token>` when a token is present (optional; without
  it the API works but is rate-limited to 60 requests/hour).
- Schema params:
  - `operation` — string enum, required: `repo`, `file`, `list`, `issues`,
    `issue`, `prs`, `pr`, `search`.
  - `repo` — `"owner/name"` (required for every operation except `search`).
  - `path` — file or directory path (required for `file`, `list`).
  - `number` — issue/PR number (required for `issue`, `pr`).
  - `query` — code-search query (required for `search`).
- Operation → endpoint:
  - `repo` → `GET /repos/{owner}/{repo}`
  - `file` → `GET /repos/{owner}/{repo}/contents/{path}` — base64-decode the `content` field.
  - `list` → `GET /repos/{owner}/{repo}/contents/{dir}` — list entry names + types.
  - `issues` → `GET /repos/{owner}/{repo}/issues`
  - `issue` → `GET /repos/{owner}/{repo}/issues/{number}`
  - `prs` → `GET /repos/{owner}/{repo}/pulls`
  - `pr` → `GET /repos/{owner}/{repo}/pulls/{number}`
  - `search` → `GET /search/code?q={query}`
- Handler validates the params required by the chosen operation, calls
  `DSHTTP_Fetch`, and formats a compact text summary. Cap output at 30000 bytes.

## `github_write`

- Same base/headers as `github_read`. A token is **mandatory**: if absent,
  the handler returns `"Error: GITHUB_TOKEN not set"`.
- Schema params:
  - `operation` — string enum, required: `create_issue`, `comment`, `create_pr`.
  - `repo` — `"owner/name"`, required.
  - `number` — issue number (required for `comment`).
  - `title` — required for `create_issue`, `create_pr`.
  - `body` — issue/PR/comment body.
  - `head`, `base` — branch names (required for `create_pr`).
- Operation → request:
  - `create_issue` → `POST /repos/{owner}/{repo}/issues` body `{title, body}`
  - `comment` → `POST /repos/{owner}/{repo}/issues/{number}/comments` body `{body}`
  - `create_pr` → `POST /repos/{owner}/{repo}/pulls` body `{title, head, base, body}`
- On success return the created resource URL/number; on non-2xx return an
  `Error:` string including the status and the API message.

## Keys and configuration

Two new secrets: the Tavily API key and the GitHub token. Resolution order
(env first, then settings file):

1. Environment: `TAVILY_API_KEY`, `GITHUB_TOKEN`.
2. `settings.json` top-level keys: `tavily_api_key`, `github_token`.

Add to `src/dsconfig.prg`:

```
FUNCTION DSCFG_ResolveKey( cEnvName, cSettingKey, hSettings ) -> cKey
```

Returns the env var if set, else `hSettings[cSettingKey]` if present, else `""`.

The `Main`/`dsrepl.prg` call site resolves both keys, builds
`hKeys := { "tavily" => <key>, "github" => <token> }`, and passes it to
`DSTools_Registry( hKeys )`.

## Registry wiring

`DSTools_Registry()` gains an optional `hKeys` parameter (default `{=>}`), so
existing no-arg callers and tests keep working:

```
FUNCTION DSTools_Registry( hKeys )
   LOCAL oReg := {=>}
   IF ValType( hKeys ) != "H" ; hKeys := {=>} ; ENDIF
   ...existing six registrations...
   DSTools_Register( oReg, DSTool_WebSearch( hb_HGetDef( hKeys, "tavily", "" ) ) )
   DSTools_Register( oReg, DSTool_WebFetch() )
   DSTools_Register( oReg, DSTool_GithubRead( hb_HGetDef( hKeys, "github", "" ) ) )
   DSTools_Register( oReg, DSTool_GithubWrite( hb_HGetDef( hKeys, "github", "" ) ) )
   RETURN oReg
```

Tool factories that need a key take it as an argument and capture it in the
handler closure. The tools are always registered even when a key is missing —
the handler returns a clear `Error:` string at call time rather than the tool
silently disappearing.

## Permissions

Add to the `permissions` hash in `DSSettings_Defaults()`:

```
"web_search"   => "ask",
"web_fetch"    => "ask",
"github_read"  => "allow",
"github_write" => "ask"
```

`web_*` default to `ask` because each call spends a Tavily quota / makes
network egress. `github_read` is read-only and free → `allow`. `github_write`
mutates remote state → `ask`.

## Testing

Every HTTP path is tested through the `transport` injection point on
`DSHTTP_Fetch`, mirroring the existing `bTransport` pattern in `Test_Http`. No
test makes a real network call.

`tests/test_web.prg` — `Test_Web()`:

- Schema shape for `web_search` and `web_fetch` (name, type, required params).
- `web_search` missing-key → `"Error: TAVILY_API_KEY not set"`.
- `web_search` formats a mocked Tavily JSON response into result blocks.
- `web_fetch` returns a mocked body; output capped at 30000 bytes.
- Non-2xx status → `Error:` string.

`tests/test_github.prg` — `Test_Github()`:

- Schema shape for `github_read` and `github_write`.
- `github_read` argument validation: missing `repo`, missing `operation`,
  missing op-specific params (`path`, `number`, `query`).
- `github_read` `file` operation base64-decodes mocked content.
- `github_read` `search` operation formats mocked results.
- `github_write` missing-token → `"Error: GITHUB_TOKEN not set"`.
- `github_write` `create_issue` builds the correct request and parses the
  mocked created-issue response.
- `DSHTTP_Fetch` itself: `transport` override returns `{ ok, status, body }`;
  default method is `GET`.

Both new test functions are wired into `tests/run_tests.prg` `Main()` and
`tests/tests.hbp`.

## Out of scope

- The browser playground (sub-project B) — separate spec.
- New native tools beyond the four above.
- Streaming for the new tools — they are whole-response.
- HTML-to-text conversion in `web_fetch`.

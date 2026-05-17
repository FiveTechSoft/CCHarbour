# CCHarbour web & github tools — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four native tools to CCHarbour — `web_search`, `web_fetch`, `github_read`, `github_write` — so the agent can search the web (via Tavily) and read/write GitHub.

**Architecture:** A new non-streaming HTTP helper (`DSHTTP_Fetch`) wraps `curl.exe` and returns the whole response. Two new tool modules register four tools whose handlers call `DSHTTP_Fetch`. API keys are resolved at startup (env → settings.json) and captured in tool closures. Read/write GitHub are split into two tools so the permission gate can default reads to `allow` and writes to `ask`.

**Tech Stack:** Harbour 3.2, `curl.exe` (system), Tavily API, GitHub REST API. Tests use Harbour's existing `T_Equal`/`T_Assert` harness with an injected HTTP transport — no real network calls.

**Spec:** `docs/superpowers/specs/2026-05-17-ccharbour-web-github-tools-design.md`

---

## Build & test commands

- Build the test runner: from `tests/`, run `hbmk2 tests.hbp`.
- Run tests: from `tests/`, run `run_tests.exe`. Exit code 0 = all pass, 1 = failures.
- Build the app: run `build.bat` from the repo root.

A Harbour 3.2 install and `curl.exe` (ships with Windows 10/11) are required.

---

## Task 1: Non-streaming HTTP — `DSHTTP_Fetch`

**Files:**
- Modify: `src/dshttp.prg` (append new functions)
- Test: `tests/test_http.prg` (extend `Test_Http`)

- [ ] **Step 1: Write the failing test**

Append these blocks inside `Test_Http()` in `tests/test_http.prg`, before `RETURN NIL`:

```harbour
   // --- DSHTTP_Fetch ---

   // per-request transport override returns its result verbatim
   hRes := DSHTTP_Fetch( { "url" => "https://x/y", "transport" => ;
      {| hR | HB_SYMBOL_UNUSED( hR ), ;
              { "ok" => .T., "status" => 200, "body" => "hello", "error" => "" } } } )
   T_Equal( hRes[ "ok" ], .T., "fetch: transport ok" )
   T_Equal( hRes[ "status" ], 200, "fetch: transport status" )
   T_Equal( hRes[ "body" ], "hello", "fetch: transport body" )

   // the module-level test transport is used when no per-request one is set
   DSHTTP_SetTestTransport( {| hR | ;
      { "ok" => .T., "status" => 201, "body" => "M:" + hR[ "method" ], "error" => "" } } )
   hRes := DSHTTP_Fetch( { "url" => "https://x", "method" => "POST" } )
   T_Equal( hRes[ "status" ], 201, "fetch: module transport status" )
   T_Equal( hRes[ "body" ], "M:POST", "fetch: method passthrough" )
   DSHTTP_SetTestTransport( NIL )
```

- [ ] **Step 2: Run test to verify it fails**

Run: from `tests/`, `hbmk2 tests.hbp`
Expected: compile error / link error — `DSHTTP_Fetch` and `DSHTTP_SetTestTransport` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `src/dshttp.prg`:

```harbour
// Module-level test transport. When set (and no per-request transport is
// given), DSHTTP_Fetch routes through it instead of curl.exe. Tests only.
STATIC s_bTestTransport := NIL

// Installs (or clears, with NIL) the module-level test transport.
FUNCTION DSHTTP_SetTestTransport( bBlock )
   s_bTestTransport := bBlock
   RETURN NIL

// Performs a non-streaming HTTP request.
// hReq: { url, method ("GET"/"POST"/"PATCH", default GET), headers (array of
//         "K: V"), body (string, sent for POST/PATCH), timeout (seconds,
//         default 60), transport (optional {|hReq| -> hResult} override) }.
// Returns: { ok, status, body, error }.
FUNCTION DSHTTP_Fetch( hReq )
   IF hb_HHasKey( hReq, "transport" ) .AND. hReq[ "transport" ] != NIL
      RETURN Eval( hReq[ "transport" ], hReq )
   ENDIF
   IF s_bTestTransport != NIL
      RETURN Eval( s_bTestTransport, hReq )
   ENDIF
   RETURN DSHTTP_CurlFetch( hReq )

// Real transport: spawns curl.exe and accumulates its whole stdout.
STATIC FUNCTION DSHTTP_CurlFetch( hReq )
   LOCAL hProc, hIn, hOut, hErr, hTmp
   LOCAL cHdrFile := "", cCmd, cHdr, nTimeout, cMethod
   LOCAL cBuf := Space( 16384 ), nRead
   LOCAL nExit, nStatus := 0, cErr := "", cBody := ""
   LOCAL aHeaders, cReqBody, lHasBody

   cMethod := iif( hb_HHasKey( hReq, "method" ) .AND. !Empty( hReq[ "method" ] ), ;
                   Upper( hb_CStr( hReq[ "method" ] ) ), "GET" )
   nTimeout := iif( hb_HHasKey( hReq, "timeout" ) .AND. ;
                    ValType( hReq[ "timeout" ] ) == "N", hReq[ "timeout" ], 60 )
   aHeaders := iif( hb_HHasKey( hReq, "headers" ) .AND. ;
                    ValType( hReq[ "headers" ] ) == "A", hReq[ "headers" ], {} )
   cReqBody := iif( hb_HHasKey( hReq, "body" ) .AND. ;
                    ValType( hReq[ "body" ] ) == "C", hReq[ "body" ], "" )
   lHasBody := !Empty( cReqBody ) .AND. ( cMethod == "POST" .OR. cMethod == "PATCH" )

   hTmp := hb_FTempCreateEx( @cHdrFile, hb_DirTemp(), "dsf", ".hdr" )
   IF hTmp != F_ERROR
      FClose( hTmp )
   ENDIF

   cCmd := "curl.exe -sS --max-time " + LTrim( Str( nTimeout ) ) + ;
           " -X " + cMethod + " -D " + Chr( 34 ) + cHdrFile + Chr( 34 )
   IF lHasBody
      cCmd += " --data-binary @-"
   ENDIF
   FOR EACH cHdr IN aHeaders
      cCmd += " -H " + Chr( 34 ) + cHdr + Chr( 34 )
   NEXT
   cCmd += " " + Chr( 34 ) + hReq[ "url" ] + Chr( 34 )

   hProc := hb_processOpen( cCmd, @hIn, @hOut, @hErr )
   IF hProc == F_ERROR
      IF !Empty( cHdrFile )
         FErase( cHdrFile )
      ENDIF
      RETURN { "ok" => .F., "status" => 0, "body" => "", ;
               "error" => "failed to spawn curl.exe" }
   ENDIF

   IF lHasBody
      FWrite( hIn, cReqBody )
   ENDIF
   FClose( hIn )

   DO WHILE ( nRead := FRead( hOut, @cBuf, hb_BLen( cBuf ) ) ) > 0
      cBody += hb_BLeft( cBuf, nRead )
   ENDDO
   DO WHILE ( nRead := FRead( hErr, @cBuf, hb_BLen( cBuf ) ) ) > 0
      cErr += hb_BLeft( cBuf, nRead )
   ENDDO

   FClose( hOut )
   FClose( hErr )
   nExit := hb_processValue( hProc )

   nStatus := DSHTTP_ParseStatus( cHdrFile )
   FErase( cHdrFile )

   RETURN { "ok" => ( nExit == 0 ), "status" => nStatus, "body" => cBody, ;
            "error" => iif( nExit == 0, "", ;
               iif( Empty( cErr ), "curl exit " + LTrim( Str( nExit ) ), ;
                    AllTrim( cErr ) ) ) }
```

`DSHTTP_ParseStatus` already exists as a STATIC in this file and is reachable from `DSHTTP_CurlFetch`.

- [ ] **Step 4: Run tests to verify they pass**

Run: from `tests/`, `hbmk2 tests.hbp` then `run_tests.exe`
Expected: PASS — the four new `fetch:` assertions pass, no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/dshttp.prg tests/test_http.prg
git commit -m "feat: add non-streaming DSHTTP_Fetch for GET/POST/PATCH"
```

---

## Task 2: Key resolution — `DSCFG_ResolveKey`

**Files:**
- Modify: `src/dsconfig.prg` (append)
- Test: `tests/test_config.prg` (extend `Test_Config`)

- [ ] **Step 1: Write the failing test**

Append inside `Test_Config()` in `tests/test_config.prg`, before `RETURN NIL`:

```harbour
   // --- DSCFG_ResolveKey ---

   // settings hash value is used when the env var is unset
   hR := DSCFG_ResolveKey( "CCHARBOUR_NO_SUCH_ENV", "tavily_api_key", ;
                           { "tavily_api_key" => "from-settings" } )
   T_Equal( hR, "from-settings", "resolvekey: settings fallback" )

   // empty everywhere -> empty string
   hR := DSCFG_ResolveKey( "CCHARBOUR_NO_SUCH_ENV", "github_token", {=>} )
   T_Equal( hR, "", "resolvekey: empty when unset" )

   // env var wins over the settings hash
   hb_SetEnv( "CCHARBOUR_TEST_KEY", "from-env" )
   hR := DSCFG_ResolveKey( "CCHARBOUR_TEST_KEY", "tavily_api_key", ;
                           { "tavily_api_key" => "from-settings" } )
   T_Equal( hR, "from-env", "resolvekey: env wins" )
   hb_SetEnv( "CCHARBOUR_TEST_KEY", "" )
```

- [ ] **Step 2: Run test to verify it fails**

Run: from `tests/`, `hbmk2 tests.hbp`
Expected: compile/link error — `DSCFG_ResolveKey` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `src/dsconfig.prg`:

```harbour
// Resolves a secret value. Precedence: environment variable cEnvName, then
// hSettings[ cSettingKey ]. Returns "" when neither is set.
FUNCTION DSCFG_ResolveKey( cEnvName, cSettingKey, hSettings )
   LOCAL cEnv := hb_GetEnv( cEnvName )
   IF !Empty( cEnv )
      RETURN cEnv
   ENDIF
   IF ValType( hSettings ) == "H" .AND. hb_HHasKey( hSettings, cSettingKey ) .AND. ;
      ValType( hSettings[ cSettingKey ] ) == "C"
      RETURN hSettings[ cSettingKey ]
   ENDIF
   RETURN ""
```

- [ ] **Step 4: Run tests to verify they pass**

Run: from `tests/`, `hbmk2 tests.hbp` then `run_tests.exe`
Expected: PASS — three new `resolvekey:` assertions pass, no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/dsconfig.prg tests/test_config.prg
git commit -m "feat: add DSCFG_ResolveKey for env/settings secret resolution"
```

---

## Task 3: `web_fetch` tool

**Files:**
- Create: `src/dstools_web.prg`
- Create: `tests/test_web.prg`
- Modify: `cc.hbp`, `tests/tests.hbp`, `tests/run_tests.prg`

- [ ] **Step 1: Wire the new files into the build and test harness**

Add `src/dstools_web.prg` to `cc.hbp` (after `src/dstools_shell.prg`):

```
src/dstools_web.prg
```

Add to `tests/tests.hbp` — `test_web.prg` after `test_tools.prg`, and the src file after `../src/dstools_shell.prg`:

```
test_web.prg
```
```
../src/dstools_web.prg
```

In `tests/run_tests.prg`, add a call to `Test_Web()` in `Main()` after `Test_Tools()`:

```harbour
   Test_Tools()
   Test_Web()
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_web.prg`:

```harbour
// Returns the schema entry for cName from an aSchemas array, or NIL.
STATIC FUNCTION WebFindSchema( aSchemas, cName )
   LOCAL h
   FOR EACH h IN aSchemas
      IF h[ "function" ][ "name" ] == cName
         RETURN h
      ENDIF
   NEXT
   RETURN NIL

FUNCTION Test_Web()
   LOCAL hTool, hSchema, cRes

   // --- web_fetch schema ---
   hTool := DSTool_WebFetch()
   T_Equal( hTool[ "name" ], "web_fetch", "web_fetch: tool name" )
   hSchema := WebFindSchema( DSTools_Schemas( { "web_fetch" => hTool } ), "web_fetch" )
   T_Assert( hSchema != NIL, "web_fetch: schema present" )
   T_Equal( hSchema[ "function" ][ "parameters" ][ "required" ][ 1 ], "url", ;
            "web_fetch: url required" )

   // --- web_fetch returns the body on HTTP 200 ---
   DSHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 200, "body" => "page-content", "error" => "" } } )
   cRes := Eval( hTool[ "handler" ], { "url" => "https://example.com" } )
   T_Equal( cRes, "page-content", "web_fetch: returns body" )
   DSHTTP_SetTestTransport( NIL )

   // --- web_fetch reports a non-2xx status ---
   DSHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 404, "body" => "", "error" => "" } } )
   cRes := Eval( hTool[ "handler" ], { "url" => "https://example.com/x" } )
   T_Equal( cRes, "Error: web_fetch HTTP 404", "web_fetch: non-2xx error" )
   DSHTTP_SetTestTransport( NIL )

   RETURN NIL
```

- [ ] **Step 3: Run test to verify it fails**

Run: from `tests/`, `hbmk2 tests.hbp`
Expected: compile/link error — `DSTool_WebFetch` undefined.

- [ ] **Step 4: Write minimal implementation**

Create `src/dstools_web.prg` with the `web_fetch` tool:

```harbour
// Web tools for CCHarbour: web_fetch (retrieve a URL) and web_search (Tavily).

// web_fetch: retrieves the raw content of a URL.
FUNCTION DSTool_WebFetch()
   RETURN { "name" => "web_fetch", ;
            "description" => "Fetch the raw content of a URL (text or HTML, not converted to plain text).", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "url" => { "type" => "string", ;
                             "description" => "The URL to fetch" } }, ;
               "required" => { "url" } }, ;
            "handler" => {| hArgs | DSTool_WebFetchRun( hArgs ) } }

STATIC FUNCTION DSTool_WebFetchRun( hArgs )
   LOCAL hRes, cBody
   hRes := DSHTTP_Fetch( { "url" => hb_CStr( hArgs[ "url" ] ), "method" => "GET" } )
   IF !hRes[ "ok" ]
      RETURN "Error: web_fetch failed: " + hRes[ "error" ]
   ENDIF
   IF hRes[ "status" ] < 200 .OR. hRes[ "status" ] >= 300
      RETURN "Error: web_fetch HTTP " + LTrim( Str( hRes[ "status" ] ) )
   ENDIF
   cBody := hRes[ "body" ]
   IF hb_BLen( cBody ) > 30000
      cBody := hb_BLeft( cBody, 30000 ) + Chr( 10 ) + "[output truncated]" + Chr( 10 )
   ENDIF
   RETURN cBody
```

- [ ] **Step 5: Run tests to verify they pass**

Run: from `tests/`, `hbmk2 tests.hbp` then `run_tests.exe`
Expected: PASS — all `web_fetch:` assertions pass, no regressions.

- [ ] **Step 6: Commit**

```bash
git add src/dstools_web.prg tests/test_web.prg cc.hbp tests/tests.hbp tests/run_tests.prg
git commit -m "feat: add web_fetch tool"
```

---

## Task 4: `web_search` tool (Tavily)

**Files:**
- Modify: `src/dstools_web.prg` (append)
- Test: `tests/test_web.prg` (extend `Test_Web`)

- [ ] **Step 1: Write the failing test**

Append inside `Test_Web()` in `tests/test_web.prg`, before `RETURN NIL`:

```harbour
   // --- web_search schema ---
   hTool := DSTool_WebSearch( "fake-key" )
   T_Equal( hTool[ "name" ], "web_search", "web_search: tool name" )

   // --- web_search missing key ---
   hTool := DSTool_WebSearch( "" )
   cRes := Eval( hTool[ "handler" ], { "query" => "harbour lang" } )
   T_Equal( cRes, "Error: TAVILY_API_KEY not set", "web_search: missing key" )

   // --- web_search formats a Tavily response ---
   hTool := DSTool_WebSearch( "fake-key" )
   DSHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 200, "error" => "", ;
        "body" => hb_jsonEncode( { "results" => { ;
           { "title" => "T1", "url" => "U1", "content" => "C1" } } } ) } } )
   cRes := Eval( hTool[ "handler" ], { "query" => "x" } )
   T_Assert( "T1" $ cRes .AND. "U1" $ cRes .AND. "C1" $ cRes, ;
             "web_search: formats results" )
   DSHTTP_SetTestTransport( NIL )

   // --- web_search reports a non-2xx status ---
   DSHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 401, "body" => "", "error" => "" } } )
   cRes := Eval( hTool[ "handler" ], { "query" => "x" } )
   T_Equal( cRes, "Error: web_search HTTP 401", "web_search: non-2xx error" )
   DSHTTP_SetTestTransport( NIL )
```

- [ ] **Step 2: Run test to verify it fails**

Run: from `tests/`, `hbmk2 tests.hbp`
Expected: compile/link error — `DSTool_WebSearch` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `src/dstools_web.prg`:

```harbour
// web_search: searches the web via the Tavily API. cApiKey is captured at
// registry-build time; an empty key yields a clear error at call time.
FUNCTION DSTool_WebSearch( cApiKey )
   RETURN { "name" => "web_search", ;
            "description" => "Search the web via the Tavily API. Returns ranked title/url/snippet results.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "query" => { "type" => "string", ;
                               "description" => "The search query" }, ;
                  "max_results" => { "type" => "integer", ;
                               "description" => "Maximum number of results (default 5)" } }, ;
               "required" => { "query" } }, ;
            "handler" => {| hArgs | DSTool_WebSearchRun( hArgs, cApiKey ) } }

STATIC FUNCTION DSTool_WebSearchRun( hArgs, cApiKey )
   LOCAL hRes, xBody, cReqBody, nMax, h1, cOut := ""
   IF Empty( cApiKey )
      RETURN "Error: TAVILY_API_KEY not set"
   ENDIF
   nMax := iif( hb_HHasKey( hArgs, "max_results" ) .AND. ;
                ValType( hArgs[ "max_results" ] ) == "N", hArgs[ "max_results" ], 5 )
   cReqBody := hb_jsonEncode( { "api_key"      => cApiKey, ;
                                "query"        => hb_CStr( hArgs[ "query" ] ), ;
                                "max_results"  => nMax, ;
                                "search_depth" => "basic" } )
   hRes := DSHTTP_Fetch( { "url"     => "https://api.tavily.com/search", ;
                           "method"  => "POST", ;
                           "headers" => { "content-type: application/json" }, ;
                           "body"    => cReqBody } )
   IF !hRes[ "ok" ]
      RETURN "Error: web_search failed: " + hRes[ "error" ]
   ENDIF
   IF hRes[ "status" ] < 200 .OR. hRes[ "status" ] >= 300
      RETURN "Error: web_search HTTP " + LTrim( Str( hRes[ "status" ] ) )
   ENDIF
   xBody := hb_jsonDecode( hRes[ "body" ] )
   IF ValType( xBody ) != "H" .OR. !hb_HHasKey( xBody, "results" ) .OR. ;
      ValType( xBody[ "results" ] ) != "A"
      RETURN "Error: web_search: unexpected response"
   ENDIF
   FOR EACH h1 IN xBody[ "results" ]
      cOut += hb_CStr( h1[ "title" ] ) + Chr( 10 ) + ;
              hb_CStr( h1[ "url" ] ) + Chr( 10 ) + ;
              hb_CStr( h1[ "content" ] ) + Chr( 10 ) + Chr( 10 )
   NEXT
   IF Empty( cOut )
      RETURN "No results for " + hb_CStr( hArgs[ "query" ] )
   ENDIF
   IF hb_BLen( cOut ) > 30000
      cOut := hb_BLeft( cOut, 30000 ) + Chr( 10 ) + "[output truncated]" + Chr( 10 )
   ENDIF
   RETURN cOut
```

- [ ] **Step 4: Run tests to verify they pass**

Run: from `tests/`, `hbmk2 tests.hbp` then `run_tests.exe`
Expected: PASS — all `web_search:` assertions pass, no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/dstools_web.prg tests/test_web.prg
git commit -m "feat: add web_search tool (Tavily)"
```

---

## Task 5: `github_read` tool

**Files:**
- Create: `src/dstools_github.prg`
- Create: `tests/test_github.prg`
- Modify: `cc.hbp`, `tests/tests.hbp`, `tests/run_tests.prg`

- [ ] **Step 1: Wire the new files into the build and test harness**

Add `src/dstools_github.prg` to `cc.hbp` (after `src/dstools_web.prg`):

```
src/dstools_github.prg
```

Add to `tests/tests.hbp` — `test_github.prg` after `test_web.prg`, and the src file after `../src/dstools_web.prg`:

```
test_github.prg
```
```
../src/dstools_github.prg
```

In `tests/run_tests.prg`, add a call to `Test_Github()` in `Main()` after `Test_Web()`:

```harbour
   Test_Web()
   Test_Github()
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_github.prg`:

```harbour
FUNCTION Test_Github()
   LOCAL hTool, cRes, cFileJson

   // --- github_read schema ---
   hTool := DSTool_GithubRead( "" )
   T_Equal( hTool[ "name" ], "github_read", "github_read: tool name" )
   T_Equal( hTool[ "parameters" ][ "required" ][ 1 ], "operation", ;
            "github_read: operation required" )

   // --- argument validation ---
   cRes := Eval( hTool[ "handler" ], { "operation" => "repo" } )
   T_Equal( cRes, "Error: github_read 'repo' requires 'repo'", ;
            "github_read: missing repo" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "file", "repo" => "a/b" } )
   T_Equal( cRes, "Error: github_read 'file' requires 'path'", ;
            "github_read: missing path" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "search" } )
   T_Equal( cRes, "Error: github_read 'search' requires 'query'", ;
            "github_read: missing query" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "bogus", "repo" => "a/b" } )
   T_Equal( cRes, "Error: github_read: unknown operation 'bogus'", ;
            "github_read: unknown op" )

   // --- file operation base64-decodes content ---
   cFileJson := hb_jsonEncode( { "content" => hb_base64Encode( "hello world" ), ;
                                 "encoding" => "base64" } )
   DSHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 200, "body" => cFileJson, "error" => "" } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "file", "repo" => "a/b", "path" => "README.md" } )
   T_Equal( cRes, "hello world", "github_read: file decodes base64" )
   DSHTTP_SetTestTransport( NIL )

   // --- non-2xx surfaces the API message ---
   DSHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 404, "error" => "", ;
        "body" => hb_jsonEncode( { "message" => "Not Found" } ) } } )
   cRes := Eval( hTool[ "handler" ], { "operation" => "repo", "repo" => "a/b" } )
   T_Equal( cRes, "Error: github_read HTTP 404: Not Found", ;
            "github_read: non-2xx with message" )
   DSHTTP_SetTestTransport( NIL )

   RETURN NIL
```

- [ ] **Step 3: Run test to verify it fails**

Run: from `tests/`, `hbmk2 tests.hbp`
Expected: compile/link error — `DSTool_GithubRead` undefined.

- [ ] **Step 4: Write minimal implementation**

Create `src/dstools_github.prg`:

```harbour
// GitHub tools for CCHarbour: github_read (queries) and github_write (mutations).

// Builds the standard GitHub API request headers; adds auth when a token is set.
STATIC FUNCTION DSGithub_Headers( cToken )
   LOCAL aHdr := { "Accept: application/vnd.github+json", ;
                   "User-Agent: CCHarbour", ;
                   "Content-Type: application/json" }
   IF !Empty( cToken )
      AAdd( aHdr, "Authorization: Bearer " + cToken )
   ENDIF
   RETURN aHdr

// Percent-encodes a string for use in a URL query component.
STATIC FUNCTION DSGithub_UrlEncode( cText )
   LOCAL cOut := "", i, c
   FOR i := 1 TO Len( cText )
      c := SubStr( cText, i, 1 )
      IF ( c >= "A" .AND. c <= "Z" ) .OR. ( c >= "a" .AND. c <= "z" ) .OR. ;
         ( c >= "0" .AND. c <= "9" ) .OR. c $ "-_.~"
         cOut += c
      ELSE
         cOut += "%" + PadL( Upper( hb_NumToHex( Asc( c ) ) ), 2, "0" )
      ENDIF
   NEXT
   RETURN cOut

// Extracts the "message" field from a GitHub error JSON body, or "".
STATIC FUNCTION DSGithub_ApiMessage( cBody )
   LOCAL xJson := hb_jsonDecode( cBody )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "message" )
      RETURN hb_CStr( xJson[ "message" ] )
   ENDIF
   RETURN ""

// github_read: read-only GitHub queries. cToken is optional (unauthenticated
// requests work but are rate-limited).
FUNCTION DSTool_GithubRead( cToken )
   RETURN { "name" => "github_read", ;
            "description" => "Read from GitHub: repo info, file content, directory listing, issues, pull requests, code search.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "operation" => { "type" => "string", ;
                     "description" => "One of: repo, file, list, issues, issue, prs, pr, search" }, ;
                  "repo" => { "type" => "string", ;
                     "description" => "Repository as owner/name (every operation except search)" }, ;
                  "path" => { "type" => "string", ;
                     "description" => "File or directory path (file, list)" }, ;
                  "number" => { "type" => "integer", ;
                     "description" => "Issue or PR number (issue, pr)" }, ;
                  "query" => { "type" => "string", ;
                     "description" => "Code search query (search)" } }, ;
               "required" => { "operation" } }, ;
            "handler" => {| hArgs | DSTool_GithubReadRun( hArgs, cToken ) } }

STATIC FUNCTION DSTool_GithubReadRun( hArgs, cToken )
   LOCAL cOp, cRepo, cUrl, hRes
   cOp := Lower( hb_CStr( hArgs[ "operation" ] ) )
   IF cOp == "search"
      IF !hb_HHasKey( hArgs, "query" ) .OR. Empty( hArgs[ "query" ] )
         RETURN "Error: github_read 'search' requires 'query'"
      ENDIF
      cUrl := "https://api.github.com/search/code?q=" + ;
              DSGithub_UrlEncode( hb_CStr( hArgs[ "query" ] ) )
   ELSE
      IF !hb_HHasKey( hArgs, "repo" ) .OR. Empty( hArgs[ "repo" ] )
         RETURN "Error: github_read '" + cOp + "' requires 'repo'"
      ENDIF
      cRepo := hb_CStr( hArgs[ "repo" ] )
      DO CASE
      CASE cOp == "repo"
         cUrl := "https://api.github.com/repos/" + cRepo
      CASE cOp == "file" .OR. cOp == "list"
         IF !hb_HHasKey( hArgs, "path" ) .OR. Empty( hArgs[ "path" ] )
            RETURN "Error: github_read '" + cOp + "' requires 'path'"
         ENDIF
         cUrl := "https://api.github.com/repos/" + cRepo + "/contents/" + ;
                 hb_CStr( hArgs[ "path" ] )
      CASE cOp == "issues"
         cUrl := "https://api.github.com/repos/" + cRepo + "/issues"
      CASE cOp == "issue"
         IF !hb_HHasKey( hArgs, "number" )
            RETURN "Error: github_read 'issue' requires 'number'"
         ENDIF
         cUrl := "https://api.github.com/repos/" + cRepo + "/issues/" + ;
                 LTrim( Str( hArgs[ "number" ] ) )
      CASE cOp == "prs"
         cUrl := "https://api.github.com/repos/" + cRepo + "/pulls"
      CASE cOp == "pr"
         IF !hb_HHasKey( hArgs, "number" )
            RETURN "Error: github_read 'pr' requires 'number'"
         ENDIF
         cUrl := "https://api.github.com/repos/" + cRepo + "/pulls/" + ;
                 LTrim( Str( hArgs[ "number" ] ) )
      OTHERWISE
         RETURN "Error: github_read: unknown operation '" + cOp + "'"
      ENDCASE
   ENDIF
   hRes := DSHTTP_Fetch( { "url" => cUrl, "method" => "GET", ;
                           "headers" => DSGithub_Headers( cToken ) } )
   IF !hRes[ "ok" ]
      RETURN "Error: github_read failed: " + hRes[ "error" ]
   ENDIF
   IF hRes[ "status" ] < 200 .OR. hRes[ "status" ] >= 300
      RETURN "Error: github_read HTTP " + LTrim( Str( hRes[ "status" ] ) ) + ": " + ;
             DSGithub_ApiMessage( hRes[ "body" ] )
   ENDIF
   RETURN DSGithub_FormatRead( cOp, hRes[ "body" ] )

// Formats a successful github_read response by operation.
STATIC FUNCTION DSGithub_FormatRead( cOp, cBody )
   LOCAL xJson, cText, h1
   DO CASE
   CASE cOp == "file"
      xJson := hb_jsonDecode( cBody )
      IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "content" )
         RETURN hb_base64Decode( StrTran( hb_CStr( xJson[ "content" ] ), Chr( 10 ), "" ) )
      ENDIF
      RETURN cBody
   CASE cOp == "list"
      xJson := hb_jsonDecode( cBody )
      IF ValType( xJson ) == "A"
         cText := ""
         FOR EACH h1 IN xJson
            cText += hb_CStr( h1[ "type" ] ) + "  " + hb_CStr( h1[ "name" ] ) + Chr( 10 )
         NEXT
         RETURN cText
      ENDIF
      RETURN cBody
   ENDCASE
   IF hb_BLen( cBody ) > 30000
      RETURN hb_BLeft( cBody, 30000 ) + Chr( 10 ) + "[output truncated]" + Chr( 10 )
   ENDIF
   RETURN cBody
```

- [ ] **Step 5: Run tests to verify they pass**

Run: from `tests/`, `hbmk2 tests.hbp` then `run_tests.exe`
Expected: PASS — all `github_read:` assertions pass, no regressions.

- [ ] **Step 6: Commit**

```bash
git add src/dstools_github.prg tests/test_github.prg cc.hbp tests/tests.hbp tests/run_tests.prg
git commit -m "feat: add github_read tool"
```

---

## Task 6: `github_write` tool

**Files:**
- Modify: `src/dstools_github.prg` (append)
- Test: `tests/test_github.prg` (extend `Test_Github`)

- [ ] **Step 1: Write the failing test**

Append inside `Test_Github()` in `tests/test_github.prg`, before `RETURN NIL`:

```harbour
   // --- github_write schema ---
   hTool := DSTool_GithubWrite( "tok" )
   T_Equal( hTool[ "name" ], "github_write", "github_write: tool name" )

   // --- missing token ---
   hTool := DSTool_GithubWrite( "" )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "create_issue", "repo" => "a/b", "title" => "T" } )
   T_Equal( cRes, "Error: GITHUB_TOKEN not set", "github_write: missing token" )

   // --- argument validation ---
   hTool := DSTool_GithubWrite( "tok" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "create_issue", "repo" => "a/b" } )
   T_Equal( cRes, "Error: github_write 'create_issue' requires 'title'", ;
            "github_write: missing title" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "comment", "repo" => "a/b" } )
   T_Equal( cRes, "Error: github_write 'comment' requires 'number'", ;
            "github_write: missing number" )

   // --- create_issue posts and reports the created URL ---
   DSHTTP_SetTestTransport( {| hR | ;
      T_Equal( hR[ "method" ], "POST", "github_write: uses POST" ), ;
      { "ok" => .T., "status" => 201, "error" => "", ;
        "body" => hb_jsonEncode( { "html_url" => "https://github.com/a/b/issues/7" } ) } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "create_issue", "repo" => "a/b", ;
                   "title" => "Bug", "body" => "desc" } )
   T_Equal( cRes, "Created: https://github.com/a/b/issues/7", ;
            "github_write: create_issue result" )
   DSHTTP_SetTestTransport( NIL )

   // --- non-2xx surfaces the API message ---
   DSHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 422, "error" => "", ;
        "body" => hb_jsonEncode( { "message" => "Validation Failed" } ) } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "create_issue", "repo" => "a/b", "title" => "X" } )
   T_Equal( cRes, "Error: github_write HTTP 422: Validation Failed", ;
            "github_write: non-2xx with message" )
   DSHTTP_SetTestTransport( NIL )
```

- [ ] **Step 2: Run test to verify it fails**

Run: from `tests/`, `hbmk2 tests.hbp`
Expected: compile/link error — `DSTool_GithubWrite` undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `src/dstools_github.prg`:

```harbour
// github_write: GitHub mutations. cToken is mandatory — an empty token yields
// a clear error at call time.
FUNCTION DSTool_GithubWrite( cToken )
   RETURN { "name" => "github_write", ;
            "description" => "Write to GitHub: create an issue, comment on an issue, or open a pull request. Requires GITHUB_TOKEN.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "operation" => { "type" => "string", ;
                     "description" => "One of: create_issue, comment, create_pr" }, ;
                  "repo" => { "type" => "string", ;
                     "description" => "Repository as owner/name" }, ;
                  "number" => { "type" => "integer", ;
                     "description" => "Issue number (comment)" }, ;
                  "title" => { "type" => "string", ;
                     "description" => "Title (create_issue, create_pr)" }, ;
                  "body" => { "type" => "string", ;
                     "description" => "Body text (issue, comment, or PR description)" }, ;
                  "head" => { "type" => "string", ;
                     "description" => "Source branch (create_pr)" }, ;
                  "base" => { "type" => "string", ;
                     "description" => "Target branch (create_pr)" } }, ;
               "required" => { "operation", "repo" } }, ;
            "handler" => {| hArgs | DSTool_GithubWriteRun( hArgs, cToken ) } }

STATIC FUNCTION DSTool_GithubWriteRun( hArgs, cToken )
   LOCAL cOp, cRepo, cUrl, cReqBody, hRes, xJson
   IF Empty( cToken )
      RETURN "Error: GITHUB_TOKEN not set"
   ENDIF
   cOp := Lower( hb_CStr( hArgs[ "operation" ] ) )
   cRepo := hb_CStr( hArgs[ "repo" ] )
   DO CASE
   CASE cOp == "create_issue"
      IF !hb_HHasKey( hArgs, "title" ) .OR. Empty( hArgs[ "title" ] )
         RETURN "Error: github_write 'create_issue' requires 'title'"
      ENDIF
      cUrl := "https://api.github.com/repos/" + cRepo + "/issues"
      cReqBody := hb_jsonEncode( { "title" => hb_CStr( hArgs[ "title" ] ), ;
         "body" => iif( hb_HHasKey( hArgs, "body" ), hb_CStr( hArgs[ "body" ] ), "" ) } )
   CASE cOp == "comment"
      IF !hb_HHasKey( hArgs, "number" )
         RETURN "Error: github_write 'comment' requires 'number'"
      ENDIF
      cUrl := "https://api.github.com/repos/" + cRepo + "/issues/" + ;
              LTrim( Str( hArgs[ "number" ] ) ) + "/comments"
      cReqBody := hb_jsonEncode( { "body" => ;
         iif( hb_HHasKey( hArgs, "body" ), hb_CStr( hArgs[ "body" ] ), "" ) } )
   CASE cOp == "create_pr"
      IF !hb_HHasKey( hArgs, "title" ) .OR. Empty( hArgs[ "title" ] ) .OR. ;
         !hb_HHasKey( hArgs, "head" ) .OR. Empty( hArgs[ "head" ] ) .OR. ;
         !hb_HHasKey( hArgs, "base" ) .OR. Empty( hArgs[ "base" ] )
         RETURN "Error: github_write 'create_pr' requires 'title', 'head', 'base'"
      ENDIF
      cUrl := "https://api.github.com/repos/" + cRepo + "/pulls"
      cReqBody := hb_jsonEncode( { "title" => hb_CStr( hArgs[ "title" ] ), ;
         "head" => hb_CStr( hArgs[ "head" ] ), "base" => hb_CStr( hArgs[ "base" ] ), ;
         "body" => iif( hb_HHasKey( hArgs, "body" ), hb_CStr( hArgs[ "body" ] ), "" ) } )
   OTHERWISE
      RETURN "Error: github_write: unknown operation '" + cOp + "'"
   ENDCASE
   hRes := DSHTTP_Fetch( { "url" => cUrl, "method" => "POST", ;
      "headers" => DSGithub_Headers( cToken ), "body" => cReqBody } )
   IF !hRes[ "ok" ]
      RETURN "Error: github_write failed: " + hRes[ "error" ]
   ENDIF
   IF hRes[ "status" ] < 200 .OR. hRes[ "status" ] >= 300
      RETURN "Error: github_write HTTP " + LTrim( Str( hRes[ "status" ] ) ) + ": " + ;
             DSGithub_ApiMessage( hRes[ "body" ] )
   ENDIF
   xJson := hb_jsonDecode( hRes[ "body" ] )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "html_url" )
      RETURN "Created: " + hb_CStr( xJson[ "html_url" ] )
   ENDIF
   RETURN "OK"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: from `tests/`, `hbmk2 tests.hbp` then `run_tests.exe`
Expected: PASS — all `github_write:` assertions pass, no regressions.

- [ ] **Step 5: Commit**

```bash
git add src/dstools_github.prg tests/test_github.prg
git commit -m "feat: add github_write tool"
```

---

## Task 7: Register tools, permissions, and wire the call site

**Files:**
- Modify: `src/dstools.prg:3-11` (`DSTools_Registry`)
- Modify: `src/dssettings.prg:7-9` (default permissions)
- Modify: `src/dsrepl.prg:28` (resolve keys, pass to registry)
- Test: `tests/test_tools.prg` (extend `Test_Tools`), `tests/test_settings.prg` (extend `Test_Settings`)

- [ ] **Step 1: Write the failing tests**

In `tests/test_tools.prg`, append inside `Test_Tools()` before `RETURN NIL`:

```harbour
   // the four new tools are registered
   oReg := DSTools_Registry()
   T_Equal( hb_HHasKey( oReg, "web_search" ), .T., "tools: web_search registered" )
   T_Equal( hb_HHasKey( oReg, "web_fetch" ), .T., "tools: web_fetch registered" )
   T_Equal( hb_HHasKey( oReg, "github_read" ), .T., "tools: github_read registered" )
   T_Equal( hb_HHasKey( oReg, "github_write" ), .T., "tools: github_write registered" )

   // keys passed via hKeys reach the tool handler
   oReg := DSTools_Registry( { "tavily" => "", "github" => "" } )
   cRes := Eval( oReg[ "web_search" ][ "handler" ], { "query" => "x" } )
   T_Equal( cRes, "Error: TAVILY_API_KEY not set", "tools: empty tavily key flows through" )
```

In `tests/test_settings.prg`, append inside `Test_Settings()` before `RETURN NIL`:

```harbour
   hL := DSSettings_Defaults()
   T_Equal( hL[ "permissions" ][ "web_search" ], "ask", "settings: web_search perm" )
   T_Equal( hL[ "permissions" ][ "web_fetch" ], "ask", "settings: web_fetch perm" )
   T_Equal( hL[ "permissions" ][ "github_read" ], "allow", "settings: github_read perm" )
   T_Equal( hL[ "permissions" ][ "github_write" ], "ask", "settings: github_write perm" )
```

- [ ] **Step 2: Run tests to verify they fail**

Run: from `tests/`, `hbmk2 tests.hbp` then `run_tests.exe`
Expected: FAIL — new tools not registered; new permission keys absent.

- [ ] **Step 3: Update `DSTools_Registry`**

Replace `src/dstools.prg` lines 1-11 with:

```harbour
// Creates a fresh tool registry with all builtin tools registered.
// hKeys (optional): { tavily => <api key>, github => <token> } — captured by
// the web/github tool handlers. Omitting it leaves those keys empty; the
// affected tools then return a clear error at call time.
FUNCTION DSTools_Registry( hKeys )
   LOCAL oReg := {=>}
   IF ValType( hKeys ) != "H"
      hKeys := {=>}
   ENDIF
   DSTools_Register( oReg, DSTool_Read() )
   DSTools_Register( oReg, DSTool_Write() )
   DSTools_Register( oReg, DSTool_Edit() )
   DSTools_Register( oReg, DSTool_Glob() )
   DSTools_Register( oReg, DSTool_Grep() )
   DSTools_Register( oReg, DSTool_Shell() )
   DSTools_Register( oReg, DSTool_WebSearch( hb_HGetDef( hKeys, "tavily", "" ) ) )
   DSTools_Register( oReg, DSTool_WebFetch() )
   DSTools_Register( oReg, DSTool_GithubRead( hb_HGetDef( hKeys, "github", "" ) ) )
   DSTools_Register( oReg, DSTool_GithubWrite( hb_HGetDef( hKeys, "github", "" ) ) )
   RETURN oReg
```

- [ ] **Step 4: Update default permissions**

In `src/dssettings.prg`, replace the `"permissions"` entry in `DSSettings_Defaults()` (lines 7-9) with:

```harbour
            "permissions"    => { "read"  => "allow", "glob"  => "allow", ;
                                  "grep"  => "allow", "write" => "ask", ;
                                  "edit"  => "ask",   "shell" => "ask", ;
                                  "web_search"   => "ask",   "web_fetch"    => "ask", ;
                                  "github_read"  => "allow", "github_write" => "ask" } }
```

- [ ] **Step 5: Wire the call site**

In `src/dsrepl.prg`, replace line 28 (`oReg := DSTools_Registry()`) with:

```harbour
   oReg    := DSTools_Registry( { ;
      "tavily" => DSCFG_ResolveKey( "TAVILY_API_KEY", "tavily_api_key", hSet ), ;
      "github" => DSCFG_ResolveKey( "GITHUB_TOKEN", "github_token", hSet ) } )
```

- [ ] **Step 6: Run tests to verify they pass**

Run: from `tests/`, `hbmk2 tests.hbp` then `run_tests.exe`
Expected: PASS — all new `tools:` and `settings:` assertions pass, no regressions.

- [ ] **Step 7: Build the app**

Run: from the repo root, `build.bat`
Expected: `cc.exe` builds with no errors.

- [ ] **Step 8: Commit**

```bash
git add src/dstools.prg src/dssettings.prg src/dsrepl.prg tests/test_tools.prg tests/test_settings.prg
git commit -m "feat: register web/github tools and resolve their API keys"
```

---

## Task 8: Document the new tools

**Files:**
- Modify: `pages/configuration.md` (settings keys + permissions)
- Modify: `pages/commands.md` (or whichever page lists tools — confirm by reading it first)

- [ ] **Step 1: Read the docs pages**

Read `pages/configuration.md` and `pages/commands.md` to match the existing tone and structure for documenting tools and settings.

- [ ] **Step 2: Document the tools and settings**

In the page that describes tools, add `web_search`, `web_fetch`, `github_read`, and `github_write`, each with its purpose and parameters (mirror the tool `description` and `parameters` written in Tasks 3-6).

In `pages/configuration.md`, document:
- `settings.json` keys `tavily_api_key` and `github_token`, and the matching environment variables `TAVILY_API_KEY` and `GITHUB_TOKEN`, noting env takes precedence.
- The new default permissions: `web_search`/`web_fetch` = `ask`, `github_read` = `allow`, `github_write` = `ask`.
- That `web_search` needs a Tavily key and `github_write` needs a GitHub token; without them the tools return an error at call time.

- [ ] **Step 3: Commit**

```bash
git add pages/configuration.md pages/commands.md
git commit -m "docs: document the web and github tools"
```

---

## Self-review notes

- **Spec coverage:** `DSHTTP_Fetch` (T1), `DSCFG_ResolveKey` (T2), `web_fetch` (T3), `web_search` (T4), `github_read` (T5), `github_write` (T6), registry/permissions/keys wiring (T7), docs (T8) — every spec section maps to a task.
- **Test transport:** the spec mentions a per-request `transport` key; the plan additionally adds `DSHTTP_SetTestTransport` (module-level hook) because tool handlers build their own `hReq` and cannot receive a per-request transport from a test. Both mechanisms exist; tool tests use the module hook.
- **Type consistency:** `DSHTTP_Fetch` returns `{ ok, status, body, error }` everywhere; tool handlers all check `ok` then status range `200..299`; key arg to `DSTools_Registry` is `hKeys` with sub-keys `tavily`/`github` consistently.
- **Harbour built-ins used:** `hb_jsonEncode`, `hb_jsonDecode`, `hb_base64Decode`, `hb_base64Encode`, `hb_NumToHex`, `hb_HGetDef`, `hb_processOpen` — all Harbour core. If `hb_base64Decode`/`hb_base64Encode` are unavailable in the local Harbour build, link the `hbtip` contrib (it provides them) in `cc.hbp` and `tests/tests.hbp`.

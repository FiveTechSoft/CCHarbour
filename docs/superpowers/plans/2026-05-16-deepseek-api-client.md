# DeepSeek API Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable Harbour library that performs streaming chat completions against the DeepSeek (OpenAI-compatible) API.

**Architecture:** Four isolated modules — `dssse` (pure SSE parser), `dsconfig` (key/URL resolution), `dshttp` (hbcurl wrapper with an injectable transport seam), `dsapi` (orchestration). Layers do not leak: `dshttp` knows no SSE, `dssse` knows no HTTP, `dsapi` ties them together. No global mutable state; each request gets its own curl handle so the library is pool-safe.

**Tech Stack:** Harbour (MT build, `hbmk2`), `hbcurl` contrib (libcurl + SSL), core `hb_jsonEncode`/`hb_jsonDecode`.

---

## File Structure

```
src/dsconfig.prg   API key + base URL resolution
src/dssse.prg      Incremental SSE parser (OpenAI format), pure, no I/O
src/dshttp.prg     hbcurl wrapper: POST, headers, write-callback, injectable transport
src/dsapi.prg      Public API: DS_Client, DS_ChatCompletion
tests/run_tests.prg  Test runner: Main + T_Assert/T_Equal helpers
tests/test_sse.prg   SSE parser tests
tests/test_config.prg Config resolution tests
tests/test_http.prg  dshttp tests (injected transport)
tests/test_api.prg   dsapi tests (injected transport)
tests/integration.prg Opt-in real-network test
tests/tests.hbp      hbmk2 project file for the test build
src/dsclient.hbp     hbmk2 project file for the library build
.gitignore
```

Conventions for all `.prg` files: public functions are `FUNCTION`, private helpers are `STATIC FUNCTION`. Hashes are the data carrier (`{ "k" => v }`). Every public function returns a value or `NIL`; none throws an uncaught exception.

---

### Task 1: Project scaffold and test runner

**Files:**
- Create: `.gitignore`
- Create: `tests/tests.hbp`
- Create: `tests/run_tests.prg`

- [ ] **Step 1: Create `.gitignore`**

```
*.exe
*.o
*.obj
*.ppo
.hbmk/
```

- [ ] **Step 2: Create the test runner with assert helpers**

`tests/run_tests.prg`:

```harbour
#include "hbclass.ch"

STATIC s_nPass := 0
STATIC s_nFail := 0

FUNCTION Main()
   Test_SSE()
   Test_Config()
   Test_Http()
   Test_Api()
   ? ""
   ? "pass: " + LTrim( Str( s_nPass ) ) + "   fail: " + LTrim( Str( s_nFail ) )
   ErrorLevel( iif( s_nFail > 0, 1, 0 ) )
   RETURN NIL

FUNCTION T_Assert( lCond, cName )
   IF lCond
      s_nPass++
      ? "ok   - " + cName
   ELSE
      s_nFail++
      ? "FAIL - " + cName
   ENDIF
   RETURN lCond

FUNCTION T_Equal( xActual, xExpected, cName )
   LOCAL lOk := ( ValType( xActual ) == ValType( xExpected ) ) .AND. ;
                ( hb_CStr( xActual ) == hb_CStr( xExpected ) )
   RETURN T_Assert( lOk, cName + iif( lOk, "", ;
      " (got <" + hb_CStr( xActual ) + "> want <" + hb_CStr( xExpected ) + ">)" ) )
```

- [ ] **Step 3: Create empty test entry points so the build links**

Append to `tests/run_tests.prg`:

```harbour
FUNCTION Test_SSE();    RETURN NIL
FUNCTION Test_Config(); RETURN NIL
FUNCTION Test_Http();   RETURN NIL
FUNCTION Test_Api();    RETURN NIL
```

(These are replaced by real implementations in later tasks. When you create `tests/test_sse.prg` etc., delete the matching stub here.)

- [ ] **Step 4: Create the hbmk2 project file**

`tests/tests.hbp`:

```
-otests/run_tests
-mt
tests/run_tests.prg
src/dsconfig.prg
src/dssse.prg
src/dshttp.prg
src/dsapi.prg
hbcurl.hbc
```

(Source files referenced before they exist will be created in later tasks. Until then this build will fail — expected.)

- [ ] **Step 5: Create placeholder source files so Task 1 builds**

Create each with a single stub so the runner links now; later tasks replace the contents:

`src/dsconfig.prg`: `FUNCTION DSCFG_ResolveKey( hOpts ); HB_SYMBOL_UNUSED( hOpts ); RETURN NIL`
`src/dssse.prg`: `FUNCTION DSSSE_New(); RETURN NIL`
`src/dshttp.prg`: `FUNCTION DSHTTP_Post( hReq, bOnChunk, bTransport ); HB_SYMBOL_UNUSED( hReq ); HB_SYMBOL_UNUSED( bOnChunk ); HB_SYMBOL_UNUSED( bTransport ); RETURN NIL`
`src/dsapi.prg`: `FUNCTION DS_Client( hOpts ); HB_SYMBOL_UNUSED( hOpts ); RETURN NIL`

- [ ] **Step 6: Build and run**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: builds clean; output ends with `pass: 0   fail: 0`; exit code 0.

- [ ] **Step 7: Commit**

```bash
git add .gitignore tests/ src/
git commit -m "chore: scaffold Harbour project and test runner"
```

---

### Task 2: SSE parser — buffering and text deltas

**Files:**
- Modify: `src/dssse.prg` (replace stub)
- Create: `tests/test_sse.prg`
- Modify: `tests/tests.hbp`, `tests/run_tests.prg`

- [ ] **Step 1: Add the test file to the build**

In `tests/tests.hbp`, add the line `tests/test_sse.prg` after `tests/run_tests.prg`.
In `tests/run_tests.prg`, delete the stub line `FUNCTION Test_SSE();    RETURN NIL`.

- [ ] **Step 2: Write the failing tests**

`tests/test_sse.prg`:

```harbour
FUNCTION Test_SSE()
   LOCAL oP, aEvents

   // One complete data line -> one text_delta
   aEvents := {}
   oP := DSSSE_New()
   DSSSE_Feed( oP, 'data: {"choices":[{"delta":{"content":"Hi"}}]}' + Chr(10), ;
               {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: one event from one line" )
   T_Equal( aEvents[ 1 ][ "type" ], "text_delta", "sse: event type" )
   T_Equal( aEvents[ 1 ][ "text" ], "Hi", "sse: delta text" )

   // JSON split across two chunks -> still one event
   aEvents := {}
   oP := DSSSE_New()
   DSSSE_Feed( oP, 'data: {"choices":[{"delta":{"con', {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 0, "sse: no event before newline" )
   DSSSE_Feed( oP, 'tent":"X"}}]}' + Chr(10), {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: event after completion" )
   T_Equal( aEvents[ 1 ][ "text" ], "X", "sse: split-json text" )

   // CRLF line endings and keep-alive blank lines are tolerated
   aEvents := {}
   oP := DSSSE_New()
   DSSSE_Feed( oP, Chr(13) + Chr(10) + ;
               'data: {"choices":[{"delta":{"content":"Y"}}]}' + Chr(13) + Chr(10), ;
               {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: crlf + blank line" )
   RETURN NIL
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: FAIL lines for the `sse:` tests (DSSSE_New returns NIL, DSSSE_Feed undefined or no-op).

- [ ] **Step 4: Implement the parser core**

Replace the entire contents of `src/dssse.prg`:

```harbour
FUNCTION DSSSE_New()
   RETURN { "buffer" => "", "closed" => .F. }

FUNCTION DSSSE_Feed( oP, cChunk, bEmit )
   LOCAL nPos, cLine
   oP[ "buffer" ] += cChunk
   DO WHILE ( nPos := At( Chr(10), oP[ "buffer" ] ) ) > 0
      cLine := Left( oP[ "buffer" ], nPos - 1 )
      oP[ "buffer" ] := SubStr( oP[ "buffer" ], nPos + 1 )
      cLine := StrTran( cLine, Chr(13), "" )
      DSSSE_Line( cLine, bEmit )
   ENDDO
   RETURN NIL

STATIC FUNCTION DSSSE_Line( cLine, bEmit )
   LOCAL cData, xJson, hChoice, hDelta
   IF Empty( cLine ) .OR. !( Left( cLine, 5 ) == "data:" )
      RETURN NIL   // comments, blank keep-alive lines, event: lines -> ignored
   ENDIF
   cData := AllTrim( SubStr( cLine, 6 ) )
   IF cData == "[DONE]"
      Eval( bEmit, { "type" => "done" } )
      RETURN NIL
   ENDIF
   xJson := hb_jsonDecode( cData )
   IF !( ValType( xJson ) == "H" )
      RETURN NIL   // unparseable / non-object -> skip silently
   ENDIF
   IF hb_HHasKey( xJson, "choices" ) .AND. Len( xJson[ "choices" ] ) > 0
      hChoice := xJson[ "choices" ][ 1 ]
      IF hb_HHasKey( hChoice, "delta" )
         hDelta := hChoice[ "delta" ]
         IF hb_HHasKey( hDelta, "content" ) .AND. ;
            ValType( hDelta[ "content" ] ) == "C" .AND. ;
            !Empty( hDelta[ "content" ] )
            Eval( bEmit, { "type" => "text_delta", "text" => hDelta[ "content" ] } )
         ENDIF
      ENDIF
   ENDIF
   RETURN NIL
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: all `sse:` lines show `ok`; exit code 0.

- [ ] **Step 6: Commit**

```bash
git add src/dssse.prg tests/test_sse.prg tests/tests.hbp tests/run_tests.prg
git commit -m "feat: SSE parser with line buffering and text deltas"
```

---

### Task 3: SSE parser — tool-call deltas, finish_reason, usage, done

**Files:**
- Modify: `src/dssse.prg`
- Modify: `tests/test_sse.prg`

- [ ] **Step 1: Add the failing tests**

Append inside `Test_SSE()` in `tests/test_sse.prg`, before `RETURN NIL`:

```harbour
   // tool_call delta
   aEvents := {}
   oP := DSSSE_New()
   DSSSE_Feed( oP, 'data: {"choices":[{"delta":{"tool_calls":[' + ;
      '{"index":0,"id":"call_1","function":{"name":"read","arguments":"{\\"p\\""}}]}}]}' + ;
      Chr(10), {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: tool_call event count" )
   T_Equal( aEvents[ 1 ][ "type" ], "tool_call_delta", "sse: tool_call type" )
   T_Equal( aEvents[ 1 ][ "index" ], 0, "sse: tool_call index" )
   T_Equal( aEvents[ 1 ][ "id" ], "call_1", "sse: tool_call id" )
   T_Equal( aEvents[ 1 ][ "name" ], "read", "sse: tool_call name" )
   T_Equal( aEvents[ 1 ][ "arguments" ], '{"p"', "sse: tool_call args fragment" )

   // finish_reason
   aEvents := {}
   oP := DSSSE_New()
   DSSSE_Feed( oP, 'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}' + Chr(10), ;
               {| h | AAdd( aEvents, h ) } )
   T_Equal( aEvents[ 1 ][ "type" ], "finish", "sse: finish event" )
   T_Equal( aEvents[ 1 ][ "finish_reason" ], "stop", "sse: finish reason" )

   // usage
   aEvents := {}
   oP := DSSSE_New()
   DSSSE_Feed( oP, 'data: {"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":5}}' + ;
               Chr(10), {| h | AAdd( aEvents, h ) } )
   T_Equal( aEvents[ 1 ][ "type" ], "usage", "sse: usage event" )
   T_Equal( aEvents[ 1 ][ "usage" ][ "prompt_tokens" ], 3, "sse: usage value" )

   // [DONE]
   aEvents := {}
   oP := DSSSE_New()
   DSSSE_Feed( oP, "data: [DONE]" + Chr(10), {| h | AAdd( aEvents, h ) } )
   T_Equal( aEvents[ 1 ][ "type" ], "done", "sse: done event" )
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: FAIL for the new `sse:` tests; the Task 2 tests still pass.

- [ ] **Step 3: Extend `DSSSE_Line`**

In `src/dssse.prg`, inside `DSSSE_Line`, replace the `IF hb_HHasKey( hChoice, "delta" )` block and add handling after it. The full `choices`/`usage` section becomes:

```harbour
   IF hb_HHasKey( xJson, "choices" ) .AND. Len( xJson[ "choices" ] ) > 0
      hChoice := xJson[ "choices" ][ 1 ]
      IF hb_HHasKey( hChoice, "delta" )
         hDelta := hChoice[ "delta" ]
         IF hb_HHasKey( hDelta, "content" ) .AND. ;
            ValType( hDelta[ "content" ] ) == "C" .AND. ;
            !Empty( hDelta[ "content" ] )
            Eval( bEmit, { "type" => "text_delta", "text" => hDelta[ "content" ] } )
         ENDIF
         IF hb_HHasKey( hDelta, "tool_calls" )
            DSSSE_ToolCalls( hDelta[ "tool_calls" ], bEmit )
         ENDIF
      ENDIF
      IF hb_HHasKey( hChoice, "finish_reason" ) .AND. ;
         ValType( hChoice[ "finish_reason" ] ) == "C"
         Eval( bEmit, { "type" => "finish", ;
                        "finish_reason" => hChoice[ "finish_reason" ] } )
      ENDIF
   ENDIF
   IF hb_HHasKey( xJson, "usage" ) .AND. ValType( xJson[ "usage" ] ) == "H"
      Eval( bEmit, { "type" => "usage", "usage" => xJson[ "usage" ] } )
   ENDIF
```

Then add the helper at the end of `src/dssse.prg`:

```harbour
STATIC FUNCTION DSSSE_ToolCalls( aCalls, bEmit )
   LOCAL hCall, hFn, hEv
   FOR EACH hCall IN aCalls
      hEv := { "type" => "tool_call_delta", "index" => 0, ;
               "id" => NIL, "name" => NIL, "arguments" => NIL }
      IF hb_HHasKey( hCall, "index" )
         hEv[ "index" ] := hCall[ "index" ]
      ENDIF
      IF hb_HHasKey( hCall, "id" )
         hEv[ "id" ] := hCall[ "id" ]
      ENDIF
      IF hb_HHasKey( hCall, "function" ) .AND. ValType( hCall[ "function" ] ) == "H"
         hFn := hCall[ "function" ]
         IF hb_HHasKey( hFn, "name" )
            hEv[ "name" ] := hFn[ "name" ]
         ENDIF
         IF hb_HHasKey( hFn, "arguments" )
            hEv[ "arguments" ] := hFn[ "arguments" ]
         ENDIF
      ENDIF
      Eval( bEmit, hEv )
   NEXT
   RETURN NIL
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: all `sse:` lines `ok`; exit code 0.

- [ ] **Step 5: Commit**

```bash
git add src/dssse.prg tests/test_sse.prg
git commit -m "feat: SSE parser handles tool_calls, finish_reason, usage, done"
```

---

### Task 4: Config — API key and base URL resolution

**Files:**
- Modify: `src/dsconfig.prg` (replace stub)
- Create: `tests/test_config.prg`
- Modify: `tests/tests.hbp`, `tests/run_tests.prg`

- [ ] **Step 1: Add the test file to the build**

In `tests/tests.hbp`, add `tests/test_config.prg`.
In `tests/run_tests.prg`, delete the stub `FUNCTION Test_Config(); RETURN NIL`.

- [ ] **Step 2: Write the failing tests**

`tests/test_config.prg`:

```harbour
FUNCTION Test_Config()
   LOCAL hR, cTmp

   // explicit api_key in hOpts wins
   hR := DSCFG_Resolve( { "api_key" => "explicit-key" } )
   T_Equal( hR[ "ok" ], .T., "cfg: explicit ok" )
   T_Equal( hR[ "api_key" ], "explicit-key", "cfg: explicit key" )

   // env var fallback
   hb_SetEnv( "DEEPSEEK_API_KEY", "env-key" )
   hR := DSCFG_Resolve( {=>} )
   T_Equal( hR[ "api_key" ], "env-key", "cfg: env key" )
   hb_SetEnv( "DEEPSEEK_API_KEY", "" )

   // config-file fallback
   cTmp := hb_DirTemp() + "dscfg_test.json"
   hb_MemoWrit( cTmp, '{"api_key":"file-key"}' )
   hR := DSCFG_Resolve( { "config_path" => cTmp } )
   T_Equal( hR[ "api_key" ], "file-key", "cfg: file key" )
   FErase( cTmp )

   // no key anywhere -> ok = .F.
   hR := DSCFG_Resolve( {=>} )
   T_Equal( hR[ "ok" ], .F., "cfg: missing key fails" )
   T_Equal( hR[ "error_type" ], "config", "cfg: missing key error_type" )

   // default base url
   hR := DSCFG_Resolve( { "api_key" => "k" } )
   T_Equal( hR[ "base_url" ], "https://api.deepseek.com", "cfg: default base url" )
   RETURN NIL
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: FAIL for `cfg:` tests (`DSCFG_Resolve` undefined).

- [ ] **Step 4: Implement config resolution**

Replace the entire contents of `src/dsconfig.prg`:

```harbour
// Resolves API key + base URL. Precedence for the key:
//   hOpts["api_key"]  ->  env DEEPSEEK_API_KEY  ->  config file (hOpts["config_path"])
// Returns: { ok, api_key, base_url, error_type, message }
FUNCTION DSCFG_Resolve( hOpts )
   LOCAL hRes, cKey := "", cEnv, cFileKey

   IF ValType( hOpts ) != "H"
      hOpts := {=>}
   ENDIF

   hRes := { "ok" => .F., "api_key" => "", ;
             "base_url" => iif( hb_HHasKey( hOpts, "base_url" ) .AND. ;
                                !Empty( hOpts[ "base_url" ] ), ;
                                hOpts[ "base_url" ], "https://api.deepseek.com" ), ;
             "error_type" => NIL, "message" => NIL }

   IF hb_HHasKey( hOpts, "api_key" ) .AND. !Empty( hOpts[ "api_key" ] )
      cKey := hOpts[ "api_key" ]
   ELSE
      cEnv := hb_GetEnv( "DEEPSEEK_API_KEY" )
      IF !Empty( cEnv )
         cKey := cEnv
      ELSEIF hb_HHasKey( hOpts, "config_path" ) .AND. !Empty( hOpts[ "config_path" ] )
         cFileKey := DSCFG_FromFile( hOpts[ "config_path" ] )
         IF !Empty( cFileKey )
            cKey := cFileKey
         ENDIF
      ENDIF
   ENDIF

   IF Empty( cKey )
      hRes[ "error_type" ] := "config"
      hRes[ "message" ]    := "No API key: set hOpts api_key, env DEEPSEEK_API_KEY, or config_path"
      RETURN hRes
   ENDIF

   hRes[ "api_key" ] := cKey
   hRes[ "ok" ]      := .T.
   RETURN hRes

STATIC FUNCTION DSCFG_FromFile( cPath )
   LOCAL cText, xJson
   IF !hb_FileExists( cPath )
      RETURN ""
   ENDIF
   cText := hb_MemoRead( cPath )
   xJson := hb_jsonDecode( cText )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "api_key" ) .AND. ;
      ValType( xJson[ "api_key" ] ) == "C"
      RETURN xJson[ "api_key" ]
   ENDIF
   RETURN ""
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: all `cfg:` lines `ok`; exit code 0.

- [ ] **Step 6: Commit**

```bash
git add src/dsconfig.prg tests/test_config.prg tests/tests.hbp tests/run_tests.prg
git commit -m "feat: API key and base URL resolution"
```

---

### Task 5: HTTP layer with injectable transport

**Files:**
- Modify: `src/dshttp.prg` (replace stub)
- Create: `tests/test_http.prg`
- Modify: `tests/tests.hbp`, `tests/run_tests.prg`

The real libcurl transport is wired in Task 7. This task defines the seam: `DSHTTP_Post` accepts an optional `bTransport` codeblock. When supplied it is used instead of curl, making the layer testable offline.

- [ ] **Step 1: Add the test file to the build**

In `tests/tests.hbp`, add `tests/test_http.prg`.
In `tests/run_tests.prg`, delete the stub `FUNCTION Test_Http(); RETURN NIL`.

- [ ] **Step 2: Write the failing tests**

`tests/test_http.prg`:

```harbour
FUNCTION Test_Http()
   LOCAL hReq, hRes, aChunks, bTransport

   hReq := { "url" => "https://x/y", "headers" => {}, "body" => "{}", "timeout" => 30 }

   // injected transport: feeds two chunks, reports HTTP 200
   aChunks := {}
   bTransport := {| hR, bOnChunk | ;
      HB_SYMBOL_UNUSED( hR ), ;
      Eval( bOnChunk, "data: a" + Chr(10) ), ;
      Eval( bOnChunk, "data: b" + Chr(10) ), ;
      { "ok" => .T., "status" => 200, "curl_code" => 0, "error" => "" } }
   hRes := DSHTTP_Post( hReq, {| c | AAdd( aChunks, c ) }, bTransport )
   T_Equal( hRes[ "ok" ], .T., "http: transport ok" )
   T_Equal( hRes[ "status" ], 200, "http: status passthrough" )
   T_Equal( Len( aChunks ), 2, "http: chunk count" )
   T_Equal( aChunks[ 1 ], "data: a" + Chr(10), "http: first chunk" )

   // injected transport reporting a network failure
   bTransport := {| hR, bOnChunk | ;
      HB_SYMBOL_UNUSED( hR ), HB_SYMBOL_UNUSED( bOnChunk ), ;
      { "ok" => .F., "status" => 0, "curl_code" => 7, "error" => "couldnt connect" } }
   hRes := DSHTTP_Post( hReq, {| c | HB_SYMBOL_UNUSED( c ) }, bTransport )
   T_Equal( hRes[ "ok" ], .F., "http: failure ok flag" )
   T_Equal( hRes[ "curl_code" ], 7, "http: curl code passthrough" )
   RETURN NIL
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: FAIL for `http:` tests (`DSHTTP_Post` is the stub returning NIL).

- [ ] **Step 4: Implement the HTTP wrapper seam**

Replace the entire contents of `src/dshttp.prg`:

```harbour
// Performs a streaming POST. hReq: { url, headers (array of "K: V"), body, timeout }.
// bOnChunk is called with each received raw text chunk.
// bTransport (optional codeblock {|hReq,bOnChunk| -> hResult }) overrides libcurl;
// when NIL the real libcurl transport (DSHTTP_CurlPost, Task 7) is used.
// Returns: { ok, status, curl_code, error }
FUNCTION DSHTTP_Post( hReq, bOnChunk, bTransport )
   IF bTransport != NIL
      RETURN Eval( bTransport, hReq, bOnChunk )
   ENDIF
   RETURN DSHTTP_CurlPost( hReq, bOnChunk )

// Placeholder real transport; replaced with the libcurl implementation in Task 7.
FUNCTION DSHTTP_CurlPost( hReq, bOnChunk )
   HB_SYMBOL_UNUSED( hReq )
   HB_SYMBOL_UNUSED( bOnChunk )
   RETURN { "ok" => .F., "status" => 0, "curl_code" => -1, ;
            "error" => "libcurl transport not yet implemented" }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: all `http:` lines `ok`; exit code 0.

- [ ] **Step 6: Commit**

```bash
git add src/dshttp.prg tests/test_http.prg tests/tests.hbp tests/run_tests.prg
git commit -m "feat: HTTP layer with injectable transport seam"
```

---

### Task 6: API orchestration — DS_Client and DS_ChatCompletion

**Files:**
- Modify: `src/dsapi.prg` (replace stub)
- Create: `tests/test_api.prg`
- Modify: `tests/tests.hbp`, `tests/run_tests.prg`

- [ ] **Step 1: Add the test file to the build**

In `tests/tests.hbp`, add `tests/test_api.prg`.
In `tests/run_tests.prg`, delete the stub `FUNCTION Test_Api(); RETURN NIL`.

- [ ] **Step 2: Write the failing tests**

`tests/test_api.prg`:

```harbour
FUNCTION Test_Api()
   LOCAL oClient, hResult, aEvents, bTransport

   oClient := DS_Client( { "api_key" => "k", "model" => "deepseek-chat" } )
   T_Equal( ValType( oClient ), "H", "api: client is hash" )

   // transport that streams a text reply, a usage line and [DONE]
   bTransport := {| hR, bOnChunk | ;
      HB_SYMBOL_UNUSED( hR ), ;
      Eval( bOnChunk, 'data: {"choices":[{"delta":{"content":"Hel"}}]}' + Chr(10) ), ;
      Eval( bOnChunk, 'data: {"choices":[{"delta":{"content":"lo"}}]}' + Chr(10) ), ;
      Eval( bOnChunk, 'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}' + Chr(10) ), ;
      Eval( bOnChunk, 'data: {"choices":[],"usage":{"prompt_tokens":2,"completion_tokens":4}}' + Chr(10) ), ;
      Eval( bOnChunk, "data: [DONE]" + Chr(10) ), ;
      { "ok" => .T., "status" => 200, "curl_code" => 0, "error" => "" } }

   aEvents := {}
   hResult := DS_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "hi" } }, ;
      { "transport" => bTransport }, {| h | AAdd( aEvents, h ) } )

   T_Equal( hResult[ "success" ], .T., "api: success" )
   T_Equal( hResult[ "content" ], "Hello", "api: assembled content" )
   T_Equal( hResult[ "finish_reason" ], "stop", "api: finish reason" )
   T_Equal( hResult[ "usage" ][ "completion_tokens" ], 4, "api: usage assembled" )
   T_Assert( Len( aEvents ) >= 2, "api: events forwarded to caller" )

   // tool_call assembly across fragments
   bTransport := {| hR, bOnChunk | ;
      HB_SYMBOL_UNUSED( hR ), ;
      Eval( bOnChunk, 'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"read","arguments":"{\\"p\\":"}}]}}]}' + Chr(10) ), ;
      Eval( bOnChunk, 'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"a\\"}"}}]}}]}' + Chr(10) ), ;
      Eval( bOnChunk, "data: [DONE]" + Chr(10) ), ;
      { "ok" => .T., "status" => 200, "curl_code" => 0, "error" => "" } }
   hResult := DS_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "x" } }, ;
      { "transport" => bTransport }, {| h | HB_SYMBOL_UNUSED( h ) } )
   T_Equal( Len( hResult[ "tool_calls" ] ), 1, "api: one tool call" )
   T_Equal( hResult[ "tool_calls" ][ 1 ][ "id" ], "c1", "api: tool call id" )
   T_Equal( hResult[ "tool_calls" ][ 1 ][ "name" ], "read", "api: tool call name" )
   T_Equal( hResult[ "tool_calls" ][ 1 ][ "arguments" ], '{"p":"a"}', "api: tool args joined" )

   // missing API key -> config error, no transport call
   oClient := DS_Client( {=>} )
   hResult := DS_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "x" } }, {=>}, NIL )
   T_Equal( hResult[ "success" ], .F., "api: missing key fails" )
   T_Equal( hResult[ "error_type" ], "config", "api: missing key error_type" )

   // transport network error surfaces in hResult
   bTransport := {| hR, bOnChunk | ;
      HB_SYMBOL_UNUSED( hR ), HB_SYMBOL_UNUSED( bOnChunk ), ;
      { "ok" => .F., "status" => 0, "curl_code" => 7, "error" => "no connect" } }
   oClient := DS_Client( { "api_key" => "k", "model" => "deepseek-chat" } )
   hResult := DS_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "x" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hResult[ "success" ], .F., "api: network failure" )
   T_Equal( hResult[ "error_type" ], "network", "api: network error_type" )

   // HTTP 429 -> api error, retryable
   bTransport := {| hR, bOnChunk | ;
      HB_SYMBOL_UNUSED( hR ), ;
      Eval( bOnChunk, '{"error":{"message":"slow down","code":"rate_limit"}}' ), ;
      { "ok" => .T., "status" => 429, "curl_code" => 0, "error" => "" } }
   hResult := DS_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "x" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hResult[ "error_type" ], "api", "api: 429 error_type" )
   T_Equal( hResult[ "retryable" ], .T., "api: 429 retryable" )
   RETURN NIL
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: FAIL for `api:` tests (`DS_ChatCompletion` undefined).

- [ ] **Step 4: Implement the API layer**

Replace the entire contents of `src/dsapi.prg`:

```harbour
// Creates a client. hOpts: { api_key, base_url, model, timeout, config_path }.
// The returned hash holds only immutable data -> safe to share read-only
// across pool threads.
FUNCTION DS_Client( hOpts )
   IF ValType( hOpts ) != "H"
      hOpts := {=>}
   ENDIF
   RETURN { "opts" => hOpts, ;
            "model" => iif( hb_HHasKey( hOpts, "model" ), hOpts[ "model" ], NIL ), ;
            "timeout" => iif( hb_HHasKey( hOpts, "timeout" ), hOpts[ "timeout" ], 120 ) }

// Runs one streaming chat completion.
// hParams: { model, temperature, max_tokens, tools, tool_choice, transport }.
// bOnEvent (optional): codeblock invoked per parsed SSE event.
// Returns hResult: { success, content, tool_calls, finish_reason, usage,
//                    error_type, status, curl_code, retryable, message }
FUNCTION DS_ChatCompletion( oClient, aMessages, hParams, bOnEvent )
   LOCAL hCfg, hResult, hState, oParser, hReq, hHttp, cBody, cModel, bEmit

   IF ValType( hParams ) != "H"
      hParams := {=>}
   ENDIF

   hResult := { "success" => .F., "content" => "", "tool_calls" => {}, ;
                "finish_reason" => NIL, "usage" => NIL, "error_type" => NIL, ;
                "status" => NIL, "curl_code" => NIL, "retryable" => .F., ;
                "message" => NIL }

   // 1. resolve key/url (fail fast, no HTTP)
   hCfg := DSCFG_Resolve( oClient[ "opts" ] )
   IF !hCfg[ "ok" ]
      hResult[ "error_type" ] := hCfg[ "error_type" ]
      hResult[ "message" ]    := hCfg[ "message" ]
      DS_Emit( bOnEvent, { "type" => "error", "error_type" => hCfg[ "error_type" ], ;
                           "message" => hCfg[ "message" ] } )
      RETURN hResult
   ENDIF

   cModel := iif( hb_HHasKey( hParams, "model" ), hParams[ "model" ], oClient[ "model" ] )
   IF Empty( cModel )
      hResult[ "error_type" ] := "config"
      hResult[ "message" ]    := "No model id: set it on the client or in hParams"
      DS_Emit( bOnEvent, { "type" => "error", "error_type" => "config", ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   // 2. build request body
   cBody := hb_jsonEncode( DS_BuildBody( cModel, aMessages, hParams ) )
   hReq  := { "url" => hCfg[ "base_url" ] + "/chat/completions", ;
              "headers" => { "Content-Type: application/json", ;
                             "Accept: text/event-stream", ;
                             "Authorization: Bearer " + hCfg[ "api_key" ] }, ;
              "body" => cBody, ;
              "timeout" => oClient[ "timeout" ] }

   // 3. stream: feed every chunk to a fresh parser; assemble into hState
   hState  := { "content" => "", "tools" => {}, "finish" => NIL, ;
                "usage" => NIL, "got_done" => .F., "raw" => "" }
   oParser := DSSSE_New()
   bEmit   := {| hEv | DS_OnEvent( hEv, hState, bOnEvent ) }

   hHttp := DSHTTP_Post( hReq, ;
      {| cChunk | DS_FeedChunk( cChunk, hState, oParser, bEmit ) }, ;
      iif( hb_HHasKey( hParams, "transport" ), hParams[ "transport" ], NIL ) )

   // 4. classify the outcome
   hResult[ "status" ]    := hHttp[ "status" ]
   hResult[ "curl_code" ] := hHttp[ "curl_code" ]

   IF !hHttp[ "ok" ]
      hResult[ "error_type" ] := "network"
      hResult[ "message" ]    := hHttp[ "error" ]
      DS_Emit( bOnEvent, { "type" => "error", "error_type" => "network", ;
                           "message" => hHttp[ "error" ] } )
      RETURN hResult
   ENDIF

   IF hHttp[ "status" ] < 200 .OR. hHttp[ "status" ] >= 300
      hResult[ "error_type" ] := "api"
      hResult[ "retryable" ]  := ( hHttp[ "status" ] == 429 .OR. hHttp[ "status" ] >= 500 )
      hResult[ "message" ]    := DS_ApiErrorMessage( hState[ "raw" ], hHttp[ "status" ] )
      DS_Emit( bOnEvent, { "type" => "error", "error_type" => "api", ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   IF !hState[ "got_done" ]
      hResult[ "error_type" ] := "stream_incomplete"
      hResult[ "message" ]    := "Stream closed before [DONE]"
      DS_Emit( bOnEvent, { "type" => "error", "error_type" => "stream_incomplete", ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   hResult[ "success" ]       := .T.
   hResult[ "content" ]       := hState[ "content" ]
   hResult[ "tool_calls" ]    := hState[ "tools" ]
   hResult[ "finish_reason" ] := hState[ "finish" ]
   hResult[ "usage" ]         := hState[ "usage" ]
   RETURN hResult

STATIC FUNCTION DS_BuildBody( cModel, aMessages, hParams )
   LOCAL hBody := { "model" => cModel, "messages" => aMessages, ;
                    "stream" => .T., ;
                    "stream_options" => { "include_usage" => .T. } }
   IF hb_HHasKey( hParams, "temperature" )
      hBody[ "temperature" ] := hParams[ "temperature" ]
   ENDIF
   IF hb_HHasKey( hParams, "max_tokens" )
      hBody[ "max_tokens" ] := hParams[ "max_tokens" ]
   ENDIF
   IF hb_HHasKey( hParams, "tools" )
      hBody[ "tools" ] := hParams[ "tools" ]
   ENDIF
   IF hb_HHasKey( hParams, "tool_choice" )
      hBody[ "tool_choice" ] := hParams[ "tool_choice" ]
   ENDIF
   RETURN hBody

// Records raw bytes (for error bodies) and feeds the SSE parser.
STATIC FUNCTION DS_FeedChunk( cChunk, hState, oParser, bEmit )
   hState[ "raw" ] += cChunk
   DSSSE_Feed( oParser, cChunk, bEmit )
   RETURN NIL

// Folds one parsed SSE event into hState and forwards it to the caller.
STATIC FUNCTION DS_OnEvent( hEv, hState, bOnEvent )
   DO CASE
   CASE hEv[ "type" ] == "text_delta"
      hState[ "content" ] += hEv[ "text" ]
   CASE hEv[ "type" ] == "tool_call_delta"
      DS_AccTool( hState[ "tools" ], hEv )
   CASE hEv[ "type" ] == "finish"
      hState[ "finish" ] := hEv[ "finish_reason" ]
   CASE hEv[ "type" ] == "usage"
      hState[ "usage" ] := hEv[ "usage" ]
   CASE hEv[ "type" ] == "done"
      hState[ "got_done" ] := .T.
   ENDCASE
   DS_Emit( bOnEvent, hEv )
   RETURN NIL

// Merges a tool_call_delta into the accumulator array, keyed by "index".
STATIC FUNCTION DS_AccTool( aTools, hEv )
   LOCAL hTool, nFound := 0, i
   FOR i := 1 TO Len( aTools )
      IF aTools[ i ][ "index" ] == hEv[ "index" ]
         nFound := i
         EXIT
      ENDIF
   NEXT
   IF nFound == 0
      hTool := { "index" => hEv[ "index" ], "id" => "", "name" => "", "arguments" => "" }
      AAdd( aTools, hTool )
   ELSE
      hTool := aTools[ nFound ]
   ENDIF
   IF hEv[ "id" ] != NIL
      hTool[ "id" ] := hEv[ "id" ]
   ENDIF
   IF hEv[ "name" ] != NIL
      hTool[ "name" ] := hEv[ "name" ]
   ENDIF
   IF hEv[ "arguments" ] != NIL
      hTool[ "arguments" ] += hEv[ "arguments" ]
   ENDIF
   RETURN NIL

STATIC FUNCTION DS_ApiErrorMessage( cRaw, nStatus )
   LOCAL xJson
   xJson := hb_jsonDecode( cRaw )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "error" ) .AND. ;
      ValType( xJson[ "error" ] ) == "H" .AND. ;
      hb_HHasKey( xJson[ "error" ], "message" )
      RETURN xJson[ "error" ][ "message" ]
   ENDIF
   RETURN "HTTP " + LTrim( Str( nStatus ) )

STATIC FUNCTION DS_Emit( bOnEvent, hEv )
   IF bOnEvent != NIL
      Eval( bOnEvent, hEv )
   ENDIF
   RETURN NIL
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: all `api:` lines `ok`; SSE/config/http tests still `ok`; exit code 0.

- [ ] **Step 6: Commit**

```bash
git add src/dsapi.prg tests/test_api.prg tests/tests.hbp tests/run_tests.prg
git commit -m "feat: API orchestration with streaming assembly and error classification"
```

---

### Task 7: Real libcurl transport and opt-in integration test

**Files:**
- Modify: `src/dshttp.prg` (replace `DSHTTP_CurlPost`)
- Create: `tests/integration.prg`
- Create: `src/dsclient.hbp`

- [ ] **Step 1: Verify the hbcurl write-callback capability**

hbcurl exposes per-chunk delivery through `HB_CURLOPT_WRITEFUNCTION` set to a Harbour codeblock that receives each received buffer as a string. Confirm it exists in the installed contrib before relying on it.

Run: `hbmk2 --help >NUL 2>&1 & findstr /I /C:"HB_CURLOPT_WRITEFUNCTION" "%HB_INSTALL%\include\hbcurl.ch"`
(Adjust the path: `hbcurl.ch` lives in the Harbour `include` directory. If `%HB_INSTALL%` is unset, locate it with `where hbmk2` and use that folder's `..\include`.)
Expected: a line containing `HB_CURLOPT_WRITEFUNCTION`.

If the symbol is **absent**, do not implement Step 2. Instead, implement `DSHTTP_CurlPost` by spawning `curl.exe` with `hb_processOpen()` using args `{ "curl", "-s", "-N", "--data-binary", "@-", ... }`, write the body to its stdin, and read stdout incrementally with `hb_processValue`/non-blocking reads — the chunk callback and return-hash contract stay identical. Record which path was taken in a comment at the top of `src/dshttp.prg`.

- [ ] **Step 2: Implement the libcurl transport**

In `src/dshttp.prg`, add `#include "hbcurl.ch"` at the top, then replace the `DSHTTP_CurlPost` placeholder function with:

```harbour
FUNCTION DSHTTP_CurlPost( hReq, bOnChunk )
   LOCAL hCurl, nErr, nStatus := 0, cHeader

   hCurl := curl_easy_init()
   IF hCurl == NIL
      RETURN { "ok" => .F., "status" => 0, "curl_code" => -1, ;
               "error" => "curl_easy_init failed" }
   ENDIF

   curl_easy_setopt( hCurl, HB_CURLOPT_URL, hReq[ "url" ] )
   curl_easy_setopt( hCurl, HB_CURLOPT_POST, .T. )
   curl_easy_setopt( hCurl, HB_CURLOPT_POSTFIELDS, hReq[ "body" ] )
   curl_easy_setopt( hCurl, HB_CURLOPT_SSL_VERIFYPEER, .T. )
   curl_easy_setopt( hCurl, HB_CURLOPT_SSL_VERIFYHOST, 2 )
   curl_easy_setopt( hCurl, HB_CURLOPT_TIMEOUT, hReq[ "timeout" ] )
   FOR EACH cHeader IN hReq[ "headers" ]
      curl_easy_setopt( hCurl, HB_CURLOPT_HTTPHEADER, cHeader )
   NEXT
   // per-chunk delivery: the codeblock receives each received buffer
   curl_easy_setopt( hCurl, HB_CURLOPT_WRITEFUNCTION, ;
      {| cData | Eval( bOnChunk, cData ), Len( cData ) } )

   nErr := curl_easy_perform( hCurl )
   IF nErr == 0
      nStatus := curl_easy_getinfo( hCurl, HB_CURLINFO_RESPONSE_CODE )
   ENDIF
   curl_easy_cleanup( hCurl )

   RETURN { "ok" => ( nErr == 0 ), ;
            "status" => nStatus, ;
            "curl_code" => nErr, ;
            "error" => iif( nErr == 0, "", curl_easy_strerror( nErr ) ) }
```

Each call creates and cleans up its own easy handle — required for pool-safety.

- [ ] **Step 3: Build and run the existing suite (no regressions)**

Run: `hbmk2 tests/tests.hbp && tests/run_tests.exe`
Expected: all `sse:`/`cfg:`/`http:`/`api:` lines `ok`; exit code 0. The injected-transport tests never touch libcurl, so they must still pass.

- [ ] **Step 4: Write the opt-in integration program**

`tests/integration.prg`:

```harbour
// Real-network smoke test. Runs only when DEEPSEEK_API_KEY is set.
// Build: hbmk2 -mt -otests/integration src/dsconfig.prg src/dssse.prg ;
//        src/dshttp.prg src/dsapi.prg tests/integration.prg hbcurl.hbc
FUNCTION Main( cModel )
   LOCAL oClient, hResult

   IF Empty( hb_GetEnv( "DEEPSEEK_API_KEY" ) )
      ? "SKIP - DEEPSEEK_API_KEY not set"
      RETURN NIL
   ENDIF
   IF Empty( cModel )
      cModel := "deepseek-chat"
   ENDIF

   oClient := DS_Client( { "model" => cModel } )
   ? "Requesting model: " + cModel
   hResult := DS_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "Reply with the single word: pong" } }, ;
      {=>}, ;
      {| hEv | iif( hEv[ "type" ] == "text_delta", ;
                    ( OutStd( hEv[ "text" ] ), NIL ), NIL ) } )
   ? ""
   IF hResult[ "success" ]
      ? "OK - finish=" + hb_CStr( hResult[ "finish_reason" ] )
      ErrorLevel( 0 )
   ELSE
      ? "FAIL - " + hb_CStr( hResult[ "error_type" ] ) + ": " + ;
        hb_CStr( hResult[ "message" ] )
      ErrorLevel( 1 )
   ENDIF
   RETURN NIL
```

- [ ] **Step 5: Build the integration program and the library project file**

`src/dsclient.hbp` (lets the four modules be reused by later sub-projects):

```
-hblib
-odsclient
-mt
src/dsconfig.prg
src/dssse.prg
src/dshttp.prg
src/dsapi.prg
hbcurl.hbc
```

Run: `hbmk2 -mt -otests/integration src/dsconfig.prg src/dssse.prg src/dshttp.prg src/dsapi.prg tests/integration.prg hbcurl.hbc`
Expected: builds clean, produces `tests/integration.exe`.

- [ ] **Step 6: Run the integration test**

Run (with a real key set): `set DEEPSEEK_API_KEY=<your-key> & tests\integration.exe deepseek-chat`
Expected: streamed text appears, final line `OK - finish=stop`, exit code 0.
Without a key: `SKIP - DEEPSEEK_API_KEY not set`, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add src/dshttp.prg src/dsclient.hbp tests/integration.prg
git commit -m "feat: libcurl streaming transport and opt-in integration test"
```

---

## Self-Review

**Spec coverage:**
- API target (endpoint, OpenAI format, configurable model, Bearer auth) — Tasks 6, 7.
- `DS_Client` / `DS_ChatCompletion` / `hResult` shape — Task 6.
- SSE parser (`DSSSE_New`/`DSSSE_Feed`, text/tool/finish/usage/done) — Tasks 2, 3.
- Config resolution (env → file precedence) — Task 4.
- hbcurl wrapper + chosen approach + fallback — Task 7 (Steps 1–2).
- Concurrency / pool-safety (own curl handle per call, no globals) — Task 7 Step 2; client immutability — Task 6.
- Error handling (network/api/stream_incomplete/config, retryable, error events) — Task 6.
- Testing (pure parser tests, config tests, injectable transport, opt-in integration, TAP-ish runner) — Tasks 1–7.

**Deferred from the spec (correctly out of scope for #1):** cancellation via progress-callback. The spec lists it under concurrency; it has no consumer until sub-project #4 (UI) supplies a cancel flag. Wiring it now would be untestable dead code (YAGNI) — it belongs in the #4 plan.

**Placeholder scan:** the Task 1 source stubs and `DSHTTP_CurlPost` placeholder are intentional, explicitly replaced in named later tasks (2, 4, 5, 7) — not unresolved TODOs.

**Type consistency:** `hResult` keys, `hReq` keys (`url`/`headers`/`body`/`timeout`), the transport contract (`{|hReq,bOnChunk| -> {ok,status,curl_code,error}}`), and SSE event hashes are used identically across Tasks 2–7.

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

// Assumes the executor (DSTools_Dispatch) has already validated required args.
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

// Assumes the executor (DSTools_Dispatch) has already validated required args.
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

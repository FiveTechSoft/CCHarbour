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

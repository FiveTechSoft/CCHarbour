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
   hTool := CCTool_WebFetch()
   T_Equal( hTool[ "name" ], "web_fetch", "web_fetch: tool name" )
   hSchema := WebFindSchema( CCTOOLS_Schemas( { "web_fetch" => hTool } ), "web_fetch" )
   T_Assert( hSchema != NIL, "web_fetch: schema present" )
   T_Equal( hSchema[ "function" ][ "parameters" ][ "required" ][ 1 ], "url", ;
            "web_fetch: url required" )

   // --- web_fetch returns the body on HTTP 200 ---
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 200, "body" => "page-content", "error" => "" } } )
   cRes := Eval( hTool[ "handler" ], { "url" => "https://example.com" } )
   T_Equal( cRes, "page-content", "web_fetch: returns body" )
   CCHTTP_SetTestTransport( NIL )

   // --- web_fetch reports a non-2xx status ---
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 404, "body" => "", "error" => "" } } )
   cRes := Eval( hTool[ "handler" ], { "url" => "https://example.com/x" } )
   T_Equal( cRes, "Error: web_fetch HTTP 404", "web_fetch: non-2xx error" )
   CCHTTP_SetTestTransport( NIL )

   // --- web_fetch reports a transport failure ---
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .F., "status" => 0, "body" => "", "error" => "couldnt connect" } } )
   cRes := Eval( hTool[ "handler" ], { "url" => "https://example.com/x" } )
   T_Equal( cRes, "Error: web_fetch failed: couldnt connect", ;
            "web_fetch: transport failure error" )
   CCHTTP_SetTestTransport( NIL )

   // --- web_search schema ---
   hTool := CCTool_WebSearch()
   T_Equal( hTool[ "name" ], "web_search", "web_search: tool name" )
   T_Assert( "No API key required" $ hTool[ "description" ], ;
             "web_search: description mentions no-key" )

   // --- web_search formats a DuckDuckGo response ---
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 200, "error" => "", ;
        "body" => hb_jsonEncode( { "AbstractText" => "Harbour is a xBase compiler", ;
                                   "AbstractURL" => "https://harbour.github.io", ;
                                   "AbstractSource" => "Wikipedia", ;
                                   "Results" => { { "Text" => "Harbour Lang", ;
                                                    "FirstURL" => "https://harbour-lang.org" } } } ) } } )
   cRes := Eval( hTool[ "handler" ], { "query" => "x" } )
   T_Assert( "Harbour" $ cRes .AND. "Harbour Lang" $ cRes, ;
             "web_search: formats results" )
   CCHTTP_SetTestTransport( NIL )

   // --- web_search reports a non-2xx status ---
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 401, "body" => "", "error" => "" } } )
   cRes := Eval( hTool[ "handler" ], { "query" => "x" } )
   T_Equal( cRes, "Error: web_search HTTP 401", "web_search: non-2xx error" )
   CCHTTP_SetTestTransport( NIL )

   RETURN NIL

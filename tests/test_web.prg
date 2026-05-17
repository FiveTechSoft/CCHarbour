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

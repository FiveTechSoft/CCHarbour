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

   // missing url -> structured error, no crash
   hRes := DSHTTP_Fetch( {=>} )
   T_Equal( hRes[ "ok" ], .F., "fetch: missing url ok flag" )
   T_Equal( hRes[ "error" ], "missing url", "fetch: missing url error" )

   RETURN NIL

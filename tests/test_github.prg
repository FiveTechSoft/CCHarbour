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

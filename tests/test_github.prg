FUNCTION Test_Github()
   LOCAL hTool, cRes, cFileJson

   // --- github_read schema ---
   hTool := CCTool_GithubRead( "" )
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
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 200, "body" => cFileJson, "error" => "" } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "file", "repo" => "a/b", "path" => "README.md" } )
   T_Equal( cRes, "hello world", "github_read: file decodes base64" )
   CCHTTP_SetTestTransport( NIL )

   // --- non-2xx surfaces the API message ---
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 404, "error" => "", ;
        "body" => hb_jsonEncode( { "message" => "Not Found" } ) } } )
   cRes := Eval( hTool[ "handler" ], { "operation" => "repo", "repo" => "a/b" } )
   T_Equal( cRes, "Error: github_read HTTP 404: Not Found", ;
            "github_read: non-2xx with message" )
   CCHTTP_SetTestTransport( NIL )

   // --- non-numeric number is rejected ---
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "issue", "repo" => "a/b", "number" => "notnum" } )
   T_Equal( cRes, "Error: github_read 'issue' requires a numeric 'number'", ;
            "github_read: non-numeric number" )

   // --- issue operation builds the numbered URL ---
   CCHTTP_SetTestTransport( {| hR | ;
      T_Equal( hR[ "url" ], "https://api.github.com/repos/a/b/issues/42", ;
               "github_read: issue url" ), ;
      { "ok" => .T., "status" => 200, "body" => "{}", "error" => "" } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "issue", "repo" => "a/b", "number" => 42 } )
   CCHTTP_SetTestTransport( NIL )

   // --- list operation formats directory entries ---
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 200, "error" => "", ;
        "body" => hb_jsonEncode( { { "type" => "file", "name" => "README.md" }, ;
                                   { "type" => "dir", "name" => "src" } } ) } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "list", "repo" => "a/b", "path" => "src" } )
   T_Assert( "file  README.md" $ cRes .AND. "dir  src" $ cRes, ;
             "github_read: list formats entries" )
   CCHTTP_SetTestTransport( NIL )

   // --- transport failure ---
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .F., "status" => 0, "body" => "", "error" => "couldnt connect" } } )
   cRes := Eval( hTool[ "handler" ], { "operation" => "repo", "repo" => "a/b" } )
   T_Equal( cRes, "Error: github_read failed: couldnt connect", ;
            "github_read: transport failure" )
   CCHTTP_SetTestTransport( NIL )

   // --- github_write schema ---
   hTool := CCTool_GithubWrite( "tok" )
   T_Equal( hTool[ "name" ], "github_write", "github_write: tool name" )

   // --- missing token ---
   hTool := CCTool_GithubWrite( "" )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "create_issue", "repo" => "a/b", "title" => "T" } )
   T_Equal( cRes, "Error: GITHUB_TOKEN not set", "github_write: missing token" )

   // --- argument validation ---
   hTool := CCTool_GithubWrite( "tok" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "create_issue", "repo" => "a/b" } )
   T_Equal( cRes, "Error: github_write 'create_issue' requires 'title'", ;
            "github_write: missing title" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "comment", "repo" => "a/b" } )
   T_Equal( cRes, "Error: github_write 'comment' requires 'number'", ;
            "github_write: missing number" )

   // --- create_issue posts and reports the created URL ---
   CCHTTP_SetTestTransport( {| hR | ;
      T_Equal( hR[ "method" ], "POST", "github_write: uses POST" ), ;
      { "ok" => .T., "status" => 201, "error" => "", ;
        "body" => hb_jsonEncode( { "html_url" => "https://github.com/a/b/issues/7" } ) } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "create_issue", "repo" => "a/b", ;
                   "title" => "Bug", "body" => "desc" } )
   T_Equal( cRes, "Created: https://github.com/a/b/issues/7", ;
            "github_write: create_issue result" )
   CCHTTP_SetTestTransport( NIL )

   // --- non-2xx surfaces the API message ---
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 422, "error" => "", ;
        "body" => hb_jsonEncode( { "message" => "Validation Failed" } ) } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "create_issue", "repo" => "a/b", "title" => "X" } )
   T_Equal( cRes, "Error: github_write HTTP 422: Validation Failed", ;
            "github_write: non-2xx with message" )
   CCHTTP_SetTestTransport( NIL )

   // --- create_pr missing args ---
   hTool := CCTool_GithubWrite( "tok" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "create_pr", "repo" => "a/b", ;
                                       "title" => "T" } )
   T_Equal( cRes, "Error: github_write 'create_pr' requires 'title', 'head', 'base'", ;
            "github_write: create_pr missing args" )

   // --- comment posts to the issue comments URL ---
   CCHTTP_SetTestTransport( {| hR | ;
      T_Equal( hR[ "url" ], "https://api.github.com/repos/a/b/issues/9/comments", ;
               "github_write: comment url" ), ;
      { "ok" => .T., "status" => 201, "error" => "", ;
        "body" => hb_jsonEncode( { "html_url" => "https://github.com/a/b/issues/9#c1" } ) } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "comment", "repo" => "a/b", "number" => 9, ;
                   "body" => "nice" } )
   T_Equal( cRes, "Created: https://github.com/a/b/issues/9#c1", ;
            "github_write: comment result" )
   CCHTTP_SetTestTransport( NIL )

   // --- create_pr posts to the pulls URL ---
   CCHTTP_SetTestTransport( {| hR | ;
      T_Equal( hR[ "url" ], "https://api.github.com/repos/a/b/pulls", ;
               "github_write: create_pr url" ), ;
      { "ok" => .T., "status" => 201, "error" => "", ;
        "body" => hb_jsonEncode( { "html_url" => "https://github.com/a/b/pull/3" } ) } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "create_pr", "repo" => "a/b", "title" => "PR", ;
                   "head" => "feature", "base" => "master", "body" => "desc" } )
   T_Equal( cRes, "Created: https://github.com/a/b/pull/3", ;
            "github_write: create_pr result" )
   CCHTTP_SetTestTransport( NIL )

   // file content over 30000 bytes is truncated
   hTool := CCTool_GithubRead( "" )
   CCHTTP_SetTestTransport( {| hR | HB_SYMBOL_UNUSED( hR ), ;
      { "ok" => .T., "status" => 200, "error" => "", ;
        "body" => hb_jsonEncode( { "content" => ;
           hb_base64Encode( Replicate( "a", 30001 ) ) } ) } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "file", "repo" => "a/b", "path" => "big.txt" } )
   T_Assert( "[output truncated]" $ cRes, "github_read: file truncated" )
   CCHTTP_SetTestTransport( NIL )

   // file/list path is percent-encoded in the URL
   CCHTTP_SetTestTransport( {| hR | ;
      T_Equal( hR[ "url" ], ;
               "https://api.github.com/repos/a/b/contents/my%20dir/f.txt", ;
               "github_read: path encoded" ), ;
      { "ok" => .T., "status" => 200, "body" => "{}", "error" => "" } } )
   cRes := Eval( hTool[ "handler" ], ;
                 { "operation" => "list", "repo" => "a/b", "path" => "my dir/f.txt" } )
   CCHTTP_SetTestTransport( NIL )

   RETURN NIL

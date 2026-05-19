// Returns the schema entry for cName from an aSchemas array, or NIL.
STATIC FUNCTION FindSchema( aSchemas, cName )
   LOCAL h
   FOR EACH h IN aSchemas
      IF h[ "function" ][ "name" ] == cName
         RETURN h
      ENDIF
   NEXT
   RETURN NIL

FUNCTION Test_Tools()
   LOCAL oReg, bExec, aSchemas, hEcho, hCustom, cTmp, cRes, cTmpDir

   // a custom tool used to exercise the registry and executor
   hCustom := { "name" => "echo", ;
                "description" => "Echoes its text argument", ;
                "parameters" => { "type" => "object", ;
                   "properties" => { "text" => { "type" => "string" } }, ;
                   "required" => { "text" } }, ;
                "handler" => {| hArgs | "echo:" + hArgs[ "text" ] } }

   oReg := CCTOOLS_Registry()
   T_Equal( ValType( oReg ), "H", "tools: registry is a hash" )
   CCTOOLS_Register( oReg, hCustom )
   T_Equal( hb_HHasKey( oReg, "echo" ), .T., "tools: register adds tool" )

   // schemas expose the registered tool in OpenAI form
   aSchemas := CCTOOLS_Schemas( oReg )
   hEcho := FindSchema( aSchemas, "echo" )
   T_Assert( hEcho != NIL, "tools: schema present for echo" )
   T_Equal( hEcho[ "type" ], "function", "tools: schema type" )
   T_Equal( hEcho[ "function" ][ "description" ], "Echoes its text argument", ;
            "tools: schema description" )
   T_Equal( ValType( hEcho[ "function" ][ "parameters" ] ), "H", ;
            "tools: schema parameters" )

   // the executor dispatches by name and parses JSON arguments
   bExec := CCTOOLS_Executor( oReg )
   T_Equal( Eval( bExec, "echo", '{"text":"hi"}' ), "echo:hi", ;
            "tools: executor dispatches and parses args" )
   T_Equal( Eval( bExec, "nope", "{}" ), "Error: unknown tool 'nope'", ;
            "tools: executor unknown tool" )
   T_Equal( Eval( bExec, "echo", "not json" ), "Error: invalid arguments JSON", ;
            "tools: executor invalid JSON" )
   T_Equal( Eval( bExec, "echo", "{}" ), "Error: missing required argument 'text'", ;
            "tools: executor missing required arg" )

   // read tool
   bExec := CCTOOLS_Executor( CCTOOLS_Registry() )
   cTmp := hb_DirTemp() + "CCTOOLS_read.txt"
   hb_MemoWrit( cTmp, "alpha" + Chr(10) + "beta" + Chr(10) + "gamma" + Chr(10) )

   cRes := Eval( bExec, "read", hb_jsonEncode( { "path" => cTmp } ) )
   T_Assert( "alpha" $ cRes, "tools: read returns content" )
   T_Assert( Chr(9) $ cRes, "tools: read has line-number tab" )

   cRes := Eval( bExec, "read", ;
      hb_jsonEncode( { "path" => cTmp, "offset" => 2 } ) )
   T_Assert( "gamma" $ cRes, "tools: read offset keeps later lines" )
   T_Assert( !( "alpha" $ cRes ), "tools: read offset drops earlier lines" )

   cRes := Eval( bExec, "read", ;
      hb_jsonEncode( { "path" => cTmp, "max_lines" => 1 } ) )
   T_Assert( "[truncated:" $ cRes, "tools: read max_lines truncates" )

   cRes := Eval( bExec, "read", ;
      hb_jsonEncode( { "path" => hb_DirTemp() + "no_such_file.txt" } ) )
   T_Assert( "Error: file not found" $ cRes, "tools: read missing file" )
   FErase( cTmp )

   // write tool
   bExec := CCTOOLS_Executor( CCTOOLS_Registry() )
   cTmp := hb_DirTemp() + "CCTOOLS_write.txt"
   FErase( cTmp )
   cRes := Eval( bExec, "write", ;
      hb_jsonEncode( { "path" => cTmp, "content" => "hello world" } ) )
   T_Assert( "Wrote" $ cRes, "tools: write reports success" )
   T_Equal( hb_MemoRead( cTmp ), "hello world", "tools: write content on disk" )

   // edit tool: unique replacement
   hb_MemoWrit( cTmp, "one two one" )
   cRes := Eval( bExec, "edit", hb_jsonEncode( { "path" => cTmp, ;
      "old_string" => "two", "new_string" => "TWO" } ) )
   T_Assert( "removed" $ cRes, "tools: edit returns a diff" )
   T_Equal( hb_MemoRead( cTmp ), "one TWO one", "tools: edit applied" )

   // edit tool: non-unique target without replace_all -> error
   hb_MemoWrit( cTmp, "x x x" )
   cRes := Eval( bExec, "edit", hb_jsonEncode( { "path" => cTmp, ;
      "old_string" => "x", "new_string" => "y" } ) )
   T_Assert( "not unique" $ cRes, "tools: edit non-unique error" )

   // edit tool: replace_all
   cRes := Eval( bExec, "edit", hb_jsonEncode( { "path" => cTmp, ;
      "old_string" => "x", "new_string" => "y", "replace_all" => .T. } ) )
   T_Equal( hb_MemoRead( cTmp ), "y y y", "tools: edit replace_all" )

   // edit tool: missing file -> error
   cRes := Eval( bExec, "edit", hb_jsonEncode( { ;
      "path" => hb_DirTemp() + "no_such_edit.txt", ;
      "old_string" => "a", "new_string" => "b" } ) )
   T_Assert( "Error: file not found" $ cRes, "tools: edit missing file" )
   FErase( cTmp )

   // glob + grep tools: build a small temp directory tree
   bExec := CCTOOLS_Executor( CCTOOLS_Registry() )
   cTmpDir := hb_DirTemp() + "CCTOOLS_search"
   hb_DirBuild( cTmpDir )
   hb_MemoWrit( cTmpDir + hb_ps() + "a.txt", "needle here" + Chr(10) + "plain line" + Chr(10) )
   hb_MemoWrit( cTmpDir + hb_ps() + "b.txt", "another needle" + Chr(10) )
   hb_MemoWrit( cTmpDir + hb_ps() + "c.log", "needle in log" + Chr(10) )

   // glob: match *.txt
   cRes := Eval( bExec, "glob", ;
      hb_jsonEncode( { "pattern" => "*.txt", "path" => cTmpDir } ) )
   T_Assert( "a.txt" $ cRes, "tools: glob finds a.txt" )
   T_Assert( "b.txt" $ cRes, "tools: glob finds b.txt" )
   T_Assert( !( "c.log" $ cRes ), "tools: glob respects the mask" )

   // glob: no matches
   cRes := Eval( bExec, "glob", ;
      hb_jsonEncode( { "pattern" => "*.xyz", "path" => cTmpDir } ) )
   T_Assert( "No matches" $ cRes, "tools: glob no matches" )

   // grep: pattern across files
   cRes := Eval( bExec, "grep", ;
      hb_jsonEncode( { "pattern" => "needle", "path" => cTmpDir } ) )
   T_Assert( "a.txt:1:" $ cRes, "tools: grep reports file:line" )
   T_Assert( "needle in log" $ cRes, "tools: grep scans all files by default" )

   // grep: glob filter restricts scanned files
   cRes := Eval( bExec, "grep", hb_jsonEncode( { "pattern" => "needle", ;
      "path" => cTmpDir, "glob" => "*.log" } ) )
   T_Assert( "needle in log" $ cRes, "tools: grep glob filter keeps matches" )
   T_Assert( !( "a.txt" $ cRes ), "tools: grep glob filter excludes others" )

   // grep: invalid regex -> error
   cRes := Eval( bExec, "grep", hb_jsonEncode( { "pattern" => "[unclosed", ;
      "path" => cTmpDir } ) )
   T_Assert( "Error: invalid regex" $ cRes, "tools: grep invalid regex" )

   FErase( cTmpDir + hb_ps() + "a.txt" )
   FErase( cTmpDir + hb_ps() + "b.txt" )
   FErase( cTmpDir + hb_ps() + "c.log" )
   hb_DirDelete( cTmpDir )

   // shell tool
   bExec := CCTOOLS_Executor( CCTOOLS_Registry() )
   cRes := Eval( bExec, "shell", hb_jsonEncode( { "command" => "echo hello" } ) )
   T_Assert( "hello" $ cRes, "tools: shell captures output" )
   T_Assert( "[exit code: 0]" $ cRes, "tools: shell reports exit 0" )

   cRes := Eval( bExec, "shell", hb_jsonEncode( { "command" => "exit 3" } ) )
   T_Assert( "[exit code: 3]" $ cRes, "tools: shell reports non-zero exit" )

   // shell tool with timeout: short command finishes quickly
   bExec := CCTOOLS_Executor( CCTOOLS_Registry( { "shell_timeout" => 5 } ) )
   cRes := Eval( bExec, "shell", hb_jsonEncode( { "command" => "echo timed_ok" } ) )
   T_Assert( "timed_ok" $ cRes, "tools: shell with timeout captures output" )
   T_Assert( "[exit code: 0]" $ cRes, "tools: shell with timeout exit 0" )

   // shell tool timeout: a slow command gets killed
   cRes := Eval( bExec, "shell", hb_jsonEncode( { "command" => "ping -n 10 127.0.0.1" } ) )
   T_Assert( "timed out" $ cRes, "tools: shell timeout kills long command" )

   // end-to-end: the default registry exposes all eleven builtin tools
   aSchemas := CCTOOLS_Schemas( CCTOOLS_Registry() )
   T_Equal( Len( aSchemas ), 11, "tools: registry has eleven builtins" )
   T_Assert( FindSchema( aSchemas, "read" )  != NIL, "tools: builtin read" )
   T_Assert( FindSchema( aSchemas, "write" ) != NIL, "tools: builtin write" )
   T_Assert( FindSchema( aSchemas, "edit" )  != NIL, "tools: builtin edit" )
   T_Assert( FindSchema( aSchemas, "glob" )  != NIL, "tools: builtin glob" )
   T_Assert( FindSchema( aSchemas, "grep" )  != NIL, "tools: builtin grep" )
   T_Assert( FindSchema( aSchemas, "shell" ) != NIL, "tools: builtin shell" )

   // the four new tools are registered
   oReg := CCTOOLS_Registry()
   T_Equal( hb_HHasKey( oReg, "web_search" ), .T., "tools: web_search registered" )
   T_Equal( hb_HHasKey( oReg, "web_fetch" ), .T., "tools: web_fetch registered" )
   T_Equal( hb_HHasKey( oReg, "github_read" ), .T., "tools: github_read registered" )
   T_Equal( hb_HHasKey( oReg, "github_write" ), .T., "tools: github_write registered" )

   // web_search no longer needs an API key (uses DuckDuckGo now)
   oReg := CCTOOLS_Registry( { "github" => "" } )
   T_Assert( hb_HHasKey( oReg, "web_search" ), "tools: web_search still registered w/o tavily key" )

   // the memory tool is registered
   oReg := CCTOOLS_Registry()
   T_Equal( hb_HHasKey( oReg, "memory" ), .T., "tools: memory registered" )
   RETURN NIL

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
   LOCAL oReg, bExec, aSchemas, hEcho, hCustom, cTmp, cRes

   // a custom tool used to exercise the registry and executor
   hCustom := { "name" => "echo", ;
                "description" => "Echoes its text argument", ;
                "parameters" => { "type" => "object", ;
                   "properties" => { "text" => { "type" => "string" } }, ;
                   "required" => { "text" } }, ;
                "handler" => {| hArgs | "echo:" + hArgs[ "text" ] } }

   oReg := DSTools_Registry()
   T_Equal( ValType( oReg ), "H", "tools: registry is a hash" )
   DSTools_Register( oReg, hCustom )
   T_Equal( hb_HHasKey( oReg, "echo" ), .T., "tools: register adds tool" )

   // schemas expose the registered tool in OpenAI form
   aSchemas := DSTools_Schemas( oReg )
   hEcho := FindSchema( aSchemas, "echo" )
   T_Assert( hEcho != NIL, "tools: schema present for echo" )
   T_Equal( hEcho[ "type" ], "function", "tools: schema type" )
   T_Equal( hEcho[ "function" ][ "description" ], "Echoes its text argument", ;
            "tools: schema description" )
   T_Equal( ValType( hEcho[ "function" ][ "parameters" ] ), "H", ;
            "tools: schema parameters" )

   // the executor dispatches by name and parses JSON arguments
   bExec := DSTools_Executor( oReg )
   T_Equal( Eval( bExec, "echo", '{"text":"hi"}' ), "echo:hi", ;
            "tools: executor dispatches and parses args" )
   T_Equal( Eval( bExec, "nope", "{}" ), "Error: unknown tool 'nope'", ;
            "tools: executor unknown tool" )
   T_Equal( Eval( bExec, "echo", "not json" ), "Error: invalid arguments JSON", ;
            "tools: executor invalid JSON" )
   T_Equal( Eval( bExec, "echo", "{}" ), "Error: missing required argument 'text'", ;
            "tools: executor missing required arg" )

   // read tool
   bExec := DSTools_Executor( DSTools_Registry() )
   cTmp := hb_DirTemp() + "dstools_read.txt"
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
   RETURN NIL

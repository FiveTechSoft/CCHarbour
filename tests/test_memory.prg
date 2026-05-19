FUNCTION Test_Memory()
   LOCAL hTool, cTmp, cRes
   cTmp := hb_DirTemp() + "ds_test_memory.md"
   FErase( cTmp )
   hTool := DSTool_Memory( cTmp )

   T_Equal( hTool[ "name" ], "memory", "memory: tool name" )
   T_Equal( hTool[ "parameters" ][ "required" ][ 1 ], "operation", ;
            "memory: operation required" )

   // append to a non-existent file creates it
   cRes := Eval( hTool[ "handler" ], { "operation" => "append", "text" => "fact one" } )
   T_Equal( cRes, "Remembered.", "memory: append result" )
   // a second append adds another line
   Eval( hTool[ "handler" ], { "operation" => "append", "text" => "fact two" } )

   // read returns both entries
   cRes := Eval( hTool[ "handler" ], { "operation" => "read" } )
   T_Assert( "fact one" $ cRes .AND. "fact two" $ cRes, "memory: read returns entries" )

   // clear empties the file
   cRes := Eval( hTool[ "handler" ], { "operation" => "clear" } )
   T_Equal( cRes, "Memory cleared.", "memory: clear result" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "read" } )
   T_Equal( cRes, "(memory is empty)", "memory: read after clear" )

   // read on an absent file is the empty state
   FErase( cTmp )
   cRes := Eval( hTool[ "handler" ], { "operation" => "read" } )
   T_Equal( cRes, "(memory is empty)", "memory: read absent file" )

   // append without text -> validation error
   cRes := Eval( hTool[ "handler" ], { "operation" => "append" } )
   T_Equal( cRes, "Error: memory 'append' requires 'text'", "memory: append missing text" )

   // unknown operation
   cRes := Eval( hTool[ "handler" ], { "operation" => "bogus" } )
   T_Equal( cRes, "Error: memory: unknown operation 'bogus'", "memory: unknown op" )

   // append to an unwritable path returns an error
   hTool := DSTool_Memory( "Z:\no_such_dir\deep\mem.md" )
   cRes := Eval( hTool[ "handler" ], { "operation" => "append", "text" => "x" } )
   T_Assert( "Error:" $ cRes, "memory: append write failure -> error" )

   FErase( cTmp )
   RETURN NIL

FUNCTION Test_UI()
   LOCAL hA

   hA := DSUI_ParseCommand( "/exit" )
   T_Equal( hA[ "type" ], "exit", "ui: /exit parses to exit" )

   hA := DSUI_ParseCommand( "/quit" )
   T_Equal( hA[ "type" ], "exit", "ui: /quit parses to exit" )

   hA := DSUI_ParseCommand( "/clear" )
   T_Equal( hA[ "type" ], "clear", "ui: /clear parses to clear" )

   hA := DSUI_ParseCommand( "/help" )
   T_Equal( hA[ "type" ], "help", "ui: /help parses to help" )

   hA := DSUI_ParseCommand( "" )
   T_Equal( hA[ "type" ], "empty", "ui: blank line parses to empty" )

   hA := DSUI_ParseCommand( "    " )
   T_Equal( hA[ "type" ], "empty", "ui: whitespace line parses to empty" )

   hA := DSUI_ParseCommand( "hello there" )
   T_Equal( hA[ "type" ], "message", "ui: text parses to message" )
   T_Equal( hA[ "text" ], "hello there", "ui: message keeps text" )

   hA := DSUI_ParseCommand( "/foo" )
   T_Equal( hA[ "type" ], "message", "ui: unknown slash is a message" )

   hA := DSUI_ParseCommand( "  /exit  " )
   T_Equal( hA[ "type" ], "exit", "ui: command is trimmed" )
   RETURN NIL

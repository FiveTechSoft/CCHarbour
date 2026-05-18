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

   // DSUI_Summarize
   T_Equal( DSUI_Summarize( "short", 80 ), "short", "ui: summarize short text" )
   T_Assert( "first" $ DSUI_Summarize( "first" + Chr(10) + "second", 80 ), ;
             "ui: summarize keeps first line" )
   T_Assert( !( "second" $ DSUI_Summarize( "first" + Chr(10) + "second", 80 ) ), ;
             "ui: summarize drops later lines" )
   T_Assert( "chars]" $ DSUI_Summarize( "first" + Chr(10) + "second", 80 ), ;
             "ui: summarize annotates size" )
   T_Assert( Len( DSUI_Summarize( Replicate( "x", 200 ), 80 ) ) < 110, ;
             "ui: summarize truncates long text" )

   // DSUI_RenderEvent
   T_Equal( DSUI_RenderEvent( { "type" => "text_delta", "text" => "hi" } ), "hi", ;
            "ui: render text_delta" )
   T_Assert( "Read(x)" $ DSUI_RenderEvent( { "type" => "tool_call", "id" => "c1", ;
             "name" => "read", "arguments" => '{"path":"x"}' } ), ;
             "ui: render tool_call shows labelled name" )
   T_Assert( ( Chr(226) + Chr(143) + Chr(186) ) $ DSUI_RenderEvent( { ;
             "type" => "tool_call", "id" => "c1", "name" => "read", ;
             "arguments" => "{}" } ), "ui: render tool_call has bullet" )
   T_Assert( "line two" $ DSUI_RenderEvent( { "type" => "tool_result", "id" => "c1", ;
             "content" => "line one" + Chr(10) + "line two" } ), ;
             "ui: render tool_result shows result lines" )
   T_Assert( "error" $ DSUI_RenderEvent( { "type" => "error", ;
             "error_type" => "network", "message" => "boom" } ), ;
             "ui: render error" )
   T_Equal( DSUI_RenderEvent( { "type" => "iteration_start", "n" => 1 } ), "", ;
            "ui: render ignores iteration_start" )

   // DSUI_SystemPrompt and DSUI_Help
   T_Assert( Len( DSUI_SystemPrompt() ) > 0, "ui: system prompt non-empty" )
   T_Assert( "/help" $ DSUI_Help(), "ui: help mentions /help" )
   T_Assert( "/clear" $ DSUI_Help(), "ui: help mentions /clear" )
   T_Assert( "/exit" $ DSUI_Help(), "ui: help mentions /exit" )

   // colour palette: codes returned regardless of colour state
   T_Equal( DSUI_Pal( "accent" ), "38;5;215", "ui: accent palette code" )
   T_Equal( DSUI_Pal( "dim" ), "90", "ui: dim palette code" )
   T_Equal( DSUI_Pal( "error" ), "31", "ui: error palette code" )
   T_Equal( DSUI_Pal( "bold" ), "1", "ui: bold palette code" )
   T_Equal( DSUI_Pal( "nope" ), "0", "ui: unknown palette name -> reset" )
   RETURN NIL

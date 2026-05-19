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
   T_Equal( DSUI_Pal( "accent" ), "38;2;217;119;87", "ui: accent palette code" )
   T_Equal( DSUI_Pal( "dim" ), "90", "ui: dim palette code" )
   T_Equal( DSUI_Pal( "error" ), "31", "ui: error palette code" )
   T_Equal( DSUI_Pal( "bold" ), "1", "ui: bold palette code" )
   T_Equal( DSUI_Pal( "nope" ), "0", "ui: unknown palette name -> reset" )

   // banner: single-panel Claude Code-style box
   DSUI_SetColor( .F. )
   T_Assert( "CCHarbour" $ DSUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has welcome line" )
   T_Assert( "model: deepseek-chat" $ DSUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has model line" )
   T_Assert( "cwd: C:\proj" $ DSUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has cwd line" )
   T_Assert( "/help for help" $ DSUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has help hint" )
   T_Assert( DSUI_Glyph( "tl" ) $ DSUI_Banner( "m", "c", "u" ), ;
             "ui: banner has a rounded top-left corner" )

   // input frame helpers
   DSUI_SetColor( .F. )
   T_Equal( hb_UTF8Len( DSUI_FrameTop() ), 79, "ui: frame top is 79 columns" )
   T_Equal( hb_UTF8Len( DSUI_FrameBottom() ), 79, "ui: frame bottom is 79 columns" )
   T_Assert( DSUI_Glyph( "tl" ) $ DSUI_FrameTop(), "ui: frame top rounded corner" )
   T_Assert( DSUI_Glyph( "bl" ) $ DSUI_FrameBottom(), "ui: frame bottom rounded corner" )
   T_Assert( "/help" $ DSUI_InputHint(), "ui: input hint mentions /help" )

   // system prompt asks for a suggested next prompt
   T_Assert( "Suggested next:" $ DSUI_SystemPrompt(), ;
             "ui: system prompt requests a suggested next line" )

   // --- tool-call line + result summary ---
   DSUI_SetColor( .F. )
   T_Assert( "Read(x.prg)" $ DSUI_ToolCallLine( "read", '{"path":"x.prg"}' ), ;
             "ui: tool-call line has the label" )
   T_Assert( ( Chr(226)+Chr(143)+Chr(186) ) $ DSUI_ToolCallLine( "read", "{}" ), ;
             "ui: tool-call line has the dot glyph" )

   T_Equal( "  " + Chr(226)+Chr(142)+Chr(191) + "  Read 3 lines" + Chr(10), ;
            DSUI_ResultSummary( "read", "a" + Chr(10) + "b" + Chr(10) + "c" + Chr(10) ), ;
            "ui: read result summary" )
   T_Assert( "Found 2 matches" $ ;
             DSUI_ResultSummary( "grep", "f:1:x" + Chr(10) + "f:2:y" + Chr(10) ), ;
             "ui: grep result summary" )
   T_Assert( "No matches for zzz" $ ;
             DSUI_ResultSummary( "grep", "No matches for zzz" ), ;
             "ui: grep no-matches passthrough" )
   T_Assert( "Wrote a.prg" $ DSUI_ResultSummary( "write", "Wrote a.prg" ), ;
             "ui: write result passthrough" )
   T_Assert( "Listed 2 files" $ ;
             DSUI_ResultSummary( "glob", "a.prg" + Chr(10) + "b.prg" + Chr(10) ), ;
             "ui: glob result summary" )
   T_Assert( "Error: file not found" $ ;
             DSUI_ResultSummary( "read", "Error: file not found: x" ), ;
             "ui: error result shows the error line" )
   T_Assert( "+ added" $ DSUI_ResultSummary( "edit", ;
             "     1 + added" + Chr(10) + "     2   kept" + Chr(10) ), ;
             "ui: diff content keeps the diff block" )

   // input box: inner width and the framed prompt line
   DSUI_SetColor( .F. )
   T_Equal( DSUI_InputInnerWidth(), 73, "ui: input inner width" )
   T_Equal( hb_UTF8Len( DSUI_InputBoxLine( "hi" ) ), 79, "ui: input box line is 79 columns" )
   T_Assert( "> hi" $ DSUI_InputBoxLine( "hi" ), "ui: input box line has the prompt + text" )
   T_Assert( DSUI_Glyph( "v" ) $ DSUI_InputBoxLine( "hi" ), "ui: input box line has side borders" )

   // version + banner
   T_Equal( DSUI_Version(), "0.2.0", "ui: version string" )
   DSUI_SetColor( .F. )
   T_Assert( "v0.2.0" $ DSUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the version" )
   T_Assert( "CCHarbour" $ DSUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the name" )
   T_Assert( "model: deepseek-v4-flash" $ DSUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the model" )
   T_Assert( "cwd: C:\proj" $ DSUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the cwd" )
   T_Assert( DSUI_Glyph( "tl" ) $ DSUI_Banner( "m", "c", "u" ), ;
             "ui: banner has the rounded box" )
   RETURN NIL

FUNCTION Test_UI()
   LOCAL hA

   hA := CCUI_ParseCommand( "/exit" )
   T_Equal( hA[ "type" ], "exit", "ui: /exit parses to exit" )

   hA := CCUI_ParseCommand( "/quit" )
   T_Equal( hA[ "type" ], "exit", "ui: /quit parses to exit" )

   hA := CCUI_ParseCommand( "/clear" )
   T_Equal( hA[ "type" ], "clear", "ui: /clear parses to clear" )

   hA := CCUI_ParseCommand( "/help" )
   T_Equal( hA[ "type" ], "help", "ui: /help parses to help" )

   hA := CCUI_ParseCommand( "" )
   T_Equal( hA[ "type" ], "empty", "ui: blank line parses to empty" )

   hA := CCUI_ParseCommand( "    " )
   T_Equal( hA[ "type" ], "empty", "ui: whitespace line parses to empty" )

   hA := CCUI_ParseCommand( "hello there" )
   T_Equal( hA[ "type" ], "message", "ui: text parses to message" )
   T_Equal( hA[ "text" ], "hello there", "ui: message keeps text" )

   hA := CCUI_ParseCommand( "/foo" )
   T_Equal( hA[ "type" ], "message", "ui: unknown slash is a message" )

   hA := CCUI_ParseCommand( "  /exit  " )
   T_Equal( hA[ "type" ], "exit", "ui: command is trimmed" )

   // CCUI_Summarize
   T_Equal( CCUI_Summarize( "short", 80 ), "short", "ui: summarize short text" )
   T_Assert( "first" $ CCUI_Summarize( "first" + Chr(10) + "second", 80 ), ;
             "ui: summarize keeps first line" )
   T_Assert( !( "second" $ CCUI_Summarize( "first" + Chr(10) + "second", 80 ) ), ;
             "ui: summarize drops later lines" )
   T_Assert( "chars]" $ CCUI_Summarize( "first" + Chr(10) + "second", 80 ), ;
             "ui: summarize annotates size" )
   T_Assert( Len( CCUI_Summarize( Replicate( "x", 200 ), 80 ) ) < 110, ;
             "ui: summarize truncates long text" )

   // CCUI_RenderEvent
   T_Equal( CCUI_RenderEvent( { "type" => "text_delta", "text" => "hi" } ), "hi", ;
            "ui: render text_delta" )
   T_Assert( "error" $ CCUI_RenderEvent( { "type" => "error", ;
             "error_type" => "network", "message" => "boom" } ), ;
             "ui: render error" )
   T_Equal( CCUI_RenderEvent( { "type" => "iteration_start", "n" => 1 } ), "", ;
            "ui: render ignores iteration_start" )

   // CCUI_SystemPrompt and CCUI_Help
   T_Assert( Len( CCUI_SystemPrompt() ) > 0, "ui: system prompt non-empty" )
   T_Assert( "/help" $ CCUI_Help(), "ui: help mentions /help" )
   T_Assert( "/clear" $ CCUI_Help(), "ui: help mentions /clear" )
   T_Assert( "/exit" $ CCUI_Help(), "ui: help mentions /exit" )

   // colour palette: codes returned regardless of colour state
   T_Equal( CCUI_Pal( "accent" ), "38;2;217;119;87", "ui: accent palette code" )
   T_Equal( CCUI_Pal( "dim" ), "90", "ui: dim palette code" )
   T_Equal( CCUI_Pal( "error" ), "31", "ui: error palette code" )
   T_Equal( CCUI_Pal( "bold" ), "1", "ui: bold palette code" )
   T_Equal( CCUI_Pal( "nope" ), "0", "ui: unknown palette name -> reset" )

   // banner: single-panel Claude Code-style box
   CCUI_SetColor( .F. )
   T_Assert( "CCHarbour" $ CCUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has the CCHarbour name" )
   T_Assert( "model: deepseek-chat" $ CCUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has model line" )
   T_Assert( "cwd: C:\proj" $ CCUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has cwd line" )
   T_Assert( "/help for help" $ CCUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has help hint" )
   T_Assert( CCUI_Glyph( "tl" ) $ CCUI_Banner( "m", "c", "u" ), ;
             "ui: banner has a rounded top-left corner" )

   // input frame helpers
   CCUI_SetColor( .F. )
   T_Equal( hb_UTF8Len( CCUI_FrameTop() ), 99, "ui: frame top is 99 columns" )
   T_Equal( hb_UTF8Len( CCUI_FrameBottom() ), 99, "ui: frame bottom is 99 columns" )
   T_Assert( CCUI_Glyph( "tl" ) $ CCUI_FrameTop(), "ui: frame top rounded corner" )
   T_Assert( CCUI_Glyph( "bl" ) $ CCUI_FrameBottom(), "ui: frame bottom rounded corner" )
   T_Assert( "/help" $ CCUI_InputHint(), "ui: input hint mentions /help" )

   // system prompt asks for a suggested next prompt
   T_Assert( "Suggested next:" $ CCUI_SystemPrompt(), ;
             "ui: system prompt requests a suggested next line" )

   // --- tool-call line + result summary ---
   CCUI_SetColor( .F. )
   T_Assert( "Read(x.prg)" $ CCUI_ToolCallLine( "read", '{"path":"x.prg"}' ), ;
             "ui: tool-call line has the label" )
   T_Assert( ( Chr(226)+Chr(143)+Chr(186) ) $ CCUI_ToolCallLine( "read", "{}" ), ;
             "ui: tool-call line has the dot glyph" )

   T_Equal( "  " + Chr(226)+Chr(142)+Chr(191) + "  Read 3 lines" + Chr(10), ;
            CCUI_ResultSummary( "read", "a" + Chr(10) + "b" + Chr(10) + "c" + Chr(10) ), ;
            "ui: read result summary" )
   T_Assert( "Found 2 matches" $ ;
             CCUI_ResultSummary( "grep", "f:1:x" + Chr(10) + "f:2:y" + Chr(10) ), ;
             "ui: grep result summary" )
   T_Assert( "No matches for zzz" $ ;
             CCUI_ResultSummary( "grep", "No matches for zzz" ), ;
             "ui: grep no-matches passthrough" )
   T_Assert( "Wrote a.prg" $ CCUI_ResultSummary( "write", "Wrote a.prg" ), ;
             "ui: write result passthrough" )
   T_Assert( "Listed 2 files" $ ;
             CCUI_ResultSummary( "glob", "a.prg" + Chr(10) + "b.prg" + Chr(10) ), ;
             "ui: glob result summary" )
   T_Assert( "Error: file not found" $ ;
             CCUI_ResultSummary( "read", "Error: file not found: x" ), ;
             "ui: error result shows the error line" )
   T_Assert( "+ added" $ CCUI_ResultSummary( "edit", ;
             "     1 + added" + Chr(10) + "     2   kept" + Chr(10) ), ;
             "ui: diff content keeps the diff block" )

   // input box: inner width and the framed prompt line
   CCUI_SetColor( .F. )
   T_Equal( CCUI_InputInnerWidth(), 93, "ui: input inner width" )
   T_Equal( hb_UTF8Len( CCUI_InputBoxLine( "hi" ) ), 99, "ui: input box line is 99 columns" )
   T_Assert( "> hi" $ CCUI_InputBoxLine( "hi" ), "ui: input box line has the prompt + text" )
   T_Assert( CCUI_Glyph( "v" ) $ CCUI_InputBoxLine( "hi" ), "ui: input box line has side borders" )

   // version + banner
   T_Equal( CCUI_Version(), "0.7.0", "ui: version string" )
   CCUI_SetColor( .F. )
   T_Assert( "v0.7.0" $ CCUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the version" )
   T_Assert( "CCHarbour" $ CCUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the name" )
   T_Assert( "model: deepseek-v4-flash" $ CCUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the model" )
   T_Assert( "cwd: C:\proj" $ CCUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
             "ui: banner shows the cwd" )
   T_Assert( CCUI_Glyph( "tl" ) $ CCUI_Banner( "m", "c", "u" ), ;
             "ui: banner has the rounded box" )

   // diff lines are space-padded so the background colour fills the row
   T_Equal( hb_UTF8Len( CCUI_DiffPad( "ab" ) ), 110, "ui: diff pad fills short line to 110" )
   T_Equal( CCUI_DiffPad( Replicate( "x", 115 ) ), Replicate( "x", 115 ), ;
            "ui: diff pad leaves a long line unchanged" )

   // CLAUDE.md renamed to CC.md
   T_Assert( "CC.md" $ CCUI_InitPrompt(), "ui: init prompt names CC.md" )
   T_Assert( !( "CLAUDE.md" $ CCUI_InitPrompt() ), "ui: init prompt drops CLAUDE.md" )
   T_Assert( "memory" $ Lower( CCUI_SystemPrompt() ) .OR. ;
             ValType( CCUI_MemoryContext() ) == "C", "ui: memory context available" )
   T_Equal( ValType( CCUI_MemoryContext() ), "C", "ui: memory context returns a string" )
   RETURN NIL

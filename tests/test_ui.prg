STATIC FUNCTION ArrayToStr( aArr )
   LOCAL cOut := "", x
   FOR EACH x IN aArr
      cOut += hb_CStr( x ) + Chr(10)
   NEXT
   RETURN cOut

FUNCTION Test_UI()
   LOCAL hA
   LOCAL aJL, aJR, aJoined, cBan, oQ, cQB
   LOCAL aTips, cTipLn, cBanTip
   LOCAL cTodoBlk

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
   T_Assert( "Run /help to list commands" $ CCUI_Banner( "deepseek-chat", "C:\proj", "x" ), ;
             "ui: banner has help hint" )
   T_Assert( CCUI_Glyph( "tl" ) $ CCUI_Banner( "m", "c", "u" ), ;
             "ui: banner has a rounded top-left corner" )

   // input frame helpers
   CCUI_SetColor( .F. )
   T_Equal( hb_UTF8Len( CCUI_FrameTop() ), 123, "ui: frame top is 123 columns" )
   T_Equal( hb_UTF8Len( CCUI_FrameBottom() ), 123, "ui: frame bottom is 123 columns" )
   T_Assert( CCUI_Glyph( "tl" ) $ CCUI_FrameTop(), "ui: frame top rounded corner" )
   T_Assert( CCUI_Glyph( "bl" ) $ CCUI_FrameBottom(), "ui: frame bottom rounded corner" )
   T_Assert( "/help" $ CCUI_InputHint(), "ui: input hint mentions /help" )

   // system prompt asks for a suggested next prompt
   T_Assert( "Suggested next:" $ CCUI_SystemPrompt(), ;
             "ui: system prompt requests a suggested next line" )

   // system prompt asks the agent to describe non-obvious actions first
   T_Assert( "non-obvious" $ CCUI_SystemPrompt(), ;
             "ui: system prompt asks to describe non-obvious actions" )

   // system prompt states the OS and working directory
   T_Assert( "working directory" $ CCUI_SystemPrompt(), ;
             "ui: system prompt states the working directory" )

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
   T_Equal( CCUI_InputInnerWidth(), 117, "ui: input inner width" )
   T_Equal( hb_UTF8Len( CCUI_InputBoxLine( "hi" ) ), 123, "ui: input box line is 123 columns" )
   T_Assert( "> hi" $ CCUI_InputBoxLine( "hi" ), "ui: input box line has the prompt + text" )
   T_Assert( CCUI_Glyph( "v" ) $ CCUI_InputBoxLine( "hi" ), "ui: input box line has side borders" )

   // version + banner
   T_Equal( CCUI_Version(), "0.8.9", "ui: version string" )
   CCUI_SetColor( .F. )
   T_Assert( "v0.8.9" $ CCUI_Banner( "deepseek-v4-flash", "C:\proj", "x" ), ;
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

   // --- CCUI_ReleaseTagline ---
   T_Equal( CCUI_ReleaseTagline( "first line" + Chr(10) + "second", "FB" ), ;
            "first line", "ui: tagline takes the first line" )
   T_Equal( CCUI_ReleaseTagline( Chr(10) + Chr(10) + "  real  " + Chr(10), "FB" ), ;
            "real", "ui: tagline skips blank lines and trims" )
   T_Equal( CCUI_ReleaseTagline( "", "FB" ), ;
            "FB", "ui: empty text falls back" )
   T_Equal( CCUI_ReleaseTagline( "  " + Chr(13) + Chr(10), "FB" ), ;
            "FB", "ui: whitespace-only text falls back" )

   // --- CCUI_BannerJoin ---
   aJL := { CCUI_Cell( "A", "L", "" ) }
   aJR := { CCUI_Cell( "B", "L", "" ), CCUI_Cell( "C", "L", "" ) }
   aJoined := CCUI_BannerJoin( aJL, aJR, 5, 5 )
   T_Equal( Len( aJoined ), 2, "ui: bannerjoin pads to the taller column" )
   T_Equal( hb_UTF8Len( aJoined[ 1 ] ), 13, ;
            "ui: bannerjoin row width is left + 3 divider + right" )
   T_Equal( hb_UTF8Len( aJoined[ 2 ] ), 13, ;
            "ui: bannerjoin pads the short column with blanks" )
   T_Assert( "A" $ aJoined[ 1 ] .AND. "B" $ aJoined[ 1 ], ;
             "ui: bannerjoin row 1 holds both cells" )

   // --- CCUI_Banner two-panel layout ---
   cBan := CCUI_Banner( "test-model", "c:\proj", "Tester" )
   T_Assert( "Welcome back, Tester!" $ cBan, ;
             "ui: banner greets the user by name" )
   T_Assert( "Tips for getting started" $ cBan, ;
             "ui: banner shows the tips panel header" )
   T_Assert( "What's new" $ cBan, ;
             "ui: banner shows the what's-new header" )
   T_Assert( "model: test-model" $ cBan, ;
             "ui: banner shows the model" )

   // --- CCUI_ClearScreenSeq ---
   T_Equal( CCUI_ClearScreenSeq(), ;
            Chr(27) + "[3J" + Chr(27) + "[2J" + Chr(27) + "[H", ;
            "ui: clear-screen sequence is 3J + 2J + H" )

   // --- CCUI_QuestionBlock ---
   oQ := CCSEL_New( "Choose a colour", { "Red", "Green" } )
   cQB := CCUI_QuestionBlock( oQ )
   T_Assert( "Choose a colour" $ cQB, "ui: question block shows the question" )
   T_Assert( "1. Red" $ cQB, "ui: question block numbers options" )
   T_Assert( "3. Other" $ cQB, "ui: question block lists Other" )
   T_Equal( Len( hb_ATokens( cQB, Chr(10) ) ), 8, ;
            "ui: question block is question + blank + 3 options + blank + hint + trailing line" )
   T_Assert( "Esc to cancel" $ cQB, "ui: question block shows the hint tail" )

   // --- CCUI_Tips / CCUI_TipAt ---
   aTips := CCUI_Tips()
   T_Equal( ValType( aTips ), "A", "ui: tips pool is an array" )
   T_Assert( Len( aTips ) > 0, "ui: tips pool is non-empty" )
   T_Equal( ValType( CCUI_TipAt( 1 ) ), "C", "ui: tip at index is a string" )
   T_Equal( CCUI_TipAt( 1 ), CCUI_TipAt( Len( aTips ) + 1 ), ;
            "ui: tip index wraps past the end" )
   T_Equal( CCUI_TipAt( 0 ), CCUI_TipAt( Len( aTips ) ), ;
            "ui: tip index 0 wraps to the last" )
   T_Assert( CCUI_TipAt( 999 ) $ ArrayToStr( aTips ), ;
             "ui: a large tip index still maps into the pool" )

   // --- CCUI_TipLine ---
   cTipLn := CCUI_TipLine( "hello world" )
   T_Assert( "Tip: hello world" $ cTipLn, "ui: tip line shows Tip: prefix and text" )
   T_Assert( Right( cTipLn, 1 ) == Chr(10), "ui: tip line ends in LF" )

   // --- banner shows a rotating tip, not the old static /init line ---
   cBanTip := CCUI_Banner( "m", "c", "u" )
   T_Assert( "Tip: " $ cBanTip, "ui: banner shows a Tip line" )
   T_Assert( !( "Run /init to create a CC.md file" $ cBanTip ), ;
             "ui: banner no longer shows the static /init line" )

   // --- CCUI_TodoBlock ---
   cTodoBlk := CCUI_TodoBlock( { { "text" => "wash up", "status" => "completed" }, ;
                                 { "text" => "cook", "status" => "in_progress" }, ;
                                 { "text" => "sleep", "status" => "pending" } } )
   T_Assert( "Todos:" $ cTodoBlk, "ui: todo block has a header" )
   T_Assert( "wash up" $ cTodoBlk, "ui: todo block shows completed item text" )
   T_Assert( "cook" $ cTodoBlk, "ui: todo block shows in_progress item text" )
   T_Assert( "sleep" $ cTodoBlk, "ui: todo block shows pending item text" )
   T_Assert( Chr(226) + Chr(136) + Chr(154) $ cTodoBlk, ;
             "ui: todo block has the completed glyph" )
   T_Assert( Chr(226) + Chr(150) + Chr(160) $ cTodoBlk, ;
             "ui: todo block has the in_progress glyph" )
   T_Assert( Chr(226) + Chr(150) + Chr(161) $ cTodoBlk, ;
             "ui: todo block has the pending glyph" )
   T_Assert( Right( cTodoBlk, 1 ) == Chr(10), "ui: todo block ends in LF" )
   RETURN NIL

FUNCTION Test_Prompt()
   LOCAL oP, hC, hR, x

   // --- CCPROMPT_Classify ---
   hC := CCPROMPT_Classify( "fix the bug" )
   T_Equal( hC[ "action" ], "queue", "prompt: plain line -> queue" )
   T_Equal( hC[ "text" ], "fix the bug", "prompt: queue keeps text" )

   hC := CCPROMPT_Classify( "  spaced  " )
   T_Equal( hC[ "text" ], "spaced", "prompt: classify trims" )

   hC := CCPROMPT_Classify( "" )
   T_Equal( hC[ "action" ], "empty", "prompt: blank line -> empty" )
   hC := CCPROMPT_Classify( "    " )
   T_Equal( hC[ "action" ], "empty", "prompt: whitespace -> empty" )

   hC := CCPROMPT_Classify( "/btw also rename it" )
   T_Equal( hC[ "action" ], "btw", "prompt: /btw -> btw" )
   T_Equal( hC[ "text" ], "also rename it", "prompt: btw extracts text" )

   hC := CCPROMPT_Classify( "/BTW shout" )
   T_Equal( hC[ "action" ], "btw", "prompt: /btw is case-insensitive" )

   hC := CCPROMPT_Classify( "/btw" )
   T_Equal( hC[ "action" ], "btw", "prompt: bare /btw -> btw" )
   T_Equal( hC[ "text" ], "", "prompt: bare /btw has empty text" )

   hC := CCPROMPT_Classify( "/btweak something" )
   T_Equal( hC[ "action" ], "queue", "prompt: /btweak is not /btw" )

   // --- CCPROMPT_Region ---
   hR := CCPROMPT_Region( 30, 100 )
   T_Equal( hR[ "active" ], .T., "prompt: 30-row console is active" )
   T_Equal( hR[ "scroll_bottom" ], 27, "prompt: scroll region ends at rows-3" )
   T_Equal( hR[ "box_top" ], 28, "prompt: box starts at rows-2" )

   hR := CCPROMPT_Region( 6, 100 )
   T_Equal( hR[ "active" ], .F., "prompt: a 6-row console falls back" )

   // --- queue: FIFO ---
   oP := CCPROMPT_New( { "rows" => 30, "cols" => 100 } )
   T_Equal( CCPROMPT_Interrupted( oP ), .F., "prompt: new prompt not interrupted" )
   T_Equal( CCPROMPT_Dequeue( oP ), NIL, "prompt: dequeue empty -> NIL" )

   CCPROMPT_Enqueue( oP, "first" )
   CCPROMPT_Enqueue( oP, "second" )
   T_Equal( CCPROMPT_Dequeue( oP ), "first", "prompt: dequeue is FIFO (1)" )
   T_Equal( CCPROMPT_Dequeue( oP ), "second", "prompt: dequeue is FIFO (2)" )
   T_Equal( CCPROMPT_Dequeue( oP ), NIL, "prompt: dequeue drained -> NIL" )

   // --- interrupt state ---
   oP := CCPROMPT_New( { "rows" => 30, "cols" => 100 } )
   oP[ "interrupt" ] := { "kind" => "esc", "text" => "" }
   T_Equal( CCPROMPT_Interrupted( oP ), .T., "prompt: interrupt set -> .T." )

   x := CCPROMPT_New( { "rows" => 30, "cols" => 100 } )
   T_Equal( ValType( x[ "editor" ] ), "H", "prompt: new has an editor state" )
   T_Equal( ValType( x[ "queue" ] ), "A", "prompt: new has a queue array" )

   RETURN NIL

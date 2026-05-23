FUNCTION Test_Select()
   LOCAL oSel

   // --- CCSEL_New ---
   oSel := CCSEL_New( "Pick one", { "Red", "Green" } )
   T_Equal( oSel[ "question" ], "Pick one", "select: stores the question" )
   T_Equal( Len( oSel[ "options" ] ), 3, "select: appends Other to options" )
   T_Equal( oSel[ "options" ][ 3 ], "Other", "select: Other is last" )
   T_Equal( oSel[ "cursor" ], 1, "select: cursor starts at 1" )

   oSel := CCSEL_New( "Q", NIL )
   T_Equal( Len( oSel[ "options" ] ), 1, "select: nil options -> just Other" )

   // --- CCSEL_SetCursor clamps ---
   oSel := CCSEL_New( "Q", { "A", "B" } )   // 3 options with Other
   CCSEL_SetCursor( oSel, 2 )
   T_Equal( oSel[ "cursor" ], 2, "select: set cursor in range" )
   CCSEL_SetCursor( oSel, 99 )
   T_Equal( oSel[ "cursor" ], 3, "select: set cursor clamps to max" )
   CCSEL_SetCursor( oSel, -5 )
   T_Equal( oSel[ "cursor" ], 1, "select: set cursor clamps to min" )

   // --- CCSEL_Move clamps ---
   oSel := CCSEL_New( "Q", { "A", "B" } )
   CCSEL_Move( oSel, 1 )
   T_Equal( oSel[ "cursor" ], 2, "select: move down" )
   CCSEL_Move( oSel, -1 )
   T_Equal( oSel[ "cursor" ], 1, "select: move up" )
   CCSEL_Move( oSel, -1 )
   T_Equal( oSel[ "cursor" ], 3, "select: move up from first wraps to last" )
   CCSEL_Move( oSel, 1 )
   T_Equal( oSel[ "cursor" ], 1, "select: move down from last wraps to first" )

   RETURN NIL

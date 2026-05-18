FUNCTION Test_Input()
   LOCAL oSt, hW

   oSt := DSIN_New( "abc" )
   T_Equal( oSt[ "buf" ], "abc", "input: new keeps initial buf" )
   T_Equal( oSt[ "cursor" ], 3, "input: new cursor at end" )

   oSt := DSIN_New( "" )
   DSIN_Insert( oSt, "x" )
   DSIN_Insert( oSt, "y" )
   T_Equal( oSt[ "buf" ], "xy", "input: insert appends" )
   T_Equal( oSt[ "cursor" ], 2, "input: insert advances cursor" )

   oSt := DSIN_New( "ac" )
   DSIN_Left( oSt )
   DSIN_Insert( oSt, "b" )
   T_Equal( oSt[ "buf" ], "abc", "input: insert mid-buffer" )

   oSt := DSIN_New( "abc" )
   DSIN_Backspace( oSt )
   T_Equal( oSt[ "buf" ], "ab", "input: backspace removes before cursor" )
   oSt := DSIN_New( "abc" )
   DSIN_Home( oSt )
   DSIN_Backspace( oSt )
   T_Equal( oSt[ "buf" ], "abc", "input: backspace at start is a no-op" )

   oSt := DSIN_New( "abc" )
   DSIN_Home( oSt )
   DSIN_Delete( oSt )
   T_Equal( oSt[ "buf" ], "bc", "input: delete removes at cursor" )
   oSt := DSIN_New( "abc" )
   DSIN_Delete( oSt )
   T_Equal( oSt[ "buf" ], "abc", "input: delete at end is a no-op" )

   oSt := DSIN_New( "ab" )
   DSIN_Left( oSt ) ; DSIN_Left( oSt ) ; DSIN_Left( oSt )
   T_Equal( oSt[ "cursor" ], 0, "input: left clamps at 0" )
   DSIN_Right( oSt ) ; DSIN_Right( oSt ) ; DSIN_Right( oSt )
   T_Equal( oSt[ "cursor" ], 2, "input: right clamps at len" )
   DSIN_Home( oSt )
   T_Equal( oSt[ "cursor" ], 0, "input: home" )
   DSIN_End( oSt )
   T_Equal( oSt[ "cursor" ], 2, "input: end" )

   oSt := DSIN_New( "hello" )
   hW := DSIN_Window( oSt, 73 )
   T_Equal( hW[ "text" ], "hello", "input: window fits -> whole buffer" )
   T_Equal( hW[ "col" ], 5, "input: window fits -> cursor col" )

   oSt := DSIN_New( Replicate( "x", 100 ) )
   hW := DSIN_Window( oSt, 73 )
   T_Equal( Len( hW[ "text" ] ), 73, "input: window scrolled width" )
   T_Equal( hW[ "col" ], 73, "input: window scrolled cursor col" )

   T_Equal( DSIN_Utf8Chr( 65 ), "A", "input: utf8chr ascii" )
   T_Equal( DSIN_Utf8Chr( 233 ), Chr(195)+Chr(169), "input: utf8chr 2-byte (e-acute)" )

   RETURN NIL

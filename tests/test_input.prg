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

FUNCTION Test_InputHistory()
   LOCAL cLine, i, nCount

   // Start clean
   DSIN_HistoryClear()
   T_Equal( DSIN_HistoryCount(), 0, "history: count 0 after clear" )

   // Add entries
   DSIN_HistoryAdd( "hello" )
   DSIN_HistoryAdd( "world" )
   DSIN_HistoryAdd( "foo" )
   T_Equal( DSIN_HistoryCount(), 3, "history: count 3 after adds" )

   // Empty lines are ignored
   DSIN_HistoryAdd( "" )
   DSIN_HistoryAdd( "   " )
   T_Equal( DSIN_HistoryCount(), 3, "history: empty lines ignored" )

   // Duplicate of most recent is ignored
   DSIN_HistoryAdd( "foo" )
   T_Equal( DSIN_HistoryCount(), 3, "history: duplicate most-recent ignored" )

   // Navigate: Prev goes from most-recent to oldest
   DSIN_HistoryReset()
   cLine := DSIN_HistoryPrev( "draft" )
   T_Equal( cLine, "foo", "history: prev #1 -> most recent (foo)" )
   cLine := DSIN_HistoryPrev( "draft" )
   T_Equal( cLine, "world", "history: prev #2 -> world" )
   cLine := DSIN_HistoryPrev( "draft" )
   T_Equal( cLine, "hello", "history: prev #3 -> hello" )
   cLine := DSIN_HistoryPrev( "draft" )
   T_Equal( cLine, NIL, "history: prev #4 -> NIL (at oldest)" )

   // Navigate: Next goes forward
   cLine := DSIN_HistoryNext( "draft" )
   T_Equal( cLine, "world", "history: next #1 -> world" )
   cLine := DSIN_HistoryNext( "draft" )
   T_Equal( cLine, "foo", "history: next #2 -> foo" )
   cLine := DSIN_HistoryNext( "draft" )
   T_Equal( cLine, "draft", "history: next #3 -> back to draft" )

   // Draft is saved on first Prev
   DSIN_HistoryReset()
   cLine := DSIN_HistoryPrev( "my draft text" )
   T_Equal( cLine, "foo", "history: prev with draft saved" )
   // Navigate all the way down: from pos=0 (foo), next -> draft
   cLine := DSIN_HistoryNext( "draft" )
   T_Equal( cLine, "my draft text", "history: next from foo -> saved draft" )

   // History is bounded
   DSIN_HistoryClear()
   FOR i := 1 TO 100
      DSIN_HistoryAdd( "line " + LTrim( Str( i ) ) )
   NEXT
   T_Equal( DSIN_HistoryCount(), 50, "history: max 50 entries" )

   // History after bounds: oldest entries dropped
   cLine := DSIN_HistoryPrev( "" )
   T_Equal( cLine, "line 100", "history: bounded -> most recent is line 100" )
   cLine := DSIN_HistoryPrev( "" )
   T_Equal( cLine, "line 99", "history: bounded -> second is line 99" )
   // Go to the oldest
   nCount := DSIN_HistoryCount()
   FOR i := 1 TO nCount - 2
      cLine := DSIN_HistoryPrev( "" )
   NEXT
   T_Equal( cLine, "line 51", "history: bounded -> oldest is line 51 (not 1)" )

   DSIN_HistoryClear()
   RETURN NIL

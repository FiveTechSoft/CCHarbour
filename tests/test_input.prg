FUNCTION Test_Input()
   LOCAL oSt, hW

   oSt := CCIN_New( "abc" )
   T_Equal( oSt[ "buf" ], "abc", "input: new keeps initial buf" )
   T_Equal( oSt[ "cursor" ], 3, "input: new cursor at end" )

   oSt := CCIN_New( "" )
   CCIN_Insert( oSt, "x" )
   CCIN_Insert( oSt, "y" )
   T_Equal( oSt[ "buf" ], "xy", "input: insert appends" )
   T_Equal( oSt[ "cursor" ], 2, "input: insert advances cursor" )

   oSt := CCIN_New( "ac" )
   CCIN_Left( oSt )
   CCIN_Insert( oSt, "b" )
   T_Equal( oSt[ "buf" ], "abc", "input: insert mid-buffer" )

   oSt := CCIN_New( "abc" )
   CCIN_Backspace( oSt )
   T_Equal( oSt[ "buf" ], "ab", "input: backspace removes before cursor" )
   oSt := CCIN_New( "abc" )
   CCIN_Home( oSt )
   CCIN_Backspace( oSt )
   T_Equal( oSt[ "buf" ], "abc", "input: backspace at start is a no-op" )

   oSt := CCIN_New( "abc" )
   CCIN_Home( oSt )
   CCIN_Delete( oSt )
   T_Equal( oSt[ "buf" ], "bc", "input: delete removes at cursor" )
   oSt := CCIN_New( "abc" )
   CCIN_Delete( oSt )
   T_Equal( oSt[ "buf" ], "abc", "input: delete at end is a no-op" )

   oSt := CCIN_New( "ab" )
   CCIN_Left( oSt ) ; CCIN_Left( oSt ) ; CCIN_Left( oSt )
   T_Equal( oSt[ "cursor" ], 0, "input: left clamps at 0" )
   CCIN_Right( oSt ) ; CCIN_Right( oSt ) ; CCIN_Right( oSt )
   T_Equal( oSt[ "cursor" ], 2, "input: right clamps at len" )
   CCIN_Home( oSt )
   T_Equal( oSt[ "cursor" ], 0, "input: home" )
   CCIN_End( oSt )
   T_Equal( oSt[ "cursor" ], 2, "input: end" )

   oSt := CCIN_New( "hello" )
   hW := CCIN_Window( oSt, 93 )
   T_Equal( hW[ "text" ], "hello", "input: window fits -> whole buffer" )
   T_Equal( hW[ "col" ], 5, "input: window fits -> cursor col" )

   oSt := CCIN_New( Replicate( "x", 100 ) )
   hW := CCIN_Window( oSt, 93 )
   T_Equal( Len( hW[ "text" ] ), 93, "input: window scrolled width" )
   T_Equal( hW[ "col" ], 93, "input: window scrolled cursor col" )

   T_Equal( CCIN_Utf8Chr( 65 ), "A", "input: utf8chr ascii" )
   T_Equal( CCIN_Utf8Chr( 233 ), Chr(195)+Chr(169), "input: utf8chr 2-byte (e-acute)" )

   RETURN NIL

FUNCTION Test_InputHistory()
   LOCAL cLine, i, nCount

   // Start clean
   CCIN_HistoryClear()
   T_Equal( CCIN_HistoryCount(), 0, "history: count 0 after clear" )

   // Add entries
   CCIN_HistoryAdd( "hello" )
   CCIN_HistoryAdd( "world" )
   CCIN_HistoryAdd( "foo" )
   T_Equal( CCIN_HistoryCount(), 3, "history: count 3 after adds" )

   // Empty lines are ignored
   CCIN_HistoryAdd( "" )
   CCIN_HistoryAdd( "   " )
   T_Equal( CCIN_HistoryCount(), 3, "history: empty lines ignored" )

   // Duplicate of most recent is ignored
   CCIN_HistoryAdd( "foo" )
   T_Equal( CCIN_HistoryCount(), 3, "history: duplicate most-recent ignored" )

   // Navigate: Prev goes from most-recent to oldest
   CCIN_HistoryReset()
   cLine := CCIN_HistoryPrev( "draft" )
   T_Equal( cLine, "foo", "history: prev #1 -> most recent (foo)" )
   cLine := CCIN_HistoryPrev( "draft" )
   T_Equal( cLine, "world", "history: prev #2 -> world" )
   cLine := CCIN_HistoryPrev( "draft" )
   T_Equal( cLine, "hello", "history: prev #3 -> hello" )
   cLine := CCIN_HistoryPrev( "draft" )
   T_Equal( cLine, NIL, "history: prev #4 -> NIL (at oldest)" )

   // Navigate: Next goes forward
   cLine := CCIN_HistoryNext( "draft" )
   T_Equal( cLine, "world", "history: next #1 -> world" )
   cLine := CCIN_HistoryNext( "draft" )
   T_Equal( cLine, "foo", "history: next #2 -> foo" )
   cLine := CCIN_HistoryNext( "draft" )
   T_Equal( cLine, "draft", "history: next #3 -> back to draft" )

   // Draft is saved on first Prev
   CCIN_HistoryReset()
   cLine := CCIN_HistoryPrev( "my draft text" )
   T_Equal( cLine, "foo", "history: prev with draft saved" )
   // Navigate all the way down: from pos=0 (foo), next -> draft
   cLine := CCIN_HistoryNext( "draft" )
   T_Equal( cLine, "my draft text", "history: next from foo -> saved draft" )

   // History is bounded
   CCIN_HistoryClear()
   FOR i := 1 TO 100
      CCIN_HistoryAdd( "line " + LTrim( Str( i ) ) )
   NEXT
   T_Equal( CCIN_HistoryCount(), 50, "history: max 50 entries" )

   // History after bounds: oldest entries dropped
   cLine := CCIN_HistoryPrev( "" )
   T_Equal( cLine, "line 100", "history: bounded -> most recent is line 100" )
   cLine := CCIN_HistoryPrev( "" )
   T_Equal( cLine, "line 99", "history: bounded -> second is line 99" )
   // Go to the oldest
   nCount := CCIN_HistoryCount()
   FOR i := 1 TO nCount - 2
      cLine := CCIN_HistoryPrev( "" )
   NEXT
   T_Equal( cLine, "line 51", "history: bounded -> oldest is line 51 (not 1)" )

   CCIN_HistoryClear()
   RETURN NIL

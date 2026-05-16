FUNCTION Test_SSE()
   LOCAL oP, aEvents

   // One complete data line -> one text_delta
   aEvents := {}
   oP := DSSSE_New()
   DSSSE_Feed( oP, 'data: {"choices":[{"delta":{"content":"Hi"}}]}' + Chr(10), ;
               {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: one event from one line" )
   T_Equal( aEvents[ 1 ][ "type" ], "text_delta", "sse: event type" )
   T_Equal( aEvents[ 1 ][ "text" ], "Hi", "sse: delta text" )

   // JSON split across two chunks -> still one event
   aEvents := {}
   oP := DSSSE_New()
   DSSSE_Feed( oP, 'data: {"choices":[{"delta":{"con', {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 0, "sse: no event before newline" )
   DSSSE_Feed( oP, 'tent":"X"}}]}' + Chr(10), {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: event after completion" )
   T_Equal( aEvents[ 1 ][ "text" ], "X", "sse: split-json text" )

   // CRLF line endings and keep-alive blank lines are tolerated
   aEvents := {}
   oP := DSSSE_New()
   DSSSE_Feed( oP, Chr(13) + Chr(10) + ;
               'data: {"choices":[{"delta":{"content":"Y"}}]}' + Chr(13) + Chr(10), ;
               {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: crlf + blank line" )
   RETURN NIL

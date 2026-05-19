FUNCTION Test_SSE()
   LOCAL oP, aEvents

   // One complete data line -> one text_delta
   aEvents := {}
   oP := CCSSE_New()
   CCSSE_Feed( oP, 'data: {"choices":[{"delta":{"content":"Hi"}}]}' + Chr(10), ;
               {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: one event from one line" )
   T_Equal( aEvents[ 1 ][ "type" ], "text_delta", "sse: event type" )
   T_Equal( aEvents[ 1 ][ "text" ], "Hi", "sse: delta text" )

   // JSON split across two chunks -> still one event
   aEvents := {}
   oP := CCSSE_New()
   CCSSE_Feed( oP, 'data: {"choices":[{"delta":{"con', {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 0, "sse: no event before newline" )
   CCSSE_Feed( oP, 'tent":"X"}}]}' + Chr(10), {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: event after completion" )
   T_Equal( aEvents[ 1 ][ "text" ], "X", "sse: split-json text" )

   // CRLF line endings and keep-alive blank lines are tolerated
   aEvents := {}
   oP := CCSSE_New()
   CCSSE_Feed( oP, Chr(13) + Chr(10) + ;
               'data: {"choices":[{"delta":{"content":"Y"}}]}' + Chr(13) + Chr(10), ;
               {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: crlf + blank line" )

   // tool_call delta
   aEvents := {}
   oP := CCSSE_New()
   CCSSE_Feed( oP, 'data: {"choices":[{"delta":{"tool_calls":[' + ;
      '{"index":0,"id":"call_1","function":{"name":"read","arguments":"{\"p\""}}]}}]}' + ;
      Chr(10), {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: tool_call event count" )
   T_Equal( aEvents[ 1 ][ "type" ], "tool_call_delta", "sse: tool_call type" )
   T_Equal( aEvents[ 1 ][ "index" ], 0, "sse: tool_call index" )
   T_Equal( aEvents[ 1 ][ "id" ], "call_1", "sse: tool_call id" )
   T_Equal( aEvents[ 1 ][ "name" ], "read", "sse: tool_call name" )
   T_Equal( aEvents[ 1 ][ "arguments" ], '{"p"', "sse: tool_call args fragment" )

   // finish_reason
   aEvents := {}
   oP := CCSSE_New()
   CCSSE_Feed( oP, 'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}' + Chr(10), ;
               {| h | AAdd( aEvents, h ) } )
   T_Equal( aEvents[ 1 ][ "type" ], "finish", "sse: finish event" )
   T_Equal( aEvents[ 1 ][ "finish_reason" ], "stop", "sse: finish reason" )

   // usage
   aEvents := {}
   oP := CCSSE_New()
   CCSSE_Feed( oP, 'data: {"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":5}}' + ;
               Chr(10), {| h | AAdd( aEvents, h ) } )
   T_Equal( aEvents[ 1 ][ "type" ], "usage", "sse: usage event" )
   T_Equal( aEvents[ 1 ][ "usage" ][ "prompt_tokens" ], 3, "sse: usage value" )

   // [DONE]
   aEvents := {}
   oP := CCSSE_New()
   CCSSE_Feed( oP, "data: [DONE]" + Chr(10), {| h | AAdd( aEvents, h ) } )
   T_Equal( aEvents[ 1 ][ "type" ], "done", "sse: done event" )

   // a reasoning_content delta emits a reasoning_delta event
   aEvents := {}
   oP := CCSSE_New()
   CCSSE_Feed( oP, 'data: {"choices":[{"delta":{"reasoning_content":"hmm"}}]}' + Chr(10), ;
               {| h | AAdd( aEvents, h ) } )
   T_Equal( Len( aEvents ), 1, "sse: one event from a reasoning delta" )
   T_Equal( aEvents[ 1 ][ "type" ], "reasoning_delta", "sse: reasoning event type" )
   T_Equal( aEvents[ 1 ][ "text" ], "hmm", "sse: reasoning delta text" )
   RETURN NIL

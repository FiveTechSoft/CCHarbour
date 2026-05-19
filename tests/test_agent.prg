// Stateful mock transport: each CC_ChatCompletion call inside the loop pops the
// next turn. Calls past the end repeat the last turn (lets cap tests loop).
// A turn is { "sse" => <raw SSE bytes>, "http" => { ok,status,curl_code,error } }.
STATIC FUNCTION AgentTransport( aTurns )
   LOCAL nCall := 0
   RETURN {| hReq, bOnChunk | ;
      CC_AgentTestTurn( aTurns, ( nCall := nCall + 1 ), hReq, bOnChunk ) }

STATIC FUNCTION CC_AgentTestTurn( aTurns, nCall, hReq, bOnChunk )
   LOCAL hTurn
   HB_SYMBOL_UNUSED( hReq )
   IF nCall > Len( aTurns )
      nCall := Len( aTurns )
   ENDIF
   hTurn := aTurns[ nCall ]
   IF !Empty( hTurn[ "sse" ] )
      Eval( bOnChunk, hTurn[ "sse" ] )
   ENDIF
   RETURN hTurn[ "http" ]

// SSE for a turn whose assistant reply is plain text then stops.
STATIC FUNCTION SSE_Text( cText )
   RETURN 'data: {"choices":[{"delta":{"content":"' + cText + '"}}]}' + Chr(10) + ;
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}' + Chr(10) + ;
          "data: [DONE]" + Chr(10)

// SSE for a turn that requests one tool call (function cName, arguments "{}").
STATIC FUNCTION SSE_Tool( cId, cName )
   RETURN 'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"' + cId + ;
          '","function":{"name":"' + cName + '","arguments":"{}"}}]}}]}' + Chr(10) + ;
          'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}' + Chr(10) + ;
          "data: [DONE]" + Chr(10)

// SSE for a thinking-model turn: reasoning then tool call.
STATIC FUNCTION SSE_ThinkTool( cReasoning, cId, cName )
   RETURN 'data: {"choices":[{"delta":{"reasoning_content":"' + cReasoning + '"}}]}' + Chr(10) + ;
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"' + cId + ;
          '","function":{"name":"' + cName + '","arguments":"{}"}}]}}]}' + Chr(10) + ;
          'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}' + Chr(10) + ;
          "data: [DONE]" + Chr(10)

STATIC FUNCTION HttpOK()
   RETURN { "ok" => .T., "status" => 200, "curl_code" => 0, "error" => "" }

FUNCTION Test_Agent()
   LOCAL oClient, hRes, bTransport, aInput, hAsstMsg, i

   oClient := CC_Client( { "api_key" => "k", "model" => "deepseek-chat" } )

   // single turn, plain text reply, no tools
   bTransport := AgentTransport( { { "sse" => SSE_Text( "hello" ), "http" => HttpOK() } } )
   hRes := CC_AgentRun( oClient, ;
      { { "role" => "user", "content" => "hi" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hRes[ "success" ], .T., "agent: single-turn success" )
   T_Equal( hRes[ "stop_reason" ], "stop", "agent: single-turn stop reason" )
   T_Equal( hRes[ "iterations" ], 1, "agent: single-turn iteration count" )
   T_Equal( hRes[ "content" ], "hello", "agent: single-turn content" )
   T_Equal( Len( hRes[ "messages" ] ), 2, "agent: single-turn message count" )
   T_Equal( hRes[ "messages" ][ 2 ][ "role" ], "assistant", "agent: assistant appended" )

   // invalid history -> config error, no API call
   hRes := CC_AgentRun( oClient, {}, { "transport" => bTransport }, NIL )
   T_Equal( hRes[ "success" ], .F., "agent: empty history fails" )
   T_Equal( hRes[ "error_type" ], "config", "agent: empty history error_type" )
   T_Equal( hRes[ "stop_reason" ], "error", "agent: empty history stop_reason" )

   // tool turn: turn 1 requests a tool, turn 2 replies with text
   bTransport := AgentTransport( { ;
      { "sse" => SSE_Tool( "c1", "ping" ), "http" => HttpOK() }, ;
      { "sse" => SSE_Text( "done" ),       "http" => HttpOK() } } )
   hRes := CC_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport, ;
        "tool_executor" => {| cName, cArgs | ;
           HB_SYMBOL_UNUSED( cArgs ), "result-of-" + cName } }, NIL )
   T_Equal( hRes[ "success" ], .T., "agent: tool turn success" )
   T_Equal( hRes[ "iterations" ], 2, "agent: tool turn iterations" )
   T_Equal( hRes[ "stop_reason" ], "stop", "agent: tool turn stop reason" )
   T_Equal( hRes[ "content" ], "done", "agent: tool turn final content" )
   // messages: user, assistant(tool_calls), tool, assistant(text)
   T_Equal( Len( hRes[ "messages" ] ), 4, "agent: tool turn message count" )
   T_Equal( hRes[ "messages" ][ 3 ][ "role" ], "tool", "agent: tool message role" )
   T_Equal( hRes[ "messages" ][ 3 ][ "tool_call_id" ], "c1", "agent: tool message id" )
   T_Equal( hRes[ "messages" ][ 3 ][ "content" ], "result-of-ping", ;
            "agent: tool message content" )

   // model requests a tool but no executor supplied -> config error
   bTransport := AgentTransport( { { "sse" => SSE_Tool( "c9", "ping" ), ;
                                     "http" => HttpOK() } } )
   hRes := CC_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hRes[ "success" ], .F., "agent: no executor fails" )
   T_Equal( hRes[ "error_type" ], "config", "agent: no executor error_type" )
   T_Equal( hRes[ "stop_reason" ], "error", "agent: no executor stop_reason" )

   // input array is not mutated by the run
   aInput := { { "role" => "user", "content" => "keep" } }
   bTransport := AgentTransport( { { "sse" => SSE_Text( "ok" ), "http" => HttpOK() } } )
   CC_AgentRun( oClient, aInput, { "transport" => bTransport }, NIL )
   T_Equal( Len( aInput ), 1, "agent: input array not mutated" )

   // usage accumulates across turns
   bTransport := AgentTransport( { ;
      { "sse" => SSE_Tool( "c1", "ping" ), "http" => HttpOK() }, ;
      { "sse" => 'data: {"choices":[{"delta":{"content":"x"}}]}' + Chr(10) + ;
                 'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}' + Chr(10) + ;
                 'data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":7}}' + ;
                 Chr(10) + "data: [DONE]" + Chr(10), ;
        "http" => HttpOK() } } )
   hRes := CC_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport, ;
        "tool_executor" => {| cName, cArgs | ;
           HB_SYMBOL_UNUSED( cName ), HB_SYMBOL_UNUSED( cArgs ), "r" } }, NIL )
   T_Equal( hRes[ "usage" ][ "prompt_tokens" ], 5, "agent: usage accumulated" )

   // iteration cap: the model keeps requesting tools; cap stops the loop
   bTransport := AgentTransport( { { "sse" => SSE_Tool( "c1", "ping" ), ;
                                     "http" => HttpOK() } } )
   hRes := CC_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport, "max_iterations" => 3, ;
        "tool_executor" => {| cName, cArgs | ;
           HB_SYMBOL_UNUSED( cName ), HB_SYMBOL_UNUSED( cArgs ), "r" } }, NIL )
   T_Equal( hRes[ "success" ], .T., "agent: cap success flag" )
   T_Equal( hRes[ "stop_reason" ], "max_iterations", "agent: cap stop reason" )
   T_Equal( hRes[ "iterations" ], 3, "agent: cap iteration count" )

   // API failure mid-loop surfaces in hResult
   bTransport := AgentTransport( { { "sse" => "", ;
      "http" => { "ok" => .F., "status" => 0, "curl_code" => 7, ;
                  "error" => "no connect" } } } )
   hRes := CC_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hRes[ "success" ], .F., "agent: api failure success flag" )
   T_Equal( hRes[ "error_type" ], "network", "agent: api failure error_type" )
   T_Equal( hRes[ "stop_reason" ], "error", "agent: api failure stop reason" )

   // reasoning_content round-trip: thinking model emits reasoning before tool call;
   // the assistant message carrying tool_calls must include reasoning_content
   bTransport := AgentTransport( { ;
      { "sse" => SSE_ThinkTool( "think", "c1", "noop" ), "http" => HttpOK() }, ;
      { "sse" => SSE_Text( "done" ),                     "http" => HttpOK() } } )
   hRes := CC_AgentRun( oClient, ;
      { { "role" => "user", "content" => "go" } }, ;
      { "transport" => bTransport, ;
        "tool_executor" => {| cName, cArgs | ;
           HB_SYMBOL_UNUSED( cName ), HB_SYMBOL_UNUSED( cArgs ), "ok" } }, NIL )
   T_Equal( hRes[ "success" ], .T., "agent: thinking tool turn success" )
   // find the assistant message that has tool_calls
   hAsstMsg := NIL
   FOR i := 1 TO Len( hRes[ "messages" ] )
      IF hb_HHasKey( hRes[ "messages" ][ i ], "tool_calls" )
         hAsstMsg := hRes[ "messages" ][ i ]
         EXIT
      ENDIF
   NEXT
   T_Assert( hAsstMsg != NIL, "agent: found tool_calls assistant message" )
   T_Assert( hb_HHasKey( hAsstMsg, "reasoning_content" ), ;
             "agent: tool_calls message has reasoning_content" )
   T_Equal( hAsstMsg[ "reasoning_content" ], "think", ;
            "agent: reasoning_content value round-trips" )
   RETURN NIL

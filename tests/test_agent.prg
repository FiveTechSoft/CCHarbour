// Stateful mock transport: each DS_ChatCompletion call inside the loop pops the
// next turn. Calls past the end repeat the last turn (lets cap tests loop).
// A turn is { "sse" => <raw SSE bytes>, "http" => { ok,status,curl_code,error } }.
STATIC FUNCTION AgentTransport( aTurns )
   LOCAL nCall := 0
   RETURN {| hReq, bOnChunk | ;
      DS_AgentTestTurn( aTurns, ( nCall := nCall + 1 ), hReq, bOnChunk ) }

STATIC FUNCTION DS_AgentTestTurn( aTurns, nCall, hReq, bOnChunk )
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

STATIC FUNCTION HttpOK()
   RETURN { "ok" => .T., "status" => 200, "curl_code" => 0, "error" => "" }

FUNCTION Test_Agent()
   LOCAL oClient, hRes, bTransport, aInput

   oClient := DS_Client( { "api_key" => "k", "model" => "deepseek-chat" } )

   // single turn, plain text reply, no tools
   bTransport := AgentTransport( { { "sse" => SSE_Text( "hello" ), "http" => HttpOK() } } )
   hRes := DS_AgentRun( oClient, ;
      { { "role" => "user", "content" => "hi" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hRes[ "success" ], .T., "agent: single-turn success" )
   T_Equal( hRes[ "stop_reason" ], "stop", "agent: single-turn stop reason" )
   T_Equal( hRes[ "iterations" ], 1, "agent: single-turn iteration count" )
   T_Equal( hRes[ "content" ], "hello", "agent: single-turn content" )
   T_Equal( Len( hRes[ "messages" ] ), 2, "agent: single-turn message count" )
   T_Equal( hRes[ "messages" ][ 2 ][ "role" ], "assistant", "agent: assistant appended" )

   // invalid history -> config error, no API call
   hRes := DS_AgentRun( oClient, {}, { "transport" => bTransport }, NIL )
   T_Equal( hRes[ "success" ], .F., "agent: empty history fails" )
   T_Equal( hRes[ "error_type" ], "config", "agent: empty history error_type" )
   T_Equal( hRes[ "stop_reason" ], "error", "agent: empty history stop_reason" )
   RETURN NIL

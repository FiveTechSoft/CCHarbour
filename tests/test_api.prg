FUNCTION Test_Api()
   LOCAL oClient, hResult, aEvents, bTransport

   oClient := CC_Client( { "api_key" => "k", "model" => "deepseek-chat" } )
   T_Equal( ValType( oClient ), "H", "api: client is hash" )

   // transport that streams a text reply, a usage line and [DONE]
   bTransport := {| hR, bOnChunk | ;
      HB_SYMBOL_UNUSED( hR ), ;
      Eval( bOnChunk, 'data: {"choices":[{"delta":{"content":"Hel"}}]}' + Chr(10) ), ;
      Eval( bOnChunk, 'data: {"choices":[{"delta":{"content":"lo"}}]}' + Chr(10) ), ;
      Eval( bOnChunk, 'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}' + Chr(10) ), ;
      Eval( bOnChunk, 'data: {"choices":[],"usage":{"prompt_tokens":2,"completion_tokens":4}}' + Chr(10) ), ;
      Eval( bOnChunk, "data: [DONE]" + Chr(10) ), ;
      { "ok" => .T., "status" => 200, "curl_code" => 0, "error" => "" } }

   aEvents := {}
   hResult := CC_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "hi" } }, ;
      { "transport" => bTransport }, {| h | AAdd( aEvents, h ) } )

   T_Equal( hResult[ "success" ], .T., "api: success" )
   T_Equal( hResult[ "content" ], "Hello", "api: assembled content" )
   T_Equal( hResult[ "finish_reason" ], "stop", "api: finish reason" )
   T_Equal( hResult[ "usage" ][ "completion_tokens" ], 4, "api: usage assembled" )
   T_Assert( Len( aEvents ) >= 2, "api: events forwarded to caller" )

   // tool_call assembly across fragments
   bTransport := {| hR, bOnChunk | ;
      HB_SYMBOL_UNUSED( hR ), ;
      Eval( bOnChunk, 'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"read","arguments":"{\"p\":"}}]}}]}' + Chr(10) ), ;
      Eval( bOnChunk, 'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"a\"}"}}]}}]}' + Chr(10) ), ;
      Eval( bOnChunk, "data: [DONE]" + Chr(10) ), ;
      { "ok" => .T., "status" => 200, "curl_code" => 0, "error" => "" } }
   hResult := CC_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "x" } }, ;
      { "transport" => bTransport }, {| h | HB_SYMBOL_UNUSED( h ) } )
   T_Equal( Len( hResult[ "tool_calls" ] ), 1, "api: one tool call" )
   T_Equal( hResult[ "tool_calls" ][ 1 ][ "id" ], "c1", "api: tool call id" )
   T_Equal( hResult[ "tool_calls" ][ 1 ][ "name" ], "read", "api: tool call name" )
   T_Equal( hResult[ "tool_calls" ][ 1 ][ "arguments" ], '{"p":"a"}', "api: tool args joined" )

   // missing API key -> config error, no transport call
   oClient := CC_Client( {=>} )
   hResult := CC_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "x" } }, {=>}, NIL )
   T_Equal( hResult[ "success" ], .F., "api: missing key fails" )
   T_Equal( hResult[ "error_type" ], "config", "api: missing key error_type" )

   // transport network error surfaces in hResult
   bTransport := {| hR, bOnChunk | ;
      HB_SYMBOL_UNUSED( hR ), HB_SYMBOL_UNUSED( bOnChunk ), ;
      { "ok" => .F., "status" => 0, "curl_code" => 7, "error" => "no connect" } }
   oClient := CC_Client( { "api_key" => "k", "model" => "deepseek-chat" } )
   hResult := CC_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "x" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hResult[ "success" ], .F., "api: network failure" )
   T_Equal( hResult[ "error_type" ], "network", "api: network error_type" )

   // HTTP 429 -> api error, retryable
   bTransport := {| hR, bOnChunk | ;
      HB_SYMBOL_UNUSED( hR ), ;
      Eval( bOnChunk, '{"error":{"message":"slow down","code":"rate_limit"}}' ), ;
      { "ok" => .T., "status" => 429, "curl_code" => 0, "error" => "" } }
   hResult := CC_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "x" } }, ;
      { "transport" => bTransport }, NIL )
   T_Equal( hResult[ "error_type" ], "api", "api: 429 error_type" )
   T_Equal( hResult[ "retryable" ], .T., "api: 429 retryable" )
   RETURN NIL

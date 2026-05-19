// Creates a client. hOpts: { api_key, base_url, model, timeout, config_path }.
// The returned hash holds only immutable data -> safe to share read-only
// across pool threads.
FUNCTION CC_Client( hOpts )
   IF ValType( hOpts ) != "H"
      hOpts := {=>}
   ENDIF
   RETURN { "opts" => hOpts, ;
            "model" => iif( hb_HHasKey( hOpts, "model" ), hOpts[ "model" ], NIL ), ;
            "timeout" => iif( hb_HHasKey( hOpts, "timeout" ), hOpts[ "timeout" ], 120 ) }

// Runs one streaming chat completion.
// hParams: { model, temperature, max_tokens, tools, tool_choice, transport }.
// bOnEvent (optional): codeblock invoked per parsed SSE event.
// Returns hResult: { success, content, tool_calls, finish_reason, usage,
//                    error_type, status, curl_code, retryable, message }
FUNCTION CC_ChatCompletion( oClient, aMessages, hParams, bOnEvent )
   LOCAL hCfg, hResult, hState, oParser, hReq, hHttp, cBody, cModel, bEmit

   IF ValType( hParams ) != "H"
      hParams := {=>}
   ENDIF

   hResult := { "success" => .F., "content" => "", "tool_calls" => {}, ;
                "finish_reason" => NIL, "usage" => NIL, "error_type" => NIL, ;
                "status" => NIL, "curl_code" => NIL, "retryable" => .F., ;
                "message" => NIL, "reasoning_content" => "" }

   // 1. resolve key/url (fail fast, no HTTP)
   hCfg := CCCFG_Resolve( oClient[ "opts" ] )
   IF !hCfg[ "ok" ]
      hResult[ "error_type" ] := hCfg[ "error_type" ]
      hResult[ "message" ]    := hCfg[ "message" ]
      CC_Emit( bOnEvent, { "type" => "error", "error_type" => hCfg[ "error_type" ], ;
                           "message" => hCfg[ "message" ] } )
      RETURN hResult
   ENDIF

   cModel := iif( hb_HHasKey( hParams, "model" ), hParams[ "model" ], oClient[ "model" ] )
   IF Empty( cModel )
      hResult[ "error_type" ] := "config"
      hResult[ "message" ]    := "No model id: set it on the client or in hParams"
      CC_Emit( bOnEvent, { "type" => "error", "error_type" => "config", ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   // 2. build request body
   cBody := hb_jsonEncode( CC_BuildBody( cModel, aMessages, hParams ) )
   hReq  := { "url" => hCfg[ "base_url" ] + "/chat/completions", ;
              "headers" => { "Content-Type: application/json", ;
                             "Accept: text/event-stream", ;
                             "Authorization: Bearer " + hCfg[ "api_key" ] }, ;
              "body" => cBody, ;
              "timeout" => oClient[ "timeout" ] }

   // 3. stream: feed every chunk to a fresh parser; assemble into hState
   hState  := { "content" => "", "tools" => {}, "finish" => NIL, ;
                "usage" => NIL, "got_done" => .F., "raw" => "", "reasoning" => "" }
   oParser := CCSSE_New()
   bEmit   := {| hEv | CC_OnEvent( hEv, hState, bOnEvent ) }

   hHttp := CCHTTP_Post( hReq, ;
      {| cChunk | CC_FeedChunk( cChunk, hState, oParser, bEmit ) }, ;
      iif( hb_HHasKey( hParams, "transport" ), hParams[ "transport" ], NIL ) )

   // 4. classify the outcome
   hResult[ "status" ]    := hHttp[ "status" ]
   hResult[ "curl_code" ] := hHttp[ "curl_code" ]

   IF !hHttp[ "ok" ]
      IF hHttp[ "curl_code" ] == -2
         hResult[ "error_type" ] := "cancelled"
         hResult[ "message" ]    := "cancelled"
      ELSE
         hResult[ "error_type" ] := "network"
         hResult[ "message" ]    := hHttp[ "error" ]
      ENDIF
      CC_Emit( bOnEvent, { "type" => "error", "error_type" => hResult[ "error_type" ], ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   IF hHttp[ "status" ] < 200 .OR. hHttp[ "status" ] >= 300
      hResult[ "error_type" ] := "api"
      hResult[ "retryable" ]  := ( hHttp[ "status" ] == 429 .OR. hHttp[ "status" ] >= 500 )
      hResult[ "message" ]    := CC_ApiErrorMessage( hState[ "raw" ], hHttp[ "status" ] )
      CC_Emit( bOnEvent, { "type" => "error", "error_type" => "api", ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   IF !hState[ "got_done" ]
      hResult[ "error_type" ] := "stream_incomplete"
      hResult[ "message" ]    := "Stream closed before [DONE]"
      CC_Emit( bOnEvent, { "type" => "error", "error_type" => "stream_incomplete", ;
                           "message" => hResult[ "message" ] } )
      RETURN hResult
   ENDIF

   hResult[ "success" ]           := .T.
   hResult[ "content" ]           := hState[ "content" ]
   hResult[ "tool_calls" ]        := hState[ "tools" ]
   hResult[ "finish_reason" ]     := hState[ "finish" ]
   hResult[ "usage" ]             := hState[ "usage" ]
   hResult[ "reasoning_content" ] := hState[ "reasoning" ]
   RETURN hResult

STATIC FUNCTION CC_BuildBody( cModel, aMessages, hParams )
   LOCAL hBody := { "model" => cModel, "messages" => aMessages, ;
                    "stream" => .T., ;
                    "stream_options" => { "include_usage" => .T. } }
   IF hb_HHasKey( hParams, "temperature" )
      hBody[ "temperature" ] := hParams[ "temperature" ]
   ENDIF
   IF hb_HHasKey( hParams, "max_tokens" )
      hBody[ "max_tokens" ] := hParams[ "max_tokens" ]
   ENDIF
   IF hb_HHasKey( hParams, "tools" )
      hBody[ "tools" ] := hParams[ "tools" ]
   ENDIF
   IF hb_HHasKey( hParams, "tool_choice" )
      hBody[ "tool_choice" ] := hParams[ "tool_choice" ]
   ENDIF
   RETURN hBody

// Records raw bytes (for error bodies) and feeds the SSE parser.
STATIC FUNCTION CC_FeedChunk( cChunk, hState, oParser, bEmit )
   hState[ "raw" ] += cChunk
   CCSSE_Feed( oParser, cChunk, bEmit )
   RETURN NIL

// Folds one parsed SSE event into hState and forwards it to the caller.
STATIC FUNCTION CC_OnEvent( hEv, hState, bOnEvent )
   DO CASE
   CASE hEv[ "type" ] == "text_delta"
      hState[ "content" ] += hEv[ "text" ]
   CASE hEv[ "type" ] == "reasoning_delta"
      hState[ "reasoning" ] += hEv[ "text" ]
   CASE hEv[ "type" ] == "tool_call_delta"
      CC_AccTool( hState[ "tools" ], hEv )
   CASE hEv[ "type" ] == "finish"
      hState[ "finish" ] := hEv[ "finish_reason" ]
   CASE hEv[ "type" ] == "usage"
      hState[ "usage" ] := hEv[ "usage" ]
   CASE hEv[ "type" ] == "done"
      hState[ "got_done" ] := .T.
   ENDCASE
   CC_Emit( bOnEvent, hEv )
   RETURN NIL

// Merges a tool_call_delta into the accumulator array, keyed by "index".
STATIC FUNCTION CC_AccTool( aTools, hEv )
   LOCAL hTool, nFound := 0, i
   FOR i := 1 TO Len( aTools )
      IF aTools[ i ][ "index" ] == hEv[ "index" ]
         nFound := i
         EXIT
      ENDIF
   NEXT
   IF nFound == 0
      hTool := { "index" => hEv[ "index" ], "id" => "", "name" => "", "arguments" => "" }
      AAdd( aTools, hTool )
   ELSE
      hTool := aTools[ nFound ]
   ENDIF
   IF hEv[ "id" ] != NIL
      hTool[ "id" ] := hEv[ "id" ]
   ENDIF
   IF hEv[ "name" ] != NIL
      hTool[ "name" ] := hEv[ "name" ]
   ENDIF
   IF hEv[ "arguments" ] != NIL
      hTool[ "arguments" ] += hEv[ "arguments" ]
   ENDIF
   RETURN NIL

STATIC FUNCTION CC_ApiErrorMessage( cRaw, nStatus )
   LOCAL xJson
   xJson := hb_jsonDecode( cRaw )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "error" ) .AND. ;
      ValType( xJson[ "error" ] ) == "H" .AND. ;
      hb_HHasKey( xJson[ "error" ], "message" )
      RETURN xJson[ "error" ][ "message" ]
   ENDIF
   RETURN "HTTP " + LTrim( Str( nStatus ) )

FUNCTION CC_Emit( bOnEvent, hEv )
   IF bOnEvent != NIL
      Eval( bOnEvent, hEv )
   ENDIF
   RETURN NIL

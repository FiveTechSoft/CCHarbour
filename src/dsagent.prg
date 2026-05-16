// Runs the agent loop: drive a multi-turn DeepSeek conversation until the model
// stops or the iteration cap is reached. Tool execution is added in Task 3,
// API-failure handling in Task 4.
// hOpts: { model, max_iterations, tools, tool_executor, temperature,
//          max_tokens, transport }
// Returns hResult: { success, messages, content, stop_reason, iterations,
//                    usage, error_type, message }
FUNCTION DS_AgentRun( oClient, aMessages, hOpts, bOnEvent )
   LOCAL hResult, aMsgs, nIter := 0, nMax, hUsage, hChat, hChatParams, tc, cRes

   IF ValType( hOpts ) != "H"
      hOpts := {=>}
   ENDIF

   hResult := { "success" => .F., "messages" => {}, "content" => "", ;
                "stop_reason" => NIL, "iterations" => 0, "usage" => {=>}, ;
                "error_type" => NIL, "message" => NIL }

   // validate the input history
   IF ValType( aMessages ) != "A" .OR. Len( aMessages ) == 0
      hResult[ "error_type" ]  := "config"
      hResult[ "message" ]     := "aMessages must be a non-empty array"
      hResult[ "stop_reason" ] := "error"
      RETURN hResult
   ENDIF

   // deep copy so the caller's array is never mutated
   aMsgs  := hb_jsonDecode( hb_jsonEncode( aMessages ) )
   nMax   := iif( hb_HHasKey( hOpts, "max_iterations" ) .AND. ;
                  ValType( hOpts[ "max_iterations" ] ) == "N" .AND. ;
                  hOpts[ "max_iterations" ] > 0, hOpts[ "max_iterations" ], 25 )
   hUsage := {=>}

   DO WHILE nIter < nMax
      nIter++
      DS_AgentEmit( bOnEvent, { "type" => "iteration_start", "n" => nIter } )

      hChatParams := {=>}
      IF hb_HHasKey( hOpts, "transport" )
         hChatParams[ "transport" ] := hOpts[ "transport" ]
      ENDIF
      IF hb_HHasKey( hOpts, "model" )
         hChatParams[ "model" ] := hOpts[ "model" ]
      ENDIF
      IF hb_HHasKey( hOpts, "tools" )
         hChatParams[ "tools" ] := hOpts[ "tools" ]
      ENDIF
      IF hb_HHasKey( hOpts, "temperature" )
         hChatParams[ "temperature" ] := hOpts[ "temperature" ]
      ENDIF
      IF hb_HHasKey( hOpts, "max_tokens" )
         hChatParams[ "max_tokens" ] := hOpts[ "max_tokens" ]
      ENDIF

      hChat := DS_ChatCompletion( oClient, aMsgs, hChatParams, bOnEvent )

      DS_AgentAddUsage( hUsage, hChat[ "usage" ] )
      AAdd( aMsgs, DS_AgentAsstMsg( hChat ) )

      IF Empty( hChat[ "tool_calls" ] )
         hResult[ "stop_reason" ] := "stop"
         EXIT
      ENDIF

      // model wants tools but caller supplied no executor -> fast-fail
      IF !hb_HHasKey( hOpts, "tool_executor" ) .OR. hOpts[ "tool_executor" ] == NIL
         hResult[ "messages" ]    := aMsgs
         hResult[ "iterations" ]  := nIter
         hResult[ "usage" ]       := hUsage
         hResult[ "error_type" ]  := "config"
         hResult[ "message" ]     := "model requested tool but no tool_executor provided"
         hResult[ "stop_reason" ] := "error"
         RETURN hResult
      ENDIF

      // execute every tool call this turn, append each result as a tool message
      FOR EACH tc IN hChat[ "tool_calls" ]
         DS_AgentEmit( bOnEvent, { "type" => "tool_call", "id" => tc[ "id" ], ;
                                   "name" => tc[ "name" ], ;
                                   "arguments" => tc[ "arguments" ] } )
         cRes := Eval( hOpts[ "tool_executor" ], tc[ "name" ], tc[ "arguments" ] )
         DS_AgentEmit( bOnEvent, { "type" => "tool_result", "id" => tc[ "id" ], ;
                                   "content" => cRes } )
         AAdd( aMsgs, { "role" => "tool", "tool_call_id" => tc[ "id" ], ;
                        "content" => cRes } )
      NEXT
   ENDDO

   IF hResult[ "stop_reason" ] == NIL
      hResult[ "stop_reason" ] := "max_iterations"
   ENDIF

   hResult[ "success" ]    := .T.
   hResult[ "messages" ]   := aMsgs
   hResult[ "iterations" ] := nIter
   hResult[ "usage" ]      := hUsage
   hResult[ "content" ]    := DS_AgentLastText( aMsgs )
   RETURN hResult

// Builds an OpenAI-format assistant message from a DS_ChatCompletion result.
STATIC FUNCTION DS_AgentAsstMsg( hChat )
   LOCAL hMsg, aTC := {}, tc
   hMsg := { "role" => "assistant", "content" => hChat[ "content" ] }
   IF !Empty( hChat[ "tool_calls" ] )
      FOR EACH tc IN hChat[ "tool_calls" ]
         AAdd( aTC, { "id" => tc[ "id" ], "type" => "function", ;
                      "function" => { "name" => tc[ "name" ], ;
                                      "arguments" => tc[ "arguments" ] } } )
      NEXT
      hMsg[ "tool_calls" ] := aTC
   ENDIF
   RETURN hMsg

// Returns the content of the last assistant message, or "" if there is none.
STATIC FUNCTION DS_AgentLastText( aMsgs )
   LOCAL i
   FOR i := Len( aMsgs ) TO 1 STEP -1
      IF aMsgs[ i ][ "role" ] == "assistant"
         RETURN aMsgs[ i ][ "content" ]
      ENDIF
   NEXT
   RETURN ""

// Adds the numeric keys of xUsage into hUsage (running totals across turns).
STATIC FUNCTION DS_AgentAddUsage( hUsage, xUsage )
   LOCAL cKey
   IF ValType( xUsage ) != "H"
      RETURN NIL
   ENDIF
   FOR EACH cKey IN hb_HKeys( xUsage )
      IF ValType( xUsage[ cKey ] ) == "N"
         hUsage[ cKey ] := iif( hb_HHasKey( hUsage, cKey ), hUsage[ cKey ], 0 ) + ;
                           xUsage[ cKey ]
      ENDIF
   NEXT
   RETURN NIL

STATIC FUNCTION DS_AgentEmit( bOnEvent, hEv )
   IF bOnEvent != NIL
      Eval( bOnEvent, hEv )
   ENDIF
   RETURN NIL

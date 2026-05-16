#include "fileio.ch"

// Program entry point. Optional cModel CLI argument overrides the settings model.
FUNCTION Main( cModel )
   LOCAL hSet, hCfg, oClient, oReg, bGate, oErr
   hSet := DSSettings_Load()
   IF Empty( cModel )
      cModel := hb_GetEnv( "DEEPSEEK_MODEL" )
   ENDIF
   IF Empty( cModel )
      cModel := hSet[ "model" ]
   ENDIF
   hCfg := DSCFG_Resolve( {=>} )
   IF !hCfg[ "ok" ]
      OutStd( "Error: no API key. Set DEEPSEEK_API_KEY." + Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   ENDIF
   oClient := DS_Client( { "model" => cModel, "base_url" => hSet[ "base_url" ] } )
   oReg    := DSTools_Registry()
   bGate   := DSPerm_Gate( DSTools_Executor( oReg ), hSet[ "permissions" ], ;
                           {| cN, cA | DSREPL_AskPerm( cN, cA ) } )
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      DSREPL_Run( oClient, oReg, cModel, bGate, hSet[ "max_iterations" ] )
   RECOVER USING oErr
      OutStd( Chr(10) + "Fatal: " + ;
              iif( ValType( oErr ) == "O", hb_CStr( oErr:Description ), "exception" ) + ;
              Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   END SEQUENCE
   RETURN NIL

// The interactive loop: read a line, dispatch, run the agent, repeat.
FUNCTION DSREPL_Run( oClient, oReg, cModel, bGate, nMaxIter )
   LOCAL aMsgs, bRender, cLine, hAction, aTurn, hRes
   aMsgs   := { { "role" => "system", "content" => DSUI_SystemPrompt() } }
   bRender := {| hEv | OutStd( DSUI_RenderEvent( hEv ) ) }
   OutStd( "CCHarbour - model: " + cModel + ". /help for commands." + Chr(10) )
   DO WHILE .T.
      OutStd( Chr(10) + "> " )
      cLine := DSREPL_ReadLine()
      IF cLine == NIL
         EXIT
      ENDIF
      hAction := DSUI_ParseCommand( cLine )
      DO CASE
      CASE hAction[ "type" ] == "empty"
         // nothing
      CASE hAction[ "type" ] == "exit"
         EXIT
      CASE hAction[ "type" ] == "help"
         OutStd( DSUI_Help() + Chr(10) )
      CASE hAction[ "type" ] == "clear"
         aMsgs := { { "role" => "system", "content" => DSUI_SystemPrompt() } }
         OutStd( "[conversation reset]" + Chr(10) )
      CASE hAction[ "type" ] == "message"
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => hAction[ "text" ] } )
         hRes := DS_AgentRun( oClient, aTurn, ;
            { "model" => cModel, ;
              "tools" => DSTools_Schemas( oReg ), ;
              "tool_executor" => bGate, ;
              "max_iterations" => nMaxIter }, ;
            bRender )
         OutStd( Chr(10) )
         IF hRes[ "success" ]
            aMsgs := hRes[ "messages" ]
            IF hRes[ "stop_reason" ] == "max_iterations"
               OutStd( "[stopped: iteration cap]" + Chr(10) )
            ENDIF
            OutStd( DSREPL_UsageLine( hRes[ "usage" ] ) + Chr(10) )
         ELSE
            OutStd( "!! error: " + hb_CStr( hRes[ "error_type" ] ) + ": " + ;
                    hb_CStr( hRes[ "message" ] ) + Chr(10) )
         ENDIF
      ENDCASE
   ENDDO
   OutStd( Chr(10) + "bye" + Chr(10) )
   RETURN NIL

// Permission prompt for a tool in "ask" mode. Returns the typed answer
// ("y"/"n"/"a"); the gate normalises it. Never throws.
STATIC FUNCTION DSREPL_AskPerm( cName, cArgsJson )
   LOCAL cLine := "n", oErr
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      OutStd( Chr(10) + "Tool '" + hb_CStr( cName ) + "' wants to run: " + ;
              DSUI_Summarize( hb_CStr( cArgsJson ), 120 ) + Chr(10) + ;
              "Allow? [y/n/a] " )
      cLine := DSREPL_ReadLine()
      IF cLine == NIL
         cLine := "n"
      ENDIF
   RECOVER USING oErr
      HB_SYMBOL_UNUSED( oErr )
      cLine := "n"
   END SEQUENCE
   RETURN cLine

// Reads one line from stdin. Returns the line, or NIL at end of input.
STATIC FUNCTION DSREPL_ReadLine()
   LOCAL cLine := "", cCh := Space(1), nRead, hIn := hb_GetStdIn()
   DO WHILE .T.
      nRead := FRead( hIn, @cCh, 1 )
      IF nRead == 0
         RETURN iif( Empty( cLine ), NIL, cLine )
      ENDIF
      IF cCh == Chr(10)
         EXIT
      ENDIF
      IF cCh != Chr(13)
         cLine += cCh
      ENDIF
   ENDDO
   // strip a leading UTF-8 BOM (piped input on Windows may prepend one)
   IF hb_BLeft( cLine, 3 ) == Chr(239) + Chr(187) + Chr(191)
      cLine := SubStr( cLine, 4 )
   ENDIF
   RETURN cLine

// Formats the per-turn token usage line from a DS_AgentRun usage hash.
STATIC FUNCTION DSREPL_UsageLine( xUsage )
   LOCAL nP := 0, nC := 0
   IF ValType( xUsage ) == "H"
      IF hb_HHasKey( xUsage, "prompt_tokens" ) .AND. ;
         ValType( xUsage[ "prompt_tokens" ] ) == "N"
         nP := xUsage[ "prompt_tokens" ]
      ENDIF
      IF hb_HHasKey( xUsage, "completion_tokens" ) .AND. ;
         ValType( xUsage[ "completion_tokens" ] ) == "N"
         nC := xUsage[ "completion_tokens" ]
      ENDIF
   ENDIF
   RETURN "[tokens: prompt " + LTrim( Str( nP ) ) + ", completion " + ;
          LTrim( Str( nC ) ) + "]"

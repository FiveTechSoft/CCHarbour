#include "fileio.ch"
#include "hbdyn.ch"

// Tracks a pending LF to swallow after a CR, so CRLF counts as one line break.
STATIC s_lSkipLF := .F.

// Program entry point. Optional cModel CLI argument overrides the settings model.
FUNCTION Main( cModel )
   LOCAL hSet, hCfg, oClient, oReg, bGate, oErr, lVT
   lVT := DSREPL_InitConsole()
   hSet := DSSettings_Load()
   // colour only when the console accepted virtual-terminal mode AND the
   // settings do not switch it off -- avoids ANSI codes on a plain console
   DSUI_SetColor( lVT .AND. hSet[ "color" ] == .T. )
   IF Empty( cModel )
      cModel := hb_GetEnv( "DEEPSEEK_MODEL" )
   ENDIF
   IF Empty( cModel )
      cModel := hSet[ "model" ]
   ENDIF
   hCfg := DSCFG_Resolve( {=>} )
   IF !hCfg[ "ok" ]
      DSREPL_Out( "Error: no API key. Set DEEPSEEK_API_KEY." + Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   ENDIF
   oClient := DS_Client( { "model" => cModel, "base_url" => hSet[ "base_url" ] } )
   oReg    := DSTools_Registry( { ;
      "tavily" => DSCFG_ResolveKey( "TAVILY_API_KEY", "tavily_api_key", hSet ), ;
      "github" => DSCFG_ResolveKey( "GITHUB_TOKEN", "github_token", hSet ) } )
   bGate   := DSPerm_Gate( DSTools_Executor( oReg ), hSet[ "permissions" ], ;
                           {| cN, cA | DSREPL_AskPerm( cN, cA ) } )
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      DSREPL_Run( oClient, oReg, cModel, bGate, hSet[ "max_iterations" ] )
   RECOVER USING oErr
      DSREPL_Out( Chr(10) + "Fatal: " + ;
              iif( ValType( oErr ) == "O", hb_CStr( oErr:Description ), "exception" ) + ;
              Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   END SEQUENCE
   RETURN NIL

// The interactive loop: read a line, dispatch, run the agent, repeat.
FUNCTION DSREPL_Run( oClient, oReg, cModel, bGate, nMaxIter )
   LOCAL aMsgs, cLine, hAction, aTurn, hRes, cMsg, oMd, cSuggest
   aMsgs    := { { "role" => "system", "content" => DSUI_SystemPrompt() } }
   cSuggest := ""
   DSREPL_Out( DSUI_Banner( cModel, hb_cwd(), hb_GetEnv( "USERNAME" ) ) )
   IF !Empty( DSUI_ProjectContext() )
      DSREPL_Out( DSUI_Color( "[loaded CLAUDE.md project instructions]", ;
                              "90" ) + Chr(10) )
   ENDIF
   DO WHILE .T.
      IF !Empty( cSuggest )
         DSCON_PrefillInput( cSuggest )
         cSuggest := ""
      ENDIF
      IF DSUI_ColorOn()
         // top border, blank prompt line, bottom border, hint; then move the
         // cursor back up onto the prompt line so the frame is fully drawn
         // before the user types.
         DSREPL_Out( Chr(10) + DSUI_FrameTop() + Chr(10) + ;
                     Chr(10) + ;
                     DSUI_FrameBottom() + Chr(10) + ;
                     DSUI_InputHint() + ;
                     DSUI_VT( "2A" ) + DSUI_VT( "1G" ) + ;
                     DSUI_Color( "> ", "1;36" ) )
      ELSE
         DSREPL_Out( Chr(10) + DSUI_FrameTop() + Chr(10) + "> " )
      ENDIF
      cLine := DSREPL_ReadLine()
      IF cLine == NIL
         EXIT
      ENDIF
      IF DSUI_ColorOn()
         DSREPL_Out( Chr(10) )
      ELSE
         DSREPL_Out( DSUI_FrameBottom() + Chr(10) )
      ENDIF
      hAction := DSUI_ParseCommand( cLine )
      DO CASE
      CASE hAction[ "type" ] == "empty"
         // nothing
      CASE hAction[ "type" ] == "exit"
         EXIT
      CASE hAction[ "type" ] == "help"
         DSREPL_Out( DSUI_Help() + Chr(10) )
      CASE hAction[ "type" ] == "clear"
         aMsgs := { { "role" => "system", "content" => DSUI_SystemPrompt() } }
         DSREPL_Out( DSUI_Color( "[conversation reset]", "90" ) + Chr(10) )
      CASE hAction[ "type" ] == "model"
         IF Empty( hAction[ "text" ] )
            DSREPL_Out( DSUI_Color( "model: " + cModel, "90" ) + Chr(10) )
         ELSE
            cModel := hAction[ "text" ]
            DSREPL_Out( DSUI_Color( "[model -> " + cModel + "]", "90" ) + Chr(10) )
         ENDIF
      CASE hAction[ "type" ] == "message" .OR. hAction[ "type" ] == "init"
         cMsg := iif( hAction[ "type" ] == "init", ;
                      DSUI_InitPrompt(), hAction[ "text" ] )
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => cMsg } )
         oMd := DSMD_New()
         hRes := DS_AgentRun( oClient, aTurn, ;
            { "model" => cModel, ;
              "tools" => DSTools_Schemas( oReg ), ;
              "tool_executor" => bGate, ;
              "max_iterations" => nMaxIter }, ;
            {| hEv | DSREPL_RenderEv( hEv, oMd ) } )
         DSREPL_Out( DSMD_Flush( oMd ) )
         DSREPL_Out( Chr(10) )
         cSuggest := DSMD_Suggestion( oMd )
         IF hRes[ "success" ]
            aMsgs := hRes[ "messages" ]
            IF hRes[ "stop_reason" ] == "max_iterations"
               DSREPL_Out( DSUI_Color( "[stopped: iteration cap]", "33" ) + Chr(10) )
            ENDIF
            DSREPL_Out( DSUI_Color( DSREPL_UsageLine( hRes[ "usage" ] ), "90" ) + Chr(10) )
         ELSE
            DSREPL_Out( DSUI_Color( "!! error: " + hb_CStr( hRes[ "error_type" ] ) + ": " + ;
                    hb_CStr( hRes[ "message" ] ), "31" ) + Chr(10) )
         ENDIF
      ENDCASE
   ENDDO
   DSREPL_Out( Chr(10) + DSUI_Color( "bye", "90" ) + Chr(10) )
   RETURN NIL

// Renders one agent event. A text_delta is fed to the per-turn markdown
// renderer oMd; every other event goes through DSUI_RenderEvent unchanged.
STATIC FUNCTION DSREPL_RenderEv( hEv, oMd )
   IF ValType( hEv ) == "H" .AND. hb_HHasKey( hEv, "type" ) .AND. ;
      hEv[ "type" ] == "text_delta"
      DSREPL_Out( DSMD_Feed( oMd, hb_CStr( hEv[ "text" ] ) ) )
   ELSE
      DSREPL_Out( DSUI_RenderEvent( hEv ) )
   ENDIF
   RETURN NIL

// Writes raw bytes straight to the OS stdout handle, bypassing the GT layer
// so UTF-8 output is not re-encoded. The console code page is set to UTF-8
// by DSREPL_InitConsole, so these bytes render correctly. Line feeds are
// normalised to CRLF: bypassing the GT also loses its LF -> CRLF translation,
// and a Windows console needs the CR to return to column 0.
STATIC FUNCTION DSREPL_Out( cText )
   // Test the length, not Empty(): Empty() is true for a whitespace-only
   // string, so a streamed delta of just "\n" would be dropped and the line
   // break lost.
   IF ValType( cText ) == "C" .AND. Len( cText ) > 0
      cText := StrTran( cText, Chr(13), "" )
      cText := StrTran( cText, Chr(10), Chr(13) + Chr(10) )
      FWrite( hb_GetStdOut(), cText )
   ENDIF
   RETURN NIL

// Sets the Windows console to the UTF-8 code page (65001) so the model's
// UTF-8 output renders, and enables virtual-terminal mode so ANSI colours
// work. Returns .T. when VT mode was accepted (so the caller can decide
// whether to colour output). Wrapped so a missing console API never aborts.
STATIC FUNCTION DSREPL_InitConsole()
   LOCAL oErr, hOut, lVT := .F.
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      hb_dynCall( { "SetConsoleOutputCP", "kernel32.dll", ;
         hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_BOOL ) }, 65001 )
      hb_dynCall( { "SetConsoleCP", "kernel32.dll", ;
         hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_BOOL ) }, 65001 )
      hOut := hb_dynCall( { "GetStdHandle", "kernel32.dll", ;
         hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_VOID_PTR ) }, -11 )
      // mode 7 = PROCESSED_OUTPUT | WRAP_AT_EOL | VIRTUAL_TERMINAL_PROCESSING
      lVT := hb_dynCall( { "SetConsoleMode", "kernel32.dll", ;
         hb_bitOr( HB_DYN_CALLCONV_STDCALL, HB_DYN_CTYPE_BOOL ), ;
         { HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_LONG_UNSIGNED } }, hOut, 7 )
   RECOVER USING oErr
      HB_SYMBOL_UNUSED( oErr )
      // console API unavailable -> leave the console as is
   END SEQUENCE
   RETURN ( lVT == .T. )

// Permission prompt for a tool in "ask" mode. Returns the typed answer
// ("y"/"n"/"a"); the gate normalises it. Never throws.
STATIC FUNCTION DSREPL_AskPerm( cName, cArgsJson )
   LOCAL cLine := "n", oErr
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      DSREPL_Out( Chr(10) + DSUI_Color( "Tool '" + hb_CStr( cName ) + ;
              "' wants to run: " + DSUI_Summarize( hb_CStr( cArgsJson ), 120 ) + ;
              Chr(10) + "Allow? [y/n/a] ", "33" ) )
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
// Terminates on LF, CR, or CRLF. The console runs in its default cooked mode
// (gtnul does not touch it), so it echoes the typed line and applies editing
// itself -- this function must NOT echo, or the input would appear twice.
STATIC FUNCTION DSREPL_ReadLine()
   LOCAL cLine := "", cCh := Space(1), nRead, hIn := hb_GetStdIn()
   DO WHILE .T.
      nRead := FRead( hIn, @cCh, 1 )
      IF nRead == 0
         RETURN iif( Empty( cLine ), NIL, cLine )
      ENDIF
      IF s_lSkipLF
         s_lSkipLF := .F.
         IF cCh == Chr(10)
            LOOP   // swallow the LF that follows a CR (CRLF)
         ENDIF
      ENDIF
      DO CASE
      CASE cCh == Chr(10)
         EXIT
      CASE cCh == Chr(13)
         s_lSkipLF := .T.
         EXIT
      CASE ( cCh == Chr(8) .OR. cCh == Chr(127) ) .AND. !Empty( cLine )
         cLine := hb_BLeft( cLine, hb_BLen( cLine ) - 1 )
      CASE cCh >= " "
         cLine += cCh
      ENDCASE
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

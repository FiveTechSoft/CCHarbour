#include "fileio.ch"
#include "hbdyn.ch"

// Tracks a pending LF to swallow after a CR, so CRLF counts as one line break.
STATIC s_lSkipLF := .F.

// Accumulated usage across the entire session (prompt_tokens, completion_tokens, ...).
STATIC s_hSessionUsage := {=>}

// Braille-pattern spinner frames for the animated "thinking" indicator.
STATIC s_aSpinnerFrames := { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

// Program entry point. Optional cModel CLI argument overrides the settings model.
FUNCTION Main( cModel )
   LOCAL hSet, hCfg, oClient, oReg, bGate, oErr, lVT
   lVT := CCREPL_InitConsole()
   hSet := CCSETTINGS_Load()
   // colour only when the console accepted virtual-terminal mode AND the
   // settings do not switch it off -- avoids ANSI codes on a plain console
   CCUI_SetColor( lVT .AND. hSet[ "color" ] == .T. )
   IF Empty( cModel )
      cModel := hb_GetEnv( "DEEPSEEK_MODEL" )
   ENDIF
   IF Empty( cModel )
      cModel := hSet[ "model" ]
   ENDIF
   hCfg := CCCFG_Resolve( {=>} )
   IF !hCfg[ "ok" ]
      CCREPL_Out( "Error: no API key. Set DEEPSEEK_API_KEY." + Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   ENDIF
   oClient := CC_Client( { "model" => cModel, "base_url" => hSet[ "base_url" ] } )
   oReg    := CCTOOLS_Registry( { ;
      "github"    => CCCFG_ResolveKey( "GITHUB_TOKEN", "github_token", hSet ), ;
      "co_author" => hb_HGetDef( hSet, "co_author", "" ) } )
   bGate   := CCPERM_Gate( CCTOOLS_Executor( oReg ), hSet[ "permissions" ], ;
                           {| cN, cA | CCREPL_AskPerm( cN, cA ) } )
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      CCREPL_Run( oClient, oReg, cModel, bGate, hSet[ "max_iterations" ] )
   RECOVER USING oErr
      CCCON_RawMode( .F. )   // restore the console if a crash happened mid-editor
      CCREPL_Out( Chr(10) + "Fatal: " + ;
              iif( ValType( oErr ) == "O", hb_CStr( oErr:Description ), "exception" ) + ;
              Chr(10) )
      ErrorLevel( 1 )
      RETURN NIL
   END SEQUENCE
   RETURN NIL

// The interactive loop: read a line, dispatch, run the agent, repeat.
FUNCTION CCREPL_Run( oClient, oReg, cModel, bGate, nMaxIter )
   LOCAL aMsgs, cLine, hAction, aTurn, hRes, cMsg, cSuggest, lCooked, hLoaded, hTurn
   aMsgs    := { { "role" => "system", "content" => CCUI_SystemPrompt() } }
   cSuggest := ""
   CCREPL_Out( CCUI_Banner( cModel, hb_cwd(), hb_GetEnv( "USERNAME" ) ) )
   IF !Empty( CCUI_ProjectContext() )
      CCREPL_Out( CCUI_Color( "[loaded CC.md project instructions]", ;
                              "90" ) + Chr(10) )
   ENDIF
   DO WHILE .T.
      lCooked := .F.
      IF CCCON_HasConsole()
         cLine := CCIN_ReadLine( cSuggest )
         IF ValType( cLine ) == "H"   // the no-console sentinel
            lCooked := .T.
            CCREPL_Out( Chr(10) + CCUI_FrameTop() + Chr(10) + "> " )
            cLine := CCREPL_ReadLine()
         ENDIF
      ELSE
         // piped / non-interactive input: the cooked reader, no box editor
         lCooked := .T.
         CCREPL_Out( Chr(10) + CCUI_FrameTop() + Chr(10) + "> " )
         cLine := CCREPL_ReadLine()
      ENDIF
      cSuggest := ""
      IF cLine == NIL
         EXIT
      ENDIF
      IF lCooked
         CCREPL_Out( CCUI_FrameBottom() + Chr(10) )
      ENDIF
      hAction := CCUI_ParseCommand( cLine )
      DO CASE
      CASE hAction[ "type" ] == "empty"
         // nothing
      CASE hAction[ "type" ] == "exit"
         EXIT
      CASE hAction[ "type" ] == "help"
         CCREPL_Out( CCUI_Help() + Chr(10) )
      CASE hAction[ "type" ] == "clear"
         aMsgs := { { "role" => "system", "content" => CCUI_SystemPrompt() } }
         s_hSessionUsage := {=>}
         CCREPL_Out( CCUI_Color( "[conversation reset]", "90" ) + Chr(10) )
      CASE hAction[ "type" ] == "model"
         IF Empty( hAction[ "text" ] )
            CCREPL_Out( CCUI_Color( "model: " + cModel, "90" ) + Chr(10) )
         ELSE
            cModel := hAction[ "text" ]
            CCREPL_Out( CCUI_Color( "[model -> " + cModel + "]", "90" ) + Chr(10) )
         ENDIF
      CASE hAction[ "type" ] == "cost"
         CCREPL_Out( CCUI_CostReport( s_hSessionUsage ) )
      CASE hAction[ "type" ] == "save"
         CCREPL_SaveSession( aMsgs, cModel, s_hSessionUsage, hAction[ "text" ] )
      CASE hAction[ "type" ] == "load"
         hLoaded := CCREPL_LoadSession( hAction[ "text" ] )
         IF ValType( hLoaded ) == "H"
            aMsgs    := hLoaded[ "messages" ]
            cModel   := hb_HGetDef( hLoaded, "model", cModel )
            s_hSessionUsage := iif( hb_HHasKey( hLoaded, "usage" ) .AND. ;
                                    ValType( hLoaded[ "usage" ] ) == "H", ;
                                    hLoaded[ "usage" ], {=>} )
         ENDIF
      CASE hAction[ "type" ] == "message" .OR. hAction[ "type" ] == "init"
         cMsg := iif( hAction[ "type" ] == "init", ;
                      CCUI_InitPrompt(), hAction[ "text" ] )
         aTurn := AClone( aMsgs )
         AAdd( aTurn, { "role" => "user", "content" => cMsg } )
         hTurn := CCREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, aTurn )
         hRes := hTurn[ "result" ]
         // when the turn stopped on the iteration cap, offer to resume it
         // with 25 more iterations -- repeatably, until done or declined.
         DO WHILE hRes[ "success" ] .AND. ;
                  hRes[ "stop_reason" ] == "max_iterations" .AND. ;
                  CCREPL_AskExtend()
            hTurn := CCREPL_RunTurn( oClient, oReg, cModel, bGate, 25, hRes[ "messages" ] )
            hRes  := hTurn[ "result" ]
         ENDDO
         cSuggest := CCMD_Suggestion( hTurn[ "render" ][ "md" ] )
         IF hRes[ "success" ]
            aMsgs := hRes[ "messages" ]
            IF hRes[ "stop_reason" ] == "max_iterations"
               CCREPL_Out( CCUI_Color( "[stopped: iteration cap]", "33" ) + Chr(10) )
            ELSEIF hRes[ "stop_reason" ] == "paused"
               CCREPL_Out( CCUI_Color( "[paused by user]", "33" ) + Chr(10) )
            ENDIF
         ELSE
            IF hb_CStr( hRes[ "error_type" ] ) == "cancelled"
               CCREPL_Out( CCUI_Color( "[cancelled]", "33" ) + Chr(10) )
            ELSE
               CCREPL_Out( CCUI_Color( "!! error: " + hb_CStr( hRes[ "error_type" ] ) + ": " + ;
                       hb_CStr( hRes[ "message" ] ), "31" ) + Chr(10) )
            ENDIF
         ENDIF
      ENDCASE
   ENDDO
   RETURN NIL

// Runs one agent turn: calls CC_AgentRun, renders output, shows token bar,
// accumulates usage, and returns { result, render }.
STATIC FUNCTION CCREPL_RunTurn( oClient, oReg, cModel, bGate, nMaxIter, aMessages )
   LOCAL hRes, oRender
   oRender := CCREPL_RenderNew()
   hRes := CC_AgentRun( oClient, aMessages, ;
      { "model" => cModel, ;
        "tools" => CCTOOLS_Schemas( oReg ), ;
        "tool_executor" => bGate, ;
        "max_iterations" => nMaxIter }, ;
      {| hEv | CCREPL_RenderEv( hEv, oRender ) } )
   CCREPL_Out( CCMD_Flush( oRender[ "md" ] ) )
   IF hRes[ "success" ]
      CCREPL_ShowTokenBar( hRes[ "usage" ] )
      CCREPL_AccumUsage( hRes[ "usage" ] )
   ELSE
      CCREPL_Out( Chr(10) )
   ENDIF
   RETURN { "result" => hRes, "render" => oRender }

// Merges a usage hash (from one agent turn) into the session total.
STATIC FUNCTION CCREPL_AccumUsage( hTurnUsage )
   LOCAL cKey
   IF ValType( hTurnUsage ) != "H"
      RETURN NIL
   ENDIF
   FOR EACH cKey IN hb_HKeys( hTurnUsage )
      IF ValType( hTurnUsage[ cKey ] ) == "N"
         s_hSessionUsage[ cKey ] := ;
            hb_HGetDef( s_hSessionUsage, cKey, 0 ) + hTurnUsage[ cKey ]
      ENDIF
   NEXT
   RETURN NIL

// Saves the current session to a JSON file.
// cArg is the user-supplied name (empty = auto-name with timestamp).
STATIC FUNCTION CCREPL_SaveSession( aMsgs, cModel, hUsage, cArg )
   LOCAL cName, cPath, hPack, cJson, hSaved
   LOCAL aSessions

   IF !CCUI_EnsureSessionDir()
      CCREPL_Out( CCUI_Color( "!! error: cannot create sessions directory", "31" ) + Chr(10) )
      RETURN NIL
   ENDIF

   // determine the session name
   IF Empty( cArg )
      // auto-name: session_YYYY-MM-DD_HHMMSS
      cName := "session_" + StrTran( StrTran( DToS( Date() ), "/", "-" ), ".", "-" ) + ;
               "_" + StrTran( SubStr( Time(), 1, 8 ), ":", "" )
   ELSE
      cName := AllTrim( cArg )
      // sanitise the name: keep only safe chars
      cName := CCREPL_SanitiseName( cName )
      IF Empty( cName )
         CCREPL_Out( CCUI_Color( "!! error: invalid session name", "31" ) + Chr(10) )
         RETURN NIL
      ENDIF
   ENDIF

   cPath := CCUI_SessionPath( cName )
   hPack := { "model" => cModel, ;
              "saved_at" => DToS( Date() ) + "T" + Time(), ;
              "usage" => hUsage, ;
              "messages" => aMsgs }
   cJson := hb_jsonEncode( hPack, .T. )  // .T. = pretty-print

   IF !hb_MemoWrit( cPath, cJson )
      CCREPL_Out( CCUI_Color( "!! error: failed to write " + cPath, "31" ) + Chr(10) )
      RETURN NIL
   ENDIF

   CCREPL_Out( CCUI_Color( "[saved: " + cName + "]", "90" ) + Chr(10) )
   RETURN NIL

// Loads a session from a JSON file.
// cArg is the session name (empty = list available sessions).
// Returns a hash { messages, model, usage } on success, or NIL on error.
STATIC FUNCTION CCREPL_LoadSession( cArg )
   LOCAL aSessions, hPack, cJson, cPath, cName

   IF Empty( cArg )
      // list available sessions
      aSessions := CCUI_SessionList()
      CCREPL_Out( CCUI_SessionListOutput( aSessions ) )
      RETURN NIL
   ENDIF

   cName := CCREPL_SanitiseName( AllTrim( cArg ) )
   IF Empty( cName )
      // maybe it's "autosave" with special chars removed - try as-is
      cName := AllTrim( cArg )
   ENDIF

   cPath := CCUI_SessionPath( cName )
   IF !hb_FileExists( cPath )
      CCREPL_Out( CCUI_Color( "!! error: session '" + cName + "' not found", "31" ) + Chr(10) )
      RETURN NIL
   ENDIF

   cJson := hb_MemoRead( cPath )
   hPack := hb_jsonDecode( cJson )
   IF ValType( hPack ) != "H" .OR. !hb_HHasKey( hPack, "messages" )
      CCREPL_Out( CCUI_Color( "!! error: invalid session file", "31" ) + Chr(10) )
      RETURN NIL
   ENDIF

   CCREPL_Out( CCUI_Color( "[loaded: " + cName + "]", "90" ) + Chr(10) )
   CCREPL_Out( CCUI_Color( "  model: " + hb_CStr( hb_HGetDef( hPack, "model", "" ) ), "90" ) + Chr(10) )
   CCREPL_Out( CCUI_Color( "  messages: " + LTrim( Str( Len( hPack[ "messages" ] ) ) ), "90" ) + Chr(10) )

   RETURN hPack

// Sanitises a session name: keeps only alphanumeric, underscores, hyphens.
STATIC FUNCTION CCREPL_SanitiseName( cName )
   LOCAL cOut := "", i, cCh
   FOR i := 1 TO Len( cName )
      cCh := SubStr( cName, i, 1 )
      IF cCh >= "A" .AND. cCh <= "Z" .OR. ;
         cCh >= "a" .AND. cCh <= "z" .OR. ;
         cCh >= "0" .AND. cCh <= "9" .OR. ;
         cCh == "_" .OR. cCh == "-"
         cOut += cCh
      ENDIF
   NEXT
   RETURN cOut

// Creates a per-turn render state: the markdown renderer, an id->tool-name
// map (to label tool results), the assistant-bullet run flag, spinner state,
// reasoning-character counter, and last-seen usage hash.
STATIC FUNCTION CCREPL_RenderNew()
   RETURN { "md" => CCMD_New(), "tools" => {=>}, "inText" => .F., ;
            "spinner" => .F., "spinnerFrame" => 1, ;
            "reasoningChars" => 0, "lastUsage" => {=>}, ;
            "lastFrameTime" => 0 }

// Renders one agent event into the terminal, using the render state oRender.
STATIC FUNCTION CCREPL_RenderEv( hEv, oRender )
   LOCAL cType, cId, cSpinner, nPrompt, nComp, cMsg, cThinking, cTokenPart
   IF ValType( hEv ) != "H" .OR. !hb_HHasKey( hEv, "type" )
      RETURN NIL
   ENDIF
   cType := hEv[ "type" ]
   DO CASE

   CASE cType == "iteration_start"
      // start the spinner on the first frame
      oRender[ "spinner" ] := .T.
      oRender[ "spinnerFrame" ] := 1
      oRender[ "reasoningChars" ] := 0
      CCREPL_SpinnerShow( oRender, "" )

   CASE cType == "reasoning_delta"
      // advance the spinner, count chars, show "Thinking..." with estimated token count
      oRender[ "reasoningChars" ] += Len( hb_CStr( hEv[ "text" ] ) )
      CCREPL_SpinnerShow( oRender, "Thinking..." )

   CASE cType == "text_delta"
      IF oRender[ "spinner" ]
         CCREPL_SpinnerClear()
         oRender[ "spinner" ] := .F.
      ENDIF
      IF !oRender[ "inText" ]
         // blank line before the assistant bullet, so an answer that follows
         // a tool result is separated from it -- matches Claude Code spacing
         CCREPL_Out( Chr(10) + CCUI_Color( Chr(226)+Chr(143)+Chr(186), ;
                                           CCUI_Pal( "accent" ) ) + "  " )
         oRender[ "inText" ] := .T.
      ENDIF
      CCREPL_Out( CCMD_Feed( oRender[ "md" ], hb_CStr( hEv[ "text" ] ) ) )

   CASE cType == "usage"
      // store the usage hash for display after the turn
      oRender[ "lastUsage" ] := hEv[ "usage" ]

   CASE cType == "tool_call"
      IF oRender[ "spinner" ]
         CCREPL_SpinnerClear()
         oRender[ "spinner" ] := .F.
      ENDIF
      CCREPL_Out( CCMD_Flush( oRender[ "md" ] ) )
      oRender[ "inText" ] := .F.
      IF hb_HHasKey( hEv, "id" )
         oRender[ "tools" ][ hb_CStr( hEv[ "id" ] ) ] := hb_CStr( hEv[ "name" ] )
      ENDIF
      CCREPL_Out( CCUI_ToolCallLine( hEv[ "name" ], hEv[ "arguments" ] ) )

   CASE cType == "tool_result"
      CCREPL_Out( CCMD_Flush( oRender[ "md" ] ) )
      oRender[ "inText" ] := .F.
      cId := hb_CStr( hb_HGetDef( hEv, "id", "" ) )
      CCREPL_Out( CCUI_ResultSummary( ;
         hb_HGetDef( oRender[ "tools" ], cId, "" ), ;
         hb_CStr( hEv[ "content" ] ) ) )

   OTHERWISE
      IF oRender[ "spinner" ]
         CCREPL_SpinnerClear()
         oRender[ "spinner" ] := .F.
      ENDIF
      CCREPL_Out( CCMD_Flush( oRender[ "md" ] ) )
      oRender[ "inText" ] := .F.
      CCREPL_Out( CCUI_RenderEvent( hEv ) )

   ENDCASE
   RETURN NIL

// ── Spinner helpers (animated reasoning indicator) ──────────────────────

// Draws the spinner line at the current cursor position. cExtra is an
// optional label like "Thinking...". The frame advances at most every
// 100ms so the spinner turns at a relaxed pace regardless of token speed.
STATIC FUNCTION CCREPL_SpinnerShow( oRender, cExtra )
   LOCAL cFrame, cMsg, nEst, nNow
   // throttle: only advance the frame if at least 100ms have passed
   nNow := hb_MilliSeconds()
   IF nNow - oRender[ "lastFrameTime" ] >= 100
      oRender[ "spinnerFrame" ] := iif( oRender[ "spinnerFrame" ] < ;
                                        Len( s_aSpinnerFrames ), ;
                                        oRender[ "spinnerFrame" ] + 1, 1 )
      oRender[ "lastFrameTime" ] := nNow
   ENDIF
   cFrame := s_aSpinnerFrames[ oRender[ "spinnerFrame" ] ]
   cMsg := cFrame + " " + iif( Empty( cExtra ), "", cExtra + " " )
   // show estimated token count from reasoning chars (rough: ~4 chars/token)
   IF oRender[ "reasoningChars" ] > 0
      nEst := Int( oRender[ "reasoningChars" ] / 4 )
      cMsg += CCUI_Color( "[" + LTrim( Str( nEst ) ) + " tok]", "90" )
   ENDIF
   // overwrite the current line with the spinner
   CCREPL_Out( CCUI_VT( "1G" ) + CCUI_VT( "K" ) + ;
               CCUI_Color( cMsg, CCUI_Pal( "dim" ) ) )
   RETURN NIL

// Clears the spinner line (erases it so normal output can follow).
STATIC FUNCTION CCREPL_SpinnerClear()
   CCREPL_Out( CCUI_VT( "1G" ) + CCUI_VT( "K" ) )
   RETURN NIL

// After a turn completes, optionally prints a compact token-usage bar when
// usage data was collected from the stream.
STATIC FUNCTION CCREPL_ShowTokenBar( hUsage )
   LOCAL nPrompt, nComp, nTotal, cBar
   IF ValType( hUsage ) != "H" .OR. Len( hb_HKeys( hUsage ) ) == 0
      RETURN NIL
   ENDIF
   nPrompt := hb_HGetDef( hUsage, "prompt_tokens", 0 )
   nComp   := hb_HGetDef( hUsage, "completion_tokens", 0 )
   nTotal  := nPrompt + nComp
   IF nTotal == 0
      RETURN NIL
   ENDIF
   cBar := CCUI_Color( "  ", "90" ) + ;
           CCUI_Color( Chr(226)+Chr(150)+Chr(146) + " ", "90" ) + ;   // ┒
           CCUI_Color( "in: ", "90" ) + ;
           CCUI_Color( LTrim( Str( nPrompt ) ), "1;36" ) + ;
           CCUI_Color( "  out: ", "90" ) + ;
           CCUI_Color( LTrim( Str( nComp ) ), "1;36" ) + ;
           CCUI_Color( "  total: ", "90" ) + ;
           CCUI_Color( LTrim( Str( nTotal ) ), "1" )
   CCREPL_Out( CCUI_VT( "1G" ) + CCUI_VT( "K" ) + cBar + Chr(10) )
   RETURN NIL

// Asks whether to continue a capped turn with 25 more iterations.
// Returns .T. for a "y" answer; end-of-input (piped stdin) -> .F. (no hang).
STATIC FUNCTION CCREPL_AskExtend()
   LOCAL cLine
   CCREPL_Out( Chr(10) + CCUI_Color( ;
      "[iteration cap reached -- continue with 25 more? y/n] ", ;
      CCUI_Pal( "warn" ) ) )
   cLine := CCREPL_ReadLine()
   IF cLine == NIL
      RETURN .F.
   ENDIF
   RETURN Lower( Left( AllTrim( cLine ), 1 ) ) == "y"

// Writes raw bytes straight to the OS stdout handle, bypassing the GT layer
// so UTF-8 output is not re-encoded. The console code page is set to UTF-8
// by CCREPL_InitConsole, so these bytes render correctly. Line feeds are
// normalised to CRLF: bypassing the GT also loses its LF -> CRLF translation,
// and a Windows console needs the CR to return to column 0.
FUNCTION CCREPL_Out( cText )
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
STATIC FUNCTION CCREPL_InitConsole()
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
STATIC FUNCTION CCREPL_AskPerm( cName, cArgsJson )
   LOCAL cLine := "n", oErr
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      CCREPL_Out( Chr(10) + CCUI_Color( "Tool '" + hb_CStr( cName ) + ;
              "' wants to run: " + CCUI_Summarize( hb_CStr( cArgsJson ), 120 ) + ;
              Chr(10) + "Allow? [y/n/a] ", "33" ) )
      cLine := CCREPL_ReadLine()
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
FUNCTION CCREPL_ReadLine()
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

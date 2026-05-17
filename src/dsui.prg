// Whether DSUI_Color emits ANSI colour codes (off unless the REPL turns it on).
STATIC s_lColor := .F.

// Classifies a line of REPL input. Returns:
//   { "type" => "exit"|"clear"|"help"|"message"|"empty", "text" => <trimmed> }
FUNCTION DSUI_ParseCommand( cLine )
   LOCAL cTrim := AllTrim( hb_CStr( cLine ) )
   DO CASE
   CASE Empty( cTrim )
      RETURN { "type" => "empty", "text" => "" }
   CASE Lower( cTrim ) == "/exit" .OR. Lower( cTrim ) == "/quit"
      RETURN { "type" => "exit", "text" => cTrim }
   CASE Lower( cTrim ) == "/clear"
      RETURN { "type" => "clear", "text" => cTrim }
   CASE Lower( cTrim ) == "/help"
      RETURN { "type" => "help", "text" => cTrim }
   ENDCASE
   RETURN { "type" => "message", "text" => cTrim }

// Returns the first line of cText, truncated to nMax characters, with a
// "[<N> chars]" annotation when anything was dropped. nMax defaults to 80.
FUNCTION DSUI_Summarize( cText, nMax )
   LOCAL cFirst, nNL, nLen
   cText := hb_CStr( cText )
   nLen  := Len( cText )
   IF ValType( nMax ) != "N" .OR. nMax <= 0
      nMax := 80
   ENDIF
   nNL := At( Chr(10), cText )
   cFirst := iif( nNL > 0, Left( cText, nNL - 1 ), cText )
   cFirst := StrTran( cFirst, Chr(13), "" )
   IF Len( cFirst ) > nMax
      cFirst := Left( cFirst, nMax )
   ENDIF
   IF Len( cFirst ) < nLen
      RETURN cFirst + " [" + LTrim( Str( nLen ) ) + " chars]"
   ENDIF
   RETURN cFirst

// Maps one agent/SSE event hash to display text ("" when the event is ignored).
FUNCTION DSUI_RenderEvent( hEv )
   LOCAL cType
   IF ValType( hEv ) != "H" .OR. !hb_HHasKey( hEv, "type" )
      RETURN ""
   ENDIF
   cType := hEv[ "type" ]
   DO CASE
   CASE cType == "text_delta"
      RETURN hb_CStr( hEv[ "text" ] )
   CASE cType == "tool_call"
      RETURN Chr(10) + DSUI_Color( Chr(226)+Chr(151)+Chr(143) + " " + ;
             DSUI_ToolLabel( hEv[ "name" ], hEv[ "arguments" ] ), "1;36" ) + Chr(10)
   CASE cType == "tool_result"
      RETURN DSUI_Color( DSUI_ResultBlock( hb_CStr( hEv[ "content" ] ) ), ;
             "90" ) + Chr(10)
   CASE cType == "error"
      RETURN Chr(10) + DSUI_Color( "!! error: " + hb_CStr( hEv[ "message" ] ), ;
             "31" ) + Chr(10)
   ENDCASE
   RETURN ""

// Builds a Claude Code-style tool label: "Read(src/x.prg)", "Shell(echo hi)".
// The tool name is capitalised; the most relevant argument goes in parentheses.
STATIC FUNCTION DSUI_ToolLabel( cName, cArgsJson )
   LOCAL cProper, xArgs, cArg := ""
   cName := hb_CStr( cName )
   cProper := iif( Empty( cName ), "Tool", ;
                   Upper( Left( cName, 1 ) ) + SubStr( cName, 2 ) )
   xArgs := hb_jsonDecode( hb_CStr( cArgsJson ) )
   IF ValType( xArgs ) == "H"
      DO CASE
      CASE hb_HHasKey( xArgs, "command" )
         cArg := hb_CStr( xArgs[ "command" ] )
      CASE hb_HHasKey( xArgs, "path" )
         cArg := hb_CStr( xArgs[ "path" ] )
      CASE hb_HHasKey( xArgs, "pattern" )
         cArg := hb_CStr( xArgs[ "pattern" ] )
      ENDCASE
   ENDIF
   cArg := StrTran( StrTran( cArg, Chr(13), " " ), Chr(10), " " )
   IF Len( cArg ) > 80
      cArg := Left( cArg, 80 ) + "..."
   ENDIF
   RETURN cProper + "(" + cArg + ")"

// Builds a Claude Code-style result block: the first line prefixed with the
// corner glyph, continuation lines aligned under it, capped at 8 lines.
STATIC FUNCTION DSUI_ResultBlock( cText )
   LOCAL aLines, cOut := "", i, nShow, cLine, cMark, nMax := 50
   aLines := hb_ATokens( StrTran( cText, Chr(13), "" ), Chr(10) )
   DO WHILE Len( aLines ) > 1 .AND. Empty( ATail( aLines ) )
      hb_ADel( aLines, Len( aLines ), .T. )
   ENDDO
   nShow := Min( Len( aLines ), nMax )
   FOR i := 1 TO nShow
      cLine := aLines[ i ]
      // colour diff lines: added on a green background, removed on dark red
      cMark := DSUI_DiffMark( cLine )
      DO CASE
      CASE cMark == "+"
         cLine := DSUI_Color( cLine, "42" )
      CASE cMark == "-"
         cLine := DSUI_Color( cLine, "48;5;52" )
      ENDCASE
      cOut += iif( i == 1, "  " + Chr(226)+Chr(142)+Chr(191) + "  ", "     " ) + cLine
      IF i < nShow
         cOut += Chr(10)
      ENDIF
   NEXT
   IF Len( aLines ) > nMax
      cOut += Chr(10) + "     ... (" + ;
              LTrim( Str( Len( aLines ) - nMax ) ) + " more lines)"
   ENDIF
   RETURN cOut

// Detects a diff line ("<6-wide number> <+|-|space> <text>"); returns the
// marker "+" or "-", or "" when the line is not a diff line.
STATIC FUNCTION DSUI_DiffMark( cLine )
   LOCAL cM, cNum, i
   IF Len( cLine ) < 9
      RETURN ""
   ENDIF
   cM := SubStr( cLine, 8, 1 )
   IF !( cM == "+" .OR. cM == "-" )
      RETURN ""
   ENDIF
   IF !( SubStr( cLine, 7, 1 ) == " " .AND. SubStr( cLine, 9, 1 ) == " " )
      RETURN ""
   ENDIF
   cNum := SubStr( cLine, 1, 6 )
   FOR i := 1 TO 6
      IF !( IsDigit( SubStr( cNum, i, 1 ) ) .OR. SubStr( cNum, i, 1 ) == " " )
         RETURN ""
      ENDIF
   NEXT
   RETURN cM

// Enables or disables ANSI colour output. Off by default; the REPL turns it on
// from the settings "color" key. Only enable it on a VT-capable terminal.
FUNCTION DSUI_SetColor( lOn )
   s_lColor := ( lOn == .T. )
   RETURN NIL

// Wraps text in an ANSI SGR colour code when colour is enabled, otherwise
// returns the text unchanged. cSGR is the code, e.g. "36" (cyan), "90" (grey),
// "31" (red), "1;36" (bold cyan), "33" (yellow).
FUNCTION DSUI_Color( cText, cSGR )
   IF !s_lColor
      RETURN cText
   ENDIF
   RETURN Chr(27) + "[" + cSGR + "m" + cText + Chr(27) + "[0m"

// The system message seeded into every conversation.
FUNCTION DSUI_SystemPrompt()
   RETURN "You are CCHarbour, a terminal coding assistant. " + ;
          "You have tools to read, write and edit files, search with glob and " + ;
          "grep, and run shell commands. Use them to help the user with coding " + ;
          "tasks. Be concise."

// The text shown by the /help command.
FUNCTION DSUI_Help()
   RETURN "Commands:" + Chr(10) + ;
          "  /help   show this help" + Chr(10) + ;
          "  /clear  reset the conversation" + Chr(10) + ;
          "  /exit   quit (alias: /quit)" + Chr(10) + ;
          "Type anything else to talk to the assistant."

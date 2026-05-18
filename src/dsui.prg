// Whether DSUI_Color emits ANSI colour codes (off unless the REPL turns it on).
STATIC s_lColor := .F.

// Classifies a line of REPL input. Returns a hash with:
//   "type" => "exit"|"clear"|"help"|"init"|"model"|"message"|"empty"
//   "text" => the trimmed line, or the command argument for "model"
FUNCTION DSUI_ParseCommand( cLine )
   LOCAL cTrim := AllTrim( hb_CStr( cLine ) )
   LOCAL cLow  := Lower( cTrim )
   DO CASE
   CASE Empty( cTrim )
      RETURN { "type" => "empty", "text" => "" }
   CASE cLow == "/exit" .OR. cLow == "/quit"
      RETURN { "type" => "exit", "text" => cTrim }
   CASE cLow == "/clear"
      RETURN { "type" => "clear", "text" => cTrim }
   CASE cLow == "/help"
      RETURN { "type" => "help", "text" => cTrim }
   CASE cLow == "/init"
      RETURN { "type" => "init", "text" => "" }
   CASE cLow == "/model" .OR. Left( cLow, 7 ) == "/model "
      RETURN { "type" => "model", "text" => AllTrim( SubStr( cTrim, 7 ) ) }
   ENDCASE
   RETURN { "type" => "message", "text" => cTrim }

// The instruction sent to the agent by the /init command: it asks the model
// to inspect the project and write a CLAUDE.md file.
FUNCTION DSUI_InitPrompt()
   RETURN "Analyse this project and create a CLAUDE.md file in the working " + ;
          "directory. Use your tools to explore the repository: its layout, " + ;
          "how it is built and run, and its coding conventions. CLAUDE.md " + ;
          "should concisely cover: what the project is, how to build and run " + ;
          "it, the key directories, and the coding conventions to follow. " + ;
          "Keep it short. Write the file with your write tool, then confirm."

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
      RETURN Chr(10) + DSUI_Color( Chr(226)+Chr(143)+Chr(186) + " " + ;
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

// Returns .T. when ANSI output (colour and cursor control) is enabled.
FUNCTION DSUI_ColorOn()
   RETURN s_lColor

// The Claude Code-style colour palette: maps a name to an ANSI SGR code so
// the codes live in one place. Unknown names return "0" (reset).
FUNCTION DSUI_Pal( cName )
   DO CASE
   CASE cName == "accent"     ; RETURN "38;5;215"   // tan/orange
   CASE cName == "dim"        ; RETURN "90"         // grey borders / secondary
   CASE cName == "bold"       ; RETURN "1"
   CASE cName == "error"      ; RETURN "31"
   CASE cName == "tool"       ; RETURN "1;36"       // bright cyan tool label
   CASE cName == "warn"       ; RETURN "33"
   CASE cName == "diff_add"   ; RETURN "42"
   CASE cName == "diff_del"   ; RETURN "48;5;52"
   ENDCASE
   RETURN "0"

// Emits an ANSI control sequence (e.g. "1A" = cursor up one line,
// "1G" = move to column 1) when ANSI output is enabled, else "".
FUNCTION DSUI_VT( cSeq )
   IF !s_lColor
      RETURN ""
   ENDIF
   RETURN Chr(27) + "[" + cSeq

// The system message seeded into every conversation. When a CLAUDE.md file is
// present in the working directory its contents are appended as project
// instructions, so the agent honours per-project conventions.
FUNCTION DSUI_SystemPrompt()
   LOCAL cBase, cProj
   cBase := "You are CCHarbour, a terminal coding assistant. " + ;
            "You have tools to read, write and edit files, search with glob and " + ;
            "grep, and run shell commands. Use them to help the user with coding " + ;
            "tasks. Be concise."
   cProj := DSUI_ProjectContext()
   IF !Empty( cProj )
      cBase += Chr(10) + Chr(10) + ;
         "The following project instructions come from the CLAUDE.md file in " + ;
         "the working directory. Treat them as authoritative and follow them:" + ;
         Chr(10) + Chr(10) + cProj
   ENDIF
   RETURN cBase

// Reads project instructions from a CLAUDE.md file in the current directory.
// Returns "" when the file is absent or empty.
FUNCTION DSUI_ProjectContext()
   LOCAL cText := ""
   IF File( "CLAUDE.md" )
      cText := hb_MemoRead( "CLAUDE.md" )
   ENDIF
   RETURN AllTrim( hb_CStr( cText ) )

// Returns a UTF-8 box-drawing glyph by name, built from raw bytes so the
// source file's encoding does not matter.
STATIC FUNCTION DSUI_Glyph( cName )
   DO CASE
   CASE cName == "tl"
      RETURN Chr(226)+Chr(149)+Chr(173)   // ╭
   CASE cName == "tr"
      RETURN Chr(226)+Chr(149)+Chr(174)   // ╮
   CASE cName == "bl"
      RETURN Chr(226)+Chr(149)+Chr(176)   // ╰
   CASE cName == "br"
      RETURN Chr(226)+Chr(149)+Chr(175)   // ╯
   CASE cName == "h"
      RETURN Chr(226)+Chr(148)+Chr(128)   // ─
   CASE cName == "v"
      RETURN Chr(226)+Chr(148)+Chr(130)   // │
   ENDCASE
   RETURN " "

// Pads cText to nWidth display columns, counting UTF-8 characters (not bytes).
// cAlign is "L" (default), "C" (centre) or "R" (right). Over-long text is cut.
STATIC FUNCTION DSUI_PadCell( cText, nWidth, cAlign )
   LOCAL nLen, nPad, nLeft
   cText := hb_CStr( cText )
   nLen  := hb_UTF8Len( cText )
   IF nLen > nWidth
      cText := hb_UTF8SubStr( cText, 1, nWidth )
      nLen  := nWidth
   ENDIF
   nPad := nWidth - nLen
   DO CASE
   CASE cAlign == "C"
      nLeft := Int( nPad / 2 )
      RETURN Space( nLeft ) + cText + Space( nPad - nLeft )
   CASE cAlign == "R"
      RETURN Space( nPad ) + cText
   ENDCASE
   RETURN cText + Space( nPad )

// Builds one content row of the banner: a left cell and a right cell divided
// by the vertical glyph. aL/aR are { text, align } pairs. lTitle highlights the
// left cell (the welcome line). A right text of "<HR>" draws a panel divider.
STATIC FUNCTION DSUI_BanRow( aL, aR, nLW, nRW )
   LOCAL cV := DSUI_Color( DSUI_Glyph( "v" ), "90" )
   LOCAL cL, cR
   cL := DSUI_PadCell( aL[ 1 ], nLW, aL[ 2 ] )
   IF aL[ 3 ]
      cL := DSUI_Color( cL, "1;36" )
   ENDIF
   IF aR[ 1 ] == "<HR>"
      cR := DSUI_Color( Replicate( DSUI_Glyph( "h" ), nRW ), "90" )
   ELSE
      cR := DSUI_PadCell( aR[ 1 ], nRW, aR[ 2 ] )
      IF aR[ 3 ]
         cR := DSUI_Color( cR, "1" )
      ENDIF
   ENDIF
   RETURN cV + " " + cL + " " + cV + " " + cR + " " + cV

// Builds the Claude Code-style startup banner: a rounded box with a welcome
// panel (logo, model, working directory) on the left and a tips / what's-new
// panel on the right. Returns the whole banner as one string ending in LF.
FUNCTION DSUI_Banner( cModel, cCwd, cUser )
   LOCAL nLW := 38, nRW := 34
   LOCAL cH := DSUI_Glyph( "h" )
   LOCAL cOut, i, aL, aR

   cModel := hb_CStr( cModel )
   cCwd   := hb_CStr( cCwd )
   cUser  := AllTrim( hb_CStr( cUser ) )
   IF Empty( cUser )
      cUser := "developer"
   ENDIF

   // left panel rows: { text, align, isTitle }
   aL := { ;
      { "",                                       "L", .F. }, ;
      { "Welcome to CCHarbour, " + cUser + "!",    "C", .T. }, ;
      { "",                                       "L", .F. }, ;
      { "  \  |  /  ",                             "C", .F. }, ;
      { "-- (CC) -- ",                             "C", .F. }, ;
      { "  /  |  \  ",                             "C", .F. }, ;
      { "",                                       "L", .F. }, ;
      { "model: " + cModel,                        "C", .F. }, ;
      { cCwd,                                      "C", .F. }, ;
      { "",                                       "L", .F. }, ;
      { "",                                       "L", .F. } }

   // right panel rows: { text, align, isBold }
   aR := { ;
      { "Tips for getting started",   "L", .T. }, ;
      { "",                           "L", .F. }, ;
      { "Type a request to begin",    "L", .F. }, ;
      { "Run /help to list commands", "L", .F. }, ;
      { "<HR>",                       "L", .F. }, ;
      { "What's new",                 "L", .T. }, ;
      { "",                           "L", .F. }, ;
      { "Streamed tool output",       "L", .F. }, ;
      { "Inline diffs on edits",      "L", .F. }, ;
      { "Auto colour detection",      "L", .F. }, ;
      { "",                           "L", .F. } }

   cOut := DSUI_Color( DSUI_Glyph( "tl" ) + ;
           Replicate( cH, nLW + nRW + 5 ) + DSUI_Glyph( "tr" ), "90" ) + Chr(10)
   FOR i := 1 TO Len( aL )
      cOut += DSUI_BanRow( aL[ i ], aR[ i ], nLW, nRW ) + Chr(10)
   NEXT
   cOut += DSUI_Color( DSUI_Glyph( "bl" ) + ;
           Replicate( cH, nLW + nRW + 5 ) + DSUI_Glyph( "br" ), "90" ) + Chr(10)
   RETURN cOut

// A horizontal rule as wide as the startup banner box, used to frame the
// input prompt the way Claude Code does.
FUNCTION DSUI_Rule()
   RETURN Replicate( DSUI_Glyph( "h" ), 79 )

// The text shown by the /help command.
FUNCTION DSUI_Help()
   RETURN "Commands:" + Chr(10) + ;
          "  /help          show this help" + Chr(10) + ;
          "  /init          analyse the project and write CLAUDE.md" + Chr(10) + ;
          "  /model [name]  show the model, or switch to <name>" + Chr(10) + ;
          "  /clear         reset the conversation" + Chr(10) + ;
          "  /exit          quit (alias: /quit)" + Chr(10) + ;
          "Type anything else to talk to the assistant."

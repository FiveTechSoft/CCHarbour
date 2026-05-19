// Whether DSUI_Color emits ANSI colour codes (off unless the REPL turns it on).
STATIC s_lColor := .F.

// Classifies a line of REPL input. Returns a hash with:
//   "type" => "exit"|"clear"|"help"|"init"|"model"|"cost"|"message"|"empty"
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
   CASE cLow == "/cost"
      RETURN { "type" => "cost", "text" => "" }
   ENDCASE
   RETURN { "type" => "message", "text" => cTrim }

// The instruction sent to the agent by the /init command: it asks the model
// to inspect the project and write a CC.md file.
FUNCTION DSUI_InitPrompt()
   RETURN "Analyse this project and create a CC.md file in the working " + ;
          "directory. Use your tools to explore the repository: its layout, " + ;
          "how it is built and run, and its coding conventions. CC.md " + ;
          "should concisely cover: what the project is, how to build and run " + ;
          "it, the key directories, and the coding conventions to follow. " + ;
          "Keep it short. Write the file with your write tool, then confirm."

// Formats a session usage hash into a human-readable cost report.
// hUsage: { prompt_tokens => N, completion_tokens => N, ... }
// Pricing is approximate (DeepSeek API rates).
FUNCTION DSUI_CostReport( hUsage )
   LOCAL nIn, nOut, cOut, nCostIn, nCostOut, nCostTotal
   IF ValType( hUsage ) != "H" .OR. Len( hb_HKeys( hUsage ) ) == 0
      RETURN DSUI_Color( "No usage data for this session yet.", "90" ) + Chr(10)
   ENDIF
   nIn  := hb_HGetDef( hUsage, "prompt_tokens", 0 )
   nOut := hb_HGetDef( hUsage, "completion_tokens", 0 )
   cOut := DSUI_Color( DSUI_Glyph( "tl" ) + Replicate( DSUI_Glyph( "h" ), 34 ) + ;
                       DSUI_Glyph( "tr" ), DSUI_Pal( "dim" ) ) + Chr(10)
   cOut += DSUI_Color( DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) ) + ;
           "  Session cost report" + ;
           DSUI_Color( "  " + DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) ) + Chr(10)
   cOut += DSUI_Color( DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) ) + ;
           "  prompt tokens:      " + LTrim( Str( nIn ) ) + ;
           DSUI_Color( "   " + DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) ) + Chr(10)
   cOut += DSUI_Color( DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) ) + ;
           "  completion tokens:  " + LTrim( Str( nOut ) ) + ;
           DSUI_Color( "   " + DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) ) + Chr(10)
   cOut += DSUI_Color( DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) ) + ;
           DSUI_Color( "  total tokens:      " + LTrim( Str( nIn + nOut ) ), "1" ) + ;
           DSUI_Color( "   " + DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) ) + Chr(10)
   // approximate cost: DeepSeek ~$0.15/M input, ~$0.60/M output
   nCostIn   := nIn * 0.15 / 1000000
   nCostOut  := nOut * 0.60 / 1000000
   nCostTotal := nCostIn + nCostOut
   cOut += DSUI_Color( DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) ) + ;
           "  est. cost:          $" + LTrim( Str( nCostTotal, 10, 6 ) ) + ;
           DSUI_Color( "   " + DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) ) + Chr(10)
   cOut += DSUI_Color( DSUI_Glyph( "bl" ) + Replicate( DSUI_Glyph( "h" ), 34 ) + ;
                       DSUI_Glyph( "br" ), DSUI_Pal( "dim" ) ) + Chr(10)
   RETURN cOut

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
// tool_call and tool_result are rendered by the REPL render layer, which has
// the tool-name state they need.
FUNCTION DSUI_RenderEvent( hEv )
   LOCAL cType
   IF ValType( hEv ) != "H" .OR. !hb_HHasKey( hEv, "type" )
      RETURN ""
   ENDIF
   cType := hEv[ "type" ]
   DO CASE
   CASE cType == "text_delta"
      RETURN hb_CStr( hEv[ "text" ] )
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
      // colour diff lines: added on a green background, removed on dark red.
      // The line is space-padded first so the background fills the width
      // instead of stopping at the end of the text.
      cMark := DSUI_DiffMark( cLine )
      DO CASE
      CASE cMark == "+"
         cLine := DSUI_Color( DSUI_DiffPad( cLine ), "42" )
      CASE cMark == "-"
         cLine := DSUI_Color( DSUI_DiffPad( cLine ), "48;5;52" )
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

// Pads a diff line with trailing spaces so its background colour fills the
// row (a coloured diff bar spans the line rather than stopping at the text).
// A line already at or over the width is returned unchanged.
FUNCTION DSUI_DiffPad( cLine )
   LOCAL nLen := hb_UTF8Len( hb_CStr( cLine ) )
   RETURN iif( nLen < 90, cLine + Space( 90 - nLen ), cLine )

// The Claude Code-style tool-call line: an accent dot, then Tool(args). The
// dot is accent-coloured; the label is left in the default foreground.
FUNCTION DSUI_ToolCallLine( cName, cArgsJson )
   RETURN Chr(10) + ;
          DSUI_Color( Chr(226)+Chr(143)+Chr(186), DSUI_Pal( "accent" ) ) + ;
          " " + DSUI_ToolLabel( cName, cArgsJson ) + Chr(10)

// True when any line of cText is diff-formatted (per DSUI_DiffMark).
STATIC FUNCTION DSUI_HasDiff( cText )
   LOCAL cLine
   FOR EACH cLine IN hb_ATokens( cText, Chr(10) )
      IF !Empty( DSUI_DiffMark( cLine ) )
         RETURN .T.
      ENDIF
   NEXT
   RETURN .F.

// Renders the block printed under a tool call. Diff-formatted content keeps
// the coloured diff block; otherwise a compact tool-aware one-line summary.
// Result ends in LF.
FUNCTION DSUI_ResultSummary( cToolName, cContent )
   LOCAL cClean, aLines, nLines, cFirst, cSum
   cToolName := Lower( hb_CStr( cToolName ) )
   cContent  := hb_CStr( cContent )
   cClean    := StrTran( cContent, Chr(13), "" )

   IF DSUI_HasDiff( cClean )
      RETURN DSUI_Color( DSUI_ResultBlock( cContent ), DSUI_Pal( "dim" ) ) + Chr(10)
   ENDIF

   IF Left( cClean, 6 ) == "Error:"
      cSum := DSUI_Summarize( cClean, 200 )
   ELSE
      aLines := hb_ATokens( cClean, Chr(10) )
      DO WHILE Len( aLines ) > 1 .AND. Empty( ATail( aLines ) )
         hb_ADel( aLines, Len( aLines ), .T. )
      ENDDO
      nLines := Len( aLines )
      cFirst := Left( iif( nLines > 0, aLines[ 1 ], "" ), 120 )
      DO CASE
      CASE cToolName == "read"
         cSum := "Read " + LTrim( Str( nLines ) ) + " lines"
      CASE cToolName == "write" .OR. cToolName == "edit"
         cSum := cFirst
      CASE cToolName == "glob"
         cSum := iif( Left( cFirst, 11 ) == "No matches ", cFirst, ;
                      "Listed " + LTrim( Str( nLines ) ) + " files" )
      CASE cToolName == "grep"
         cSum := iif( Left( cFirst, 11 ) == "No matches ", cFirst, ;
                      "Found " + LTrim( Str( nLines ) ) + " matches" )
      CASE cToolName == "shell"
         cSum := iif( nLines > 1, ;
                      cFirst + " (" + LTrim( Str( nLines ) ) + " lines)", cFirst )
      OTHERWISE
         cSum := LTrim( Str( nLines ) ) + " lines"
      ENDCASE
   ENDIF

   RETURN DSUI_Color( "  " + Chr(226)+Chr(142)+Chr(191) + "  " + cSum, ;
                      DSUI_Pal( "dim" ) ) + Chr(10)

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
   CASE cName == "accent"     ; RETURN "38;2;217;119;87"   // Claude Code coral
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

// The system message seeded into every conversation. When a CC.md file is
// present in the working directory its contents are appended as project
// instructions, so the agent honours per-project conventions. When a
// memory.md file is present it is appended as the agent's persisted memory.
FUNCTION DSUI_SystemPrompt()
   LOCAL cBase, cProj, cMem
   cBase := "You are CCHarbour, a terminal coding assistant. " + ;
            "You have tools to read, write and edit files, search with glob and " + ;
            "grep, and run shell commands. Use them to help the user with coding " + ;
            "tasks. Be concise. " + ;
            "End every reply with a final line in the exact form " + ;
            "'Suggested next: <a short prompt the user might send next>'."
   cProj := DSUI_ProjectContext()
   IF !Empty( cProj )
      cBase += Chr(10) + Chr(10) + ;
         "The following project instructions come from the CC.md file in " + ;
         "the working directory. Treat them as authoritative and follow them:" + ;
         Chr(10) + Chr(10) + cProj
   ENDIF
   cMem := DSUI_MemoryContext()
   IF !Empty( cMem )
      cBase += Chr(10) + Chr(10) + ;
         "The following is your own memory, persisted from previous sessions " + ;
         "in this project. Use it, and keep it current with the memory tool:" + ;
         Chr(10) + Chr(10) + cMem
   ENDIF
   RETURN cBase

// Reads project instructions from a CC.md file in the current directory.
// Returns "" when the file is absent or empty.
FUNCTION DSUI_ProjectContext()
   LOCAL cText := ""
   IF File( "CC.md" )
      cText := hb_MemoRead( "CC.md" )
   ENDIF
   RETURN AllTrim( hb_CStr( cText ) )

// Reads the agent's persisted memory from memory.md in the current directory.
// Returns "" when the file is absent or empty.
FUNCTION DSUI_MemoryContext()
   LOCAL cText := ""
   IF File( "memory.md" )
      cText := hb_MemoRead( "memory.md" )
   ENDIF
   RETURN AllTrim( hb_CStr( cText ) )

// Returns a UTF-8 box-drawing glyph by name, built from raw bytes so the
// source file's encoding does not matter.
FUNCTION DSUI_Glyph( cName )
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

// The CCHarbour version string.
FUNCTION DSUI_Version()
   RETURN "0.2.0"

// Builds the Claude Code-style startup banner: a single-panel rounded box with
// a block-letter "CC" logo on the left (default foreground) and the
// name+version (accent colour), a tagline, the /help hint, the model and the
// working directory on the right. Returns the whole banner as one string ending in LF.
FUNCTION DSUI_Banner( cModel, cCwd, cUser )
   LOCAL nInner := 75, cH := DSUI_Glyph( "h" ), cV
   LOCAL cAccent := Chr(226)+Chr(156)+Chr(187)   // U+273B
   LOCAL aLogo, aInfo, aRows, cOut, i, cText, cSGR, cCell

   HB_SYMBOL_UNUSED( cUser )
   cModel := hb_CStr( cModel )
   cCwd   := hb_CStr( cCwd )
   cV     := DSUI_Color( DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) )

   // the "CC" logo, six rows of block-drawing glyphs
   aLogo := { ;
      "  ██████╗ ██████╗ ", ;
      " ██╔════╝██╔════╝ ", ;
      " ██║     ██║      ", ;
      " ██║     ██║      ", ;
      " ╚██████╗╚██████╗ ", ;
      "  ╚═════╝ ╚═════╝ " }

   // the info column, paired row-for-row with the logo
   aInfo := { ;
      cAccent + " CCHarbour  v" + DSUI_Version(), ;
      "terminal coding assistant " + Chr(226)+Chr(128)+Chr(183) + ;
         " Claude Code-style", ;
      "", ;
      "/help for help", ;
      "model: " + cModel, ;
      "cwd: " + cCwd }

   // each row: { plain text, SGR code or "" }. The first info row (name +
   // version) is accent; the rest plain.
   aRows := {}
   FOR i := 1 TO 6
      cText := DSUI_PadCell( aLogo[ i ], 18, "L" ) + " " + aInfo[ i ]
      cSGR  := iif( i == 1, DSUI_Pal( "accent" ), "" )
      AAdd( aRows, { cText, cSGR } )
   NEXT

   cOut := DSUI_Color( DSUI_Glyph( "tl" ) + Replicate( cH, nInner + 2 ) + ;
           DSUI_Glyph( "tr" ), DSUI_Pal( "dim" ) ) + Chr(10)
   FOR i := 1 TO Len( aRows )
      cText := aRows[ i ][ 1 ]
      cSGR  := aRows[ i ][ 2 ]
      cCell := DSUI_PadCell( cText, nInner, "L" )
      IF !Empty( cSGR )
         cCell := DSUI_Color( cCell, cSGR )
      ENDIF
      cOut += cV + " " + cCell + " " + cV + Chr(10)
   NEXT
   cOut += DSUI_Color( DSUI_Glyph( "bl" ) + Replicate( cH, nInner + 2 ) + ;
           DSUI_Glyph( "br" ), DSUI_Pal( "dim" ) ) + Chr(10)
   RETURN cOut

// The rounded top border of the input frame, 79 columns wide.
FUNCTION DSUI_FrameTop()
   RETURN DSUI_Color( DSUI_Glyph( "tl" ) + ;
          Replicate( DSUI_Glyph( "h" ), 77 ) + DSUI_Glyph( "tr" ), ;
          DSUI_Pal( "dim" ) )

// The rounded bottom border of the input frame, 79 columns wide.
FUNCTION DSUI_FrameBottom()
   RETURN DSUI_Color( DSUI_Glyph( "bl" ) + ;
          Replicate( DSUI_Glyph( "h" ), 77 ) + DSUI_Glyph( "br" ), ;
          DSUI_Pal( "dim" ) )

// The dim hint line shown beneath the input frame.
// nLines (optional) shows the line count for multi-line input.
FUNCTION DSUI_InputHint( nLines )
   LOCAL cSuffix := ""
   IF ValType( nLines ) == "N" .AND. nLines > 1
      cSuffix := "  " + Chr(226)+Chr(128)+Chr(162) + "  " + LTrim( Str( nLines ) ) + " lines"
   ENDIF
   RETURN DSUI_Color( "  /help for commands" + cSuffix + ;
          "  " + Chr(226)+Chr(128)+Chr(162) + "  /exit to quit", DSUI_Pal( "dim" ) )

// The text-column width available inside the input box (79 total: 2 borders,
// 2 inside spaces, the "> " prompt = 6 of overhead, leaving 73).
FUNCTION DSUI_InputInnerWidth()
   RETURN 73

// One framed input-box prompt line: side borders, the "> " prompt, and cText
// padded (or truncated) to the inner width. 79 display columns wide.
FUNCTION DSUI_InputBoxLine( cText )
   LOCAL cV := DSUI_Color( DSUI_Glyph( "v" ), DSUI_Pal( "dim" ) )
   RETURN cV + " " + DSUI_Color( "> ", "1;36" ) + ;
          DSUI_PadCell( hb_CStr( cText ), DSUI_InputInnerWidth(), "L" ) + ;
          " " + cV

// The text shown by the /help command.
FUNCTION DSUI_Help()
   RETURN "Commands:" + Chr(10) + ;
          "  /help          show this help" + Chr(10) + ;
          "  /init          analyse the project and write CC.md" + Chr(10) + ;
          "  /model [name]  show the model, or switch to <name>" + Chr(10) + ;
          "  /cost          show token usage and estimated cost" + Chr(10) + ;
          "  /clear         reset the conversation" + Chr(10) + ;
          "  /exit          quit (alias: /quit)" + Chr(10) + ;
          "Type anything else to talk to the assistant."

// Streaming, line-buffered markdown-to-ANSI renderer for the assistant's
// reply. The reply arrives as text deltas; this renders each line once it is
// complete, mirroring the SSE parser pattern. It also captures the
// "Suggested next:" marker line. Never throws: unrecognised text is emitted
// unchanged, and with colour off (DSUI_ColorOn() false) markers are stripped
// but no ANSI codes are produced.

// Creates a fresh render state.
FUNCTION DSMD_New()
   RETURN { "buf" => "", "fence" => .F., "suggestion" => "" }

// Appends a chunk; renders every line completed by a newline. Returns the
// rendered ANSI text for those lines ("" when only a partial line is buffered).
FUNCTION DSMD_Feed( oSt, cChunk )
   LOCAL cOut := "", nNL, cLine
   oSt[ "buf" ] += hb_CStr( cChunk )
   DO WHILE ( nNL := At( Chr(10), oSt[ "buf" ] ) ) > 0
      cLine := Left( oSt[ "buf" ], nNL - 1 )
      oSt[ "buf" ] := SubStr( oSt[ "buf" ], nNL + 1 )
      cOut += DSMD_RenderLine( oSt, cLine )
   ENDDO
   RETURN cOut

// Renders any buffered partial line (call at end of stream).
FUNCTION DSMD_Flush( oSt )
   LOCAL cOut := ""
   IF Len( oSt[ "buf" ] ) > 0
      cOut := DSMD_RenderLine( oSt, oSt[ "buf" ] )
      oSt[ "buf" ] := ""
   ENDIF
   RETURN cOut

// Returns the captured suggested next prompt, or "".
FUNCTION DSMD_Suggestion( oSt )
   RETURN oSt[ "suggestion" ]

// Renders one line (no trailing newline supplied); the result ends in LF.
STATIC FUNCTION DSMD_RenderLine( oSt, cLine )
   LOCAL cTrim, cRest, nH, cList
   cLine := StrTran( cLine, Chr(13), "" )
   cTrim := AllTrim( cLine )

   // suggested-prompt marker -> captured, never printed
   IF Len( cTrim ) >= 15 .AND. Lower( Left( cTrim, 15 ) ) == "suggested next:"
      oSt[ "suggestion" ] := AllTrim( SubStr( cTrim, 16 ) )
      RETURN ""
   ENDIF

   // fenced code block toggle (``` optionally followed by a language tag)
   IF Left( cTrim, 3 ) == "```"
      oSt[ "fence" ] := !oSt[ "fence" ]
      RETURN ""
   ENDIF
   IF oSt[ "fence" ]
      RETURN "  " + DSUI_Color( cLine, "90" ) + Chr(10)
   ENDIF

   // blank line
   IF Empty( cTrim )
      RETURN Chr(10)
   ENDIF

   // heading
   nH := DSMD_HeadingLevel( cTrim )
   IF nH > 0
      cRest := AllTrim( SubStr( cTrim, nH + 1 ) )
      RETURN DSUI_Color( cRest, "1" ) + Chr(10)
   ENDIF

   // list item
   cList := DSMD_ListRender( cTrim )
   IF cList != NIL
      RETURN cList + Chr(10)
   ENDIF

   // paragraph
   RETURN DSMD_Inline( cLine ) + Chr(10)

// Returns the heading level 1..6 for a "# " .. "###### " line, else 0.
STATIC FUNCTION DSMD_HeadingLevel( cTrim )
   LOCAL n := 0
   DO WHILE SubStr( cTrim, n + 1, 1 ) == "#"
      n++
   ENDDO
   IF n >= 1 .AND. n <= 6 .AND. SubStr( cTrim, n + 1, 1 ) == " "
      RETURN n
   ENDIF
   RETURN 0

// Renders a bullet ("- ", "* ", "+ ") or numbered ("<digits>. ") list item,
// or NIL when the line is not a list item.
STATIC FUNCTION DSMD_ListRender( cTrim )
   LOCAL cMark := Left( cTrim, 2 ), nDot := 0, i, c
   LOCAL cBullet := Chr(226)+Chr(128)+Chr(162)   // U+2022 bullet
   IF cMark == "- " .OR. cMark == "* " .OR. cMark == "+ "
      RETURN "  " + DSUI_Color( cBullet, "90" ) + " " + ;
             DSMD_Inline( SubStr( cTrim, 3 ) )
   ENDIF
   FOR i := 1 TO Len( cTrim )
      c := SubStr( cTrim, i, 1 )
      IF IsDigit( c )
         LOOP
      ENDIF
      IF c == "." .AND. i > 1 .AND. SubStr( cTrim, i + 1, 1 ) == " "
         nDot := i
      ENDIF
      EXIT
   NEXT
   IF nDot > 0
      RETURN "  " + DSUI_Color( Left( cTrim, nDot ), "90" ) + " " + ;
             DSMD_Inline( SubStr( cTrim, nDot + 2 ) )
   ENDIF
   RETURN NIL

// Applies inline formatting: **bold**, `code`, *italic*. Order matters:
// ** before * so a bold pair is not split by the italic pass.
STATIC FUNCTION DSMD_Inline( cText )
   cText := DSMD_Span( cText, "**", "1" )
   cText := DSMD_Span( cText, "`", "96" )
   cText := DSMD_Span( cText, "*", "3" )
   RETURN cText

// Wraps every cDelim..cDelim span in cText with the ANSI colour cSGR.
// An unmatched trailing delimiter is left as literal text.
STATIC FUNCTION DSMD_Span( cText, cDelim, cSGR )
   LOCAL nDL := Len( cDelim ), nOpen, nClose, cResult := ""
   LOCAL cInner, cBefore
   DO WHILE ( nOpen := At( cDelim, cText ) ) > 0
      nClose := At( cDelim, SubStr( cText, nOpen + nDL ) )
      IF nClose == 0
         EXIT
      ENDIF
      cBefore := Left( cText, nOpen - 1 )
      cInner  := SubStr( cText, nOpen + nDL, nClose - 1 )
      cResult += cBefore + DSUI_Color( cInner, cSGR )
      cText := SubStr( cText, nOpen + nDL + nClose - 1 + nDL )
   ENDDO
   RETURN cResult + cText

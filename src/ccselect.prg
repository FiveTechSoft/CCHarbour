// ccselect: the interactive multiple-choice selector used by the ask_user
// tool. This file holds the pure state logic and the raw-key I/O loop. The
// block rendering (CCUI_QuestionBlock) lives in ccui.prg so it can reuse the
// static CCUI_PadCell helper.

// Builds a fresh selector state. aOptions is the list of answer strings; the
// literal "Other" is appended so the user is never boxed in. The cursor
// starts on the first option.
FUNCTION CCSEL_New( cQuestion, aOptions )
   LOCAL aOpts := {}, x
   IF ValType( aOptions ) == "A"
      FOR EACH x IN aOptions
         AAdd( aOpts, hb_CStr( x ) )
      NEXT
   ENDIF
   AAdd( aOpts, "Other" )
   RETURN { "question" => hb_CStr( cQuestion ), ;
            "options"  => aOpts, ;
            "cursor"   => 1 }

// Moves the cursor to nIndex, clamped to 1..Len(options). Returns oSel.
FUNCTION CCSEL_SetCursor( oSel, nIndex )
   LOCAL nMax := Len( oSel[ "options" ] )
   IF nIndex < 1
      nIndex := 1
   ELSEIF nIndex > nMax
      nIndex := nMax
   ENDIF
   oSel[ "cursor" ] := nIndex
   RETURN oSel

// Moves the cursor by nDelta rows, clamped. Returns oSel.
FUNCTION CCSEL_Move( oSel, nDelta )
   RETURN CCSEL_SetCursor( oSel, oSel[ "cursor" ] + nDelta )

// Writes bytes straight to stdout, bypassing CCREPL_Out's line rewriting --
// needed for absolute cursor positioning.
STATIC FUNCTION CCSEL_Raw( cText )
   FWrite( hb_GetStdOut(), cText )
   RETURN NIL

// Paints the question block. On a repaint, first moves the cursor up over the
// previous block (question line + one line per option) so the new block
// overwrites it. Every row is a constant display width across repaints -- only
// the marker and inverse video change -- so no explicit clearing is needed.
STATIC FUNCTION CCSEL_Paint( oSel, lRepaint )
   LOCAL nLines := Len( oSel[ "options" ] ) + 1
   IF lRepaint
      CCSEL_Raw( Chr(27) + "[" + LTrim( Str( nLines ) ) + "A" )
   ENDIF
   CCSEL_Raw( CCUI_QuestionBlock( oSel ) )
   RETURN NIL

// Reads a free-text answer for the "Other" option: prints a prompt, then
// collects printable characters until Enter. Backspace deletes the last char.
STATIC FUNCTION CCSEL_ReadOther()
   LOCAL cBuf := "", nKey
   CCSEL_Raw( Chr(10) + "Other (type your answer, Enter to confirm): " )
   DO WHILE .T.
      DO WHILE !CCCON_KeyPending()
         hb_idleSleep( 0.02 )
      ENDDO
      nKey := CCCON_ReadKey()
      DO CASE
      CASE nKey == -1                       // Enter -> done
         EXIT
      CASE nKey == -2                       // Backspace
         IF !Empty( cBuf )
            cBuf := hb_UTF8SubStr( cBuf, 1, hb_UTF8Len( cBuf ) - 1 )
            CCSEL_Raw( Chr(8) + " " + Chr(8) )
         ENDIF
      CASE nKey > 0                         // a printable character
         cBuf += CCIN_Utf8Chr( nKey )
         CCSEL_Raw( CCIN_Utf8Chr( nKey ) )
      ENDCASE
   ENDDO
   CCSEL_Raw( Chr(10) )
   RETURN AllTrim( cBuf )

// Runs the selector interactively and returns the chosen answer string.
// Up/Down move the highlight, a digit key (1-9) jumps to and selects that
// option, Enter confirms the highlighted option. Choosing "Other" drops to a
// free-text prompt. With no console (piped input) it cannot prompt, so it
// returns the first option as a default.
FUNCTION CCSEL_Run( oSel )
   LOCAL nKey, cAnswer, lDone := .F.
   IF !CCCON_HasConsole()
      RETURN oSel[ "options" ][ 1 ]
   ENDIF
   CCSEL_Paint( oSel, .F. )
   DO WHILE !lDone
      DO WHILE !CCCON_KeyPending()
         hb_idleSleep( 0.02 )
      ENDDO
      nKey := CCCON_ReadKey()
      DO CASE
      CASE nKey == -9                       // Up
         CCSEL_Move( oSel, -1 )
      CASE nKey == -10                      // Down
         CCSEL_Move( oSel, 1 )
      CASE nKey >= 49 .AND. nKey <= 57      // digit 1-9 -> jump and select
         CCSEL_SetCursor( oSel, nKey - 48 )
         lDone := .T.
      CASE nKey == -1                       // Enter -> confirm
         lDone := .T.
      ENDCASE
      IF !lDone
         CCSEL_Paint( oSel, .T. )
      ENDIF
   ENDDO
   cAnswer := oSel[ "options" ][ oSel[ "cursor" ] ]
   IF cAnswer == "Other"
      cAnswer := CCSEL_ReadOther()
   ENDIF
   RETURN cAnswer

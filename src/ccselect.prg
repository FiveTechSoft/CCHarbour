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

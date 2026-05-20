// ccprompt: the persistent bottom input box and the mid-turn message queue.
// This file holds the pure logic; the console I/O (Poll, Redraw, Activate,
// Teardown) is added on top of it.

// The input box occupies the bottom THREE rows of the terminal.
#define CCPROMPT_BOX_ROWS  3
// Below this many rows there is no room for the box -> fallback mode.
#define CCPROMPT_MIN_ROWS  8

// Builds a fresh prompt state. hSize is an optional { rows, cols } hash; when
// omitted the console is queried with CCCON_Size(). region/editor/queue are
// always present so the pure helpers work without a console.
FUNCTION CCPROMPT_New( hSize )
   LOCAL nRows, nCols
   IF ValType( hSize ) == "H"
      nRows := hSize[ "rows" ]
      nCols := hSize[ "cols" ]
   ELSE
      hSize := CCCON_Size()
      nRows := hSize[ "rows" ]
      nCols := hSize[ "cols" ]
   ENDIF
   RETURN { "editor"    => CCIN_New( "" ), ;
            "queue"     => {}, ;
            "interrupt" => NIL, ;
            "region"    => CCPROMPT_Region( nRows, nCols ) }

// Computes the screen layout for a console of nRows x nCols. The box is the
// bottom 3 rows; the scroll region is rows 1 .. nRows-3. A console shorter
// than CCPROMPT_MIN_ROWS is reported inactive (the caller falls back).
FUNCTION CCPROMPT_Region( nRows, nCols )
   RETURN { "rows"          => nRows, ;
            "cols"          => nCols, ;
            "active"        => ( nRows >= CCPROMPT_MIN_ROWS ), ;
            "scroll_bottom" => nRows - CCPROMPT_BOX_ROWS, ;
            "box_top"       => nRows - CCPROMPT_BOX_ROWS + 1 }

// Classifies a submitted line. Returns { action, text }:
//   action "empty" -> blank line, ignore
//   action "btw"   -> /btw line, text is the remainder (an interrupt)
//   action "queue" -> a normal message to queue
FUNCTION CCPROMPT_Classify( cLine )
   LOCAL cTrim := AllTrim( hb_CStr( cLine ) )
   IF Empty( cTrim )
      RETURN { "action" => "empty", "text" => "" }
   ENDIF
   IF Lower( cTrim ) == "/btw"
      RETURN { "action" => "btw", "text" => "" }
   ENDIF
   IF Lower( Left( cTrim, 5 ) ) == "/btw "
      RETURN { "action" => "btw", "text" => AllTrim( SubStr( cTrim, 6 ) ) }
   ENDIF
   RETURN { "action" => "queue", "text" => cTrim }

// Appends a message to the FIFO queue.
FUNCTION CCPROMPT_Enqueue( oPrompt, cText )
   AAdd( oPrompt[ "queue" ], hb_CStr( cText ) )
   RETURN oPrompt

// Removes and returns the oldest queued message, or NIL when the queue is
// empty.
FUNCTION CCPROMPT_Dequeue( oPrompt )
   LOCAL cFirst
   IF Empty( oPrompt[ "queue" ] )
      RETURN NIL
   ENDIF
   cFirst := oPrompt[ "queue" ][ 1 ]
   hb_ADel( oPrompt[ "queue" ], 1, .T. )
   RETURN cFirst

// Returns .T. when an interruption (Esc or /btw) is pending.
FUNCTION CCPROMPT_Interrupted( oPrompt )
   RETURN oPrompt[ "interrupt" ] != NIL

// Writes a string straight to stdout, bypassing CCREPL_Out (which strips CR
// and rewrites LF). Needed for absolute cursor positioning.
STATIC FUNCTION CCPROMPT_Raw( cText )
   FWrite( hb_GetStdOut(), cText )
   RETURN NIL

// Activates the pinned box: sets the VT scroll region to rows 1..scroll_bottom
// so agent output scrolls above the box, parks the cursor at the bottom of
// that region, and draws the (empty) box. No-op when the region is inactive
// (small console / fallback).
FUNCTION CCPROMPT_Activate( oPrompt )
   LOCAL hReg := oPrompt[ "region" ]
   IF !hReg[ "active" ]
      RETURN oPrompt
   ENDIF
   // ESC[1;<bottom>r  -> set scroll region; cursor then homes to (1,1)
   CCPROMPT_Raw( Chr(27) + "[1;" + LTrim( Str( hReg[ "scroll_bottom" ] ) ) + "r" )
   // park the cursor on the last row of the scroll region
   CCPROMPT_Raw( Chr(27) + "[" + LTrim( Str( hReg[ "scroll_bottom" ] ) ) + ";1H" )
   CCPROMPT_Redraw( oPrompt )
   RETURN oPrompt

// Restores the terminal: clears the scroll region (full screen scrollable
// again) and drops the cursor below where the box was.
FUNCTION CCPROMPT_Teardown( oPrompt )
   LOCAL hReg := oPrompt[ "region" ]
   IF !hReg[ "active" ]
      RETURN oPrompt
   ENDIF
   CCPROMPT_Raw( Chr(27) + "[r" )   // reset scroll region to the whole screen
   RETURN oPrompt

// Redraws the box on the bottom three rows: top frame, the editor line, the
// bottom frame. Recomputes the region from a fresh CCCON_Size() so a resize
// is picked up. Cursor is saved and restored around the draw.
FUNCTION CCPROMPT_Redraw( oPrompt )
   LOCAL hReg, hW, hSz
   hSz := CCCON_Size()
   oPrompt[ "region" ] := CCPROMPT_Region( hSz[ "rows" ], hSz[ "cols" ] )
   hReg := oPrompt[ "region" ]
   IF !hReg[ "active" ]
      RETURN oPrompt
   ENDIF
   hW := CCIN_Window( oPrompt[ "editor" ], CCUI_InputInnerWidth() )
   CCPROMPT_Raw( ;
      Chr(27) + "[s" + ;                                            // save cursor
      Chr(27) + "[" + LTrim( Str( hReg[ "box_top" ] ) ) + ";1H" + ; // to box row 1
      CCUI_FrameTop() + Chr(13) + Chr(10) + ;
      CCUI_InputBoxLine( hW[ "text" ] ) + Chr(13) + Chr(10) + ;
      CCUI_FrameBottom() + ;
      Chr(27) + "[u" )                                              // restore cursor
   RETURN oPrompt

// Non-blocking: drains every pending key into the editor, then redraws the
// box. On Enter the buffer is classified; on Esc an interrupt is recorded.
// Returns an action string: "none", "queued", or "interrupt".
FUNCTION CCPROMPT_Poll( oPrompt )
   LOCAL oEd := oPrompt[ "editor" ], nKey, hC, cAction := "none"
   DO WHILE CCCON_KeyPending()
      nKey := CCCON_ReadKey()
      DO CASE
      CASE nKey == -13                       // Esc -> interrupt, no message
         oPrompt[ "interrupt" ] := { "kind" => "esc", "text" => "" }
         cAction := "interrupt"
      CASE nKey == -1                        // Enter -> classify the buffer
         hC := CCPROMPT_Classify( oEd[ "buf" ] )
         DO CASE
         CASE hC[ "action" ] == "empty"
            // ignore
         CASE hC[ "action" ] == "btw"
            oPrompt[ "interrupt" ] := { "kind" => "btw", "text" => hC[ "text" ] }
            cAction := "interrupt"
         OTHERWISE
            CCPROMPT_Enqueue( oPrompt, hC[ "text" ] )
            cAction := "queued"
         ENDCASE
         oPrompt[ "editor" ] := CCIN_New( "" )
         oEd := oPrompt[ "editor" ]
      CASE nKey == -2 ; CCIN_Backspace( oEd )
      CASE nKey == -3 ; CCIN_Left( oEd )
      CASE nKey == -4 ; CCIN_Right( oEd )
      CASE nKey == -5 ; CCIN_Home( oEd )
      CASE nKey == -6 ; CCIN_End( oEd )
      CASE nKey == -7 ; CCIN_Delete( oEd )
      CASE nKey == -11 ; CCIN_Insert( oEd, Chr(10) )   // Shift+Enter -> newline
      CASE nKey > 0 ; CCIN_Insert( oEd, CCIN_Utf8Chr( nKey ) )
      // other keys (Tab, Up, Down, Ctrl+C, unmapped) are ignored mid-prompt
      ENDCASE
      IF cAction == "interrupt"
         EXIT   // stop draining once an interrupt is seen
      ENDIF
   ENDDO
   CCPROMPT_Redraw( oPrompt )
   RETURN cAction

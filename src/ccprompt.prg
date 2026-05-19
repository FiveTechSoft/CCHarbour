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

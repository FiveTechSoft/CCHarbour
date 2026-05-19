// Raw-mode single-line input editor for the main prompt. This file holds the
// pure buffer-state operations; the raw-mode I/O loop is added in a later
// task. State: { "buf" => <utf-8 text>, "cursor" => <char index> }.
// All operations count UTF-8 characters, not bytes.

// ── History buffer (persists across calls to DSIN_ReadLine) ──────────────
STATIC s_aHistory := {}          // array of history lines, oldest first
STATIC s_nHistoryMax := 50       // maximum entries kept
STATIC s_nHistoryPos := -1       // -1 = not navigating; 0 = most recent, 1 = older...
STATIC s_cHistoryDraft := ""     // saved draft text when entering history navigation

// Adds a line to the history buffer. Empty lines and exact duplicates of the
// most recent entry are ignored. The buffer never exceeds s_nHistoryMax.
FUNCTION DSIN_HistoryAdd( cText )
   LOCAL cTrim := AllTrim( hb_CStr( cText ) )
   IF Empty( cTrim )
      RETURN NIL
   ENDIF
   // skip if it's the same as the most recent entry
   IF Len( s_aHistory ) > 0 .AND. ATail( s_aHistory ) == cTrim
      RETURN NIL
   ENDIF
   AAdd( s_aHistory, cTrim )
   // trim the oldest when over the limit
   IF Len( s_aHistory ) > s_nHistoryMax
      hb_ADel( s_aHistory, 1, .T. )
   ENDIF
   RETURN NIL

// Resets the navigation position back to "current draft" mode.
FUNCTION DSIN_HistoryReset()
   s_nHistoryPos := -1
   s_cHistoryDraft := ""
   RETURN NIL

// Returns the previous history entry (one step back in time), or NIL when
// there is no more history to go back to. Also saves the current draft on
// the first Up press.
FUNCTION DSIN_HistoryPrev( cCurrentBuf )
   LOCAL nLen := Len( s_aHistory )
   IF nLen == 0
      RETURN NIL
   ENDIF
   IF s_nHistoryPos == -1
      // first Up: save the current draft
      s_cHistoryDraft := hb_CStr( cCurrentBuf )
   ENDIF
   IF s_nHistoryPos < nLen - 1
      s_nHistoryPos++
      RETURN s_aHistory[ nLen - s_nHistoryPos ]
   ENDIF
   // already at the oldest entry
   RETURN NIL

// Returns the next history entry (one step forward toward the present), or
// the saved draft when the bottom is reached.
FUNCTION DSIN_HistoryNext( cCurrentBuf )
   LOCAL nLen := Len( s_aHistory )
   HB_SYMBOL_UNUSED( cCurrentBuf )
   IF s_nHistoryPos <= 0
      // back to draft mode
      s_nHistoryPos := -1
      RETURN s_cHistoryDraft
   ENDIF
   s_nHistoryPos--
   RETURN s_aHistory[ nLen - s_nHistoryPos ]

// Returns the number of history entries currently stored.
FUNCTION DSIN_HistoryCount()
   RETURN Len( s_aHistory )

// Clears all history.
FUNCTION DSIN_HistoryClear()
   s_aHistory := {}
   s_nHistoryPos := -1
   s_cHistoryDraft := ""
   RETURN NIL

// ── Editor state operations ──────────────────────────────────────────────

// A fresh editor state, cursor at the end of the initial text.
FUNCTION DSIN_New( cInitial )
   cInitial := hb_CStr( cInitial )
   RETURN { "buf" => cInitial, "cursor" => hb_UTF8Len( cInitial ) }

// Inserts cChar at the cursor and advances the cursor.
FUNCTION DSIN_Insert( oSt, cChar )
   LOCAL n := oSt[ "cursor" ], cBuf := oSt[ "buf" ]
   oSt[ "buf" ] := hb_UTF8SubStr( cBuf, 1, n ) + cChar + ;
                   hb_UTF8SubStr( cBuf, n + 1, hb_UTF8Len( cBuf ) - n )
   oSt[ "cursor" ] := n + 1
   RETURN oSt

// Deletes the character before the cursor; moves the cursor back. No-op at 0.
FUNCTION DSIN_Backspace( oSt )
   LOCAL n := oSt[ "cursor" ], cBuf := oSt[ "buf" ]
   IF n > 0
      oSt[ "buf" ] := hb_UTF8SubStr( cBuf, 1, n - 1 ) + ;
                      hb_UTF8SubStr( cBuf, n + 1, hb_UTF8Len( cBuf ) - n )
      oSt[ "cursor" ] := n - 1
   ENDIF
   RETURN oSt

// Deletes the character at the cursor. No-op at the end.
FUNCTION DSIN_Delete( oSt )
   LOCAL n := oSt[ "cursor" ], cBuf := oSt[ "buf" ], nLen := hb_UTF8Len( oSt[ "buf" ] )
   IF n < nLen
      oSt[ "buf" ] := hb_UTF8SubStr( cBuf, 1, n ) + ;
                      hb_UTF8SubStr( cBuf, n + 2, nLen - n - 1 )
   ENDIF
   RETURN oSt

// Cursor movement, all clamped to [0, len].
FUNCTION DSIN_Left( oSt )
   IF oSt[ "cursor" ] > 0
      oSt[ "cursor" ] := oSt[ "cursor" ] - 1
   ENDIF
   RETURN oSt

FUNCTION DSIN_Right( oSt )
   IF oSt[ "cursor" ] < hb_UTF8Len( oSt[ "buf" ] )
      oSt[ "cursor" ] := oSt[ "cursor" ] + 1
   ENDIF
   RETURN oSt

FUNCTION DSIN_Home( oSt )
   oSt[ "cursor" ] := 0
   RETURN oSt

FUNCTION DSIN_End( oSt )
   oSt[ "cursor" ] := hb_UTF8Len( oSt[ "buf" ] )
   RETURN oSt

// Returns { "text" => <slice that fits nWidth columns>, "col" => <cursor
// column within the slice> }. When the buffer fits, the slice is the whole
// buffer. When it is wider, it scrolls so the cursor stays visible.
FUNCTION DSIN_Window( oSt, nWidth )
   LOCAL nLen := hb_UTF8Len( oSt[ "buf" ] ), nCur := oSt[ "cursor" ], nOff
   IF nLen <= nWidth
      RETURN { "text" => oSt[ "buf" ], "col" => nCur }
   ENDIF
   nOff := iif( nCur > nWidth, nCur - nWidth, 0 )
   RETURN { "text" => hb_UTF8SubStr( oSt[ "buf" ], nOff + 1, nWidth ), ;
            "col" => nCur - nOff }

// Encodes a Unicode codepoint (BMP) as a UTF-8 character string.
FUNCTION DSIN_Utf8Chr( n )
   DO CASE
   CASE n < 128
      RETURN Chr( n )
   CASE n < 2048
      RETURN Chr( hb_bitOr( 192, hb_bitShift( n, -6 ) ) ) + ;
             Chr( hb_bitOr( 128, hb_bitAnd( n, 63 ) ) )
   OTHERWISE
      RETURN Chr( hb_bitOr( 224, hb_bitShift( n, -12 ) ) ) + ;
             Chr( hb_bitOr( 128, hb_bitAnd( hb_bitShift( n, -6 ), 63 ) ) ) + ;
             Chr( hb_bitOr( 128, hb_bitAnd( n, 63 ) ) )
   ENDCASE
   RETURN ""

// NOTE: requires DSUI_ColorOn() (VT enabled) — the editor positions the cursor
// with DSUI_VT sequences; without VT the sentinel path is taken instead.
// Reads one line through the raw-mode input box. cInitial pre-fills the buffer
// (the suggested next prompt). Returns the typed string, or NIL on Ctrl-C /
// end of input. Returns the sentinel hash { "no_console" => .T. } when there
// is no interactive console, so the caller can fall back to a cooked reader.
FUNCTION DSIN_ReadLine( cInitial )
   LOCAL oSt, nKey, hW, cResult := NIL, lDone := .F., cHistoryLine

   // the box editor needs VT cursor control; without it (no console, or a
   // console that rejected virtual-terminal mode) fall back to the cooked
   // reader via the sentinel.
   IF !DSUI_ColorOn() .OR. !DSCON_RawMode( .T. )
      RETURN { "no_console" => .T. }
   ENDIF

   // when a suggestion is provided, pre-fill the buffer.
   // do NOT add the suggestion to history — it is a machine-generated prompt,
   // not user input. Only explicit user submits go into history.
   oSt := DSIN_New( hb_CStr( cInitial ) )
   DSIN_HistoryReset()

   // draw the box: top border, prompt line, bottom border, hint; then move
   // the cursor up onto the prompt line (hint -> bottom -> prompt = up 2).
   hW := DSIN_Window( oSt, DSUI_InputInnerWidth() )
   DSREPL_Out( Chr(10) + DSUI_FrameTop() + Chr(10) + ;
               DSUI_InputBoxLine( hW[ "text" ] ) + Chr(10) + ;
               DSUI_FrameBottom() + Chr(10) + ;
               DSUI_InputHint() + DSUI_VT( "2A" ) )

   DO WHILE !lDone
      // place the terminal cursor at the editing column: column 1 is the
      // left border, then a space, then "> " -> text starts at column 5.
      hW := DSIN_Window( oSt, DSUI_InputInnerWidth() )
      DSREPL_Out( DSUI_VT( "1G" ) + ;
                  DSUI_VT( LTrim( Str( 5 + hW[ "col" ] ) ) + "G" ) )
      nKey := DSCON_ReadKey()
      DO CASE
      CASE nKey == 0 .OR. nKey == -8
         cResult := NIL
         DSIN_HistoryReset()
         lDone := .T.
      CASE nKey == -1
         // Enter: submit the line (add to history, return it)
         DSIN_HistoryAdd( oSt[ "buf" ] )
         cResult := oSt[ "buf" ]
         DSIN_HistoryReset()
         lDone := .T.
      CASE nKey == -2
         DSIN_Backspace( oSt )
      CASE nKey == -3
         DSIN_Left( oSt )
      CASE nKey == -4
         DSIN_Right( oSt )
      CASE nKey == -5
         DSIN_Home( oSt )
      CASE nKey == -6
         DSIN_End( oSt )
      CASE nKey == -7
         DSIN_Delete( oSt )
      CASE nKey == -9
         // Up: navigate to previous history entry
         cHistoryLine := DSIN_HistoryPrev( oSt[ "buf" ] )
         IF cHistoryLine != NIL
            oSt[ "buf" ] := cHistoryLine
            oSt[ "cursor" ] := hb_UTF8Len( cHistoryLine )
         ENDIF
      CASE nKey == -10
         // Down: navigate to next history entry or back to draft
         cHistoryLine := DSIN_HistoryNext( oSt[ "buf" ] )
         IF cHistoryLine != NIL
            oSt[ "buf" ] := cHistoryLine
            oSt[ "cursor" ] := hb_UTF8Len( cHistoryLine )
         ENDIF
      CASE nKey > 0
         DSIN_Insert( oSt, DSIN_Utf8Chr( nKey ) )
      // nKey == -99 (an unmapped key) matches no case above and is ignored
      ENDCASE
      // redraw the prompt line in place
      hW := DSIN_Window( oSt, DSUI_InputInnerWidth() )
      DSREPL_Out( DSUI_VT( "1G" ) + DSUI_InputBoxLine( hW[ "text" ] ) )
   ENDDO

   DSCON_RawMode( .F. )
   // step the cursor below the box (prompt -> bottom -> hint -> next line)
   DSREPL_Out( DSUI_VT( "2B" ) + Chr(10) )
   RETURN cResult

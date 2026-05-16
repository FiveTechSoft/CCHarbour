FUNCTION DSSSE_New()
   RETURN { "buffer" => "", "closed" => .F. }

FUNCTION DSSSE_Feed( oP, cChunk, bEmit )
   LOCAL nPos, cLine
   oP[ "buffer" ] += cChunk
   DO WHILE ( nPos := At( Chr(10), oP[ "buffer" ] ) ) > 0
      cLine := Left( oP[ "buffer" ], nPos - 1 )
      oP[ "buffer" ] := SubStr( oP[ "buffer" ], nPos + 1 )
      cLine := StrTran( cLine, Chr(13), "" )
      DSSSE_Line( cLine, bEmit )
   ENDDO
   RETURN NIL

STATIC FUNCTION DSSSE_Line( cLine, bEmit )
   LOCAL cData, xJson, hChoice, hDelta
   IF Empty( cLine ) .OR. !( Left( cLine, 5 ) == "data:" )
      RETURN NIL   // comments, blank keep-alive lines, event: lines -> ignored
   ENDIF
   cData := AllTrim( SubStr( cLine, 6 ) )
   IF cData == "[DONE]"
      Eval( bEmit, { "type" => "done" } )
      RETURN NIL
   ENDIF
   xJson := hb_jsonDecode( cData )
   IF !( ValType( xJson ) == "H" )
      RETURN NIL   // unparseable / non-object -> skip silently
   ENDIF
   IF hb_HHasKey( xJson, "choices" ) .AND. Len( xJson[ "choices" ] ) > 0
      hChoice := xJson[ "choices" ][ 1 ]
      IF hb_HHasKey( hChoice, "delta" )
         hDelta := hChoice[ "delta" ]
         IF hb_HHasKey( hDelta, "content" ) .AND. ;
            ValType( hDelta[ "content" ] ) == "C" .AND. ;
            !Empty( hDelta[ "content" ] )
            Eval( bEmit, { "type" => "text_delta", "text" => hDelta[ "content" ] } )
         ENDIF
      ENDIF
   ENDIF
   RETURN NIL

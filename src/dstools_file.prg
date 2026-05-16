// read: returns the line-numbered content of a text file.
FUNCTION DSTool_Read()
   RETURN { "name" => "read", ;
            "description" => "Read a text file from disk. Returns line-numbered content.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "path" => { "type" => "string", ;
                              "description" => "Path of the file to read" }, ;
                  "offset" => { "type" => "integer", ;
                                "description" => "Number of leading lines to skip" }, ;
                  "max_lines" => { "type" => "integer", ;
                                   "description" => "Maximum lines to return (default 2000)" } }, ;
               "required" => { "path" } }, ;
            "handler" => {| hArgs | DSTool_ReadRun( hArgs ) } }

STATIC FUNCTION DSTool_ReadRun( hArgs )
   LOCAL cPath, cText, aLines, nOffset, nMax, nFrom, nTo, i, cLine
   LOCAL cOut := "", nShown := 0
   cPath := hb_CStr( hArgs[ "path" ] )
   IF !hb_FileExists( cPath )
      RETURN "Error: file not found: " + cPath
   ENDIF
   cText  := hb_MemoRead( cPath )
   aLines := hb_ATokens( cText, Chr(10) )
   FOR i := 1 TO Len( aLines )
      aLines[ i ] := StrTran( aLines[ i ], Chr(13), "" )
   NEXT
   nOffset := iif( hb_HHasKey( hArgs, "offset" ) .AND. ;
                   ValType( hArgs[ "offset" ] ) == "N", Int( hArgs[ "offset" ] ), 0 )
   nMax    := iif( hb_HHasKey( hArgs, "max_lines" ) .AND. ;
                   ValType( hArgs[ "max_lines" ] ) == "N", Int( hArgs[ "max_lines" ] ), 2000 )
   nFrom := nOffset + 1
   nTo   := Min( Len( aLines ), nFrom + nMax - 1 )
   FOR i := nFrom TO nTo
      cLine := aLines[ i ]
      IF Len( cLine ) > 2000
         cLine := Left( cLine, 2000 ) + "..."
      ENDIF
      cOut += Str( i, 6 ) + Chr(9) + cLine + Chr(10)
      nShown++
   NEXT
   IF nTo < Len( aLines )
      cOut += "[truncated: " + LTrim( Str( Len( aLines ) - nTo ) ) + " more lines]" + Chr(10)
   ENDIF
   IF nShown == 0
      RETURN "(empty, or offset past end of file)"
   ENDIF
   RETURN cOut

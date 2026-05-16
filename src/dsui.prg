// Classifies a line of REPL input. Returns:
//   { "type" => "exit"|"clear"|"help"|"message"|"empty", "text" => <trimmed> }
FUNCTION DSUI_ParseCommand( cLine )
   LOCAL cTrim := AllTrim( hb_CStr( cLine ) )
   DO CASE
   CASE Empty( cTrim )
      RETURN { "type" => "empty", "text" => "" }
   CASE Lower( cTrim ) == "/exit" .OR. Lower( cTrim ) == "/quit"
      RETURN { "type" => "exit", "text" => cTrim }
   CASE Lower( cTrim ) == "/clear"
      RETURN { "type" => "clear", "text" => cTrim }
   CASE Lower( cTrim ) == "/help"
      RETURN { "type" => "help", "text" => cTrim }
   ENDCASE
   RETURN { "type" => "message", "text" => cTrim }

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
      RETURN Chr(10) + "  -> " + hb_CStr( hEv[ "name" ] ) + " " + ;
             hb_CStr( hEv[ "arguments" ] ) + Chr(10)
   CASE cType == "tool_result"
      RETURN "  <- " + DSUI_Summarize( hb_CStr( hEv[ "content" ] ), 80 ) + Chr(10)
   CASE cType == "error"
      RETURN Chr(10) + "!! error: " + hb_CStr( hEv[ "message" ] ) + Chr(10)
   ENDCASE
   RETURN ""

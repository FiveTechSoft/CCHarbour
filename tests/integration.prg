// Real-network smoke test. Runs only when DEEPSEEK_API_KEY is set.
// Build: hbmk2 -mt -gtcgi -otests/integration src/dsconfig.prg src/dssse.prg ;
//        src/dshttp.prg src/dsapi.prg tests/integration.prg
//        (-gtcgi routes console output to stdout so it is capturable)
// Transport is curl.exe (see src/dshttp.prg) -- curl.exe must be in PATH.
FUNCTION Main( cModel )
   LOCAL oClient, hResult

   IF Empty( hb_GetEnv( "DEEPSEEK_API_KEY" ) )
      ? "SKIP - DEEPSEEK_API_KEY not set"
      RETURN NIL
   ENDIF
   IF Empty( cModel )
      cModel := "deepseek-chat"
   ENDIF

   oClient := DS_Client( { "model" => cModel } )
   ? "Requesting model: " + cModel
   hResult := DS_ChatCompletion( oClient, ;
      { { "role" => "user", "content" => "Reply with the single word: pong" } }, ;
      {=>}, ;
      {| hEv | iif( hEv[ "type" ] == "text_delta", ;
                    ( OutStd( hEv[ "text" ] ), NIL ), NIL ) } )
   ? ""
   IF hResult[ "success" ]
      ? "OK - finish=" + hb_CStr( hResult[ "finish_reason" ] )
      ErrorLevel( 0 )
   ELSE
      ? "FAIL - " + hb_CStr( hResult[ "error_type" ] ) + ": " + ;
        hb_CStr( hResult[ "message" ] )
      ErrorLevel( 1 )
   ENDIF
   RETURN NIL

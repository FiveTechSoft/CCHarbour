// Visual check of the GUI-style console cards (CCUI_Card* / cost report).
// Build: hbmk2 tests\test_cards.prg src\ccui.prg
PROCEDURE Main()
   LOCAL hUsage := { "prompt_tokens" => 152000, "completion_tokens" => 8400, ;
                     "prompt_cache_hit_tokens" => 120000 }
   CCUI_SetColor( .T. )
   OutStd( Chr(10) + "-- reply card --" + Chr(10) )
   OutStd( CCUI_Card( "Hola, esta es la respuesta del agente" + Chr(10) + ;
           "con " + Chr(27) + "[1mnegrita interior" + Chr(27) + "[0m y mas texto" + Chr(10) + ;
           "como una card del GUI", "card", 60 ) + Chr(10) )
   OutStd( Chr(10) + "-- thinking card --" + Chr(10) )
   OutStd( CCUI_CardLine( "razonando sobre el problema...", "card_think", 60 ) + Chr(10) )
   OutStd( Chr(10) + "-- error card --" + Chr(10) )
   OutStd( CCUI_RenderEvent( { "type" => "error", ;
           "message" => "HTTP 500 - server blew up" } ) )
   OutStd( Chr(10) + "-- cost card --" + Chr(10) )
   OutStd( CCUI_CostReport( hUsage ) )
RETURN

// stubs for ccui externals not exercised by this test
FUNCTION CCREPL_LeanMode() ; RETURN .F.
FUNCTION CCSKILL_List() ; RETURN {}
FUNCTION CCTODO_IsBlocked() ; RETURN .F.
FUNCTION CCREPL_Cols() ; RETURN 100

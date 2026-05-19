// Creates a fresh tool registry with all builtin tools registered.
// hKeys (optional): { tavily => <api key>, github => <token> } — captured by
// the web/github tool handlers. Omitting it leaves those keys empty; the
// affected tools then return a clear error at call time.
FUNCTION DSTools_Registry( hKeys )
   LOCAL oReg := {=>}
   IF ValType( hKeys ) != "H"
      hKeys := {=>}
   ENDIF
   DSTools_Register( oReg, DSTool_Read() )
   DSTools_Register( oReg, DSTool_Write() )
   DSTools_Register( oReg, DSTool_Edit() )
   DSTools_Register( oReg, DSTool_Glob() )
   DSTools_Register( oReg, DSTool_Grep() )
   DSTools_Register( oReg, DSTool_Shell() )
   DSTools_Register( oReg, DSTool_WebSearch( hb_HGetDef( hKeys, "tavily", "" ) ) )
   DSTools_Register( oReg, DSTool_WebFetch() )
   DSTools_Register( oReg, DSTool_GithubRead( hb_HGetDef( hKeys, "github", "" ) ) )
   DSTools_Register( oReg, DSTool_GithubWrite( hb_HGetDef( hKeys, "github", "" ) ) )
   DSTools_Register( oReg, DSTool_Memory( "memory.md" ) )
   RETURN oReg

// Adds a tool record to the registry, keyed by its name.
// hTool: { name, description, parameters, handler }.
FUNCTION DSTools_Register( oReg, hTool )
   oReg[ hTool[ "name" ] ] := hTool
   RETURN oReg

// Returns the OpenAI "tools" array for every registered tool.
FUNCTION DSTools_Schemas( oReg )
   LOCAL aOut := {}, cKey, hTool
   FOR EACH cKey IN hb_HKeys( oReg )
      hTool := oReg[ cKey ]
      AAdd( aOut, { "type" => "function", ;
                    "function" => { "name" => hTool[ "name" ], ;
                                    "description" => hTool[ "description" ], ;
                                    "parameters" => hTool[ "parameters" ] } } )
   NEXT
   RETURN aOut

// Returns the executor codeblock { |cName,cArgsJson| -> cResultString }.
// It plugs straight into DS_AgentRun's hOpts["tool_executor"].
FUNCTION DSTools_Executor( oReg )
   RETURN {| cName, cArgsJson | DSTools_Dispatch( oReg, cName, cArgsJson ) }

// Looks up a tool, validates arguments, runs the handler under an error net.
STATIC FUNCTION DSTools_Dispatch( oReg, cName, cArgsJson )
   LOCAL hTool, xArgs, cReq, cResult, oErr
   IF !hb_HHasKey( oReg, cName )
      RETURN "Error: unknown tool '" + hb_CStr( cName ) + "'"
   ENDIF
   hTool := oReg[ cName ]
   xArgs := hb_jsonDecode( hb_CStr( cArgsJson ) )
   IF ValType( xArgs ) != "H"
      RETURN "Error: invalid arguments JSON"
   ENDIF
   IF hb_HHasKey( hTool[ "parameters" ], "required" )
      FOR EACH cReq IN hTool[ "parameters" ][ "required" ]
         IF !hb_HHasKey( xArgs, cReq )
            RETURN "Error: missing required argument '" + cReq + "'"
         ENDIF
      NEXT
   ENDIF
   BEGIN SEQUENCE WITH {| o | Break( o ) }
      cResult := Eval( hTool[ "handler" ], xArgs )
   RECOVER USING oErr
      cResult := "Error: tool '" + cName + "' failed: " + ;
                 iif( ValType( oErr ) == "O", hb_CStr( oErr:Description ), "exception" )
   END SEQUENCE
   RETURN cResult

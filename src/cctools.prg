// Creates a fresh tool registry with all builtin tools registered.
// hKeys (optional): { github => <token> } — captured by
// the web/github tool handlers. Omitting it leaves those keys empty; the
// affected tools then return a clear error at call time.
FUNCTION CCTOOLS_Registry( hKeys )
   LOCAL oReg := {=>}
   IF ValType( hKeys ) != "H"
      hKeys := {=>}
   ENDIF
   CCTOOLS_Register( oReg, CCTool_Read() )
   CCTOOLS_Register( oReg, CCTool_Write() )
   CCTOOLS_Register( oReg, CCTool_Edit() )
   CCTOOLS_Register( oReg, CCTool_Glob() )
   CCTOOLS_Register( oReg, CCTool_Grep() )
   CCTOOLS_Register( oReg, CCTool_Shell( hb_HGetDef( hKeys, "co_author", "" ) ) )
   CCTOOLS_Register( oReg, CCTool_WebSearch() )
   CCTOOLS_Register( oReg, CCTool_WebFetch() )
   CCTOOLS_Register( oReg, CCTool_GithubRead( hb_HGetDef( hKeys, "github", "" ) ) )
   CCTOOLS_Register( oReg, CCTool_GithubWrite( hb_HGetDef( hKeys, "github", "" ) ) )
   CCTOOLS_Register( oReg, CCTool_Memory( "memory.md" ) )
   RETURN oReg

// Adds a tool record to the registry, keyed by its name.
// hTool: { name, description, parameters, handler }.
FUNCTION CCTOOLS_Register( oReg, hTool )
   oReg[ hTool[ "name" ] ] := hTool
   RETURN oReg

// Returns the OpenAI "tools" array for every registered tool.
FUNCTION CCTOOLS_Schemas( oReg )
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
// It plugs straight into CC_AgentRun's hOpts["tool_executor"].
FUNCTION CCTOOLS_Executor( oReg )
   RETURN {| cName, cArgsJson | CCTOOLS_Dispatch( oReg, cName, cArgsJson ) }

// Looks up a tool, validates arguments, runs the handler under an error net.
STATIC FUNCTION CCTOOLS_Dispatch( oReg, cName, cArgsJson )
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

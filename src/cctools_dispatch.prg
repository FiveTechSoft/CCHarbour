// dispatch_agent: spawns a subagent with its own conversation and a
// filtered tool registry on a self-contained subtask. The parent's main
// loop blocks until the subagent finishes and only the subagent's final
// reply text comes back. Used to delegate exploration / multi-file
// searches / focused subtasks so the parent's context stays small.

FUNCTION CCTool_DispatchAgent()
   RETURN { "name" => "dispatch_agent", ;
            "description" => "Launch an isolated subagent on a specific " + ;
               "task. The subagent has its own conversation and its own " + ;
               "(filtered) tool registry; it returns only its final " + ;
               "answer. Useful for delegating exploration, multi-file " + ;
               "searches, or any self-contained subtask so the parent " + ;
               "agent's context stays focused. agent_type: " + ;
               "'explore' (read-only tools: read, glob, grep, " + ;
               "github_read, memory, use_skill) or " + ;
               "'general' (full toolset, no further dispatch). " + ;
               "Example: { prompt: 'List every cctools_*.prg file and " + ;
               "summarise each in one line', agent_type: 'explore' }", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "prompt" => { "type" => "string", ;
                                "description" => "The task for the subagent" }, ;
                  "agent_type" => { "type" => "string", ;
                                    "description" => "explore | general " + ;
                                       "(default: explore)" } }, ;
               "required" => { "prompt" } }, ;
            "handler" => {| hArgs | CCTool_DispatchRun( hArgs ) } }

STATIC FUNCTION CCTool_DispatchRun( hArgs )
   LOCAL cPrompt, cType, hSet, hCfg, oClient, oReg, aMsgs, hRes
   LOCAL cReply, hMsg, hKeys
   cPrompt := hb_CStr( hArgs[ "prompt" ] )
   IF Empty( cPrompt )
      RETURN "Error: dispatch_agent requires 'prompt'"
   ENDIF
   cType := iif( hb_HHasKey( hArgs, "agent_type" ) .AND. ;
                 ValType( hArgs[ "agent_type" ] ) == "C", ;
                 Lower( hArgs[ "agent_type" ] ), "explore" )
   IF !( cType == "explore" .OR. cType == "general" )
      RETURN "Error: dispatch_agent agent_type must be 'explore' or 'general'"
   ENDIF
   hSet := CCSETTINGS_Load()
   hCfg := CCCFG_Resolve( {=>} )
   IF !hCfg[ "ok" ]
      RETURN "Error: dispatch_agent: no API key configured"
   ENDIF
   oClient := CC_Client( { "model" => hSet[ "model" ], ;
                           "base_url" => hSet[ "base_url" ] } )
   hKeys := { "github"        => CCCFG_ResolveKey( "GITHUB_TOKEN", ;
                                                   "github_token", hSet ), ;
              "co_author"     => hb_HGetDef( hSet, "co_author", "" ), ;
              "shell_timeout" => hb_HGetDef( hSet, "shell_timeout", 30 ) }
   oReg := CCTOOLS_Registry( hKeys )
   CCTOOLS_FilterForAgent( oReg, cType )
   aMsgs := { ;
      { "role" => "system", ;
        "content" => "You are a CCHarbour subagent of type '" + cType + "'. " + ;
           "Complete the task succinctly using the tools you have. The " + ;
           "parent agent will receive ONLY your final reply, so put your " + ;
           "answer in plain text -- no preamble, no 'Suggested next' line, " + ;
           "no chit-chat. Keep it focused and short." }, ;
      { "role" => "user", "content" => cPrompt } }
   hRes := CC_AgentRun( oClient, aMsgs, ;
      { "model"          => hSet[ "model" ], ;
        "tools"          => CCTOOLS_Schemas( oReg ), ;
        "tool_executor"  => CCTOOLS_Executor( oReg ), ;
        "max_iterations" => 10 }, ;
      {| hEv | HB_SYMBOL_UNUSED( hEv ) } )
   IF !hRes[ "success" ]
      RETURN "Subagent failed: " + ;
             hb_CStr( hb_HGetDef( hRes, "error_type", "?" ) ) + ": " + ;
             hb_CStr( hb_HGetDef( hRes, "message", "" ) )
   ENDIF
   cReply := ""
   FOR EACH hMsg IN hRes[ "messages" ]
      IF hMsg[ "role" ] == "assistant" .AND. ;
         hb_HHasKey( hMsg, "content" ) .AND. ;
         ValType( hMsg[ "content" ] ) == "C" .AND. ;
         !Empty( hMsg[ "content" ] )
         cReply := hMsg[ "content" ]
      ENDIF
   NEXT
   RETURN iif( Empty( cReply ), "[subagent returned no text]", cReply )

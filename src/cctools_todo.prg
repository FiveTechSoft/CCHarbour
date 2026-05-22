// todo_write: the agent maintains a visible session task list. Each call
// replaces the whole list; the rendered list is returned so the model and
// the user both see the current state.
FUNCTION CCTool_TodoWrite()
   RETURN { "name" => "todo_write", ;
            "description" => "Maintain a visible task list for multi-step " + ;
               "work. Call with the full list every time -- it replaces the " + ;
               "previous list. Mark each item pending, in_progress or " + ;
               "completed; keep exactly one item in_progress while working.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "todos" => { "type" => "array", ;
                     "description" => "The full task list", ;
                     "items" => { "type" => "object", ;
                        "properties" => { ;
                           "text" => { "type" => "string", ;
                              "description" => "The task description" }, ;
                           "status" => { "type" => "string", ;
                              "description" => "pending, in_progress or completed" } }, ;
                        "required" => { "text", "status" } } } }, ;
               "required" => { "todos" } }, ;
            "handler" => {| hArgs | CCTool_TodoWriteRun( hArgs ) } }

STATIC FUNCTION CCTool_TodoWriteRun( hArgs )
   IF ValType( hArgs[ "todos" ] ) != "A"
      RETURN "Error: 'todos' must be an array"
   ENDIF
   CCTODO_Set( hArgs[ "todos" ] )
   RETURN CCUI_TodoBlock( CCTODO_Get() )

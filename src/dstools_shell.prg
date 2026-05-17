// shell: runs a command through cmd.exe and returns combined output.
// The command always runs via "cmd.exe /c"; there is deliberately no shell
// parameter, since models tend to send it a boolean and break the call.
// No timeout: a hard timeout requires the cancellable background-thread model
// introduced in sub-project #4.
FUNCTION DSTool_Shell()
   RETURN { "name" => "shell", ;
            "description" => "Run a shell command via cmd.exe and return its combined output and exit code.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "command" => { "type" => "string", ;
                                 "description" => "Command line to run" } }, ;
               "required" => { "command" } }, ;
            "handler" => {| hArgs | DSTool_ShellRun( hArgs ) } }

STATIC FUNCTION DSTool_ShellRun( hArgs )
   LOCAL cCommand, cCmdLine, cOut := "", cErr := "", nExit, cResult
   cCommand := hb_CStr( hArgs[ "command" ] )
   cCmdLine := "cmd.exe /c " + cCommand
   nExit := hb_processRun( cCmdLine, , @cOut, @cErr )
   IF nExit == -1
      RETURN "Error: cannot run shell: " + cCmdLine
   ENDIF
   cResult := cOut
   IF !Empty( cErr )
      cResult += cErr
   ENDIF
   IF hb_BLen( cResult ) > 30000
      cResult := hb_BLeft( cResult, 30000 ) + Chr(10) + "[output truncated]" + Chr(10)
   ENDIF
   IF !Empty( cResult ) .AND. !( Right( cResult, 1 ) == Chr(10) )
      cResult += Chr(10)
   ENDIF
   cResult += "[exit code: " + LTrim( Str( nExit ) ) + "]"
   RETURN cResult

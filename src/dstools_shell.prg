// shell: runs a command through a launcher and returns combined output.
// The "shell" argument is the full launcher prefix; default "cmd.exe /c".
// No timeout: a hard timeout requires the cancellable background-thread model
// introduced in sub-project #4.
FUNCTION DSTool_Shell()
   RETURN { "name" => "shell", ;
            "description" => "Run a shell command and return its combined output and exit code.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "command" => { "type" => "string", ;
                                 "description" => "Command line to run" }, ;
                  "shell" => { "type" => "string", ;
                               "description" => "Launcher prefix (default 'cmd.exe /c')" } }, ;
               "required" => { "command" } }, ;
            "handler" => {| hArgs | DSTool_ShellRun( hArgs ) } }

STATIC FUNCTION DSTool_ShellRun( hArgs )
   LOCAL cCommand, cShell, cCmdLine, cOut := "", cErr := "", nExit, cResult
   cCommand := hb_CStr( hArgs[ "command" ] )
   cShell := iif( hb_HHasKey( hArgs, "shell" ) .AND. !Empty( hArgs[ "shell" ] ), ;
                  hb_CStr( hArgs[ "shell" ] ), "cmd.exe /c" )
   cCmdLine := cShell + " " + cCommand
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

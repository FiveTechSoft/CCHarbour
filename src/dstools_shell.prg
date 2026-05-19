// shell: runs a command through cmd.exe and returns combined output.
// The command always runs via "cmd.exe /c"; there is deliberately no shell
// parameter, since models tend to send it a boolean and break the call.
// When cCoAuthor is non-empty, any "git commit" command automatically gets
// a --trailer "Co-authored-by: ..." appended (configurable in settings.json
// under the "co_author" key).
FUNCTION DSTool_Shell( cCoAuthor )
   RETURN { "name" => "shell", ;
            "description" => "Run a shell command via cmd.exe and return its combined output and exit code.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "command" => { "type" => "string", ;
                                 "description" => "Command line to run" } }, ;
               "required" => { "command" } }, ;
            "handler" => {| hArgs | DSTool_ShellRun( hArgs, cCoAuthor ) } }

STATIC FUNCTION DSTool_ShellRun( hArgs, cCoAuthor )
   LOCAL cCommand, cCmdLine, cOut := "", cErr := "", nExit, cResult
   cCommand := hb_CStr( hArgs[ "command" ] )
   // auto-inject co-author trailer on git commit commands
   IF !Empty( cCoAuthor ) .AND. DSTool_IsGitCommit( cCommand )
      cCommand += ' --trailer "Co-authored-by: ' + cCoAuthor + '"'
   ENDIF
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

// Returns .T. when cCmd looks like a "git commit" invocation.
// Checks that the command contains "git commit" and does not already have
// a --trailer or Co-authored-by marker (to avoid double-injection).
STATIC FUNCTION DSTool_IsGitCommit( cCmd )
   LOCAL cLow := Lower( AllTrim( cCmd ) )
   // bail if the user already included a trailer manually
   IF "co-authored-by" $ cLow .OR. "--trailer" $ cLow
      RETURN .F.
   ENDIF
   // detect "git commit" followed by space, end-of-string, or a flag
   RETURN "git commit" $ cLow

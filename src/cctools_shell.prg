#include "fileio.ch"   // F_ERROR

// shell: runs a command through cmd.exe and returns combined output.
// The command always runs via "cmd.exe /c"; there is deliberately no shell
// parameter, since models tend to send it a boolean and break the call.
// When cCoAuthor is non-empty, any "git commit" command automatically gets
// a --trailer "Co-authored-by: ..." appended (configurable in settings.json
// under the "co_author" key).
// nTimeout: max seconds the command may run (0 = no limit).
//           Configurable via "shell_timeout" in settings (default 30).
FUNCTION CCTool_Shell( cCoAuthor, nTimeout )
   IF ValType( nTimeout ) != "N" .OR. nTimeout < 0
      nTimeout := 0
   ENDIF
   RETURN { "name" => "shell", ;
            "description" => "Run a shell command via cmd.exe and return its combined output and exit code.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "command" => { "type" => "string", ;
                                 "description" => "Command line to run" } }, ;
               "required" => { "command" } }, ;
            "handler" => {| hArgs | CCTool_ShellRun( hArgs, cCoAuthor, nTimeout ) } }

STATIC FUNCTION CCTool_ShellRun( hArgs, cCoAuthor, nTimeout )
   LOCAL cCommand, cCmdLine, cOut := "", cErr := "", nExit, cResult
   LOCAL cOutFile, hProc, hIn, hOut, hErr, nStart, lTimedOut := .F.

   cCommand := hb_CStr( hArgs[ "command" ] )

   // auto-inject co-author trailer on git commit commands
   IF !Empty( cCoAuthor ) .AND. CCTool_IsGitCommit( cCommand )
      cCommand += ' --trailer "Co-authored-by: ' + cCoAuthor + '"'
   ENDIF

   IF nTimeout > 0
      // === Timed execution via temp file redirect + polling ===
      // Create a unique temp file for the redirected output, then close
      // our own handle so cmd.exe can write to it.
      cOutFile := ""
      hOut := hb_FTempCreateEx( @cOutFile, hb_DirTemp(), "ccsh", ".out" )
      IF hOut != F_ERROR
         FClose( hOut )
      ENDIF

      // Redirect both stdout and stderr to the temp file.
      // Append a done-marker (with exit code) so we can detect completion
      // without blocking and also capture the real exit code.
      // "call echo" re-parses the line, so %ERRORLEVEL% expands to the code
      // left by the command, not the (parse-time) value before it ran.
      cCmdLine := 'cmd.exe /c (' + cCommand + ') > "' + cOutFile + ;
                  '" 2>&1 & call echo __CC_DONE__%ERRORLEVEL%>> "' + cOutFile + '"'

      hProc := hb_processOpen( cCmdLine, @hIn, @hOut, @hErr )
      IF hProc == F_ERROR
         RETURN "Error: cannot run shell: " + cCmdLine
      ENDIF
      // Close pipes immediately — all output goes to cOutFile
      FClose( hIn )
      FClose( hOut )
      FClose( hErr )

      // Poll for completion or timeout
      nStart := Seconds()
      DO WHILE .T.
         IF hb_FileExists( cOutFile ) .AND. CCTool_HasDoneMarker( cOutFile )
            EXIT   // command finished normally
         ENDIF
         IF Seconds() - nStart >= nTimeout
            lTimedOut := .T.
            EXIT
         ENDIF
         hb_IdleSleep( 0.05 )
      ENDDO

      // If timed out, close the process handle (does not kill it, but
      // lets CCharbour continue; the orphaned cmd.exe will die on its own).
      IF lTimedOut
         hb_processClose( hProc )
      ENDIF

      // Read the output file
      IF hb_FileExists( cOutFile )
         cResult := hb_MemoRead( cOutFile )
         // Extract exit code from done-marker and remove marker line(s)
         nExit := CCTool_StripDoneMarker( @cResult )
         FErase( cOutFile )
         // Remove trailing whitespace left by marker removal
         cResult := RTrim( cResult )
      ELSE
         cResult := ""
         nExit := -1
      ENDIF

      // Append timeout note
      IF lTimedOut
         cResult += Chr( 10 ) + "[timed out after " + LTrim( Str( nTimeout ) ) + ;
                    " seconds]" + Chr( 10 )
      ENDIF
   ELSE
      // === Original approach (no timeout) — uses hb_processRun directly ===
      cCmdLine := "cmd.exe /c " + cCommand
      nExit := hb_processRun( cCmdLine, , @cOut, @cErr )
      IF nExit == -1
         RETURN "Error: cannot run shell: " + cCmdLine
      ENDIF
      cResult := cOut
      IF !Empty( cErr )
         cResult += cErr
      ENDIF
   ENDIF

   // Common output post-processing
   IF hb_BLen( cResult ) > 30000
      cResult := hb_BLeft( cResult, 30000 ) + Chr(10) + "[output truncated]" + Chr(10)
   ENDIF
   IF !Empty( cResult ) .AND. !( Right( cResult, 1 ) == Chr(10) )
      cResult += Chr(10)
   ENDIF
   cResult += "[exit code: " + LTrim( Str( nExit ) ) + "]"
   RETURN cResult

// Returns .T. when the file at cPath contains the done-marker line.
STATIC FUNCTION CCTool_HasDoneMarker( cPath )
   LOCAL cContent
   cContent := hb_MemoRead( cPath )
   RETURN "__CC_DONE__" $ cContent

// Locates the last "__CC_DONE__<digits>" line in cText, removes it, and
// returns the parsed exit code.  Returns -1 if no marker is found.
// cText is updated in-place (by reference).
STATIC FUNCTION CCTool_StripDoneMarker( cText )
   LOCAL aLines, cLine, i, nExit := -1, cMarker
   aLines := hb_ATokens( cText, Chr( 10 ) )
   FOR i := Len( aLines ) TO 1 STEP -1
      cLine := AllTrim( aLines[ i ] )
      IF Left( cLine, 11 ) == "__CC_DONE__"
         cMarker := aLines[ i ]
         hb_ADel( aLines, i, .T. )   // remove the marker line
         // parse optional digits after the marker
         cMarker := SubStr( cLine, 12 )   // everything after "__CC_DONE__"
         IF !Empty( cMarker ) .AND. IsDigit( Left( cMarker, 1 ) )
            nExit := Val( cMarker )
         ELSE
            nExit := 0
         ENDIF
         EXIT
      ENDIF
   NEXT
   IF nExit == -1
      nExit := 0   // no marker found — assume success
   ENDIF
   // Rebuild text without the marker
   cText := ""
   FOR EACH cLine IN aLines
      cText += cLine + Chr( 10 )
   NEXT
   RETURN nExit

// Returns .T. when cCmd looks like a "git commit" invocation.
// Checks that the command contains "git commit" and does not already have
// a --trailer or Co-authored-by marker (to avoid double-injection).
STATIC FUNCTION CCTool_IsGitCommit( cCmd )
   LOCAL cLow := Lower( AllTrim( cCmd ) )
   // bail if the user already included a trailer manually
   IF "co-authored-by" $ cLow .OR. "--trailer" $ cLow
      RETURN .F.
   ENDIF
   // detect "git commit" followed by space, end-of-string, or a flag
   RETURN "git commit" $ cLow

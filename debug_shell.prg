#include "fileio.ch"

PROCEDURE Main()
   LOCAL cOutFile := "", hOut, cCmdLine, hProc, hIn, hErr
   LOCAL hTool, cRes

   // --- step 1: temp file creation ---
   hOut := hb_FTempCreateEx( @cOutFile, hb_DirTemp(), "ccsh", ".out" )
   ? "FTempCreateEx handle:", hOut, " F_ERROR:", F_ERROR
   ? "cOutFile:[" + cOutFile + "]"
   ? "exists after create:", hb_FileExists( cOutFile )
   IF hOut != F_ERROR
      FClose( hOut )
   ENDIF

   // --- step 2: run the cmd line manually ---
   cCmdLine := "cmd.exe /c (echo hello) > " + cOutFile + ;
               " 2>&1 & echo __CC_DONE__%ERRORLEVEL%>> " + cOutFile
   ? "cmdline:[" + cCmdLine + "]"
   hProc := hb_processOpen( cCmdLine, @hIn, @hOut, @hErr )
   ? "processOpen handle:", hProc
   IF hProc != F_ERROR
      FClose( hIn ) ; FClose( hOut ) ; FClose( hErr )
   ENDIF
   hb_IdleSleep( 1.0 )
   ? "exists after run:", hb_FileExists( cOutFile )
   ? "content:[" + hb_MemoRead( cOutFile ) + "]"
   FErase( cOutFile )

   // --- step 3: through the real tool ---
   hTool := CCTool_Shell( "", 5 )
   cRes  := Eval( hTool[ "handler" ], { "command" => "echo hello" } )
   ? "TOOL RESULT:[" + cRes + "]"
   RETURN

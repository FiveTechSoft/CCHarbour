#include "fileio.ch"

PROCEDURE Main()
   LOCAL cOutFile := "", hOut, cCmdLine, hProc, hIn, hErr
   LOCAL nVal, nStart, i := 0

   hOut := hb_FTempCreateEx( @cOutFile, hb_DirTemp(), "ccsh", ".out" )
   IF hOut != F_ERROR
      FClose( hOut )
   ENDIF

   cCmdLine := 'cmd.exe /c (exit 3) > "' + cOutFile + '" 2>&1'
   ? "cmdline:[" + cCmdLine + "]"
   hProc := hb_processOpen( cCmdLine, @hIn, @hOut, @hErr )
   ? "processOpen handle:", hProc
   IF hProc != F_ERROR
      FClose( hIn ) ; FClose( hOut ) ; FClose( hErr )
   ENDIF

   nStart := Seconds()
   DO WHILE .T.
      nVal := hb_processValue( hProc, .F. )
      i++
      IF nVal != -1
         ? "FINISHED after polls=", i, " value=", nVal
         EXIT
      ENDIF
      IF Seconds() - nStart >= 5
         ? "TIMED OUT, last value=", nVal
         EXIT
      ENDIF
      hb_IdleSleep( 0.02 )
   ENDDO

   ? "file content:[" + hb_MemoRead( cOutFile ) + "]"
   FErase( cOutFile )
   RETURN

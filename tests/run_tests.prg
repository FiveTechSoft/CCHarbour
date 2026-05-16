#include "hbclass.ch"

STATIC s_nPass := 0
STATIC s_nFail := 0

FUNCTION Main()
   Test_SSE()
   Test_Config()
   Test_Http()
   Test_Api()
   Test_Agent()
   Test_Tools()
   Test_UI()
   ? ""
   ? "pass: " + LTrim( Str( s_nPass ) ) + "   fail: " + LTrim( Str( s_nFail ) )
   ErrorLevel( iif( s_nFail > 0, 1, 0 ) )
   RETURN NIL

FUNCTION T_Assert( lCond, cName )
   IF lCond
      s_nPass++
      ? "ok   - " + cName
   ELSE
      s_nFail++
      ? "FAIL - " + cName
   ENDIF
   RETURN lCond

FUNCTION T_Equal( xActual, xExpected, cName )
   LOCAL lOk := ( ValType( xActual ) == ValType( xExpected ) ) .AND. ;
                ( hb_CStr( xActual ) == hb_CStr( xExpected ) )
   RETURN T_Assert( lOk, cName + iif( lOk, "", ;
      " (got <" + hb_CStr( xActual ) + "> want <" + hb_CStr( xExpected ) + ">)" ) )

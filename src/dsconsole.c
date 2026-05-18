/* Console-input prefill for CCHarbour.
 *
 * DSCON_PrefillInput( cText ) injects cText (UTF-8) into the Windows console
 * input buffer as key events, so the cooked-mode line editor shows the text
 * as editable pending input. Returns .T. on success, .F. on any failure --
 * it never aborts the program.
 */
#include "hbapi.h"
#include <windows.h>

HB_FUNC( DSCON_PREFILLINPUT )
{
   const char * szUtf8 = hb_parc( 1 );
   HB_BOOL fOk = HB_FALSE;

   if( szUtf8 )
   {
      int nWide = MultiByteToWideChar( CP_UTF8, 0, szUtf8, -1, NULL, 0 );

      if( nWide > 1 )
      {
         WCHAR * pWide = ( WCHAR * ) hb_xgrab( nWide * sizeof( WCHAR ) );

         MultiByteToWideChar( CP_UTF8, 0, szUtf8, -1, pWide, nWide );
         {
            HANDLE hIn = GetStdHandle( STD_INPUT_HANDLE );
            int n = nWide - 1;   /* drop the terminating NUL */
            INPUT_RECORD * pRec = ( INPUT_RECORD * ) hb_xgrab( n * sizeof( INPUT_RECORD ) );
            DWORD nWritten = 0;
            int i;

            for( i = 0; i < n; i++ )
            {
               pRec[ i ].EventType = KEY_EVENT;
               pRec[ i ].Event.KeyEvent.bKeyDown = TRUE;
               pRec[ i ].Event.KeyEvent.wRepeatCount = 1;
               pRec[ i ].Event.KeyEvent.wVirtualKeyCode = 0;
               pRec[ i ].Event.KeyEvent.wVirtualScanCode = 0;
               pRec[ i ].Event.KeyEvent.dwControlKeyState = 0;
               pRec[ i ].Event.KeyEvent.uChar.UnicodeChar = pWide[ i ];
            }

            if( hIn != INVALID_HANDLE_VALUE && hIn != NULL &&
                WriteConsoleInputW( hIn, pRec, ( DWORD ) n, &nWritten ) )
               fOk = HB_TRUE;

            hb_xfree( pRec );
         }
         hb_xfree( pWide );
      }
   }

   hb_retl( fOk );
}

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

/* Raw-mode console input for the CCHarbour line editor. */

/* DSCON_HasConsole() -> .T. when stdin is a real interactive console. */
HB_FUNC( DSCON_HASCONSOLE )
{
   DWORD mode;
   HANDLE h = GetStdHandle( STD_INPUT_HANDLE );
   hb_retl( h != INVALID_HANDLE_VALUE && h != NULL && GetConsoleMode( h, &mode ) );
}

static DWORD    s_dscon_savedMode = 0;
static HB_BOOL  s_dscon_modeSaved = HB_FALSE;

/* DSCON_RawMode( lOn ) -- lOn .T. disables line-input/echo/processed-input on
 * the console (so keystrokes and Ctrl+C arrive as raw events); .F. restores
 * the previously saved mode. Returns .T. on success, .F. on any failure. */
HB_FUNC( DSCON_RAWMODE )
{
   HB_BOOL fOn = hb_parl( 1 );
   HANDLE  h   = GetStdHandle( STD_INPUT_HANDLE );
   HB_BOOL fOk = HB_FALSE;

   if( h != INVALID_HANDLE_VALUE && h != NULL )
   {
      if( fOn )
      {
         DWORD mode;
         if( GetConsoleMode( h, &mode ) )
         {
            s_dscon_savedMode = mode;
            s_dscon_modeSaved = HB_TRUE;
            mode &= ~( ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT );
            if( SetConsoleMode( h, mode ) )
               fOk = HB_TRUE;
         }
      }
      else if( s_dscon_modeSaved )
      {
         if( SetConsoleMode( h, s_dscon_savedMode ) )
            fOk = HB_TRUE;
      }
   }

   hb_retl( fOk );
}

/* DSCON_ReadKey() -- blocks for one key-down event and returns an int:
 *   > 0  the Unicode codepoint of a printable character
 *     0  end of input
 *    -1 Enter  -2 Backspace  -3 Left  -4 Right  -5 Home  -6 End
 *    -7 Delete  -8 Ctrl+C   -99 an unmapped key (caller ignores it). */
HB_FUNC( DSCON_READKEY )
{
   HANDLE       h = GetStdHandle( STD_INPUT_HANDLE );
   INPUT_RECORD rec;
   DWORD        nRead;
   int          result = -99;
   HB_BOOL      done = HB_FALSE;

   if( h == INVALID_HANDLE_VALUE || h == NULL )
   {
      hb_retni( 0 );
      return;
   }

   while( ! done )
   {
      if( ! ReadConsoleInputW( h, &rec, 1, &nRead ) || nRead == 0 )
      {
         result = 0;
         break;
      }
      if( rec.EventType != KEY_EVENT || ! rec.Event.KeyEvent.bKeyDown )
         continue;
      {
         WORD  vk   = rec.Event.KeyEvent.wVirtualKeyCode;
         WCHAR ch   = rec.Event.KeyEvent.uChar.UnicodeChar;
         DWORD cks  = rec.Event.KeyEvent.dwControlKeyState;
         HB_BOOL ctrl = ( cks & ( LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED ) ) != 0;

         if( ctrl && vk == 'C' )         { result = -8; done = HB_TRUE; }
         else if( vk == VK_RETURN )      { result = -1; done = HB_TRUE; }
         else if( vk == VK_BACK )        { result = -2; done = HB_TRUE; }
         else if( vk == VK_LEFT )        { result = -3; done = HB_TRUE; }
         else if( vk == VK_RIGHT )       { result = -4; done = HB_TRUE; }
         else if( vk == VK_HOME )        { result = -5; done = HB_TRUE; }
         else if( vk == VK_END )         { result = -6; done = HB_TRUE; }
         else if( vk == VK_DELETE )      { result = -7; done = HB_TRUE; }
         else if( ch >= 32 )             { result = ( int ) ch; done = HB_TRUE; }
         /* else: a non-printable key with no mapping -> read the next event */
      }
   }

   hb_retni( result );
}

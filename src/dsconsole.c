/* Windows console support for CCHarbour: console detection, raw-mode
 * toggling, and raw key reading for the line editor. */
#include "hbapi.h"
#include <windows.h>

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
         if( SetConsoleMode( h, s_dscon_modeSaved ) )
            fOk = HB_TRUE;
      }
   }

   hb_retl( fOk );
}

/* DSCON_ReadKey() -- blocks for one key-down event and returns an int:
 *   > 0  the Unicode codepoint of a printable character
 *     0  end of input
 *    -1 Enter      -2 Backspace  -3 Left    -4 Right   -5 Home  -6 End
 *    -7 Delete     -8 Ctrl+C     -9 Up      -10 Down   -11 Shift+Enter
 *   -12 Tab
 *   -99 an unmapped key (caller ignores it). */
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
         HB_BOOL ctrl  = ( cks & ( LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED ) ) != 0;
         HB_BOOL shift = ( cks & SHIFT_PRESSED ) != 0;

         if( ctrl && vk == 'C' )         { result = -8; done = HB_TRUE; }
         else if( vk == VK_RETURN && shift )
                                          { result = -11; done = HB_TRUE; }
         else if( vk == VK_RETURN )      { result = -1; done = HB_TRUE; }
         else if( vk == VK_BACK )        { result = -2; done = HB_TRUE; }
         else if( vk == VK_LEFT )        { result = -3; done = HB_TRUE; }
         else if( vk == VK_RIGHT )       { result = -4; done = HB_TRUE; }
         else if( vk == VK_HOME )        { result = -5; done = HB_TRUE; }
         else if( vk == VK_END )         { result = -6; done = HB_TRUE; }
         else if( vk == VK_DELETE )      { result = -7; done = HB_TRUE; }
         else if( vk == VK_UP )          { result = -9; done = HB_TRUE; }
         else if( vk == VK_DOWN )        { result = -10; done = HB_TRUE; }
         else if( vk == VK_TAB )          { result = -12; done = HB_TRUE; }
         else if( ch >= 32 )             { result = ( int ) ch; done = HB_TRUE; }
         /* else: a non-printable key with no mapping -> read the next event */
      }
   }

   hb_retni( result );
}

/* DSCON_PeekCtrlC() -> .T. when a Ctrl+C key event is pending in the
 * console input buffer. The event is consumed and discarded, so a
 * subsequent DSCON_ReadKey will not see it. Non-blocking. */
HB_FUNC( DSCON_PEEKCTRLC )
{
   HANDLE h = GetStdHandle( STD_INPUT_HANDLE );
   DWORD nEvents = 0;
   INPUT_RECORD rec;
   DWORD nRead;
   WORD  vk;
   DWORD cks;
   HB_BOOL ctrl;

   if( h == INVALID_HANDLE_VALUE || h == NULL )
   {
      hb_retl( 0 );
      return;
   }

   if( ! GetNumberOfConsoleInputEvents( h, &nEvents ) || nEvents == 0 )
   {
      hb_retl( 0 );
      return;
   }

   /* Peek at the first pending event */
   if( PeekConsoleInputW( h, &rec, 1, &nRead ) && nRead > 0 )
   {
      if( rec.EventType == KEY_EVENT && rec.Event.KeyEvent.bKeyDown )
      {
         vk   = rec.Event.KeyEvent.wVirtualKeyCode;
         cks  = rec.Event.KeyEvent.dwControlKeyState;
         ctrl = ( cks & ( LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED ) ) != 0;

         if( ctrl && vk == 'C' )
         {
            /* Consume the event so it does not reach ReadLine */
            ReadConsoleInputW( h, &rec, 1, &nRead );
            hb_retl( 1 );
            return;
         }
      }
   }

   hb_retl( 0 );
}

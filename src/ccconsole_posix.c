/* POSIX console support for CCHarbour (macOS + Linux): console detection,
 * raw-mode toggling, and raw key reading for the line editor. */
#include "hbapi.h"
#include "hbapiitm.h"
#include <unistd.h>
#include <termios.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <stdio.h>

static struct termios s_CCCON_savedMode;
static HB_BOOL        s_CCCON_modeSaved = HB_FALSE;

/* CCCON_HasConsole() -> .T. when stdin is a real interactive console. */
HB_FUNC( CCCON_HASCONSOLE )
{
   hb_retl( isatty( STDIN_FILENO ) );
}

/* CCCON_RawMode( lOn ) -- lOn .T. disables line-input/echo/processed-input
 * so keystrokes arrive as raw events; .F. restores saved mode. */
HB_FUNC( CCCON_RAWMODE )
{
   HB_BOOL fOn = hb_parl( 1 );
   HB_BOOL fOk = HB_FALSE;

   if( isatty( STDIN_FILENO ) )
   {
      if( fOn )
      {
         struct termios raw;
         if( tcgetattr( STDIN_FILENO, &s_CCCON_savedMode ) == 0 )
         {
            s_CCCON_modeSaved = HB_TRUE;
            raw = s_CCCON_savedMode;
            raw.c_lflag &= ~( ICANON | ECHO | ISIG );
            raw.c_cc[ VMIN ]  = 1;
            raw.c_cc[ VTIME ] = 0;
            fOk = ( tcsetattr( STDIN_FILENO, TCSAFLUSH, &raw ) == 0 );
         }
      }
      else if( s_CCCON_modeSaved )
      {
         fOk = ( tcsetattr( STDIN_FILENO, TCSAFLUSH, &s_CCCON_savedMode ) == 0 );
      }
   }

   hb_retl( fOk );
}

static int read_one_byte( void )
{
   unsigned char ch;
   if( read( STDIN_FILENO, &ch, 1 ) == 1 )
      return ( int ) ch;
   return -1;
}

/* CCCON_ReadKey() -- blocks for one key event and returns an int:
 *   > 0  the Unicode codepoint of a printable character
 *     0  end of input
 *    -1 Enter      -2 Backspace  -3 Left    -4 Right   -5 Home  -6 End
 *    -7 Delete     -8 Ctrl+C     -9 Up      -10 Down   -11 Shift+Enter
 *   -12 Tab       -14 Ctrl+E
 *   -99 an unmapped key (caller ignores it). */
HB_FUNC( CCCON_READKEY )
{
   int ch = read_one_byte();
   int result = -99;

   if( ch == -1 )
   {
      hb_retni( 0 );
      return;
   }

   if( ch == 3 )
      result = -8;          /* Ctrl+C */
   else if( ch == 5 )
      result = -14;         /* Ctrl+E */
   else if( ch == 13 || ch == 10 )
      result = -1;          /* Enter */
   else if( ch == 127 )
      result = -2;          /* Backspace */
   else if( ch == 9 )
      result = -12;         /* Tab */
   else if( ch == 27 )
   {
      int next = read_one_byte();
      if( next == 91 || next == 79 )
      {
         int third = read_one_byte();
         if( next == 91 )
         {
            switch( third )
            {
               case 65: result = -9;  break;  /* Up */
               case 66: result = -10; break;  /* Down */
               case 67: result = -4;  break;  /* Right */
               case 68: result = -3;  break;  /* Left */
               case 72: result = -5;  break;  /* Home */
               case 70: result = -6;  break;  /* End */
               case 51:
               {
                  int fourth = read_one_byte();
                  if( fourth == 126 )
                     result = -7;     /* Delete */
                  break;
               }
               case 90: result = -12; break;  /* Shift+Tab */
               default: break;
            }
         }
         else if( next == 79 )
         {
            switch( third )
            {
               case 72: result = -5;  break;  /* Home */
               case 70: result = -6;  break;  /* End */
               default: break;
            }
         }
      }
   }
   else if( ch >= 32 )
      result = ch;

   hb_retni( result );
}

/* CCCON_PeekCtrlC() -> .T. when a Ctrl+C is pending in input buffer.
 * The character is consumed. Non-blocking. */
HB_FUNC( CCCON_PEEKCTRLC )
{
   fd_set set;
   struct timeval tv = { 0, 0 };
   FD_ZERO( &set );
   FD_SET( STDIN_FILENO, &set );

   if( select( STDIN_FILENO + 1, &set, NULL, NULL, &tv ) > 0 )
   {
      unsigned char ch;
      if( read( STDIN_FILENO, &ch, 1 ) == 1 && ch == 3 )
      {
         hb_retl( 1 );
         return;
      }
   }
   hb_retl( 0 );
}

/* CCCON_PeekEsc() -> .T. when Escape is pending in input buffer.
 * The character is consumed. Non-blocking. */
HB_FUNC( CCCON_PEEKESC )
{
   fd_set set;
   struct timeval tv = { 0, 0 };
   FD_ZERO( &set );
   FD_SET( STDIN_FILENO, &set );

   if( select( STDIN_FILENO + 1, &set, NULL, NULL, &tv ) > 0 )
   {
      unsigned char ch;
      if( read( STDIN_FILENO, &ch, 1 ) == 1 && ch == 27 )
      {
         hb_retl( 1 );
         return;
      }
   }
   hb_retl( 0 );
}

/* CCCON_Size() -> hash { "rows" => n, "cols" => n } with the terminal size.
 * Falls back to 24x80 when the size cannot be queried. */
HB_FUNC( CCCON_SIZE )
{
   struct winsize ws;
   int rows = 24, cols = 80;
   PHB_ITEM pHash;
   PHB_ITEM pKey;
   PHB_ITEM pVal;

   if( ioctl( STDOUT_FILENO, TIOCGWINSZ, &ws ) == 0 )
   {
      if( ws.ws_row > 0 ) rows = ws.ws_row;
      if( ws.ws_col > 0 ) cols = ws.ws_col;
   }

   pHash = hb_hashNew( NULL );
   pKey  = hb_itemNew( NULL );
   pVal  = hb_itemNew( NULL );
   hb_hashAdd( pHash, hb_itemPutC( pKey, "rows" ), hb_itemPutNI( pVal, rows ) );
   hb_hashAdd( pHash, hb_itemPutC( pKey, "cols" ), hb_itemPutNI( pVal, cols ) );
   hb_itemRelease( pKey );
   hb_itemRelease( pVal );
   hb_itemReturnRelease( pHash );
}

/* CCCON_KeyPending() -> .T. when a key is waiting in the input buffer.
 * Non-blocking; does NOT consume the event. */
HB_FUNC( CCCON_KEYPENDING )
{
   fd_set set;
   struct timeval tv = { 0, 0 };
   FD_ZERO( &set );
   FD_SET( STDIN_FILENO, &set );
   hb_retl( select( STDIN_FILENO + 1, &set, NULL, NULL, &tv ) > 0 );
}

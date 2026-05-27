// Unit and integration tests for the hooks system.
// Pure helpers tested in-process; spawn/log tests touch the filesystem
// under hb_DirTemp() and clean up after themselves.
FUNCTION Test_Hooks()
   LOCAL hSet
   LOCAL cOldCwd, cTmpDir

   // CCHOOKS_ValidEvents
   T_Equal( hb_CStr( CCHOOKS_ValidEvents()[ 1 ] ), "turn_complete", ;
           "hooks: turn_complete is the canonical event" )
   T_Equal( CCHOOKS_IsValidEvent( "turn_complete" ), .T., ;
           "hooks: turn_complete is valid" )
   T_Equal( CCHOOKS_IsValidEvent( "foo" ), .F., ;
           "hooks: 'foo' is not a valid event" )

   // CCHOOKS_List: empty settings
   hSet := { "hooks" => {=>} }
   T_Equal( Len( CCHOOKS_List( hSet, "turn_complete" ) ), 0, ;
           "hooks: list empty when no event" )

   // CCHOOKS_Add appends
   hSet := { "hooks" => {=>} }
   T_Equal( CCHOOKS_Add( hSet, "turn_complete", "echo a" ), .T., ;
           "hooks: add valid event returns .T." )
   T_Equal( Len( hSet[ "hooks" ][ "turn_complete" ] ), 1, ;
           "hooks: add creates array of len 1" )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 1 ], "echo a", ;
           "hooks: add stores cmd verbatim" )
   CCHOOKS_Add( hSet, "turn_complete", "echo b" )
   T_Equal( Len( hSet[ "hooks" ][ "turn_complete" ] ), 2, ;
           "hooks: second add appends" )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 2 ], "echo b", ;
           "hooks: append preserves order" )

   // Add invalid event
   T_Equal( CCHOOKS_Add( hSet, "foo", "echo x" ), .F., ;
           "hooks: add invalid event returns .F." )

   // CCHOOKS_Remove valid + out-of-range
   hSet := { "hooks" => { "turn_complete" => { "a", "b", "c" } } }
   T_Equal( CCHOOKS_Remove( hSet, "turn_complete", 2 ), .T., ;
           "hooks: remove valid idx returns .T." )
   T_Equal( Len( hSet[ "hooks" ][ "turn_complete" ] ), 2, ;
           "hooks: remove shrinks array" )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 1 ], "a", ;
           "hooks: remove preserves earlier" )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 2 ], "c", ;
           "hooks: remove preserves later" )
   T_Equal( CCHOOKS_Remove( hSet, "turn_complete", 99 ), .F., ;
           "hooks: remove out-of-range returns .F." )
   T_Equal( Len( hSet[ "hooks" ][ "turn_complete" ] ), 2, ;
           "hooks: remove out-of-range no mutation" )

   // CCHOOKS_Edit
   hSet := { "hooks" => { "turn_complete" => { "old1", "old2" } } }
   T_Equal( CCHOOKS_Edit( hSet, "turn_complete", 1, "new1" ), .T., ;
           "hooks: edit valid idx returns .T." )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 1 ], "new1", ;
           "hooks: edit replaces at idx" )
   T_Equal( hSet[ "hooks" ][ "turn_complete" ][ 2 ], "old2", ;
           "hooks: edit leaves other entries" )
   T_Equal( CCHOOKS_Edit( hSet, "turn_complete", 99, "x" ), .F., ;
           "hooks: edit out-of-range returns .F." )

   // LogPath returns ".ccharbour/hooks.log" relative to cwd
   T_Equal( CCHOOKS_LogPath(), ".ccharbour" + hb_ps() + "hooks.log", ;
           "hooks: LogPath default" )

   // Log writes only when hooks_log is .T.
   // (use a temp cwd-relative path by stashing cwd, switching, restoring)
   cOldCwd := hb_cwd()
   cTmpDir := hb_DirTemp() + "ccharbour_log_test"
   hb_DirBuild( cTmpDir )
   hb_cwd( cTmpDir )
   // Default settings -> hooks_log .F. -> no file
   FErase( CCHOOKS_LogPath() )
   CCHOOKS_Log( "test line" )
   T_Equal( hb_FileExists( CCHOOKS_LogPath() ), .F., ;
           "hooks: Log no-op when hooks_log disabled" )
   // Enable hooks_log via a real settings.json under .ccharbour/
   hb_DirBuild( ".ccharbour" )
   hb_MemoWrit( ".ccharbour" + hb_ps() + "settings.json", ;
                '{"hooks_log":true}' )
   CCHOOKS_Log( "test line" )
   T_Equal( hb_FileExists( CCHOOKS_LogPath() ), .T., ;
           "hooks: Log writes when hooks_log enabled" )
   T_Assert( "test line" $ hb_MemoRead( CCHOOKS_LogPath() ), ;
            "hooks: Log appends the line" )
   // Cleanup
   FErase( CCHOOKS_LogPath() )
   FErase( ".ccharbour" + hb_ps() + "settings.json" )
   hb_cwd( cOldCwd )

   RETURN NIL

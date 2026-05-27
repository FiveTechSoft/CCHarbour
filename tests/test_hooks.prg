// Unit and integration tests for the hooks system.
// Pure helpers tested in-process; spawn/log tests touch the filesystem
// under hb_DirTemp() and clean up after themselves.
FUNCTION Test_Hooks()
   LOCAL hSet
   LOCAL cOldCwd, cTmpDir
   LOCAL cTmpDir2, cMarker, cCmd, nDeadline
   LOCAL cTmpDir3, cOut

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
   // Append, not overwrite
   CCHOOKS_Log( "first" )
   CCHOOKS_Log( "second" )
   T_Assert( "first" $ hb_MemoRead( CCHOOKS_LogPath() ) .AND. ;
             "second" $ hb_MemoRead( CCHOOKS_LogPath() ), ;
            "hooks: Log appends, does not overwrite" )
   // Cleanup
   FErase( CCHOOKS_LogPath() )
   FErase( ".ccharbour" + hb_ps() + "settings.json" )
   hb_cwd( cOldCwd )

   // Run: no-op when no hooks
   cTmpDir2 := hb_DirTemp() + "ccharbour_run_test"
   hb_DirBuild( cTmpDir2 )
   hb_cwd( cTmpDir2 )
   hb_DirBuild( ".ccharbour" )
   hb_MemoWrit( ".ccharbour" + hb_ps() + "settings.json", "{}" )
   CCHOOKS_Run( "turn_complete", { "status" => "success", ;
      "model" => "m", "tokens" => 0, "duration_ms" => 0 } )
   T_Assert( .T., "hooks: Run with no hooks does not crash" )

   // Run spawns and sets env vars
   cMarker := cTmpDir2 + hb_ps() + "marker.txt"
   FErase( cMarker )
#ifdef __PLATFORM__WINDOWS
   cCmd := "cmd /c echo %CCHARBOUR_STATUS% > " + cMarker
#else
   cCmd := "sh -c 'echo $CCHARBOUR_STATUS > " + cMarker + "'"
#endif
   hb_MemoWrit( ".ccharbour" + hb_ps() + "settings.json", ;
                '{"hooks":{"turn_complete":["' + StrTran( cCmd, "\", "\\" ) + ;
                '"]},"hooks_log":false}' )
   CCHOOKS_Run( "turn_complete", { "status" => "success", ;
      "model" => "m", "tokens" => 1, "duration_ms" => 10 } )
   // Give the spawned process up to 2 seconds to materialise the file.
   nDeadline := hb_MilliSeconds() + 2000
   DO WHILE !hb_FileExists( cMarker ) .AND. hb_MilliSeconds() < nDeadline
      hb_idleSleep( 0.05 )
   ENDDO
   T_Assert( hb_FileExists( cMarker ), ;
            "hooks: Run spawns hook process" )
   T_Assert( "success" $ hb_MemoRead( cMarker ), ;
            "hooks: Run sets CCHARBOUR_STATUS env var" )

   // Cleanup
   FErase( cMarker )
   FErase( ".ccharbour" + hb_ps() + "settings.json" )
   FErase( CCHOOKS_LogPath() )
   hb_cwd( cOldCwd )

   // Invalid event logs a WARN line when hooks_log is on
   hb_DirBuild( cTmpDir2 )
   hb_cwd( cTmpDir2 )
   hb_DirBuild( ".ccharbour" )
   FErase( CCHOOKS_LogPath() )
   hb_MemoWrit( ".ccharbour" + hb_ps() + "settings.json", ;
                '{"hooks_log":true}' )
   CCHOOKS_Run( "bogus_event", { "status" => "success" } )
   T_Assert( hb_FileExists( CCHOOKS_LogPath() ), ;
            "hooks: Run invalid event creates log file" )
   T_Assert( "unknown-event" $ hb_MemoRead( CCHOOKS_LogPath() ), ;
            "hooks: Run invalid event logs WARN" )

   // Cleanup
   FErase( CCHOOKS_LogPath() )
   FErase( ".ccharbour" + hb_ps() + "settings.json" )
   hb_cwd( cOldCwd )

   // ---- Handler tests (CCHOOKS_Render) --------------------------------
   // The /hook REPL command is implemented as a thin wrapper around
   // CCHOOKS_Render in cchooks.prg. We test the renderer directly so
   // we can assert on the rendered text without going through the live
   // REPL output path.

   // Handler: list with no hooks renders an empty block (just header)
   cTmpDir3 := hb_DirTemp() + "ccharbour_handler_test"
   hb_DirBuild( cTmpDir3 )
   hb_cwd( cTmpDir3 )
   hb_DirBuild( ".ccharbour" )
   hb_MemoWrit( ".ccharbour" + hb_ps() + "settings.json", "{}" )
   cOut := CCHOOKS_Render( "list" )
   T_Assert( "turn_complete" $ cOut, ;
            "hooks-handler: list output names the event" )
   T_Assert( "(none)" $ cOut .OR. "no hooks" $ Lower( cOut ), ;
            "hooks-handler: list shows empty marker" )

   // Handler: add valid event persists to settings.json
   cOut := CCHOOKS_Render( "add turn_complete echo persisted" )
   T_Assert( "echo persisted" $ ;
             hb_MemoRead( ".ccharbour" + hb_ps() + "settings.json" ), ;
            "hooks-handler: add persists cmd to settings.json" )

   // Handler: add unknown event yields error containing valid event list
   cOut := CCHOOKS_Render( "add foo bar" )
   T_Assert( "foo" $ cOut .AND. "turn_complete" $ cOut, ;
            "hooks-handler: add unknown event lists valid events" )

   // Handler: remove valid idx pops the entry
   cOut := CCHOOKS_Render( "remove turn_complete 1" )
   T_Assert( !( "echo persisted" $ ;
                hb_MemoRead( ".ccharbour" + hb_ps() + "settings.json" ) ), ;
            "hooks-handler: remove drops the entry" )

   // Handler: edit valid idx swaps the cmd
   CCHOOKS_Render( "add turn_complete echo before" )
   CCHOOKS_Render( "edit turn_complete 1 echo after" )
   T_Assert( "echo after" $ ;
             hb_MemoRead( ".ccharbour" + hb_ps() + "settings.json" ), ;
            "hooks-handler: edit swaps the cmd" )

   // Handler: log subcommand with hooks_log off prints the disabled hint
   cOut := CCHOOKS_Render( "log" )
   T_Assert( "disabled" $ Lower( cOut ), ;
            "hooks-handler: log subcommand hints when disabled" )

   // Handler: test subcommand dispatches CCHOOKS_Run with dummy env
   FErase( cTmpDir3 + hb_ps() + "marker_t.txt" )
#ifdef __PLATFORM__WINDOWS
   cCmd := "cmd /c echo %CCHARBOUR_STATUS% > " + cTmpDir3 + hb_ps() + ;
           "marker_t.txt"
#else
   cCmd := "sh -c 'echo $CCHARBOUR_STATUS > " + cTmpDir3 + hb_ps() + ;
           "marker_t.txt'"
#endif
   CCHOOKS_Render( "remove turn_complete 1" )
   CCHOOKS_Render( "add turn_complete " + cCmd )
   cOut := CCHOOKS_Render( "test turn_complete" )
   nDeadline := hb_MilliSeconds() + 2000
   DO WHILE !hb_FileExists( cTmpDir3 + hb_ps() + "marker_t.txt" ) .AND. ;
            hb_MilliSeconds() < nDeadline
      hb_idleSleep( 0.05 )
   ENDDO
   T_Assert( hb_FileExists( cTmpDir3 + hb_ps() + "marker_t.txt" ), ;
            "hooks-handler: test fires the hook" )
   T_Assert( "success" $ ;
             hb_MemoRead( cTmpDir3 + hb_ps() + "marker_t.txt" ), ;
            "hooks-handler: test passes status=success" )

   // Cleanup
   FErase( ".ccharbour" + hb_ps() + "settings.json" )
   FErase( cTmpDir3 + hb_ps() + "marker_t.txt" )
   hb_cwd( cOldCwd )

   RETURN NIL

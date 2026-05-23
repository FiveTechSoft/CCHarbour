FUNCTION Test_Todo()
   LOCAL aNorm, aList

   // --- CCTODO_Norm ---
   aNorm := CCTODO_Norm( { { "text" => "a", "status" => "bogus" } } )
   T_Equal( aNorm[ 1 ][ "status" ], "pending", "todo: bad status -> pending" )

   aNorm := CCTODO_Norm( { { "text" => "a", "status" => "in_progress" } } )
   T_Equal( aNorm[ 1 ][ "status" ], "in_progress", "todo: valid status kept" )

   aNorm := CCTODO_Norm( { "not a hash", { "text" => "ok", "status" => "pending" } } )
   T_Equal( Len( aNorm ), 1, "todo: non-hash element dropped" )

   aNorm := CCTODO_Norm( { { "status" => "pending" } } )
   T_Equal( Len( aNorm ), 0, "todo: element missing text dropped" )

   aNorm := CCTODO_Norm( "not an array" )
   T_Equal( Len( aNorm ), 0, "todo: non-array input -> empty list" )

   // --- CCTODO_Set / CCTODO_Get round-trip ---
   CCTODO_Set( { { "text" => "first", "status" => "pending" }, ;
                 { "text" => "second", "status" => "completed" } } )
   aList := CCTODO_Get()
   T_Equal( Len( aList ), 2, "todo: set/get round-trips the list" )
   T_Equal( aList[ 1 ][ "text" ], "first", "todo: get keeps item text" )

   // --- CCTODO_HasOpen ---
   CCTODO_Set( { { "text" => "a", "status" => "pending" } } )
   T_Equal( CCTODO_HasOpen(), .T., "todo: pending item -> has open" )

   CCTODO_Set( { { "text" => "a", "status" => "in_progress" } } )
   T_Equal( CCTODO_HasOpen(), .T., "todo: in_progress item -> has open" )

   CCTODO_Set( { { "text" => "a", "status" => "completed" }, ;
                 { "text" => "b", "status" => "completed" } } )
   T_Equal( CCTODO_HasOpen(), .F., "todo: all completed -> no open" )

   CCTODO_Set( {} )
   T_Equal( CCTODO_HasOpen(), .F., "todo: empty list -> no open" )

   // --- new fields: id, active_form, blocked_by ---
   aNorm := CCTODO_Norm( { { "text" => "a", "status" => "in_progress", ;
                             "id" => "t1", ;
                             "active_form" => "Working on a", ;
                             "blocked_by" => { "t0", "x" } } } )
   T_Equal( aNorm[ 1 ][ "id" ], "t1", "todo: id preserved" )
   T_Equal( aNorm[ 1 ][ "active_form" ], "Working on a", ;
            "todo: active_form preserved" )
   T_Equal( Len( aNorm[ 1 ][ "blocked_by" ] ), 2, ;
            "todo: blocked_by preserved" )

   aNorm := CCTODO_Norm( { { "text" => "a", "status" => "pending" } } )
   T_Equal( aNorm[ 1 ][ "id" ], "", "todo: missing id defaults to empty" )
   T_Equal( aNorm[ 1 ][ "active_form" ], "", ;
            "todo: missing active_form defaults to empty" )
   T_Equal( Len( aNorm[ 1 ][ "blocked_by" ] ), 0, ;
            "todo: missing blocked_by defaults to empty array" )

   // --- CCTODO_IsBlocked ---
   aList := CCTODO_Norm( { ;
      { "text" => "build", "status" => "pending", "id" => "build" }, ;
      { "text" => "test",  "status" => "pending", "id" => "test", ;
        "blocked_by" => { "build" } } } )
   T_Equal( CCTODO_IsBlocked( aList[ 2 ], aList ), .T., ;
            "todo: depends on pending blocker -> blocked" )
   aList[ 1 ][ "status" ] := "completed"
   T_Equal( CCTODO_IsBlocked( aList[ 2 ], aList ), .F., ;
            "todo: depends on completed blocker -> not blocked" )

   T_Equal( CCTODO_IsBlocked( ;
      { "text" => "x", "status" => "pending" }, aList ), .F., ;
      "todo: missing blocked_by key -> not blocked" )

   RETURN NIL

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

   RETURN NIL

FUNCTION Test_Perm()
   LOCAL bGate, bInner, hPerm, nInner, nAsk

   // allow -> inner runs
   nInner := 0
   bInner := {| cN, cA | HB_SYMBOL_UNUSED( cN ), HB_SYMBOL_UNUSED( cA ), ;
                         nInner++, "ran" }
   bGate := CCPERM_Gate( bInner, { "read" => "allow" }, NIL )
   T_Equal( Eval( bGate, "read", "{}" ), "ran", "perm: allow runs inner" )
   T_Equal( nInner, 1, "perm: allow called inner once" )

   // deny -> inner never runs
   nInner := 0
   bGate := CCPERM_Gate( bInner, { "shell" => "deny" }, NIL )
   T_Assert( "denied by policy" $ Eval( bGate, "shell", "{}" ), ;
             "perm: deny returns policy error" )
   T_Equal( nInner, 0, "perm: deny did not call inner" )

   // ask + "y" -> inner runs
   nInner := 0
   bGate := CCPERM_Gate( bInner, { "shell" => "ask" }, ;
      {| cN, cA | HB_SYMBOL_UNUSED( cN ), HB_SYMBOL_UNUSED( cA ), "y" } )
   T_Equal( Eval( bGate, "shell", "{}" ), "ran", "perm: ask+y runs inner" )

   // ask + "n" -> denied
   nInner := 0
   bGate := CCPERM_Gate( bInner, { "shell" => "ask" }, ;
      {| cN, cA | HB_SYMBOL_UNUSED( cN ), HB_SYMBOL_UNUSED( cA ), "n" } )
   T_Assert( "denied by user" $ Eval( bGate, "shell", "{}" ), ;
             "perm: ask+n returns user error" )
   T_Equal( nInner, 0, "perm: ask+n did not call inner" )

   // ask + "a" -> session upgrade: inner runs twice, ask asked once
   nInner := 0
   nAsk := 0
   bGate := CCPERM_Gate( bInner, { "shell" => "ask" }, ;
      {| cN, cA | HB_SYMBOL_UNUSED( cN ), HB_SYMBOL_UNUSED( cA ), nAsk++, "a" } )
   Eval( bGate, "shell", "{}" )
   Eval( bGate, "shell", "{}" )
   T_Equal( nAsk, 1, "perm: 'a' asks only once" )
   T_Equal( nInner, 2, "perm: 'a' runs inner both times" )

   // ask with no bAsk -> fails closed (deny)
   nInner := 0
   bGate := CCPERM_Gate( bInner, { "shell" => "ask" }, NIL )
   T_Assert( "denied" $ Eval( bGate, "shell", "{}" ), "perm: ask + no bAsk denies" )
   T_Equal( nInner, 0, "perm: ask + no bAsk did not call inner" )

   // invalid mode -> treated as ask (here, no bAsk -> deny)
   bGate := CCPERM_Gate( bInner, { "shell" => "maybe" }, NIL )
   T_Assert( "denied" $ Eval( bGate, "shell", "{}" ), "perm: invalid mode treated as ask" )

   // caller's permissions hash is not mutated by an "a" upgrade
   hPerm := { "shell" => "ask" }
   bGate := CCPERM_Gate( bInner, hPerm, ;
      {| cN, cA | HB_SYMBOL_UNUSED( cN ), HB_SYMBOL_UNUSED( cA ), "a" } )
   Eval( bGate, "shell", "{}" )
   T_Equal( hPerm[ "shell" ], "ask", "perm: caller hash not mutated" )
   RETURN NIL

// Wraps a raw tool executor with a permission gate.
// bInner       : the raw executor, {|cName,cArgsJson| -> cString}.
// hPermissions : { toolName => "allow"|"deny"|"ask" }.
// bAsk         : optional {|cName,cArgsJson| -> "y"|"n"|"a"}.
// Returns a gated executor with the same {|cName,cArgsJson| -> cString} contract.
FUNCTION CCPERM_Gate( bInner, hPermissions, bAsk )
   LOCAL hPerm := CCPERM_CloneModes( hPermissions )
   RETURN {| cName, cArgsJson | ;
      CCPERM_Decide( hPerm, bInner, bAsk, cName, cArgsJson ) }

// Copies the caller's permission hash so an "a" upgrade never mutates it.
STATIC FUNCTION CCPERM_CloneModes( hPermissions )
   LOCAL hOut := {=>}, cKey
   IF ValType( hPermissions ) == "H"
      FOR EACH cKey IN hb_HKeys( hPermissions )
         hOut[ cKey ] := hPermissions[ cKey ]
      NEXT
   ENDIF
   RETURN hOut

// Decides allow/deny for one call; "a" upgrades the tool to allow for the session.
STATIC FUNCTION CCPERM_Decide( hPerm, bInner, bAsk, cName, cArgsJson )
   LOCAL cMode, cAns
   // ask_user / todo_write only drive the UI -- inherently consented, never gated
   IF cName == "ask_user" .OR. cName == "todo_write"
      RETURN Eval( bInner, cName, cArgsJson )
   ENDIF
   cMode := iif( hb_HHasKey( hPerm, cName ), hPerm[ cName ], "ask" )
   IF !( cMode == "allow" .OR. cMode == "deny" .OR. cMode == "ask" )
      cMode := "ask"
   ENDIF
   DO CASE
   CASE cMode == "allow"
      RETURN Eval( bInner, cName, cArgsJson )
   CASE cMode == "deny"
      RETURN "Error: tool '" + hb_CStr( cName ) + "' denied by policy"
   ENDCASE
   // cMode == "ask"
   cAns := iif( bAsk == NIL, "n", CCPERM_Norm( Eval( bAsk, cName, cArgsJson ) ) )
   DO CASE
   CASE cAns == "y"
      RETURN Eval( bInner, cName, cArgsJson )
   CASE cAns == "a"
      hPerm[ cName ] := "allow"
      RETURN Eval( bInner, cName, cArgsJson )
   ENDCASE
   RETURN "Error: tool '" + hb_CStr( cName ) + "' denied by user"

// Normalises an ask answer to a single lowercase character; non-strings -> "n".
STATIC FUNCTION CCPERM_Norm( xAns )
   LOCAL cAns
   IF ValType( xAns ) != "C"
      RETURN "n"
   ENDIF
   cAns := Lower( AllTrim( xAns ) )
   RETURN iif( Empty( cAns ), "n", Left( cAns, 1 ) )

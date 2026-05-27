// Canonical list of events the hooks system supports.
// Keep this small until a real use case justifies expansion.
FUNCTION CCHOOKS_ValidEvents()
   RETURN { "turn_complete" }

// True if cEvent is in the canonical event list.
FUNCTION CCHOOKS_IsValidEvent( cEvent )
   RETURN AScan( CCHOOKS_ValidEvents(), {| c | c == cEvent } ) > 0

// Returns the array of hook command strings registered for cEvent in
// hSet, or an empty array if the event is absent or hSet has no hooks
// key. Safe to call with arbitrary settings hashes.
FUNCTION CCHOOKS_List( hSet, cEvent )
   IF ValType( hSet ) != "H" .OR. !hb_HHasKey( hSet, "hooks" )
      RETURN {}
   ENDIF
   IF ValType( hSet[ "hooks" ] ) != "H" .OR. ;
      !hb_HHasKey( hSet[ "hooks" ], cEvent )
      RETURN {}
   ENDIF
   RETURN hSet[ "hooks" ][ cEvent ]

// Appends cCmd to hSet["hooks"][cEvent], creating intermediate keys as
// needed. Returns .T. on success, .F. if cEvent is not a valid event.
// Mutates hSet in place; caller is responsible for CCSETTINGS_Save.
FUNCTION CCHOOKS_Add( hSet, cEvent, cCmd )
   IF !CCHOOKS_IsValidEvent( cEvent )
      RETURN .F.
   ENDIF
   IF ValType( hSet ) != "H"
      RETURN .F.
   ENDIF
   IF !hb_HHasKey( hSet, "hooks" ) .OR. ValType( hSet[ "hooks" ] ) != "H"
      hSet[ "hooks" ] := {=>}
   ENDIF
   IF !hb_HHasKey( hSet[ "hooks" ], cEvent )
      hSet[ "hooks" ][ cEvent ] := {}
   ENDIF
   AAdd( hSet[ "hooks" ][ cEvent ], cCmd )
   RETURN .T.

// Removes the 1-based nIdx-th entry from hSet["hooks"][cEvent]. Returns
// .F. (and leaves hSet untouched) if the event is missing or the index
// is out of range. Mutates hSet on success.
FUNCTION CCHOOKS_Remove( hSet, cEvent, nIdx )
   LOCAL aHooks
   IF !CCHOOKS_IsValidEvent( cEvent ) .OR. ValType( hSet ) != "H"
      RETURN .F.
   ENDIF
   aHooks := CCHOOKS_List( hSet, cEvent )
   IF nIdx < 1 .OR. nIdx > Len( aHooks )
      RETURN .F.
   ENDIF
   hb_ADel( aHooks, nIdx, .T. )
   RETURN .T.

// Replaces the 1-based nIdx-th entry with cCmd. Same return-value
// semantics as CCHOOKS_Remove.
FUNCTION CCHOOKS_Edit( hSet, cEvent, nIdx, cCmd )
   LOCAL aHooks
   IF !CCHOOKS_IsValidEvent( cEvent ) .OR. ValType( hSet ) != "H"
      RETURN .F.
   ENDIF
   aHooks := CCHOOKS_List( hSet, cEvent )
   IF nIdx < 1 .OR. nIdx > Len( aHooks )
      RETURN .F.
   ENDIF
   aHooks[ nIdx ] := cCmd
   RETURN .T.

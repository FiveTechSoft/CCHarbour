// cctodo: the session todo list maintained by the todo_write tool. Holds the
// pure normaliser plus the in-memory list state. Knows nothing about
// rendering or the REPL.

STATIC s_aTodos := {}

// True when cStatus is one of the three valid task statuses.
STATIC FUNCTION CCTODO_ValidStatus( cStatus )
   RETURN cStatus == "pending" .OR. cStatus == "in_progress" .OR. ;
          cStatus == "completed"

// Returns a cleaned copy of aTodos. Each element must be a hash with a string
// "text"; others are dropped. A "status" that is missing or not one of the
// three valid values becomes "pending". Returns an array of
// { "text" => <string>, "status" => <valid status> } hashes.
FUNCTION CCTODO_Norm( aTodos )
   LOCAL aOut := {}, hItem, cStatus
   IF ValType( aTodos ) != "A"
      RETURN aOut
   ENDIF
   FOR EACH hItem IN aTodos
      IF ValType( hItem ) != "H" .OR. !hb_HHasKey( hItem, "text" ) .OR. ;
         ValType( hItem[ "text" ] ) != "C"
         LOOP
      ENDIF
      cStatus := iif( hb_HHasKey( hItem, "status" ) .AND. ;
                      ValType( hItem[ "status" ] ) == "C", ;
                      hItem[ "status" ], "pending" )
      IF !CCTODO_ValidStatus( cStatus )
         cStatus := "pending"
      ENDIF
      AAdd( aOut, { "text" => hItem[ "text" ], "status" => cStatus } )
   NEXT
   RETURN aOut

// Normalises aTodos and stores it as the session list. Returns the stored list.
FUNCTION CCTODO_Set( aTodos )
   s_aTodos := CCTODO_Norm( aTodos )
   RETURN s_aTodos

// Returns a fresh copy of the stored session list (an empty array before the
// first Set). A copy, not the live STATIC, so a caller cannot mutate the
// stored state without going through CCTODO_Set.
FUNCTION CCTODO_Get()
   LOCAL aOut := {}, hItem
   FOR EACH hItem IN s_aTodos
      AAdd( aOut, { "text" => hItem[ "text" ], "status" => hItem[ "status" ] } )
   NEXT
   RETURN aOut

// True when the stored list is non-empty and at least one item is not done.
FUNCTION CCTODO_HasOpen()
   LOCAL hItem
   FOR EACH hItem IN s_aTodos
      IF hItem[ "status" ] != "completed"
         RETURN .T.
      ENDIF
   NEXT
   RETURN .F.

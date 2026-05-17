FUNCTION Test_Diff()
   LOCAL cD

   // one line changed -> one add, one delete
   cD := DSDiff_Lines( "a" + Chr(10) + "b" + Chr(10) + "c", ;
                       "a" + Chr(10) + "B" + Chr(10) + "c" )
   T_Assert( "Added 1 line, removed 1 line" $ cD, "diff: header counts" )
   T_Assert( "- b" $ cD, "diff: shows deleted line" )
   T_Assert( "+ B" $ cD, "diff: shows added line" )

   // pure addition
   cD := DSDiff_Lines( "", "x" )
   T_Assert( "Added 1 line, removed 0 lines" $ cD, "diff: pure add header" )
   T_Assert( "+ x" $ cD, "diff: pure add line" )

   // identical text -> no changes
   cD := DSDiff_Lines( "same" + Chr(10) + "text", "same" + Chr(10) + "text" )
   T_Assert( "Added 0 lines, removed 0 lines" $ cD, "diff: no-change header" )

   // a deletion
   cD := DSDiff_Lines( "keep" + Chr(10) + "drop", "keep" )
   T_Assert( "removed 1 line" $ cD, "diff: deletion counted" )
   T_Assert( "- drop" $ cD, "diff: shows deleted text" )
   RETURN NIL

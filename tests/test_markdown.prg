FUNCTION Test_Markdown()
   LOCAL oSt, cOut

   DSUI_SetColor( .F. )

   // a line is rendered only once complete (split across two feeds)
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "hello " ), "", "md: partial line buffered" )
   T_Equal( DSMD_Feed( oSt, "world" + Chr(10) ), "hello world" + Chr(10), ;
            "md: completed line emitted" )

   // a blank line passes through
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, Chr(10) ), Chr(10), "md: blank line" )

   // inline markers are stripped when colour is off
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "a **b** c" + Chr(10) ), "a b c" + Chr(10), ;
            "md: bold markers stripped, colour off" )
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "x `code` y" + Chr(10) ), "x code y" + Chr(10), ;
            "md: code markers stripped, colour off" )
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "an *it* word" + Chr(10) ), "an it word" + Chr(10), ;
            "md: italic markers stripped, colour off" )

   // heading: marks removed
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "## Title" + Chr(10) ), "Title" + Chr(10), ;
            "md: heading marks removed" )

   // bullet list: marker becomes a bullet glyph, indented
   oSt := DSMD_New()
   cOut := DSMD_Feed( oSt, "- item" + Chr(10) )
   T_Equal( cOut, "  " + Chr(226)+Chr(128)+Chr(162) + " item" + Chr(10), ;
            "md: bullet list item" )

   // numbered list: number kept
   oSt := DSMD_New()
   T_Equal( DSMD_Feed( oSt, "3. third" + Chr(10) ), "  3. third" + Chr(10), ;
            "md: numbered list item" )

   // fenced code block: fence lines vanish, content kept verbatim and indented
   oSt := DSMD_New()
   cOut := DSMD_Feed( oSt, "```js" + Chr(10) + "let x" + Chr(10) + "```" + Chr(10) )
   T_Equal( cOut, "  let x" + Chr(10), "md: fenced block content only" )

   // a line inside a fence is not inline-formatted
   oSt := DSMD_New()
   cOut := DSMD_Feed( oSt, "```" + Chr(10) + "a **b**" + Chr(10) + "```" + Chr(10) )
   T_Equal( cOut, "  a **b**" + Chr(10), "md: no inline parsing inside a fence" )

   // suggested-prompt marker: captured, produces no output
   oSt := DSMD_New()
   cOut := DSMD_Feed( oSt, "done." + Chr(10) + "Suggested next: run the tests" + Chr(10) )
   T_Equal( cOut, "done." + Chr(10), "md: suggestion line not printed" )
   T_Equal( DSMD_Suggestion( oSt ), "run the tests", "md: suggestion captured" )

   // flush renders a final unterminated line
   oSt := DSMD_New()
   DSMD_Feed( oSt, "tail" )
   T_Equal( DSMD_Flush( oSt ), "tail" + Chr(10), "md: flush renders partial line" )

   // colour on: bold emits the ANSI bold code
   DSUI_SetColor( .T. )
   oSt := DSMD_New()
   cOut := DSMD_Feed( oSt, "**x**" + Chr(10) )
   T_Assert( Chr(27) + "[1m" $ cOut, "md: bold emits ANSI when colour on" )
   DSUI_SetColor( .F. )

   RETURN NIL

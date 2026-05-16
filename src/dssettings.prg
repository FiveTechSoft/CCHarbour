// Returns the built-in default settings hash.
FUNCTION DSSettings_Defaults()
   RETURN { "model"          => "deepseek-chat", ;
            "base_url"       => "https://api.deepseek.com", ;
            "max_iterations" => 25, ;
            "color"          => .F., ;
            "permissions"    => { "read"  => "allow", "glob"  => "allow", ;
                                  "grep"  => "allow", "write" => "ask", ;
                                  "edit"  => "ask",   "shell" => "ask" } }

// Loads settings.json merged over the defaults.
// cPath omitted -> env CCHARBOUR_CONFIG, else .ccharbour/settings.json under cwd.
// Missing or malformed file -> the pure defaults. Never throws.
FUNCTION DSSettings_Load( cPath )
   LOCAL hSet := DSSettings_Defaults(), cText, xJson, cKey, cTool
   IF Empty( cPath )
      cPath := hb_GetEnv( "CCHARBOUR_CONFIG" )
   ENDIF
   IF Empty( cPath )
      cPath := ".ccharbour" + hb_ps() + "settings.json"
   ENDIF
   IF !hb_FileExists( cPath )
      RETURN hSet
   ENDIF
   cText := hb_MemoRead( cPath )
   xJson := hb_jsonDecode( cText )
   IF ValType( xJson ) != "H"
      RETURN hSet
   ENDIF
   FOR EACH cKey IN hb_HKeys( xJson )
      IF cKey == "permissions"
         IF ValType( xJson[ "permissions" ] ) == "H"
            FOR EACH cTool IN hb_HKeys( xJson[ "permissions" ] )
               hSet[ "permissions" ][ cTool ] := xJson[ "permissions" ][ cTool ]
            NEXT
         ENDIF
      ELSE
         hSet[ cKey ] := xJson[ cKey ]
      ENDIF
   NEXT
   RETURN hSet

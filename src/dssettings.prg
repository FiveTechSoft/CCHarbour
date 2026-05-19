// Returns the built-in default settings hash.
FUNCTION DSSettings_Defaults()
   RETURN { "model"          => "deepseek-v4-flash", ;
            "base_url"       => "https://api.deepseek.com", ;
            "max_iterations" => 25, ;
            "color"          => .T., ;
            "co_author"      => "", ;
            "permissions"    => { "read"  => "allow", "glob"  => "allow", ;
                                  "grep"  => "allow", "write" => "ask", ;
                                  "edit"  => "ask",   "shell" => "ask", ;
                                  "web_search"   => "ask",   "web_fetch"    => "ask", ;
                                  "github_read"  => "allow", "github_write" => "ask", ;
                                  "memory" => "allow" } }

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

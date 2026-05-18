FUNCTION Test_Settings()
   LOCAL hD, hL, cTmp

   // defaults
   hD := DSSettings_Defaults()
   T_Equal( hD[ "model" ], "deepseek-chat", "settings: default model" )
   T_Equal( hD[ "base_url" ], "https://api.deepseek.com", "settings: default base_url" )
   T_Equal( hD[ "max_iterations" ], 25, "settings: default max_iterations" )
   T_Equal( hD[ "permissions" ][ "shell" ], "ask", "settings: default shell mode" )
   T_Equal( hD[ "permissions" ][ "read" ], "allow", "settings: default read mode" )

   // missing file -> defaults
   hL := DSSettings_Load( hb_DirTemp() + "no_such_settings.json" )
   T_Equal( hL[ "model" ], "deepseek-chat", "settings: missing file uses defaults" )

   // a file overriding model and one permission
   cTmp := hb_DirTemp() + "ccharbour_test_settings.json"
   hb_MemoWrit( cTmp, '{"model":"deepseek-reasoner","permissions":{"shell":"allow"}}' )
   hL := DSSettings_Load( cTmp )
   T_Equal( hL[ "model" ], "deepseek-reasoner", "settings: file overrides model" )
   T_Equal( hL[ "base_url" ], "https://api.deepseek.com", "settings: unset key keeps default" )
   T_Equal( hL[ "permissions" ][ "shell" ], "allow", "settings: file overrides one permission" )
   T_Equal( hL[ "permissions" ][ "read" ], "allow", "settings: other permissions keep defaults" )
   FErase( cTmp )

   // malformed JSON -> defaults
   cTmp := hb_DirTemp() + "ccharbour_bad_settings.json"
   hb_MemoWrit( cTmp, "{not valid json" )
   hL := DSSettings_Load( cTmp )
   T_Equal( hL[ "model" ], "deepseek-chat", "settings: malformed file uses defaults" )
   FErase( cTmp )

   hL := DSSettings_Defaults()
   T_Equal( hL[ "permissions" ][ "web_search" ], "ask", "settings: web_search perm" )
   T_Equal( hL[ "permissions" ][ "web_fetch" ], "ask", "settings: web_fetch perm" )
   T_Equal( hL[ "permissions" ][ "github_read" ], "allow", "settings: github_read perm" )
   T_Equal( hL[ "permissions" ][ "github_write" ], "ask", "settings: github_write perm" )
   RETURN NIL

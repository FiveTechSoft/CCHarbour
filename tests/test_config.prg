FUNCTION Test_Config()
   LOCAL hR, cTmp

   // explicit api_key in hOpts wins
   hR := CCCFG_Resolve( { "api_key" => "explicit-key" } )
   T_Equal( hR[ "ok" ], .T., "cfg: explicit ok" )
   T_Equal( hR[ "api_key" ], "explicit-key", "cfg: explicit key" )

   // env var fallback
   hb_SetEnv( "DEEPSEEK_API_KEY", "env-key" )
   hR := CCCFG_Resolve( {=>} )
   T_Equal( hR[ "api_key" ], "env-key", "cfg: env key" )
   hb_SetEnv( "DEEPSEEK_API_KEY", "" )

   // config-file fallback
   cTmp := hb_DirTemp() + "CCCFG_test.json"
   hb_MemoWrit( cTmp, '{"api_key":"file-key"}' )
   hR := CCCFG_Resolve( { "config_path" => cTmp } )
   T_Equal( hR[ "api_key" ], "file-key", "cfg: file key" )
   FErase( cTmp )

   // no key anywhere -> ok = .F.
   hR := CCCFG_Resolve( {=>} )
   T_Equal( hR[ "ok" ], .F., "cfg: missing key fails" )
   T_Equal( hR[ "error_type" ], "config", "cfg: missing key error_type" )

   // default base url
   hR := CCCFG_Resolve( { "api_key" => "k" } )
   T_Equal( hR[ "base_url" ], "https://api.deepseek.com", "cfg: default base url" )

   // --- CCCFG_ResolveKey ---

   // settings hash value is used when the env var is unset
   hR := CCCFG_ResolveKey( "CCHARBOUR_NO_SUCH_ENV", "tavily_api_key", ;
                           { "tavily_api_key" => "from-settings" } )
   T_Equal( hR, "from-settings", "resolvekey: settings fallback" )

   // empty everywhere -> empty string
   hR := CCCFG_ResolveKey( "CCHARBOUR_NO_SUCH_ENV", "github_token", {=>} )
   T_Equal( hR, "", "resolvekey: empty when unset" )

   // env var wins over the settings hash
   hb_SetEnv( "CCHARBOUR_TEST_KEY", "from-env" )
   hR := CCCFG_ResolveKey( "CCHARBOUR_TEST_KEY", "tavily_api_key", ;
                           { "tavily_api_key" => "from-settings" } )
   T_Equal( hR, "from-env", "resolvekey: env wins" )
   hb_SetEnv( "CCHARBOUR_TEST_KEY", "" )
   RETURN NIL

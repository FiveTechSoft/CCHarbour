FUNCTION Test_Config()
   LOCAL hR, cTmp

   // explicit api_key in hOpts wins
   hR := DSCFG_Resolve( { "api_key" => "explicit-key" } )
   T_Equal( hR[ "ok" ], .T., "cfg: explicit ok" )
   T_Equal( hR[ "api_key" ], "explicit-key", "cfg: explicit key" )

   // env var fallback
   hb_SetEnv( "DEEPSEEK_API_KEY", "env-key" )
   hR := DSCFG_Resolve( {=>} )
   T_Equal( hR[ "api_key" ], "env-key", "cfg: env key" )
   hb_SetEnv( "DEEPSEEK_API_KEY", "" )

   // config-file fallback
   cTmp := hb_DirTemp() + "dscfg_test.json"
   hb_MemoWrit( cTmp, '{"api_key":"file-key"}' )
   hR := DSCFG_Resolve( { "config_path" => cTmp } )
   T_Equal( hR[ "api_key" ], "file-key", "cfg: file key" )
   FErase( cTmp )

   // no key anywhere -> ok = .F.
   hR := DSCFG_Resolve( {=>} )
   T_Equal( hR[ "ok" ], .F., "cfg: missing key fails" )
   T_Equal( hR[ "error_type" ], "config", "cfg: missing key error_type" )

   // default base url
   hR := DSCFG_Resolve( { "api_key" => "k" } )
   T_Equal( hR[ "base_url" ], "https://api.deepseek.com", "cfg: default base url" )
   RETURN NIL

// Resolves API key + base URL. Precedence for the key:
//   hOpts["api_key"]  ->  env DEEPSEEK_API_KEY  ->  config file (hOpts["config_path"])
// Returns: { ok, api_key, base_url, error_type, message }
FUNCTION DSCFG_Resolve( hOpts )
   LOCAL hRes, cKey := "", cEnv, cFileKey

   IF ValType( hOpts ) != "H"
      hOpts := {=>}
   ENDIF

   hRes := { "ok" => .F., "api_key" => "", ;
             "base_url" => iif( hb_HHasKey( hOpts, "base_url" ) .AND. ;
                                !Empty( hOpts[ "base_url" ] ), ;
                                hOpts[ "base_url" ], "https://api.deepseek.com" ), ;
             "error_type" => NIL, "message" => NIL }

   IF hb_HHasKey( hOpts, "api_key" ) .AND. !Empty( hOpts[ "api_key" ] )
      cKey := hOpts[ "api_key" ]
   ELSE
      cEnv := hb_GetEnv( "DEEPSEEK_API_KEY" )
      IF !Empty( cEnv )
         cKey := cEnv
      ELSEIF hb_HHasKey( hOpts, "config_path" ) .AND. !Empty( hOpts[ "config_path" ] )
         cFileKey := DSCFG_FromFile( hOpts[ "config_path" ] )
         IF !Empty( cFileKey )
            cKey := cFileKey
         ENDIF
      ENDIF
   ENDIF

   IF Empty( cKey )
      hRes[ "error_type" ] := "config"
      hRes[ "message" ]    := "No API key: set hOpts api_key, env DEEPSEEK_API_KEY, or config_path"
      RETURN hRes
   ENDIF

   hRes[ "api_key" ] := cKey
   hRes[ "ok" ]      := .T.
   RETURN hRes

STATIC FUNCTION DSCFG_FromFile( cPath )
   LOCAL cText, xJson
   IF !hb_FileExists( cPath )
      RETURN ""
   ENDIF
   cText := hb_MemoRead( cPath )
   xJson := hb_jsonDecode( cText )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "api_key" ) .AND. ;
      ValType( xJson[ "api_key" ] ) == "C"
      RETURN xJson[ "api_key" ]
   ENDIF
   RETURN ""

// Resolves a secret value. Precedence: environment variable cEnvName, then
// hSettings[ cSettingKey ]. Returns "" when neither is set.
FUNCTION DSCFG_ResolveKey( cEnvName, cSettingKey, hSettings )
   LOCAL cEnv := hb_GetEnv( cEnvName )
   IF !Empty( cEnv )
      RETURN cEnv
   ENDIF
   IF ValType( hSettings ) == "H" .AND. hb_HHasKey( hSettings, cSettingKey ) .AND. ;
      ValType( hSettings[ cSettingKey ] ) == "C"
      RETURN hSettings[ cSettingKey ]
   ENDIF
   RETURN ""

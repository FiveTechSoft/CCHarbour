// GitHub tools for CCHarbour: github_read (queries) and github_write (mutations).

// Builds the standard GitHub API request headers; adds auth when a token is set.
STATIC FUNCTION DSGithub_Headers( cToken )
   LOCAL aHdr := { "Accept: application/vnd.github+json", ;
                   "User-Agent: CCHarbour", ;
                   "Content-Type: application/json" }
   IF !Empty( cToken )
      AAdd( aHdr, "Authorization: Bearer " + cToken )
   ENDIF
   RETURN aHdr

// Percent-encodes a string for use in a URL query component. Byte-wise so
// multi-byte (UTF-8) input is encoded one octet at a time.
STATIC FUNCTION DSGithub_UrlEncode( cText )
   LOCAL cOut := "", i, c
   FOR i := 1 TO hb_BLen( cText )
      c := hb_BSubStr( cText, i, 1 )
      IF ( c >= "A" .AND. c <= "Z" ) .OR. ( c >= "a" .AND. c <= "z" ) .OR. ;
         ( c >= "0" .AND. c <= "9" ) .OR. c $ "-_.~"
         cOut += c
      ELSE
         cOut += "%" + PadL( Upper( hb_NumToHex( hb_BCode( c ) ) ), 2, "0" )
      ENDIF
   NEXT
   RETURN cOut

// Extracts the "message" field from a GitHub error JSON body, or "".
STATIC FUNCTION DSGithub_ApiMessage( cBody )
   LOCAL xJson := hb_jsonDecode( cBody )
   IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "message" )
      RETURN hb_CStr( xJson[ "message" ] )
   ENDIF
   RETURN ""

// github_read: read-only GitHub queries. cToken is optional (unauthenticated
// requests work but are rate-limited).
FUNCTION DSTool_GithubRead( cToken )
   RETURN { "name" => "github_read", ;
            "description" => "Read from GitHub: repo info, file content, directory listing, issues, pull requests, code search.", ;
            "parameters" => { "type" => "object", ;
               "properties" => { ;
                  "operation" => { "type" => "string", ;
                     "description" => "One of: repo, file, list, issues, issue, prs, pr, search" }, ;
                  "repo" => { "type" => "string", ;
                     "description" => "Repository as owner/name (every operation except search)" }, ;
                  "path" => { "type" => "string", ;
                     "description" => "File or directory path (file, list)" }, ;
                  "number" => { "type" => "integer", ;
                     "description" => "Issue or PR number (issue, pr)" }, ;
                  "query" => { "type" => "string", ;
                     "description" => "Code search query (search)" } }, ;
               "required" => { "operation" } }, ;
            "handler" => {| hArgs | DSTool_GithubReadRun( hArgs, cToken ) } }

// The executor validates only `operation`; this handler validates the
// per-operation arguments (repo, path, number, query).
STATIC FUNCTION DSTool_GithubReadRun( hArgs, cToken )
   LOCAL cOp, cRepo, cUrl, hRes
   cOp := Lower( hb_CStr( hArgs[ "operation" ] ) )
   IF cOp == "search"
      IF !hb_HHasKey( hArgs, "query" ) .OR. Empty( hArgs[ "query" ] )
         RETURN "Error: github_read 'search' requires 'query'"
      ENDIF
      cUrl := "https://api.github.com/search/code?q=" + ;
              DSGithub_UrlEncode( hb_CStr( hArgs[ "query" ] ) )
   ELSE
      IF !hb_HHasKey( hArgs, "repo" ) .OR. Empty( hArgs[ "repo" ] )
         RETURN "Error: github_read '" + cOp + "' requires 'repo'"
      ENDIF
      cRepo := hb_CStr( hArgs[ "repo" ] )
      DO CASE
      CASE cOp == "repo"
         cUrl := "https://api.github.com/repos/" + cRepo
      CASE cOp == "file" .OR. cOp == "list"
         IF !hb_HHasKey( hArgs, "path" ) .OR. Empty( hArgs[ "path" ] )
            RETURN "Error: github_read '" + cOp + "' requires 'path'"
         ENDIF
         cUrl := "https://api.github.com/repos/" + cRepo + "/contents/" + ;
                 hb_CStr( hArgs[ "path" ] )
      CASE cOp == "issues"
         cUrl := "https://api.github.com/repos/" + cRepo + "/issues"
      CASE cOp == "issue"
         IF !hb_HHasKey( hArgs, "number" ) .OR. ValType( hArgs[ "number" ] ) != "N"
            RETURN "Error: github_read 'issue' requires a numeric 'number'"
         ENDIF
         cUrl := "https://api.github.com/repos/" + cRepo + "/issues/" + ;
                 LTrim( Str( hArgs[ "number" ] ) )
      CASE cOp == "prs"
         cUrl := "https://api.github.com/repos/" + cRepo + "/pulls"
      CASE cOp == "pr"
         IF !hb_HHasKey( hArgs, "number" ) .OR. ValType( hArgs[ "number" ] ) != "N"
            RETURN "Error: github_read 'pr' requires a numeric 'number'"
         ENDIF
         cUrl := "https://api.github.com/repos/" + cRepo + "/pulls/" + ;
                 LTrim( Str( hArgs[ "number" ] ) )
      OTHERWISE
         RETURN "Error: github_read: unknown operation '" + cOp + "'"
      ENDCASE
   ENDIF
   hRes := DSHTTP_Fetch( { "url" => cUrl, "method" => "GET", ;
                           "headers" => DSGithub_Headers( cToken ) } )
   IF !hRes[ "ok" ]
      RETURN "Error: github_read failed: " + hRes[ "error" ]
   ENDIF
   IF hRes[ "status" ] < 200 .OR. hRes[ "status" ] >= 300
      RETURN "Error: github_read HTTP " + LTrim( Str( hRes[ "status" ] ) ) + ": " + ;
             DSGithub_ApiMessage( hRes[ "body" ] )
   ENDIF
   RETURN DSGithub_FormatRead( cOp, hRes[ "body" ] )

// Formats a successful github_read response by operation.
STATIC FUNCTION DSGithub_FormatRead( cOp, cBody )
   LOCAL xJson, cText, h1
   DO CASE
   CASE cOp == "file"
      xJson := hb_jsonDecode( cBody )
      IF ValType( xJson ) == "H" .AND. hb_HHasKey( xJson, "content" )
         RETURN hb_base64Decode( StrTran( hb_CStr( xJson[ "content" ] ), Chr( 10 ), "" ) )
      ENDIF
      RETURN cBody
   CASE cOp == "list"
      xJson := hb_jsonDecode( cBody )
      IF ValType( xJson ) == "A"
         cText := ""
         FOR EACH h1 IN xJson
            IF ValType( h1 ) == "H" .AND. hb_HHasKey( h1, "name" )
               cText += hb_CStr( hb_HGetDef( h1, "type", "" ) ) + "  " + ;
                        hb_CStr( h1[ "name" ] ) + Chr( 10 )
            ENDIF
         NEXT
         RETURN cText
      ENDIF
      RETURN cBody
   ENDCASE
   IF hb_BLen( cBody ) > 30000
      RETURN hb_BLeft( cBody, 30000 ) + Chr( 10 ) + "[output truncated]" + Chr( 10 )
   ENDIF
   RETURN cBody

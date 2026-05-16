// Performs a streaming POST. hReq: { url, headers (array of "K: V"), body, timeout }.
// bOnChunk is called with each received raw text chunk.
// bTransport (optional codeblock {|hReq,bOnChunk| -> hResult }) overrides libcurl;
// when NIL the real libcurl transport (DSHTTP_CurlPost, Task 7) is used.
// Returns: { ok, status, curl_code, error }
FUNCTION DSHTTP_Post( hReq, bOnChunk, bTransport )
   IF bTransport != NIL
      RETURN Eval( bTransport, hReq, bOnChunk )
   ENDIF
   RETURN DSHTTP_CurlPost( hReq, bOnChunk )

// Placeholder real transport; replaced with the libcurl implementation in Task 7.
FUNCTION DSHTTP_CurlPost( hReq, bOnChunk )
   HB_SYMBOL_UNUSED( hReq )
   HB_SYMBOL_UNUSED( bOnChunk )
   RETURN { "ok" => .F., "status" => 0, "curl_code" => -1, ;
            "error" => "libcurl transport not yet implemented" }

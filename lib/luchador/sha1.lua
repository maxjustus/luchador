SHA1 = {}

SHA1.digest_base64 = function(str)
  return ngx.encode_base64(ngx.sha1_bin(str))
end

return SHA1

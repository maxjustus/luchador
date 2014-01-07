SHA1 = {}

function SHA1.tohex(str)
  return (
    str:gsub('.', function (c)
      return string.format('%02x', string.byte(c))
    end)
  )
end

SHA1.hexdigest = function(str)
  return SHA1.tohex(ngx.sha1_bin(str))
end

return SHA1

local cache_control = require "luchador.cache_control"
local Header = {}
local mt = {__index = Header}
local debug_headers = ngx.var.debug_headers

function Header.become(header)
  if header then setmetatable(header, mt) end
  return header
end

function Header:ttl()
  local cc = cache_control.parse(self["Cache-Control"])

  if self['Pragma'] == 'no-cache' or
     cc['no-cache'] or
     cc['no-store'] or
     cc['private'] or
     cc['must-revalidate'] or
     cc['proxy-revalidate']
  then
    return
  end

  local ttl = cc['s-maxage'] or
              cc['max-age'] or
              self:expires_header_ttl()

  if debug_headers then
    ngx.header['ttl'] = ttl
  end

  return ttl
end

function Header:expires_header_ttl()
  if self['Expires'] then
    return (ngx.parse_http_time(self['Expires']) or 0) - ngx.time()
  end
end

function Header:age()
  if not (self["Date"] == nil) then
    return ngx.time() - ngx.parse_http_time(self["Date"])
  end
end

return Header

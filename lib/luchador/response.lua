local zlib = require "zlib"
local Response = {}
local mt = { __index = Response }

function Response.new(req_headers)
  local r = {
    headers = {},
    req_headers = req_headers
  }
  setmetatable(r, mt)
  return r
end

-- Headers that MUST NOT be included with 304 Not Modified responses.
-- http://tools.ietf.org/html/rfc2616#section-10.3.5
NOT_MODIFIED_OMIT_HEADERS = {
  "Allow",
  "Content-Encoding",
  "Content-Language",
  "Content-Length",
  "Content-MD5",
  "Content-Type",
  "Last-Modified"
}

function Response:set_headers()
  if self.status == 304 then
    for _, omit in pairs(NOT_MODIFIED_OMIT_HEADERS) do
      self.headers[omit] = nil
    end
  end

  self.headers["Age"] = self.headers:age()

  for k,v in pairs(self.headers) do
    ngx.header[k] = v
  end
end

function Response:set_content_encoding()
  local requested_gzip = tostring(self.req_headers['Accept-Encoding']):match('gzip')
  local cached_gzip = tostring(self.headers['Content-Encoding']) == 'gzip'
  if cached_gzip and self.body and not requested_gzip then
    self.headers['Content-Encoding'] = nil
    self.body = zlib.decompress(self.body, 15+16)
  end
end

function Response:check_not_modified()
  return self.headers and
         ngx.var.http_if_none_match and
         self.headers["ETag"] == ngx.var.http_if_none_match
end

function Response:serve()
  ngx.status = self.status
  self:set_content_encoding()
  self:set_headers()
  ngx.say(self.body)
end

return Response

local Header = require "header"
local Upstream = {}
local mt = {__index = Upstream}

function Upstream.new(base_path)
  local resp = ngx.location.capture(base_path .. ngx.var.request_uri,
                                    {share_all_vars = true})

  local upstream = {
    body   = resp.body,
    header = Header.become(resp.header),
    status = resp.status
  }
  setmetatable(upstream, mt)

  return upstream
end

function Upstream:ttl()
  return self.header:ttl()
end

return Upstream

local Header = require "header"
local cluster = require "memc_cluster"
local storage = require "storage"
local response = require "response"
local upstream = require "upstream"
local debug_headers = ngx.var.debug_headers

local Cache = {}
local mt = { __index = Cache }

function Cache.new(upstream_location, options)
  options = options or {}
  local servers = options.memcached_servers or {'127.0.0.1'}
  local datastore = cluster.connect(servers)
  local cache = {storage           = storage.new(datastore),
                 upstream_location = upstream_location,
                 after_hit         = options.after_hit,
                 after_request     = options.after_request}
  setmetatable(cache, mt)
  return cache
end

function record(change)
  local h = ngx.header['X-Cache']
  if not h then h = '' end
  ngx.header['X-Cache'] = h .. change .. ' '
end

function Cache:call_callback(name)
  if self[name] then self[name]() end
end

function Cache:miss()
  local upst = upstream.new(self.upstream_location)
  local did_store = self.storage:store_page(upst, self.req_headers)

  record('miss')
  if did_store then
    record('store')
  else
    record('pass')
  end

  self.response.headers = upst.header
  self.response.status = upst.status
  self.response.body = upst.body
end

function Cache:get_lock(f)
  local tries = 0
  while tries < 15 do
    if self.storage:get_lock() then
      local r = f()
      self.storage:release_lock()
      return r
    else
      tries = tries + 1
      ngx.sleep(1)
      if self:get_stored_headers() and self:get_page() then
        return self:hit()
      end
    end
  end
end

function Cache:hit()
  self.response.headers = self.stored_headers
  self.response.status = 200
  self.response.body = self.cached_body
  self:call_callback('after_hit')
  record('hit')
end

function Cache:not_modified()
  self.response.status = ngx.HTTP_NOT_MODIFIED
  self.response.headers = self.stored_headers
end

function Cache:get_stored_headers()
  if not self.stored_headers then
    self.stored_headers = Header.become(self.storage:get_metadata(self.req_headers))
  end

  return self.stored_headers
end

function Cache:get_page()
  if not self.cached_body then
    self.cached_body = self.storage:get_page(self.stored_headers)
  end

  return self.cached_body
end

function Cache:serve()
  self.req_headers = ngx.req.get_headers()
  self.response = response.new(self.req_headers)
  local meth = ngx.req.get_method()
  if not (meth == "GET") and not (meth == "HEAD") then
    return ngx.exit(ngx.HTTP_NOT_FOUND)
  end

  self.response.headers = self:get_stored_headers()

  if self.response:check_not_modified() then
    self:not_modified()
  else
    if not self:get_page() then
      self:get_lock(function() self:miss() end)
    else
      self:hit()
    end
  end

  self.response:serve()
  self:call_callback('after_request')
  self.storage:keepalive()

  if debug_headers and self.req_headers['clear-ngx-cache'] then
    ngx.shared.cache:flush_all()
  end
end

return Cache

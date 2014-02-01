local Header = require "luchador.header"
local cluster = require "luchador.memc_cluster"
local storage = require "luchador.storage"
local response = require "luchador.response"
local upstream = require "luchador.upstream"
local table = table
local debug_headers = ngx.var.debug_headers

local Cache = {}
local mt = { __index = Cache }

function Cache.new(upstream_location, options)
  options = options or {}
  local servers = options.memcached_servers or {'127.0.0.1'}
  local datastore = cluster.new(servers)
  local cache = {storage           = storage.new(datastore, options.page_key_filter),
                 status            = {},
                 upstream_location = upstream_location,
                 lock_timeout      = (options.lock_timeout or 30),
                 before_response   = options.before_response,
                 after_response    = options.after_response}
  setmetatable(cache, mt)
  return cache
end

function Cache:record(change)
  table.insert(self.status, change)
end

function Cache:call_callback(name, cache_status, response_status)
  if self[name] then self[name](cache_status, response_status) end
end

function Cache:miss()
  local upst = upstream.new(self.upstream_location)
  local ttl = upst:ttl()
  local cacheable = upst.status == 200 and ttl and not (ttl == '0')

  local body, encoding =
    self.storage:compress(upst.body, upst.header['Content-Type'], cacheable)

  upst.body = body
  upst.header['Content-Encoding'] = encoding
  if encoding == 'gzip' then
    upst.header['Content-Length'] = #body
  end

  self:record('miss')
  if cacheable then
    self.storage:store_page(upst, self.req_headers, ttl)
    self:record('store')
  else
    self:record('pass')
    self.storage:set_skip()
  end

  self.response.headers = upst.header
  self.response.status = upst.status
  self.response.body = upst.body
end

function Cache:get_lock(f)
  if self.storage:get_skip() then
    self:record('miss')
    self:record('pass')
    self:before_serve()
    return ngx.exit(ngx.HTTP_NOT_FOUND)
  end

  local tries = 0
  local lock_timeout = self.lock_timeout
  while tries < lock_timeout do
    if self.storage:get_lock(lock_timeout) then
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
  self:record('hit')
end

function Cache:not_modified()
  self.response.status = ngx.HTTP_NOT_MODIFIED
  self.response.headers = self.stored_headers
  self:record('hit')
end

function Cache:get_stored_headers()
  local locally_cached

  if not self.stored_headers then
    local stored_headers

    stored_headers, locally_cached = self.storage:get_metadata(self.req_headers)
    self.stored_headers = Header.become(stored_headers)
  end

  return self.stored_headers, locally_cached
end

function Cache:get_page()
  if not self.cached_body then
    self.cached_body = self.storage:get_page(self.stored_headers)
  end

  return self.cached_body
end

function Cache:before_serve()
  ngx.header['X-Cache'] = table.concat(self.status, ' ')
  self:call_callback('before_response', self.status, self.response.status)
end

function Cache:serve()
  self.req_headers = ngx.req.get_headers()
  self.response = response.new(self.req_headers)
  local meth = ngx.req.get_method()
  if not (meth == "GET") and not (meth == "HEAD") then
    return ngx.exit(ngx.HTTP_NOT_FOUND)
  end

  local locally_cached
  self.response.headers, locally_cached = self:get_stored_headers()
  if locally_cached then self:record('local') end

  if self.response:check_not_modified() then
    self:not_modified()
  else
    if not self:get_page() then
      self:get_lock(function() self:miss() end)
    else
      self:hit()
    end
  end

  self:before_serve()
  self.response:serve()
  self:call_callback('after_response')
  self.storage:keepalive()

  if debug_headers and self.req_headers['clear-ngx-cache'] then
    ngx.shared.cache_locks:flush_all()
    ngx.shared.cache_metadata:flush_all()
    ngx.shared.cache_entities:flush_all()
  end

  self.storage:flush_expired()
end

return Cache

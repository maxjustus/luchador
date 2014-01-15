local memcached = require "resty.memcached"
local hashfunc = ngx.crc32_short
local SERVER_RETRIES = 10
local MemcCluster = {}
local mt = {__index = MemcCluster}

function noop(string) return string end

function MemcCluster.get_memcached_connection(host)
  local memc, err = memcached:new{key_transform = {noop, noop}}
  if not memc then
    ngx.log(ngx.WARN, "failed to instantiate memc: ", err)
    return ngx.exit(ngx.HTTP_NOT_FOUND)
  end

  memc:set_timeout(1000) -- 1 sec

  local ok, err = memc:connect(host, 11211)
  if not ok then
    ngx.log(ngx.WARN, "failed to connect: ", err)
    return ngx.exit(ngx.HTTP_NOT_FOUND)
  end

  return memc
end

function MemcCluster.new(hosts)
  local cluster = {
    hosts = hosts,
    server_count = #hosts,
    servers = {}
  }

  setmetatable(cluster, mt)

  return cluster
end

function MemcCluster:get(key)
  local val, flags, err = self:for_key(key):get(key)
  if err then
    ngx.log(ngx.WARN, "failed to get " .. key .. ": ", err)
    return ngx.exit(ngx.HTTP_NOT_FOUND)
  end

  return val
end

function MemcCluster:set(key, val, ttl)
  local flags, err = self:for_key(key):set(key, val, ttl)
  if err then
    ngx.log(ngx.WARN, "failed to set " .. key .. ": ", err)
    return ngx.exit(ngx.HTTP_NOT_FOUND)
  else
    return val
  end
end

function MemcCluster:for_key(key)
  local hash = hashfunc(key)

  local host
  if self.server_count > 1 then
    for i = 0, SERVER_RETRIES do
      local index = (hash % server_count) + 1
      host = self.hosts[index]

      if not host then
        serverhash = hashfunc(hash .. i)
      else
        break
      end
    end
  else
    host = self.hosts[1]
  end

  local server
  if self.servers[host] then
    return self.servers[host]
  else
    local server = MemcCluster.get_memcached_connection(host)
    self.servers[host] = server
    return server
  end
end

function MemcCluster:keepalive()
  for _,node in pairs(self.servers) do
    local ok, err = node:set_keepalive(10000, 100)
    if not ok then
      ngx.log(ngx.WARN, "cannot set keepalive: ", err)
    end
  end
end

return MemcCluster

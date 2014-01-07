local memcached = require "memcached"
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

function MemcCluster.connect(hosts)
  local cluster = {servers = {}}
  setmetatable(cluster, mt)

  for _,host in ipairs(hosts) do
    local client = MemcCluster.get_memcached_connection(host)
    table.insert(cluster.servers, client)
  end

  cluster.server_count = #cluster.servers

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

  if self.server_count > 1 then
    for i = 0, SERVER_RETRIES do
      local index = (hash % server_count) + 1
      local server = self.servers[index]

      if not server then
        serverhash = hashfunc(hash .. i)
      else
        return server
      end
    end
  else
    return self.servers[1]
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

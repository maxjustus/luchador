local sha1 = require "luchador.sha1"
local serializer = require "luchador.serializer"
local zlib = require "zlib"
local namespace = 'LC_'

local Storage = {}
local mt = {__index = Storage}

function Storage.new(datastore, page_key_filter, local_entity_size)
  local storage = {datastore = datastore,
                   local_entity_size = local_entity_size,
                   page_key_filter = page_key_filter}
  setmetatable(storage, mt)
  return storage
end

function Storage:page_key()
  local key = ngx.var.scheme .. "://" .. ngx.var.host .. ngx.var.request_uri

  if self.page_key_filter then
    key = self.page_key_filter(key, self.datastore)
  end

  return sha1.digest_base64(key)
end

function Storage:get_metadata(req_h)
  local metadata, locally_cached = self:get(self:page_key(), true)

  if metadata == nil then
    return nil
  else
    ngx.log(ngx.INFO, "HIT")
    for _, metadata in pairs(metadata) do
      local cached_vary_key = metadata[1]
      local cached_req_h = metadata[2]
      local cached_resp_h = metadata[3]

      if cached_resp_h['Vary'] then
        if cached_vary_key == self.vary_key(cached_resp_h['Vary'], req_h) then
          return cached_resp_h, locally_cached
        end
      else
        return cached_resp_h, locally_cached
      end
    end
  end
end

function Storage:store_metadata(req_h, resp_h, digest_key, ttl)
  if resp_h["Date"] == nil then
    resp_h["Date"] = ngx.http_time(ngx.time())
  end

  resp_h['X-Content-Digest'] = digest_key
  resp_h['Set-Cookie'] = nil
  local k = self:page_key()
  local h = (self:get(k) or {})

  local vk = self.vary_key(resp_h['Vary'], req_h)
  local vary_position = 1
  for i,v in ipairs(h) do
    if v[1] == vk then
      vary_position = i
    else
      vary_position = i + 1
    end
  end

  local cached_vary_val = {vk, req_h, resp_h}
  h[vary_position] = cached_vary_val

  self:set(k, h, ttl, true)
end

function Storage.vary_key(vary, req_h)
  local vk = {}

  if vary then
    for h in vary:gmatch("[^ ,]+") do
      h = h:lower()
      table.insert(vk, req_h[h] or '')
    end
  end

  return table.concat(vk)
end

function Storage:get_page(metadata)
  if not (metadata == nil) then
    local digest = metadata["X-Content-Digest"]
    if not (digest == nil) then
      return self:get(digest, false)
    end
  end
end

function Storage:store_page(resp, req_h, ttl)
  ngx.log(ngx.INFO, "MISS" .. ngx.var.request_uri)

  local digest_key = ngx.md5(resp.body)

  self:store_metadata(req_h, resp.header, digest_key, ttl)
  self:set(digest_key, resp.body, ttl)
  return true
end

function Storage:compress(content, content_type, use_best)
  local compression_level = zlib.BEST_SPEED
  if use_best then
    compression_level = zlib.BEST_COMPRESSION
  end

  if content_type and
     (content_type:match('text') or content_type:match('application'))
  then
    content = zlib.compress(content, compression_level, nil, 15+16)
    return content, "gzip"
  else
    return content, nil
  end
end

function Storage:get_skip()
  return ngx.shared.cache_metadata:get(self:page_key() .. 'skip')
end

function Storage:set_skip()
  local r, err = ngx.shared.cache_metadata:set(self:page_key() .. 'skip', true, 30)
  return r
end

function Storage:get_lock(timeout)
  local r, err = ngx.shared.cache_metadata:add(self:page_key() .. 'lock', true, timeout)
  return r
end

function Storage:release_lock()
  return ngx.shared.cache_metadata:delete(self:page_key() .. 'lock')
end

function Storage:set(key, val, ttl, is_metadata)
  key = namespace .. key

  val = {val = val, ttl = ttl, created = ngx.time()}
  val = serializer.serialize(val)

  self:local_set(key, self.datastore:set(key, val, ttl), ttl, is_metadata)
end

function Storage:get(key, is_metadata)
  key = namespace .. key
  local locally_cached = false
  local entry = self:local_get(key, is_metadata)

  if entry then
    locally_cached = true
  else
    entry = self.datastore:get(key)
  end

  local thawed
  if entry then
    thawed = serializer.deserialize(entry)
  end

  if thawed then
    if not locally_cached then
      local age = (ngx.time() - thawed.created)
      local remaining_ttl = thawed.ttl - age
      if remaining_ttl > 0 then
        self:local_set(key, entry, remaining_ttl, is_metadata)
      end
    end

    return thawed.val, locally_cached
  end
end

function Storage:local_set(key, value, ttl, is_metadata)
  local storage = self:get_local_store(is_metadata)

  if is_metadata then
    storage:set(key, value, ttl)
  else
    local padded_value, real_length = self:pad(value)
    storage:set(key, padded_value, ttl, real_length)
  end
end

function Storage:local_get(key, is_metadata)
  local val, real_length = self:get_local_store(is_metadata):get(key)
  if val and real_length then
    return string.sub(val, 0, real_length)
  else
    return val
  end
end

function Storage:get_local_store(is_metadata)
  if is_metadata then
    return ngx.shared.cache_metadata
  else
    return ngx.shared.cache_entities
  end
end

-- This is required for large local store entries
-- due to an issue with the way nginx's slab allocator
-- works with large allocations. It will repeatedly split
-- the slabs until the maximum slab size is too small to
-- store any cached page data in.
-- The only workaround that seems effective is to pad every
-- value so they all have the same size.
-- Once some version of this patch gets into mainline nginx
-- http://forum.nginx.org/read.php?29,240420,241321#msg-241321
-- this code should be removed.
function Storage:pad(value)
  local real_length = #value
  local padded_length = self.local_entity_size
  if real_length > padded_length then return end

  local padded_value = value .. string.rep(' ', padded_length - real_length)
  return padded_value, real_length
end

function Storage:flush_expired()
  ngx.shared.cache_metadata:flush_expired(5)
  ngx.shared.cache_entities:flush_expired(5)
end

function Storage:keepalive()
  self.datastore:keepalive()
end

return Storage

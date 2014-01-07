CacheControl = {}

function CacheControl.parse(cache_control)
  if not cache_control then
    return {}
  end

  local headers = {}
  local cache_control = cache_control:gsub(" *", ""):lower()
  for directive in cache_control:gmatch("[^,]+") do
    if directive:match("=") then
      local k, v = directive:match("(.*)=(.*)")
      headers[k] = v
    else
      headers[directive] = true
    end
  end

  return headers
end

return CacheControl

require "test_helper"
io = require "io"
os = require "os"

function get(request_headers, response_headers, flush)
  if flush == nil then flush = true end
  local header_string = ""
  if flush then request_headers['clear-ngx-cache'] = 'true' end
  for h, v in pairs(request_headers) do
    header_string = header_string .. '-H "' .. h .. ":" .. v .. '" '
  end

  local path = ''
  for h, v in pairs(response_headers) do
    path = path .. h .. ":" .. v .. ";"
  end

  local command = 'curl 2>/dev/null ' .. header_string .. ' -I "localhost:8081/' .. path .. '"'
  local f = io.popen(command)
  local headers = f:read("*a")
  f:close()
  if flush then flush_cache() end
  return headers
end

function flush_cache()
  os.execute("echo 'flush_all' | nc -c localhost 11211 > /dev/null")
end

function start_server()
  os.execute('nginx -c `echo $(pwd)/nginx/nginx.conf` -p `echo $(pwd)/nginx/` 2> /dev/null')
end

function stop_server()
  os.execute('kill $(ps -ax | grep -v grep | grep "nginx -c $(echo $(pwd))" | head -n 1 | awk \'{print $1}\')')
end

start_server()

test("supports max-age", function()
  local headers = get({},
                      {["Cache-Control"] = "max-age=180, public",
                       ["Content-Type"] = "text/html"})
  return headers:match("Age: (.*)") and headers:match("X-Cache: miss store")
end)

test("supports s-maxage", function()
  local headers = get({},
                      {["Cache-Control"] = "s-maxage=800, max-age=180, public",
                       ["Content-Type"] = "text/html"})
  return headers:match("ttl: 800") and
         headers:match("Age: (.*)") and
         headers:match("X-Cache: miss store")
end)

test("supports expires", function()
  local headers = get({},
                      {["Cache-Control"] = "public",
                       ["Expires"] = "Sat, 01 Jul 2036 01:50:55 UTC",
                       ["Content-Type"] = "text/html"})
  return headers:match("ttl: %d%d%d") and
         headers:match("Age: (.*)") and
         headers:match("X%-Content%-Digest")
end)

test("ignores expires if cache-control disallows it", function()
  local headers = get({},
                      {["Cache-Control"] = "no-cache",
                       ["Expires"] = "Sun, 22 Dec 2023 19:43:52 GMT",
                       ["Content-Type"] = "text/html"})
  return not (headers:match("Age: (.*)") and
         headers:match("X%-Content%-Digest"))
end)

test("respects Pragma: no-cache", function()
  local headers = get({},
                      {["Pragma"] = "no-cache",
                       ["Expires"] = "Sun, 22 Dec 2023 19:43:52 GMT"})
  return not (headers:match("Age: (.*)") and
         headers:match("X%-Content%-Digest"))
end)

test("caches and returns response headers", function()
  local headers = get({}, {['Content-Type'] = 'text/html',
                           ['Cache-Control'] = 'max-age=180, public'})
  return headers:match("ttl: 180") and
         headers:match("Content%-Type: text/html") and
         headers:match("X-Cache: miss store")
end)

test("responds with gzipped content when Accept-Encoding includes gzip", function()
  local resp = {['Content-Encoding'] = 'gzip',
                ['Cache-Control'] = 'max-age=180, public'}
  get({['Accept-Encoding'] = 'gzip'}, resp, false)
  local headers = get({['Accept-Encoding'] = 'gzip'}, resp, false)
  return headers:match("gzip")
end)

test("responds with upzipped content when Accept-Encoding does not include gzip", function()
  local resp = {['Content-Encoding'] = 'gzip',
                ['Cache-Control'] = 'max-age=180, public'}
  get({['Accept-Encoding'] = 'chicken'}, resp, false)
  local headers = get({['Accept-Encoding'] = 'chicken'}, resp)
  return not headers:match("gzip")
end)

test("304s if etags matches If-None-Match", function()
  local server_response_headers = {
    ["Cache-Control"] = "max-age=180, public",
    ["ETag"] = "123"
  }

  get({["If-None-Match"] = "123"}, server_response_headers, false)
  local headers = get({["If-None-Match"] = "123"}, server_response_headers)

  return headers:match("304 Not Modified")
end)

test("excludes disallowed 304 headers on 304", function()
  local headers_to_omit = {
    ["Allow"] = "POST",
    ["Content-Encoding"] = "gzip",
    ["Content-Language"] = "en",
    ["Content-Length"] = "123",
    ["Content-MD5"] = "123",
    ["Last-Modified"] = "Sat, 01 Jul 2036 01:50:55 UTC",
  }

  local server_response_headers = {
    ["Cache-Control"] = "max-age=180, public",
    ["ETag"] = "123"
  }

  for k,v in pairs(headers_to_omit) do
    server_response_headers[k] = v
  end

  get({["If-None-Match"] = "123"}, server_response_headers, false)
  local headers = get({["If-None-Match"] = "123"}, server_response_headers)

  local includes_omitted = nil
  for k, _ in pairs(headers_to_omit) do
    k = k:gsub('-', '%%-')
    includes_omitted = (includes_omitted or headers:match(k))
  end

  return headers:match("304 Not Modified") and not includes_omitted
end)

for _, t in pairs({'no-cache',
                   'no-store',
                   'private',
                   'must-revalidate',
                   'proxy-revalidate'})
do
  test("does not cache if " .. t .. " is set", function()
    local headers = get({},
                        {["Cache-Control"] = "max-age=180, " .. t,
                        ["Content-Type"] = "text/html"})
    return headers:match("X-Cache: miss pass")
  end)
end

test("caches unique values for headers specified by varies header", function()
  local resp = {["Cache-Control"] = "max-age=180, public",
       ["Chicken"] = "blue",
       ["Vary"] = "Content-Type, Chicken"}

  get({["Chicken"] = "blue"}, resp, false)

  local headers = get({["Chicken"] = "green"}, resp)
  assert(headers:match("X-Cache: miss store"))

  headers = get({["Content-Type"] = "green"}, resp, false)
  assert(headers:match("X-Cache: miss store"))

  headers = get({["Content-Type"] = "green"}, resp, false)
  assert(headers:match("X-Cache: hit"))

  headers = get({["Content-Type"] = "greens", ["Zerp"] = "fun"}, resp)

  return assert(headers:match("X-Cache: miss store"))
end)

test("after hit callback works", function()
  get({}, {['Cache-Control'] = "max-age=50, public"}, false)
  local headers = get({}, {['Cache-Control'] = "max-age=50, public"})
  return headers:match("after%-hit: true")
end)

stop_server()

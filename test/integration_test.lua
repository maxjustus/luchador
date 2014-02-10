require "test_helper"
io = require "io"
os = require "os"

function get(request_headers, response_headers, flush, http_10)
  if flush == nil then flush = true end
  local header_string = ''
  if flush then request_headers['clear-ngx-cache'] = 'true' end
  for h, v in pairs(request_headers) do
    header_string = header_string .. '-H "' .. h .. ':' .. v .. '" '
  end

  local path = ''
  for h, v in pairs(response_headers) do
    path = path .. h .. ':' .. v .. ';'
  end

  local flags = ''
  if http_10 then
    flags = ' -0 -H "Connection: Keep-Alive" '
  end

  local command = 'curl 2>/dev/null ' .. header_string .. flags .. ' -I "localhost:8081/' .. path .. '"'
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
  os.execute('pkill -f "nginx -c $(echo $(pwd))"')
end

start_server()

test("supports max-age", function()
  local headers = get({},
                      {["Cache-Control"] = "max-age=180, public",
                       ["Content-Type"] = "text/html"})
  assert_match(headers, "Age: (.*)")
  assert_match(headers, "X-Cache: miss store")
end)

test("supports s-maxage", function()
  local headers = get({},
                      {["Cache-Control"] = "s-maxage=800, max-age=180, public",
                       ["Content-Type"] = "text/html"})
  assert_match(headers, "ttl: 800")
  assert_match(headers, "Age: (.*)")
  assert_match(headers, "X-Cache: miss store")
end)

test("supports expires", function()
  local headers = get({},
                      {["Cache-Control"] = "public",
                       ["Expires"] = "Sat, 01 Jul 2036 01:50:55 UTC",
                       ["Content-Type"] = "text/html"})
  assert_match(headers, "ttl: %d%d%d")
  assert_match(headers, "Age: (.*)")
  assert_match(headers, "X%-Content%-Digest")
end)

test("ignores expires if cache-control disallows it", function()
  local headers = get({},
                      {["Cache-Control"] = "no-cache",
                       ["Expires"] = "Sun, 22 Dec 2023 19:43:52 GMT",
                       ["Content-Type"] = "text/html"})
  assert(not headers:match("Age: (.*)"))
  assert(not headers:match("X%-Content%-Digest"))
end)

test("respects Pragma: no-cache", function()
  local headers = get({},
                      {["Pragma"] = "no-cache",
                       ["Expires"] = "Sun, 22 Dec 2023 19:43:52 GMT"})
  assert(not headers:match("Age: (.*)"))
  assert(not headers:match("X%-Content%-Digest"))
end)

test('records that a page should not be cached and skips cache on subsequent requests', function()
  local headers = get({}, {}, false)
  local headers = get({}, {})
  assert(headers:match("upstream"))
end)

test("caches and returns response headers", function()
  local headers = get({}, {['Content-Type'] = 'text/html',
                           ['Cache-Control'] = 'max-age=180, public'})
  assert_match(headers, "ttl: 180")
  assert_match(headers, "Content%-Type: text/html")
  assert_match(headers, "X-Cache: miss store")
end)

test("responds with gzipped content when Accept-Encoding includes gzip", function()
  local resp = {['Content-Encoding'] = 'gzip',
                ['Cache-Control'] = 'max-age=180, public'}
  get({['Accept-Encoding'] = 'gzip'}, resp, false)
  local headers = get({['Accept-Encoding'] = 'gzip'}, resp, false)
  assert_match(headers, "gzip")
end)

test("responds with upzipped content when Accept-Encoding does not include gzip", function()
  local resp = {['Content-Encoding'] = 'gzip',
                ['Cache-Control'] = 'max-age=180, public'}
  get({['Accept-Encoding'] = 'chicken'}, resp, false)
  local headers = get({['Accept-Encoding'] = 'chicken'}, resp)
  assert(not headers:match("gzip"))
end)

test("304s if etags matches If-None-Match", function()
  local server_response_headers = {
    ["Cache-Control"] = "max-age=180, public",
    ["ETag"] = "123"
  }

  get({["If-None-Match"] = "123"}, server_response_headers, false)
  local headers = get({["If-None-Match"] = "123"}, server_response_headers)

  assert_match(headers, "304 Not Modified")
  assert_match(headers, "X-Cache: local hit")
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

  for k, _ in pairs(headers_to_omit) do
    k = k:gsub('-', '%%-')
    assert(not headers:match(k))
  end

  assert_match(headers, "304 Not Modified")
end)

test("sets content-length for http 1.0", function()
  local headers = get({}, {['Content-Type'] = 'text/html',
                           ['Cache-Control'] = 'max-age=10, public'}, true, true)
  assert_match(headers, "keep%-alive")
  assert_match(headers, "Content%-Length")
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
    assert_match(headers, "X-Cache: miss pass")
  end)
end

test("caches unique values for headers specified by varies header", function()
  local resp = {["Cache-Control"] = "max-age=180, public",
       ["Chicken"] = "blue",
       ["Vary"] = "Content-Type, Chicken"}

  get({["Chicken"] = "blue"}, resp, false)

  local headers = get({["Chicken"] = "green"}, resp)
  assert_match(headers, "X%-Cache: miss store")

  headers = get({["Content-Type"] = "green"}, resp, false)
  assert_match(headers, "X%-Cache: miss store")

  headers = get({["Content-Type"] = "green"}, resp, false)
  assert_match(headers, "X%-Cache: hit")

  headers = get({["Content-Type"] = "greens", ["Zerp"] = "fun"}, resp)
  assert_match(headers, "X%-Cache: miss store")
end)

test("Caches locally once min_hits_for_local is met", function()
  local resp = {['Content-Type'] = 'text/html', ['Cache-Control'] = 'max-age=10, public'}
  get({}, resp, false)
  get({}, resp, false)
  local headers = get({}, resp, false)
  assert_match(headers, "X%-Hit%-Count: 2")
  assert_match(headers, "X%-Cache: local hit")
end)

test("before_response callback works", function()
  local headers = get({}, {['Cache-Control'] = "max-age=50, public"}, false)
  assert_match(headers, "before%-response: miss%-store")
  assert_match(headers, "before%-response%-status: 200")

  headers = get({}, {['Cache-Control'] = "max-age=50, public"})
  assert_match(headers, "before%-response: hit")
end)

-- see test/nginx/nginx.conf
test("supports page_key_filter", function()
  local headers = get({['page-key-filter'] = 'true'},
  {['Cache-Control'] = "max-age=50, public"}, true)
  assert_match(headers, 'Filtered: true')
end)

stop_server()

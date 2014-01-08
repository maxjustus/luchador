package.path = package.path .. ";../lib/?.lua"
require "test_helper"
cache_control = require "luchador.cache_control"

test("parsing max-age", function()
  local r = cache_control.parse("Max-Age=180, public")
  return assert_equal(r["max-age"], "180") and
                      assert_equal(r["public"], true)
end)


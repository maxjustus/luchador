function test(label, scenario)
  local success = xpcall(scenario, function(message)
    print("FAIL " .. label)
    print(message)
    print(debug.traceback())
  end)

  if success then print(".") end
end

function assert_equal(lval, rval)
  assert(lval == rval)
end

function assert_match(string, matcher)
  assert(string:match(matcher))
end


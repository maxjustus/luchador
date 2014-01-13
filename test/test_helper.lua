function test(label, scenario)
	local success, result, message = xpcall(scenario, function()
		print("FAIL " .. label)
		print(message)
		print(debug.traceback())
  end)

	if success and result then
		print(".")
	end
end

function assert_equal(lval, rval)
	if lval == rval then
		return true
	else
		local message = "Expected " .. (lval or "nil") ..
		                " to equal " .. (rval or "nil")
		return false, message
	end
end


function test(label, scenario)
	local success, result, message = pcall(scenario)
	if success and result then
		print(".")
	else
		print("FAIL " .. label)
		print(message)
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


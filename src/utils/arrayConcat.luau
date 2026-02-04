--!strict
type Array<T> = { [number]: T }

return function<T>(...: Array<T>): Array<T>
	local result = {} :: Array<T>
	local arg = { ... } :: { Array<T> }

	for _i, array in ipairs(arg) do
		for _x, element in ipairs(array) do
			table.insert(result, element)
		end
	end

	return result
end

--!strict
type AnyTable = { [any]: any }

-- The function used for deep cloning a table
local function deepClone<T>(original: T): T
	local seen: { [AnyTable]: AnyTable } = {}

	local function cloneValue(value: any): any
		if type(value) ~= "table" then
			return value
		end

		local existing = seen[value]
		if existing then
			return existing
		end

		local copy: any = table.clone(value)
		seen[value] = copy

		for key, child in value do
			copy[key] = cloneValue(child)
		end

		return copy
	end

	return cloneValue(original)
end

return deepClone

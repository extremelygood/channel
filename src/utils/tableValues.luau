--!strict
return function<T>(tbl: { [any]: T }): { T }
	local vals = {}
	for _k, v in pairs(tbl) do
		table.insert(vals, v)
	end
	return vals
end

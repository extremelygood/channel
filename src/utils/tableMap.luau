--!strict
type Reducer<V, K, T> = (V, K) -> T

return function<K, V, T>(tbl: { [K]: V }, reducer: Reducer<V, K, T>): { [K]: T }
	local newTable = {}
	for key, value in pairs(tbl) do
		newTable[key] = reducer(value, key)
	end
	return newTable
end

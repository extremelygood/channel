--!strict

--[=[
    Top level class of all objects, providing some utilities

    @class Object
]=]
local Object = {}
local function hideIndexSet(someTable: any)
	someTable.__index = someTable
end
hideIndexSet(Object)

export type ObjectType = {} & typeof(Object)

--[=[
    Construct a new object

    @within Object
]=]
function Object.new(): ObjectType
	local self = {}
	setmetatable(self, Object)

	return self :: any
end

--[=[
	Extend an object. Allows for easy typecheck compatible inheritance

	@within Object
	@method extend
	@param metatable table -- table of functions (methods)  to be attached
	@param properties table -- table of properties (fields) to be attached
	@return self -- (for typechecking purposes, no new object is created!)
	@error "Missing Parameters" -- if any of the parameters are missing
]=]
function Object.extend<O, T, P>(self: O, metatable: T, properties: P): O & T & P
	assert(self, `Object - Attempt to extend object, but self is nil!`)
	assert(metatable, `Object - Attempt to extend object, but metatable is nil!`)
	assert(properties, `Object - Attempt to extend object, but properties is nil!`)

	local refinedSelf = self :: any

	for propertyName, value in pairs(properties :: any) do
		refinedSelf[propertyName] = value
	end
	setmetatable(self :: any, metatable)
	return self :: any
end

--[=[
	Method to append properties to an existing object. This is useful when constructing an object in multiple steps (when a single :extend is not enough).
	This can happen when, for example, trying to add a member that needs a reference to the object that is actively being constructed. 
	Avoids casting.

	@within Object
	@method append
	@param properties table -- some table of properties to be attached
	@return self -- (for typechecking properites, no new object is created!)
]=]
function Object.append<O, P>(self: O, properties: P): O & P
	local refinedSelf = self :: any
	local refinedProperties = properties :: { [string]: any } & any

	for key, value in pairs(refinedProperties) do
		refinedSelf[key] = value
	end

	return refinedSelf
end

--[=[
	Method to implement a mixin (for multiple inheritance)

	@within Object
	@method mixin
	@param mixer table -- the table that provides the methods and functions
	@return table -- combined object of receiver and mixer
]=]
function Object.mixin<O, M>(self: O, mixer: M): O & M
	local theMetaTable = getmetatable(self :: any)
	assert(theMetaTable, `Object - Failed to mixin. Could not find metatable`)

	local theMixer = mixer :: any
	for key, value in pairs(theMixer) do
		if theMetaTable[key] then
			continue
		end
		theMetaTable[key] = value
	end

	return self :: O & M
end

--[=[
	Utility class method to set a metatable and index without the dumb ahh typechecker taking it as an invitation to bomb the type with metatables

	@within Object
	@function setIndexAndMeta
	@param baseTable table -- the table to receive metatable
	@param meta table -- the table to be attached as a metatable

]=]
function Object.setIndexAndMeta(baseTable: any, meta: any)
	baseTable.__index = baseTable
	if meta then
		setmetatable(baseTable, meta)
	end
end

return Object

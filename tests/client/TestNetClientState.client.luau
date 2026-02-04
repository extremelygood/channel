--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetClientState = require(ReplicatedStorage.Packages.Channel.netWorld.NetClientState)
local _netWorldPackets = require(ReplicatedStorage.Packages.Channel.netWorld._netWorldPackets)

type NodesUpdate = _netWorldPackets.NodesUpdate

local failures = 0

local function fail(message: string)
	error(message, 2)
end

local function assertEqual<T>(actual: T, expected: T, message: string?)
	if actual ~= expected then
		fail(message or `Expected {tostring(expected)}, got {tostring(actual)}`)
	end
end

local function assertTruthy(value: any, message: string?)
	if not value then
		fail(message or "Expected value to be truthy")
	end
end

local function assertTableContains(list: { string }, value: string, message: string?)
	if table.find(list, value) == nil then
		fail(message or `Expected list to contain {value}`)
	end
end

local function run(name: string, fn: () -> ())
	local ok, err = (pcall :: any)(fn)
	if ok then
		print(`[PASS] NetClientState {name}`)
	else
		failures += 1
		warn(`[FAIL] NetClientState {name}: {err}`)
	end
end

local function makeFullEvent(): NodesUpdate
	return {
		type = "NodesUpdate",
		isFull = true,
		hide = {},
		show = {
			{
				channelId = "1",
				topic = "root",
				immutableData = "root-data",
				parentId = nil :: string?,
				children = { "2" },
			},
			{
				channelId = "2",
				topic = "child",
				immutableData = "child-data",
				parentId = "1",
				children = {},
			},
		},
	}
end

run("create initializes empty state", function()
	local state = NetClientState.create()
	assertEqual(state.fullStateReceived, false, "fullStateReceived should start false")
	assertEqual(next(state.channels), nil, "channels should start empty")
end)

run("ignores non-full update before full state", function()
	local state = NetClientState.create()
	local event: NodesUpdate = {
		type = "NodesUpdate",
		isFull = false,
		hide = {},
		show = {
			{
				channelId = "1",
				topic = "root",
				immutableData = "root-data",
				parentId = nil,
				children = {},
			},
		},
	}

	local newState, effects = NetClientState.reduceEvent(state, event)
	assertEqual(newState, state, "state should be unchanged when full state not received")
	assertEqual(#effects, 0, "no effects expected before full state")
	assertEqual(next(newState.channels), nil, "channels should remain empty")
end)

run("full update sets state and creates channels", function()
	local state = NetClientState.create()
	local event = makeFullEvent()
	local newState, effects = NetClientState.reduceEvent(state, event)

	assertEqual(newState.fullStateReceived, true, "fullStateReceived should be true after full update")
	assertTruthy(newState.channels["1"], "root channel missing")
	assertTruthy(newState.channels["2"], "child channel missing")
	assertTableContains(newState.channels["1"].children, "2", "parent should list child")

	local created = {}
	for _, effect in effects do
		if effect.type == "CreateChannel" then
			created[effect.channelId] = true
		end
	end
	assertTruthy(created["1"], "missing create effect for root")
	assertTruthy(created["2"], "missing create effect for child")
end)

run("remove child updates parent children", function()
	local state = NetClientState.create()
	local fullState, _ = NetClientState.reduceEvent(state, makeFullEvent())

	local event: NodesUpdate = {
		type = "NodesUpdate",
		hide = { "2" },
		show = {},
		isFull = true,
	}

	local newState, _effects = NetClientState.reduceEvent(fullState, event)
	assertEqual(newState.channels["2"] :: any, nil, "child should be removed")
	assertEqual(#newState.channels["1"].children, 0, "parent children should be emptied")
end)

run("remove parent removes children recursively", function()
	local state = NetClientState.create()
	local fullState, _ = NetClientState.reduceEvent(state, makeFullEvent())

	local event: NodesUpdate = {
		type = "NodesUpdate",
		hide = { "1" },
		show = {},
		isFull = true,
	}

	local newState, effects = NetClientState.reduceEvent(fullState, event)
	assertEqual(next(newState.channels), nil, "all channels should be removed")

	local removed = {}
	for _, effect in effects do
		if effect.type == "RemoveChannel" then
			removed[effect.channelId] = true
		end
	end
	assertTruthy(removed["1"], "missing remove effect for root")
	assertTruthy(removed["2"], "missing remove effect for child")
end)

run("channelFromId returns a deep clone", function()
	local state = NetClientState.create()
	local fullState, _ = NetClientState.reduceEvent(state, makeFullEvent())
	local channel = NetClientState.channelFromId(fullState, "1")
	assertTruthy(channel, "channel should exist")
	assert(channel) -- Typechecker tomfoolery
	table.insert(channel.children, "x")
	assertEqual(#fullState.channels["1"].children, 1, "state should not be mutated by channelFromId result")
end)

if failures > 0 then
	error(`NetClientState tests failed: {failures}`)
end

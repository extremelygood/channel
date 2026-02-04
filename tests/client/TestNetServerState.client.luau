--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetServerState = require(ReplicatedStorage.Packages.Channel.netWorld.NetServerState)
local _netTypes = require(ReplicatedStorage.Packages.Channel._netTypes)
local _netWorldEvents = require(ReplicatedStorage.Packages.Channel.netWorld._netWorldEvents)

type ReplicationState = _netTypes.ReplicationState
type Event = _netWorldEvents.Event

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
		print(`[PASS] NetServerState {name}`)
	else
		failures += 1
		warn(`[FAIL] NetServerState {name}: {err}`)
	end
end

local function replication(mode: "ALL" | "SPECIFIED" | "NONE", players: { Player }?, locked: boolean?): ReplicationState
	return {
		isLockedToParent = locked == true,
		mode = mode,
		players = players or {},
	}
end

run("create channel increments id and stores channel", function()
	local state = NetServerState.create()
	local event: Event = {
		type = "CreateNewChannel",
		topic = "root",
		immutableData = "root-data",
		parent = nil,
		replicationState = replication("ALL"),
	}

	local newState, effects = NetServerState.reduceEvent(state, event)
	assertEqual(newState.nextId, 1, "nextId should increment")
	assertTruthy(newState.channels["1"], "root channel missing")

	local foundCreate = false
	for _, effect in effects do
		if effect.type == "CreateChannel" then
			foundCreate = true
			assertEqual(effect.channel.channelId, "1", "create effect channelId mismatch")
		end
	end
	assertTruthy(foundCreate, "create effect not found")
end)

run("create child attaches to parent", function()
	local state = NetServerState.create()
	local parentEvent: Event = {
		type = "CreateNewChannel",
		topic = "root",
		immutableData = "root-data",
		parent = nil,
		replicationState = replication("ALL"),
	}
	local stateWithParent, _ = NetServerState.reduceEvent(state, parentEvent)

	local childEvent: Event = {
		type = "CreateNewChannel",
		topic = "child",
		immutableData = "child-data",
		parent = "1",
		replicationState = replication("ALL"),
	}
	local newState, _effects = NetServerState.reduceEvent(stateWithParent, childEvent)

	assertTruthy(newState.channels["2"], "child channel missing")
	assertTableContains(newState.channels["1"].children, "2", "parent should list child")
end)

run("destroy removes parent and children", function()
	local state = NetServerState.create()
	local parentEvent: Event = {
		type = "CreateNewChannel",
		topic = "root",
		immutableData = "root-data",
		parent = nil,
		replicationState = replication("ALL"),
	}
	local stateWithParent, _ = NetServerState.reduceEvent(state, parentEvent)

	local childEvent: Event = {
		type = "CreateNewChannel",
		topic = "child",
		immutableData = "child-data",
		parent = "1",
		replicationState = replication("ALL"),
	}
	local stateWithChild, _ = NetServerState.reduceEvent(stateWithParent, childEvent)

	local destroyEvent: Event = {
		type = "DestroyChannel",
		uniqueId = "1",
	}
	local newState, effects = NetServerState.reduceEvent(stateWithChild, destroyEvent)

	assertEqual(newState.channels["1"] :: any, nil, "parent should be removed")
	assertEqual(newState.channels["2"] :: any, nil, "child should be removed")

	local destroyed = {}
	for _, effect in effects do
		if effect.type == "DestroyChannel" then
			destroyed[effect.channelId] = true
		end
	end
	assertTruthy(destroyed["1"], "missing destroy effect for parent")
	assertTruthy(destroyed["2"], "missing destroy effect for child")
end)

run("change replication rejects wider than parent", function()
	local state = NetServerState.create()
	local parentEvent: Event = {
		type = "CreateNewChannel",
		topic = "root",
		immutableData = nil,
		parent = nil,
		replicationState = replication("NONE"),
	}
	local stateWithParent, _ = NetServerState.reduceEvent(state, parentEvent)

	local childEvent: Event = {
		type = "CreateNewChannel",
		topic = "child",
		immutableData = nil,
		parent = "1",
		replicationState = replication("NONE"),
	}
	local stateWithChild, _ = NetServerState.reduceEvent(stateWithParent, childEvent)

	local changeEvent: Event = {
		type = "ChangeReplication",
		channelId = "2",
		desiredReplicationState = replication("ALL"),
	}
	local newState, _effects = NetServerState.reduceEvent(stateWithChild, changeEvent)

	assertEqual(newState.channels["2"].replicationState.mode, "NONE", "child replication should remain constrained")
end)

run("locked child follows parent replication", function()
	local localPlayer = Players.LocalPlayer
	local playerList = {}
	if localPlayer then
		table.insert(playerList, localPlayer)
	end

	local state = NetServerState.create()
	local parentEvent: Event = {
		type = "CreateNewChannel",
		topic = "root",
		immutableData = nil,
		parent = nil,
		replicationState = replication("SPECIFIED", playerList, false),
	}
	local stateWithParent, _ = NetServerState.reduceEvent(state, parentEvent)

	local childEvent: Event = {
		type = "CreateNewChannel",
		topic = "child",
		immutableData = nil,
		parent = "1",
		replicationState = replication("NONE", {}, true),
	}
	local stateWithChild, _ = NetServerState.reduceEvent(stateWithParent, childEvent)

	local changeEvent: Event = {
		type = "ChangeReplication",
		channelId = "1",
		desiredReplicationState = replication("ALL"),
	}
	local newState, _effects = NetServerState.reduceEvent(stateWithChild, changeEvent)

	assertEqual(newState.channels["1"].replicationState.mode, "ALL", "parent replication should update")
	assertEqual(newState.channels["2"].replicationState.mode, "ALL", "locked child should match parent replication")
	assertEqual(newState.channels["2"].replicationState.isLockedToParent, true, "locked flag should remain true")
end)

if failures > 0 then
	error(`NetServerState tests failed: {failures}`)
end

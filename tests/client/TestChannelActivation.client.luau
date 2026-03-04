--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChannelClient = require(ReplicatedStorage.Packages.Channel.channels.ChannelClient)
local NetWorldClient = require(ReplicatedStorage.Packages.Channel.netWorld.NetWorldClient)
local _netWorldPackets = require(ReplicatedStorage.Packages.Channel.netWorld._netWorldPackets)
local fSignal = require(ReplicatedStorage.Packages.Channel.utils.fSignal)

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

local function run(name: string, fn: () -> ())
	local ok, err = (pcall :: any)(fn)
	if ok then
		print(`[PASS] ChannelActivation {name}`)
	else
		failures += 1
		warn(`[FAIL] ChannelActivation {name}: {err}`)
	end
end

run("ChannelClient onActive transitions from inactive with alreadyActive=false", function()
	local active = false
	local onActive = fSignal()

	local channel = ChannelClient.new("topic", "id", {
		bindOnChild = function()
			return function() end
		end,
		bindOnMessage = function()
			return function() end
		end,
		bindOnDestroy = function()
			return function() end
		end,
		bindOnActive = onActive.bind,
		fireServer = function() end,
		queryChildren = function()
			return {}
		end,
		queryImmutableData = function()
			return nil
		end,
		queryParent = function()
			return nil
		end,
		queryIsActive = function()
			return active
		end,
	})

	assertEqual(channel:isActive(), false, "channel should start inactive")

	local callCount = 0
	local lastAlreadyActive = true
	channel:onActive(function(alreadyActive)
		callCount += 1
		lastAlreadyActive = alreadyActive
	end)

	assertEqual(callCount, 0, "onActive should not fire while still inactive")

	active = true
	onActive.fire(true)

	assertEqual(callCount, 1, "onActive should fire after activation")
	assertEqual(lastAlreadyActive, false, "transition activation should report alreadyActive=false")
end)

run("NetWorldClient channel and expected channel expose activation correctly", function()
	local packetSignal = fSignal()
	local sentPackets = {}
	local netClient = NetWorldClient.new(function(packet)
		table.insert(sentPackets, packet)
	end, packetSignal.bind)

	assertTruthy(sentPackets[1], "client should send CheckIn on startup")
	assertEqual(sentPackets[1].type, "CheckIn", "first packet should be CheckIn")

	local createdChannel = nil
	netClient:onChannel(function(newChannel)
		if newChannel:topic() == "root" then
			createdChannel = newChannel
		end
	end)

	local expectedRoot = netClient:expectChannel(function(channel)
		return channel:topic() == "root"
	end)

	assertEqual(expectedRoot:isActive(), false, "expected channel should be inactive before resolve")

	local expectedPreResolveCalls = 0
	local expectedPreResolveAlreadyActive = true
	expectedRoot:onActive(function(alreadyActive)
		expectedPreResolveCalls += 1
		expectedPreResolveAlreadyActive = alreadyActive
	end)

	local showRoot: NodesUpdate = {
		type = "NodesUpdate",
		isFull = true,
		hide = {},
		show = {
			{
				channelId = "1",
				topic = "root",
				immutableData = nil,
				parentId = nil,
				children = {},
			},
		},
	}
	packetSignal.fire(showRoot)

	assertTruthy(createdChannel, "root channel should be created")
	assert(createdChannel)
	assertEqual(createdChannel:isActive(), true, "newly created channel should be active")

	local channelOnActiveCalls = 0
	local channelAlreadyActive = false
	createdChannel:onActive(function(alreadyActive)
		channelOnActiveCalls += 1
		channelAlreadyActive = alreadyActive
	end)
	assertEqual(channelOnActiveCalls, 1, "onActive should fire immediately for active channel")
	assertEqual(channelAlreadyActive, true, "immediate onActive should report alreadyActive=true")

	assertEqual(expectedPreResolveCalls, 1, "expected onActive should fire on resolve")
	assertEqual(expectedPreResolveAlreadyActive, false, "resolve activation should report alreadyActive=false")
	assertEqual(expectedRoot:isActive(), true, "expected channel should be active after resolve")

	local expectedPostResolveCalls = 0
	local expectedPostResolveAlreadyActive = false
	expectedRoot:onActive(function(alreadyActive)
		expectedPostResolveCalls += 1
		expectedPostResolveAlreadyActive = alreadyActive
	end)
	assertEqual(expectedPostResolveCalls, 1, "expected onActive should fire immediately after resolve")
	assertEqual(expectedPostResolveAlreadyActive, true, "post-resolve immediate activation should report true")

	local destroyedCalls = 0
	createdChannel:onDestroy(function()
		destroyedCalls += 1
	end)

	local hideRoot: NodesUpdate = {
		type = "NodesUpdate",
		isFull = true,
		hide = { "1" },
		show = {},
	}
	packetSignal.fire(hideRoot)

	assertEqual(destroyedCalls, 1, "onDestroy should fire exactly once on channel removal")
	assertEqual(createdChannel:isActive(), false, "retained channel reference should become inactive after removal")
	assertEqual(channelOnActiveCalls, 1, "channel onActive should not re-fire on removal")
end)

if failures > 0 then
	error(`ChannelActivation tests failed: {failures}`)
end

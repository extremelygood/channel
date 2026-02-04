--!strict
local RunService = game:GetService("RunService")

local fSignal = require(script.Parent.Parent.utils.fSignal)
local groupSignal = require(script.Parent.Parent.utils.groupSignal)
local _netTypes = require(script.Parent.Parent._netTypes)
local _netUtils = require(script.Parent.Parent._netUtils)
local ExpectedChannel = require(script.Parent.Parent.channels.ExpectedChannel)
local NetWorldClient = require(script.Parent.Parent.netWorld.NetWorldClient)

local ClientMain = {}

type AnyChannelClient = _netTypes.AnyChannelClient

-- Globals
local netClient: _netTypes.NetWorldClient?
local onChannel = fSignal()
local onTopic = groupSignal()
local clientCreationInvoked = false

--[[
    Public
]]
function ClientMain.onChannel(eventHandler: (newChannel: AnyChannelClient) -> ()): () -> ()
	assert(RunService:IsClient(), `Not running on client!`)
	return onChannel.bind(eventHandler)
end

function ClientMain.onTopic(topic: string, eventHandler: (newChannel: AnyChannelClient) -> ()): () -> ()
	assert(RunService:IsClient(), `Not running on client!`)
	return onTopic.bind(topic, eventHandler)
end

function ClientMain.expectChannel(predicate: (newChannel: AnyChannelClient) -> boolean): AnyChannelClient
	return ExpectedChannel.new(ClientMain.onChannel, ClientMain.allChannels, predicate)
end

function ClientMain.allChannels(): { AnyChannelClient }
	if netClient then
		return netClient:allChannels()
	else
		return {}
	end
end

--[[
    Private
]]
local function _createClient()
	assert(RunService:IsClient(), `createClient can only be executed from the client!`)
	assert(not clientCreationInvoked, `createClient can only be called once!`)
	clientCreationInvoked = true

	task.spawn(function()
		local remote = script.Parent:WaitForChild(_netUtils.RemoteName)
		assert(
			remote:IsA("RemoteEvent"),
			`Expected instance at {remote:GetFullName()} to be a RemoteEvent, got {remote.ClassName} instead`
		)

		local receiveSignal = fSignal()
		remote.OnClientEvent:Connect(receiveSignal.fire)

		netClient = NetWorldClient.new(function(...)
			remote:FireServer(...)
		end, receiveSignal.bind)

		-- Have to do this, old typechecker not advanced enough
		assert(netClient)

		netClient:onChannel(function(newChannel)
			onChannel.fire(newChannel)
			onTopic.fire(newChannel:topic(), newChannel)
		end)
	end)
end
if RunService:IsClient() then
	_createClient()
end

return ClientMain

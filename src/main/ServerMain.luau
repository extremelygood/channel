--!strict
local RunService = game:GetService("RunService")

local fSignal = require(script.Parent.Parent.utils.fSignal)
local _netTypes = require(script.Parent.Parent._netTypes)
local _netUtils = require(script.Parent.Parent._netUtils)
local NetWorldServer = require(script.Parent.Parent.netWorld.NetWorldServer)

local ServerMain = {}

--[[
    Globals
]]
local serverCreationInvoked = false
local netServer: _netTypes.NetWorldServer

--[[
    Public
]]
function ServerMain.openChannel<D>(topic: string, immutableData: D?): _netTypes.ChannelServer<D>
	assert(RunService:IsServer(), `Not running on server!`)
	return netServer:openChannel(topic, immutableData)
end

--[[
    Private
]]
local function _createServer(): ()
	assert(RunService:IsServer(), `createServer can only be executed from the server!`)
	assert(not serverCreationInvoked, `createServer can only be called once!`)

	serverCreationInvoked = true

	local remote = Instance.new("RemoteEvent")
	remote.Name = _netUtils.RemoteName
	remote.Parent = script.Parent

	local receiveSignal = fSignal()
	remote.OnServerEvent:Connect(receiveSignal.fire)

	netServer = NetWorldServer.new(function(plr: Player, ...)
		remote:FireClient(plr, ...)
	end, function(...)
		remote:FireAllClients(...)
	end, receiveSignal.bind)
end
if RunService:IsServer() then
	_createServer()
end

return ServerMain

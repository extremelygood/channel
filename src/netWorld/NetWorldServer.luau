--!strict

local NetServerState = require(script.Parent.NetServerState)
local _netWorldEvents = require(script.Parent._netWorldEvents)
local _netWorldPackets = require(script.Parent._netWorldPackets)
local Object = require(script.Parent.Parent.utils.Object)
local fSignal = require(script.Parent.Parent.utils.fSignal)
local _netTypes = require(script.Parent.Parent._netTypes)
local ChannelServer = require(script.Parent.Parent.channels.ChannelServer)
local deepClone = require(script.Parent.Parent.utils.deepClone)
local tableMap = require(script.Parent.Parent.utils.tableMap)

local NetWorldServer = {}
Object.setIndexAndMeta(NetWorldServer, Object)

type INetWorld = _netTypes.NetWorldServer
type IChannelServer<D = nil> = _netTypes.ChannelServer<D>
type NetState = NetServerState.NetState
type NetContext = _netTypes.NetWorldContextServer
type Effect = NetServerState.Effect
type Event = _netWorldEvents.Event
type NodesUpdatePacket = _netWorldPackets.NodesUpdate
type Packet = _netWorldPackets.Packet
type ChannelState = NetServerState.Channel

type NetWorldServerImpl = INetWorld & typeof(NetWorldServer) & {
	sendClientFun: (player: Player, ...any) -> (),
	sendAllClientsFun: (...any) -> (),
	state: NetState,

	storedChannels: { [string]: StoredChannel },
}

local function typeHack(): (Player, ...any)
	return {} :: any
end

type StoredChannel = {
	object: IChannelServer,
	onMessageSignal: fSignal.FunSignal<typeof(typeHack())>,
	onDestroySignal: fSignal.FunSignal<>,
}

type Artifacts = {
	channel: IChannelServer<any>?,
}

function NetWorldServer.new(
	sendClient: (Player, ...any) -> (),
	sendAllClients: (...any) -> (),
	bindOnMessage: fSignal.BindFun<Player, Packet>
): INetWorld
	local self: NetWorldServerImpl = Object.new():extend(NetWorldServer, {
		state = NetServerState.create(),
		storedChannels = {},

		sendClientFun = sendClient,
		sendAllClientsFun = sendAllClients,
	})

	bindOnMessage(function(plr: Player, packet)
		self:_handlePacket(plr, packet)
	end)

	return self
end

function NetWorldServer.openChannel<D>(self: NetWorldServerImpl, topic: string, immutableData: D?): IChannelServer<D>
	local event: _netWorldEvents.CreateNewChannelEvent<D?> = {
		topic = topic,
		immutableData = immutableData,
		type = "CreateNewChannel",
		replicationState = {
			isLockedToParent = false,
			mode = "NONE",
			players = {},
		},
	}
	local artifacts = self:_handleEvent(event)
	assert(artifacts.channel, `Failed to open channel (missing artifact)`)
	return artifacts.channel
end

function NetWorldServer.fromId(self: NetWorldServerImpl, id: string): IChannelServer?
	local stored = self.storedChannels[id]
	if stored then
		return stored.object
	end

	return nil
end

--[[
    Private
]]

function NetWorldServer._createChannel(self: NetWorldServerImpl, channel: ChannelState): IChannelServer
	assert(not self:fromId(channel.channelId), `Channel with id {channel.channelId} already exists!`)

	local onMessageSignal = fSignal()
	local onDestroy = fSignal()

	local newChannel = ChannelServer.new(channel.topic, channel.channelId, {
		makeChild = function(topic: string, immutableData: any?)
			local channelState = NetServerState.channelFromId(self.state, channel.channelId)
			assert(channelState, `Attempt to query parent but self channel data not found`)

			local repState = deepClone(channelState.replicationState)
			repState.isLockedToParent = true

			local artifact = self:_handleEvent({
				type = "CreateNewChannel",
				replicationState = repState,
				topic = topic,
				immutableData = immutableData,
				parent = channel.channelId,
			})

			local resultChannel = artifact.channel
			assert(resultChannel, `Tried to make child, but failed.`)
			return resultChannel
		end,
		destroy = function()
			self:_handleEvent({
				type = "DestroyChannel",
				uniqueId = channel.channelId,
			})
		end,
		setReplication = function(newReplication)
			self:_handleEvent({
				type = "ChangeReplication",
				channelId = channel.channelId,
				desiredReplicationState = newReplication,
			})
		end,
		sendPacket = function(specificPlayer: Player, ...: any)
			self:_sendToPlayer(specificPlayer, {
				type = "ChannelMessage",
				channelId = channel.channelId,
				values = table.pack(...),
			})
		end,
		sendPacketAll = function(...: any)
			self:_sendToAll({
				type = "ChannelMessage",
				channelId = channel.channelId,
				values = table.pack(...),
			})
		end,
		queryParent = function()
			local channelState = NetServerState.channelFromId(self.state, channel.channelId)
			assert(channelState, `Attempt to query parent but self channel data not found`)

			local parentId = channelState.parentId

			if parentId then
				local found = self:fromId(parentId)
				assert(found, `Could not find channel object with parent id`)
				return found
			end
			return nil
		end,
		queryChildren = function()
			local channelState = NetServerState.channelFromId(self.state, channel.channelId)
			assert(channelState, `Attempt to query parent but self channel data not found`)

			return tableMap(channelState.children, function(childId: string)
				local childObj = self:fromId(childId)
				assert(childObj, `Attempt to resolve childId into child object failed. Not found`)
				return childObj
			end)
		end,
		queryReplicationState = function()
			local channelState = NetServerState.channelFromId(self.state, channel.channelId)
			assert(channelState, `Attempt to query parent but self channel data not found`)

			return channelState.replicationState
		end,
		queryImmutableData = function()
			local channelState = NetServerState.channelFromId(self.state, channel.channelId)
			assert(channelState, `Attempt to query parent but self channel data not found`)

			return channelState.replicationState
		end,
		bindOnMessage = onMessageSignal.bind,
		bindOnDestroy = onDestroy.bind,
	})

	self.storedChannels[channel.channelId] = {
		object = newChannel,
		onMessageSignal = onMessageSignal,
		onDestroySignal = onDestroy,
	}

	return newChannel
end

function NetWorldServer._destroyChannel(self: NetWorldServerImpl, channelId: string): ()
	local stored = self.storedChannels[channelId]
	assert(stored, `Attempt to destroy channel, could not find channel with id {channelId}`)

	self.storedChannels[channelId] = nil
	stored.onDestroySignal.fire()
end

function NetWorldServer._sendToPlayer(self: NetWorldServerImpl, player: Player, packet: Packet): ()
	self.sendClientFun(player, packet)
end

function NetWorldServer._sendToAll(self: NetWorldServerImpl, packet: Packet): ()
	return self.sendAllClientsFun(packet)
end

function NetWorldServer._runEffects(self: NetWorldServerImpl, effects: { Effect }): Artifacts
	local artifacts = {}

	for _i, effect in effects do
		if effect.type == "CreateChannel" then
			artifacts.channel = self:_createChannel(effect.channel)
		elseif effect.type == "DestroyChannel" then
			self:_destroyChannel(effect.channelId)
		elseif effect.type == "SendUpdate" then
			self:_sendToPlayer(effect.player, effect.packet)
		end
	end

	return artifacts
end

function NetWorldServer._handlePacket(self: NetWorldServerImpl, plr: Player, packet: Packet): ()
	if packet.type == "CheckIn" then
		self:_handleEvent({
			type = "FullState",
			player = plr,
		})
		return
	elseif packet.type == "ChannelMessage" then
		local stored = self.storedChannels[packet.channelId]

		-- Client could be operating with stale data
		if not stored then
			return
		end

		stored.onMessageSignal.fire(plr, table.unpack(packet.values))
		return
	end

	error(`No handler found for packet {packet} sent by player {plr.Name} or missing return statement`)
end

function NetWorldServer._handleEvent(self: NetWorldServerImpl, event: Event): Artifacts
	local newState, effects = NetServerState.reduceEvent(self.state, event)
	self.state = newState
	return self:_runEffects(effects)
end

return NetWorldServer

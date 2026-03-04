--!strict

local NetClientState = require(script.Parent.NetClientState)
local _netWorldEvents = require(script.Parent._netWorldEvents)
local _netWorldPackets = require(script.Parent._netWorldPackets)
local Object = require(script.Parent.Parent.utils.Object)
local fSignal = require(script.Parent.Parent.utils.fSignal)
local groupSignal = require(script.Parent.Parent.utils.groupSignal)
local _netTypes = require(script.Parent.Parent._netTypes)
local ChannelClient = require(script.Parent.Parent.channels.ChannelClient)
local ExpectedChannel = require(script.Parent.Parent.channels.ExpectedChannel)
local tableMap = require(script.Parent.Parent.utils.tableMap)
local tableValues = require(script.Parent.Parent.utils.tableValues)

local NetWorldClient = {}
Object.setIndexAndMeta(NetWorldClient, Object)

type AnyChannel = _netTypes.AnyChannelClient
type NetState = NetClientState.NetState
type INetWorldClient = _netTypes.NetWorldClient
type IChannelClient = _netTypes.ChannelClient
type FunSignal<T...> = fSignal.FunSignal<T...>
type EventHandler<T...> = fSignal.EventHandler<T...>
type DisconnectFun = fSignal.DisconnectFun

type StoredChannel = {
	object: IChannelClient,
	onChildAdded: fSignal.FunSignal<IChannelClient>,
	onMessage: fSignal.FunSignal<...any>,
	onDestroy: fSignal.FunSignal<>,
	onActive: fSignal.FunSignal<boolean>,
	isActive: boolean,
}

type NetWorldClientImpl = typeof(NetWorldClient) & {
	state: NetState,
	storedChannels: { [string]: StoredChannel },

	fireServerFun: (...any) -> (),

	onChannelSignal: FunSignal<AnyChannel>,
	onTopicSignal: groupSignal.GroupedSignal<string, AnyChannel>,
}

function NetWorldClient.new(fireServer: (...any) -> (), bindOnPacket: fSignal.BindFun<...any>): INetWorldClient
	local self: NetWorldClientImpl = Object.new():extend(NetWorldClient, {
		state = NetClientState.create(),
		storedChannels = {},

		fireServerFun = fireServer,

		onChannelSignal = fSignal(),
		onTopicSignal = groupSignal(),
	})

	bindOnPacket(function(...)
		self:_handlePacket(...)
	end)

	self:_doCheckIn()

	return self
end

function NetWorldClient.onChannel(self: NetWorldClientImpl, eventHandler: EventHandler<AnyChannel>): DisconnectFun
	return self.onChannelSignal.bind(eventHandler)
end

function NetWorldClient.onTopic(
	self: NetWorldClientImpl,
	topic: string,
	eventHandler: EventHandler<AnyChannel>
): () -> ()
	return self.onTopicSignal.bind(topic, eventHandler)
end

function NetWorldClient.expectChannel(self: NetWorldClientImpl, predicate: (AnyChannel) -> boolean): IChannelClient
	return ExpectedChannel.new(self.onChannelSignal.bind, function()
		return self:allChannels()
	end, predicate, nil)
end

function NetWorldClient.fromId(self: NetWorldClientImpl, id: string): AnyChannel?
	local stored = self.storedChannels[id]
	if stored then
		return stored.object
	end
	return nil
end

function NetWorldClient.allChannels(self: NetWorldClientImpl): { IChannelClient }
	return tableValues(tableMap(self.storedChannels, function(stored)
		return stored.object
	end))
end

--[[
    Private
]]

function NetWorldClient._doCheckIn(self: NetWorldClientImpl): ()
	local packet: _netWorldPackets.CheckIn = {
		type = "CheckIn",
	}
	self.fireServerFun(packet)
end

function NetWorldClient._createChannel(self: NetWorldClientImpl, effect: NetClientState.CreateChannelEffect): ()
	assert(not self:fromId(effect.channelId), `Channel with id {effect.channelId} already exists`)

	local channelData = NetClientState.channelFromId(self.state, effect.channelId)
	assert(channelData, `Could not find channel data in state for {effect.channelId}`)

	local onChildAdded = fSignal()
	local onMessage = fSignal()
	local onDestroy = fSignal()
	local onActive = fSignal()
	local storedChannel: StoredChannel

	local newObj = ChannelClient.new(channelData.topic, channelData.uniqueIdent, {
		fireServer = function(...: any)
			local packet: _netWorldPackets.ChannelMessage = {
				type = "ChannelMessage",
				channelId = effect.channelId,
				values = table.pack(...),
			}
			self.fireServerFun(packet)
		end,
		bindOnChild = function(eventHandler)
			return onChildAdded.bind(eventHandler)
		end,
		bindOnMessage = function(eventHandler)
			return onMessage.bind(eventHandler)
		end,
		queryChildren = function()
			local channelData = NetClientState.channelFromId(self.state, effect.channelId)
			if not channelData then
				return {}
			end

			local assembledChannels = {}
			for _i, childId in channelData.children do
				-- It could be possible for a children query to happen before child nodes are
				-- created. This is a bummer

				local childObj = self:fromId(childId)
				if childObj then
					table.insert(assembledChannels, childObj)
				end
			end

			return assembledChannels
		end,
		queryParent = function()
			local channelData = NetClientState.channelFromId(self.state, effect.channelId)
			if not channelData then
				return nil
			end

			local parentId = channelData.parent
			if parentId then
				return self:fromId(parentId)
			end

			return nil
		end,
		queryImmutableData = function()
			local channelData = NetClientState.channelFromId(self.state, effect.channelId)
			if not channelData then
				return nil
			end

			return channelData.immutableData
		end,
		bindOnDestroy = onDestroy.bind,
		bindOnActive = function(eventHandler)
			return storedChannel.onActive.bind(eventHandler)
		end,
		queryIsActive = function()
			return storedChannel.isActive
		end,
	})

	storedChannel = {
		object = newObj,
		onChildAdded = onChildAdded,
		onMessage = onMessage,
		onDestroy = onDestroy,
		onActive = onActive,
		isActive = true,
	}
	self.storedChannels[effect.channelId] = storedChannel
	storedChannel.onActive.fire(true)

	-- Events
	local parent = newObj:parent()
	if parent then
		local storedParent = self.storedChannels[parent:uniqueIdent()]
		assert(storedParent, `No stored parent`)

		storedParent.onChildAdded.fire(newObj)
	end
	self.onChannelSignal.fire(newObj)
	self.onTopicSignal.fire(channelData.topic, newObj)
end

function NetWorldClient._removeChannel(self: NetWorldClientImpl, effect: NetClientState.RemoveChannelEffect): ()
	local stored = self.storedChannels[effect.channelId]
	assert(stored, `Attempt to destroy channel with id {effect.channelId} failed, could not find`)

	stored.isActive = false
	self.storedChannels[effect.channelId] = nil

	stored.onDestroy.fire()
end

function NetWorldClient._runEffects(self: NetWorldClientImpl, effects: { NetClientState.Effect }): ()
	for _i, effect in effects do
		if effect.type == "CreateChannel" then
			self:_createChannel(effect)
		elseif effect.type == "RemoveChannel" then
			self:_removeChannel(effect)
		end
	end
end

function NetWorldClient._handlePacket(self: NetWorldClientImpl, packet: _netWorldPackets.Packet): ()
	if packet.type == "NodesUpdate" then
		local newState, effects = NetClientState.reduceEvent(self.state, packet)
		self.state = newState
		self:_runEffects(effects)
		return
	elseif packet.type == "ChannelMessage" then
		local storedChannel = self.storedChannels[packet.channelId]

		--[[
			I choose to return here instead of asserting, because in the future this
			event could handle "unreliable remote events". In this case, chronologicaly
			unsound messages could arrive.
		]]
		if not storedChannel then
			return
		end

		storedChannel.onMessage.fire(table.unpack(packet.values))
		return
	end

	error("No packet handler found, or missing return statement inside handler")
end

return NetWorldClient

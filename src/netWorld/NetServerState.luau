--!strict
local Players = game:GetService("Players")

local _netTypes = require(script.Parent.Parent._netTypes)
local ReplicationRules = require(script.Parent.Parent.replication.ReplicationRules)
local arrayConcat = require(script.Parent.Parent.utils.arrayConcat)
local deepClone = require(script.Parent.Parent.utils.deepClone)
local tableMap = require(script.Parent.Parent.utils.tableMap)
local _netWorldEvents = require(script.Parent._netWorldEvents)
local _netWorldPackets = require(script.Parent._netWorldPackets)
local NetServerState = {}

export type NetState = {
	nextId: number,
	channels: { [string]: Channel },
}

export type CreateChannelEffect = {
	type: "CreateChannel",
	channel: Channel,
}

export type DestroyChannelEffect = {
	type: "DestroyChannel",
	channelId: string,
}

export type SendUpdateEffect = {
	type: "SendUpdate",
	player: Player,
	packet: _netWorldPackets.NodesUpdate,
}

export type Effect = CreateChannelEffect | DestroyChannelEffect | SendUpdateEffect

export type Channel<D = nil> = {
	parentId: string?,
	channelId: string,
	topic: string,
	immutableData: D,
	children: { string },
	replicationState: ReplicationState,
}
type ReplicationState = _netTypes.ReplicationState

--[[ 
    Function to compute updates for players
        When stating the intention to hide a tree from a player,
            --> Will only return the top most hidden node. This assumes that all following nodes are implictily hidden
        When stating the intention to show a tree,
            --> Will name all nodes to be shown
]]
local function buildUpdatePacket(player: Player, oldState: NetState, newState: NetState): _netWorldPackets.NodesUpdate
	local function computeVisibilityMap(state: NetState): { [string]: boolean }
		local visibilityMap: { [string]: boolean } = {}

		local function isVisible(channelId: string): boolean
			local cached = visibilityMap[channelId]
			if cached ~= nil then
				return cached
			end

			local channel = NetServerState.channelFromId(state, channelId)
			if not channel then
				visibilityMap[channelId] = false
				return false
			end

			if not ReplicationRules.isReplicatedToPlayer(channel.replicationState, player) then
				visibilityMap[channelId] = false
				return false
			end

			if channel.parentId then
				if not isVisible(channel.parentId) then
					visibilityMap[channelId] = false
					return false
				end
			end

			visibilityMap[channelId] = true
			return true
		end

		for id in pairs(state.channels) do
			isVisible(id)
		end

		return visibilityMap
	end

	local function serializeChannel(
		channel: Channel,
		visibilityMap: { [string]: boolean }
	): _netWorldPackets.SerializedChannel
		local visibleChildren = {}
		for _i, childId in channel.children do
			if visibilityMap[childId] then
				table.insert(visibleChildren, childId)
			end
		end

		local parentId = channel.parentId
		if parentId and not visibilityMap[parentId] then
			parentId = nil
		end

		return {
			parentId = parentId,
			channelId = channel.channelId,
			topic = channel.topic,
			immutableData = channel.immutableData,
			children = visibleChildren,
		}
	end

	local oldVisibility = computeVisibilityMap(oldState)
	local newVisibility = computeVisibilityMap(newState)

	local hide = {}
	for id, channel in oldState.channels do
		if oldVisibility[id] and not newVisibility[id] then
			local parentId = channel.parentId
			if not parentId or not (oldVisibility[parentId] and not newVisibility[parentId]) then
				table.insert(hide, id)
			end
		end
	end

	local show = {}
	for id, channel in newState.channels do
		if newVisibility[id] and not oldVisibility[id] then
			table.insert(show, serializeChannel(channel, newVisibility))
		end
	end

	return {
		type = "NodesUpdate",
		hide = hide,
		show = show,
	}
end

local function buildUpdateEffects(players: { Player }, oldState: NetState, newState: NetState): { SendUpdateEffect }
	local effects = {}
	for _i, player in players do
		local computedPacket = buildUpdatePacket(player, oldState, newState)
		if #computedPacket.hide <= 0 and #computedPacket.show <= 0 then
			continue
		end

		local newPacket: SendUpdateEffect = {
			type = "SendUpdate",
			player = player,
			packet = computedPacket,
		}
		table.insert(effects, newPacket)
	end
	return effects
end

local function generateId(state: NetState): NetState
	local newState = deepClone(state)
	newState.nextId += 1
	return newState
end

local function createChannel(state: NetState, event: _netWorldEvents.CreateNewChannelEvent): (NetState, { Effect })
	local newState = generateId(state)
	local effects: { Effect } = {}

	local newId = tostring(newState.nextId)

	local newChannel: Channel = {
		parentId = event.parent,
		channelId = newId,
		children = {},
		topic = event.topic,
		immutableData = event.immutableData,
		replicationState = event.replicationState,
	}

	newState.channels[newId] = newChannel

	if event.parent then
		local parentChannel = NetServerState.channelFromId(newState, event.parent)
		assert(parentChannel, `Attempt to create channel and assign to parent, however, could not find parent.`)

		local newParent = deepClone(parentChannel)
		table.insert(newParent.children, newId)
		newState.channels[event.parent] = newParent
	end

	local createEffect: CreateChannelEffect = {
		type = "CreateChannel",
		channel = newChannel,
	}
	table.insert(effects, createEffect)

	return newState, arrayConcat(effects, buildUpdateEffects(Players:GetPlayers(), state, newState))
end

local function removeChannel(state: NetState, channelId: string): (NetState, { Effect })
	local newState = deepClone(state)
	local effects = {}

	local channelData = NetServerState.channelFromId(state, channelId)
	if not channelData then
		return newState, effects
	end

	newState.channels[channelId] = nil

	local destroyEffect: DestroyChannelEffect = {
		type = "DestroyChannel",
		channelId = channelId,
	}
	table.insert(effects, destroyEffect)

	for _i, childId in channelData.children do
		local childState, childEffects = removeChannel(newState, childId)
		newState = childState

		effects = arrayConcat(effects, childEffects)
	end

	return newState, arrayConcat(effects, buildUpdateEffects(Players:GetPlayers(), state, newState))
end

local function changeReplication(
	state: NetState,
	channelId: string,
	desiredReplication: ReplicationState
): (NetState, { Effect })
	local recursiveUpdate
	recursiveUpdate = function(
		stepState: NetState,
		stepChannelId: string,
		stepDesiredReplication: ReplicationState
	): NetState
		local channel = NetServerState.channelFromId(stepState, stepChannelId)
		assert(channel, `Attempt to change replication state, but no channel with id {stepChannelId} could be found!`)

		local parentChannel
		if channel.parentId then
			parentChannel = NetServerState.channelFromId(stepState, channel.parentId)
		end

		if parentChannel and not channel.replicationState.isLockedToParent then
			if ReplicationRules.isOtherWider(parentChannel.replicationState, stepDesiredReplication) then
				warn(`Illegal expansion! Returning with current state`)
				return stepState
			end
		end

		local newChannelReplicationState: ReplicationState

		if channel.replicationState.isLockedToParent then
			assert(parentChannel, `Node is locked to parent state, but no parent found!`)
			newChannelReplicationState = {
				isLockedToParent = true,
				mode = parentChannel.replicationState.mode,
				players = table.clone(parentChannel.replicationState.players),
			}
		else
			newChannelReplicationState = stepDesiredReplication
		end

		local newChannel = deepClone(channel)
		newChannel.replicationState = newChannelReplicationState

		local newStepState = deepClone(stepState)
		newStepState.channels[stepChannelId] = newChannel

		for _i, child in newChannel.children do
			local childChannel = NetServerState.channelFromId(newStepState, child)
			assert(childChannel, `Could not find child state for id {child}`)

			newStepState = recursiveUpdate(
				newStepState,
				child,
				ReplicationRules.constrainWithinMax(newChannelReplicationState, childChannel.replicationState)
			)
		end

		return newStepState
	end

	local newState = recursiveUpdate(state, channelId, desiredReplication)

	return newState, buildUpdateEffects(Players:GetPlayers(), state, newState)
end

--[[
    Public
]]

function NetServerState.create(): NetState
	return {
		nextId = 0,
		channels = {},
	}
end

function NetServerState.channelFromId(state: NetState, id: string): Channel?
	return state.channels[id]
end

function NetServerState.reduceEvent(state: NetState, event: _netWorldEvents.Event): (NetState, { Effect })
	if event.type == "CreateNewChannel" then
		return createChannel(state, event)
	elseif event.type == "DestroyChannel" then
		return removeChannel(state, event.uniqueId)
	elseif event.type == "ChangeReplication" then
		return changeReplication(state, event.channelId, event.desiredReplicationState)
	elseif event.type == "FullState" then
		return state,
			tableMap(
				buildUpdateEffects({ event.player }, NetServerState.create(), state),
				function(effect: SendUpdateEffect)
					local clone = deepClone(effect)
					clone.packet.isFull = true
					return clone
				end
			)
	end

	error(`No event handler found for event {event}`)
end

return NetServerState

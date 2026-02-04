--!strict

local arrayConcat = require(script.Parent.Parent.utils.arrayConcat)
local deepClone = require(script.Parent.Parent.utils.deepClone)
local _netWorldPackets = require(script.Parent._netWorldPackets)
local NetClientState = {}

export type NetState = {
	channels: { [string]: Channel },
	fullStateReceived: boolean,
}

export type CreateChannelEffect = {
	type: "CreateChannel",
	channelId: string,
}

export type RemoveChannelEffect = {
	type: "RemoveChannel",
	channelId: string,
}

export type Effect = CreateChannelEffect | RemoveChannelEffect

type Channel<D = nil> = {
	uniqueIdent: string,
	topic: string,
	immutableData: D,

	parent: string?,
	children: { string },
}

type NodesUpdateEvent = _netWorldPackets.NodesUpdate
type Event = NodesUpdateEvent

local function removeNode(state: NetState, nodeId: string): (NetState, { Effect })
	local foundChannel = NetClientState.channelFromId(state, nodeId)
	assert(foundChannel, `Tried to remove node but could not find node with id {nodeId}`)

	local newState = deepClone(state)
	newState.channels[nodeId] = nil

	local effects: { Effect } = { {
		type = "RemoveChannel",
		channelId = nodeId,
	} }

	if foundChannel.parent then
		local parentData = NetClientState.channelFromId(newState, foundChannel.parent)

		if parentData then
			local foundIndex = table.find(parentData.children, nodeId)
			if foundIndex then
				table.remove(parentData.children, foundIndex)
			end

			newState.channels[foundChannel.parent] = parentData
		end
	end

	for _i, childId in foundChannel.children do
		local computedState, computedEffects = removeNode(newState, childId)
		newState = computedState
		effects = arrayConcat(effects, computedEffects)
	end

	return newState, effects
end

local function addNode(
	state: NetState,
	nodeId: string,
	topic: string,
	immutableData: any?,
	parent: string?,
	children: { string }
): (NetState, { Effect })
	local newState = deepClone(state)

	if parent then
		local parentData = newState.channels[parent]

		-- Its okay to skip. When parent is being added, it will make the reference itself.
		if parentData and not table.find(parentData.children, nodeId) then
			table.insert(newState.channels[parentData.uniqueIdent].children, nodeId)
		end
	end

	newState.channels[nodeId] = {
		parent = parent,
		uniqueIdent = nodeId,
		topic = topic,
		immutableData = immutableData,

		children = table.clone(children),
	}

	return newState, { {
		type = "CreateChannel",
		channelId = nodeId,
	} }
end

local function updateNodes(
	state: NetState,
	hide: { string },
	show: { _netWorldPackets.SerializedChannel },
	isFullState: boolean
): (NetState, { Effect })
	local newState = deepClone(state)
	local effects = {}

	-- Remove nodes
	for _i, hideId in hide do
		local computedState, computedEffects = removeNode(newState, hideId)
		newState = computedState
		effects = arrayConcat(effects, computedEffects)
	end

	-- Add nodes
	for _i, showChannel in show do
		local computedState, computedEffects = addNode(
			newState,
			showChannel.channelId,
			showChannel.topic,
			showChannel.immutableData,
			showChannel.parentId,
			showChannel.children
		)
		newState = computedState
		effects = arrayConcat(effects, computedEffects)
	end

	return newState, effects
end

--[[
	Public
]]

function NetClientState.channelFromId(state: NetState, id: string): Channel?
	local channel = state.channels[id]

	if channel then
		return deepClone(channel)
	end

	return nil
end

function NetClientState.create(): NetState
	return {
		channels = {},
		fullStateReceived = false,
	}
end

function NetClientState.reduceEvent(state: NetState, event: Event): (NetState, { Effect })
	if event.type == "NodesUpdate" then
		if state.fullStateReceived ~= true and event.isFull ~= true then
			return state, {}
		end

		local useState = state
		if state.fullStateReceived ~= true then
			useState = deepClone(state)
			useState.fullStateReceived = true
		end

		return updateNodes(useState, event.hide, event.show, event.isFull == true)
	end

	error(`No event handler found for {event}`)
end

return NetClientState

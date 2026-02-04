--!strict
local _netTypes = require(script.Parent.Parent._netTypes)
local bool = require(script.Parent.Parent.utils.bool)
local ReplicationRules = {}

--[[
    How I want replication changes to happen:
        1. Developer changes replication setting of a node
        2. Function checks if replication change is legal
            2.1 A node is always constrained by its parent node
            2.2 A node can never replicate beyond its parent node (ILLEAGAL! EXCEPTION!)
            2.3 A node CAN replicate LESS than its parent node
                2.3.1 In this case, all replication states of the children need to be re-evaluated
        3. Function computes new replication state of all affected nodes
        4. System applies new replication states (effects)
]]

type ReplicationState = _netTypes.ReplicationState
type IChannelServer = _netTypes.ChannelServer

local ModesOrder = {
	["ALL"] = 3,
	["SPECIFIED"] = 2,
	["NONE"] = 1,
}

function ReplicationRules.isReplicatedToPlayer(state: ReplicationState, player: Player): boolean
	if state.mode == "ALL" then
		return true
	end

	if state.mode == "NONE" then
		return false
	end

	return table.find(state.players, player) ~= nil
end

function ReplicationRules.isOtherWider(root: ReplicationState, other: ReplicationState): boolean
	local isGreater = ModesOrder[other.mode] > ModesOrder[root.mode]

	if isGreater then
		return true
	end

	-- Still need to check if both specify
	if root.mode == "SPECIFIED" and other.mode == "SPECIFIED" then
		if #other.players > #root.players then
			return true
		end

		for _i, otherPlayer in ipairs(other.players) do
			if not table.find(root.players, otherPlayer) then
				return true
			end
		end
	end

	return false
end

function ReplicationRules.constrainWithinMax(max: ReplicationState, current: ReplicationState): ReplicationState
	if max.mode == "ALL" then
		return current
	end

	if max.mode == "NONE" then
		return {
			isLockedToParent = current.isLockedToParent,
			mode = "NONE",
			players = {},
		}
	end

	-- Clamp within SPECIFIED parent
	if max.mode == "SPECIFIED" then
		if current.mode == "ALL" then
			return {
				isLockedToParent = current.isLockedToParent,
				mode = "SPECIFIED",
				players = table.clone(max.players),
			}
		end

		if current.mode == "NONE" then
			return {
				isLockedToParent = current.isLockedToParent,
				mode = "NONE",
				players = {},
			}
		end

		-- Purge any players which are in current but not in max
		local constrainedPlayers = {}
		for _i, otherPlayer in ipairs(current.players) do
			local foundInMax = bool(table.find(max.players, otherPlayer))
			if foundInMax then
				table.insert(constrainedPlayers, otherPlayer)
			end
		end
		return {
			isLockedToParent = current.isLockedToParent,
			mode = "SPECIFIED",
			players = constrainedPlayers,
		}
	end

	return current
end

return ReplicationRules

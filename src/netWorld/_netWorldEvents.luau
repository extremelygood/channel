--!strict

local _netTypes = require(script.Parent.Parent._netTypes)

export type CreateNewChannelEvent<D = nil> = {
	type: "CreateNewChannel",
	topic: string,
	immutableData: D,
	parent: string?,
	replicationState: _netTypes.ReplicationState,
}

export type DestroyChannelEvent = {
	type: "DestroyChannel",
	uniqueId: string,
}

export type SendMessageEvent = {
	type: "SendMessage",
	giveArgs: () -> ...any,
	recepients: "ALL" | "SPECIFIED",
	player: Player?,
}

export type ChangeReplicationEvent = {
	type: "ChangeReplication",
	channelId: string,
	desiredReplicationState: _netTypes.ReplicationState,
}

export type FullStateEvent = {
	type: "FullState",
	player: Player,
}

export type Event =
	CreateNewChannelEvent<any>
	| DestroyChannelEvent
	| SendMessageEvent
	| ChangeReplicationEvent
	| FullStateEvent

return {}

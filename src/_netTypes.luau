--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fSignal = require(script.Parent.utils.fSignal)
type NilFun = () -> ()

export type NetWorldServer = {
	openChannel: <D>(self: any, topic: string, immutableData: D?) -> ChannelServer<D>,
}

export type NetWorldContextServer = {
	-- Commands
	sendPacket: (player: Player, ...any) -> (),
	sendPacketAll: (...any) -> (),
	makeChild: (topic: string, immutableData: any?) -> AnyChannelServer,
	destroy: () -> (),
	setReplication: (newState: ReplicationState) -> (),

	-- Queries
	queryParent: () -> AnyChannelServer?,
	queryChildren: () -> { AnyChannelServer },
	queryReplicationState: () -> ReplicationState,
	queryImmutableData: () -> any,

	-- Bindings
	bindOnMessage: ((Player, ...any) -> ()) -> fSignal.DisconnectFun,
	bindOnDestroy: fSignal.BindFun<>,
}

export type NetWorldClient = {
	onChannel: (self: any, callback: (newChannel: AnyChannelClient) -> ()) -> NilFun,
	onTopic: (self: any, topic: string, callback: (newChannel: AnyChannelClient) -> ()) -> NilFun,
	expectChannel: (self: any, predicate: (AnyChannelClient) -> boolean) -> AnyChannelClient,

	fromId: (self: any, id: string) -> AnyChannelClient?,
	allChannels: (self: any) -> { AnyChannelClient },
}

export type NetWorldContextClient = {

	-- Bindings
	bindOnChild: fSignal.BindFun<AnyChannelClient>,
	bindOnMessage: fSignal.BindFun<...any>,
	bindOnDestroy: fSignal.BindFun<>,

	-- Commands
	fireServer: (...any) -> (),

	-- Queries
	queryParent: () -> AnyChannelClient?,
	queryChildren: () -> { AnyChannelClient },
	queryImmutableData: () -> any,
}

type Channel<D = nil> = {
	-- MetaData
	topic: (self: any) -> string,
	uniqueIdent: (self: any) -> string,
	immutableData: (self: any) -> D,
}

export type ChannelServer<D = nil> = Channel<D> & {
	fireClient: (self: any, player: Player, ...any) -> (),
	fireAllClients: (self: any, ...any) -> (),

	parent: (self: any) -> AnyChannelServer?,
	children: (self: any) -> { AnyChannelServer },

	onMessage: (self: any, eventHandler: (plr: Player, ...any) -> ()) -> fSignal.DisconnectFun,

	makeChild: (self: any, topic: string, immutableData: any?) -> AnyChannelServer,
	destroy: (self: any) -> (),

	-- Replication control
	replicateAll: (self: any) -> (),
	replicatePlayers: (self: any, players: { Player }) -> (),
	stopReplication: (self: any) -> (),
	replicationState: (self: any) -> ReplicationState,
}

export type ChannelClient<D = nil> = Channel<D> & {
	fireServer: (self: any, ...any) -> (),

	parent: (self: any) -> AnyChannelClient?,
	children: (self: any) -> { AnyChannelClient },

	onMessage: (self: any, eventHandler: fSignal.EventHandler<...any>) -> fSignal.DisconnectFun,
	onDestroy: (self: any, fSignal.EventHandler<>) -> fSignal.DisconnectFun,
	onChild: (self: any, (newChild: AnyChannelClient) -> ()) -> NilFun,

	immutableData: (self: any) -> D,
	expectChild: (self: any, predicate: (newChild: AnyChannelClient) -> boolean) -> AnyChannelClient,
}

type AnyChannel = {
	topic: (self: AnyChannel) -> string,
	uniqueIdent: (self: AnyChannel) -> string,
	immutableData: (self: AnyChannel) -> any,
}

export type AnyChannelServer = AnyChannel & {
	fireClient: (self: AnyChannelServer, player: Player, ...any) -> (),
	fireAllClients: (self: AnyChannelServer, ...any) -> (),

	parent: (self: AnyChannelServer) -> AnyChannelServer?,
	children: (self: AnyChannelServer) -> { AnyChannelServer },

	onMessage: (self: any, eventHandler: (plr: Player, ...any) -> ()) -> fSignal.DisconnectFun,

	makeChild: (self: any, topic: string, immutableData: any?) -> AnyChannelServer,
	destroy: (self: any) -> (),

	-- Replication control
	replicateAll: (self: AnyChannelServer) -> (),
	replicatePlayers: (self: AnyChannelServer, players: { Player }) -> (),
	stopReplication: (self: AnyChannelServer) -> (),
	replicationState: (self: AnyChannelServer) -> ReplicationState,
}

export type AnyChannelClient = AnyChannel & {

	fireServer: (self: AnyChannelClient, ...any) -> (),

	parent: (self: AnyChannelClient) -> AnyChannelClient?,
	children: (self: AnyChannelClient) -> { AnyChannelClient },

	onMessage: (self: any, eventHandler: fSignal.EventHandler<...any>) -> fSignal.DisconnectFun,
	onDestroy: (self: any, fSignal.EventHandler<>) -> fSignal.DisconnectFun,
	onChild: (self: AnyChannelClient, (newChild: AnyChannelClient) -> ()) -> NilFun,

	immutableData: (self: any) -> any,
	expectChild: (self: AnyChannelClient, predicate: (newChild: AnyChannelClient) -> boolean) -> AnyChannelClient,
}

--[[
	Small types
]]

export type ReplicationState = {
	isLockedToParent: boolean,
	mode: "ALL" | "SPECIFIED" | "NONE",
	players: { Player },
}

return {}

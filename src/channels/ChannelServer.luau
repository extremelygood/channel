--!strict

local Object = require(script.Parent.Parent.utils.Object)
local _netTypes = require(script.Parent.Parent._netTypes)

local ChannelServer = {}
Object.setIndexAndMeta(ChannelServer, Object)

type IChannelServer<D = any> = _netTypes.ChannelServer<D>
type NetContext = _netTypes.NetWorldContextServer
type ReplicationState = _netTypes.ReplicationState

type ChannelServerImpl<D = any> = IChannelServer<D> & typeof(ChannelServer) & {
	topicString: string,
	identString: string,
	context: NetContext,
}

function ChannelServer.new(topic: string, ident: string, context: NetContext): IChannelServer
	local self: ChannelServerImpl = Object.new():extend(ChannelServer, {
		topicString = topic,
		identString = ident,
		context = context,
	})
	return self
end

function ChannelServer.topic(self: ChannelServerImpl): string
	return self.topicString
end

function ChannelServer.uniqueIdent(self: ChannelServerImpl): string
	return self.identString
end

function ChannelServer.fireClient(self: ChannelServerImpl, player: Player, ...: any): ()
	self.context.sendPacket(player, ...)
end

function ChannelServer.fireAllClients(self: ChannelServerImpl, ...: any): ()
	self.context.sendPacketAll(...)
end

function ChannelServer.parent(self: ChannelServerImpl): IChannelServer?
	return self.context.queryParent()
end

function ChannelServer.children(self: ChannelServerImpl): { IChannelServer }
	return self.context.queryChildren()
end

function ChannelServer.makeChild(self: ChannelServerImpl, topic: string, immutableData: any?): IChannelServer
	return self.context.makeChild(topic, immutableData)
end

function ChannelServer.onMessage(self: ChannelServerImpl, eventHandler: (Player, ...any) -> ()): any
	return self.context.bindOnMessage(eventHandler)
end

function ChannelServer.immutableData<D>(self: ChannelServerImpl): D
	return self.context.queryImmutableData()
end

function ChannelServer.destroy(self: ChannelServerImpl): ()
	self.context.destroy()
end

function ChannelServer.replicateAll(self: ChannelServerImpl): ()
	self.context.setReplication({
		isLockedToParent = false,
		mode = "ALL",
		players = {},
	})
end

function ChannelServer.replicatePlayers(self: ChannelServerImpl, players: { Player }): ()
	self.context.setReplication({
		isLockedToParent = false,
		mode = "SPECIFIED",
		players = table.clone(players),
	})
end

function ChannelServer.stopReplication(self: ChannelServerImpl): ()
	self.context.setReplication({
		isLockedToParent = false,
		mode = "NONE",
		players = {},
	})
end

function ChannelServer.replicationState(self: ChannelServerImpl): ReplicationState
	return self.context.queryReplicationState()
end

return ChannelServer

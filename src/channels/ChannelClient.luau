--!strict

local ExpectedChannel = require(script.Parent.ExpectedChannel)
local Object = require(script.Parent.Parent.utils.Object)
local fSignal = require(script.Parent.Parent.utils.fSignal)
local _netTypes = require(script.Parent.Parent._netTypes)

local ChannelClient = {}
Object.setIndexAndMeta(ChannelClient, Object)

type Context = _netTypes.NetWorldContextClient
type IChannelClient<D = nil> = _netTypes.ChannelClient<D>

type ChannelClientImpl<D = nil> = typeof(ChannelClient) & IChannelClient<D> & {
	topicString: string,
	uniqueIdentString: string,

	context: Context,
}

function ChannelClient.new(topic: string, ident: string, context: Context): IChannelClient
	local self: ChannelClientImpl = Object.new():extend(ChannelClient, {
		topicString = topic,
		uniqueIdentString = ident,
		context = context,
	})
	return self
end

function ChannelClient.topic(self: ChannelClientImpl): string
	return self.topicString
end

function ChannelClient.uniqueIdent(self: ChannelClientImpl): string
	return self.uniqueIdentString
end

function ChannelClient.fireServer(self: ChannelClientImpl, ...: any): ()
	self.context.fireServer(...)
end

function ChannelClient.parent(self: ChannelClientImpl): IChannelClient?
	return self.context.queryParent()
end

function ChannelClient.children(self: ChannelClientImpl): { IChannelClient }
	return self.context.queryChildren()
end

function ChannelClient.onMessage(
	self: ChannelClientImpl,
	eventHandler: fSignal.EventHandler<...any>
): fSignal.DisconnectFun
	return self.context.bindOnMessage(eventHandler)
end

function ChannelClient.immutableData<D>(self: ChannelClientImpl): D
	return self.context.queryImmutableData()
end

function ChannelClient.onChild(
	self: ChannelClientImpl,
	eventHandler: fSignal.EventHandler<IChannelClient>
): fSignal.DisconnectFun
	return self.context.bindOnChild(eventHandler)
end

function ChannelClient.onDestroy(self: ChannelClientImpl, eventHandler: fSignal.EventHandler<>): fSignal.DisconnectFun
	return self.context.bindOnDestroy(eventHandler)
end

function ChannelClient.isActive(self: ChannelClientImpl): boolean
	return self.context.queryIsActive()
end

function ChannelClient.onActive(
	self: ChannelClientImpl,
	eventHandler: (alreadyActive: boolean) -> ()
): fSignal.DisconnectFun
	if self:isActive() then
		eventHandler(true)
		return function() end
	end

	return self.context.bindOnActive(function(_alreadyActiveFromContext)
		eventHandler(false)
	end)
end

function ChannelClient.expectChild(self: ChannelClientImpl, predicate: (IChannelClient) -> boolean): IChannelClient
	return ExpectedChannel.new(self.context.bindOnChild, function()
		return self:children()
	end, predicate, self)
end

return ChannelClient

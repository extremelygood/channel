--!strict

local Object = require(script.Parent.Parent.utils.Object)
local fSignal = require(script.Parent.Parent.utils.fSignal)
local _netTypes = require(script.Parent.Parent._netTypes)

local ExpectedChannel = {}
Object.setIndexAndMeta(ExpectedChannel, Object)

type IChannelClient<D = nil> = _netTypes.ChannelClient<D>

type ExpectedChannelImpl<D = nil> = typeof(ExpectedChannel) & IChannelClient<D> & {
	initialParent: IChannelClient?,
	acceptPredicate: (IChannelClient) -> boolean,
	resolvedChannel: IChannelClient<D>?,

	onMessageSignal: fSignal.FunSignal<...any>,
	onChildSignal: fSignal.FunSignal<IChannelClient>,
	onDestroySignal: fSignal.FunSignal<>,
	onActiveSignal: fSignal.FunSignal<boolean>,
	isCurrentlyActive: boolean,

	stopResolving: fSignal.DisconnectFun?,
}

function ExpectedChannel.new(
	bindAttemptResolve: fSignal.BindFun<IChannelClient>,
	queryResolvable: () -> { IChannelClient },
	predicate: (IChannelClient) -> boolean,
	parent: IChannelClient?
): IChannelClient
	local self: ExpectedChannelImpl = Object.new():extend(ExpectedChannel, {
		initialParent = parent,
		acceptPredicate = predicate,

		onMessageSignal = fSignal(),
		onChildSignal = fSignal(),
		onDestroySignal = fSignal(),
		onActiveSignal = fSignal(),
		isCurrentlyActive = false,
	})

	for _i, resolvable in queryResolvable() do
		self:_attemptResolve(resolvable)
	end

	if not self.resolvedChannel then
		bindAttemptResolve(function(newResolvable)
			self:_attemptResolve(newResolvable)
		end)
	end

	return self
end

function ExpectedChannel.topic(self: ExpectedChannelImpl): string
	if self.resolvedChannel then
		return self.resolvedChannel:topic()
	else
		return "TO_BE_RESOLVED"
	end
end

function ExpectedChannel.uniqueIdent(self: ExpectedChannelImpl): string
	if self.resolvedChannel then
		return self.resolvedChannel:uniqueIdent()
	else
		return "TO_BE_RESOLVED"
	end
end

function ExpectedChannel.fireServer(self: ExpectedChannelImpl, ...: any): ()
	if self.resolvedChannel then
		return self.resolvedChannel:fireServer(...)
	else
		warn(`Could not fire packet to server, expected child is yet to be resolved`)
		warn(debug.traceback())
	end
end

function ExpectedChannel.parent(self: ExpectedChannelImpl): IChannelClient?
	if self.resolvedChannel then
		return self.resolvedChannel:parent()
	else
		return self.initialParent
	end
end

function ExpectedChannel.children(self: ExpectedChannelImpl): { IChannelClient }
	if self.resolvedChannel then
		return self.resolvedChannel:children()
	else
		return {}
	end
end

function ExpectedChannel.immutableData<D>(self: ExpectedChannelImpl<D>): D
	if self.resolvedChannel then
		return self.resolvedChannel:immutableData()
	end
	error(
		`Cannot pull immutableData without being resolved. This means, you cannot call :immutableData on an ExpectedChannel, BEFORE it has resolved. This is very annoying but I think this should not happen anyway`
	)
end

function ExpectedChannel.onChild(
	self: ExpectedChannelImpl,
	eventHandler: fSignal.EventHandler<IChannelClient>
): fSignal.DisconnectFun
	return self.onChildSignal.bind(eventHandler)
end

function ExpectedChannel.onMessage(
	self: ExpectedChannelImpl,
	eventHandler: fSignal.EventHandler<...any>
): fSignal.DisconnectFun
	return self.onMessageSignal.bind(eventHandler)
end

function ExpectedChannel.onDestroy(
	self: ExpectedChannelImpl,
	eventHandler: fSignal.EventHandler<>
): fSignal.DisconnectFun
	return self.onDestroySignal.bind(eventHandler)
end

function ExpectedChannel.isActive(self: ExpectedChannelImpl): boolean
	if self.resolvedChannel then
		return self.resolvedChannel:isActive()
	end

	return false
end

function ExpectedChannel.onActive(
	self: ExpectedChannelImpl,
	eventHandler: (alreadyActive: boolean) -> ()
): fSignal.DisconnectFun
	if self:isActive() then
		eventHandler(true)
		return function() end
	end

	return self.onActiveSignal.bind(eventHandler)
end

function ExpectedChannel.expectChild(self: ExpectedChannelImpl, predicate: (IChannelClient) -> boolean): any
	local newExpected = ExpectedChannel.new(self.onChildSignal.bind, function()
		return self:children()
	end, predicate, self)
	return newExpected
end

--[[ 
    Private
]]

function ExpectedChannel._resolve(self: ExpectedChannelImpl, channel: IChannelClient): ()
	self.resolvedChannel = channel

	if self.stopResolving then
		self.stopResolving()
		self.stopResolving = nil
	end

	channel:onChild(self.onChildSignal.fire)
	channel:onMessage(self.onMessageSignal.fire)
	channel:onDestroy(self.onDestroySignal.fire)
	channel:onActive(function(alreadyActive)
		local adjustedAlreadyActive = alreadyActive
		if not self.isCurrentlyActive and alreadyActive then
			adjustedAlreadyActive = false
		end
		self.isCurrentlyActive = true
		self.onActiveSignal.fire(adjustedAlreadyActive)
	end)

	-- It could be possible that onChild is not fired again, since
	-- channels are sent along with its children in one packet.

	for _i, child in channel:children() do
		self.onChildSignal.fire(child)
	end
end

function ExpectedChannel._attemptResolve(self: ExpectedChannelImpl, channel: IChannelClient): ()
	if self.acceptPredicate(channel) then
		self:_resolve(channel)
	end
end

return ExpectedChannel

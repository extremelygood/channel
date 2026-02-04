--!strict
type FireFun<T...> = (T...) -> ()
export type DisconnectFun = () -> ()
export type EventHandler<T...> = (T...) -> ()
export type BindFun<T...> = (EventHandler<T...>) -> DisconnectFun

export type FunSignal<T...> = {
	fire: FireFun<T...>,
	bind: BindFun<T...>,
}

return function<T...>(onUnbind: (remainingBindings: number) -> ()?): FunSignal<T...>
	local bindings: { EventHandler<T...> } = {}

	local function fireFun(...: T...): ()
		for _i, eventHandler in bindings do
			eventHandler(...)
		end
	end

	local function bindFun(eventHandler: EventHandler<T...>): DisconnectFun
		table.insert(bindings, eventHandler)

		local function disconnector()
			local foundIndex = table.find(bindings, eventHandler)
			if foundIndex then
				table.remove(bindings, foundIndex)
				if onUnbind then
					onUnbind(#bindings)
				end
			end
		end

		return disconnector
	end

	return {
		fire = fireFun,
		bind = bindFun,
	}
end

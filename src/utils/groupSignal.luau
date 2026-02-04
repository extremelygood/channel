--!strict
local fSignal = require(script.Parent.fSignal)

export type GroupedSignal<G, T...> = {
	fire: (group: G, T...) -> (),
	bind: (group: G, fSignal.EventHandler<T...>) -> fSignal.DisconnectFun,
}

return function<G, T...>(): GroupedSignal<G, T...>
	local groupMap: { [G]: fSignal.FunSignal<T...> } = {}

	local function onUnbind(group: G, remainingBindings: number)
		if remainingBindings > 0 then
			return
		end

		groupMap[group] = nil
	end

	local function bind(group: G, eventHandler: fSignal.EventHandler<T...>): fSignal.DisconnectFun
		local groupSig: fSignal.FunSignal<T...> = groupMap[group]
			or fSignal(function(remainingBindings: number)
				onUnbind(group, remainingBindings)
			end)
		groupMap[group] = groupSig

		return groupSig.bind(eventHandler)
	end

	local function fire(group: G, ...: T...)
		local groupSig = groupMap[group]
		if not groupSig then
			return
		end

		groupSig.fire(...)
	end

	return {
		fire = fire,
		bind = bind,
	}
end

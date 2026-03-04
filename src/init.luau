--!strict

local _netTypes = require(script._netTypes)
local ClientMain = require(script.main.ClientMain)
local ServerMain = require(script.main.ServerMain)

export type ChannelClient<D = any> = _netTypes.ChannelClient<D>
export type ChannelServer<D = any> = _netTypes.ChannelServer<D>

return {
	server = ServerMain,
	client = ClientMain,
}

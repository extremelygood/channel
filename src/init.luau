--!strict

local ClientMain = require(script.main.ClientMain)
local ServerMain = require(script.main.ServerMain)

return {
	server = ServerMain,
	client = ClientMain,
}

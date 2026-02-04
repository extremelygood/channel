--!strict

local ClientMain = require(script.Parent.main.ClientMain)
local ServerMain = require(script.Parent.main.ServerMain)

return {
	server = ServerMain,
	client = ClientMain,
}

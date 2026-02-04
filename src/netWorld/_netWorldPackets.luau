--!strict

export type SerializedChannel = {
	parentId: string?,
	channelId: string,
	topic: string,
	immutableData: any?,
	children: { string },
}

export type NodesUpdate = {
	type: "NodesUpdate",
	hide: { string },
	show: { SerializedChannel },
	isFull: boolean?,
}

export type ChannelMessage = {
	type: "ChannelMessage",
	channelId: string,
	values: { [number]: any, n: number },
}

export type CheckIn = {
	type: "CheckIn",
}

export type Packet = NodesUpdate | ChannelMessage | CheckIn

return {}

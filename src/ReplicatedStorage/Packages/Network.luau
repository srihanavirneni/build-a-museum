local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EventsFolder = ReplicatedStorage:WaitForChild("Events")

local NET_POLLING_TIMEOUT = 10

local Network = {}

local function isRemoteObject(object)
	if typeof(object) ~= "Instance" then
		return
	end
	return object:IsA("RemoteEvent") or object:IsA("RemoteFunction") or object:IsA("UnreliableRemoteEvent")
end

function Event(eventName: string, remoteType: string)
	local eventObject = EventsFolder:FindFirstChild(eventName)
	if eventObject and isRemoteObject(eventObject) then
		return eventObject
	else
		if RunService:IsServer() then
			-- creates a remote on the server instead
			local newRemote = Instance.new(remoteType)
			newRemote.Name = eventName
			newRemote.Parent = EventsFolder

			return newRemote
		else
			-- waits for the remote for 10 seconds if on the client (otherwise throw error -- kinda rare)
			eventObject = EventsFolder:WaitForChild(eventName, NET_POLLING_TIMEOUT)
			if not eventObject then
				error("Failed to find remote: " .. eventName, 2)
			end

			return eventObject
		end
	end
end

function Network:RemoteEvent(eventName: string): RemoteEvent
	return Event(eventName, "RemoteEvent")
end

function Network:RemoteFunction(eventName: string): RemoteFunction
	return Event(eventName, "RemoteFunction")
end

function Network:UnreliableRemoteEvent(eventName: string): UnreliableRemoteEvent
	return Event(eventName, "UnreliableRemoteEvent")
end

function Network:Connect(eventName: string, handler: (...any) -> ()): RBXScriptConnection
	if RunService:IsServer() then
		return self:RemoteEvent(eventName).OnServerEvent:Connect(handler)
	else
		return self:RemoteEvent(eventName).OnClientEvent:Connect(handler)
	end
end

function Network:ConnectUnreliable(eventName: string, handler: (...any) -> ()): RBXScriptConnection
	if RunService:IsServer() then
		return self:UnreliableRemoteEvent(eventName).OnServerEvent:Connect(handler)
	else
		return self:UnreliableRemoteEvent(eventName).OnClientEvent:Connect(handler)
	end
end

function Network:Handle(eventName: string, handler: (...any) -> ()): RBXScriptConnection
	self:RemoteFunction(eventName).OnServerInvoke = handler
end

function Network:Invoke(eventName: string, ...: any): ...any
	return self:RemoteFunction(eventName):InvokeServer(...)
end

-- only should be used in testing environments and not during actual runtime
function Network:Clean()
	EventsFolder:ClearAllChildren()
end

return Network

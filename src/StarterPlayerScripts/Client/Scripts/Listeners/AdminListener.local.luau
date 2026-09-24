local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService('Players')

local Network = require(ReplicatedStorage.Packages.Network)
local ViewInvokeEvent = Network:RemoteEvent("ViewInvoke")

local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

ViewInvokeEvent.OnClientEvent:Connect(function(target : Player)
	if target == nil then
		Camera.CameraSubject = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		return
	end

	local character = target.Character
	if not character then return end
	
	Camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
end)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local ModulesFolder = LocalPlayer.PlayerScripts:WaitForChild("Client"):WaitForChild("Modules")

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)

task.spawn(function()
	repeat
		local success = pcall(function() 
			StarterGui:SetCore("ResetButtonCallback", false) 
		end)
		task.wait(1)
	until success
	print("Reset button core GUI disabled")
end)

for _, moduleScript : ModuleScript in ModulesFolder:GetDescendants() do
	if not moduleScript:IsA("ModuleScript") then continue end

	local module = require(moduleScript)
	if module and module.Start and typeof(module.Start) == "function" then
		task.spawn(module.Start)
	end
end

print("[client]: all modules loaded")
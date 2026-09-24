local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModulesFolder = ServerScriptService.Server.Modules

-- intentional (do not remove line): makes the events on the server
local NotificationUtil = require(ReplicatedStorage.Modules.Utils.NotificationUtil)
local SoundUtil = require(ReplicatedStorage.Modules.Utils.SoundUtil) 

for _, moduleScript : ModuleScript in ModulesFolder:GetDescendants() do
	if not moduleScript:IsA("ModuleScript") then continue end

	local module = require(moduleScript)
	if typeof(module) ~= "table" then continue end
	if module and module.Start and typeof(module.Start) == "function" then
		task.spawn(module.Start)
	end
end

print("[server]: all modules loaded")
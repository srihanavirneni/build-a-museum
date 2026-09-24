local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayerDataService = require(ServerScriptService.Server.Modules.PlayerData.PlayerDataService)
local PlayerStatsData = require(ReplicatedStorage.Modules.Data.PlayerStats)

local Signal = require(ReplicatedStorage.Packages.Signal)

local STATS_FOLDER_NAME = "PlayerStats"

local StatsService = {}
StatsService.StatChanged = Signal.new()

function StatsService.GetStat(player : Player, statName : string)
	local statFolder = player:FindFirstChild(STATS_FOLDER_NAME)
	if not statFolder then return end
	
	local statData = PlayerStatsData.GetStatData(statName)
	if not statData then return end

	local statAttributeStr = "stat_"..statData.Id
	return statFolder:GetAttribute(statAttributeStr) or statData.DefaultValue
end

function StatsService.SetStat(player : Player, statName : string, newValue : number)
	local statFolder = player:FindFirstChild(STATS_FOLDER_NAME)
	if not statFolder then return end
	
	local profile = PlayerDataService.GetProfile(player)
	if not profile then return end
	
	local statData = PlayerStatsData.GetStatData(statName)
	if not statData then return end
	
	local statAttributeStr = "stat_"..statData.Id
	statFolder:SetAttribute(statAttributeStr, newValue)
	profile.Data.PlayerStats[statAttributeStr] = newValue
	
	StatsService.StatChanged:Fire(player, statName, newValue)
end

function StatsService.UpdateStat(player : Player, statName : string, callback : (number) -> ())
	local statFolder = player:FindFirstChild(STATS_FOLDER_NAME)
	if not statFolder then return end
	
	local profile = PlayerDataService.GetProfile(player)
	if not profile then return end

	local statData = PlayerStatsData.GetStatData(statName)
	if not statData then return end
	
	local statAttributeStr = "stat_"..statData.Id
	local originalStatValue = statFolder:GetAttribute(statAttributeStr)
	
	local newValue = nil
	local success, err = pcall(function()
		newValue = callback(originalStatValue)
	end)

	if success and newValue then
		StatsService.SetStat(player, statName, newValue)
	else
		return error(err)
	end
end

function StatsService.Start()
	local function playerAdded(player : Player)
		local newStatsFolder = Instance.new("Configuration")
		newStatsFolder.Parent = player
		newStatsFolder.Name = STATS_FOLDER_NAME
		
		local profile = PlayerDataService.GetProfile(player)
		if not profile then return end
		
		for _, statData in PlayerStatsData.Data do
			local statAttributeStr = "stat_"..statData.Id
			
			local savedStatValue = profile.Data.PlayerStats[statAttributeStr]
			if statData.Id == 1 then -- backpack limit
				savedStatValue = 40
			end
			newStatsFolder:SetAttribute(statAttributeStr, savedStatValue or statData.DefaultValue)
			profile.Data.PlayerStats[statAttributeStr] = savedStatValue or statData.DefaultValue
			
			StatsService.StatChanged:Fire(player, statData.Name, savedStatValue or statData.DefaultValue)
		end
		
		player:SetAttribute("StatsInitialized", true)
	end
	
	for _, player in Players:GetPlayers() do
		task.spawn(playerAdded, player)
	end
	Players.PlayerAdded:Connect(playerAdded)
end

return StatsService
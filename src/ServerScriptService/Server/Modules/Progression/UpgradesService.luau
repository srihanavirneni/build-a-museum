local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local MonetizationService = require(ServerScriptService.Server.Modules.Monetization.MonetizationService)
local PlayerDataService = require(ServerScriptService.Server.Modules.PlayerData.PlayerDataService)
local StatsService = require(ServerScriptService.Server.Modules.Progression.StatsService)

local NotificationUtil = require(ReplicatedStorage.Modules.Utils.NotificationUtil)
local UpgradesData = require(ReplicatedStorage.Modules.Data.Upgrades)
local Network = require(ReplicatedStorage.Packages.Network)
local UpgradeWithRobuxEvent = Network:RemoteEvent("UpgradeWithRobux")
local UpgradeEvent = Network:RemoteEvent("Upgrade")
local OnUpgradeEvent = Network:RemoteEvent("OnUpgrade")
local StatSwitchUpgradeEvent = Network:RemoteEvent("SwitchUpgrade")

local UPGRADES_FOLDER_NAME = "PlayerUpgrades"

local UpgradesService = {}

function UpgradesService.StatSwitch(player : Player, upgradeId : number, direction : number)
	if typeof(upgradeId) ~= "number" then return end
	if typeof(direction) ~= "number" then return end
	
	local upgradesFolder = player:FindFirstChild(UPGRADES_FOLDER_NAME)
	if not upgradesFolder then return end
	local data = UpgradesData.GetDataById(upgradeId)
	if not data then return end
	if not data.SwitchingEnabled then return end

	local profile = PlayerDataService.GetProfile(player)
	if not profile then return end
	
	local upgradeAttributeStr = "upgrade_"..upgradeId
	
	local currentUpgradeLevel = profile.Data.Upgrades[upgradeAttributeStr]
	local currentSwitchValue = profile.Data.CurrentUpgradeStatSwitches[upgradeAttributeStr]  or currentUpgradeLevel
	
	if not currentSwitchValue then return end
	
	local statLevel = currentSwitchValue + direction
	if statLevel > currentUpgradeLevel or statLevel < 1 then return end

	profile.Data.CurrentUpgradeStatSwitches[upgradeAttributeStr] = statLevel
	StatsService.SetStat(player, data.AffectedStat, data.Stat(statLevel))
	upgradesFolder:SetAttribute(upgradeAttributeStr.."_switch", statLevel)
end

function UpgradesService.Upgrade(player : Player, upgradeId : number, robuxPurchaseState : "BUY" | "REQUEST"?)
	if typeof(upgradeId) ~= "number" then return end
	
	local upgradesFolder = player:FindFirstChild(UPGRADES_FOLDER_NAME)
	if not upgradesFolder then return end
	
	local profile = PlayerDataService.GetProfile(player)
	if not profile then return end

	local upgradeAttributeStr = "upgrade_"..upgradeId
	local currentLevel = profile.Data.Upgrades[upgradeAttributeStr]
	if not currentLevel then return end
	
	local nextLevel = currentLevel + 1
	
	local data = UpgradesData.GetDataById(upgradeId)
	if not data then return end
	
	if currentLevel >= data.MaxLevel then
		NotificationUtil.newTextNotification(
			player,
			"you maxed out this upgrade!",
			Color3.fromRGB(255, 0, 0),
			{
				Sound = "Error"
			}
		)
		return
	end
	
	if robuxPurchaseState == "REQUEST" then
		local tier = UpgradesData.GetProductTier(data.Id, currentLevel)
		local tierData = data.ProductTiers[tier or 1]
		if not tierData then return end
		
		MonetizationService.PromptPlayer(player, tierData.ProductId)
		return
	end
	
	if robuxPurchaseState ~= "BUY" then
		local costToUpgrade = data.Cost(nextLevel)
		if data.GemCurrency then
			if profile.Data.Gems < costToUpgrade then
				NotificationUtil.newTextNotification(
					player,
					"you need more gems to buy this upgrade!",
					Color3.fromRGB(255,0,0),
					{
						Sound = "Error"
					}
				)
				return
			end
		else
			if profile.Data.Money < costToUpgrade then
				NotificationUtil.newTextNotification(
					player,
					"you need more money to buy this upgrade!",
					Color3.fromRGB(255,0,0),
					{
						Sound = "Error"
					}
				)
				return
			end
		end

		PlayerDataService.UpdateProfileData(player, data.GemCurrency and "Gems" or "Money", function(old)
			return old - costToUpgrade
		end)
	end

	NotificationUtil.newTextNotification(
		player,
		`you upgraded {string.lower(data.Name)} to level {nextLevel}!`,
		nil,
		{
			Sound = "Purchase"
		}
	)
	
	profile.Data.Upgrades[upgradeAttributeStr] = profile.Data.Upgrades[upgradeAttributeStr] + 1
	if data.SwitchingEnabled then
		upgradesFolder:SetAttribute(upgradeAttributeStr.."_switch", profile.Data.Upgrades[upgradeAttributeStr])
		profile.Data.CurrentUpgradeStatSwitches[upgradeAttributeStr] =
			profile.Data.Upgrades[upgradeAttributeStr]
	end
	
	upgradesFolder:SetAttribute(upgradeAttributeStr, nextLevel)
	StatsService.SetStat(player, data.AffectedStat, data.Stat(nextLevel))
	
	OnUpgradeEvent:FireClient(player)
	
	return true
end

function UpgradesService.Start()
	local function playerAdded(player : Player)
		local newUpgradesFolder = Instance.new("Configuration")
		newUpgradesFolder.Parent = player
		newUpgradesFolder.Name = UPGRADES_FOLDER_NAME
		
		local profile = PlayerDataService.GetProfile(player)
		if not profile then return end
		
		for _, data in UpgradesData.Data do
			local upgradeAttributeStr = "upgrade_"..data.Id
			
			local savedUpgradeLevel = profile.Data.Upgrades[upgradeAttributeStr]
			local savedStatSwitch = profile.Data.CurrentUpgradeStatSwitches[upgradeAttributeStr]
			
			newUpgradesFolder:SetAttribute(upgradeAttributeStr, savedUpgradeLevel or 1)
			profile.Data.Upgrades[upgradeAttributeStr] = savedUpgradeLevel or 1
			
			if data.SwitchingEnabled then
				newUpgradesFolder:SetAttribute(upgradeAttributeStr.."_switch", savedStatSwitch or savedUpgradeLevel or 1)
				profile.Data.CurrentUpgradeStatSwitches[upgradeAttributeStr] = savedStatSwitch or savedUpgradeLevel or 1
			end
		end
		
		task.spawn(function()
			repeat task.wait() until player:GetAttribute("StatsInitialized")
			for _, data in UpgradesData.Data do
				local upgradeAttributeStr = "upgrade_"..data.Id
				
				local target = profile.Data.Upgrades[upgradeAttributeStr]
				if data.SwitchingEnabled then
					target = profile.Data.CurrentUpgradeStatSwitches[upgradeAttributeStr]
				end
				
				StatsService.SetStat(player, data.AffectedStat, data.Stat(target))
			end
		end)
	end
	
	for _, player in Players:GetPlayers() do
		task.spawn(playerAdded, player)
	end
	Players.PlayerAdded:Connect(playerAdded)
	
	StatSwitchUpgradeEvent.OnServerEvent:Connect(function(player : Player, upgradeId : number, direction : number)
		if typeof(upgradeId) ~= "number" then return end
		if typeof(direction) ~= "number" then return end
		direction = direction ~= 0 and math.sign(direction) or 1
		
		local data = UpgradesData.GetDataById(upgradeId)
		if not data then return end
		if data.Name == "Plot Tier" then return end
		if not data.SwitchingEnabled then return end
		
		UpgradesService.StatSwitch(player, upgradeId, direction)
	end)
	UpgradeWithRobuxEvent.OnServerEvent:Connect(function(player : Player, upgradeId : number)
		if typeof(upgradeId) ~= "number" then return end

		local data = UpgradesData.GetDataById(upgradeId)
		if not data then return end
		if data.Name == "Plot Tier" then return end
		
		UpgradesService.Upgrade(player, upgradeId, "REQUEST")
	end)
	UpgradeEvent.OnServerEvent:Connect(function(player : Player, upgradeId : number)
		if typeof(upgradeId) ~= "number" then return end
		
		local data = UpgradesData.GetDataById(upgradeId)
		if not data then return end
		if data.Name == "Plot Tier" then return end
		
		UpgradesService.Upgrade(player, upgradeId)
	end)
	
	MonetizationService.OnProductPurchase:Connect(function(player : Player, productId : number)
		for _, upgradeData in UpgradesData.Data do
			if not upgradeData.ProductTiers then continue end
			for _, tierData in upgradeData.ProductTiers do
				if tierData.ProductId == productId then
					
					UpgradesService.Upgrade(player, upgradeData.Id, "BUY")
					return
					
				end
			end
		end
	end)
end

return UpgradesService
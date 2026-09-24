local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local BoostsData = require(ReplicatedStorage.Modules.Data.Boosts)
local Network = require(ReplicatedStorage.Packages.Network)
local UpdateBoostsTimeLeftEvent = Network:RemoteEvent("UpdateBoostsTimeLeft")
local UpdateBoostsEvent = Network:RemoteEvent("UpdateBoosts")
local GetBoostsEvent = Network:RemoteFunction("GetBoosts")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local MainUI = LocalPlayer.PlayerGui:WaitForChild("MainUI")

local BoostsList = MainUI.Boosts
local BoostTemplate = BoostsList.UIGridLayout.BoostTemplate

local FriendInviteButton = MainUI.Stats.FriendBoost.Invite
local FriendBoostLabel : TextLabel = MainUI.Stats.FriendBoost.Percentage

local function getEffectColor(effectName : string)
	if effectName == "luck" then
		return Color3.fromRGB(0,255,0)
	elseif effectName == "size boost" then
		return Color3.fromRGB(255, 158, 81)
	elseif effectName == "mutation" then
		return Color3.fromRGB(0, 194, 247)
	elseif effectName == "money boost" then
		return Color3.fromRGB(0, 255, 0)
	end
	return Color3.fromRGB(255,255,255)
end

local function formatTime(seconds : number)
	if seconds < 60 then
		return seconds.."s"
	end
	
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	return string.format("%dm %ds", minutes, remainingSeconds)
end

local function createBoost(boost)
	local appearanceData = BoostsData.GetDataById(boost.AppearanceId)
	if not appearanceData then return end
	
	local newBoostItem : Frame = BoostTemplate:Clone()
	newBoostItem.Parent = BoostsList
	newBoostItem.Name = "Boost_"..boost.Id
	
	newBoostItem.Boost.Icon.Image = boost.PresetIcon or appearanceData.Icon
	newBoostItem.Boost.Icon.ImageColor3 = appearanceData.ImageColor
	
	newBoostItem.Lifetime.Text = boost.TimeLeft == -10 and "<b>∞</b>" or formatTime(boost.TimeLeft)
	
	local firstMultiplier = nil
	for effectStr, multiplier in boost.Multipliers do
		firstMultiplier = multiplier
	end
	if boost.ShowMultiplier then
		newBoostItem.Effect.Text = `{firstMultiplier}x`
	else
		newBoostItem.Effect.Text = `+{(firstMultiplier-1) * 100}%`
	end
	
	local tooltipFrame = newBoostItem.ToolTip
	local effectTextTemplate : TextLabel = tooltipFrame.Templates.Effect
	tooltipFrame.BoostName.Text = string.lower(boost.PresetName or appearanceData.Name)
	for effectStr, multiplier in boost.Multipliers do
		local newEffect = effectTextTemplate:Clone()
		newEffect.Parent = tooltipFrame

		local e : string = effectStr -- type checker buggin out here idk why so this is a workaround
		if boost.ShowMultiplier then
			newEffect.Text = `{multiplier}x {string.lower(e)}`
		else
			local percentage = (multiplier - 1) * 100
			newEffect.Text = `+{percentage}% {string.lower(e)}`
		end
		
		newEffect.TextColor3 = getEffectColor(string.lower(e))
		
		newEffect.Visible = true
	end
	
	tooltipFrame.Visible = false
	newBoostItem.Boost.MouseEnter:Connect(function() tooltipFrame.Visible = true end)
	newBoostItem.Boost.MouseLeave:Connect(function() tooltipFrame.Visible = false end)
	
	if (boost.PresetName or appearanceData.Name) == "Friend Boost" then
		newBoostItem.Boost.MouseButton1Click:Connect(function()
			SocialService:PromptGameInvite(LocalPlayer)
		end)
	end
	
	newBoostItem.Visible = true
end

local currentBoosts = GetBoostsEvent:InvokeServer()
if currentBoosts then
	for _, boost in currentBoosts do
		if not BoostsList:FindFirstChild("Boost_"..boost.Id) then
			createBoost(boost)
		end
	end
end

UpdateBoostsEvent.OnClientEvent:Connect(function(list)
	local ids = {}
	for _, boost in list do
		if not BoostsList:FindFirstChild("Boost_"..boost.Id) then
			createBoost(boost)
		end
		table.insert(ids, boost.Id)
	end
	for _, boostItem in BoostsList:GetChildren() do
		if boostItem:IsA("Frame") then
			local split = string.split(boostItem.Name, "_")
			local boostId : string = split[2]
			
			local exists = table.find(ids, boostId)
			if not exists then
				boostItem:Destroy()
			end
		end
	end
end)

UpdateBoostsTimeLeftEvent.OnClientEvent:Connect(function(list)
	local times = {}
	for _, boost in list do times[boost.Id] = boost.TimeLeft end
	for _, boostItem in BoostsList:GetChildren() do
		if boostItem:IsA("Frame") then
			local split = string.split(boostItem.Name, "_")
			local boostId : string = split[2]

			local newTimeLeft = times[boostId]
			if newTimeLeft then
				boostItem.Lifetime.Text = newTimeLeft == -10 and "<b>∞</b>" or formatTime(newTimeLeft)
			end
		end
	end
end)

local function updateFriendBoostLabel()
	local friendBoostMultiplier = LocalPlayer:GetAttribute("FriendBoost") or 1
	local boostPercentage = math.round((friendBoostMultiplier - 1) * 100)
	FriendBoostLabel.Text = `friend bonus: +{boostPercentage}%`
end
updateFriendBoostLabel()
LocalPlayer.AttributeChanged:Connect(updateFriendBoostLabel)
FriendInviteButton.MouseButton1Click:Connect(function() SocialService:PromptGameInvite(LocalPlayer) end)
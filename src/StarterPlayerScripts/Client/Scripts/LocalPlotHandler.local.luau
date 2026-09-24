local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local PlotCustomizationUI = ReplicatedStorage.UI.SurfaceGUI.PlotCustomizationUI
local CustomizationSignTemplate = ReplicatedStorage.Assets.Models.CustomizationSign

local PlayerStatsData = require(ReplicatedStorage.Modules.Data.PlayerStats)
local UpgradesData = require(ReplicatedStorage.Modules.Data.Upgrades)
local MuseumColors = require(ReplicatedStorage.Modules.Data.MuseumColors)
local PlayerUtil = require(ReplicatedStorage.Modules.Utils.PlayerUtil)
local MathUtil = require(ReplicatedStorage.Modules.Utils.MathUtil)
local Interface = require(ReplicatedStorage.Modules.Interface)
local Network = require(ReplicatedStorage.Packages.Network)
local ChangePlotColorEvent = Network:RemoteEvent("ChangePlotColor")
local PromptProductEvent = Network:RemoteEvent("PromptProduct")
local GetPlotEvent = Network:RemoteFunction("GetPlot")

local PlotsFolder = workspace.Environment.Museums

local LocalPlayer = Players.LocalPlayer
local PlayerUpgradesFolder = LocalPlayer:WaitForChild("PlayerUpgrades", 20)

local VIP_GAMEPASS_ID = 1662545834
local CustomColorModal = nil

local function handlePlotCustomizationSign(customizationSign : typeof(CustomizationSignTemplate))
	local newCustomizationUI = PlotCustomizationUI:Clone()
	newCustomizationUI.Parent = LocalPlayer.PlayerGui
	newCustomizationUI.Adornee = customizationSign.Display
	
	local customMuseumColorButton : TextButton = newCustomizationUI.CustomColor
	customMuseumColorButton.MouseButton1Click:Connect(function()
		if CustomColorModal then return end
		local gamepassesFolder = LocalPlayer:FindFirstChild("Gamepasses")
		if gamepassesFolder and gamepassesFolder:GetAttribute(`ID_{VIP_GAMEPASS_ID}`) then
			CustomColorModal = Interface.Open("CustomMuseumColorModal", function()
				CustomColorModal = nil
			end)
		else
			PromptProductEvent:FireServer(VIP_GAMEPASS_ID)
		end
	end)
	
	local colorOptionTemplate = newCustomizationUI.ColorGrid.Templates.ColorOptionContainer
	for _, colorData in MuseumColors.Data do
		local newOption = colorOptionTemplate:Clone()
		newOption.Parent = newCustomizationUI.ColorGrid
		newOption.LayoutOrder = colorData.Order

		newOption.TextButton.BackgroundColor3 = colorData.DisplayColor or colorData.PrimaryColor
		newOption.TextButton.MouseButton1Click:Connect(function()
			ChangePlotColorEvent:FireServer(colorData.Id)
		end)
		
		CollectionService:AddTag(newOption.TextButton, "ButtonAnimation1")
		
		newOption.Visible = true
	end
end

local function InitializePlot()
	local plotModel = GetPlotEvent:InvokeServer()
	
	local customizationSignPart = plotModel:WaitForChild("Essentials"):WaitForChild("CustomizationSignPart")
	if customizationSignPart then
		local newCustomizationSign = CustomizationSignTemplate:Clone()
		newCustomizationSign.Parent = plotModel.Essentials
		newCustomizationSign:PivotTo(customizationSignPart.CFrame)
		task.spawn(handlePlotCustomizationSign, newCustomizationSign)
	end
end

local currentFloorModal = nil
local function InitializeFloorTeleport(floorTeleportButton : Model)
	if not floorTeleportButton:IsA("Model") then return end
	
	local ownerPointerValue = floorTeleportButton:FindFirstChildOfClass("ObjectValue")
	local owner : Player? = ownerPointerValue.Value and ownerPointerValue.Value.Value
	
	local newProximityPrompt = Instance.new("ProximityPrompt")
	newProximityPrompt.Parent = floorTeleportButton.PrimaryPart
	newProximityPrompt.RequiresLineOfSight = false
	newProximityPrompt.ActionText = "teleport"
	newProximityPrompt.ObjectText = ""
	newProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	
	newProximityPrompt.Triggered:Connect(function(playerWhoTriggered : Player)
		if playerWhoTriggered ~= LocalPlayer then return end
		if currentFloorModal then return end
		currentFloorModal = Interface.Open("TeleportToFloorModal", function()
			currentFloorModal = nil
		end)
		
		local floorTeleportHandlerScript : LocalScript = currentFloorModal:FindFirstChild("FloorTeleportHandler")
		local selectedPlayerObjectValue = Instance.new("ObjectValue")
		selectedPlayerObjectValue.Parent = currentFloorModal
		selectedPlayerObjectValue.Name = "SelectedPlayer"
		selectedPlayerObjectValue.Value = owner
		floorTeleportHandlerScript.Enabled = true
	end)
end

local floorTeleportButtons = CollectionService:GetTagged("FloorTeleport")
for _, floorTeleportButton in floorTeleportButtons do
	task.spawn(InitializeFloorTeleport, floorTeleportButton)
end
CollectionService:GetInstanceAddedSignal("FloorTeleport"):Connect(InitializeFloorTeleport)

InitializePlot()
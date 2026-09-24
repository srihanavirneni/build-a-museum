local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local TutorialManager = require(ReplicatedStorage.Modules.Tutorial.TutorialManager)
local Interface = require(ReplicatedStorage.Modules.Interface)
local Network = require(ReplicatedStorage.Packages.Network)
local CollectAllEarningsEvent = Network:RemoteFunction("CollectAllEarnings")
local PromptProductEvent = Network:RemoteEvent("PromptProduct")

local LocalPlayer = Players.LocalPlayer
local MainUI = LocalPlayer.PlayerGui:WaitForChild("MainUI")

local GemInfoButton = MainUI.Stats.Gems.Info

local StarterPackButton = MainUI.Left.StarterPackButton
local CollectAnywhereButton = MainUI.Left.CollectAnywhereButton
local CollectionButton = MainUI.Right.CollectionButton
local RebirthButton = MainUI.Right.RebirthButton
local ShopButton = MainUI.Right.ShopButton

local AVAILABLE_ARROW_TWEEN_TIME = 0.5
local COLLECT_ANYWHERE_GAMEPASS_ID = 1665013367

local CurrentModal = nil
local Debounce = false

local function openModal(modalName : string)
	if TutorialManager.IsPlayingTutorial() then return end
	
	if Debounce then return end
	Debounce = true
	
	if CurrentModal then
		if CurrentModal.Name == modalName then
			Interface.Close(CurrentModal, {
				Instant = true
			})
			CurrentModal = nil
			
			Debounce = false
			
			return
		else
			Interface.Close(CurrentModal, {
				Instant = true
			})
			CurrentModal = nil
		end
	end
	
	CurrentModal = Interface.Open(modalName, function()
		CurrentModal = nil
	end)
	
	task.delay(0.5, function()
		Debounce = false
	end)
end

ShopButton.MouseButton1Click:Connect(function() openModal("ShopModal") end)
CollectionButton.MouseButton1Click:Connect(function() openModal("IndexModal") end)
RebirthButton.MouseButton1Click:Connect(function() openModal("RebirthModal") end)
GemInfoButton.MouseButton1Click:Connect(function() openModal("GemInfoModal") end)
StarterPackButton.MouseButton1Click:Connect(function() openModal("StarterPackModal") end)

local collectDebounce = false
CollectAnywhereButton.MouseButton1Click:Connect(function()
	if TutorialManager.IsPlayingTutorial() then return end
	
	if collectDebounce then return end
	collectDebounce = true
	
	local gamepassesFolder = LocalPlayer:FindFirstChild("Gamepasses")
	if gamepassesFolder and gamepassesFolder:GetAttribute(`ID_{COLLECT_ANYWHERE_GAMEPASS_ID}`) then
		CollectAllEarningsEvent:InvokeServer(true)
	else
		PromptProductEvent:FireServer(COLLECT_ANYWHERE_GAMEPASS_ID)
	end
	
	task.delay(0.5, function()
		collectDebounce = false
	end)
end)

RebirthButton.Notify.Visible = LocalPlayer:GetAttribute("RebirthAvailable")
RebirthButton.Arrow.Visible = LocalPlayer:GetAttribute("RebirthAvailable")
LocalPlayer.AttributeChanged:Connect(function(attributeName)
	if attributeName ~= "RebirthAvailable" then return end
	RebirthButton.Notify.Visible = LocalPlayer:GetAttribute("RebirthAvailable")
	RebirthButton.Arrow.Visible = LocalPlayer:GetAttribute("RebirthAvailable")
end)

task.spawn(function()
	local arrowPos = RebirthButton.Arrow.Position
	local arrowOutPos = RebirthButton.Arrow.Position - UDim2.new(0.15, 0, 0, 0)
	while task.wait() do
		local tween1 = TweenService:Create(RebirthButton.Arrow, TweenInfo.new(AVAILABLE_ARROW_TWEEN_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
			Position = arrowOutPos
		})
		tween1:Play()
		tween1.Completed:Wait()

		local tween2 = TweenService:Create(RebirthButton.Arrow, TweenInfo.new(AVAILABLE_ARROW_TWEEN_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut), {
			Position = arrowPos
		})
		tween2:Play()
		tween2.Completed:Wait()
	end
end)
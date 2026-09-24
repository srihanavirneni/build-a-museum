local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local CartoonFallSound = ReplicatedStorage.Assets.Sounds.CartoonFall
local BoxDropParticles = ReplicatedStorage.Assets.VFX.BoxDropParticles
local BoxHealthUI = ReplicatedStorage.UI.BillboardGUI.BoxHealthUI
local DeliveryTimeUI = ReplicatedStorage.UI.BillboardGUI.BoxDeliveryTimeUI
local PlayerStatsData = require(ReplicatedStorage.Modules.Data.PlayerStats)
local SettingsData = require(ReplicatedStorage.Modules.Data.PlayerSettings)
local CameraShaker = require(ReplicatedStorage.Packages.CameraShaker)
local CameraShakeInstance = require(ReplicatedStorage.Packages.CameraShaker.CameraShakeInstance)
local TweenUtil = require(ReplicatedStorage.Modules.Utils.TweenUtil)
local SoundUtil = require(ReplicatedStorage.Modules.Utils.SoundUtil)
local MathUtil = require(ReplicatedStorage.Modules.Utils.MathUtil)
local ItemsData = require(ReplicatedStorage.Modules.Data.Items)
local BoxesData = require(ReplicatedStorage.Modules.Data.Boxes)
local Network = require(ReplicatedStorage.Packages.Network)
local PromptProductEvent = Network:RemoteEvent("PromptProduct")
local GetBoxesEvent = Network:RemoteEvent("GetBoxes")
local BoxCreatedEvent = Network:RemoteEvent("BoxCreated")
local OpenBoxEvent = Network:RemoteEvent("OpenBox")
local GetPlotEvent = Network:RemoteFunction("GetPlot")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local MainUI = LocalPlayer.PlayerGui:WaitForChild("MainUI")
local BoxClickIcon = MainUI.BoxClickContainer.BoxClickIcon
local ClickDelayBar = MainUI.BoxClickContainer.ClickDelayBar
local DeliverAllBoxesButton = MainUI.Left.DeliverAllBoxesButton
local OriginalBoxClickIconSize = BoxClickIcon.Size

local CameraShake = CameraShaker.new(Enum.RenderPriority.Camera.Value, function(shakeCf)
	Camera.CFrame = Camera.CFrame * shakeCf
end)
CameraShake:Start()

local DELIVER_ALL_THRESHOLD = 3 -- min x boxes required to deliver all dev product

local BOX_DROP_HEIGHT = 500
local BOX_BOUNCE_HEIGHT = 2
local BOX_HIT_SCALE = 0.25

local MIN_CAMERA_SHAKE_MAGNITUDE = 0
local MAX_CAMERA_SHAKE_MAGNITUDE = 8
local MAX_CAMERA_SHAKE_DISTANCE = 120

local HIT_SOUNDS = { "Hit1", "Hit2", "Hit3" }
local BOX_BREAK_SOUNDS = { "BoxBreak", "BoxBreak2" }
local DROP_SOUNDS = { "BoxDrop", "BoxDrop2" }

local HIGHLIGHT_COLOR = Color3.fromRGB(0, 255, 0)
local HIGHLIGHT_FLASH_COLOR = Color3.fromRGB(255, 255, 255)

local BOX_MAX_HEALTH_COLOR = Color3.fromRGB(105, 255, 66)
local BOX_MAX_HEALTH_BG_COLOR = Color3.fromRGB(12, 42, 10)
local BOX_MIN_HEALTH_COLOR = Color3.fromRGB(247, 72, 55)
local BOX_MIN_HEALTH_BG_COLOR = Color3.fromRGB(53, 8, 7)

local MAX_BOX_HIGHLIGHT_TRANSPARENCY = 0.9
local MIN_BOX_HIGHLIGHT_TRANSPARENCY = 0.7

local SHATTER_SHAPES = { Enum.PartType.Block, Enum.PartType.Wedge }
local SHATTER_MIN_FORCE, SHATTER_MAX_FORCE = 100, 150
local SHATTER_MIN_COUNT, SHATTER_MAX_COUNT = 50, 70
local FRAGMENT_LIFETIME = 3
local RNG = Random.new()

local BoxController = {}
local ClickCooldown = false
local CurrentBoxes : { Box } = {}
local FocusedBox = nil

local Highlight = Instance.new("SelectionBox")
Highlight.Parent = script
Highlight.Color3 = HIGHLIGHT_COLOR
Highlight.SurfaceTransparency = 1
Highlight.LineThickness = 0.05

local function getDeliveringBoxCount() : number
	local plotModel = GetPlotEvent:InvokeServer()
	if not plotModel then return 0 end
	
	local orderedBoxesFolder : Folder = plotModel.Essentials.OrderedBoxes
	if not orderedBoxesFolder then return 0 end
	
	local deliveringCount = 0
	for _, box in orderedBoxesFolder:GetChildren() do
		local deliveryTimeUI = box:FindFirstChild(DeliveryTimeUI.Name)
		if deliveryTimeUI then
			deliveringCount = deliveringCount + 1
		end
	end
	
	return deliveringCount
end

export type Box = {
	InstanceId : string,
	Model : Model,
	Prompt : ProximityPrompt,
	Opened : boolean,
	Scale : number,
	
	HealthUI : typeof(BoxHealthUI),
	MaxHealth : number,
	Health : number,
}
function BoxController.CreateBox(instanceId : string, boxModel : Model)
	local newBox : Box = {}
	
	local boxId = boxModel:GetAttribute("Id")
	local boxData = BoxesData.GetDataById(boxId)
	
	newBox.InstanceId = instanceId
	newBox.Model = boxModel
	newBox.Scale = boxModel:GetScale()
	
	newBox.Health = boxData.Stats.Strength
	newBox.MaxHealth = boxData.Stats.Strength
	
	newBox.Opened = false
	
	local newProximityPrompt = Instance.new("ProximityPrompt")
	newProximityPrompt.Parent = boxModel
	newProximityPrompt.RequiresLineOfSight = false
	newProximityPrompt.MaxActivationDistance = 15
	newProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	newProximityPrompt:SetAttribute("Ignore", true)
	newBox.Prompt = newProximityPrompt
	
	local newHealthUI = BoxHealthUI:Clone()
	newHealthUI.Parent = newBox.Model
	newHealthUI.Enabled = false
	newHealthUI.HealthBar.BackgroundColor3 = BOX_MAX_HEALTH_BG_COLOR
	newHealthUI.HealthBar.Bar.BackgroundColor3 = BOX_MAX_HEALTH_COLOR
	newHealthUI.HealthBar.Bar.Size = UDim2.new(1,0,1,0)
	newBox.HealthUI = newHealthUI
	
	BoxController.HandlePrompt(newBox)
	
	return newBox
end

function BoxController.ShakeBox(box : Box, intensity : number, frequency : number)
	local rootCFrame = box.Model:GetPivot()
	local startTime = os.clock()

	local tweenInfo = TweenInfo.new(
		1 / frequency,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.Out
	)
	
	box.Model:ScaleTo(BOX_HIT_SCALE)
	TweenUtil.TweenModelScale(box.Model, TweenInfo.new(0.25, Enum.EasingStyle.Back), box.Scale or 1)
	
	while os.clock() - startTime < 0.1 do
		local offset = Vector3.new(
			(math.random() - 0.5) * 2 * intensity,
			(math.random() - 0.5) * 2 * intensity,
			(math.random() - 0.5) * 2 * intensity
		)
		
		TweenUtil.TweenModelToCFrame(
			box.Model, tweenInfo, rootCFrame * CFrame.new(offset)
		).Completed:Wait()
	end
	
	TweenUtil.TweenModelToCFrame(box.Model, tweenInfo, rootCFrame)
end

function BoxController.UpdateHealth(box: Box, newHealth : number)
	for _, otherBox in CurrentBoxes do
		if otherBox.InstanceId ~= box.InstanceId then
			otherBox.HealthUI.Enabled = false
		end
	end

	box.Health = math.clamp(newHealth, 0, box.MaxHealth)
	box.HealthUI.Enabled = box.Health < box.MaxHealth
	
	box.HealthUI.TextLabel.Text = string.lower(box.Model.Name)
	box.HealthUI.HealthBar.Progress.Text = box.Health.." / "..box.MaxHealth
	
	TweenService:Create(box.HealthUI.HealthBar.Bar, TweenInfo.new(0.25), {
		Size = UDim2.new(box.Health / box.MaxHealth, 0, 1, 0),
		BackgroundColor3 = BOX_MIN_HEALTH_COLOR:Lerp(BOX_MAX_HEALTH_COLOR, box.Health / box.MaxHealth)
	}):Play()
	TweenService:Create(box.HealthUI.HealthBar, TweenInfo.new(0.25), {
		BackgroundColor3 = BOX_MIN_HEALTH_BG_COLOR:Lerp(BOX_MAX_HEALTH_BG_COLOR, box.Health / box.MaxHealth)
	}):Play()

	BoxClickIcon.Size = UDim2.new(0,0,0,0)
	TweenService:Create(BoxClickIcon, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
		Size = OriginalBoxClickIconSize
	}):Play()
	
	if not box.Model:FindFirstChildOfClass("Highlight") then
		local newHighlight = Instance.new("Highlight")
		newHighlight.Parent = box.Model
		newHighlight.Adornee = box.Model
		newHighlight.OutlineTransparency = 1
		newHighlight.FillColor = Color3.fromRGB(255, 67, 48)
		newHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
	end
	box.Model.Highlight.FillTransparency = MathUtil.Lerp(
		MIN_BOX_HIGHLIGHT_TRANSPARENCY, MAX_BOX_HIGHLIGHT_TRANSPARENCY,
		box.Health / box.MaxHealth
	)
	
	SoundUtil.Play(LocalPlayer, HIT_SOUNDS[math.random(1, #HIT_SOUNDS)], workspace)
	task.spawn(BoxController.ShakeBox, box, 0.75, 40)
	
	if box.Health <= 0 then
		OpenBoxEvent:FireServer(box.InstanceId)
		BoxController.OpenBox(box)
	end
end

function BoxController.HandlePrompt(box : Box)
	local proximityPrompt : ProximityPrompt = box.Prompt
	proximityPrompt.PromptShown:Connect(function()
		Highlight.Parent = box.Model
		Highlight.Adornee = box.Model
		
		BoxClickIcon.Size = UDim2.new(0,0,0,0)
		BoxClickIcon.Visible = true
		TweenService:Create(BoxClickIcon, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = OriginalBoxClickIconSize
		}):Play()
		
		FocusedBox = box
	end)
	proximityPrompt.PromptHidden:Connect(function()
		Highlight.Parent = script
		Highlight.Adornee = nil
		
		TweenService:Create(BoxClickIcon, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(0,0,0,0)
		}):Play()
		
		FocusedBox = nil
	end)
end

function BoxController.Shatter(box : Box)
	local count = math.random(SHATTER_MIN_COUNT, SHATTER_MAX_COUNT)
	local parts = {}

	for i = 1, count do
		local newPart = Instance.new("Part")
		newPart.Color = box.Model.PrimaryPart.Color
		newPart.Transparency = box.Model.PrimaryPart.Transparency
		newPart.Size = Vector3.new(1,1,1)
		newPart.Shape = SHATTER_SHAPES[math.random(1,#SHATTER_SHAPES)]
		newPart.Parent = workspace.Debris
		newPart.Position = box.Model.PrimaryPart.Position
		newPart.Anchored = false
		newPart.CanCollide = true
		table.insert(parts, newPart)
	end

	for _, part : BasePart in parts do
		local randomUnitVector = MathUtil.RandomUnitVector()
		local appliedForceMagnitude = math.random(SHATTER_MIN_FORCE, SHATTER_MAX_FORCE)

		part:ApplyImpulse(randomUnitVector * appliedForceMagnitude)

		task.delay(FRAGMENT_LIFETIME+RNG:NextNumber(-0.5, 0.5), function()
			local t = TweenService:Create(part, TweenInfo.new(0.9), {
				Transparency = 1
			})
			t:Play()
			t.Completed:Connect(function()
				part:Destroy()
			end)
		end)
	end
end

function BoxController.OpenBox(box : Box)
	local existingHighlight : Highlight = box.Model:FindFirstChildOfClass("Highlight")
	if existingHighlight then existingHighlight:Destroy() end
	
	local proximityPrompt : ProximityPrompt = box.Model:FindFirstChildOfClass("ProximityPrompt")
	if proximityPrompt then proximityPrompt:Destroy() end
	
	BoxController.Shatter(box)
	
	for _, content : BasePart in box.Model:GetChildren() do
		if content:IsA("BasePart") then
			content.Transparency = 1
			content.CanCollide = false
			content.CastShadow = false
		end
		
		if content:IsA("Decal") then
			content.Transparency = 1
		end
	end
	
	box.HealthUI.Enabled = false
	box.Opened = true
	
	local cameraShakeEnabled = SettingsData.GetLocalSetting("camera shake")
	if cameraShakeEnabled then
		local c = CameraShakeInstance.new(15,10,0,0.5)
		c.PositionInfluence = Vector3.new(0.25, 0.25, 0.25)
		c.RotationInfluence = Vector3.new(1,1,1)
		CameraShake:Shake(c)
	end
	
	SoundUtil.Play(LocalPlayer, BOX_BREAK_SOUNDS[math.random(1, #BOX_BREAK_SOUNDS)])
	
	task.delay(2, function()
		BoxController.DestroyBox(box)
	end)
end

function BoxController.DestroyBox(box : Box)
	if box.Model then
		if Highlight.Parent == box.Model then
			Highlight.Parent = script
			Highlight.Adornee = nil
		end
		
		box.Model:Destroy()
		box.Model = nil
	end
	
	if FocusedBox and FocusedBox.InstanceId == box.InstanceId then
		FocusedBox = nil
	end
	
	table.freeze(box)
	box = nil
end

function BoxController.Start()
	local function handleDeliverAllBoxes()
		local plotModel = GetPlotEvent:InvokeServer()
		if not plotModel then return end

		local orderedBoxesFolder : Folder = plotModel.Essentials.OrderedBoxes
		if not orderedBoxesFolder then return end
		
		local function count()
			local deliveringCount = 0
			for _, box in orderedBoxesFolder:GetChildren() do
				local deliveryTimeUI = box:FindFirstChild(DeliveryTimeUI.Name)
				if deliveryTimeUI then
					deliveringCount = deliveringCount + 1
				end
			end
			DeliverAllBoxesButton.Visible = deliveringCount >= DELIVER_ALL_THRESHOLD
		end
		
		count()
		orderedBoxesFolder.ChildAdded:Connect(count)
		orderedBoxesFolder.ChildRemoved:Connect(count)
		BoxCreatedEvent.OnClientEvent:Connect(count)
	end
	
	local function startClickCooldown()
		if ClickCooldown then return end
		ClickCooldown = true

		ClickDelayBar.Bar.Size = UDim2.new(0,0,1,0)
		ClickDelayBar.Visible = true

		local cooldownTime = PlayerStatsData.GetStatValue("Punch Cooldown") or 1
		local tInfo = TweenInfo.new(cooldownTime, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
		local tween = TweenService:Create(ClickDelayBar.Bar, tInfo, {
			Size = UDim2.new(1,0,1,0)
		})
		tween:Play()
		tween.Completed:Wait()

		ClickCooldown = false
		ClickDelayBar.Visible = false
	end
	
	local function shakeCamera(origin : Vector3)
		local distance = LocalPlayer:DistanceFromCharacter(origin)
		local shakeMagnitude = math.max(MathUtil.Lerp(
			MIN_CAMERA_SHAKE_MAGNITUDE, MAX_CAMERA_SHAKE_MAGNITUDE, 
			(MAX_CAMERA_SHAKE_DISTANCE-distance) / MAX_CAMERA_SHAKE_DISTANCE
		), 0)
		local c = CameraShakeInstance.new(shakeMagnitude,10,0,0.5)
		c.PositionInfluence = Vector3.new(0.25, 0.25, 0.25)
		c.RotationInfluence = Vector3.new(2,1,1)
		CameraShake:Shake(c)
	end
	
	local function onBoxCreated(boxInstanceId : string, boxModel : Model, canAnimate : boolean)
		if CurrentBoxes[boxInstanceId] then return end
		
		for _, part : BasePart in boxModel:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = part:GetAttribute("OriginalTransparency")
				part.CanCollide = part:GetAttribute("OriginalCollision")
			end
		end
		
		if canAnimate then
			local originalCF = boxModel.PrimaryPart.CFrame
			boxModel:PivotTo(originalCF + Vector3.new(0, BOX_DROP_HEIGHT, 0))
			
			local particles = BoxDropParticles:Clone()
			particles.Parent = boxModel.PrimaryPart
			
			local newCartoonFallSound = CartoonFallSound:Clone()
			newCartoonFallSound.Parent = workspace.Debris
			newCartoonFallSound:Play()
			
			TweenUtil.TweenModelToCFrame(
				boxModel, 
				TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				originalCF
			).Completed:Connect(function()
				newCartoonFallSound:Stop()
				newCartoonFallSound:Destroy()
				
				SoundUtil.Play(LocalPlayer, DROP_SOUNDS[math.random(1, #DROP_SOUNDS)], boxModel.PrimaryPart)
				
				local cameraShakeEnabled = SettingsData.GetLocalSetting("camera shake")
				if cameraShakeEnabled then
					shakeCamera(originalCF.Position)
				end
				
				particles:Emit(55)
				task.delay(3, function()
					particles:Destroy()
				end)
				
				TweenUtil.TweenModelToCFrame(
					boxModel,
					TweenInfo.new(
						0.1,
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.Out
					),
					originalCF + Vector3.new(0, BOX_BOUNCE_HEIGHT, 0)
				).Completed:Connect(function()
					TweenUtil.TweenModelToCFrame(
						boxModel,
						TweenInfo.new(
							0.1,
							Enum.EasingStyle.Quad,
							Enum.EasingDirection.In
						),
						originalCF
					)
				end)
			end)
		end
		
		local newBox = BoxController.CreateBox(boxInstanceId, boxModel)
		CurrentBoxes[boxInstanceId] = newBox
	end
	
	local function inputBegan(input : InputObject, gameProcessedEvent : boolean)
		if gameProcessedEvent or ClickCooldown then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local focused : Box = FocusedBox
			if not focused then return end
			
			if focused.Opened then return end
			
			local cameraShakeEnabled = SettingsData.GetLocalSetting("camera shake")
			if cameraShakeEnabled then
				local c = CameraShakeInstance.new(6,10,0,0.5)
				c.PositionInfluence = Vector3.new(0.25, 0.25, 0.25)
				c.RotationInfluence = Vector3.new(0,0,0)
				CameraShake:Shake(c)
			end
			
			local damage = PlayerStatsData.GetStatValue("Punch Damage")
			local newHealth = focused.Health - (damage or 1)
			BoxController.UpdateHealth(focused, newHealth)
			task.spawn(startClickCooldown)
		end
	end
	
	BoxCreatedEvent.OnClientEvent:Connect(onBoxCreated)
	GetBoxesEvent:FireServer()
	
	UserInputService.InputBegan:Connect(inputBegan)
	
	task.delay(3, handleDeliverAllBoxes)
	
	local debounce = false
	DeliverAllBoxesButton.MouseButton1Click:Connect(function()
		if debounce then return end
		debounce = false
		
		local deliveringCount = getDeliveringBoxCount()
		if deliveringCount >= DELIVER_ALL_THRESHOLD then
			PromptProductEvent:FireServer(3540039738)
		end
		
		task.delay(0.5, function()
			debounce = false
		end)
	end)
	
	task.spawn(function()
		while task.wait() do
			local tween1 = TweenService:Create(Highlight, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
				Color3 = HIGHLIGHT_FLASH_COLOR
			})
			tween1:Play()
			tween1.Completed:Wait()

			local tween2 = TweenService:Create(Highlight, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
				Color3 = HIGHLIGHT_COLOR
			})
			tween2:Play()
			tween2.Completed:Wait()
		end
	end)
end

return BoxController
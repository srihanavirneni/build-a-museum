local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local T = require('./TutorialTypes')
local Network = require(ReplicatedStorage.Packages.Network)
local TutorialStepEvent = Network:RemoteEvent("TutorialStep")
local StartTutorialEvent = Network:RemoteEvent("StartTutorial")

local DialogUI = script.TutorialDialogUI
local HighlightUI = script.HighlightUI
local GuideBeam = script.GuideBeam

local LocalPlayer = Players.LocalPlayer

local TutorialManager = {}

function TutorialManager.IsPlayingTutorial(player : Player)
	local tutorialFolder = (player or LocalPlayer):FindFirstChild("TutorialSteps")
	if tutorialFolder then
		for _, state in tutorialFolder:GetChildren() do
			local step = state:GetAttribute("Step")
			if step > 0 then return true, step end
		end
	end
	return false
end

function TutorialManager.CreateTutorial(sequence : T.Sequence, during : () -> ()?, complete : () -> ()?)
	if RunService:IsServer() then return warn("TutorialManager is a client only module.") end
	
	local newSequence : T.Sequence = {}
	for key, value in sequence do
		newSequence[key] = value
	end
	
	local tutorialFolder = LocalPlayer:WaitForChild("TutorialSteps")
	if not tutorialFolder:GetAttribute("Done") then repeat task.wait() until tutorialFolder:GetAttribute("Done") end
	
	local stateFolder = tutorialFolder:FindFirstChild(newSequence.Name)
	newSequence.CurrentStep = stateFolder and stateFolder:GetAttribute("Step") or 0
	newSequence.Connections = {}
	
	newSequence.CurrentHighlight = nil
	newSequence.CurrentDialogUI = nil
	
	newSequence.During = during
	newSequence.Complete = complete
	
	return newSequence
end

function TutorialManager.Dialog(
	sequence : T.Sequence, message : string, waitTime : number? | boolean?, bottom : boolean?
)
	if not message then
		if sequence.CurrentDialogUI then
			sequence.CurrentDialogUI:Destroy()
			sequence.CurrentDialogUI = nil
		end
		return
	end
	
	local dialog = sequence.CurrentDialogUI or DialogUI:Clone()
	dialog.Parent = LocalPlayer.PlayerGui
	dialog.Main.Message.Text = ""
	sequence.CurrentDialogUI = dialog

	TweenService:Create(dialog.Main, TweenInfo.new(0.5), {
		Position = (not bottom) and UDim2.new(0.5, 0, 0.1, 0) or UDim2.new(0.5, 0, 0.87, 0),
		AnchorPoint = (not bottom) and Vector2.new(0.5, 0) or Vector2.new(0.5, 1)
	}):Play()
	
	local function typewrite()
		local curText = ""
		local skip = false
		local arrow = 0
		for i, letter in string.split(message,"") do
			curText = curText .. letter
			if letter == "<" then skip = true end
			if letter == ">" then skip = false arrow += 1 continue end
			if arrow == 2 then arrow = 0 end
			if skip then continue end
			
			if not dialog:FindFirstChild("Main") then continue end
			dialog.Main.Message.Text = curText .. if arrow == 1 then "</font>" else ""
			ReplicatedStorage.Assets.Sounds.Dialogue:Play()
			task.wait(1 / 25)
		end
	end
	
	if waitTime then 
		typewrite() 
		if waitTime == "YIELD" then
			local inputConnection = nil
			local continue = false
			inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
				if gameProcessedEvent then return end
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					continue = true
				end
			end)
			
			dialog.Main.ClickContinue.Visible = true
			
			table.insert(sequence.Connections, inputConnection)
			repeat task.wait() until continue == true
		else
			task.wait(waitTime == true and 2 or waitTime)
		end
	else 
		return task.spawn(typewrite)
	end
end

function TutorialManager.DistanceCheck(
	sequence : T.Sequence, target : BasePart | Vector3, threshold : number, on : () -> ()
)
	local distanceConnection = nil
	distanceConnection = RunService.Stepped:Connect(function()
		local targetPos = target:IsA("BasePart") and target.Position or target
		local distance = LocalPlayer:DistanceFromCharacter(targetPos)
		if distance <= threshold then
			distanceConnection:Disconnect()
			distanceConnection = nil
			
			task.spawn(on)
		end
	end)
	
	table.insert(sequence.Connections, distanceConnection)
end

function TutorialManager.TargetPart(sequence : T.Sequence, target : BasePart? | Attachment?)
	local character = LocalPlayer.Character
	local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end
	
	local existingGuideBeam : typeof(GuideBeam) = humanoidRootPart:FindFirstChild(GuideBeam.Name)
	if existingGuideBeam then
		if existingGuideBeam.A0.Value then existingGuideBeam.A0.Value:Destroy() end
		if existingGuideBeam.A1.Value then existingGuideBeam.A1.Value:Destroy() end
		existingGuideBeam:Destroy()
	end

	if not target then return end
	
	local newBeam = GuideBeam:Clone()
	newBeam.Parent = humanoidRootPart
	
	local attachment0 = Instance.new("Attachment")
	attachment0.Parent = humanoidRootPart
	attachment0.Name = "A0"
	
	local attachment1 = target
	if not target:IsA("Attachment") then
		attachment1 = Instance.new("Attachment")
		attachment1.Parent = target
		attachment1.Name = "A1"
	end
	
	newBeam.A0.Value = attachment0
	newBeam.A1.Value = attachment1
	newBeam.Attachment0 = attachment0
	newBeam.Attachment1 = attachment1
	
	return newBeam
end

function TutorialManager.TargetUI(
	sequence : T.Sequence, target : GuiBase2d?, padding : Vector2?
)
	if sequence.CurrentHighlight then
		if not target then
			local highlightFrame = sequence.CurrentHighlight.FrameValue.Value
			local tween = TweenService:Create(highlightFrame.UIStroke, TweenInfo.new(0.25), {
				Transparency = 1
			})
			tween:Play()
			tween.Completed:Connect(function()
				if sequence.CurrentHighlight and sequence.CurrentHighlight.Parent ~= nil then
					sequence.CurrentHighlight:Destroy()
				end
				sequence.CurrentHighlight = nil
			end)
		else
			sequence.CurrentHighlight:Destroy()
			sequence.CurrentHighlight = nil
		end
	end
	
	if not target then return end
	
	local surfaceGui = target:FindFirstAncestorWhichIsA("SurfaceGui")
	
	local newHighlightUI = HighlightUI:Clone()
	
	local highlightFrame = newHighlightUI.HighlightFrame
	highlightFrame.Size = UDim2.new(0, 0, 0, 0)
	highlightFrame.Position = UDim2.new(0.5, 0, 0.5, 0)

	local originalStrokeTransparency = highlightFrame.UIStroke.Transparency
	highlightFrame.UIStroke.Transparency = 1

	newHighlightUI.Parent = surfaceGui or LocalPlayer.PlayerGui
	sequence.CurrentHighlight = newHighlightUI
	
	highlightFrame.Visible = true
	
	if surfaceGui then
		highlightFrame.Parent = surfaceGui
	end
	
	TweenService:Create(highlightFrame.UIStroke, TweenInfo.new(0.25), {
		Transparency = originalStrokeTransparency
	}):Play()
	TweenService:Create(highlightFrame, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Position = UDim2.new(
			0, target.AbsolutePosition.X + target.AbsoluteSize.X/2,
			0, target.AbsolutePosition.Y + target.AbsoluteSize.Y/2
		),
		Size = UDim2.new(
			0, target.AbsoluteSize.X + (padding.X or 0),
			0, target.AbsoluteSize.Y + (padding.Y or 0)
		)
	}):Play()
end

function TutorialManager.Step(sequence : T.Sequence)
	if sequence.CurrentStep == -1 then return end -- tutorial is finished
	if sequence.CurrentStep == 0 then
		StartTutorialEvent:FireServer(sequence.Name)
	end
	
	local nextStep = sequence.CurrentStep + 1
	local segment = sequence.Segments[nextStep]
	
	local tutorialFolder = LocalPlayer:WaitForChild("TutorialSteps")
	if not tutorialFolder then repeat task.wait() until tutorialFolder end
	
	local stateFolder = tutorialFolder and tutorialFolder:WaitForChild(sequence.Name)
	if stateFolder then
		stateFolder:SetAttribute("Step", nextStep)
		sequence.CurrentStep = sequence.CurrentStep + 1
		
		if sequence.During then
			task.spawn(sequence.During, sequence.CurrentStep)
		end
		
		if segment then
			TutorialStepEvent:FireServer(sequence.Name)
			task.spawn(segment, function(clean : boolean?)
				if clean then
					TutorialManager.Dialog(sequence, nil)
					TutorialManager.TargetPart(sequence, nil)
					TutorialManager.TargetUI(sequence, nil)
				end
				
				for _, connection in sequence.Connections do
					connection:Disconnect()
					connection = nil
				end
				sequence.Connections = {}
				TutorialManager.Step(sequence)
			end, sequence)
		else
			TutorialStepEvent:FireServer(sequence.Name, true)
			TutorialManager.End(sequence)
		end
	end
end

function TutorialManager.End(sequence : T.Sequence)
	if sequence.Complete then
		task.spawn(sequence.Complete)
	end
	
	for _, connection in sequence.Connections do
		connection:Disconnect()
		connection = nil
	end
	sequence.Connections = {}
	
	table.freeze(sequence)
	sequence = nil
end

return TutorialManager
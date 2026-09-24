local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local NPCChatBubbleUI = ReplicatedStorage.UI.BillboardGUI.NPCChatBubble
local TypewriteSound = ReplicatedStorage.Assets.Sounds.Dialogue
local Network = require(ReplicatedStorage.Packages.Network)
local OnVisitorChattedEvent = Network:RemoteEvent("OnVisitorChatted")

local LocalPlayer = Players.LocalPlayer

local VISITOR_TALK_SPEED = 35
local VISITOR_TAG = "Visitor"
local VisitorsController = {}

function VisitorsController.Typewrite(textLabel : TextLabel, message : string, sound : Sound)
	textLabel.Text = ""

	local curText = ""
	local skip = false
	local arrow = 0
	for i, letter in string.split(message,"") do
		curText = curText .. letter
		if letter == "<" then skip = true end
		if letter == ">" then skip = false arrow += 1 continue end
		if arrow == 2 then arrow = 0 end
		if skip then continue end

		textLabel.Text = curText .. if arrow == 1 then "</font>" else ""
		task.wait(1 / VISITOR_TALK_SPEED)
		
		if sound then
			sound:Play()
		end
	end
end

function VisitorsController.Start()
	local function initializeVisitor(visitorNPC : Model)
		local hrp = visitorNPC:WaitForChild("HumanoidRootPart")
		local newTypewriteSound = TypewriteSound:Clone()
		newTypewriteSound.Parent = hrp
		newTypewriteSound.Volume = 0.15
	end
	
	local function chatVisitor(visitorNPC : Model, message : string, delayTime : number)
		local humanoidRootPart = visitorNPC:FindFirstChild("HumanoidRootPart")
		local head = visitorNPC:FindFirstChild("Head")
		
		if not humanoidRootPart or not head then return end
		
		local newBubble = NPCChatBubbleUI:Clone()

		newBubble.Container.Content.Message.Text = ""
		newBubble.Container.GroupTransparency = 1
		newBubble.Container.Size = UDim2.new(0,0,0,0)
		
		task.spawn(function()
			local sound = humanoidRootPart:FindFirstChild(TypewriteSound.Name)
			VisitorsController.Typewrite(newBubble.Container.Content.Message, message, sound)
		end)

		newBubble.Parent = head

		TweenService:Create(newBubble.Container, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(1,0,1,0),
			GroupTransparency = 0,
		}):Play()

		task.delay(delayTime, function()
			if not visitorNPC or not visitorNPC:IsDescendantOf(workspace) then return end
			
			local tween = TweenService:Create(newBubble.Container, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Size = UDim2.new(0,0,0,0),
				GroupTransparency = 1,
			})
			tween:Play()
			tween.Completed:Connect(function()
				newBubble:Destroy()
			end)
		end)
	end
	
	for _, visitor : Model in CollectionService:GetTagged(VISITOR_TAG) do
		task.spawn(initializeVisitor, visitor)
	end
	
	OnVisitorChattedEvent.OnClientEvent:Connect(chatVisitor)
	CollectionService:GetInstanceAddedSignal(VISITOR_TAG):Connect(initializeVisitor)
end

return VisitorsController
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ItemsData = require(ReplicatedStorage.Modules.Data.Items)
local BoxesData = require(ReplicatedStorage.Modules.Data.Boxes)
local SoundUtil = require(ReplicatedStorage.Modules.Utils.SoundUtil)
local MathUtil = require(ReplicatedStorage.Modules.Utils.MathUtil)
local RaritiesData = require(ReplicatedStorage.Modules.Data.Rarities)
local LuckUtil = require(ReplicatedStorage.Modules.Utils.LuckUtil)
local MutationsData = require(ReplicatedStorage.Modules.Data.Mutations)
local Network = require(ReplicatedStorage.Packages.Network)
local CollectEarningsEvent = Network:RemoteEvent("CollectEarnings")
local PromptProductEvent = Network:RemoteEvent("PromptProduct")
local PickUpItemEvent = Network:RemoteEvent("PickUpItem")
local StealItemEvent = Network:RemoteEvent("StealItem")
local GetPlotEvent = Network:RemoteFunction("GetPlot")

local LocalPlayer = Players.LocalPlayer
local MainUI = LocalPlayer.PlayerGui:WaitForChild("MainUI")
local ItemToolTipUI = MainUI:WaitForChild("ItemToolTipUI")
local BoxToolTipUI = MainUI:WaitForChild("BoxToolTipUI")

local OriginalItemToolTipPosition = ItemToolTipUI.Position
local MobileItemToolTipPosition = UDim2.new(0, 15, 0.67, 0)
local OriginalBoxToolTipPosition = BoxToolTipUI.Position
local MobileBoxToolTipPosition = UDim2.new(0, 15, 0.67, 0)

local OriginalPedestalStatusSize = ReplicatedStorage.UI.BillboardGUI.ItemPedestalStatusUI.Size

local TOOLTIP_TAG = "ItemTooltip"
local BOX_TAG = "BoxTooltip"
local TOOLTIP_HIGHLIGHT = Instance.new("Highlight")
TOOLTIP_HIGHLIGHT.Parent = script
TOOLTIP_HIGHLIGHT.OutlineTransparency = 0
TOOLTIP_HIGHLIGHT.FillTransparency = 0.7
TOOLTIP_HIGHLIGHT.OutlineColor = Color3.fromRGB(255,255,255)
TOOLTIP_HIGHLIGHT.FillColor = Color3.fromRGB(255,255,255)
TOOLTIP_HIGHLIGHT.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
local COLLECT_HIGHLIGHT = Instance.new("Highlight")
COLLECT_HIGHLIGHT.Parent = script
COLLECT_HIGHLIGHT.OutlineTransparency = 1
COLLECT_HIGHLIGHT.FillColor = Color3.fromRGB(62, 252, 0)
COLLECT_HIGHLIGHT.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
local DELETION_OUTLINE = Instance.new("SelectionBox")
DELETION_OUTLINE.LineThickness = 0.05
DELETION_OUTLINE.Color3 = Color3.fromRGB(255,0,0)

local Items = {}
local CollectAllButton = nil

local function isHoldingDeletionTool()
	local character = LocalPlayer.Character
	local holdingTool : Tool = character and character:FindFirstChildOfClass("Tool")
	if holdingTool and holdingTool:IsA("Tool") and holdingTool.Name == "remove items" then
		return true
	end
	return false
end

local function createBoxToolTipUI(boxId)
	local data = BoxesData.GetDataById(boxId)

	RaritiesData.SetColor(BoxToolTipUI.UIStroke, data.Rarity.Name)
	if data.Rarity.FlatColor then
		BoxToolTipUI.BackgroundColor3 = data.Rarity.FlatColor
	else
		RaritiesData.SetColor(BoxToolTipUI, data.Rarity.Name)
	end
	
	local chances, effectiveLuck = LuckUtil.GetPercentagesForPlayer(
		LocalPlayer, 
		RaritiesData.Data, 
		data.Stats.Luck
	)
	
	BoxToolTipUI.BoxTitle.Text = string.lower(data.Name)
	BoxToolTipUI.Luck.Text = `+{MathUtil.FormatNumber(effectiveLuck)}% luck`
	
	local chanceList = BoxToolTipUI.RarityDistribution
	local chanceTemplate = chanceList.Templates.Chance
	for _, chanceItem in chanceList:GetChildren() do
		if chanceItem:IsA("Frame") then
			chanceItem:Destroy()
		end
	end
	for _, data in BoxesData.ReadChances(chances) do
		local newChanceItem = chanceTemplate:Clone()
		
		newChanceItem.Name = data.Name
		newChanceItem.RarityName.Text = data.Name
		RaritiesData.SetColor(newChanceItem.RarityName, data.Name)
		newChanceItem.Value.Text = `{data.Chance}%`
		
		newChanceItem.Parent = chanceList
		newChanceItem.Visible = true
	end
	
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local targetPos : UDim2 = isMobile and MobileBoxToolTipPosition or OriginalBoxToolTipPosition
	BoxToolTipUI.AnchorPoint = isMobile and Vector2.new(0,1) or Vector2.new(1,1)
	BoxToolTipUI.Position = targetPos + UDim2.new(0,0,0.015,0)
	BoxToolTipUI.Visible = true
	TweenService:Create(BoxToolTipUI, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
		Position = targetPos
	}):Play()
end

local function createToolTipUI(itemId, itemSize, mutationId)
	local data = ItemsData.GetDataById(itemId)
	
	RaritiesData.SetColor(ItemToolTipUI.UIStroke, data.Rarity.Name)
	RaritiesData.SetColor(ItemToolTipUI.Rarity, data.Rarity.Name)
	if data.Rarity.FlatColor then
		ItemToolTipUI.BackgroundColor3 = data.Rarity.FlatColor
	else
		RaritiesData.SetColor(ItemToolTipUI, data.Rarity.Name)
	end
	
	ItemToolTipUI.ItemTitle.Text = string.lower(data.Name)
	ItemToolTipUI.Rarity.Text = string.lower(data.Rarity.Name)
	
	local moneyPerSecond = ItemsData.GetCost(itemId, itemSize, mutationId)
	
	if mutationId then
		local mutationData = MutationsData.GetDataById(mutationId)
		if mutationData then
			ItemToolTipUI.Mutation.Visible = true
			ItemToolTipUI.Mutation.Text = string.lower(mutationData.Name)
			MutationsData.SetColor(ItemToolTipUI.Mutation, mutationId)
		end
	else
		ItemToolTipUI.Mutation.Visible = false
	end

	ItemToolTipUI.Stats.ItemSize.Value.Text = `{itemSize}x`
	if data.Rarity.Exclusive then
		-- TODO: show exact income in realtime
		ItemToolTipUI.Stats.MoneyPerSecond.Value.Text = (MathUtil.FormatNumber(moneyPerSecond)).."%"
		
		ItemToolTipUI.Stats.InterestTime.Visible = false
	else
		ItemToolTipUI.Stats.InterestTime.Value.Text = data.InterestTime.."s"
		ItemToolTipUI.Stats.InterestTime.Visible = true
		
		ItemToolTipUI.Stats.MoneyPerSecond.Value.Text = "$"..(MathUtil.FormatNumber(moneyPerSecond)).." / s"
	end
	
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local targetPos : UDim2 = isMobile and MobileItemToolTipPosition or OriginalItemToolTipPosition
	ItemToolTipUI.AnchorPoint = isMobile and Vector2.new(0,1) or Vector2.new(1,1)
	ItemToolTipUI.Position = targetPos + UDim2.new(0,0,0.015,0)
	ItemToolTipUI.Visible = true
	TweenService:Create(ItemToolTipUI, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
		Position = targetPos
	}):Play()
end

local function updateItems(deltaTime)
	local holdingDeletionTool = isHoldingDeletionTool()
	local totalEarnings = 0
	for part, data in Items do
		local ownerObjectValue = part:WaitForChild("OWNER")
		if not ownerObjectValue or ownerObjectValue.Value ~= LocalPlayer then
			data.Outline.Transparency = 1
			continue
		end
		
		local outline : SelectionBox = data.Outline
		local actionPrompt : ProximityPrompt = data.Prompt

		outline.Transparency = holdingDeletionTool and 0 or 1
		
		if data.IsDecoration then
			actionPrompt.ActionText = holdingDeletionTool and "remove" or ""
			actionPrompt.Enabled = holdingDeletionTool
		else
			local visitorEarnings = part:GetAttribute("Earnings") or 0
			local passiveEarnings = part:GetAttribute("PassiveEarnings") or 0
			
			actionPrompt.ActionText = holdingDeletionTool and "remove" or "collect"

			TOOLTIP_HIGHLIGHT.OutlineTransparency = holdingDeletionTool and 1 or 0
			TOOLTIP_HIGHLIGHT.FillTransparency = holdingDeletionTool and 1 or 0.7

			totalEarnings = totalEarnings + (visitorEarnings + passiveEarnings)
		end
	end
	
	if CollectAllButton then
		local buttonPart = CollectAllButton:WaitForChild("ButtonPart")
		local earningsUI : BillboardGui = buttonPart:WaitForChild("CollectEarningsUI")
		earningsUI.MoneyText.Text = "$"..MathUtil.FormatNumber(totalEarnings)
	end
end

function InitializeBox(boxModel : Model)
	if not boxModel:IsA("Model") then return end
	
	local boxId = boxModel:GetAttribute("Id")
	local proximityPrompt : ProximityPrompt = nil
	local success, err = pcall(function()
		proximityPrompt = boxModel:WaitForChild("ProximityPrompt", 10)
	end)
	
	local function initializePrompt(prompt : ProximityPrompt)
		if not prompt:IsA("ProximityPrompt") then return end
		prompt.PromptShown:Connect(function()
			createBoxToolTipUI(boxId)
			SoundUtil.Play(LocalPlayer, "SlightClick")
		end)
		prompt.PromptHidden:Connect(function()
			BoxToolTipUI.Visible = false
		end)
	end
	
	if success and proximityPrompt then
		initializePrompt(proximityPrompt)
		boxModel.DescendantAdded:Connect(initializePrompt)
	end
end

function InitializePart(part : BasePart | ProximityPrompt)
	local isDecoration = part:GetAttribute("Decoration")
	local pedestalUI : BillboardGui = not isDecoration and part:WaitForChild("ItemPedestalStatusUI")
	
	local itemInstanceId = part:GetAttribute("InstanceId")
	local mutationId = part:GetAttribute("MutationId")
	local itemId = part:GetAttribute("Id")
	
	local data = ItemsData.GetDataById(itemId)
	
	local ownerObjectValue = part:WaitForChild("OWNER")
	if not ownerObjectValue then return end
	
	local isOwner : boolean? = ownerObjectValue.Value == LocalPlayer
	
	local actionPrompt = Instance.new("ProximityPrompt")
	actionPrompt.Parent = part:IsA("Model") and (part:FindFirstChild("PromptAdornee") or part.PrimaryPart) or part
	actionPrompt.ObjectText = ""
	actionPrompt.ActionText = isOwner and "collect" or "steal item"
	actionPrompt.RequiresLineOfSight = false
	actionPrompt.Enabled = not isDecoration
	actionPrompt.Style = Enum.ProximityPromptStyle.Custom
	local newDeletionOutline = DELETION_OUTLINE:Clone()
	newDeletionOutline.Parent = part
	newDeletionOutline.Adornee = part
	newDeletionOutline.Visible = false
	
	if pedestalUI then pedestalUI.Enabled = false end
	
	local collecting = false
	actionPrompt.Triggered:Connect(function()
		if collecting then return end
		collecting = true
		
		task.delay(0.5, function()
			collecting = false
		end)
		
		if not isOwner and not isDecoration then
			StealItemEvent:FireServer(ownerObjectValue.Value, itemInstanceId)
			return
		end
		
		if isHoldingDeletionTool() then
			PickUpItemEvent:FireServer(itemInstanceId)
		else
			if isDecoration then return end
			if part:GetAttribute("Earnings") > 0 then
				local newCollectHighlight = COLLECT_HIGHLIGHT:Clone()
				newCollectHighlight.FillTransparency = 1
				newCollectHighlight.Parent = part
				newCollectHighlight.Adornee = part
				local tween1 = TweenService:Create(newCollectHighlight, TweenInfo.new(0.2), {
					FillTransparency = 0.5
				})
				tween1:Play()
				tween1.Completed:Connect(function()
					local tween2 = TweenService:Create(newCollectHighlight, TweenInfo.new(0.2), {
						FillTransparency = 1
					})
					tween2:Play()
					tween2.Completed:Connect(function()
						newCollectHighlight:Destroy()
					end)
				end)
			end
			CollectEarningsEvent:FireServer(itemInstanceId)
		end
	end)
	
	actionPrompt.PromptShown:Connect(function()
		if not isDecoration then
			TOOLTIP_HIGHLIGHT.Adornee = part
			RaritiesData.SetColor(TOOLTIP_HIGHLIGHT, data.Rarity.Name)

			pedestalUI.Size = UDim2.new(0,0,0,0)
			pedestalUI.Enabled = true
			TweenService:Create(pedestalUI, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
				Size = OriginalPedestalStatusSize
			}):Play()
			
			createToolTipUI(itemId, part:GetAttribute("Size"), mutationId)
		end

		SoundUtil.Play(LocalPlayer, "SlightClick")
		newDeletionOutline.Visible = true
	end)
	actionPrompt.PromptHidden:Connect(function()
		TOOLTIP_HIGHLIGHT.Adornee = nil
		ItemToolTipUI.Visible = false
		if pedestalUI then
			pedestalUI.Enabled = false
		end

		newDeletionOutline.Visible = false
	end)
	
	Items[part] = {
		Outline = newDeletionOutline,
		Prompt = actionPrompt,
		IsDecoration = isDecoration,
		Tween = nil,
	}

	part.AttributeChanged:Connect(function(attributeName)
		if pedestalUI and pedestalUI.Enabled and (attributeName == "Earnings" or attributeName == "PassiveEarnings") then
			local earningsFrame = pedestalUI:FindFirstChild("Earnings")
			local earningsValueText : TextLabel = earningsFrame and earningsFrame.Value
			
			if not earningsValueText then return end
			
			earningsValueText.TextColor3 = Color3.fromRGB(0, 255, 0)
			
			if Items[part].Tween then
				Items[part].Tween:Cancel()
				Items[part].Tween = nil
			end
			
			Items[part].Tween = TweenService:Create(earningsValueText, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
				Size = UDim2.new(1.25,0,1.25,0),
				TextColor3 = Color3.fromRGB(255,255,255)
			})
			Items[part].Tween:Play()
			Items[part].Tween.Completed:Connect(function()
				if not Items[part] then return end
				Items[part].Tween = TweenService:Create(earningsValueText, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					Size = UDim2.new(1,0,1,0),
					TextColor3 = Color3.fromRGB(0,255,0)
				})
				Items[part].Tween:Play()
			end)
		end
	end)
end

local function initializePlot()
	local plotModel = GetPlotEvent:InvokeServer()
	
	local interiorFolder = plotModel:WaitForChild("Essentials"):WaitForChild("Interior")
	CollectAllButton = interiorFolder:WaitForChild("CollectAllButton")
end

local parts = CollectionService:GetTagged(TOOLTIP_TAG)
for _, part in parts do
	task.spawn(InitializePart,part)
end

CollectionService:GetInstanceAddedSignal(BOX_TAG):Connect(InitializeBox)

CollectionService:GetInstanceAddedSignal(TOOLTIP_TAG):Connect(InitializePart)
CollectionService:GetInstanceRemovedSignal(TOOLTIP_TAG):Connect(function(part)
	Items[part] = nil
end)

RunService.Heartbeat:Connect(updateItems)
initializePlot()
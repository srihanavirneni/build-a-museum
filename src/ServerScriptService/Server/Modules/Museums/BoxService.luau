local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ServerLuckMultiplierValue = ReplicatedStorage.Modules.Data.ServerLuckMultiplier
local MonetizationService = require(ServerScriptService.Server.Modules.Monetization.MonetizationService)
local ItemCollectionService = require(ServerScriptService.Server.Modules.Museums.ItemCollectionService)
local PlayerDataService = require(ServerScriptService.Server.Modules.PlayerData.PlayerDataService)
local BoostsService = require(ServerScriptService.Server.Modules.Progression.BoostsService)
local ItemService = require(ServerScriptService.Server.Modules.Museums.ItemService)
local StatsService = require(ServerScriptService.Server.Modules.Progression.StatsService)
local RemoveOrderFromBoxSpawnerEvent = ServerScriptService.Server.Bindables.RemoveOrderFromBoxSpawner
local AddOrderToBoxSpawnerEvent = ServerScriptService.Server.Bindables.AddOrderToBoxSpawner
local GetPlotBindableFunction = ServerScriptService.Server.Bindables.GetPlot
local T = require(ServerScriptService.Server.Modules.Museums.PlotTypes)
local BoxAssetsFolder = ServerStorage.Assets.Boxes

local TutorialManager = require(ReplicatedStorage.Modules.Tutorial.TutorialManager)
local BoxDeliveryTimeUI = ReplicatedStorage.UI.BillboardGUI.BoxDeliveryTimeUI
local ObjectUtil = require(ReplicatedStorage.Modules.Utils.ObjectUtil)
local MathUtil = require(ReplicatedStorage.Modules.Utils.MathUtil)
local ItemsData = require(ReplicatedStorage.Modules.Data.Items)
local BoxesData = require(ReplicatedStorage.Modules.Data.Boxes)
local RaritiesData = require(ReplicatedStorage.Modules.Data.Rarities)
local Network = require(ReplicatedStorage.Packages.Network)
local BoxCreatedEvent = Network:RemoteEvent("BoxCreated")
local BoxOpenedEvent = Network:RemoteEvent("BoxOpened")
local GetBoxesEvent = Network:RemoteEvent("GetBoxes")
local OpenBoxEvent = Network:RemoteEvent("OpenBox")

local MAX_BOX_PLACEMENT_ATTEMPTS = 50
local ORDER_TRANSPARENCY = 0.5

local SKIP_PRODUCT_ID = 3508023547
local SKIP_ALL_PRODUCT_ID = 3540039738

local MIN_ORDER_COLOR = Color3.fromRGB(255, 38, 43)
local MAX_ORDER_COLOR = Color3.fromRGB(0, 255, 0)

local BoxService = {}
local CurrentOrders = {}
local CurrentlySkipping = {}

local function formatTime(seconds)
	if seconds < 60 then
		return seconds.."s"
	end
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	return string.format("%dm %ds", minutes, remainingSeconds)
end

function BoxService.CreateOrder(
	player : Player, 
	boxId : number, 
	boxInstanceId : string, 
	maxDeliveryTime : number, 
	deliveryTimeLeft : number, 
	isDelivered : boolean?
)
	local newOrder : T.Order = {}

	newOrder.Player = player
	newOrder.BoxId = boxId
	newOrder.BoxInstanceId = boxInstanceId
	newOrder.MaxDeliveryTime = maxDeliveryTime
	newOrder.DeliveryTimeLeft = deliveryTimeLeft
	newOrder.Delivered = isDelivered or false

	newOrder.Connections = {}
	newOrder.OrderModel = BoxService.PlaceOrder(newOrder)
	newOrder.OrderModel:SetAttribute("Id", newOrder.BoxId)
	
	newOrder.SkipTimePrompt = nil

	if newOrder.Delivered then
		BoxService.DeliverOrder(newOrder)
	end

	local currentTime = 0
	table.insert(newOrder.Connections, RunService.Heartbeat:Connect(function(deltaTime)
		if newOrder.Delivered then return end
		currentTime = currentTime + deltaTime
		if currentTime >= 1 then
			currentTime = 0
			BoxService.TickOrder(newOrder)
		end
	end))
	
	CollectionService:AddTag(newOrder.OrderModel, "BoxTooltip")

	return newOrder
end

function BoxService.TickOrder(order : T.Order)
	if order.Delivered then return end
	if not order.OrderModel then return end

	local profile = PlayerDataService.GetProfile(order.Player)
	if not profile then return end
	
	local deliveryTimeUI : typeof(BoxDeliveryTimeUI) = order.OrderModel:FindFirstChild(BoxDeliveryTimeUI.Name)
	if not deliveryTimeUI then return end

	order.DeliveryTimeLeft = order.DeliveryTimeLeft - 1
	deliveryTimeUI.Time.Text = formatTime(order.DeliveryTimeLeft)

	local deliveryColor = MIN_ORDER_COLOR:Lerp(MAX_ORDER_COLOR, (order.MaxDeliveryTime - order.DeliveryTimeLeft) / order.MaxDeliveryTime)
	deliveryTimeUI.TextLabel.TextColor3 = deliveryColor
	deliveryTimeUI.Time.TextColor3 = deliveryColor

	for index, savedOrder in profile.Data.OrderedBoxes do
		if savedOrder.InstanceId == order.BoxInstanceId then
			savedOrder.DeliveryTime = math.max(order.DeliveryTimeLeft, 0)
		end
	end

	if order.DeliveryTimeLeft <= 0 then
		order.DeliveryTimeLeft = 0
		deliveryTimeUI:Destroy()

		BoxService.DeliverOrder(order)
	end
end

function BoxService.DeliverOrder(order : T.Order)
	local alreadyDelivered = order.Delivered
	order.Delivered = true

	local profile = PlayerDataService.GetProfile(order.Player)
	if profile then
		for index, savedOrder in profile.Data.OrderedBoxes do
			if savedOrder.InstanceId == order.BoxInstanceId then
				savedOrder.Delivered = true
			end
		end
	end
	
	if order.SkipTimePrompt then
		order.SkipTimePrompt:Destroy()
		order.SkipTimePrompt = nil
	end

	if alreadyDelivered then
		for _, part : BasePart in order.OrderModel:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = part:GetAttribute("OriginalTransparency")
				part.CanCollide = part:GetAttribute("OriginalCollision")
			elseif part:IsA("ProximityPrompt") then
				part:Destroy()
			end
		end
	else
		for _, part : BasePart in order.OrderModel:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = 1
			elseif part:IsA("ProximityPrompt") then
				part:Destroy()
			elseif part:IsA("Decal") then
				part.Transparency = 1
			
			end
		end

		task.delay(2, function()
			if order.OrderModel and order.OrderModel:IsDescendantOf(workspace) then
				for _, part : BasePart in order.OrderModel:GetChildren() do
					if part:IsA("BasePart") then
						part.Transparency = part:GetAttribute("OriginalTransparency")
						part.CanCollide = part:GetAttribute("OriginalCollision")
					end
				end
			end
		end)
	end

	order.OrderModel:SetAttribute("Id", order.BoxId)
	if not alreadyDelivered then
		BoxCreatedEvent:FireClient(order.Player, order.BoxInstanceId, order.OrderModel, true)
	end
end

function BoxService.PlaceOrder(order : T.Order)
	local boxAreaModel = CurrentOrders[order.Player].BoxArea
	
	local orderedBoxesFolder = boxAreaModel.Parent.OrderedBoxes
	local areaPart = boxAreaModel.Area

	local boxData = BoxesData.GetDataById(order.BoxId)
	if not boxData then return end
	local boxModelTemplate = BoxAssetsFolder:FindFirstChild(boxData.Name)
	if not boxModelTemplate then return end

	local newBoxModel : Model = boxModelTemplate:Clone()
	newBoxModel.Parent = orderedBoxesFolder

	for _, part : BasePart in newBoxModel:GetChildren() do
		if part:IsA("BasePart") then
			part:SetAttribute("OriginalTransparency", part.Transparency)
			part:SetAttribute("OriginalCollision", part.CanCollide)
			part.Transparency = ORDER_TRANSPARENCY
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
		end
	end

	if not order.Delivered then
		local newBoxDeliveryTimeUI = BoxDeliveryTimeUI:Clone()
		newBoxDeliveryTimeUI.Parent = newBoxModel
		newBoxDeliveryTimeUI.Adornee = newBoxModel
		newBoxDeliveryTimeUI.Time.Text = formatTime(order.DeliveryTimeLeft)
		local deliveryColor = MIN_ORDER_COLOR:Lerp(MAX_ORDER_COLOR, (order.MaxDeliveryTime - order.DeliveryTimeLeft) / order.MaxDeliveryTime)
		newBoxDeliveryTimeUI.TextLabel.TextColor3 = deliveryColor
		newBoxDeliveryTimeUI.Time.TextColor3 = deliveryColor
		
		local newSkipTimePrompt = Instance.new("ProximityPrompt")
		newSkipTimePrompt.Parent = newBoxModel
		newSkipTimePrompt.ObjectText = ""
		newSkipTimePrompt.ActionText = "unbox now!"
		newSkipTimePrompt.KeyboardKeyCode = Enum.KeyCode.E
		newSkipTimePrompt.MaxActivationDistance = 10
		newSkipTimePrompt.RequiresLineOfSight = false
		newSkipTimePrompt.Style = Enum.ProximityPromptStyle.Custom
		newSkipTimePrompt.Triggered:Connect(function(playerWhoTriggered : Player)
			if order.Player ~= playerWhoTriggered then return end
			if CurrentlySkipping[order.Player] then return end
			
			CurrentlySkipping[order.Player] = order.BoxInstanceId
			MonetizationService.PromptPlayer(order.Player, 3508023547)
		end)
		CollectionService:AddTag(newSkipTimePrompt, "HighlightablePrompt")
		order.SkipTimePrompt = newSkipTimePrompt
	end
	
	local rotation : Vector3 = newBoxModel:GetAttribute("Rotation") or Vector3.zero
	local dedicatePrimary : boolean = newBoxModel:GetAttribute("Rotation") and true or false
	
	newBoxModel:PivotTo(CFrame.new(Vector3.new(500,500,500)) * CFrame.Angles(
		math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)
		))
	
	--local _, boxSize = newBoxModel:GetBoundingBox()
	local _, boxSize = ObjectUtil.GetBoundingBox(dedicatePrimary and newBoxModel.PrimaryPart or newBoxModel)

	local maxX = (areaPart.Size.X - boxSize.X) / 2
	local maxZ = (areaPart.Size.Z - boxSize.Z) / 2

	local existing = {}
	for _, model in orderedBoxesFolder:GetChildren() do
		if model:IsA("Model") and model ~= newBoxModel then
			local cf, size = model:GetBoundingBox()
			local localPos = areaPart.CFrame:PointToObjectSpace(cf.Position)
			table.insert(existing, {
				x = localPos.X,
				z = localPos.Z,
				hx = size.X / 2,
				hz = size.Z / 2,
			})
		end
	end

	for i = 1, MAX_BOX_PLACEMENT_ATTEMPTS do
		local x = (math.random() * 2 - 1) * maxX
		local z = (math.random() * 2 - 1) * maxZ

		local overlap = false
		for _, box in existing do
			if math.abs(x - box.x) < (boxSize.X/2 + box.hx)
				and math.abs(z - box.z) < (boxSize.Z/2 + box.hz) then
				overlap = true
				break
			end
		end

		if not overlap then
			local randomCFrame = areaPart.CFrame * CFrame.new(x, areaPart.Size.Y / 2 + boxSize.Y / 2, z)
			newBoxModel:PivotTo(randomCFrame * CFrame.Angles(
				math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)
			))

			return newBoxModel
		end
	end

	-- just in case anything else fails:
	local randomX = (math.random() * 2 - 1) * maxX
	local randomZ = (math.random() * 2 - 1) * maxZ
	local randomCFrame = areaPart.CFrame * CFrame.new(randomX, areaPart.Size.Y / 2 + boxSize.Y / 2, randomZ)
	newBoxModel:PivotTo(randomCFrame * CFrame.Angles(
		math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)
		))
	return newBoxModel
end

function BoxService.DestroyOrder(order : T.Order, removeSaved : boolean?)
	local profile = PlayerDataService.GetProfile(order.Player)
	if profile and removeSaved then
		for index, savedOrder in profile.Data.OrderedBoxes do
			if savedOrder.InstanceId == order.BoxInstanceId then

				table.remove(profile.Data.OrderedBoxes, index)

			end
		end
	end

	RemoveOrderFromBoxSpawnerEvent:Fire(order.Player, order.BoxInstanceId)

	for _, connection in order.Connections do
		connection:Disconnect()
		connection = nil
	end

	if order.OrderModel then
		order.OrderModel:Destroy()
		order.OrderModel = nil
	end

	if CurrentOrders[order.Player] then
		CurrentOrders[order.Player].Orders[order.BoxInstanceId] = nil
	end

	table.freeze(order)
	order = nil
end

export type BoxProps = {
	DeliveryTimeLeft : number?,
	BoxInstanceId : string?,
}
function BoxService.GiveBox(player : Player, boxId : number, props : BoxProps) : T.Order
	props = props or {}

	local profile = PlayerDataService.GetProfile(player)
	if not profile then return end

	local boxData = BoxesData.GetDataById(boxId)
	if not boxData then return end

	local boxInstanceId = props.BoxInstanceId or HttpService:GenerateGUID()
	local deliveryTime = props.DeliveryTimeLeft or math.random(boxData.Stats.DeliveryTime[1], boxData.Stats.DeliveryTime[2])
	
	local deliveryTimePercentage = StatsService.GetStat(player, "Box Delivery Time") or 0
	deliveryTime = math.max(deliveryTime - math.floor(deliveryTime * (deliveryTimePercentage / 100)), 0)
	
	local order = BoxService.CreateOrder(player, boxId, boxInstanceId, deliveryTime, deliveryTime, false)
	CurrentOrders[player].Orders[boxInstanceId] = order
	table.insert(profile.Data.OrderedBoxes, {
		InstanceId = boxInstanceId,
		MaxDeliveryTime = deliveryTime,
		DeliveryTime = deliveryTime,
		Delivered = false,
		Id = boxId,
	})
	
	return order
end

function BoxService.Open(player : Player, boxInstanceId : string)
	if typeof(boxInstanceId) ~= "string" then return end
	
	local currentOrder : T.Order = CurrentOrders[player].Orders[boxInstanceId]
	if not currentOrder then return end

	local boxData = BoxesData.GetDataById(currentOrder.BoxId)
	
	local itemCount = TutorialManager.IsPlayingTutorial(player) 
		and 1 or math.random(boxData.Stats.Items[1], boxData.Stats.Items[2])
	
	local sizeBoostMultiplier = BoostsService.GetCumulativeMultiplier(player, "Size Boost")
	local luckBoostMultiplier = BoostsService.GetCumulativeMultiplier(player, "Luck")
	
	local sizeBoostPercentage = math.floor((sizeBoostMultiplier - 1) * 100)
	local luckBoostPercentage = math.floor((luckBoostMultiplier - 1) * 100)
	
	local rolledItemData = ItemService.RollItems(player, boxData.Stats.Luck, itemCount, {
		SizeBoostPercentage = sizeBoostPercentage,
		LuckBoostPercentage = luckBoostPercentage
	})

	local _, boxSize = currentOrder.OrderModel:GetBoundingBox()
	local originPosition = currentOrder.OrderModel.PrimaryPart.Position - Vector3.new(0,boxSize.Y/2,0)
	
	PlayerDataService.UpdateProfileData(player, "BoxesOpened", function(old)
		return old + 1
	end)
	
	BoxOpenedEvent:FireClient(player, currentOrder.BoxInstanceId)
	
	task.spawn(function() ItemCollectionService.CreateItemCollectors(player, originPosition, rolledItemData) end)
	task.delay(2, function() BoxService.DestroyOrder(currentOrder, true) end)
end

function BoxService.Start()
	local function playerAdded(player : Player)
		local profile = PlayerDataService.GetProfile(player)
		if not profile then return end

		local plotModel = GetPlotBindableFunction:Invoke(player)
		local boxArea = plotModel.Essentials.BoxArea
		
		CurrentOrders[player] = {
			BoxArea = boxArea,
			Orders = {}
		}

		local timeSpentOffline = player:GetAttribute("TimeSpentOffline") or 0
		for index, savedOrderData in profile.Data.OrderedBoxes do
			profile.Data.OrderedBoxes[index].DeliveryTime -= math.floor(timeSpentOffline)
			if profile.Data.OrderedBoxes[index].DeliveryTime <= 0 then
				profile.Data.OrderedBoxes[index].DeliveryTime = 0
				profile.Data.OrderedBoxes[index].Delivered = true
			end
			
			local order = BoxService.CreateOrder(
				player, 
				savedOrderData.Id, 
				savedOrderData.InstanceId, 
				savedOrderData.MaxDeliveryTime, 
				savedOrderData.DeliveryTime, 
				savedOrderData.Delivered
			)

			CurrentOrders[player].Orders[savedOrderData.InstanceId] = order
			AddOrderToBoxSpawnerEvent:Fire(player, order)
		end
	end

	for _, player in Players:GetPlayers() do
		task.spawn(playerAdded, player)
	end
	
	OpenBoxEvent.OnServerEvent:Connect(BoxService.Open)
	GetBoxesEvent.OnServerEvent:Connect(function(player : Player)
		if not CurrentOrders[player] then repeat task.wait() until CurrentOrders[player] end
		for _, order : T.Order in CurrentOrders[player].Orders do
			if order.Delivered then
				BoxCreatedEvent:FireClient(player, order.BoxInstanceId, order.OrderModel, false)
			end
		end
	end)

	Players.PlayerAdded:Connect(playerAdded)
	Players.PlayerRemoving:Connect(function(player : Player)
		CurrentlySkipping[player] = nil
		if not CurrentOrders[player] then return end
		for _, order in CurrentOrders[player].Orders do
			BoxService.DestroyOrder(order, false)
		end
		CurrentOrders[player] = nil
	end)
	
	MonetizationService.OnProductPurchase:Connect(function(player : Player, productId : number)
		if productId ~= SKIP_ALL_PRODUCT_ID then return end
		
		local playerOrders = CurrentOrders[player]
		if not playerOrders then return end
		
		for _, order : T.Order in playerOrders.Orders do
			if order.Delivered then continue end
			if order.OrderModel then
				local deliveryTimeUI : typeof(BoxDeliveryTimeUI) = 
					order.OrderModel:FindFirstChild(BoxDeliveryTimeUI.Name)
				if deliveryTimeUI then
					deliveryTimeUI:Destroy()
				end
			end
			
			BoxService.DeliverOrder(order)
		end
	end)
	MonetizationService.OnProductPurchase:Connect(function(player : Player, productId : number)
		if productId ~= SKIP_PRODUCT_ID then return end
		if not CurrentlySkipping[player] then return end
		
		local targetInstanceId = CurrentlySkipping[player]
		local currentOrder : T.Order = CurrentOrders[player].Orders[targetInstanceId]
		if not currentOrder then return end
		
		local deliveryTimeUI : typeof(BoxDeliveryTimeUI) = 
			currentOrder.OrderModel:FindFirstChild(BoxDeliveryTimeUI.Name)
		if deliveryTimeUI then
			deliveryTimeUI:Destroy()
		end
		
		CurrentlySkipping[player] = nil
		BoxService.DeliverOrder(currentOrder)
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId : number, productId : number, isPurchased : boolean?)
		local player : Player = Players:GetPlayerByUserId(userId)
		if not player then return end
		if productId ~= SKIP_PRODUCT_ID then return end
		if not isPurchased then CurrentlySkipping[player] = nil end
	end)
end

return BoxService
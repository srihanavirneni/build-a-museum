local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local CanRebirthBindableFunction = ServerScriptService.Server.Bindables.CanRebirth
local MonetizationService = require(ServerScriptService.Server.Modules.Monetization.MonetizationService)
local PlayerDataService = require(ServerScriptService.Server.Modules.PlayerData.PlayerDataService)
local DecorationsService = require(ServerScriptService.Server.Modules.Museums.DecorationsService)
local MutationsService = require(ServerScriptService.Server.Modules.Museums.MutationsService)
local BoostsService = require(ServerScriptService.Server.Modules.Progression.BoostsService)
local StatsService = require(ServerScriptService.Server.Modules.Progression.StatsService)
local ItemService = require(ServerScriptService.Server.Modules.Museums.ItemService)
local UpdateDecorationColorsBindableEvent = ServerScriptService.Server.Bindables.UpdateDecorationColors
local GetPlotBindableFunction = ServerScriptService.Server.Bindables.GetPlot
local DecorationAssetsFolder = ServerStorage.Assets.Decorations
local PedestalAssetsFolder = ServerStorage.Assets.Pedestals
local ItemAssetsFolder = ServerStorage.Assets.Items

local ItemPedestalStatusUI = ReplicatedStorage.UI.BillboardGUI.ItemPedestalStatusUI
local NotificationUtil = require(ReplicatedStorage.Modules.Utils.NotificationUtil)
local PlotUtil = require(ReplicatedStorage.Modules.Utils.PlotUtil)
local MathUtil = require(ReplicatedStorage.Modules.Utils.MathUtil)
local ObjectUtil = require(ReplicatedStorage.Modules.Utils.ObjectUtil)
local ItemsData = require(ReplicatedStorage.Modules.Data.Items)
local DecorationsData = require(ReplicatedStorage.Modules.Data.Decorations)
local MutationsData = require(ReplicatedStorage.Modules.Data.Mutations)
local RaritiesData = require(ReplicatedStorage.Modules.Data.Rarities)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Network = require(ReplicatedStorage.Packages.Network)
local PromptOfflineEarningsEvent = Network:RemoteEvent("PromptOfflineEarnings")
local CloseOfflineEarningsModalEvent = Network:RemoteEvent("CloseOfflineEarningsModal")
local ClaimOfflineEarningsEvent = Network:RemoteEvent("ClaimOfflineEarnings")
local PlayerEarnedMoneyEvent = Network:RemoteEvent("PlayerEarnedMoney")
local CollectEarningsEvent = Network:RemoteEvent("CollectEarnings")
local CollectAllEarningsEvent = Network:RemoteFunction("CollectAllEarnings")
local PickUpItemEvent = Network:RemoteEvent("PickUpItem")
local StealItemEvent = Network:RemoteEvent("StealItem")
local PlaceItemEvent = Network:RemoteFunction("PlaceItem")
local ItemPlacedEvent = Network:RemoteEvent("ItemPlaced")

local STEALING_COOLDOWN = 420
local MAX_PLACEMENT_HEIGHT = 3.5
local GROUP_ID = 15600357
local CLAIM_5X_PRODUCT_ID = 3535022560
local STEAL_PRODUCT_IDS = {
	3507021712,
	3528634978,
	3528635318,
	3528635512,
	3528635676,
	3528636004
}

local MAX_ITEMS = {
	["Tier_1"] = 35,
	["Tier_2"] = 70,
	["Tier_3"] = 115,
	["Tier_4"] = 150,
	["Tier_5"] = 200,
	["Tier_6"] = 250,
	["Tier_7"] = 300,
	["Tier_8"] = 350,
	["Tier_9"] = 400,
	["Tier_10"] = 450,
}

type ObjectInfo = {
	InstanceId : string,
	Size : number,
	Id: number,
	MutationId : number,
	Earnings : number,
	PassiveEarnings : number,
	CFrame: { number },
	Decoration : boolean,
}

local ItemPlacementService = {}

local StealingPlayers = {}
local StealingCooldowns = {}
local PendingOfflineEarnings = {}

ItemPlacementService.PlacementChangedEvent = Signal.new()

local function convertToolToModel(target : Tool)
	local newModel = Instance.new("Model")
	local fakeItem = target:Clone()
	newModel:SetAttribute("Pedestal", target:GetAttribute("Pedestal")) -- copy dimensions
	newModel:SetAttribute("Rotation", target:GetAttribute("Rotation"))
	newModel:SetAttribute("XRotation", target:GetAttribute("XRotation"))
	for _, content in fakeItem:GetChildren() do
		if content:IsA("BasePart") then
			content.Anchored = true
			content.CanCollide = false
		end
		content.Parent = newModel
		if content.Name == "Handle" then
			newModel.PrimaryPart = content
		end
	end
	fakeItem:Destroy()

	local itemCostUI = newModel:FindFirstChildOfClass("BillboardGui")
	if itemCostUI then
		itemCostUI:Destroy()
	end

	local upperName = target:GetAttribute("UpperName")
	newModel.Name = upperName or target.Name

	return newModel
end

local function applyPedestal(toolModel : Model, grip : CFrame)
	local pedestalDimensions = toolModel:GetAttribute("Pedestal") or "2x2"
	local toolRotationY = toolModel:GetAttribute("Rotation") or 0
	local toolRotationX = toolModel:GetAttribute("XRotation") or 0
	
	local newPedestal = PedestalAssetsFolder:FindFirstChild(pedestalDimensions):Clone()
	local gripRotation = grip - grip.Position

	local pedestalPlate : BasePart = newPedestal.Plate
	local pedestalAttachment : Attachment = pedestalPlate:FindFirstChildOfClass("Attachment")
	
	local primary = toolModel.PrimaryPart

	toolModel.Parent = newPedestal
	toolModel.PrimaryPart = nil
	
	local facingCFrame = CFrame.lookAt(
		pedestalAttachment.WorldCFrame.Position,
		pedestalAttachment.WorldCFrame.Position + pedestalAttachment.WorldAxis
	) * CFrame.Angles(math.rad(toolRotationX), math.rad(toolRotationY), 0)
	
	toolModel:PivotTo(facingCFrame * gripRotation:Inverse())
	
	local cf, size = ObjectUtil.GetBoundingBox(toolModel) -- calculating bounding box after rotation

	toolModel.PrimaryPart = primary
	toolModel:PivotTo(toolModel:GetPivot() + Vector3.new(0,size.Y/2,0))
	
	newPedestal.Name = toolModel.Name
	
	return newPedestal
end

function ItemPlacementService.Serialize(profile : typeof(PlayerDataService.GetProfile()), buildRegionModel : Model, objectsFolder : Folder)
	local data : {ObjectInfo} = {}
	for _, object : Model in objectsFolder:GetChildren() do
		if not object:IsA("Model") then continue end

		local instanceId = object:GetAttribute("InstanceId")
		local objectCF : CFrame = buildRegionModel:GetPivot():ToObjectSpace(object:GetPivot())

		local instanceExists = false
		for index, currentObjectInfo : ObjectInfo in profile.Data.PlacedObjects do
			if currentObjectInfo.InstanceId == instanceId then

				profile.Data.PlacedObjects[index].CFrame = table.pack(objectCF:GetComponents())
				if not currentObjectInfo.Decoration then
					profile.Data.PlacedObjects[index].Earnings = object:GetAttribute("Earnings") or 0
					profile.Data.PlacedObjects[index].PassiveEarnings = object:GetAttribute("PassiveEarnings") or 0
				end
				
				instanceExists = true

				table.insert(data, currentObjectInfo)

				break
			end
		end

		if not instanceExists then
			local info : ObjectInfo = {
				InstanceId = instanceId,
				Id = object:GetAttribute("Id"),
				Size = object:GetAttribute("Size"),
				Earnings = object:GetAttribute("Earnings") or 0,
				PassiveEarnings = object:GetAttribute("PassiveEarnings") or 0,
				MutationId = object:GetAttribute("MutationId") or nil,
				CFrame = table.pack(objectCF:GetComponents()),
				Decoration = object:GetAttribute("Decoration")
			}

			table.insert(data, info)
		end
	end

	return data
end

function ItemPlacementService.Save(player : Player, buildRegionModel : Model, objectsFolder : Folder)
	local profile = PlayerDataService.GetProfile(player)
	local serializedData = ItemPlacementService.Serialize(profile, buildRegionModel, objectsFolder)

	if not serializedData then return false end

	profile.Data.PlacedObjects = serializedData
	ItemPlacementService.PlacementChangedEvent:Fire()

	print("Successfully saved "..player.Name.."'s object configuration.")

	return true
end

function ItemPlacementService.CreateItem(owner : Player, itemModel : Model, objectCF : CFrame, props : ObjectInfo)
	local newOwnerValue = Instance.new("ObjectValue")
	newOwnerValue.Parent = itemModel
	newOwnerValue.Name = "OWNER"
	newOwnerValue.Value = owner

	local instanceId = props.InstanceId or HttpService:GenerateGUID()
	itemModel:SetAttribute("InstanceId", instanceId)
	itemModel:SetAttribute("MutationId", props.MutationId)
	itemModel:SetAttribute("Id", props.Id)
	itemModel:SetAttribute("PlacedItem", true)
	itemModel:SetAttribute("Decoration", props.Decoration)
	itemModel:SetAttribute("Size", props.Size)
	
	if props.MutationId then
		MutationsService.RemoveMutation(itemModel:FindFirstChildOfClass("Model")) -- remove potential copies
		MutationsService.ApplyMutation(itemModel:FindFirstChildOfClass("Model"), props.MutationId)
	end

	for key, value in props do
		if typeof(value) == "Instance" then continue end
		itemModel:SetAttribute(key, value)
	end
	
	if not props.Decoration then
		local viewersFolder = Instance.new("Folder")
		viewersFolder.Parent = itemModel
		viewersFolder.Name = "Viewers"
		
		local data = ItemsData.GetDataById(props.Id)
		local moneyPerSecond, passiveIncome = ItemsData.GetCost(props.Id, props.Size, props.MutationId)
		
		if data.Rarity.Exclusive then
			itemModel:SetAttribute("Percentage", moneyPerSecond)
			itemModel:SetAttribute("Exclusive", true)
		else
			itemModel:SetAttribute("MoneyPerSecond", moneyPerSecond)
			itemModel:SetAttribute("PassiveIncome", passiveIncome)
			itemModel:SetAttribute("MaxViewers", data.MaxViewers)
		end
		
		local newStatusUI = ItemPedestalStatusUI:Clone()
		newStatusUI.Parent = itemModel
		newStatusUI.Adornee = itemModel
		if data.Rarity.Exclusive then
			newStatusUI.MoneyPerSecond.Text = moneyPerSecond.."%"
			newStatusUI.PassiveIncome.Text = "of best item"
		else
			newStatusUI.MoneyPerSecond.Text = "$"..MathUtil.FormatNumber(moneyPerSecond).." / s"
			newStatusUI.PassiveIncome.Text = "passive: $"..MathUtil.FormatNumber(passiveIncome).." / s"
		end
		newStatusUI.Earnings.Value.Text = "$"..MathUtil.FormatNumber(props.Earnings)
		newStatusUI.ItemName.Text = string.lower(data.Name).." ("..props.Size.."x)"
		if props.MutationId then
			local mutationData = MutationsData.GetDataById(props.MutationId)
			newStatusUI.MutationName.Text = string.lower(mutationData.Name)
			MutationsData.SetColor(newStatusUI.MutationName, props.MutationId)
			newStatusUI.MutationName.Visible = true
		end
		RaritiesData.SetColor(newStatusUI.ItemName, data.Rarity.Name)
		newStatusUI.AlwaysOnTop = true
		newStatusUI.StudsOffset = Vector3.new(0, 4, 0)
		newStatusUI.Enabled = false
		
		itemModel.AttributeChanged:Connect(function()
			local visitorEarnings = itemModel:GetAttribute("Earnings")
			local passiveEarnings = itemModel:GetAttribute("PassiveEarnings") or 0
			if visitorEarnings and passiveEarnings and newStatusUI:FindFirstChild("Earnings") then
				newStatusUI.Earnings.Value.Text = "$"..MathUtil.FormatNumber(visitorEarnings + passiveEarnings)
			end
		end)
	else
		local data = DecorationsData.GetDataById(props.Id)
		itemModel:SetAttribute("Attraction", data.Attraction)
	end
	
	itemModel.Parent = props.Parent
	itemModel:PivotTo(objectCF)

	CollectionService:AddTag(itemModel, "ItemTooltip")
	for _, part : BasePart in itemModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = part:GetAttribute("Interactive") 
				and "MuseumItem_Interactive" or "MuseumItem"
		end
	end

	return itemModel
end

function ItemPlacementService.Load(player : Player, buildRegionModel : Model, objectsFolder : Folder)
	local profile = PlayerDataService.GetProfile(player)
	local serializedObjectData = profile.Data.PlacedObjects
	
	for index, objectInfo : ObjectInfo in serializedObjectData do
		local newModel : Model = nil

		local relativeCF : CFrame = CFrame.new(table.unpack(objectInfo.CFrame))
		local objectCF : CFrame = buildRegionModel:GetPivot():ToWorldSpace(relativeCF)
		
		if objectInfo.Decoration then
			local data = DecorationsData.GetDataById(objectInfo.Id)
			local decorationAsset = DecorationAssetsFolder:FindFirstChild(data.Name)
			
			if not decorationAsset then continue end
			
			newModel = decorationAsset:Clone()
		else
			local data = ItemsData.GetDataById(objectInfo.Id)
			local itemTool : Tool = ItemAssetsFolder:FindFirstChild(data.Name)

			if not itemTool then continue end

			newModel = convertToolToModel(itemTool)
			newModel.Name = itemTool.Name
			newModel:ScaleTo(objectInfo.Size)
			newModel = applyPedestal(newModel, itemTool.Grip)
		end
		
		ItemPlacementService.CreateItem(player, newModel, objectCF, {
			Parent = objectsFolder,
			InstanceId = objectInfo.InstanceId,
			MutationId = objectInfo.MutationId,
			Id = objectInfo.Id,
			Size = objectInfo.Size,
			Earnings = objectInfo.Earnings or 0,
			PassiveEarnings = objectInfo.PassiveEarnings or 0,
			Decoration = objectInfo.Decoration
		})
	end

	UpdateDecorationColorsBindableEvent:Fire(player)
	ItemPlacementService.PlacementChangedEvent:Fire()
end

function ItemPlacementService.Unload(currentObjectsFolder : Folder)
	for _, object : Model in currentObjectsFolder:GetChildren() do
		if object:IsA("Model") then 
			object:Destroy()
		end
	end
end

function ItemPlacementService.PlaceDecoration(
	player : Player, 
	decorationAsset : Model, 
	decorationId : string,
	objectCF : CFrame, 
	buildRegionModel : Model, 
	itemsFolder : Folder, 
	successFunc
)
	local profile = PlayerDataService.GetProfile(player)
	if not profile then return end
	
	local index = table.find(profile.Data.Decorations, decorationId)
	if not index then return end
	
	local decorationData = DecorationsData.GetDataById(decorationId)
	
	local newAsset = decorationAsset:Clone()
	local newObject = ItemPlacementService.CreateItem(player, newAsset, objectCF, {
		Parent = itemsFolder,
		Id = decorationId,
		Decoration = true,
	})
	
	if decorationAsset:GetAttribute("HasBeam") then
		task.spawn(function()
			for _, item : Model in itemsFolder:GetChildren() do
				if item:IsA("Model") and item:GetAttribute("HasBeam") then
					local beam : Beam = item:FindFirstChildOfClass("Beam")
					if beam then

						local oldBeam = beam:Clone()
						beam:Destroy()

						task.delay(.1, function()
							oldBeam.Parent = item
						end)

					end
				end
			end
		end)
	end

	local success = ItemPlacementService.Save(player, buildRegionModel, itemsFolder)
	if success then
		table.remove(profile.Data.Decorations, index)
		if successFunc then task.spawn(successFunc) end

		UpdateDecorationColorsBindableEvent:Fire(player)
		
		local rebirthAvailable = CanRebirthBindableFunction:Invoke(player)
		player:SetAttribute("RebirthAvailable", rebirthAvailable)
		
		NotificationUtil.newTextNotification(
			player,
			`you placed {string.lower(decorationData.Name)} in your museum!`,
			nil,
			{
				Sound = "Ping"
			}
		)

		return true
	else
		newObject:Destroy()
		NotificationUtil.newTextNotification(
			player,
			"failed to save item to museum, try to place again.",
			Color3.fromRGB(255,0,0),
			{
				Sound = "Error"
			}
		)
	end
end

function ItemPlacementService.PlaceItem(
	player : Player, 
	pedestal : Model, 
	instanceId : string,
	objectCF : CFrame, 
	buildRegionModel : Model, 
	itemsFolder : Folder, 
	successFunc
)
	local profile = PlayerDataService.GetProfile(player)
	if not profile then return end
	
	local function ownsItem()
		for index, item in profile.Data.Backpack do
			if item.InstanceId == instanceId then
				return index
			end
		end
	end
	
	local itemIndex = ownsItem()
	if not itemIndex then return end
	
	local item = profile.Data.Backpack[itemIndex]
	local itemData = ItemsData.GetDataById(item.Id)
	local newObject = ItemPlacementService.CreateItem(player, pedestal, objectCF, {
		Parent = itemsFolder,
		Id = item.Id,
		InstanceId = item.InstanceId,
		MutationId = item.MutationId,
		Size = item.Size,
		PassiveEarnings = 0,
		Earnings = 0,
	})

	local success = ItemPlacementService.Save(player, buildRegionModel, itemsFolder)
	if success then
		table.remove(profile.Data.Backpack, itemIndex)
		
		local rebirthAvailable = CanRebirthBindableFunction:Invoke(player)
		player:SetAttribute("RebirthAvailable", rebirthAvailable)
		
		if successFunc then task.spawn(successFunc) end
		
		ItemPlacedEvent:FireClient(player)
		NotificationUtil.newTextNotification(
			player,
			`you placed {string.lower(itemData.Name)} in your museum!`,
			nil,
			{
				Sound = "Ping"
			}
		)
		
		return true
	else
		newObject:Destroy()
		NotificationUtil.newTextNotification(
			player,
			"failed to save item to museum, try to place again.",
			Color3.fromRGB(255,0,0),
			{
				Sound = "Error"
			}
		)
	end
end

function ItemPlacementService.CollectItem(player : Player, instanceId : string, itemsFolder : Folder, keepEarnings : boolean?, collectAll : boolean?)
	local profile = PlayerDataService.GetProfile(player)
	if not profile then return end
	
	local friendBoost = player:GetAttribute("FriendBoost")
	local isVIP = MonetizationService.OwnsGamepassByName(player, "VIP", true)
	
	for _, object : Model in itemsFolder:GetChildren() do
		local itemInstanceId = object:GetAttribute("InstanceId")
		if itemInstanceId == instanceId then
			local visitorEarnings = object:GetAttribute("Earnings") or 0
			local passiveEarnings = object:GetAttribute("PassiveEarnings") or 0
			
			local totalEarnings = math.floor((visitorEarnings + passiveEarnings) * friendBoost)
			if isVIP then totalEarnings = totalEarnings * 2 end
			if profile.Data.ClaimedGroupTotem then 
				totalEarnings = math.ceil(totalEarnings * 1.2)
			end
			
			if totalEarnings <= 0 then return end
			
			if not collectAll then
				PlayerEarnedMoneyEvent:FireClient(player, object.PrimaryPart.Position, totalEarnings)
			end
			PlayerDataService.UpdateProfileData(player, "Money", function(old)
				return old + totalEarnings
			end)
			
			if not collectAll then
				NotificationUtil.newTextNotification(
					player,
					"collected +$"..MathUtil.FormatNumber(totalEarnings),
					Color3.fromRGB(0,255,0),
					{
						Sound = "ItemCollectEarnings"
					}
				)
			end
			
			if not keepEarnings then
				object:SetAttribute("Earnings", 0)
				object:SetAttribute("PassiveEarnings", 0)
			end
			
			return totalEarnings
		end
	end
end

function ItemPlacementService.PickUpItem(player : Player, instanceId : string, buildRegionModel : Model, itemsFolder : Folder, delete : boolean?)
	local character = player.Character
	local humanoid : Humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local pickedUpObjectName = nil
	local pickedUpObjectPosition = nil
	for _, object : Model in itemsFolder:GetChildren() do
		local itemId, itemSize = object:GetAttribute("Id"), object:GetAttribute("Size")
		local itemInstanceId = object:GetAttribute("InstanceId")
		local mutationId = object:GetAttribute("MutationId")
		
		local data = object:GetAttribute("Decoration") 
			and DecorationsData.GetDataById(itemId) or ItemsData.GetDataById(itemId)

		if itemInstanceId == instanceId then

			if not delete then
				local newItem : Tool = nil
				if object:GetAttribute("Decoration") then
					newItem = DecorationsService.CreateDecoration(player, itemId, {
						SaveToBackpack = true,
						Parent = player.Backpack,
					})
				else
					newItem = ItemService.CreateItem(player, itemId, itemSize, {
						SaveToBackpack = true,
						ItemInstanceId = itemInstanceId,
						MutationId = mutationId,
						Parent = player.Backpack,
					})
				end
				
				if not newItem then
					return
				end
			end
			
			local visitorEarnings = object:GetAttribute("Earnings") or 0
			local passiveEarnings = object:GetAttribute("PassiveEarnings") or 0
			if visitorEarnings + passiveEarnings > 0 then
				ItemPlacementService.CollectItem(player, instanceId, itemsFolder, true)
			end

			pickedUpObjectName = data.Name
			pickedUpObjectPosition = object:GetPivot().Position

			object:Destroy()

			break

		end
	end

	local success = ItemPlacementService.Save(player, buildRegionModel, itemsFolder)
	if success and pickedUpObjectName then
		if not delete then
			NotificationUtil.newTextNotification(
				player,
				`you picked up your {string.lower(pickedUpObjectName)} from your museum!`,
				nil,
				{
					Sound = "Delete"
				}
			)
		end
		
		return success, pickedUpObjectName, pickedUpObjectPosition
	end
end

function ItemPlacementService.CalculateOfflineEarnings(player : Player, itemsFolder : Folder, offlineTime : number)
	offlineTime = offlineTime or 0
	
	local offlineEarnings = 0
	for _, object : Model in itemsFolder:GetChildren() do
		if object:GetAttribute("Decoration") then continue end
		
		local itemId, itemSize = object:GetAttribute("Id"), object:GetAttribute("Size")
		local mutationId = object:GetAttribute("MutationId")

		local data = ItemsData.GetDataById(itemId)
		local passiveIncome = object:GetAttribute("PassiveIncome") or 0
		
		offlineEarnings += math.floor(passiveIncome * offlineTime)
	end
	
	return offlineEarnings
end

function ItemPlacementService.PromptOfflineEarnings(player : Player)
	local timeSpentOffline = player:GetAttribute("TimeSpentOffline") or 0
	if timeSpentOffline <= 10 then return end
	
	local plotModel = GetPlotBindableFunction:Invoke(player)
	local itemsFolder : Folder = plotModel.Essentials.Items
	
	local offlineEarnings = ItemPlacementService.CalculateOfflineEarnings(player, itemsFolder, timeSpentOffline)
	if offlineEarnings <= 0 then return end
	
	PendingOfflineEarnings[player] = offlineEarnings
	PromptOfflineEarningsEvent:FireClient(player, offlineEarnings)
end

function ItemPlacementService.ClaimOfflineEarnings(player : Player, claimMore : boolean, processedPayment : boolean)
	if not PendingOfflineEarnings[player] then return end

	local profile = PlayerDataService.GetProfile(player)
	if not profile then return end
	
	if claimMore and not processedPayment then
		MonetizationService.PromptPlayer(player, CLAIM_5X_PRODUCT_ID)
		return
	end
	
	local offlineEarnings = PendingOfflineEarnings[player] or 0
	if claimMore then offlineEarnings = math.floor(offlineEarnings * 5) end
	
	PlayerDataService.UpdateProfileData(player, "Money", function(old)
		return old + offlineEarnings
	end)
	NotificationUtil.newTextNotification(
		player,
		"collected +$"..MathUtil.FormatNumber(offlineEarnings),
		Color3.fromRGB(0,255,0),
		{
			Sound = "ItemCollectEarnings"
		}
	)
	
	CloseOfflineEarningsModalEvent:FireClient(player)
	PendingOfflineEarnings[player] = nil
end

function ItemPlacementService.CollectAll(player : Player, collectAnywhere : boolean)
	if collectAnywhere and not MonetizationService.OwnsGamepassByName(player, "Collect Anywhere") then
		return false
	end

	local friendBoost = player:GetAttribute("FriendBoost")
	if not friendBoost then friendBoost = 1 end

	local plotModel = GetPlotBindableFunction:Invoke(player)

	local itemsFolder : Folder = plotModel.Essentials.Items
	local collectAllButton : Model = plotModel.Essentials.Interior.CollectAllButton

	if not itemsFolder then return end

	local totalEarnings = 0
	for _, item : Model in itemsFolder:GetChildren() do
		if not item:GetAttribute("PlacedItem") then continue end
		if item:GetAttribute("Decoration") then continue end

		local itemInstanceId = item:GetAttribute("InstanceId")
		local earnings = ItemPlacementService.CollectItem(player, itemInstanceId, itemsFolder, false, true)

		if not earnings then earnings = 0 end

		totalEarnings = totalEarnings + earnings
	end

	if totalEarnings > 0 then
		PlayerEarnedMoneyEvent:FireClient(player, collectAllButton.PrimaryPart.Position, totalEarnings)
		NotificationUtil.newTextNotification(
			player,
			"collected +$"..MathUtil.FormatNumber(totalEarnings),
			Color3.fromRGB(0,255,0),
			{
				Sound = "ItemCollectEarnings"
			}
		)
	end

	return true
end

function ItemPlacementService.Start()
	local function snapCFrameY(cf: CFrame)
		local _, y, _ = cf:ToOrientation()
		local snappedY = math.rad(
			math.round(math.deg(y) / 90) * 90
		)
		return CFrame.new(cf.Position) * CFrame.Angles(0, snappedY, 0)
	end
	
	local function onItemPlaceRequest(player : Player, objectCF : CFrame, rotation : number)
		if typeof(objectCF) ~= "CFrame" then return end
		if typeof(rotation) ~= "number" then rotation = 0 end
		objectCF = snapCFrameY(objectCF)

		if not player.Character then return end

		local plotModel = GetPlotBindableFunction:Invoke(player)
		local buildRegionModel : Model = plotModel.Essentials.BuildRegion
		local itemsFolder : Folder = plotModel.Essentials.Items
		local interiorFolder : Folder = plotModel.Essentials.Interior
		
		local plotTier = StatsService.GetStat(player, "Plot Tier")
		if not plotTier then return end
		
		local function getItemCount()
			local count = 0
			for _, itemModel in itemsFolder:GetChildren() do
				if not itemModel:GetAttribute("Decoration") then
					count = count + 1
				end
			end
			return count
		end
		
		if not buildRegionModel or not itemsFolder then return end
		
		
		local holdingTool : Tool = player.Character:FindFirstChildOfClass("Tool")
		if holdingTool and holdingTool:IsA("Tool") and (holdingTool:GetAttribute("Item") or holdingTool:GetAttribute("Decoration")) then
			if (not holdingTool:GetAttribute("Decoration")) 
				and getItemCount() >= MAX_ITEMS["Tier_"..plotTier] then
				
				NotificationUtil.newTextNotification(
					player,
					`too many items for your museum size! (max is {MAX_ITEMS["Tier_"..plotTier]} items)`,
					Color3.fromRGB(255, 0, 0),
					{
						Sound = "Error"
					}
				)
				
				return
			end
			
			local model : Model = nil
			if holdingTool:GetAttribute("Item") then
				local grip = holdingTool.Grip
				model = convertToolToModel(holdingTool)
				model = applyPedestal(model, grip)
			else
				local decorationId = holdingTool:GetAttribute("Id")
				local decorationData = DecorationsData.GetDataById(decorationId)
				model = DecorationAssetsFolder:FindFirstChild(decorationData.Name)
			end
			
			if holdingTool:GetAttribute("Item") then
				local sizeX, sizeZ = model:GetAttribute("X") or 1, model:GetAttribute("Z") or 1
				if not PlotUtil.IsGridAligned(buildRegionModel, objectCF.Position, rotation, sizeX, sizeZ) then
					return false
				end
			end
			
			local objectSize = model.BoundingBox.Size
			if not PlotUtil.WithinBounds(buildRegionModel, objectSize, objectCF) then
				return false
			end
			if not PlotUtil.NotIntersectingObjects(buildRegionModel, itemsFolder, interiorFolder, objectSize, objectCF) then
				return false
			end
			
			if holdingTool:GetAttribute("Item") then
				local instanceId = holdingTool:GetAttribute("InstanceId")
				return ItemPlacementService.PlaceItem(player, model, instanceId, objectCF, buildRegionModel, itemsFolder, function()
					if holdingTool then holdingTool:Destroy() end
				end)
			else
				local decorationId = holdingTool:GetAttribute("Id")
				return ItemPlacementService.PlaceDecoration(player, model, decorationId, objectCF, buildRegionModel, itemsFolder, function()
					local newCount = holdingTool:GetAttribute("Count") - 1
					holdingTool:SetAttribute("Count", newCount)
				end)
			end
		end
		
		return false
	end
	
	local function onItemPickUpRequest(player : Player, instanceId : string)
		if not instanceId or typeof(instanceId) ~= "string" then return end
		if not player.Character then return end

		local plotModel = GetPlotBindableFunction:Invoke(player)
		local buildRegionModel : Model = plotModel.Essentials.BuildRegion
		local itemsFolder : Folder = plotModel.Essentials.Items
		
		if not buildRegionModel or not itemsFolder then return end

		ItemPlacementService.PickUpItem(player, instanceId, buildRegionModel, itemsFolder)
		
		local rebirthAvailable = CanRebirthBindableFunction:Invoke(player)
		player:SetAttribute("RebirthAvailable", rebirthAvailable)
	end
	
	local function onStealRequest(player : Player, victim : Player, instanceId : string)
		if typeof(victim) ~= "Instance" or not victim:IsA("Player") then return end
		if typeof(instanceId) ~= "string" then return end
		
		if StealingPlayers[player] then return end
		if StealingCooldowns[player] then
			local function formatTime(seconds : number) : string
				if seconds < 60 then
					return seconds.."s"
				end
				seconds = math.max(0, math.floor(seconds))

				local minutes = math.floor(seconds / 60)
				local secs = seconds % 60

				return string.format("%dm %ds", minutes, secs)
			end
			
			NotificationUtil.newTextNotification(
				player,
				`you can steal after: {formatTime(StealingCooldowns[player])}`,
				Color3.fromRGB(255, 0, 0),
				{
					Sound = "Error"
				}
			)
			return
		end
		StealingCooldowns[player] = STEALING_COOLDOWN
		
		local plotModel = GetPlotBindableFunction:Invoke(victim)
		local itemsFolder : Folder = plotModel.Essentials.Items
		if not itemsFolder then return end
		
		for _, object : Model in itemsFolder:GetChildren() do
			local itemInstanceId = object:GetAttribute("InstanceId")
			if itemInstanceId == instanceId and not object:GetAttribute("Decoration") then
				local itemId, itemSize = object:GetAttribute("Id"), object:GetAttribute("Size")
				local mutationId = object:GetAttribute("MutationId")
				
				local itemData = ItemsData.GetDataById(itemId)
				local rarityData = itemData and itemData.Rarity
				if itemData and rarityData then
					local stealTier = rarityData.StealTier or 1
					if stealTier then
						
						local selectedProduct = STEAL_PRODUCT_IDS[stealTier] or STEAL_PRODUCT_IDS[1]
						MonetizationService.PromptPlayer(player, selectedProduct)
						StealingPlayers[player] = {
							Victim = victim, 
							InstanceId = instanceId,
							ItemId = itemId,
							ItemSize = itemSize,
							ItemName = object.Name,
							MutationId = mutationId
						}
						
					end
				end
			end
		end
	end
	
	local function onCollectItemRequest(player : Player, instanceId : string)
		if not instanceId or typeof(instanceId) ~= "string" then return end
		
		local plotModel = GetPlotBindableFunction:Invoke(player)
		local itemsFolder : Folder = plotModel.Essentials.Items
		if not itemsFolder then return end
		
		ItemPlacementService.CollectItem(player, instanceId, itemsFolder)
	end

	PhysicsService:RegisterCollisionGroup("MuseumItem")
	PhysicsService:RegisterCollisionGroup("MuseumItem_Interactive")
	task.delay(2, function()
		PhysicsService:CollisionGroupSetCollidable("MuseumItem", "PlayerCharacters", false)
		PhysicsService:CollisionGroupSetCollidable("MuseumItem", "Visitor", false)

		PhysicsService:CollisionGroupSetCollidable("MuseumItem_Interactive", "PlayerCharacters", true)
		PhysicsService:CollisionGroupSetCollidable("MuseumItem_Interactive", "Visitor", false)
	end)
	
	PlaceItemEvent.OnServerInvoke = onItemPlaceRequest
	PickUpItemEvent.OnServerEvent:Connect(onItemPickUpRequest)
	CollectEarningsEvent.OnServerEvent:Connect(onCollectItemRequest)
	CollectAllEarningsEvent.OnServerInvoke = ItemPlacementService.CollectAll
	StealItemEvent.OnServerEvent:Connect(onStealRequest)
	
	ClaimOfflineEarningsEvent.OnServerEvent:Connect(function(player : Player, claimMore : boolean)
		return ItemPlacementService.ClaimOfflineEarnings(player, claimMore)
	end)
	
	task.spawn(function()
		while task.wait(1) do
			for player, timeLeft in StealingCooldowns do
				StealingCooldowns[player] = timeLeft - 1
				if StealingCooldowns[player] <= 0 then
					StealingCooldowns[player] = nil
				end
			end
		end
	end)
	task.spawn(function()
		while task.wait(1) do
			for _, player : Player in Players:GetPlayers() do
				local plotModel = GetPlotBindableFunction:Invoke(player)
				if not plotModel then continue end
				
				local itemsFolder = plotModel.Essentials.Items
				if not itemsFolder then continue end
				
				for _, placedItem in itemsFolder:GetChildren() do
					if not placedItem:IsA("Model") then continue end
					if not placedItem:GetAttribute("PlacedItem") then continue end
					if placedItem:GetAttribute("Decoration") then continue end
					
					local viewersFolder = placedItem:FindFirstChild("Viewers")
					if viewersFolder and #viewersFolder:GetChildren() > 0 then continue end
					
					local passiveIncome = placedItem:GetAttribute("PassiveIncome") or 0
					local oldPassiveEarnings = placedItem:GetAttribute("PassiveEarnings") or 0
					placedItem:SetAttribute("PassiveEarnings", oldPassiveEarnings + passiveIncome)
					
					if placedItem:GetAttribute("BestItem") then
						for _, exclusiveItem in itemsFolder:GetChildren() do
							if not exclusiveItem:IsA("Model") then continue end
							if not exclusiveItem:GetAttribute("PlacedItem") then continue end
							if not exclusiveItem:GetAttribute("Exclusive") then continue end
							
							local addedIncome = math.ceil(passiveIncome * (exclusiveItem:GetAttribute("Percentage")/100))
							local oldEarnings = exclusiveItem:GetAttribute("Earnings")
							exclusiveItem:SetAttribute("Earnings", oldEarnings + addedIncome)
						end
					end
				end
			end
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId : number, productId : number, isPurchased : boolean?)
		local player : Player = Players:GetPlayerByUserId(userId)
		if not player then return end
		if not table.find(STEAL_PRODUCT_IDS, productId) then return end
		if not isPurchased then 
			StealingPlayers[player] = nil
			StealingCooldowns[player] = nil
		end
	end)
	MonetizationService.OnProductPurchase:Connect(function(player : Player, productId : number)
		if productId == CLAIM_5X_PRODUCT_ID then
			ItemPlacementService.ClaimOfflineEarnings(player, true, true)
			return
		end
		
		if not table.find(STEAL_PRODUCT_IDS, productId) then return end
		if not StealingPlayers[player] then return end
		
		local character = player.Character
		local humanoid : Humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		
		local victimName = StealingPlayers[player].Victim
		local itemId = StealingPlayers[player].ItemId
		local itemName = StealingPlayers[player].ItemName
		local itemSize = StealingPlayers[player].ItemSize
		local mutationId = StealingPlayers[player].MutationId
		
		local newItem : Tool = ItemService.CreateItem(player, itemId, itemSize, {
			SaveToBackpack = true,
			MutationId = mutationId,
		})

		if not newItem then
			return
		end

		humanoid:UnequipTools()
		newItem.Parent = character
		
		StealingPlayers[player] = nil
		NotificationUtil.newTextNotification(
			player,
			`you stole a {string.lower(itemName)} from {victimName}!`,
			Color3.fromRGB(255, 156, 0),
			{
				Sound = "Victory"
			}
		)
	end)
	
	Players.PlayerAdded:Connect(function(player : Player)
		local profile = PlayerDataService.GetProfile(player)
		if not profile then return end
		
		ItemPlacementService.PromptOfflineEarnings(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player : Player)
		StealingPlayers[player] = nil
		StealingCooldowns[player] = nil
		PendingOfflineEarnings[player] = nil
	end)
end

return ItemPlacementService
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local PlayerDataService = require(ServerScriptService.Server.Modules.PlayerData.PlayerDataService)
local MonetizationService = require(ServerScriptService.Server.Modules.Monetization.MonetizationService)
local BoxService = require(ServerScriptService.Server.Modules.Museums.BoxService)
local StatsService = require(ServerScriptService.Server.Modules.Progression.StatsService)
local RemoveOrderFromBoxSpawnerEvent = ServerScriptService.Server.Bindables.RemoveOrderFromBoxSpawner
local AddOrderToBoxSpawnerEvent = ServerScriptService.Server.Bindables.AddOrderToBoxSpawner
local T = require(ServerScriptService.Server.Modules.Museums.PlotTypes)

local BoxAreaDisplayUI = ReplicatedStorage.UI.SurfaceGUI.BoxAreaDisplayUI
local TutorialManager = require(ReplicatedStorage.Modules.Tutorial.TutorialManager)
local NotificationUtil = require(ReplicatedStorage.Modules.Utils.NotificationUtil)
local BoxesData = require(ReplicatedStorage.Modules.Data.Boxes)
local MathUtil = require(ReplicatedStorage.Modules.Utils.MathUtil)
local LuckUtil = require(ReplicatedStorage.Modules.Utils.LuckUtil)
local Network = require(ReplicatedStorage.Packages.Network)
local SpawnConveyorBoxEvent = Network:RemoteEvent("SpawnConveyorBox")
local DestroyConveyorBoxEvent = Network:RemoteEvent("DestroyConveyorBox")
local BuyBoxWithGemsEvent = Network:RemoteEvent("BuyBoxWithGems")
local BuyBoxEvent = Network:RemoteFunction("BuyBox")
local BoxBoughtEvent = Network:RemoteEvent("BoxBought")

local CONVEYOR_SPEED = 7
local CONVEYOR_SPAWN_RATE = 0.4

local BOX_COUNT_MIN_COLOR = Color3.fromRGB(0,255,0)
local BOX_COUNT_MAX_COLOR = Color3.fromRGB(255,0,0)

local PurchasingBoxRequests = {}
local BOX_PRODUCT_IDS = { -- tiers
	[1] = 3529456447,
	[2] = 3529456785,
	[3] = 3529457084,
	[4] = 3529462216
}

local BoxSpawnerService = {}
local BoxSpawners : {[Player] : T.BoxSpawner} = {}

function BoxSpawnerService.CreateBoxSpawner(plot : T.Plot)
	local newBoxSpawner : T.BoxSpawner = {}
	
	newBoxSpawner.Plot = plot
	newBoxSpawner.Model = plot.Model
	newBoxSpawner.Owner = plot.Owner
	
	newBoxSpawner.BoxAreaDisplayUI = BoxAreaDisplayUI:Clone()
	newBoxSpawner.BoxAreaDisplayUI.Parent = plot.Model.Essentials.BoxArea.Area
	newBoxSpawner.BoxAreaDisplayUI.Adornee = plot.Model.Essentials.BoxArea.Area
	
	newBoxSpawner.Connections = {}
	newBoxSpawner.CurrentBoxes = {}
	
	newBoxSpawner.CurrentOrders = {}
	
	newBoxSpawner.BoxLimit = StatsService.GetStat(plot.Owner, "Box Limit") or 10
	newBoxSpawner.ConveyorLuck = StatsService.GetStat(plot.Owner, "Conveyor Luck") or 0
	
	BoxSpawnerService.SpawnBoxes(newBoxSpawner)
	BoxSpawnerService.AdjustConveyorBeam(newBoxSpawner)
	BoxSpawnerService.UpdateUI(newBoxSpawner)
	
	BoxSpawners[plot.Owner] = newBoxSpawner
	table.insert(newBoxSpawner.Connections, RunService.Heartbeat:Connect(function(deltaTime)
		for index, box in newBoxSpawner.CurrentBoxes do
			box.ExpirationTime = box.ExpirationTime - deltaTime
			if box.ExpirationTime <= 0 then
				table.remove(newBoxSpawner.CurrentBoxes, index)
				break
			end
		end
	end))
	
	return newBoxSpawner
end

function BoxSpawnerService.AdjustConveyorBeam(boxSpawner : T.BoxSpawner)
	local conveyorPart = boxSpawner.Model.Essentials.Conveyor
	local beam : Beam = conveyorPart.Beam
	
	beam.TextureSpeed = CONVEYOR_SPEED / beam.TextureLength
end

function BoxSpawnerService.UpdateUI(boxSpawner : T.BoxSpawner)
	local orderCount = #boxSpawner.CurrentOrders
	boxSpawner.BoxAreaDisplayUI.Container.Value.Text = `{orderCount} / {boxSpawner.BoxLimit}`
	boxSpawner.BoxAreaDisplayUI.Container.Value.TextColor3 =
		BOX_COUNT_MIN_COLOR:Lerp(BOX_COUNT_MAX_COLOR, orderCount / boxSpawner.BoxLimit)
end

function BoxSpawnerService.BuyConveyorBox(boxSpawner : T.BoxSpawner, boxInstanceId : string)
	local profile = PlayerDataService.GetProfile(boxSpawner.Owner)
	if not profile then return end
	
	if TutorialManager.IsPlayingTutorial(boxSpawner.Owner) 
		and #boxSpawner.CurrentOrders >= 1 then
		return
	end
	
	for index, currentBox in boxSpawner.CurrentBoxes do
		if currentBox.InstanceId == boxInstanceId then
			local selectedBoxName = currentBox.BoxName
			local selectedBoxData = BoxesData.Data[selectedBoxName]
			
			if profile.Data.Money < selectedBoxData.Cost then
				NotificationUtil.newTextNotification(
					boxSpawner.Owner,
					`you need more money to buy {string.lower(selectedBoxName)}!`,
					Color3.fromRGB(255,0,0),
					{
						Sound = "Error"
					}
				)
				
				local purchaseTier = selectedBoxData.RobuxTier or 1
				local purchaseProductId = BOX_PRODUCT_IDS[purchaseTier]
				if purchaseProductId and not PurchasingBoxRequests[boxSpawner.Owner] then
					MonetizationService.PromptPlayer(boxSpawner.Owner, purchaseProductId)
					PurchasingBoxRequests[boxSpawner.Owner] = {
						Tier = purchaseTier,
						BoxId = selectedBoxData.Id,
						BoxInstanceId = boxInstanceId
					}
				end
				
				return false
			end
			
			if #boxSpawner.CurrentOrders >= boxSpawner.BoxLimit then
				NotificationUtil.newTextNotification(
					boxSpawner.Owner,
					`too many boxes!`,
					Color3.fromRGB(255,0,0),
					{
						Sound = "Error"
					}
				)
				return false
			end
			
			PlayerDataService.UpdateProfileData(boxSpawner.Owner, "Money", function(old)
				return old - selectedBoxData.Cost
			end)
			
			NotificationUtil.newTextNotification(
				boxSpawner.Owner,
				`you bought a {string.lower(selectedBoxName)} for ${MathUtil.FormatNumber(selectedBoxData.Cost)}!`,
				nil,
				{
					Sound = "Purchase"
				}
			)
			
			local order = BoxService.GiveBox(boxSpawner.Owner, selectedBoxData.Id)
			DestroyConveyorBoxEvent:FireAllClients(boxInstanceId)
			BoxBoughtEvent:FireClient(boxSpawner.Owner)
			
			table.insert(boxSpawner.CurrentOrders, order)
			table.remove(boxSpawner.CurrentBoxes, index)
			
			BoxSpawnerService.UpdateUI(boxSpawner)
			
			return true
		end
	end
end

function BoxSpawnerService.CreateConveyorBox(boxSpawner : T.BoxSpawner)
	local selectedBoxName = LuckUtil.Roll(BoxesData.Data, boxSpawner.ConveyorLuck or 0)
	local selectedBoxData = BoxesData.Data[selectedBoxName]
	
	if not selectedBoxData then return end
	
	local newInstanceId = HttpService:GenerateGUID()
	
	local spawnPosition : Vector3 = boxSpawner.Model.Essentials.BoxSpawnerPart.Attachment.WorldPosition
	local removePosition : Vector3 = boxSpawner.Model.Essentials.BoxRemoverPart.Attachment.WorldPosition
	
	local distance = (spawnPosition - removePosition).Magnitude
	local expirationTime = distance / CONVEYOR_SPEED
	
	table.insert(boxSpawner.CurrentBoxes, {
		InstanceId = newInstanceId,
		BoxName = selectedBoxName,
		ExpirationTime = expirationTime + 1
	})
	
	SpawnConveyorBoxEvent:FireAllClients(
		boxSpawner.Owner, 
		boxSpawner.Model, 
		newInstanceId,
		expirationTime,
		selectedBoxName
	)
end

function BoxSpawnerService.SpawnBoxes(boxSpawner : T.BoxSpawner)
	local timeElapsed = 0
	local function update(deltaTime)
		timeElapsed = timeElapsed + deltaTime
		if timeElapsed >= 1 / CONVEYOR_SPAWN_RATE then
			timeElapsed = 0
			
			local newBoxModel = BoxSpawnerService.CreateConveyorBox(boxSpawner)
			table.insert(boxSpawner.CurrentBoxes, newBoxModel)
		end
	end
	
	table.insert(boxSpawner.Connections, RunService.Heartbeat:Connect(update))
end

function BoxSpawnerService.Destroy(boxSpawner : T.BoxSpawner)
	for _, connection in boxSpawner.Connections do
		connection:Disconnect()
		connection = nil
	end
	
	BoxSpawners[boxSpawner.Owner] = nil
	
	table.freeze(boxSpawner)
	boxSpawner = nil
end

function BoxSpawnerService.Start()
	local function onBuyWithGemsRequest(player : Player, boxId : number)
		if typeof(boxId) ~= "number" then return end
		if not BoxSpawners[player] then return end
		
		local boxData = BoxesData.GetDataById(boxId)
		local existingSpawner = BoxSpawners[player]
		
		if not boxData then return end
		
		local profile = PlayerDataService.GetProfile(player)
		if not profile then return end

		if #existingSpawner.CurrentOrders >= existingSpawner.BoxLimit then
			NotificationUtil.newTextNotification(
				player,
				`too many boxes!`,
				Color3.fromRGB(255,0,0),
				{
					Sound = "Error"
				}
			)
			return false
		end
		
		if profile.Data.Gems < boxData.GemCost then
			NotificationUtil.newTextNotification(
				player,
				`you need more gems to buy {string.lower(boxData.Name)}!`,
				Color3.fromRGB(255,0,0),
				{
					Sound = "Error"
				}
			)
			return false
		end

		PlayerDataService.UpdateProfileData(player, "Gems", function(old)
			return old - boxData.GemCost
		end)

		NotificationUtil.newTextNotification(
			player,
			`you bought a {string.lower(boxData.Name)} for ${boxData.GemCost}!`,
			nil,
			{
				Sound = "Purchase"
			}
		)
		
		local order = BoxService.GiveBox(player, boxId)
		table.insert(existingSpawner.CurrentOrders, order)
	end
	
	local function onBuyRequest(player : Player, boxInstanceId : string)
		if typeof(boxInstanceId) ~= "string" then return end
		if not BoxSpawners[player] then return end
		
		local existingSpawner = BoxSpawners[player]
		local transactionSuccess = false
		for _, currentBox in BoxSpawners[player].CurrentBoxes do
			if currentBox.InstanceId == boxInstanceId then
				transactionSuccess = BoxSpawnerService.BuyConveyorBox(existingSpawner, boxInstanceId)
				break
			end
		end
		
		return transactionSuccess
	end
	
	local function onAddOrderRequest(player : Player, order : T.Order)
		local boxSpawner = BoxSpawners[player]
		if not boxSpawner then return end
		
		table.insert(boxSpawner.CurrentOrders, order)
		BoxSpawnerService.UpdateUI(boxSpawner)
	end
	
	local function onRemoveOrderRequest(player : Player, instanceId : string)
		local boxSpawner = BoxSpawners[player]
		if not boxSpawner then return end
		
		for index, order in boxSpawner.CurrentOrders do
			if order.BoxInstanceId == instanceId then
				table.remove(boxSpawner.CurrentOrders, index)
				break
			end
		end
		
		BoxSpawnerService.UpdateUI(boxSpawner)
	end
	
	RemoveOrderFromBoxSpawnerEvent.Event:Connect(onRemoveOrderRequest)
	AddOrderToBoxSpawnerEvent.Event:Connect(onAddOrderRequest)
	
	BuyBoxEvent.OnServerInvoke = onBuyRequest
	BuyBoxWithGemsEvent.OnServerEvent:Connect(onBuyWithGemsRequest)
	
	StatsService.StatChanged:Connect(function(player : Player, statName : string, newValue : number)
		if not BoxSpawners[player] then return end
		if statName == "Box Limit" then
			BoxSpawners[player].BoxLimit = newValue
			BoxSpawnerService.UpdateUI(BoxSpawners[player])
		elseif statName == "Conveyor Luck" then
			BoxSpawners[player].ConveyorLuck = newValue
		end
	end)
	
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId : number, productId : number, isPurchased : boolean?)
		local player : Player = Players:GetPlayerByUserId(userId)
		if not player then return end
		if not table.find(BOX_PRODUCT_IDS, productId) then return end
		if not isPurchased then 
			PurchasingBoxRequests[player] = nil
		end
	end)
	MonetizationService.OnProductPurchase:Connect(function(player : Player, productId : number)
		if not table.find(BOX_PRODUCT_IDS, productId) then return end
		if not PurchasingBoxRequests[player] then return end

		local character = player.Character
		local humanoid : Humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		local boxSpawner = BoxSpawners[player]
		if not boxSpawner then return end
		
		local boxId = PurchasingBoxRequests[player].BoxId
		local boxInstanceId = PurchasingBoxRequests[player].BoxInstanceId
		
		local boxData = BoxesData.GetDataById(boxId)
		
		NotificationUtil.newTextNotification(
			player,
			`you bought a {string.lower(boxData.Name)}!`,
			nil,
			{
				Sound = "Purchase"
			}
		)

		local order = BoxService.GiveBox(player, boxId)
		DestroyConveyorBoxEvent:FireAllClients(boxInstanceId)
		BoxBoughtEvent:FireClient(player)

		table.insert(boxSpawner.CurrentOrders, order)
		BoxSpawnerService.UpdateUI(boxSpawner)
		
		for index, currentBox in boxSpawner.CurrentBoxes do
			if currentBox.InstanceId == boxInstanceId then
				table.remove(boxSpawner.CurrentBoxes, index)
			end
		end
		
		PurchasingBoxRequests[player] = nil
	end)
	
	Players.PlayerRemoving:Connect(function(player : Player)
		PurchasingBoxRequests[player] = nil
	end)
end

return BoxSpawnerService
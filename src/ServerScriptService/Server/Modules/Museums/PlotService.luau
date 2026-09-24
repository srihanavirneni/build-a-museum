local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local NPCTeleportToFloorEvent = ServerScriptService.Server.Bindables.NPCTeleportToFloor
local UpdateDecorationColorsBindableEvent = ServerScriptService.Server.Bindables.UpdateDecorationColors
local VisitorSpawnerService = require(ServerScriptService.Server.Modules.Visitors.VisitorSpawnerService)
local ItemPlacementService = require(ServerScriptService.Server.Modules.Museums.ItemPlacementService)
local PlayerDataService = require(ServerScriptService.Server.Modules.PlayerData.PlayerDataService)
local MonetizationService = require(ServerScriptService.Server.Modules.Monetization.MonetizationService)
local UpgradesService = require(ServerScriptService.Server.Modules.Progression.UpgradesService)
local BoxSpawnerService = require(ServerScriptService.Server.Modules.Museums.BoxSpawnerService)
local ButtonPadService = require(ServerScriptService.Server.Modules.Utils.ButtonPadService)
local StatsService = require(ServerScriptService.Server.Modules.Progression.StatsService)
local ItemService = require(ServerScriptService.Server.Modules.Museums.ItemService)
local GetPlotBindableFunction = ServerScriptService.Server.Bindables.GetPlot
local T = require(ServerScriptService.Server.Modules.Museums.PlotTypes)

local MuseumAssetTemplate = ServerStorage.Assets.Museums.StarterMuseum
local TopJigsawTemplate = ServerStorage.Assets.Museums.TopJigsaw
local MuseumTeleportsFolder = ServerStorage.Assets.MuseumTeleports

local PlotIndicatorUI = ReplicatedStorage.UI.BillboardGUI.PlotIndicatorUI
local VisitorStatusUI = ReplicatedStorage.UI.SurfaceGUI.VisitorStatusUI
local PlotDisplayUI = ReplicatedStorage.UI.SurfaceGUI.PlotDisplayUI
local GroupTotemModel = ReplicatedStorage.Assets.Models.GroupTotem
local NotificationUtil = require(ReplicatedStorage.Modules.Utils.NotificationUtil)
local MuseumColors = require(ReplicatedStorage.Modules.Data.MuseumColors)
local PlayerUtil = require(ReplicatedStorage.Modules.Utils.PlayerUtil)
local UpgradesData = require(ReplicatedStorage.Modules.Data.Upgrades)
local Colors = require(ReplicatedStorage.Modules.Data.Colors)
local Network = require(ReplicatedStorage.Packages.Network)
local ChangePlotColorEvent = Network:RemoteEvent("ChangePlotColor")
local SetCustomMuseumColorEvent = Network:RemoteEvent("SetCustomMuseumColor")
local GetMuseumColorEvent = Network:RemoteFunction("GetMuseumColor")
local GetPlotEvent = Network:RemoteFunction("GetPlot")
local GetAvailableFloorsEvent = Network:RemoteFunction("GetAvailableFloors")
local TeleportToFloorEvent = Network:RemoteEvent("TeleportToFloor")

local PlotSpawnsFolder = workspace.Environment.MuseumSpawns
local PlotsFolder = workspace.Environment.Museums

local LIGHT_ON_COLOR = Color3.fromRGB(151, 120, 51)
local LIGHT_OFF_COLOR = Color3.fromRGB(100,100,100)

local PlotService = {}

local CurrentPlots : {Players} = {}
local PlotOwners : {[Player] : number} = {}

local function darkenColor(color : Color3, amount : number?)
	amount = amount or 0.2 -- 20% darker by default

	local h, s, v = color:ToHSV()
	v = math.clamp(v * (1 - amount), 0, 1)

	return Color3.fromHSV(h, s, v)
end

local function fromHex(hex : string)
	-- allow "#RRGGBB" or "RRGGBB"
	hex = hex:gsub("^#", "")

	local r = tonumber(hex:sub(1, 2), 16)
	local g = tonumber(hex:sub(3, 4), 16)
	local b = tonumber(hex:sub(5, 6), 16)
	if not r or not g or not b then
		return nil
	end

	return Color3.fromRGB(r, g, b)
end

local function getPlot(index : number) : T.Plot
	for _, plot in CurrentPlots do
		if plot.Index == index then
			return plot
		end
	end
	return nil
end

local function findAvailablePlot()
	local availablePlots = {}
	for _, plot in CurrentPlots do
		if not plot.Owner then
			table.insert(availablePlots, plot)
		end
	end

	local selectedPlot : T.Plot = availablePlots[math.random(1, #availablePlots)]
	return selectedPlot.Index
end

function PlotService.CreatePlot(index : number)
	local newPlot : T.Plot = {}

	local spawnPart : BasePart = PlotSpawnsFolder:FindFirstChild(tostring(index))
	if not spawnPart then return end

	local newModel = MuseumAssetTemplate:Clone()
	newModel.Parent = PlotsFolder
	newModel:PivotTo(spawnPart.CFrame)
	spawnPart.Transparency = 1
	spawnPart.CanCollide = false
	
	newModel.Essentials.CustomizationSignPart.Transparency = 1
	newModel.Essentials.CustomizationSignPart.CanCollide = false

	local spawnsFolder = newModel.Essentials.Spawns
	for _, spawnPart : BasePart in spawnsFolder:GetChildren() do
		spawnPart.Transparency = 1
		spawnPart.CanCollide = false
		spawnPart.CastShadow = false
	end
	
	newPlot.TierSpawnsFolder = newModel.TierSpawns
	newPlot.Tier = 1
	
	for _, tierSpawn : BasePart in newModel.TierSpawns:GetChildren() do
		tierSpawn.Transparency = 1
		tierSpawn.CanCollide = false
		tierSpawn.CastShadow = false
	end

	local lightsFolder = newModel.Essentials.Lights
	for _, light in lightsFolder:GetChildren() do
		local pointLight : PointLight = light.LightSource.PointLight
		pointLight.Enabled = false
		if light.Name == "CeilingLight" then
			light.CeilingLight.Color = LIGHT_OFF_COLOR
		else
			light.LightSource.Color = LIGHT_OFF_COLOR
		end
	end

	newPlot.Index = index
	newPlot.Model = newModel
	
	local newOwnerObjectValue = Instance.new("ObjectValue")
	newOwnerObjectValue.Parent = newPlot.Model
	newOwnerObjectValue.Name = "OWNER"
	newOwnerObjectValue.Value = newPlot.Owner
	
	local newDisplayUI = PlotDisplayUI:Clone()
	newPlot.DisplayUI = newDisplayUI
	newPlot.DisplayUI.Parent = newModel.Essentials.PlotDataSign.Display
	
	local newVisitorStatusUI = VisitorStatusUI:Clone()
	newPlot.VisitorStatusUI = newVisitorStatusUI
	newPlot.VisitorStatusUI.Parent = newModel.Essentials.VisitorStatusSign.Display

	local newLikePrompt = Instance.new("ProximityPrompt")
	newLikePrompt.ActionText = "like museum"
	newLikePrompt.RequiresLineOfSight = false
	newLikePrompt.HoldDuration = 0.5
	newLikePrompt.Parent = newModel.Essentials.PlotDataSign.Display
	newLikePrompt.Name = "LikePrompt"
	newLikePrompt.Style = Enum.ProximityPromptStyle.Custom
	newLikePrompt.Enabled = false
	newLikePrompt.Triggered:Connect(function(playerWhoLiked : Player)
		PlotService.LikePlot(newPlot, playerWhoLiked)
	end)
	newPlot.LikePrompt = newLikePrompt
	newPlot.LikeDebounce = false
	
	local floorTeleportSpawn : BasePart = newPlot.Model.Essentials.FloorTeleportSpawn
	local newTeleportButton = MuseumTeleportsFolder.FloorTeleportButton:Clone()
	newTeleportButton.Parent = newPlot.Model.Essentials
	newTeleportButton:PivotTo(floorTeleportSpawn.CFrame)
	local ownerPointerObjectValue = Instance.new("ObjectValue")
	ownerPointerObjectValue.Parent = newTeleportButton
	ownerPointerObjectValue.Name = "OwnerPointer"
	ownerPointerObjectValue.Value = newOwnerObjectValue
	
	local newIndicatorUI = PlotIndicatorUI:Clone()
	newIndicatorUI.Parent = newPlot.Model.PlotIndicatorAdornee
	newIndicatorUI.Adornee = newIndicatorUI.Parent
	newPlot.PlotIndicatorUI = newIndicatorUI
	
	PlotService.UpdatePlot(newPlot)
	PlotService.ChangeColor(newPlot, 1)

	PlotService.UpdateFront(newPlot)
	
	return newPlot
end

function PlotService.SetOwner(plot : T.Plot, player : Player?)
	local oldOwner = plot.Owner
	plot.Owner = player
	
	local ownerObjectValue = plot.Model:FindFirstChild("OWNER")
	if ownerObjectValue and ownerObjectValue:IsA("ObjectValue") then
		ownerObjectValue.Value = plot.Owner
	end

	PlotService.UpdatePlot(plot)
	
	local buildRegionModel : Model = plot.Model.Essentials.BuildRegion
	local itemsFolder : Folder = plot.Model.Essentials.Items
	if oldOwner then
		ItemPlacementService.Save(oldOwner, buildRegionModel, itemsFolder)
	end
	ItemPlacementService.Unload(itemsFolder) -- unloading old stuff
	
	if plot.Owner then
		local newBoxSpawner = BoxSpawnerService.CreateBoxSpawner(plot)
		plot.BoxSpawner = newBoxSpawner
		
		local newVisitorSpawner = VisitorSpawnerService.CreateVisitorSpawner(player, plot.Model, {
			VisitorLimit = StatsService.GetStat(player, "Visitor Count"),
			VisitorSpawnRate = StatsService.GetStat(player, "Visitor Spawn Rate")
		})
		plot.VisitorSpawner = newVisitorSpawner
		
		ItemPlacementService.Load(player, buildRegionModel, itemsFolder)
	else
		if plot.BoxSpawner then
			BoxSpawnerService.Destroy(plot.BoxSpawner)
			plot.BoxSpawner = nil
		end
		if plot.VisitorSpawner then
			VisitorSpawnerService.Destroy(plot.VisitorSpawner)
			plot.VisitorSpawner = nil
		end
	end
end

function PlotService.ResetTier(plot : T.Plot)
	for _, tier : Model in plot.Model.Tiers:GetChildren() do
		tier:Destroy()
	end
	
	for _, part : BasePart in plot.Model.Essentials.BuildRegion:GetChildren() do
		if part.Name == "Tiered" then
			part:Destroy()
		end
	end
	
	plot.Tier = 1
	PlotService.UpdateFront(plot)
end

function PlotService.ExpandTier(plot : T.Plot)
	local tiersFolder : Folder = plot.Model.Tiers
	local newTier = plot.Tier + 1
	
	local newJigsaw = TopJigsawTemplate:Clone()

	local floorTeleportSpawn : BasePart = newJigsaw.Essentials.FloorTeleportSpawn
	local newTeleportButton = MuseumTeleportsFolder.FloorTeleportButton:Clone()
	newTeleportButton.Parent = newJigsaw.Essentials
	newTeleportButton:PivotTo(floorTeleportSpawn.CFrame)
	local ownerObjectValue = plot.Model:FindFirstChild("OWNER")
	if ownerObjectValue and ownerObjectValue:IsA("ObjectValue") then
		local ownerPointerObjectValue = Instance.new("ObjectValue")
		ownerPointerObjectValue.Parent = newTeleportButton
		ownerPointerObjectValue.Name = "OwnerPointer"
		ownerPointerObjectValue.Value = ownerObjectValue
	end
	
	for _, part in newJigsaw:GetDescendants() do
		if part:IsA("BasePart") and not part:GetAttribute("ShadowEnabled") then
			part.CastShadow = false
		end
	end
	
	local success, err = pcall(function()
		local tierSpawn : BasePart = plot.Model.TierSpawns:FindFirstChild("Tier"..newTier.."Spawn")

		newJigsaw.Parent = tiersFolder
		newJigsaw.Name = "Tier"..newTier
		newJigsaw:PivotTo(tierSpawn.CFrame)

		for _, part : BasePart in newJigsaw.Essentials.BuildRegion:GetChildren() do
			part.Parent = plot.Model.Essentials.BuildRegion
			part.Name = "Tiered"
			
			part:SetAttribute("Tier", newTier)
		end
	end)
	
	if not success or err then
		return warn("BAD!", plot.Owner.Name, newTier, err)
	end
	
	plot.Tier = plot.Tier + 1
	PlotService.UpdateFront(plot)
	
	return true
end

function PlotService.UpdateFront(plot : T.Plot)
	local primaryColorFolder = plot.Model.PrimaryColor
	
	for _, part : BasePart in primaryColorFolder.Front:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = plot.Tier <= 1 and 0 or 1
			part.CanCollide = plot.Tier <= 1
		end
	end
	
	for _, part : BasePart in primaryColorFolder.FrontWithTier:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = plot.Tier > 1 and 0 or 1
			part.CanCollide = plot.Tier > 1
		end
	end
end

function PlotService.ToggleGroupTotem(plot : T.Plot, toggle : boolean)
	local groupTotemSpawn : BasePart = plot.Model.Essentials:FindFirstChild("GroupTotemSpawn")
	if not groupTotemSpawn then return end
	
	local existingTotem : Model = groupTotemSpawn:FindFirstChildOfClass("Model")
	if existingTotem then
		existingTotem:Destroy()
	end
	
	if toggle then
		local newTotem = GroupTotemModel:Clone()
		newTotem.Parent = groupTotemSpawn
		newTotem:PivotTo(groupTotemSpawn.CFrame)
	end
end

function PlotService.UpdatePlot(plot : T.Plot)
	if not plot.DisplayUI then return end

	local playerInfoFrame = plot.DisplayUI.PlayerInfo
	local vacantFrame = plot.DisplayUI.Vacant

	local playerThumbnail = playerInfoFrame.PlayerThumbnail
	local usernameText = playerInfoFrame.Info.Username
	local likesText = playerInfoFrame.Info.Likes
	
	local signPart = plot.Model.Essentials.Sign
	local signTextLabel : TextLabel = signPart.SurfaceGui.TextLabel

	if plot.Owner then
		local profile = PlayerDataService.GetProfile(plot.Owner)
		if not profile then return end

		playerThumbnail.Image = PlayerUtil.GetPlayerThumbnail(
			plot.Owner.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420
		)
		usernameText.Text = `{plot.Owner.DisplayName}'s museum`
		signTextLabel.Text = `{plot.Owner.DisplayName}'s museum`

		likesText.Text = `👍 {#profile.Data.PlotLikesList}`
		
		plot.PlotIndicatorUI.PlayerThumbnail.Transparency = 1
		plot.PlotIndicatorUI.PlayerThumbnail.Image = playerThumbnail.Image
		plot.PlotIndicatorUI.TextLabel.Text = plot.Owner.Name
		
		local plotColorId = profile.Data.PlotColorId
		local customPlotColor = profile.Data.CustomPlotColor
		
		local savedTier = StatsService.GetStat(plot.Owner, "Plot Tier")
		if savedTier ~= 1 and plot.Tier ~= savedTier then
			for i = 1, savedTier - 1 do
				PlotService.ExpandTier(plot)
			end
		end
		
		if profile.Data.ClaimedGroupTotem then
			PlotService.ToggleGroupTotem(plot, true)
		else
			PlotService.ToggleGroupTotem(plot, false)
		end
		
		PlotService.ChangeColor(plot, 
			string.len(customPlotColor) > 0 and customPlotColor or plotColorId
		)
		
		local collectAllButton = plot.Model.Essentials.Interior.CollectAllButton
		local collectAllPad = ButtonPadService.CreateButtonPad(plot.Owner, collectAllButton, 0.5)
		plot.CollectAllPad = collectAllPad
		collectAllPad.OnTrigger:Connect(function()
			ItemPlacementService.CollectAll(plot.Owner, false)
		end)

		playerInfoFrame.Visible = true
		vacantFrame.Visible = false

		plot.LikePrompt.Enabled = true
		plot.PlotIndicatorUI.Enabled = true
	else
		playerInfoFrame.Visible = false
		vacantFrame.Visible = true
		
		signTextLabel.Text = "vacant museum"
		
		PlotService.ResetTier(plot)
		PlotService.ChangeColor(plot, 1)
		PlotService.ToggleGroupTotem(plot, false)

		plot.LikePrompt.Enabled = false
		plot.PlotIndicatorUI.Enabled = false
		
		if plot.CollectAllPad then
			ButtonPadService.Destroy(plot.CollectAllPad)
		end
	end

	local lightsFolder = plot.Model.Essentials.Lights
	for _, light in lightsFolder:GetChildren() do
		local pointLight : PointLight = light.LightSource.PointLight
		pointLight.Enabled = plot.Owner and true or false
		if light.Name == "CeilingLight" then
			light.CeilingLight.Color = plot.Owner and LIGHT_ON_COLOR or LIGHT_OFF_COLOR
		else
			light.LightSource.Color = plot.Owner and LIGHT_ON_COLOR or LIGHT_OFF_COLOR
		end
	end
	
	PlotService.UpdateFront(plot)
end

function PlotService.UpdateDecorationColors(plot : T.Plot, colorId : number | string)
	local primaryColor, secondaryColor
	if typeof(colorId) == "string" then
		local color : Color3 = fromHex(colorId)
		if color then
			primaryColor = color
			secondaryColor = darkenColor(color)
		else
			return
		end
	else
		local colorData = MuseumColors.GetDataById(colorId)
		if not colorData then return end
		primaryColor = colorData.PrimaryColor
		secondaryColor = colorData.SecondaryColor
	end
	
	local itemsFolder : Folder = plot.Model.Essentials.Items
	for _, item : Model in itemsFolder:GetChildren() do
		if item:GetAttribute("PlotColor") then
			for _, part in item:GetDescendants() do
				if part:IsA("BasePart") then
					if part:GetAttribute("PrimaryColor") then
						part.Color = primaryColor
					elseif part:GetAttribute("SecondaryColor") then
						part.Color = secondaryColor
					end
				end
			end
		end
	end
end

function PlotService.TeleportToFloor(plot : T.Plot, character : Model, tier : number)
	local humanoid : Humanoid = character and character:FindFirstChild("Humanoid")
	if humanoid then
		local tierModel = tier <= 1 and plot.Model or plot.Model.Tiers:FindFirstChild("Tier"..tier)
		if not tierModel then return end

		local floorSpawnPart : BasePart = tierModel.Essentials.Spawns.FloorSpawn
		if not floorSpawnPart then return end
		
		if Players:GetPlayerFromCharacter(character) then -- not an NPC/visitor
			if plot.TeleportDebounce then return end
			plot.TeleportDebounce = true
			task.delay(0.5, function()
				plot.TeleportDebounce = false
			end)
		end

		character:PivotTo(floorSpawnPart.CFrame + Vector3.new(0, 5, 0))
	end
end

function PlotService.ChangeColor(plot : T.Plot, colorId : number | string)
	local primaryColor, secondaryColor
	if typeof(colorId) == "string" then
		local color : Color3 = fromHex(colorId)
		if color then
			primaryColor = color
			secondaryColor = darkenColor(color)
		else
			return
		end
	else
		local colorData = MuseumColors.GetDataById(colorId)
		if not colorData then return end
		primaryColor = colorData.PrimaryColor
		secondaryColor = colorData.SecondaryColor
	end
	
	local function paint(target : Model)
		local primaryColorParts = target.PrimaryColor
		local secondaryColorParts = target.SecondaryColor

		for _, primaryColorPart : BasePart in primaryColorParts:GetDescendants() do
			if primaryColorPart:IsA("BasePart") then
				primaryColorPart.Color = primaryColor
			end
		end

		for _, secondaryColorPart : BasePart in secondaryColorParts:GetDescendants() do
			if secondaryColorPart:IsA("BasePart") then
				secondaryColorPart.Color = secondaryColor
			end
		end
	end
	
	PlotService.UpdateDecorationColors(plot, colorId)
	
	paint(plot.Model)
	
	for _, tier : Model in plot.Model.Tiers:GetChildren() do
		paint(tier)
	end
end

function PlotService.LikePlot(plot : T.Plot, playerWhoLiked : Player)
	if plot.LikeDebounce then return end

	if not playerWhoLiked or not plot.Owner then return end
	if plot.Owner.Name == playerWhoLiked.Name then
		return NotificationUtil.newTextNotification(
			playerWhoLiked,
			"you cannot like your own museum!"
		)
	end

	local profile = PlayerDataService.GetProfile(plot.Owner)
	if not profile then return end

	if table.find(profile.Data.PlotLikesList, playerWhoLiked.UserId) then
		return NotificationUtil.newTextNotification(
			playerWhoLiked,
			`you already liked {plot.Owner.Name}'s museum`
		)
	end

	plot.LikeDebounce = true
	task.delay(.5, function() plot.LikeDebounce = false end)

	NotificationUtil.newTextNotification(
		plot.Owner,
		`{playerWhoLiked} liked your museum`
	)
	NotificationUtil.newTextNotification(
		playerWhoLiked,
		`you liked {plot.Owner.Name}'s museum`
	)

	table.insert(profile.Data.PlotLikesList, playerWhoLiked.UserId)
	PlotService.UpdatePlot(plot)
end

function PlotService.TeleportPlayer(player : Player)
	if not PlotOwners[player] then return end

	local plot = getPlot(PlotOwners[player])
	player.Character:PivotTo(
		plot.Model.Essentials.Spawns.PlayerSpawn.CFrame + Vector3.new(0, 5, 0)
	)
end

function PlotService.GetPlot(player : Player) : T.Plot
	if not PlotOwners[player] then
		repeat task.wait() until PlotOwners[player]
	end
	local plot = getPlot(PlotOwners[player])
	return plot
end

function PlotService.Start()
	local function playerAdded(player : Player)
		local availableIndex = findAvailablePlot()
		if not availableIndex then return end

		local function characterAdded(character)
			RunService.Stepped:Wait()
			PlotService.TeleportPlayer(player)
		end

		local plot = getPlot(availableIndex)
		PlotService.SetOwner(plot, player)

		PlotOwners[player] = availableIndex

		if player.Character then characterAdded(player.Character) end
		player.CharacterAdded:Connect(characterAdded)
	end

	for _, spawnPart : BasePart in PlotSpawnsFolder:GetChildren() do
		if not spawnPart:IsA("BasePart") then continue end

		local index = tonumber(spawnPart.Name)
		local newPlot = PlotService.CreatePlot(index)

		CurrentPlots[index] = newPlot
	end
	
	SetCustomMuseumColorEvent.OnServerEvent:Connect(function(player : Player, customColor : Color3)
		if typeof(customColor) ~= "Color3" then return end
		if not MonetizationService.OwnsGamepassByName(player, "VIP") then
			return NotificationUtil.newTextNotification(
				player,
				"VIP required!",
				Color3.fromRGB(255,0,0),
				{
					Sound = "Error"
				}
			)
		end
		
		local plot = PlotService.GetPlot(player)
		if not plot then return end

		local profile = PlayerDataService.GetProfile(player)
		if not profile then return end
		
		profile.Data.CustomPlotColor = customColor:ToHex()
		PlotService.ChangeColor(plot, customColor:ToHex())
	end)
	ChangePlotColorEvent.OnServerEvent:Connect(function(player : Player, colorId : number)
		if typeof(colorId) ~= "number" then return end
		
		local colorData = MuseumColors.GetDataById(colorId)
		if not colorData then return end
		
		local plot = PlotService.GetPlot(player)
		if not plot then return end
		
		local profile = PlayerDataService.GetProfile(player)
		if not profile then return end
		
		profile.Data.PlotColorId = colorId
		profile.Data.CustomPlotColor = ""
		PlotService.ChangeColor(plot, colorId)
	end)
	
	GetAvailableFloorsEvent.OnServerInvoke = function(player : Player, targetPlayer : Player?)
		if targetPlayer ~= nil then
			if typeof(targetPlayer) ~= "Instance" then return end
			if not targetPlayer:IsA("Player") then return end
		end
		
		local plot = PlotService.GetPlot(targetPlayer or player)
		if not plot then return end
		local tiersFolder = plot.Model.Tiers
		local available = { 1 }
		for _, tierModel in tiersFolder:GetChildren() do
			local tierNum : number = tonumber(tierModel.Name:match("%d+"))
			table.insert(available, tierNum)
		end
		return available, plot.Model.Essentials.BuildRegion
	end
	TeleportToFloorEvent.OnServerEvent:Connect(function(player : Player, selectedFloorTier : number, targetPlayer : Player)
		if targetPlayer ~= nil then
			if typeof(targetPlayer) ~= "Instance" then return end
			if not targetPlayer:IsA("Player") then return end
		end
		
		local plot = PlotService.GetPlot(targetPlayer or player)
		if not plot then return end
		PlotService.TeleportToFloor(plot, player.Character, selectedFloorTier)
	end)
	
	NPCTeleportToFloorEvent.Event:Connect(function(player : Player, ...)
		local plot = PlotService.GetPlot(player)
		if not plot then return end
		PlotService.TeleportToFloor(plot, ...)
	end)
	UpdateDecorationColorsBindableEvent.Event:Connect(function(player : Player)
		local profile = PlayerDataService.GetProfile(player)
		if not profile then return end
		local plot = PlotService.GetPlot(player)
		if not plot then return end
		
		PlotService.UpdateDecorationColors(plot, 
			string.len(profile.Data.CustomPlotColor) > 0 and profile.Data.CustomPlotColor or profile.Data.PlotColorId
		)
	end)
	GetPlotBindableFunction.OnInvoke = function(player : Player)
		local plot = PlotService.GetPlot(player)
		return plot.Model
	end
	GetPlotEvent.OnServerInvoke = function(player : Player)
		local plot = PlotService.GetPlot(player)
		return plot.Model
	end
	GetMuseumColorEvent.OnServerInvoke = function(player : Player)
		local profile = PlayerDataService.GetProfile(player)
		if not profile then return end
		
		if string.len(profile.Data.CustomPlotColor) > 0 then
			return fromHex(profile.Data.CustomPlotColor)
		end
		
		local colorData = MuseumColors.GetDataById(profile.Data.PlotColorId)
		if not colorData then return end
		return colorData.PrimaryColor
	end

	for _, player : Player in Players:GetPlayers() do
		task.spawn(playerAdded, player)
	end
	Players.PlayerAdded:Connect(playerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, index in PlotOwners do
			local plot = getPlot(index)
			if plot.Owner and plot.Owner.Name == player.Name then
				PlotService.SetOwner(plot, nil)
			end
		end
		PlotOwners[player] = nil
	end)
end

return PlotService
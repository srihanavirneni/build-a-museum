local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local ItemPlacementService = require(ServerScriptService.Server.Modules.Museums.ItemPlacementService)
local VisitorService = require(ServerScriptService.Server.Modules.Visitors.VisitorService)
local StatsService = require(ServerScriptService.Server.Modules.Progression.StatsService)
local T = require(ServerScriptService.Server.Modules.Visitors.VisitorTypes)

local VisitorStatusUI = ReplicatedStorage.UI.SurfaceGUI.VisitorStatusUI
local MathUtil = require(ReplicatedStorage.Modules.Utils.MathUtil)

local VisitorSpawnerService = {}
local VisitorSpawners : { T.VisitorSpawner } = {}

function VisitorSpawnerService.CreateVisitorSpawner(player : Player, plotModel : Model, props : T.VisitorSpawner)
	props = props or {}

	local newVisitorSpawner : T.VisitorSpawner = {}

	newVisitorSpawner.Player = player
	newVisitorSpawner.PlotModel = plotModel

	newVisitorSpawner.SpawnPart = newVisitorSpawner.PlotModel.Essentials.Spawns.VisitorSpawn
	newVisitorSpawner.VisitorLimit = props.VisitorLimit or 8
	newVisitorSpawner.VisitorSpawnRate = props.VisitorSpawnRate or 0.5
	
	newVisitorSpawner.Exclusives = {}
	newVisitorSpawner.ItemLuxuryIndices = 
		VisitorSpawnerService.CalculateLuxuryIndices(newVisitorSpawner)

	newVisitorSpawner.Visitors = {}
	newVisitorSpawner.Connections = {}
	
	newVisitorSpawner.BestItem = nil

	VisitorSpawnerService.SpawnVisitors(newVisitorSpawner)
	
	table.insert(newVisitorSpawner.Connections, ItemPlacementService.PlacementChangedEvent:Connect(function()
		newVisitorSpawner.ItemLuxuryIndices = VisitorSpawnerService.CalculateLuxuryIndices(newVisitorSpawner)
	end))
	
	table.insert(VisitorSpawners, newVisitorSpawner)

	return newVisitorSpawner
end

function VisitorSpawnerService.CalculateLuxuryIndices(visitorSpawner : T.VisitorSpawner)
	local plotModel = visitorSpawner.PlotModel
	local itemsFolder = plotModel.Essentials.Items

	local sorted = {}
	for _, item : Model in itemsFolder:GetChildren() do
		if not item:GetAttribute("PlacedItem") then continue end
		if item:GetAttribute("Decoration") then continue end
		if item:GetAttribute("Exclusive") then 
			table.insert(visitorSpawner.Exclusives, item)
			continue
		end
		
		item:SetAttribute("BestItem", nil)
		table.insert(sorted, item)
	end

	table.sort(sorted, function(a,b)
		local incomeA = a:GetAttribute("MoneyPerSecond")
		local incomeB = b:GetAttribute("MoneyPerSecond")
		return incomeA < incomeB
	end)
	
	visitorSpawner.ItemLuxuryIndices = sorted
	
	if sorted[#sorted] and sorted[#sorted]:IsA("Model") and sorted[#sorted]:GetAttribute("InstanceId") then
		visitorSpawner.BestItem = sorted[#sorted]:GetAttribute("InstanceId")
		sorted[#sorted]:SetAttribute("BestItem", true)
	end
	
	return sorted
end

function VisitorSpawnerService.SpawnVisitors(visitorSpawner : T.VisitorSpawner)
	local timeElapsed = 0
	
	local visitorStatusSign = visitorSpawner.PlotModel.Essentials.VisitorStatusSign
	local statusUI : typeof(VisitorStatusUI) 
		= visitorStatusSign.Display:FindFirstChild("VisitorStatusUI")
	if not statusUI then return end
	
	local function getAvailableViewingSlots()
		local plotModel = visitorSpawner.PlotModel
		local itemsFolder = plotModel.Essentials.Items
		
		local slots = 0
		
		for _, item : Model in itemsFolder:GetChildren() do
			if item:GetAttribute("Decoration") then continue end
			
			local maxViewers = item:GetAttribute("MaxViewers") or 1
			local viewersFolder = item:FindFirstChild("Viewers")
			
			local currentViewers = viewersFolder and #viewersFolder:GetChildren() or 0
			
			slots += math.max(maxViewers - currentViewers, 0)
		end
		
		if slots == 0 then
			timeElapsed = 0
		end
		
		return slots
	end

	local nextInterval = 1 / (visitorSpawner.VisitorSpawnRate)
	local nextRate = 1 / nextInterval
	
	local function update(deltaTime)
		timeElapsed = timeElapsed + deltaTime
		
		local visitorCount = #visitorSpawner.Visitors
		statusUI.VisitorCount.Text = "visitors: "..visitorCount
		statusUI.VisitorCount.TextColor3 = visitorCount >= visitorSpawner.VisitorLimit 
			and Color3.fromRGB(255,0,0) or Color3.fromRGB(255,255,255)
		statusUI.VisitorSpawnRate.Text = "visitor spawn rate: "..MathUtil.Round(nextRate,2)
		
		if 
			timeElapsed >= nextInterval and 
			visitorCount < visitorSpawner.VisitorLimit and
			#visitorSpawner.ItemLuxuryIndices > 0 and getAvailableViewingSlots() > 0
		then
			timeElapsed = 0
			
			local averageSpawnInterval = 1 / (visitorSpawner.VisitorSpawnRate)
			nextInterval = math.max(MathUtil.SampleNormalDistribution(averageSpawnInterval, 0.36), 0.1)
			nextRate = 1 / averageSpawnInterval
			
			local newVisitorNPC = VisitorService.CreateVisitor(visitorSpawner)
			table.insert(visitorSpawner.Visitors, newVisitorNPC)
		end
		
	end

	table.insert(visitorSpawner.Connections, RunService.Heartbeat:Connect(update))
end

function VisitorSpawnerService.Destroy(visitorSpawner : T.VisitorSpawner)
	for index, existingVisitorSpawner in VisitorSpawners do
		if existingVisitorSpawner.Player == visitorSpawner.Player then
			table.remove(VisitorSpawners, index)
			break
		end
	end
	
	for _, connection in visitorSpawner.Connections do
		connection:Disconnect()
		connection = nil
	end

	for _, visitor in visitorSpawner.Visitors do
		VisitorService.Destroy(visitor)
	end

	table.freeze(visitorSpawner)
	visitorSpawner = nil
end

function VisitorSpawnerService.Start()
	StatsService.StatChanged:Connect(function(player : Player, statName : string, newValue : number)
		if statName == "Visitor Count" or statName == "Visitor Spawn Rate" then
			for _, visitorSpawner in VisitorSpawners do
				if visitorSpawner.Player == player then
					
					if statName == "Visitor Count" then
						visitorSpawner.VisitorLimit = newValue
					elseif statName == "Visitor Spawn Rate" then
						visitorSpawner.VisitorSpawnRate = newValue
					end
					
				end
			end
		end
	end)
end

return VisitorSpawnerService
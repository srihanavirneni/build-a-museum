local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local NPCTeleportToFloorEvent = ServerScriptService.Server.Bindables.NPCTeleportToFloor
local ItemPlacementService = require(ServerScriptService.Server.Modules.Museums.ItemPlacementService)
local VisitorMessages = require(ServerScriptService.Server.Modules.Visitors.VisitorMessages)
local T = require(ServerScriptService.Server.Modules.Visitors.VisitorTypes)
local VisitorNPCTemplate = ServerStorage.Assets.VisitorNPCTemplate
local PresetVisitorsFolder = ServerStorage.Assets.PresetVisitors

local ItemsData = require(ReplicatedStorage.Modules.Data.Items)
local MathUtil = require(ReplicatedStorage.Modules.Utils.MathUtil)
local SoundUtil = require(ReplicatedStorage.Modules.Utils.SoundUtil)
local Network = require(ReplicatedStorage.Packages.Network)
local OnVisitorChattedEvent = Network:RemoteEvent("OnVisitorChatted")

local VISITOR_COLLISION_GROUP = "Visitor"
local MIN_USER_ID, MAX_USER_ID = 1, 4244085920
local RNG = Random.new()

local LUXURY_EFFECTIVENESS_CONSTANT = 0.4
local NPC_STAND_DISTANCE = 4

local MIN_LUXURY_PREFERENCE = 0
local MAX_LUXURY_PREFERENCE = 100

local VisitorService = {}
local PlayerFriends : { [Player] : {number} } = {}

local function getRandomPointInPart(targetPart : BasePart)
	local halfSize = targetPart.Size / 2
	local randomX = RNG:NextNumber(-halfSize.X, halfSize.X)
	local randomZ = RNG:NextNumber(-halfSize.Z, halfSize.Z)

	local localOffset = Vector3.new(randomX, 0, randomZ)
	local worldPosition = targetPart.CFrame:PointToWorldSpace(localOffset)

	return CFrame.new(worldPosition, worldPosition + targetPart.CFrame.LookVector)
end

local function getClosestPointOnPart(part: BasePart, worldPoint: Vector3)
	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local halfSize = part.Size * 0.5

	local clampedLocal = Vector3.new(
		math.clamp(localPoint.X, -halfSize.X, halfSize.X),
		math.clamp(localPoint.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPoint.Z, -halfSize.Z, halfSize.Z)
	)

	return part.CFrame:PointToWorldSpace(clampedLocal)
end

function VisitorService.CreateVisitor(visitorSpawner : T.VisitorSpawner)
	local newVisitor : T.Visitor = {}

	newVisitor.Id = HttpService:GenerateGUID()

	newVisitor.VisitorSpawner = visitorSpawner

	newVisitor.IsTalking = false
	newVisitor.Connections = {}
	newVisitor.LookedTargets = {}
	newVisitor.FocusingObjectValue = nil
	
	newVisitor.LuxuryPreference = 50
	newVisitor.AttentionSpan = 50
	newVisitor.ViewCount = math.random(1, 2)
	
	VisitorService.BuildNPC(newVisitor)
	
	newVisitor.ShouldDestroy = false
	newVisitor.DestroyTask = task.spawn(function()
		repeat
			task.wait()
		until newVisitor.ShouldDestroy
		VisitorService.Destroy(newVisitor)
	end)
	newVisitor.Task = task.spawn(function()
		local totalViews = 0
		repeat task.wait()
			local targetItem : Model = VisitorService.Search(newVisitor)
			if not targetItem then return VisitorService.Leave(newVisitor, VisitorMessages.Leave) end

			table.insert(newVisitor.LookedTargets, targetItem)
			VisitorService.LookAt(newVisitor, targetItem)

			if newVisitor.FocusingObjectValue then
				newVisitor.FocusingObjectValue:Destroy()
				newVisitor.FocusingObjectValue = nil
			end
			
			totalViews = totalViews + 1
		until totalViews >= newVisitor.ViewCount

		VisitorService.Leave(newVisitor, VisitorMessages.Satisfied)
	end)

	return newVisitor
end

function VisitorService.LookAt(visitor : T.Visitor, targetItem : Model)
	local targetId = targetItem:GetAttribute("Id")
	local targetItemData = ItemsData.GetDataById(targetId)

	local attentionSpanPercentage = visitor.AttentionSpan / 100
	local interestTime = math.clamp(
		MathUtil.SampleNormalDistribution(targetItemData.InterestTime, 0.45),
		math.max(targetItemData.InterestTime - (attentionSpanPercentage * targetItemData.InterestTime), 1),
		targetItemData.InterestTime + (attentionSpanPercentage * targetItemData.InterestTime)
	)

	local totalTimeToSpend = attentionSpanPercentage * interestTime
	
	if not targetItem.PrimaryPart then return end
	
	local closestPoint = getClosestPointOnPart(targetItem.PrimaryPart, visitor.NPCModel.PrimaryPart.Position)
	local direction = (visitor.NPCModel.PrimaryPart.Position - closestPoint).Unit
	local standPosition = closestPoint + direction * NPC_STAND_DISTANCE
	standPosition = Vector3.new(standPosition.X, targetItem.PrimaryPart.Position.Y, standPosition.Z)
	
	local viewersFolder = targetItem:FindFirstChild("Viewers")
	if viewersFolder and not visitor.FocusingObjectValue then
		local newObjectValue = Instance.new("ObjectValue")
		newObjectValue.Parent = viewersFolder
		newObjectValue.Name = "visitor"
		newObjectValue.Value = visitor.NPCModel
		visitor.FocusingObjectValue = newObjectValue
	end
	
	VisitorService.WalkTo(visitor, standPosition)
	
	task.delay(0.15, function()
		if visitor.NPCModel and visitor.NPCModel.PrimaryPart and targetItem.PrimaryPart and targetItem.PrimaryPart.Position then
			visitor.NPCModel:PivotTo(
				CFrame.lookAt(visitor.NPCModel:GetPivot().Position, 
					targetItem.PrimaryPart.Position)
			)
		end
	end)
	
	local counter = 0
	local timeBetweenChat = totalTimeToSpend // 2
	
	repeat
		if not targetItem or not targetItem:IsDescendantOf(workspace) then
			break
		end
		
		if counter ~= 0 and counter % timeBetweenChat == 0 and counter < totalTimeToSpend - 2 then
			local appreciationMessage = VisitorMessages.Appreciation[math.random(1, #VisitorMessages.Appreciation)]
			VisitorService.Chat(visitor, appreciationMessage)
		end
		
		VisitorService.Earn(visitor, targetItem)
		
		counter = counter + 1
		task.wait(1)
	until counter >= totalTimeToSpend
end

function VisitorService.Earn(visitor : T.Visitor, targetItem : Model)
	local moneyPerSecond = targetItem:GetAttribute("MoneyPerSecond")
	local oldEarnings = targetItem:GetAttribute("Earnings")
	
	targetItem:SetAttribute("Earnings", oldEarnings + moneyPerSecond)
	
	if visitor.VisitorSpawner.BestItem == targetItem:GetAttribute("InstanceId") then
		VisitorService.ExclusiveEarn(visitor, moneyPerSecond)
	end
end

function VisitorService.ExclusiveEarn(visitor : T.Visitor, bestItemIncome : number)
	for _, exclusiveItem : Model in visitor.VisitorSpawner.Exclusives do
		if exclusiveItem and exclusiveItem:IsA("Model") and exclusiveItem:GetAttribute("Percentage") then
			local addedIncome = math.ceil(bestItemIncome * (exclusiveItem:GetAttribute("Percentage")/100))

			local oldEarnings = exclusiveItem:GetAttribute("Earnings")
			exclusiveItem:SetAttribute("Earnings", oldEarnings + addedIncome)
		end
	end
end

function VisitorService.Search(visitor : T.Visitor)
	local M = 1 + (LUXURY_EFFECTIVENESS_CONSTANT * (visitor.LuxuryPreference / 100))
	local N = #visitor.VisitorSpawner.ItemLuxuryIndices
	
	local function isValidItem(item : Model)
		if table.find(visitor.LookedTargets, item) then return false end
		local viewersFolder = item:FindFirstChild("Viewers")
		if viewersFolder and #viewersFolder:GetChildren() >= item:GetAttribute("MaxViewers") then
			return false
		end
		return true
	end
	
	if N > 0 then
		-- recalculating N
		
		local itemPool = {}
		for _, item : Model in visitor.VisitorSpawner.ItemLuxuryIndices do
			if not isValidItem(item) then continue end	
			table.insert(itemPool, item)
		end
		N = #itemPool
		
		local weights = {}
		local currentIndex = 1
		for _, item : Model in itemPool do
			local weight = 1 / N
			if visitor.LuxuryPreference > 0 then
				weight = (M^currentIndex * (M - 1)) / (M^(N+1) - M)
			end
			
			table.insert(weights, weight)
			currentIndex = currentIndex + 1
		end
		
		local roll = RNG:NextNumber(0, 1)
		local cumulative = 0
		for luxuryIndex, weight in weights do
			cumulative = cumulative + weight
			if roll <= cumulative then
				return itemPool[luxuryIndex]
			end
		end
	end
end

function VisitorService.WalkTo(visitor : T.Visitor, destination : Vector3, onComplete : () -> ())
	local humanoid : Humanoid = visitor.NPCModel.Humanoid
	local humanoidRootPart : BasePart = visitor.NPCModel.HumanoidRootPart
	if not humanoid or not humanoidRootPart then return end
	
	if visitor.Destroying then return end
	
	local function getFloorLevels() : number
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.IgnoreWater = true
		raycastParams.FilterDescendantsInstances = { 
			visitor.VisitorSpawner.PlotModel.Essentials.BuildRegion
		}

		local destinationResult = workspace:Raycast(
			destination + Vector3.new(0, 5, 0), 
			Vector3.new(0, -15, 0), 
			raycastParams
		)
		
		local visitorResult = workspace:Raycast(
			humanoidRootPart.Position + Vector3.new(0, 5, 0),
			Vector3.new(0, -15, 0),
			raycastParams
		)
		
		local visitorTier, destinationTier = 1, 1
		
		if visitorResult and visitorResult.Instance and visitorResult.Instance.Name ~= "AlignmentAnchor" then
			visitorTier = visitorResult.Instance:GetAttribute("Tier") or 1
		end
		
		if destinationResult and destinationResult.Instance and destinationResult.Instance.Name ~= "AlignmentAnchor" then
			destinationTier = destinationResult.Instance:GetAttribute("Tier") or 1
		end
		
		return visitorTier, destinationTier
	end
	
	local visitorTier, destinationTier = getFloorLevels()
	
	if visitorTier ~= destinationTier then
		local tp : BasePart = visitor.VisitorSpawner.PlotModel.Essentials.FloorTeleportSpawn
		
		humanoid:MoveTo(Vector3.new(tp.Position.X, humanoidRootPart.Position.Y, tp.Position.Z))
		humanoid.MoveToFinished:Wait()

		if visitor.Destroying then return end
		
		NPCTeleportToFloorEvent:Fire(
			visitor.VisitorSpawner.Player,
			visitor.NPCModel,
			destinationTier
		)
		
		task.wait(0.1)
	end
	
	humanoid:MoveTo(Vector3.new(destination.X, humanoidRootPart.Position.Y, destination.Z))
	humanoid.MoveToFinished:Wait()
	
	if onComplete then
		task.spawn(onComplete)
	end
end

function VisitorService.Leave(visitor : T.Visitor, chatMessagePool : { string }?)
	local leaveCF : CFrame = getRandomPointInPart(visitor.VisitorSpawner.PlotModel.Essentials.Spawns.VisitorSpawn)
	local leavePosition = leaveCF.Position

	if visitor.Destroying then return end
	if chatMessagePool then
		local randomLeaveMessage = chatMessagePool[math.random(1, #chatMessagePool)]
		VisitorService.Chat(visitor, randomLeaveMessage)

		task.wait(1)
	end
	
	VisitorService.WalkTo(visitor, leavePosition, function()
		if math.random(1, 2) == 1 then
			SoundUtil.Play(visitor.VisitorSpawner.Player, "Bye", visitor.NPCModel.HumanoidRootPart, {
				Volume = 0.125
			})
		end
		visitor.ShouldDestroy = true
	end)
end

function VisitorService.BuildNPC(visitor : T.Visitor)
	local randomPreset = PresetVisitorsFolder:GetChildren()[math.random(1, #PresetVisitorsFolder:GetChildren())]
	local isRealCharacter = math.random(1,2) == 1

	visitor.NPCModel = isRealCharacter and VisitorNPCTemplate:Clone() or randomPreset:Clone()
	visitor.NPCModel.Parent = visitor.VisitorSpawner.PlotModel.Essentials.Visitors
	visitor.NPCModel:PivotTo(CFrame.new(Vector3.new(1000, 500, 1000)))

	visitor.NPCModel.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	visitor.NPCModel.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	visitor.NPCModel.Name = "Visitor"

	for _, part : BasePart in visitor.NPCModel:GetChildren() do
		if part:IsA("BasePart") then
			part.CollisionGroup = VISITOR_COLLISION_GROUP
		end
	end

	if isRealCharacter then
		local isFriend = math.random(1,2) == 1
		local friendCount = 0
		
		if PlayerFriends[visitor.VisitorSpawner.Player] then
			friendCount = #PlayerFriends[visitor.VisitorSpawner.Player]
		end
		
		local randomFriendId = 
			(PlayerFriends[visitor.VisitorSpawner.Player] and friendCount > 0 and isFriend)
			and PlayerFriends[visitor.VisitorSpawner.Player][math.random(1, friendCount)] 
			or Random.new():NextInteger(MIN_USER_ID, MAX_USER_ID)

		local friendHumanoidDescription : HumanoidDescription = nil
		local success, err = pcall(function()
			friendHumanoidDescription = Players:GetHumanoidDescriptionFromUserIdAsync(randomFriendId)
		end)

		if success and friendHumanoidDescription then
			pcall(function()
				visitor.NPCModel.Humanoid:ApplyDescriptionResetAsync(friendHumanoidDescription)
			end)
		end
	end

	visitor.NPCModel:PivotTo(getRandomPointInPart(visitor.VisitorSpawner.PlotModel.Essentials.Spawns.VisitorSpawn))
	visitor.NPCModel.HumanoidRootPart:SetNetworkOwner(nil)
	
	CollectionService:AddTag(visitor.NPCModel, "Visitor")
	
	if math.random(1, 2) == 1 then
		SoundUtil.Play(visitor.VisitorSpawner.Player, "Hi", visitor.NPCModel.HumanoidRootPart, {
			Volume = 0.125
		})
	end
end

function VisitorService.Chat(visitor : T.Visitor, message : string, delayTime : number?)
	delayTime = delayTime or 3

	if visitor.IsTalking then return end
	visitor.IsTalking = true

	OnVisitorChattedEvent:FireAllClients(visitor.NPCModel, message, delayTime)

	task.delay(delayTime, function()
		if visitor.Destroying then return end
		visitor.IsTalking = false
	end)
end

function VisitorService.Destroy(visitor : T.Visitor)
	if visitor.Destroying then return end
	visitor.Destroying = true
	
	if visitor.Task then
		task.cancel(visitor.Task)
	end

	if visitor.NPCModel then
		visitor.NPCModel:Destroy()
		visitor.NPCModel = nil
	end

	if visitor.VisitorSpawner then
		for index, target in visitor.VisitorSpawner.Visitors do
			if target.Id == visitor.Id then
				table.remove(visitor.VisitorSpawner.Visitors, index)
			end
		end
	end

	if visitor.Connections then
		for _, connection in visitor.Connections do
			connection:Disconnect()
			connection = nil
		end
	end

	table.freeze(visitor)
	visitor = nil
end

function VisitorService.Start()
	local function playerAdded(player : Player)
		local friendList : FriendPages = nil
		local success, err = pcall(function()
			friendList = Players:GetFriendsAsync(player.UserId)
		end)

		local function iterPageItems(pages)
			local pagenum = 1
			local list = {}
			while pagenum <= 500 do
				for _, item in pages:GetCurrentPage() do
					table.insert(list, item)
				end
				if pages.IsFinished then
					break
				end
				pages:AdvanceToNextPageAsync()
				pagenum = pagenum + 1
			end

			return list
		end

		if success and friendList then
			local friendIds = {}
			for _, friendData in iterPageItems(friendList) do
				table.insert(friendIds, friendData.Id)
			end
			PlayerFriends[player] = friendIds
		else
			warn(err)
		end
	end

	PhysicsService:RegisterCollisionGroup(VISITOR_COLLISION_GROUP)
	PhysicsService:CollisionGroupSetCollidable(VISITOR_COLLISION_GROUP, VISITOR_COLLISION_GROUP, false)
	task.delay(2, function()
		PhysicsService:CollisionGroupSetCollidable("PlayerCharacters", VISITOR_COLLISION_GROUP, false)
	end)
	
	for _, player in Players:GetPlayers() do
		task.spawn(playerAdded, player)
	end
	Players.PlayerAdded:Connect(playerAdded)
	Players.PlayerRemoving:Connect(function(player : Player)
		PlayerFriends[player] = nil
	end)
end

return VisitorService
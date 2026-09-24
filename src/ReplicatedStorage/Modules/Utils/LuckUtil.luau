local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerLuckMultiplierValue = ReplicatedStorage.Modules.Data.ServerLuckMultiplier
local MathUtil = require(ReplicatedStorage.Modules.Utils.MathUtil)

local LuckUtil = {}

local SEED = math.random(workspace:GetServerTimeNow())
local TOTAL_ROLLS = 0

local LUCK_CONSTANT = 1.5
local STANDARD_DEVIATION = 2

local function calculateAdjustedChanceDenominator(chance : number, luck : number)
	local chanceDenominator = 1 / chance
	local effectiveLuck = luck ^ LUCK_CONSTANT

	local newChanceDenominator = math.max(1, (chanceDenominator/effectiveLuck))
	return newChanceDenominator
end

local function sortItems(itemsTable)
	local sortedTbl = {}
	for _, entry in itemsTable do
		if entry.Exclusive then continue end
		table.insert(sortedTbl, {
			Name = entry.Name,
			Chance = entry.Chance,
			Exclusive = entry.Exclusive,
		})
	end

	table.sort(sortedTbl, function(a,b)
		return a.Chance > b.Chance
	end)

	for index, entry in sortedTbl do
		sortedTbl[index].Tier = index
	end

	return sortedTbl
end

function LuckUtil.GetPercentagesForPlayer(player : Player, itemsTable, luck : number)
	local luckBoostMultiplier = player:GetAttribute("CumulativeLuckMultiplier") or 1
	local luckBoostPercentage = math.floor((luckBoostMultiplier - 1) * 100)

	local effectiveLuck = luck * ((math.ceil(luckBoostPercentage/2) or 0) + 100)/100
	effectiveLuck = effectiveLuck * ServerLuckMultiplierValue.Value

	local adjustedChances, totalWeight = LuckUtil.GetPercentages(itemsTable, effectiveLuck)
	local percentages = {}

	for _, data in adjustedChances do
		local percentage = MathUtil.Round((data[2] / totalWeight) * 100, 2)
		if percentage > 0 then
			percentages[data[1]] = percentage
		end
	end

	return percentages, effectiveLuck
end

function LuckUtil.GetPercentages(itemsTable, luckBoostPercentage : number, ignoreSort : boolean)
	if not ignoreSort then itemsTable = sortItems(itemsTable) end
	for i = #itemsTable, 1, -1 do
		if not itemsTable[i] then continue end
		if itemsTable[i].Exclusive then
			table.remove(itemsTable,i)
		end
	end

	luckBoostPercentage = luckBoostPercentage or 0

	local luck = 1 + (luckBoostPercentage / 100)
	local mean = math.min(#itemsTable, 1 + 0.05 * (#itemsTable - 1) * math.log(1 + (luck ^ LUCK_CONSTANT)))

	local adjustedChances = {}
	for _, data in itemsTable do
		local newChanceDenominator = calculateAdjustedChanceDenominator(data.Chance, luck)
		local newChance = 1 / newChanceDenominator

		local gaussianMultiplier = math.exp(-0.5 * ((data.Tier - mean) / STANDARD_DEVIATION) ^ 2)

		table.insert(adjustedChances, { data.Name, newChance * gaussianMultiplier})
	end

	local totalWeight = 0
	for _, data in adjustedChances do
		totalWeight = totalWeight + data[2]
	end

	return adjustedChances, totalWeight
end

function LuckUtil.Roll(itemsTable, luckBoostPercentage : number)
	itemsTable = sortItems(itemsTable)

	TOTAL_ROLLS = TOTAL_ROLLS + 1
	luckBoostPercentage = luckBoostPercentage or 0

	local adjustedChances, totalWeight = LuckUtil.GetPercentages(
		itemsTable, 
		luckBoostPercentage, 
		true
	)

	local seed = SEED + TOTAL_ROLLS
	local roll = Random.new(seed):NextNumber(0, 1) * totalWeight
	
	for _, data in adjustedChances do
		local itemName, chance = data[1], data[2]
		if roll < chance then
			return itemName
		end
		roll = roll - chance
	end
end

return LuckUtil
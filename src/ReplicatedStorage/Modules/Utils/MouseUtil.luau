--[[
Handles all of the mouse functions that are useful for raycasting and stuff
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService('Players')

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local MouseUtil = {}

function MouseUtil.GetUnitRay()
	local mouseLocation = UserInputService:GetMouseLocation()
	local unitRay = workspace.CurrentCamera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	return unitRay
end

function MouseUtil.GetMouseHit(unitRay, directionalDistance, excludeList)
	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude

	local fullExclusionList = { LocalPlayer.Character, workspace.Debris } -- filters character and debris folder
	if excludeList then
		for _, exclusion in pairs(excludeList) do
			table.insert(fullExclusionList, exclusion)
		end
	end

	castParams.FilterDescendantsInstances = fullExclusionList
	castParams.IgnoreWater = true

	local origin, direction = unitRay.Origin, unitRay.Direction * (directionalDistance or 1000) -- distance must be high

	local result = workspace:Raycast(origin, direction, castParams)
	return result or {
		Position = origin + direction
	}
end

-- gets a more accurate and more controllable mouse position using raycasting
function MouseUtil.GetMousePosition(unitRay, castParams, directionalDistance)
	if not castParams then
		castParams = RaycastParams.new()
		castParams.FilterType = Enum.RaycastFilterType.Exclude
		castParams.FilterDescendantsInstances = { LocalPlayer.Character, workspace.Debris } -- filters character and debris folder
		castParams.IgnoreWater = true
	end

	local origin, direction = unitRay.Origin, unitRay.Direction * (directionalDistance or 1000) -- distance must be high

	local result = workspace:Raycast(origin, direction, castParams)
	return result and result.Position or origin + direction
end

return MouseUtil
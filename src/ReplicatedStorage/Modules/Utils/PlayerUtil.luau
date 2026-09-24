local UserService = game:GetService("UserService")
local Players = game:GetService("Players")

local THUMBNAIL_PLACEHOLDER_IMAGE = "rbxassetid://0" -- replace with placeholder image
local PlayerUtil = {}

local DEVELOPERS = {
	1575095913
}

local NAME_COLORS =
	{
		Color3.new(253/255, 41/255, 67/255), -- BrickColor.new("Bright red").Color,
		Color3.new(1/255, 162/255, 255/255), -- BrickColor.new("Bright blue").Color,
		Color3.new(2/255, 184/255, 87/255), -- BrickColor.new("Earth green").Color,
		BrickColor.new("Bright violet").Color,
		BrickColor.new("Bright orange").Color,
		BrickColor.new("Bright yellow").Color,
		BrickColor.new("Light reddish violet").Color,
		BrickColor.new("Brick yellow").Color,
	}

local Caches = {
	GetUsernameFromUserId = {},
	GetUserIdFromUsername = {},
}

function PlayerUtil.IsDeveloper(userId)
	return table.find(DEVELOPERS, userId)
end

function PlayerUtil.GetPlayerThumbnail(userId, thumbnailType, thumbnailSize)
	if not thumbnailType then
		thumbnailType = Enum.ThumbnailType.HeadShot
	end
	if not thumbnailSize then
		thumbnailSize = Enum.ThumbnailSize.Size420x420
	end

	local content, isReady
	local success, err = pcall(function()
		content, isReady = Players:GetUserThumbnailAsync(userId, thumbnailType, thumbnailSize)
	end)

	return (success and (isReady and content or THUMBNAIL_PLACEHOLDER_IMAGE) or THUMBNAIL_PLACEHOLDER_IMAGE)
end

function PlayerUtil.GetInfoFromUserIds(userIds)
	local userInfos = nil
	local success, err = pcall(function()
		userInfos = UserService:GetUserInfosByUserIdsAsync(userIds)
	end)
	
	return userInfos
end

function PlayerUtil.GetUsernameFromUserId(userId)
	-- First, check if the cache contains the name
	if Caches.GetUsernameFromUserId[userId] then return Caches.GetUsernameFromUserId[userId] end
	-- Second, check if the user is already connected to the server
	local player = Players:GetPlayerByUserId(userId)
	if player then
		Caches.GetUsernameFromUserId[userId] = player.Name
		return player.Name
	end 
	-- If all else fails, send a request
	local name
	pcall(function ()
		name = Players:GetNameFromUserIdAsync(userId)
	end)
	Caches.GetUsernameFromUserId[userId] = name
	return name
end

function PlayerUtil.GetUniqueColor(username)
	local function getNameValue(pName)
		local value = 0
		for index = 1, #pName do
			local cValue = string.byte(string.sub(pName, index, index))
			local reverseIndex = #pName - index + 1
			if #pName%2 == 1 then
				reverseIndex = reverseIndex - 1
			end
			if reverseIndex%4 >= 2 then
				cValue = -cValue
			end
			value = value + cValue
		end
		return value
	end

	local color_offset = 0
	local predictedColor = NAME_COLORS[((getNameValue(username) + color_offset) % #NAME_COLORS) + 1]

	local r, g, b = predictedColor.R*255, predictedColor.G*255, predictedColor.B*255
	return Color3.fromRGB(math.round(r), math.round(g), math.round(b))
end

return PlayerUtil

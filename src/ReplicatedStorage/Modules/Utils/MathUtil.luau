--[[
Holds all of the necessary math functions and constants that are commonly used such as lerping
]]

local MathUtil = {}
MathUtil.TAU = math.pi * 2
MathUtil.EULER = 2.718281828459045 -- e
MathUtil.PHI = 1.618033988749895 -- golden ratio
MathUtil.G = 9.807 -- earth's gravitational constant

local ABBREVIATIONS = {
	"",
	"K", -- 4 digits
	"M", -- 7 eigits
	"B", -- 10 digits
	"T", -- 13 digits
	"Q", -- 16 digits
	"Qi", -- 19 digits
	"S", -- 22 digits
	"Sx", -- 25 digits
	"Sp", -- 25 digits
	"Oc", -- 28 digits
	"N", -- 31 digits
	"De", -- 34 digits
	"Un", -- 37 digits
	"Tr", -- 40 digits,
	"∞",
}

function MathUtil.InverseLerp(start, goal, mid)
	return (mid - start) / (goal - start)
end

function MathUtil.Lerp(start, goal, alpha) -- interpolates from start to goal with an alpha
	return start + (goal - start) * alpha
end

function MathUtil.Round(number, decimalPlaces, singular)
	if decimalPlaces == 1 and singular then
		return math.floor(number * 10 + 0.5) / 10
	end
	decimalPlaces = decimalPlaces or 2
	return math.floor(number * math.pow(10, decimalPlaces)) / math.pow(10, decimalPlaces)
end

function MathUtil.PreciseRandom(minimum, maximum)
	return math.random() * (maximum - minimum) + minimum
end

function MathUtil.SampleNormalDistribution(mean, standardDeviation)
	local u1, u2 = math.random(), math.random()
	local z0 = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	return mean + z0 * standardDeviation
end

function MathUtil.Abbreviate(value, maxValue : number?) -- shortens numbers by abbreviating them
	maxValue = maxValue or 1_000_000
	
	if value < maxValue then
		return value, false
	else
		for i = 1, #ABBREVIATIONS do
			if value < 10 ^ (i * 3) then
				if ABBREVIATIONS[i] == "∞" then
					return "∞", true
				else
					return math.floor(value / ((10 ^ ((i - 1) * 3)) / 100)) / (100) .. ABBREVIATIONS[i], true
				end
			elseif tostring(value) == "inf" then
				return "∞", true
			end
		end
	end
end

function MathUtil.AddCommasToNumber(value : number)
	local formatted = value
	while true do
		local k = nil
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
		if (k==0) then
			break
		end
	end
	return formatted
end

function MathUtil.FormatNumber(value : number, maxValue : number?)
	local abbreviatedValue, isAbbreviated = MathUtil.Abbreviate(value, maxValue)
	return (isAbbreviated and abbreviatedValue or MathUtil.AddCommasToNumber(value))
end

function MathUtil.RandomUnitVector()
	local sqrt = math.sqrt(-2 * math.log(math.random()))
	local angle = 2 * math.pi * math.random()

	return Vector3.new(
		sqrt * math.cos(angle),
		sqrt * math.sin(angle),
		math.sqrt(-2 * math.log(math.random())) * math.cos(2 * math.pi * math.random())
	).Unit
end

function MathUtil.RandomUpwardUnitVector(maxAngleDegrees)
	local maxAngleRadians = math.rad(maxAngleDegrees or 30) -- default 30 degrees cone

	local cosTheta = math.cos(maxAngleRadians)
	-- Pick a random cosine of the angle between up and vector (uniformly in cone)
	local z = math.random() * (1 - cosTheta) + cosTheta
	local theta = math.acos(z)

	local phi = math.random() * 2 * math.pi

	local x = math.sin(theta) * math.cos(phi)
	local y = math.cos(theta)
	local z = math.sin(theta) * math.sin(phi)

	return Vector3.new(x, y, z).Unit
end

return MathUtil
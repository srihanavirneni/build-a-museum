local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local MoneyParticleAsset = ReplicatedStorage.Assets.Models.MoneyParticle

local SettingsData = require(ReplicatedStorage.Modules.Data.PlayerSettings)
local SoundUtil = require(ReplicatedStorage.Modules.Utils.SoundUtil)
local MathUtil = require(ReplicatedStorage.Modules.Utils.MathUtil)
local Network = require(ReplicatedStorage.Packages.Network)
local PlayerEarnedMoneyEvent = Network:RemoteEvent("PlayerEarnedMoney")

local LocalPlayer = Players.LocalPlayer

local Particles = {}

local MIN_LAUNCH_DISTANCE, MAX_LAUNCH_DISTANCE = 4, 10
local RNG = Random.new(math.random(1, 9999))
local PARTICLE_DURATION = 1

local counter = 0
local function getId()
	counter = counter + 1
	return counter
end

local function quadBezier(t, p0, p1, p2)
	local l1 = MathUtil.Lerp(p0, p1, t)
	local l2 = MathUtil.Lerp(p1, p2, t)
	local quad = MathUtil.Lerp(l1, l2, t)
	return quad
end

local function cubicBezier(t, p0, p1, p2, p3)
	local l1 = MathUtil.Lerp(p0, p1, t)
	local l2 = MathUtil.Lerp(p1, p2, t)
	local l3 = MathUtil.Lerp(p2, p3, t)

	local q1 = MathUtil.Lerp(l1, l2, t)
	local q2 = MathUtil.Lerp(l2, l3, t)

	return MathUtil.Lerp(q1, q2, t)
end

local function tweenParticleToDestination(id : number, particle : BasePart, destination : Vector3, onComplete, controlPoint : Vector3, hrp)
	local particleOriginPosition : Vector3 = particle.Position

	local midpoint = (particleOriginPosition + destination) / 2
	local randomOffsetX, randomOffsetY, randomOffsetZ = math.random(-20, 20), math.random(-10, 10), math.random(-20, 20)

	local control : Vector3 = controlPoint or midpoint + Vector3.new(randomOffsetX, randomOffsetY, randomOffsetZ)

	local elapsed = 0

	local connection
	connection = RunService.PreRender:Connect(function(dt)
		if not Particles[id] then
			if connection then connection:Disconnect() end
			return
		end

		elapsed += dt
		local t = math.clamp(elapsed / (PARTICLE_DURATION), 0, 1)
		local position = quadBezier(t, particleOriginPosition, control, hrp and hrp.Position or destination)

		particle.Position = position

		if t >= 1 then
			if connection then connection:Disconnect() end
			onComplete(control)
		end
	end)

	if Particles[id] then
		Particles[id].Connection = connection
	end
end

local function tweenParticleToPlayer(id : number, particle : BasePart, previousMidpoint : Vector3)
	local character = LocalPlayer.Character
	local humanoidRootPart : BasePart = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoidRootPart then return end

	local tangent = particle.Position - previousMidpoint
	local control = particle.Position + tangent

	task.spawn(tweenParticleToDestination, id, particle, humanoidRootPart.Position, function()
		if not Particles[id] then return end

		if Particles[id].Connection then Particles[id].Connection:Disconnect() end

		Particles[id].Sleeping = true

		SoundUtil.Play(LocalPlayer, "MoneyCollect")

		if Particles[id].Entity then
			Particles[id].Entity.BillboardGui.Enabled = false
			task.delay(1, function()
				Particles[id].Entity:Destroy()
				Particles[id] = nil
			end)
		end
	end, control, humanoidRootPart)
end

local function onMoneyEarned(moneySource : Vector3, value : number)
	local moneyParticlesEnabled = SettingsData.GetLocalSetting("money particles")
	if not moneyParticlesEnabled then return end
	
	for i = 1, math.random(6,15) do
		local newMoneyParticle = MoneyParticleAsset:Clone()
		newMoneyParticle.Parent = workspace.Debris
		newMoneyParticle.Position = moneySource

		local particleId = getId()
		Particles[particleId] = { Entity = newMoneyParticle, Connection = nil }
		
		local randomUnitVector = MathUtil.RandomUpwardUnitVector()
		local destination : Vector3 = moneySource + (randomUnitVector * math.random(MIN_LAUNCH_DISTANCE, MAX_LAUNCH_DISTANCE))
		task.spawn(tweenParticleToDestination, particleId, newMoneyParticle, destination, function(previousMidpoint : Vector3)
			tweenParticleToPlayer(particleId, newMoneyParticle, previousMidpoint)
		end)
		task.wait(RNG:NextNumber(0.05, 0.125))
	end
end

PlayerEarnedMoneyEvent.OnClientEvent:Connect(onMoneyEarned)
LocalPlayer.CharacterAdded:Connect(function(character)
	for id, particle in Particles do
		if particle.Connection then particle.Connection:Disconnect() end
		if particle.Entity then particle.Entity:Destroy() end
		Particles[id] = nil
	end
end)
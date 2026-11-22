--!strict
-- Light snowfall (step 5.1, docs/04 section 5 "light falling snow particles").
-- One invisible emitter part follows this client's camera, so snow is only drawn where the
-- player is looking and costs the same on a small phone anywhere on the map. Purely visual.
-- Numbers in Config.Snow. Turns off underground (Naughty Jail) where a roof is overhead.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

-- Soft round puff that ships with the client (no upload needed); tiny, it reads as a flake.
local FLAKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local SnowController = {}

local function buildEmitter(): (BasePart, ParticleEmitter)
	local snow = Config.Snow
	local part = Instance.new("Part")
	part.Name = "SnowEmitter"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(snow.AreaStuds, 1, snow.AreaStuds)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = FLAKE_TEXTURE
	emitter.Color = ColorSequence.new(Color3.fromRGB(245, 250, 255))
	emitter.LightEmission = 0.3
	emitter.LightInfluence = 0.6
	emitter.Rate = snow.Rate
	emitter.Lifetime = NumberRange.new(snow.LifetimeSeconds)
	emitter.Speed = NumberRange.new(snow.FallSpeed.min, snow.FallSpeed.max)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Size = NumberSequence.new(snow.FlakeSize.min, snow.FlakeSize.max)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.15),
		NumberSequenceKeypoint.new(0.85, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = part
	return part, emitter
end

function SnowController:Init() end

function SnowController:Start()
	local part, emitter = buildEmitter()
	part.Parent = workspace.CurrentCamera -- local to this client, never replicated
	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		if part.Parent ~= camera then
			part.Parent = camera -- the camera object can be replaced (e.g. on respawn)
		end
		local position = camera.CFrame.Position
		local underground = position.Y < Config.Snow.OffBelowY
		emitter.Enabled = not underground
		-- Blizzard (6.2): much heavier snow while one blows (server time in a Workspace attribute).
		local endsAt = workspace:GetAttribute("BlizzardEndsAt")
		local blizzard = type(endsAt) == "number" and workspace:GetServerTimeNow() < endsAt
		emitter.Rate = Config.Snow.Rate * (if blizzard then Config.DevProducts.Blizzard.snowMultiplier else 1)
		part.CFrame = CFrame.new(position + Vector3.new(0, Config.Snow.HeightAboveCamera, 0))
	end)
end

return SnowController

--!strict
-- Builds the placeholder model for one toy from ServerStorage/Templates/Toy: rarity colour,
-- mutation look, and the name/rarity tag. Used for toys on the unwrap table and on shelves.
-- PLACEHOLDER toy shape until Phase 5 (real toy meshes). The mutation looks (step 4.3) follow
-- docs/01 section 6 "Look" column and are layers on top of the toy, so they carry over to meshes:
--   Frosted      icy blue Ice + drifting sparkles
--   Gingerbread  brown, with a white icing cap on top (a part; Phase 5 may swap it for a texture)
--   Glowing      Neon in the rarity colour + outline (Highlight) + soft light
--   Golden       gold Foil, shiny + a warm glint and slow twinkles

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

-- Built-in sparkle texture (ships with the client, so no upload is needed).
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local FROST_COLOR = Color3.fromRGB(170, 225, 255)
local GINGER_COLOR = Color3.fromRGB(150, 90, 45)
local ICING_COLOR = Color3.fromRGB(250, 250, 245)
local GOLD_COLOR = Color3.fromRGB(255, 200, 60)

local ICING_THICKNESS = 0.22 -- studs
local ICING_OVERHANG = 0.06 -- studs past each side, so it reads as a drip edge
local ICING_BALL_HEIGHT = 0.55 -- round toys: icing sits this fraction of the radius above centre
local GLOW_OUTLINE_WHITE = 0.6 -- outline = rarity colour this far towards white, so it shows on Neon
local GLOW_RANGE = 8
local GOLD_REFLECTANCE = 0.25

local ToyModel = {}

local function template(): Model?
	local templates = ServerStorage:FindFirstChild("Templates")
	local found = templates and templates:FindFirstChild("Toy")
	if found and found:IsA("Model") and found.PrimaryPart then
		return found
	end
	return nil
end

local function sparkles(body: BasePart, color: Color3, rate: number, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MutationSparkles"
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(0.3, 0.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = body
end

local function light(body: BasePart, color: Color3, range: number, brightness: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Name = "MutationLight"
	pointLight.Color = color
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Parent = body
end

-- White icing on top of the body, welded so it moves with the toy. On a round body it is a
-- disc where the sphere is still wide (ICING_BALL_HEIGHT of the radius up); on a box, a slab.
local function icingCap(model: Model, body: BasePart)
	local icing = Instance.new("Part")
	icing.Name = "Icing"
	if body:IsA("Part") and body.Shape == Enum.PartType.Ball then
		local radius = body.Size.X / 2
		local height = radius * ICING_BALL_HEIGHT
		local width = 2 * math.sqrt(radius * radius - height * height) + ICING_OVERHANG * 2
		icing.Shape = Enum.PartType.Cylinder -- a cylinder's axis is X: turn it upright below
		icing.Size = Vector3.new(ICING_THICKNESS, width, width)
		icing.CFrame = body.CFrame * CFrame.new(0, height, 0) * CFrame.Angles(0, 0, math.rad(90))
	else
		icing.Size = Vector3.new(body.Size.X + ICING_OVERHANG * 2, ICING_THICKNESS, body.Size.Z + ICING_OVERHANG * 2)
		icing.CFrame = body.CFrame * CFrame.new(0, body.Size.Y / 2 - ICING_THICKNESS / 2 + 0.01, 0)
	end
	icing.Color = ICING_COLOR
	icing.Material = Enum.Material.SmoothPlastic
	icing.Anchored = body.Anchored
	icing.CanCollide = false
	icing.CanQuery = false
	icing.CanTouch = false
	icing.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = icing
	weld.Parent = icing
	icing.Parent = model
end

local function applyMutation(model: Model, body: BasePart, mutation: Types.Mutation, rarityColor: Color3)
	if mutation == "Frosted" then
		body.Color = FROST_COLOR
		body.Material = Enum.Material.Ice
		sparkles(body, Color3.fromRGB(220, 240, 255), 5, 0.35)
	elseif mutation == "Gingerbread" then
		body.Color = GINGER_COLOR
		body.Material = Enum.Material.Sand
		icingCap(model, body)
	elseif mutation == "Glowing" then
		body.Material = Enum.Material.Neon -- keeps the rarity colour
		light(body, rarityColor, GLOW_RANGE, 1.5)
		-- Highlight: max 255 shown per client (docs); Glowing is 2% of toys, so far below that.
		local outline = Instance.new("Highlight")
		outline.Name = "MutationOutline"
		outline.FillTransparency = 1
		outline.OutlineColor = rarityColor:Lerp(Color3.new(1, 1, 1), GLOW_OUTLINE_WHITE)
		outline.OutlineTransparency = 0
		outline.DepthMode = Enum.HighlightDepthMode.Occluded
		outline.Adornee = model
		outline.Parent = model
	elseif mutation == "Golden" then
		body.Color = GOLD_COLOR
		body.Material = Enum.Material.Foil
		body.Reflectance = GOLD_REFLECTANCE
		light(body, Color3.fromRGB(255, 210, 120), 6, 0.8)
		sparkles(body, Color3.fromRGB(255, 230, 150), 1.5, 0.5)
	end
end

-- True if the template exists. Services call this in Init to warn early.
function ToyModel.isReady(): boolean
	return template() ~= nil
end

-- A new, unparented toy model, or nil if the template is missing.
function ToyModel.build(toy: Types.ToyDef, mutation: Types.Mutation?): Model?
	local source = template()
	if not source then
		return nil
	end
	local model = source:Clone()
	local body = model.PrimaryPart
	if not body then
		model:Destroy()
		return nil
	end
	local rarityColor = Config.Rarities[toy.rarity].color
	body.Color = rarityColor
	if mutation then
		applyMutation(model, body, mutation, rarityColor)
		model:SetAttribute("Mutation", mutation)
	end
	local nameLabel = body:FindFirstChild("ToyName", true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = if mutation then `{mutation} {toy.name}` else toy.name
	end
	local rarityLabel = body:FindFirstChild("Rarity", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Text = toy.rarity
		rarityLabel.TextColor3 = rarityColor
	end
	return model
end

return table.freeze(ToyModel)

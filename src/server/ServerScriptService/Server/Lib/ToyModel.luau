--!strict
-- Builds the model for one toy: the toy's mesh, mutation look, and the name/rarity tag. Used for
-- toys on the unwrap table and on shelves.
-- Step 5.4: each toy has a generated mesh in ServerStorage/ToyMeshes/<toy id> (place file): a Model
-- whose parts are centred on the origin, with a BoxSize attribute (its bounding box). The
-- template's Body becomes an invisible box of that size, so the tag and the prompt sit on it and
-- callers that stand the toy on a shelf by Body.Size keep working. A toy with no mesh falls back
-- to the old placeholder ball in its rarity colour.
-- Mutation looks (docs/01 section 6 "Look" column) are layers on top of the toy. On a mesh, the
-- texture comes off and the whole silhouette takes the mutation's material:
--   Frosted      icy blue Ice + drifting sparkles
--   Gingerbread  brown, with white icing trim (an outline on a mesh, a cap on the placeholder)
--   Glowing      Neon in the rarity colour + outline (Highlight) + soft light
--   Golden       gold Foil, shiny + a warm glint and slow twinkles

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

-- Built-in sparkle texture (ships with the client, so no upload is needed).
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local MESH_FOLDER = "ToyMeshes"

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

local function meshFor(toyId: string): Model?
	local folder = ServerStorage:FindFirstChild(MESH_FOLDER)
	local found = folder and folder:FindFirstChild(toyId)
	if found and found:IsA("Model") and typeof(found:GetAttribute("BoxSize")) == "Vector3" then
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

-- An outline around the whole toy. Highlights: max 255 shown per client (docs); only Glowing (2%)
-- and Gingerbread meshes (5%) use one, far below that.
local function outline(model: Model, color: Color3, name: string)
	local highlight = Instance.new("Highlight")
	highlight.Name = name
	highlight.FillTransparency = 1
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
end

-- White icing on top of the placeholder ball, welded so it moves with the toy: a disc where the
-- sphere is still wide (ICING_BALL_HEIGHT of the radius up).
local function icingCap(model: Model, body: BasePart)
	local icing = Instance.new("Part")
	icing.Name = "Icing"
	local radius = body.Size.X / 2
	local height = radius * ICING_BALL_HEIGHT
	local width = 2 * math.sqrt(radius * radius - height * height) + ICING_OVERHANG * 2
	icing.Shape = Enum.PartType.Cylinder -- a cylinder's axis is X: turn it upright below
	icing.Size = Vector3.new(ICING_THICKNESS, width, width)
	icing.CFrame = body.CFrame * CFrame.new(0, height, 0) * CFrame.Angles(0, 0, math.rad(90))
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

-- Paints every visible part of the toy in one material (a mesh loses its texture first, or the
-- texture would hide the colour).
local function paint(visuals: { BasePart }, color: Color3, material: Enum.Material, reflectance: number?)
	for _, part in visuals do
		if part:IsA("MeshPart") then
			part.TextureID = ""
		end
		part.Color = color
		part.Material = material
		part.Reflectance = reflectance or 0
	end
end

-- `body` carries the effects (sparkles, light); `visuals` are the parts you see.
local function applyMutation(model: Model, body: BasePart, visuals: { BasePart }, isMesh: boolean, mutation: Types.Mutation, rarityColor: Color3)
	if mutation == "Frosted" then
		paint(visuals, FROST_COLOR, Enum.Material.Ice)
		sparkles(body, Color3.fromRGB(220, 240, 255), 5, 0.35)
	elseif mutation == "Gingerbread" then
		paint(visuals, GINGER_COLOR, Enum.Material.Sand)
		if isMesh then
			outline(model, ICING_COLOR, "IcingTrim")
		else
			icingCap(model, body)
		end
	elseif mutation == "Glowing" then
		paint(visuals, rarityColor, Enum.Material.Neon)
		light(body, rarityColor, GLOW_RANGE, 1.5)
		outline(model, rarityColor:Lerp(Color3.new(1, 1, 1), GLOW_OUTLINE_WHITE), "MutationOutline")
	elseif mutation == "Golden" then
		paint(visuals, GOLD_COLOR, Enum.Material.Foil, GOLD_REFLECTANCE)
		light(body, Color3.fromRGB(255, 210, 120), 6, 0.8)
		sparkles(body, Color3.fromRGB(255, 230, 150), 1.5, 0.5)
	end
end

-- Puts the toy's mesh parts around `body` (welded, same anchoring) and turns body into an
-- invisible box the mesh's size. Returns the mesh parts.
local function attachMesh(model: Model, body: BasePart, mesh: Model): { BasePart }
	local parts: { BasePart } = {}
	if body:IsA("Part") then
		body.Shape = Enum.PartType.Block
	end
	body.Size = mesh:GetAttribute("BoxSize") :: Vector3
	body.Transparency = 1
	for _, source in mesh:GetDescendants() do
		if source:IsA("BasePart") then
			local part = source:Clone()
			part:ClearAllChildren() -- no stray welds or scripts from the source
			part.CFrame = body.CFrame * source.CFrame -- source parts are laid out around the origin
			part.Anchored = body.Anchored
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			if not body.Anchored then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = body
				weld.Part1 = part
				weld.Parent = part
			end
			part.Parent = model
			table.insert(parts, part)
		end
	end
	return parts
end

-- Copies the meshes to ReplicatedStorage/ToyMeshes at boot (step 5.5), so the client's unwrap
-- reveal can spin the toy. Done at runtime because ReplicatedStorage is a Script Sync folder,
-- where the place file must not keep non-script instances. Meshes are looks only: nothing to steal.
function ToyModel.publishMeshes()
	local source = ServerStorage:FindFirstChild(MESH_FOLDER)
	if not source or ReplicatedStorage:FindFirstChild(MESH_FOLDER) then
		return
	end
	source:Clone().Parent = ReplicatedStorage
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
	local mesh = meshFor(toy.id)
	local visuals: { BasePart }
	if mesh then
		visuals = attachMesh(model, body, mesh)
	else
		body.Color = rarityColor -- placeholder ball
		visuals = { body }
	end
	if mutation then
		applyMutation(model, body, visuals, mesh ~= nil, mutation, rarityColor)
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

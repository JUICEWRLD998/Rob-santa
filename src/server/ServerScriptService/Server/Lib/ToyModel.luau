--!strict
-- Builds the placeholder model for one toy from ServerStorage/Templates/Toy: rarity colour,
-- mutation look, and the name/rarity tag. Used for toys on the unwrap table and on shelves.
-- PLACEHOLDER looks until Phase 5 (real toy meshes, docs/01 section 6 "Look" column).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type MutationLook = { color: Color3?, material: Enum.Material, light: boolean }
local MUTATION_LOOKS: { [string]: MutationLook } = {
	Frosted = { color = Color3.fromRGB(170, 225, 255), material = Enum.Material.Ice, light = false },
	Gingerbread = { color = Color3.fromRGB(150, 90, 45), material = Enum.Material.Sand, light = false },
	Glowing = { color = nil, material = Enum.Material.Neon, light = true },
	Golden = { color = Color3.fromRGB(255, 200, 60), material = Enum.Material.Foil, light = false },
}
local GLOW_RANGE = 8

local ToyModel = {}

local function template(): Model?
	local templates = ServerStorage:FindFirstChild("Templates")
	local found = templates and templates:FindFirstChild("Toy")
	if found and found:IsA("Model") and found.PrimaryPart then
		return found
	end
	return nil
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
		local look = MUTATION_LOOKS[mutation]
		if look then
			body.Material = look.material
			if look.color then
				body.Color = look.color
			end
			if look.light then
				local light = Instance.new("PointLight")
				light.Color = rarityColor
				light.Range = GLOW_RANGE
				light.Parent = body
			end
		end
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

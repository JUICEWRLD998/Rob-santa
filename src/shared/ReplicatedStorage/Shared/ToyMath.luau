--!strict
-- What a toy is worth. Pure functions over Config, shared so the server pays and the UI shows
-- exactly the same numbers. docs/01-GAME-DESIGN.md section 6:
--   income per second = rarity income x mutation multiplier
--   sell price        = rarity sell price (45 s of income) x mutation multiplier

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Toys = require(ReplicatedStorage.Shared.Toys)
local Types = require(ReplicatedStorage.Shared.Types)

local ToyMath = {}

-- 1 for no mutation (or an unknown name).
function ToyMath.mutationMultiplier(mutation: Types.Mutation?): number
	if mutation == nil then
		return 1
	end
	for _, entry in Config.Mutations do
		if entry.name == mutation then
			return entry.incomeMultiplier
		end
	end
	return 1
end

-- Coins per second while shelved. 0 for an unknown toy id.
function ToyMath.incomePerSecond(toyId: string, mutation: Types.Mutation?): number
	local toy = Toys.get(toyId)
	if not toy then
		return 0
	end
	return Config.Rarities[toy.rarity].incomePerSecond * ToyMath.mutationMultiplier(mutation)
end

-- Whole coins paid when sold. 0 for an unknown toy id.
function ToyMath.sellPrice(toyId: string, mutation: Types.Mutation?): number
	local toy = Toys.get(toyId)
	if not toy then
		return 0
	end
	return math.floor(Config.Rarities[toy.rarity].sellPrice * ToyMath.mutationMultiplier(mutation))
end

return table.freeze(ToyMath)

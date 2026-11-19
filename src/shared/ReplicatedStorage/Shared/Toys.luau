--!strict
-- The toy list (docs/01-GAME-DESIGN.md section 6). Original names only.
-- `id` is the save key: never change an id after launch. `name` can change freely.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local LIST: { Types.ToyDef } = {
	{ id = "wool_sock", name = "Wool Sock", rarity = "Common" },
	{ id = "candy_cane", name = "Candy Cane", rarity = "Common" },
	{ id = "rubber_duck", name = "Rubber Duck", rarity = "Common" },
	{ id = "teddy_bear", name = "Teddy Bear", rarity = "Uncommon" },
	{ id = "yo_yo", name = "Yo-Yo", rarity = "Uncommon" },
	{ id = "toy_drum", name = "Toy Drum", rarity = "Uncommon" },
	{ id = "toy_train", name = "Toy Train", rarity = "Rare" },
	{ id = "snow_globe", name = "Snow Globe", rarity = "Rare" },
	{ id = "rc_sled", name = "RC Sled", rarity = "Rare" },
	{ id = "robot_buddy", name = "Robot Buddy", rarity = "Epic" },
	{ id = "rocket_skis", name = "Rocket Skis", rarity = "Epic" },
	{ id = "dragon_kite", name = "Dragon Kite", rarity = "Epic" },
	{ id = "golden_rocking_horse", name = "Golden Rocking Horse", rarity = "Legendary" },
	{ id = "crystal_nutcracker", name = "Crystal Nutcracker", rarity = "Legendary" },
	{ id = "star_of_the_north", name = "Star of the North", rarity = "Mythic" },
	{ id = "santas_pocket_watch", name = "Santa's Pocket Watch", rarity = "Mythic" },
}

local byId: { [string]: Types.ToyDef } = {}
local byRarity: { [Types.Rarity]: { Types.ToyDef } } = {}
for _, toy in LIST do
	assert(byId[toy.id] == nil, `duplicate toy id {toy.id}`)
	table.freeze(toy)
	byId[toy.id] = toy
	local bucket = byRarity[toy.rarity]
	if not bucket then
		bucket = {}
		byRarity[toy.rarity] = bucket
	end
	table.insert(bucket, toy)
end

local Toys = {}

function Toys.all(): { Types.ToyDef }
	return LIST
end

function Toys.get(id: string): Types.ToyDef?
	return byId[id]
end

function Toys.ofRarity(rarity: Types.Rarity): { Types.ToyDef }
	return byRarity[rarity] or {}
end

return table.freeze(Toys)

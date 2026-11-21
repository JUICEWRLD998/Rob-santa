--!strict
-- Everything the Gadget Shop sells (step 4.2), as pure functions over Config, shared so the server
-- charges and the shop screen shows exactly the same numbers (like ToyMath).
-- Every item has a level: 0 = not bought. Boots go to 6, a zone or the Snowball to 1.
-- The server mirrors each level onto the Player as an attribute (attributeName) for the UI.
-- docs/01-GAME-DESIGN.md sections 6 (shelves), 7 (upgrades) and 2 (zones).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type ItemId = "Boots" | "ExtraWrap" | "QuietSteps" | "Snowball" | "Shelf" | "Zone2" | "Zone3"

export type Item = {
	id: ItemId,
	name: string,
	maxLevel: number,
	requires: ItemId?, -- must own at least level 1 of this first
	-- What the item does, for the card. `level` is the level owned now.
	describe: (level: number) -> string,
}

local upgrades = Config.Upgrades
local shelves = Config.Shelves

local function oneDecimal(value: number): string
	return string.format("%.1f", value)
end

local ITEMS: { Item } = {
	{
		id = "Boots",
		name = "Boots",
		maxLevel = #upgrades.Boots.costs,
		describe = function(level: number): string
			return `Run faster: +{oneDecimal(upgrades.Boots.speedPerLevel)} speed per level. Now +{oneDecimal(level * upgrades.Boots.speedPerLevel)}`
		end,
	},
	{
		id = "ExtraWrap",
		name = "Extra Wrap",
		maxLevel = #upgrades.ExtraWrap.costs,
		describe = function(level: number): string
			local now = if level > 0 then upgrades.ExtraWrap.wrapsByLevel[level] else Config.Disguise.WrapsPerTrip
			return `More gift-box disguises per trip. Now {now}`
		end,
	},
	{
		id = "QuietSteps",
		name = "Quiet Steps",
		maxLevel = #upgrades.QuietSteps.costs,
		describe = function(level: number): string
			local percent = math.round(upgrades.QuietSteps.visionReductionPerLevel * 100)
			return `Elves and cameras spot you {percent}% later per level. Now {level * percent}%`
		end,
	},
	{
		id = "Snowball",
		name = "Snowball",
		maxLevel = 1,
		describe = function(_level: number): string
			-- Throwing arrives in step 6.4; say so, so nobody buys it expecting it to work now.
			return `Throw at an elf to stun it for {upgrades.Snowball.elfStunSeconds} s. Throwing unlocks in a later update`
		end,
	},
	{
		id = "Shelf",
		name = "Extra Shelf",
		maxLevel = shelves.Max - shelves.Start,
		describe = function(level: number): string
			return `One more shelf for a toy that earns. You have {shelves.Start + level} of {shelves.Max}`
		end,
	},
	{
		id = "Zone2",
		name = Config.Zones[2].name,
		maxLevel = 1,
		describe = function(_level: number): string
			return "Zone 2: better presents, more elves, a snowman camera"
		end,
	},
	{
		id = "Zone3",
		name = Config.Zones[3].name,
		maxLevel = 1,
		requires = "Zone2",
		describe = function(_level: number): string
			return "Zone 3: Epic and Legendary presents, and the Head Elf"
		end,
	},
}

local byId: { [string]: Item } = {}
for _, item in ITEMS do
	byId[item.id] = item
end

local ShopCatalog = {}

ShopCatalog.Items = ITEMS -- in the order the shop shows them

-- nil for an unknown id (anything the client sends must go through this).
function ShopCatalog.get(id: any): Item?
	return if type(id) == "string" then byId[id] else nil
end

-- Coins for the NEXT level when `level` is owned now. nil when it's already maxed.
function ShopCatalog.cost(id: ItemId, level: number): number?
	local item = byId[id]
	if not item or level >= item.maxLevel or level < 0 then
		return nil
	end
	if id == "Boots" then
		return upgrades.Boots.costs[level + 1]
	elseif id == "ExtraWrap" then
		return upgrades.ExtraWrap.costs[level + 1]
	elseif id == "QuietSteps" then
		return upgrades.QuietSteps.costs[level + 1]
	elseif id == "Snowball" then
		return upgrades.Snowball.cost
	elseif id == "Shelf" then
		-- docs/01 section 6: 500 x 1.8 ^ (shelves bought)
		return math.floor(shelves.CostBase * shelves.CostGrowth ^ level)
	elseif id == "Zone2" then
		return Config.Zones[2].unlockCost
	elseif id == "Zone3" then
		return Config.Zones[3].unlockCost
	end
	return nil
end

-- The Player attribute holding the owned level of `id` (set by the server only).
function ShopCatalog.attributeName(id: ItemId): string
	return `Shop_{id}`
end

return table.freeze(ShopCatalog)

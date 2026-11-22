--!strict
-- The Robux store (step 6.2, docs/01-GAME-DESIGN.md section 10), shared like ShopCatalog so the
-- server grants and the store screen shows exactly the same numbers. IDs and tunables are in
-- Config.GamePasses / Config.DevProducts. Real prices come from Creator Hub at runtime.
-- Owned passes are mirrored onto the Player as attributes (passAttribute) by MonetizationService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Toys = require(ReplicatedStorage.Shared.Toys)

export type PassKey = "Vip" | "BigSack" | "SpeedBoots" | "WrapMaster"
export type ProductKey =
	"BailOut"
	| "LuckyWrap"
	| "Blizzard"
	| "CoinPackSmall"
	| "CoinPackMedium"
	| "CoinPackLarge"
	| "AdventCatchUp"

export type Entry = {
	key: string,
	kind: "Pass" | "Product",
	id: number,
	fallbackPrice: number,
	name: string,
	-- What it does, for the store card. `income` = the player's coins per second now.
	describe: (income: number) -> string,
}

local StoreCatalog = {}

local passes = Config.GamePasses
local products = Config.DevProducts

local PASS_KEYS: { PassKey } = { "Vip", "BigSack", "SpeedBoots", "WrapMaster" }
StoreCatalog.PassKeys = PASS_KEYS

-- Player attribute that is true while the player owns a pass.
function StoreCatalog.passAttribute(key: PassKey): string
	return `Pass_{key}`
end

local function withCommas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return if formatted:sub(1, 1) == "," then formatted:sub(2) else formatted
end
StoreCatalog.withCommas = withCommas

-- Coins a pack gives right now: incomeSeconds of current income, at least minCoins, rounded down
-- to 2 significant figures so the number reads cleanly ("12,000", not "12,347").
function StoreCatalog.coinPackAmount(key: ProductKey, incomePerSecond: number): number
	local pack = (products :: any)[key]
	if type(pack) ~= "table" or type(pack.incomeSeconds) ~= "number" then
		return 0
	end
	local income = if incomePerSecond == incomePerSecond and incomePerSecond > 0 then incomePerSecond else 0
	local raw = math.max(pack.minCoins, income * pack.incomeSeconds)
	local digits = math.floor(math.log10(raw)) + 1
	local unit = 10 ^ math.max(0, digits - 2)
	return math.max(pack.minCoins, math.floor(raw / unit) * unit)
end

-- The Lucky Wrap odds, shown before buying (a paid random item; Roblox requires this).
function StoreCatalog.luckyWrapOdds(): string
	local parts: { string } = {}
	for _, mutation in Config.Mutations do
		table.insert(parts, `{mutation.name} {mutation.chance * 100}%`)
	end
	local mythics = #Toys.ofRarity("Mythic")
	return `Your next unwrap is one rarity higher (a Common present gives an Uncommon toy ... a Legendary gives a Mythic). `
		.. `Odds: each toy of that rarity has an equal chance ({mythics} Mythic toys). Mutations: {table.concat(parts, ", ")}. `
		.. `A Mythic present stays Mythic and keeps the wrap.`
end

local function coinPack(key: ProductKey, name: string): Entry
	local pack = (products :: any)[key]
	return {
		key = key,
		kind = "Product",
		id = pack.id,
		fallbackPrice = pack.price,
		name = name,
		describe = function(income: number): string
			return `{withCommas(StoreCatalog.coinPackAmount(key, income))} coins right now (grows with your income)`
		end,
	}
end

-- In the order the store screen lists them. Bail Out is sold from the jail panel and Advent
-- Catch-up from the Advent board (6.3), so they are not here.
StoreCatalog.Entries = {
	{
		key = "Vip",
		kind = "Pass",
		id = passes.Vip.id,
		fallbackPrice = passes.Vip.price,
		name = "VIP",
		describe = function(): string
			return `x{passes.Vip.coinMultiplier} coins forever, {Config.Offline.MaxHoursVip}h of offline earnings, gold name tag`
		end,
	},
	{
		key = "BigSack",
		kind = "Pass",
		id = passes.BigSack.id,
		fallbackPrice = passes.BigSack.price,
		name = "Big Sack",
		describe = function(): string
			return `Carry {Config.Presents.CarryCapacityBigSack} presents at once`
		end,
	},
	{
		key = "SpeedBoots",
		kind = "Pass",
		id = passes.SpeedBoots.id,
		fallbackPrice = passes.SpeedBoots.price,
		name = "Speed Boots",
		describe = function(): string
			return `Run faster: +{passes.SpeedBoots.extraWalkSpeed} speed on top of upgrades`
		end,
	},
	{
		key = "WrapMaster",
		kind = "Pass",
		id = passes.WrapMaster.id,
		fallbackPrice = passes.WrapMaster.price,
		name = "Wrap Master",
		describe = function(): string
			local wrap = passes.WrapMaster
			return `+{wrap.extraWraps} disguises per trip and a {wrap.cooldownReductionSeconds}s faster cooldown`
		end,
	},
	{
		key = "Blizzard",
		kind = "Product",
		id = products.Blizzard.id,
		fallbackPrice = products.Blizzard.price,
		name = "Blizzard",
		describe = function(): string
			local blizzard = products.Blizzard
			return `Whole server: for {blizzard.durationSeconds}s every elf sees half as far and moves slower. Your name goes on the banner!`
		end,
	},
	{
		key = "LuckyWrap",
		kind = "Product",
		id = products.LuckyWrap.id,
		fallbackPrice = products.LuckyWrap.price,
		name = "Lucky Wrap",
		describe = function(): string
			return StoreCatalog.luckyWrapOdds()
		end,
	},
	coinPack("CoinPackSmall", "Coins (Small)"),
	coinPack("CoinPackMedium", "Coins (Medium)"),
	coinPack("CoinPackLarge", "Coins (Large)"),
} :: { Entry }

return table.freeze(StoreCatalog)

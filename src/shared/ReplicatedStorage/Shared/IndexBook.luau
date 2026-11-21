--!strict
-- The Collection Index (step 4.4), as pure functions over Config and the saved `index` table,
-- shared so the server pays and the Index screen shows exactly the same numbers (like ToyMath).
-- An entry is one toy in one form: plain, or with one mutation. Saved keys: "toyId" for plain,
-- "toyId:Mutation" for a mutated find. docs/01-GAME-DESIGN.md section 6 "Collection Index".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ToyMath = require(ReplicatedStorage.Shared.ToyMath)
local Toys = require(ReplicatedStorage.Shared.Toys)
local Types = require(ReplicatedStorage.Shared.Types)

export type Found = { [string]: boolean }
export type Page = { zone: number, name: string, toys: { Types.ToyDef } }

local IndexBook = {}

-- Mutations from most to least common (Frosted first), the order the Index shows them.
local MUTATIONS: { Types.Mutation } = {}
for i = #Config.Mutations, 1, -1 do
	table.insert(MUTATIONS, Config.Mutations[i].name)
end
IndexBook.Mutations = table.freeze(MUTATIONS)

local PAGES: { Page } = {}
for _, pageDef in Config.Index.Pages do
	local toys: { Types.ToyDef } = {}
	for _, rarity in pageDef.rarities do
		for _, toy in Toys.ofRarity(rarity :: Types.Rarity) do
			table.insert(toys, toy)
		end
	end
	local zone = Config.Zones[pageDef.zone]
	table.insert(PAGES, table.freeze({
		zone = pageDef.zone,
		name = if zone then zone.name else `Zone {pageDef.zone}`,
		toys = table.freeze(toys),
	}))
end
IndexBook.Pages = table.freeze(PAGES)

local function isMutation(value: any): boolean
	return table.find(MUTATIONS, value) ~= nil
end

function IndexBook.key(toyId: string, mutation: Types.Mutation?): string
	return if mutation then `{toyId}:{mutation}` else toyId
end

-- True for a key that names a real toy (and a real mutation). Anything else is ignored.
function IndexBook.isValidKey(key: any): boolean
	if type(key) ~= "string" then
		return false
	end
	local toyId, mutation = string.match(key, "^([^:]+):(.+)$")
	if toyId then
		return Toys.get(toyId) ~= nil and isMutation(mutation)
	end
	return Toys.get(key) ~= nil
end

function IndexBook.isFound(found: Found, toyId: string, mutation: Types.Mutation?): boolean
	return found[IndexBook.key(toyId, mutation)] == true
end

-- How many forms of this toy are found (0 to 1 + number of mutations).
function IndexBook.formsFound(found: Found, toyId: string): number
	local count = if IndexBook.isFound(found, toyId, nil) then 1 else 0
	for _, mutation in MUTATIONS do
		if IndexBook.isFound(found, toyId, mutation :: Types.Mutation) then
			count += 1
		end
	end
	return count
end

-- Does this toy count towards its page? See Config.Index.PageNeedsAllMutations.
function IndexBook.toyDone(found: Found, toyId: string): boolean
	local forms = IndexBook.formsFound(found, toyId)
	return if Config.Index.PageNeedsAllMutations then forms == 1 + #MUTATIONS else forms > 0
end

function IndexBook.pageProgress(found: Found, page: Page): (number, number)
	local done = 0
	for _, toy in page.toys do
		if IndexBook.toyDone(found, toy.id) then
			done += 1
		end
	end
	return done, #page.toys
end

function IndexBook.isPageComplete(found: Found, page: Page): boolean
	local done, total = IndexBook.pageProgress(found, page)
	return total > 0 and done == total
end

function IndexBook.completedPages(found: Found): number
	local count = 0
	for _, page in PAGES do
		if IndexBook.isPageComplete(found, page) then
			count += 1
		end
	end
	return count
end

-- Shelf income multiplier from completed pages: 1.05 for one page, 1.10 for two, ...
function IndexBook.incomeMultiplier(found: Found): number
	return 1 + IndexBook.completedPages(found) * Config.Index.ZoneCompleteIncomeBonus
end

-- Coins for finding this entry for the first time.
function IndexBook.discoveryBonus(toyId: string, mutation: Types.Mutation?): number
	return math.floor(Config.Index.DiscoveryBonusSeconds * ToyMath.incomePerSecond(toyId, mutation))
end

-- (entries found, total entries). Every toy x (plain + each mutation).
function IndexBook.count(found: Found): (number, number)
	local done = 0
	for key, value in found do
		if value == true and IndexBook.isValidKey(key) then
			done += 1
		end
	end
	return done, #Toys.all() * (1 + #MUTATIONS)
end

return table.freeze(IndexBook)

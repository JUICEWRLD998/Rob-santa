--!strict
-- The Collection Index (step 4.4, docs/01-GAME-DESIGN.md section 6). Records every toy x mutation
-- a player unwraps in their saved `index`. A first find pays a one-time coin bonus; completing a
-- zone's page adds +5% shelf income for good (ShelfService reads it through IndexBook).
-- Rules and numbers live in Shared/IndexBook + Config.Index, so the Index screen agrees.
-- The client only receives the list of found keys (IndexSync); it can't add entries.
-- The page-complete badge comes later (build plan: "badge comes later").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IndexBook = require(ReplicatedStorage.Shared.IndexBook)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ShelfService = require(script.Parent.ShelfService)

local IndexService = {}

local indexSync: RemoteEvent
local notify: RemoteEvent

local function withCommas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return if formatted:sub(1, 1) == "," then formatted:sub(2) else formatted
end

-- Sends the full list of found keys. Small (80 entries at most), so no diffing.
local function sync(player: Player, found: IndexBook.Found)
	local keys = {}
	for key, value in found do
		if value == true then
			table.insert(keys, key)
		end
	end
	indexSync:FireClient(player, keys)
end

-- Saves from before step 4.4 have toys but an empty index: count the toys they already own as
-- found (no coins for these, they were not new finds).
local function backfill(data: DataService.PlayerData)
	for _, toy in data.shelves do
		data.index[IndexBook.key(toy.toyId, toy.mutation :: Types.Mutation?)] = true
	end
	for _, toy in data.tableToys do
		data.index[IndexBook.key(toy.toyId, toy.mutation :: Types.Mutation?)] = true
	end
	-- Drop anything that no longer names a real toy or mutation (renamed ids).
	for key in data.index do
		if not IndexBook.isValidKey(key) then
			data.index[key] = nil
		end
	end
end

local function onLoaded(player: Player, data: DataService.PlayerData)
	backfill(data)
	ShelfService:RefreshIncome(player)
	sync(player, data.index)
end

function IndexService:Init()
	indexSync = Remotes.get("IndexSync")
	notify = Remotes.get("Notify")
	-- Registered in Init so no player's load is missed (DataService:Start loads them).
	DataService:OnLoaded(onLoaded)
end

function IndexService:Start() end

-- Called by UnwrapService for every unwrapped toy. Pays the discovery bonus on a first find.
function IndexService:Record(player: Player, toyId: string, mutation: Types.Mutation?)
	local data = DataService:GetData(player)
	local key = IndexBook.key(toyId, mutation)
	if not data or data.index[key] or not IndexBook.isValidKey(key) then
		return
	end
	local pagesBefore = IndexBook.completedPages(data.index)
	data.index[key] = true
	local bonus = IndexBook.discoveryBonus(toyId, mutation)
	if bonus > 0 then
		EconomyService:AddCoins(player, bonus)
	end
	local text = `New Index entry! +{withCommas(bonus)} coins`
	if IndexBook.completedPages(data.index) > pagesBefore then
		ShelfService:RefreshIncome(player)
		local percent = math.round((IndexBook.incomeMultiplier(data.index) - 1) * 100)
		text = `Index page complete! Shelf income now +{percent}%. Find bonus +{withCommas(bonus)} coins`
	end
	notify:FireClient(player, text)
	sync(player, data.index)
end

return IndexService

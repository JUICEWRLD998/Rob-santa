--!strict
-- The Gadget Shop (step 4.2): Boots, Extra Wrap, Quiet Steps, Snowball, extra shelves and the
-- Zone 2/3 unlocks. Items and prices come from ShopCatalog (shared with the shop screen).
-- The client sends RequestPurchase with an item id ONLY. The server looks up the level the player
-- owns, the price for the next level, the "needs Zone 2 first" rule and the coins, then saves the
-- new level and applies it. It answers with ShopResult (ok + a short message for the shop screen).
-- Owned levels are mirrored onto the Player as attributes (ShopCatalog.attributeName) for the UI
-- and for GuardService (Quiet Steps) and DisguiseService (Extra Wrap), which read them.
-- The Snowball is bought and saved here; throwing it comes in step 6.4 (RequestSnowball).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local DisguiseService = require(script.Parent.DisguiseService)
local EconomyService = require(script.Parent.EconomyService)
local MovementService = require(script.Parent.MovementService)
local ShelfService = require(script.Parent.ShelfService)

type ItemId = ShopCatalog.ItemId
type PlayerData = DataService.PlayerData

local ShopService = {}

local resultRemote: RemoteEvent
local lastRequest: { [Player]: number } = {}

local function zoneOf(id: ItemId): number?
	if id == "Zone2" then
		return 2
	elseif id == "Zone3" then
		return 3
	end
	return nil
end

-- The level of `id` the save says the player owns.
local function levelOf(data: PlayerData, id: ItemId): number
	if id == "Boots" then
		return data.upgrades.boots
	elseif id == "ExtraWrap" then
		return data.upgrades.extraWrap
	elseif id == "QuietSteps" then
		return data.upgrades.quietSteps
	elseif id == "Snowball" then
		return if data.upgrades.snowball then 1 else 0
	elseif id == "Shelf" then
		return data.shelvesBought
	end
	local zone = zoneOf(id)
	return if zone and table.find(data.zonesOwned, zone) then 1 else 0
end

local function setLevel(data: PlayerData, id: ItemId, level: number)
	if id == "Boots" then
		data.upgrades.boots = level
	elseif id == "ExtraWrap" then
		data.upgrades.extraWrap = level
	elseif id == "QuietSteps" then
		data.upgrades.quietSteps = level
	elseif id == "Snowball" then
		data.upgrades.snowball = level > 0
	elseif id == "Shelf" then
		data.shelvesBought = level
	else
		local zone = zoneOf(id)
		if zone and level > 0 and not table.find(data.zonesOwned, zone) then
			table.insert(data.zonesOwned, zone)
		end
	end
end

local function wrapsAt(level: number): number
	return if level > 0 then Config.Upgrades.ExtraWrap.wrapsByLevel[level] else Config.Disguise.WrapsPerTrip
end

-- Makes the owned level of `id` take effect. `previous` is the level before (0 on join).
local function apply(player: Player, data: PlayerData, id: ItemId, previous: number)
	local level = levelOf(data, id)
	player:SetAttribute(ShopCatalog.attributeName(id), level)
	if id == "Boots" then
		MovementService:SetModifier(player, "boots", level * Config.Upgrades.Boots.speedPerLevel)
	elseif id == "ExtraWrap" then
		DisguiseService:GrantExtraWraps(player, wrapsAt(level) - wrapsAt(previous))
	elseif id == "Shelf" then
		ShelfService:RefreshShelfCount(player)
	end
	-- Quiet Steps and the zones work through the attribute (GuardService, ZoneController) and
	-- the save (ZoneService); the Snowball does nothing until 6.4.
end

local function onLoaded(player: Player, data: PlayerData)
	for _, item in ShopCatalog.Items do
		apply(player, data, item.id, 0)
	end
end

local function reply(player: Player, itemId: string, ok: boolean, message: string)
	local result: Types.ShopResult = { itemId = itemId, ok = ok, message = message }
	resultRemote:FireClient(player, result)
end

local function withCommas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return if formatted:sub(1, 1) == "," then formatted:sub(2) else formatted
end

local function onRequest(player: Player, itemId: any)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < Config.Shop.RequestCooldownSeconds then
		return -- rate limit: a double tap buys once
	end
	lastRequest[player] = now

	local item = ShopCatalog.get(itemId) -- validates the type and the id
	if not item then
		return
	end
	local data = DataService:GetData(player)
	if not data then
		reply(player, item.id, false, "Your save is still loading. Try again in a moment.")
		return
	end
	local level = levelOf(data, item.id)
	local cost = ShopCatalog.cost(item.id, level)
	if not cost then
		local text = if item.maxLevel > 1 then `{item.name} is already maxed!` else `You already own {item.name}.`
		reply(player, item.id, false, text)
		return
	end
	local needed = ShopCatalog.get(item.requires) -- e.g. Zone 3 needs Zone 2 first
	if needed and levelOf(data, needed.id) < 1 then
		reply(player, item.id, false, `Unlock {needed.name} first.`)
		return
	end
	if not EconomyService:TrySpend(player, cost) then
		local missing = cost - EconomyService:GetCoins(player)
		reply(player, item.id, false, `You need {withCommas(missing)} more coins.`)
		return
	end
	setLevel(data, item.id, level + 1)
	apply(player, data, item.id, level)
	local levelText = if item.maxLevel > 1 then ` level {level + 1}` else ""
	reply(player, item.id, true, `Bought {item.name}{levelText}!`)
end

function ShopService:Init()
	resultRemote = Remotes.get("ShopResult")
	-- Registered in Init so no player's load is missed (DataService:Start loads them).
	DataService:OnLoaded(onLoaded)
end

function ShopService:Start()
	Remotes.get("RequestPurchase").OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return ShopService

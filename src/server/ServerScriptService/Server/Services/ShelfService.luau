--!strict
-- Every unwrapped toy a player owns: the ones waiting on their unwrap table and the ones on their
-- shelves (step 2.3, docs/01-GAME-DESIGN.md section 6).
-- * A toy on the table has a "Put on shelf" prompt: it moves to the first free ACTIVE shelf slot.
--   4 slots are active at the start; more are bought in the Gadget Shop (ShopService, 4.2).
-- * Shelved toys pay coins every IncomeTickSeconds: rarity income x mutation (ToyMath).
-- * A shelved toy has a "Sell" prompt. The Black Market in the Town Square buys every toy on
--   the table at once.
-- * Only the owner can use these prompts. The server checks owner, distance and that the toy is
--   still where the prompt says; the client also hides other players' prompts (OwnerOnly tag).
-- * Saving (step 4.1): every change to the table or shelves is copied into the player's data
--   (DataService), and the toys come back when they rejoin. Shelves also pay for the time the
--   player was away, up to Config.Offline.MaxHours. A shelf slot that no longer exists sends its
--   toy back to the table instead of losing it.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local IndexBook = require(ReplicatedStorage.Shared.IndexBook)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ToyMath = require(ReplicatedStorage.Shared.ToyMath)
local Toys = require(ReplicatedStorage.Shared.Toys)
local Types = require(ReplicatedStorage.Shared.Types)
local ToyModel = require(script.Parent.Parent.Lib.ToyModel)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)

local OWNER_TAG = "OwnerOnly" -- the client hides prompts inside these unless it is the owner
local OWNER_ATTRIBUTE = "OwnerUserId"
local INDEX_ATTRIBUTE = "Hideout"
local TOY_GAP = 0.4 -- studs between toys waiting on the table
local VIP_ATTRIBUTE = "Pass_Vip" -- StoreCatalog.passAttribute("Vip"), set by MonetizationService
local PASSES_CHECKED_ATTRIBUTE = "PassesChecked" -- MonetizationService: pass ownership is known

type Entry = {
	owned: Types.OwnedToy,
	def: Types.ToyDef,
	model: Model?,
}

type State = {
	index: number, -- hideout number
	waiting: { Entry }, -- on the unwrap table, oldest first
	shelves: { [number]: Entry }, -- shelf slot index -> toy
	activeShelves: number,
	incomeCarry: number, -- fractions of a coin not paid yet (Frosted gives 1.5/s)
}

local ShelfService = {}

local notifyRemote: RemoteEvent
local stateOf: { [Player]: State } = {}
local slotsOf: { [number]: { [number]: BasePart } } = {} -- hideout -> slot index -> part
local originalTransparency: { [BasePart]: number } = {}
local tableOf: { [number]: BasePart } = {}

local function message(player: Player, text: string)
	notifyRemote:FireClient(player, text)
end

-- Alive and within `distance` (+ lag slack) of the part.
local function isNear(player: Player, part: BasePart, distance: number): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end
	local limit = distance + Config.Shelves.PromptDistanceSlack
	return (root.Position - part.Position).Magnitude <= limit
end

-- Shelf income x the Index bonus (+5% per completed page, step 4.4).
-- VIP (step 6.2): x coinMultiplier on shelf income (offline too) and on every sale.
-- MonetizationService sets the attribute and calls RefreshIncome when it changes.
local function coinMultiplier(player: Player): number
	return if player:GetAttribute(VIP_ATTRIBUTE) == true then Config.GamePasses.Vip.coinMultiplier else 1
end

local function salePrice(player: Player, entry: Entry): number
	return ToyMath.sellPrice(entry.owned.toyId, entry.owned.mutation) * coinMultiplier(player)
end

local function incomeOf(player: Player, state: State): number
	local total = 0
	for _, entry in state.shelves do
		total += ToyMath.incomePerSecond(entry.owned.toyId, entry.owned.mutation)
	end
	total *= coinMultiplier(player)
	local data = DataService:GetData(player)
	return if data then total * IndexBook.incomeMultiplier(data.index) else total
end

local function refreshIncome(player: Player, state: State)
	if player.Parent then
		player:SetAttribute("IncomePerSecond", incomeOf(player, state))
	end
end

local function destroyModel(entry: Entry)
	if entry.model then
		entry.model:Destroy()
		entry.model = nil
	end
end

-- Builds the toy's model with one prompt that calls `onTriggered(player)`.
local function buildWithPrompt(
	owner: Player,
	entry: Entry,
	actionText: string,
	objectText: string,
	holdSeconds: number,
	onTriggered: (Player) -> ()
): Model?
	local model = ToyModel.build(entry.def, entry.owned.mutation)
	local body = model and model.PrimaryPart
	if not model or not body then
		return nil
	end
	model:SetAttribute(OWNER_ATTRIBUTE, owner.UserId)
	CollectionService:AddTag(model, OWNER_TAG)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdSeconds
	prompt.MaxActivationDistance = Config.Shelves.PromptDistance
	prompt.Triggered:Connect(onTriggered)
	prompt.Parent = body
	return model
end

-- Copies the table and shelves into the player's data; DataService saves it to Roblox.
local function saveToys(player: Player, state: State)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local shelves: { DataService.SavedShelfToy } = {}
	for slot, entry in state.shelves do
		local mutation: string? = entry.owned.mutation -- stored as plain text
		table.insert(shelves, { slot = slot, toyId = entry.owned.toyId, mutation = mutation })
	end
	table.sort(shelves, function(a, b)
		return a.slot < b.slot
	end)
	local tableToys: { DataService.SavedTableToy } = {}
	for _, entry in state.waiting do
		local mutation: string? = entry.owned.mutation
		table.insert(tableToys, { toyId = entry.owned.toyId, mutation = mutation })
	end
	data.shelves = shelves
	data.tableToys = tableToys
end

-- A saved mutation name back to a Mutation; nil if it's missing or no longer exists.
local function toMutation(name: string?): Types.Mutation?
	for _, entry in Config.Mutations do
		if entry.name == name then
			return entry.name
		end
	end
	return nil
end

-- A saved toy back to an Entry; nil (with a warning) if the toy id no longer exists.
local function toEntry(player: Player, toyId: string, mutation: string?): Entry?
	local def = Toys.get(toyId)
	if not def then
		warn(`[ShelfService] {player.Name} has a saved toy "{toyId}" that is not in Toys.luau; skipped`)
		return nil
	end
	local owned: Types.OwnedToy = { uid = HttpService:GenerateGUID(false), toyId = toyId, mutation = toMutation(mutation) }
	return { owned = owned, def = def, model = nil }
end

local function displayName(entry: Entry): string
	return if entry.owned.mutation then `{entry.owned.mutation} {entry.def.name}` else entry.def.name
end

-- Forward declaration: placing re-lays the table, which re-creates prompts.
local layoutTable: (player: Player, state: State) -> ()

local function sellShelved(player: Player, slot: number, entry: Entry)
	local state = stateOf[player]
	if not state or state.shelves[slot] ~= entry then
		return -- already sold, or not this player's toy
	end
	local body = entry.model and entry.model.PrimaryPart
	if not body or not isNear(player, body, Config.Shelves.PromptDistance) then
		return
	end
	state.shelves[slot] = nil
	destroyModel(entry)
	saveToys(player, state)
	local price = salePrice(player, entry)
	if price > 0 then
		EconomyService:AddCoins(player, price)
	end
	refreshIncome(player, state)
	message(player, `Sold {displayName(entry)} for {price} coins`)
end

local function slotPart(state: State, slot: number): BasePart?
	local slots = slotsOf[state.index]
	return if slots then slots[slot] else nil
end

local function showOnShelf(player: Player, state: State, slot: number, entry: Entry)
	local part = slotPart(state, slot)
	if not part then
		return
	end
	local price = salePrice(player, entry)
	local objectText = `{displayName(entry)}: {price} coins`
	local model = buildWithPrompt(player, entry, "Sell", objectText, Config.Shelves.SellHoldSeconds, function(who)
		if who == player then
			sellShelved(player, slot, entry)
		end
	end)
	local body = model and model.PrimaryPart
	if not model or not body then
		return
	end
	model:PivotTo(part.CFrame * CFrame.new(0, part.Size.Y / 2 + body.Size.Y / 2, 0))
	model.Parent = part
	entry.model = model
end

local function freeActiveSlot(state: State): number?
	for slot = 1, state.activeShelves do
		if state.shelves[slot] == nil and slotPart(state, slot) then
			return slot
		end
	end
	return nil
end

local function placeOnShelf(player: Player, entry: Entry)
	local state = stateOf[player]
	if not state then
		return
	end
	local position = table.find(state.waiting, entry)
	local body = entry.model and entry.model.PrimaryPart
	if not position or not body or not isNear(player, body, Config.Shelves.PromptDistance) then
		return
	end
	local slot = freeActiveSlot(state)
	if not slot then
		message(player, "Shelves full! Sell a toy, or sell your table at the Black Market.")
		return
	end
	table.remove(state.waiting, position)
	destroyModel(entry)
	state.shelves[slot] = entry
	showOnShelf(player, state, slot, entry)
	layoutTable(player, state)
	refreshIncome(player, state)
	saveToys(player, state)
end

-- Shows the oldest ToysShownOnTable waiting toys in a row on the table; the rest wait unseen.
function layoutTable(player: Player, state: State)
	local tablePart = tableOf[state.index]
	if not tablePart then
		return
	end
	local shown = math.min(#state.waiting, Config.Presents.ToysShownOnTable)
	for position, entry in state.waiting do
		if position > shown then
			destroyModel(entry)
			continue
		end
		if not entry.model then
			local income = ToyMath.incomePerSecond(entry.owned.toyId, entry.owned.mutation)
			local objectText = `{displayName(entry)}: {income}/s`
			entry.model = buildWithPrompt(player, entry, "Put on shelf", objectText, Config.Shelves.PlaceHoldSeconds, function(who)
				if who == player then
					placeOnShelf(player, entry)
				end
			end)
		end
		local model = entry.model
		local body = model and model.PrimaryPart
		if model and body then
			local spacing = body.Size.X + TOY_GAP
			local x = (position - (shown + 1) / 2) * spacing
			model:PivotTo(tablePart.CFrame * CFrame.new(x, tablePart.Size.Y / 2 + body.Size.Y / 2, 0))
			model.Parent = tablePart
		end
	end
end

local function sellAllWaiting(player: Player, market: BasePart)
	local state = stateOf[player]
	if not state or not isNear(player, market, Config.BlackMarket.PromptDistance) then
		return
	end
	local count = #state.waiting
	if count == 0 then
		message(player, "Nothing on your table to sell. Unwrap a present first!")
		return
	end
	local total = 0
	for _, entry in state.waiting do
		total += salePrice(player, entry)
		destroyModel(entry)
	end
	state.waiting = {}
	saveToys(player, state)
	if total > 0 then
		EconomyService:AddCoins(player, total)
	end
	message(player, `The Black Market paid {total} coins for {count} toy{if count == 1 then "" else "s"}`)
end

-- Active slots look solid; slots you haven't bought yet look see-through. nil = free hideout.
local function applyShelfLook(index: number, active: number?)
	local slots = slotsOf[index]
	if not slots then
		return
	end
	for slot, part in slots do
		local original = originalTransparency[part] or part.Transparency
		if active == nil or slot <= active then
			part.Transparency = original
		else
			part.Transparency = Config.Shelves.InactiveTransparency
		end
	end
end

-- Puts the saved toys back: each on its shelf slot, or on the table if that slot is gone.
local function restoreToys(player: Player, state: State, data: DataService.PlayerData)
	for _, saved in data.shelves do
		local entry = toEntry(player, saved.toyId, saved.mutation)
		if not entry then
			continue
		end
		local slot = saved.slot
		local fits = slot >= 1 and slot <= state.activeShelves and state.shelves[slot] == nil
		if fits and slotPart(state, slot) then
			state.shelves[slot] = entry
			showOnShelf(player, state, slot, entry)
		else
			table.insert(state.waiting, entry)
		end
	end
	for _, saved in data.tableToys do
		local entry = toEntry(player, saved.toyId, saved.mutation)
		if entry then
			table.insert(state.waiting, entry)
		end
	end
	layoutTable(player, state)
	saveToys(player, state)
end

local function formatDuration(seconds: number): string
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	if hours > 0 then
		return `{hours}h {minutes}m`
	end
	return `{math.max(minutes, 1)}m`
end

-- Pays the shelves' income for the time the player was away, up to the offline cap (VIP: longer,
-- and x2). Waits a little for the pass check first, or a VIP would be paid as a free player.
local function payOffline(player: Player, state: State)
	local waitUntil = os.clock() + Config.Store.PassesWaitSeconds
	while player:GetAttribute(PASSES_CHECKED_ATTRIBUTE) ~= true and player.Parent and os.clock() < waitUntil do
		task.wait(0.2)
	end
	if stateOf[player] ~= state then
		return -- left (or lost the hideout) while waiting; the seconds stay unpaid for next time
	end
	local away = DataService:TakeOfflineSeconds(player)
	local isVip = player:GetAttribute(VIP_ATTRIBUTE) == true
	local capHours = if isVip then Config.Offline.MaxHoursVip else Config.Offline.MaxHours
	local paidSeconds = math.min(away, capHours * 3600)
	local coins = math.floor(incomeOf(player, state) * paidSeconds)
	if coins > 0 and EconomyService:AddCoins(player, coins) then
		message(player, `Welcome back! Your shelves earned {coins} coins while you were away ({formatDuration(paidSeconds)})`)
	end
end

-- Called (in its own thread) when the player gets a hideout. Waits for their save to load, then
-- puts their toys back and pays offline earnings.
local function onAssigned(player: Player, index: number)
	if stateOf[player] then
		return
	end
	local data = DataService:WaitForData(player)
	-- They may have left, or been moved to another hideout, while the save loaded.
	if not data or stateOf[player] or PlotService:GetHideoutIndex(player) ~= index then
		return
	end
	local state: State = {
		index = index,
		waiting = {},
		shelves = {},
		activeShelves = math.min(Config.Shelves.Start + data.shelvesBought, Config.Shelves.Max),
		incomeCarry = 0,
	}
	stateOf[player] = state
	applyShelfLook(index, state.activeShelves)
	restoreToys(player, state, data)
	refreshIncome(player, state)
	payOffline(player, state)
end

local function onReleased(player: Player, index: number)
	local state = stateOf[player]
	stateOf[player] = nil
	if state then
		for _, entry in state.waiting do
			destroyModel(entry)
		end
		for _, entry in state.shelves do
			destroyModel(entry)
		end
	end
	applyShelfLook(index, nil)
end

local function payIncome()
	local tickSeconds = Config.Shelves.IncomeTickSeconds
	for player, state in stateOf do
		state.incomeCarry += incomeOf(player, state) * tickSeconds
		local whole = math.floor(state.incomeCarry)
		if whole > 0 then
			EconomyService:AddCoins(player, whole)
			state.incomeCarry -= whole
		end
	end
end

function ShelfService:Init()
	notifyRemote = Remotes.get("Notify")
	if not ToyModel.isReady() then
		warn("[ShelfService] ServerStorage/Templates/Toy is missing; toys will be invisible")
	end
	ToyModel.publishMeshes() -- the unwrap reveal (client) shows the toy's mesh
	for _, part in CollectionService:GetTagged("ShelfSlot") do
		local index = part:GetAttribute(INDEX_ATTRIBUTE)
		local slot = part:GetAttribute("Index")
		local valid = part:IsA("BasePart") and part:IsDescendantOf(workspace)
		if valid and type(index) == "number" and type(slot) == "number" then
			local slots = slotsOf[index]
			if not slots then
				slots = {}
				slotsOf[index] = slots
			end
			slots[slot] = part :: BasePart
			originalTransparency[part :: BasePart] = (part :: BasePart).Transparency
		end
	end
	for _, part in CollectionService:GetTagged("UnwrapTable") do
		local index = part:GetAttribute(INDEX_ATTRIBUTE)
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) and type(index) == "number" then
			tableOf[index] = part
		end
	end
	-- Registered in Init so the first assignments (made in PlotService:Start) are not missed.
	PlotService:OnAssigned(onAssigned)
	PlotService:OnReleased(onReleased)
end

function ShelfService:Start()
	for _, market in CollectionService:GetTagged("BlackMarket") do
		if market:IsA("BasePart") and market:IsDescendantOf(workspace) then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Sell table toys"
			prompt.ObjectText = "Black Market"
			prompt.HoldDuration = Config.BlackMarket.HoldSeconds
			prompt.MaxActivationDistance = Config.BlackMarket.PromptDistance
			prompt.RequiresLineOfSight = false -- the stall is one big block; its centre is inside it
			prompt.Triggered:Connect(function(player)
				sellAllWaiting(player, market)
			end)
			prompt.Parent = market
		end
	end
	task.spawn(function()
		while true do
			task.wait(Config.Shelves.IncomeTickSeconds)
			local ok, err = pcall(function(): any
				payIncome()
				return nil
			end)
			if not ok then
				warn(`[ShelfService] income tick failed: {err}`)
			end
		end
	end)
end

-- Puts a freshly unwrapped toy on the player's unwrap table. Returns false if it could not.
function ShelfService:AddUnwrapped(player: Player, owned: Types.OwnedToy): boolean
	local state = stateOf[player]
	local def = Toys.get(owned.toyId)
	if not state or not def then
		return false
	end
	table.insert(state.waiting, { owned = owned, def = def, model = nil })
	layoutTable(player, state)
	saveToys(player, state)
	return true
end

-- Re-reads how many shelves the player owns (Config.Shelves.Start + shelves bought in the shop)
-- and lights up the new slots. Called by ShopService after a shelf is bought.
function ShelfService:RefreshShelfCount(player: Player)
	local state = stateOf[player]
	local data = DataService:GetData(player)
	if not state or not data then
		return -- not set up yet: onAssigned reads the count from the save when it is
	end
	state.activeShelves = math.min(Config.Shelves.Start + data.shelvesBought, Config.Shelves.Max)
	applyShelfLook(state.index, state.activeShelves)
end

-- Coins per second from the player's shelves right now.
function ShelfService:GetIncomePerSecond(player: Player): number
	local state = stateOf[player]
	return if state then incomeOf(player, state) else 0
end

-- Re-shows income after something outside the shelves changed it (an Index page completed, or
-- VIP arriving: then the shelved toys' "Sell" prompts show the doubled price too).
function ShelfService:RefreshIncome(player: Player)
	local state = stateOf[player]
	if state then
		refreshIncome(player, state)
		for _, entry in state.shelves do
			local prompt = entry.model and entry.model:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt then
				prompt.ObjectText = `{displayName(entry)}: {salePrice(player, entry)} coins`
			end
		end
	end
end

return ShelfService

--!strict
-- Robux (step 6.2, docs/01-GAME-DESIGN.md section 10). The ONLY script that sets
-- MarketplaceService.ProcessReceipt. IDs live in Config.GamePasses / Config.DevProducts.
--
-- Game passes: owned forever. Checked on join (UserOwnsGamePassAsync) and granted the moment a
-- purchase finishes (PromptGamePassPurchaseFinished, a server event players can't fake). Each owned
-- pass becomes a Player attribute (StoreCatalog.passAttribute); the services that apply it read
-- that: ShelfService (VIP x2 coins, 4 h offline), PresentService (Big Sack), DisguiseService (Wrap
-- Master). Speed Boots is a MovementService modifier. VIP also gets a gold name tag.
-- "PassesChecked" = true once ownership is known (offline earnings wait for it).
--
-- Developer products: granted ONLY in ProcessReceipt, exactly once per PurchaseId, through
-- DataService:ProcessPurchase (records the PurchaseId with the grant, answers "granted" only once
-- that is saved). Anything uncertain answers NotProcessedYet, so Roblox delivers it again later.
--   BailOut: out of jail now. If the player is no longer jailed when it arrives, it is saved as a
--            free Bail Out (bailCredits), used from the jail panel next time (RequestBailOut).
--   LuckyWrap: saved (luckyWraps); UnwrapService uses one on the next unwrap.
--   Blizzard: server-wide for durationSeconds (GuardService:SetBlizzard), buyer named on a banner
--            (Workspace attributes BlizzardEndsAt / BlizzardBy, read by BlizzardController).
--   Coin packs: StoreCatalog.coinPackAmount of the buyer's current income.
--   AdventCatchUp: not sold until step 6.3.
-- Paid random items (Lucky Wrap): PolicyService decides per player; "PaidRandomItemsRestricted"
-- hides it on the store screen. If the check fails, it counts as restricted.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local DataService = require(script.Parent.DataService)
local DisguiseService = require(script.Parent.DisguiseService)
local EconomyService = require(script.Parent.EconomyService)
local GuardService = require(script.Parent.GuardService)
local JailService = require(script.Parent.JailService)
local MovementService = require(script.Parent.MovementService)
local PresentService = require(script.Parent.PresentService)
local ShelfService = require(script.Parent.ShelfService)

type PassKey = StoreCatalog.PassKey
type ProductKey = StoreCatalog.ProductKey
type PlayerData = DataService.PlayerData

local PASSES_CHECKED_ATTRIBUTE = "PassesChecked"
local RESTRICTED_ATTRIBUTE = "PaidRandomItemsRestricted"
local VIP_TAG_NAME = "VipTag"
local BLIZZARD_CHECK_SECONDS = 0.5
local PASS_KEYS: { PassKey } = StoreCatalog.PassKeys :: any

local MonetizationService = {}

local passKeyById: { [number]: PassKey } = {}
local productKeyById: { [number]: ProductKey } = {}
local owned: { [Player]: { [string]: boolean } } = {}
local lastBailRequest: { [Player]: number } = {}
local notify: RemoteEvent
local blizzardEndsAt = 0 -- server time (Workspace:GetServerTimeNow)
local blizzardRunning = false

local function message(player: Player, text: string)
	if player.Parent then
		notify:FireClient(player, text)
	end
end

----------------------------------------------------------------------------------------------------
-- Game passes

-- A gold name over a VIP's head, seen by everyone. Hidden while they're a gift box, or the box
-- would give them away.
local function updateVipTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid or player:GetAttribute(StoreCatalog.passAttribute("Vip")) ~= true then
		return
	end
	local tag = head:FindFirstChild(VIP_TAG_NAME)
	if not tag then
		local gui = Instance.new("BillboardGui")
		gui.Name = VIP_TAG_NAME
		gui.Size = UDim2.fromOffset(180, 34)
		gui.StudsOffset = Vector3.new(0, 2.4, 0)
		gui.MaxDistance = 80
		gui.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Config.Store.VipTagColor
		label.TextStrokeColor3 = Color3.fromRGB(22, 30, 51)
		label.TextStrokeTransparency = 0
		label.Text = `[VIP] {player.DisplayName}`
		label.Parent = gui
		gui.Parent = head
		tag = gui
	end
	-- The gold tag replaces the plain name. DisguiseService saves and restores this setting, so
	-- popping out of a box keeps it hidden.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = player:GetAttribute("Disguised") ~= true
	end
end

local function applyPass(player: Player, key: PassKey)
	player:SetAttribute(StoreCatalog.passAttribute(key), true)
	if key == "Vip" then
		ShelfService:RefreshIncome(player)
		updateVipTag(player)
	elseif key == "BigSack" then
		PresentService:RefreshCapacity(player)
	elseif key == "SpeedBoots" then
		MovementService:SetModifier(player, "speedBoots", Config.GamePasses.SpeedBoots.extraWalkSpeed)
	elseif key == "WrapMaster" then
		DisguiseService:GrantExtraWraps(player, Config.GamePasses.WrapMaster.extraWraps)
	end
end

local PASS_THANKS: { [PassKey]: string } = {
	Vip = "You're a VIP! Double coins from now on.",
	BigSack = "Big Sack! You can carry 2 presents now.",
	SpeedBoots = "Speed Boots on! You run faster now.",
	WrapMaster = "Wrap Master! More disguises, shorter cooldown.",
}

local function grantPass(player: Player, key: PassKey, justBought: boolean)
	local set = owned[player]
	if not set or set[key] or player.Parent == nil then
		return
	end
	set[key] = true
	applyPass(player, key)
	if justBought then
		message(player, PASS_THANKS[key])
	end
end

local function ownsPass(player: Player, passId: number): boolean
	for attempt = 1, Config.Store.PassCheckRetries do
		local ok, result = pcall(function(): any
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if ok then
			return result == true
		end
		if attempt == Config.Store.PassCheckRetries then
			warn(`[MonetizationService] pass {passId} check failed for {player.UserId}: {result}`)
		else
			task.wait(attempt)
		end
	end
	return false
end

local function checkPasses(player: Player)
	for _, key in PASS_KEYS do
		local id = Config.GamePasses[key].id
		if id > 0 and player.Parent and ownsPass(player, id) then
			grantPass(player, key :: PassKey, false)
		end
	end
	if player.Parent then
		player:SetAttribute(PASSES_CHECKED_ATTRIBUTE, true)
	end
end

local function checkPolicy(player: Player)
	local ok, info = pcall(function(): any
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	local allowed = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false
	if not ok then
		warn(`[MonetizationService] policy check failed for {player.UserId}: {info}; Lucky Wrap hidden`)
	end
	if player.Parent then
		player:SetAttribute(RESTRICTED_ATTRIBUTE, not allowed)
	end
end

----------------------------------------------------------------------------------------------------
-- Blizzard

local function runBlizzard()
	blizzardRunning = true
	GuardService:SetBlizzard(true)
	while Workspace:GetServerTimeNow() < blizzardEndsAt do
		task.wait(BLIZZARD_CHECK_SECONDS)
	end
	GuardService:SetBlizzard(false)
	Workspace:SetAttribute("BlizzardEndsAt", nil)
	Workspace:SetAttribute("BlizzardBy", nil)
	blizzardRunning = false
end

-- Starts a Blizzard, or adds durationSeconds to the one already blowing.
local function startBlizzard(buyer: Player)
	local now = Workspace:GetServerTimeNow()
	blizzardEndsAt = math.max(blizzardEndsAt, now) + Config.DevProducts.Blizzard.durationSeconds
	Workspace:SetAttribute("BlizzardEndsAt", blizzardEndsAt)
	Workspace:SetAttribute("BlizzardBy", buyer.DisplayName)
	if not blizzardRunning then
		task.spawn(runBlizzard)
	end
end

----------------------------------------------------------------------------------------------------
-- Developer products

-- Gives one purchase. Runs inside DataService:ProcessPurchase, so it must NOT yield: anything slow
-- goes into task.spawn.
local function grantProduct(player: Player, key: ProductKey, data: PlayerData)
	if key == "CoinPackSmall" or key == "CoinPackMedium" or key == "CoinPackLarge" then
		local amount = StoreCatalog.coinPackAmount(key, ShelfService:GetIncomePerSecond(player))
		if not EconomyService:AddCoins(player, amount) then
			error(`could not add {amount} coins`) -- nothing recorded; the receipt comes back later
		end
		message(player, `+{StoreCatalog.withCommas(amount)} coins! Thank you!`)
	elseif key == "LuckyWrap" then
		data.luckyWraps += 1
		player:SetAttribute("LuckyWraps", data.luckyWraps)
		message(player, "Lucky Wrap ready! Your next unwrap rolls one rarity higher.")
	elseif key == "BailOut" then
		if JailService:IsJailed(player) then
			task.spawn(function()
				JailService:Release(player)
			end)
			message(player, "Bailed out! Back to your hideout.")
		else
			data.bailCredits += 1
			player:SetAttribute("BailCredits", data.bailCredits)
			message(player, "You were already free, so your Bail Out is saved for next time.")
		end
	elseif key == "Blizzard" then
		task.spawn(startBlizzard, player)
		message(player, "BLIZZARD! The elves can barely see. Everyone thanks you!")
	else
		error(`no grant for product {key}`)
	end
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local key = productKeyById[receipt.ProductId]
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- comes back when they next join
	end
	if not key then
		warn(`[MonetizationService] receipt for unknown product {receipt.ProductId}; left unprocessed`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not DataService:WaitForData(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local ok, granted = pcall(function(): any
		return DataService:ProcessPurchase(player, purchaseId, function(data: PlayerData)
			grantProduct(player, key :: ProductKey, data)
		end)
	end)
	if ok and granted == true then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not ok then
		warn(`[MonetizationService] receipt {purchaseId} ({key}) for {player.UserId} failed: {granted}`)
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- The jail panel's "Free Bail Out" button: spends one saved Bail Out.
local function onBailRequest(player: Player)
	local now = os.clock()
	if now - (lastBailRequest[player] or 0) < Config.Store.RequestCooldownSeconds then
		return
	end
	lastBailRequest[player] = now
	local data = DataService:GetData(player)
	if not data or data.bailCredits <= 0 or not JailService:IsJailed(player) then
		return
	end
	data.bailCredits -= 1
	player:SetAttribute("BailCredits", data.bailCredits)
	JailService:Release(player)
	message(player, "Used a saved Bail Out. Back to your hideout!")
end

----------------------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if owned[player] then
		return
	end
	owned[player] = {}
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		updateVipTag(player)
	end)
	player:GetAttributeChangedSignal("Disguised"):Connect(function()
		updateVipTag(player)
	end)
	task.spawn(checkPolicy, player)
	checkPasses(player)
end

-- Studio-only test hook (Config.Debug.MonetizationHookInStudio), like DataService's DebugData.
--   Invoke("pass", player, passKey)                 -> gives the pass as if just bought
--   Invoke("receipt", player, productKey, purchaseId?) -> runs a fake receipt; returns the decision name
local function createDebugHook()
	if not (RunService:IsStudio() and Config.Debug.MonetizationHookInStudio) then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "DebugMonetization"
	hook.OnInvoke = function(action: string, player: Player, key: string, purchaseId: string?): any
		if action == "pass" and (Config.GamePasses :: any)[key] then
			grantPass(player, key :: PassKey, true)
			return true
		elseif action == "receipt" then
			local product = (Config.DevProducts :: any)[key]
			local decision = processReceipt({
				PlayerId = player.UserId,
				ProductId = if product then product.id else -1,
				PurchaseId = purchaseId or `test-{os.clock()}`,
				CurrencySpent = 0,
				PlaceIdWherePurchased = game.PlaceId,
			})
			return decision.Name
		end
		return nil
	end
	hook.Parent = ServerStorage
end

function MonetizationService:Init()
	notify = Remotes.get("Notify")
	for _, key in PASS_KEYS do
		local id = Config.GamePasses[key].id
		if id > 0 then
			passKeyById[id] = key :: PassKey
		end
	end
	for key, product in Config.DevProducts :: any do
		if product.id > 0 then
			productKeyById[product.id] = key :: ProductKey
		end
	end
	DataService:OnLoaded(function(player: Player, data: PlayerData)
		player:SetAttribute("LuckyWraps", data.luckyWraps)
		player:SetAttribute("BailCredits", data.bailCredits)
	end)
end

function MonetizationService:Start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local key = passKeyById[passId]
		if purchased and key then
			grantPass(player, key :: PassKey, true)
		end
	end)
	Remotes.get("RequestBailOut").OnServerEvent:Connect(onBailRequest)
	createDebugHook()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		lastBailRequest[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return MonetizationService

--!strict
-- The gift-box disguise (step 3.4). docs/01-GAME-DESIGN.md section 5. Numbers in Config.Disguise.
-- Q / the gift-box button / ButtonY sends RequestDisguise (no arguments). The server checks: alive,
-- not jailed, standing on the ground, a Wrap left, cooldown over, rate limit. Then the avatar (and
-- any present on your back) is hidden and a big wrapped present sits where you stand.
-- Moving cancels it at once; otherwise it lasts MaxSeconds. While an elf is sniffing the box
-- (GuardService calls BeginInspect/EndInspect) the timer waits, so the inspection always resolves:
-- stay still = fooled, move = caught. Wraps refill to WrapsPerTrip when you touch your hideout.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local PlotService = require(script.Parent.PlotService)
local PresentService = require(script.Parent.PresentService)
local GameEvents = require(script.Parent.Parent.Lib.GameEvents) -- 6.3: daily quest progress

local WRAPS_ATTRIBUTE = "Wraps" -- on the Player; the HUD reads it
local EXTRA_WRAP_ATTRIBUTE = "Shop_ExtraWrap" -- ShopCatalog.attributeName("ExtraWrap")
local WRAP_MASTER_ATTRIBUTE = "Pass_WrapMaster" -- StoreCatalog.passAttribute("WrapMaster")
local DISGUISED_ATTRIBUTE = "Disguised" -- on the Player while wrapped
local BOX_NAME = "DisguiseBox"
local PRESENT_SIZE = 2 -- studs, a zone present's box (Templates/Present.Box)
local REFILL_CHECK_SECONDS = 0.5

type Hidden = { instance: Instance, property: string, value: any }
type Disguise = {
	box: Model,
	anchor: Vector3, -- where the player stood when they wrapped
	endsAt: number, -- os.clock
	hidden: { Hidden },
	displayType: Enum.HumanoidDisplayDistanceType,
	inspectors: number,
}

local DisguiseService = {}

local active: { [Player]: Disguise } = {}
local readyAt: { [Player]: number } = {} -- os.clock when the next disguise is allowed
local lastRequest: { [Player]: number } = {}
local update: RemoteEvent

local function serverTime(clockTime: number): number
	return Workspace:GetServerTimeNow() + (clockTime - os.clock())
end

local function send(player: Player, state: Types.DisguiseState, disguise: Disguise?)
	local payload: Types.DisguiseUpdate = { state = state }
	if disguise then
		payload.endsAt = serverTime(disguise.endsAt)
	end
	local ready = readyAt[player]
	if ready then
		payload.readyAt = serverTime(ready)
	end
	update:FireClient(player, payload)
end

local function hasWrapMaster(player: Player): boolean
	return player:GetAttribute(WRAP_MASTER_ATTRIBUTE) == true
end

-- Wraps per trip: the Extra Wrap level (ShopService sets the attribute), plus the Wrap Master pass
-- (MonetizationService sets that one, 6.2).
local function maxWraps(player: Player): number
	local level = player:GetAttribute(EXTRA_WRAP_ATTRIBUTE)
	local byLevel = Config.Upgrades.ExtraWrap.wrapsByLevel
	local wraps = Config.Disguise.WrapsPerTrip
	if type(level) == "number" and level >= 1 then
		wraps = byLevel[math.min(level, #byLevel)]
	end
	if hasWrapMaster(player) then
		wraps += Config.GamePasses.WrapMaster.extraWraps
	end
	return wraps
end

local function cooldownOf(player: Player): number
	local seconds = Config.Disguise.CooldownSeconds
	if hasWrapMaster(player) then
		seconds -= Config.GamePasses.WrapMaster.cooldownReductionSeconds
	end
	return math.max(0, seconds)
end

local function wrapsOf(player: Player): number
	local wraps = player:GetAttribute(WRAPS_ATTRIBUTE)
	return if type(wraps) == "number" then wraps else 0
end

type Body = { character: Model, humanoid: Humanoid, root: BasePart }

local function bodyOf(player: Player): Body?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return { character = character, humanoid = humanoid, root = root }
	end
	return nil
end

-- Sets `property` to `value`, remembering the old value so restore() can put it back.
local function hide(list: { Hidden }, instance: Instance, property: string, value: any)
	local old = (instance :: any)[property]
	if old ~= value then
		table.insert(list, { instance = instance, property = property, value = old });
		(instance :: any)[property] = value
	end
end

local function hideModel(list: { Hidden }, model: Instance, skip: Instance?)
	for _, item in model:GetDescendants() do
		if skip and (item == skip or item:IsDescendantOf(skip)) then
			continue
		end
		if item:IsA("BasePart") or item:IsA("Decal") then
			hide(list, item, "Transparency", 1)
		end
	end
end

local function restore(list: { Hidden })
	for _, entry in list do
		if entry.instance.Parent then
			(entry.instance :: any)[entry.property] = entry.value
		end
	end
end

-- A plain wrapped present, BoxScale times a zone present, welded under the player's feet.
local function makeBox(body: Body): Model?
	local templates = ServerStorage:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("Present")
	if not template or not template:IsA("Model") then
		warn("[DisguiseService] ServerStorage/Templates/Present is missing")
		return nil
	end
	local box = template:Clone()
	box.Name = BOX_NAME
	for _, tag in CollectionService:GetTags(box) do
		CollectionService:RemoveTag(box, tag)
	end
	for _, item in box:GetDescendants() do
		for _, tag in CollectionService:GetTags(item) do
			CollectionService:RemoveTag(item, tag)
		end
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true
		elseif item:IsA("ProximityPrompt") or item:IsA("BaseScript") then
			item:Destroy()
		end
	end
	box:ScaleTo(Config.Disguise.BoxScale)
	local size = PRESENT_SIZE * Config.Disguise.BoxScale
	local root = body.root
	local feetY = root.Position.Y - body.humanoid.HipHeight - root.Size.Y / 2
	local look = root.CFrame.LookVector
	local at = Vector3.new(root.Position.X, feetY + size / 2, root.Position.Z)
	box:PivotTo(CFrame.lookAt(at, at + Vector3.new(look.X, 0, look.Z)))
	local primary = box.PrimaryPart
	if primary then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = primary
		weld.Parent = primary
	end
	box.Parent = body.character -- inside the character: elves' sight rays already skip it
	return box
end

local function finish(player: Player, state: Types.DisguiseState)
	local disguise = active[player]
	if not disguise then
		return
	end
	active[player] = nil
	restore(disguise.hidden)
	local body = bodyOf(player)
	if body then
		body.humanoid.DisplayDistanceType = disguise.displayType
	end
	disguise.box:Destroy()
	readyAt[player] = os.clock() + cooldownOf(player)
	if player.Parent then
		player:SetAttribute(DISGUISED_ATTRIBUTE, nil)
		send(player, state, nil)
	end
end

-- Ends the disguise as soon as the player moves, or when time is up and nobody is sniffing.
local function watch(player: Player, disguise: Disguise)
	local settings = Config.Disguise
	while active[player] == disguise do
		task.wait(settings.MoveCheckSeconds)
		if active[player] ~= disguise then
			return
		end
		local body = bodyOf(player)
		if not body or (body.root.Position - disguise.anchor).Magnitude > settings.MoveCancelStuds then
			finish(player, "Ended")
			return
		end
		if disguise.inspectors == 0 and os.clock() >= disguise.endsAt then
			finish(player, "Ended")
			return
		end
	end
end

local function tryStart(player: Player)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < Config.Disguise.RequestCooldownSeconds then
		return
	end
	lastRequest[player] = now
	if active[player] then
		finish(player, "Ended") -- pressing again pops you out
		return
	end
	local body = bodyOf(player)
	if not body or player:GetAttribute("Jailed") == true then
		return
	end
	if body.humanoid.FloorMaterial == Enum.Material.Air then
		return -- mid-jump: you'd fall out of the box at once
	end
	if now < (readyAt[player] or 0) or wrapsOf(player) <= 0 then
		send(player, "Ended", nil) -- refresh the button so it shows why
		return
	end
	local box = makeBox(body)
	if not box then
		return
	end
	local hidden: { Hidden } = {}
	hideModel(hidden, body.character, box)
	for _, model in PresentService:GetCarriedModels(player) do
		hideModel(hidden, model, nil)
	end
	local disguise: Disguise = {
		box = box,
		anchor = body.root.Position,
		endsAt = now + Config.Disguise.MaxSeconds,
		hidden = hidden,
		displayType = body.humanoid.DisplayDistanceType,
		inspectors = 0,
	}
	body.humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- no name over the box
	active[player] = disguise
	player:SetAttribute(WRAPS_ATTRIBUTE, wrapsOf(player) - 1)
	player:SetAttribute(DISGUISED_ATTRIBUTE, true)
	send(player, "Wrapped", disguise)
	task.spawn(watch, player, disguise)
end

local function refillLoop()
	local padding = Vector3.one * Config.Disguise.HideoutRefillPadding * 2
	while true do
		task.wait(REFILL_CHECK_SECONDS)
		for _, player in Players:GetPlayers() do
			local wraps = maxWraps(player)
			if wrapsOf(player) >= wraps or active[player] then
				continue
			end
			local hideout = PlotService:GetHideout(player)
			local body = bodyOf(player)
			if hideout and body then
				local frame, size = hideout:GetBoundingBox()
				local spot = frame:PointToObjectSpace(body.root.Position)
				local half = (size + padding) / 2
				if math.abs(spot.X) <= half.X and math.abs(spot.Y) <= half.Y and math.abs(spot.Z) <= half.Z then
					player:SetAttribute(WRAPS_ATTRIBUTE, wraps)
				end
			end
		end
	end
end

local function setupPlayer(player: Player)
	player:SetAttribute(WRAPS_ATTRIBUTE, maxWraps(player))
	player:GetAttributeChangedSignal("Jailed"):Connect(function()
		if player:GetAttribute("Jailed") == true then
			finish(player, "Ended")
		end
	end)
	player.CharacterRemoving:Connect(function()
		finish(player, "Ended")
	end)
end

function DisguiseService:Init()
	update = Remotes.get("DisguiseUpdate")
end

function DisguiseService:Start()
	Remotes.get("RequestDisguise").OnServerEvent:Connect(function(player: Player)
		tryStart(player) -- takes no arguments; anything sent along is ignored
	end)
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		finish(player, "Ended")
		readyAt[player] = nil
		lastRequest[player] = nil
	end)
	task.spawn(refillLoop)
end

-- Adds wraps right away when the per-trip number goes up (an Extra Wrap bought, or the saved
-- level arriving after join), never above the new maximum.
function DisguiseService:GrantExtraWraps(player: Player, amount: number)
	if amount <= 0 or player.Parent == nil then
		return
	end
	player:SetAttribute(WRAPS_ATTRIBUTE, math.min(wrapsOf(player) + amount, maxWraps(player)))
end

-- True while the player is a gift box (which also means they're holding still).
function DisguiseService:IsDisguised(player: Player): boolean
	return active[player] ~= nil
end

-- Where the box stands, for an elf walking over to sniff it.
function DisguiseService:GetBoxPosition(player: Player): Vector3?
	local disguise = active[player]
	return if disguise then disguise.anchor else nil
end

-- An elf starts sniffing: the disguise won't time out until every sniffing elf is done.
function DisguiseService:BeginInspect(player: Player)
	local disguise = active[player]
	if disguise then
		disguise.inspectors += 1
		send(player, "Inspected", disguise)
	end
end

-- An elf stops sniffing. fooled = the player held still the whole time.
function DisguiseService:EndInspect(player: Player, fooled: boolean)
	local disguise = active[player]
	if disguise then
		disguise.inspectors = math.max(0, disguise.inspectors - 1)
	end
	if player.Parent then
		send(player, if fooled then "Fooled" else "Gotcha", disguise)
		if fooled then
			GameEvents.fire("InspectionSurvived", player)
		end
	end
end

return DisguiseService

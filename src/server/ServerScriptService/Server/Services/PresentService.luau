--!strict
-- Presents: spawn on PresentSpawn points, get grabbed (ProximityPrompt), ride on the thief's back,
-- and go back to their zone if dropped. Delivery and unwrapping live in UnwrapService.
--
-- Rules (docs/01-GAME-DESIGN.md sections 3 and 6):
-- * The wrapping IS the rarity: rolled from the zone table at spawn, wrapping coloured to match.
-- * A grabbed present frees its spawn point, which spawns a new present in 20-40 s.
-- * A dropped present (death, reset, leaving) lies where it fell for 10 s, then goes to a free
--   spawn point in its zone. If the zone is full, it disappears.
-- * Every grab is checked on the server: present resting or dropped, player alive and close, hands free.
-- * Step 6.4: a dropped present can be picked up by anyone nearby until it goes home (a snowball
--   knocks presents loose); the Sleigh Raid's presents are zone 0 (the Town) and vanish when dropped.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local MovementService = require(script.Parent.MovementService)
local ZoneService = require(script.Parent.ZoneService)
local GameEvents = require(script.Parent.Parent.Lib.GameEvents) -- 6.3: daily quest progress

local PRESENT_TAG = "Present" -- on every present model, so the client can find their prompts
local CARRY_MODIFIER = "carry"
local DROP_RAY_LENGTH = 60

type State = "Resting" | "Carried" | "Dropped" | "Delivered"

type SpawnPoint = {
	part: BasePart,
	zone: number,
	present: Present?,
	timer: thread?,
}

type Present = {
	model: Model,
	box: BasePart,
	zone: number,
	rarity: Types.Rarity,
	state: State,
	point: SpawnPoint?,
	carrier: Player?,
	weld: WeldConstraint?,
	prompt: ProximityPrompt?,
	returnTimer: thread?,
	-- Where and when it was picked up. The position is the present's own resting spot (server
	-- truth, not the client's character), used by the delivery speed check.
	grabbedFrom: Vector3?,
	grabbedAt: number?,
}

-- What UnwrapService gets when a player delivers.
export type Delivered = {
	model: Model,
	box: BasePart,
	zone: number,
	rarity: Types.Rarity,
}

local PresentService = {}

local rng = Random.new()
local template: Model? = nil
local folder: Folder
local pointsByZone: { [number]: { SpawnPoint } } = {}
local carriedBy: { [Player]: { Present } } = {}
-- Sleigh Raid presents (zone 0, no spawn point). Cleared when the sleigh leaves, unless carried.
local eventPresents: { [Present]: true } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}

-- Forward declarations (these functions call each other).
local placeAt: (present: Present, point: SpawnPoint) -> ()
local scheduleRespawn: (point: SpawnPoint) -> ()

-- Weights are percent per present, in Config.RarityOrder (a zone's table, or the Sleigh Raid's).
local function rollRarity(weights: { number }): Types.Rarity
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll = rng:NextNumber(0, total)
	local lowest: number? = nil -- the lowest tier that can drop (a roll of exactly `total` lands here)
	for tier, weight in weights do
		roll -= weight
		if weight > 0 then
			lowest = lowest or tier
			if roll < 0 then
				return Config.RarityOrder[tier]
			end
		end
	end
	return Config.RarityOrder[lowest or 1]
end

-- Big Sack (game pass, 6.2): MonetizationService sets the attribute.
local function capacityOf(player: Player): number
	if player:GetAttribute("Pass_BigSack") == true then
		return Config.Presents.CarryCapacityBigSack
	end
	return Config.Presents.CarryCapacity
end

local function setPartsCarried(present: Present, carried: boolean)
	for _, part in present.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Massless = carried
			part.CanTouch = false
			part.CanCollide = false
		end
	end
end

-- Recomputes the carrier's slowdown and the attributes the client reads.
local function refreshCarrier(player: Player)
	local list: { Present } = carriedBy[player] or {}
	local slowdown = 0
	for _, present in list do
		slowdown += Config.Rarities[present.rarity].carrySlowdown
	end
	MovementService:SetModifier(player, CARRY_MODIFIER, -slowdown)
	if player.Parent then
		player:SetAttribute("CarryCount", #list)
		player:SetAttribute("CarryCapacity", capacityOf(player))
	end
end

local function removePrompt(present: Present)
	if present.prompt then
		present.prompt:Destroy() -- also disconnects its Triggered connection
		present.prompt = nil
	end
end

-- Welds the present to the character's back. Returns false, changing nothing, if there is no torso.
local function attachToBack(present: Present, character: Model, slot: number): boolean
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return false
	end
	local box = present.box
	setPartsCarried(present, true)
	box.Anchored = false
	-- A character's local +Z is its back. Extra presents (Big Sack) stack upwards.
	local back = torso.Size.Z / 2 + box.Size.Z / 2 + 0.05
	box.CFrame = torso.CFrame * CFrame.new(0, (slot - 1) * box.Size.Y, back)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = box
	weld.Parent = box
	present.weld = weld
	return true
end

local function tryGrab(player: Player, present: Present)
	-- 6.4: a present knocked loose (snowball) or dropped (reset) can be picked up by anyone nearby.
	if present.state ~= "Resting" and present.state ~= "Dropped" then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	local maxDistance = Config.Presents.GrabDistance + Config.Presents.GrabDistanceSlack
	if (root.Position - present.box.Position).Magnitude > maxDistance then
		return
	end
	-- 4.2: only owners of a zone can take its loot, even if they got past the barrier somehow.
	if not ZoneService:OwnsZone(player, present.zone) then
		return
	end
	local list = carriedBy[player]
	if not list or #list >= capacityOf(player) then
		return
	end
	local grabbedFrom = present.box.Position -- read before attaching moves the box
	if not attachToBack(present, character, #list + 1) then
		return
	end
	present.grabbedFrom = grabbedFrom
	present.grabbedAt = os.clock()
	if present.returnTimer then
		task.cancel(present.returnTimer)
		present.returnTimer = nil
	end

	removePrompt(present)
	local point = present.point
	if point then
		point.present = nil
		present.point = nil
		scheduleRespawn(point)
	end
	present.state = "Carried"
	present.carrier = player
	eventPresents[present] = nil -- a grabbed raid present is the thief's, even after the sleigh leaves
	table.insert(list, present)
	refreshCarrier(player)
	GameEvents.fire("PresentGrabbed", player)
end

local function addPrompt(present: Present)
	removePrompt(present)
	local rarity = Config.Rarities[present.rarity]
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Steal"
	prompt.ObjectText = `{present.rarity} Present`
	prompt.HoldDuration = rarity.grabHoldSeconds
	prompt.MaxActivationDistance = Config.Presents.GrabDistance
	prompt.Triggered:Connect(function(player)
		tryGrab(player, present)
	end)
	prompt.Parent = present.box
	present.prompt = prompt
end

local function destroyPresent(present: Present)
	if present.returnTimer then
		task.cancel(present.returnTimer)
		present.returnTimer = nil
	end
	removePrompt(present)
	eventPresents[present] = nil
	present.model:Destroy()
end

local function freePointIn(zone: number): SpawnPoint?
	local points = pointsByZone[zone]
	if not points then
		return nil
	end
	for _, point in points do
		if point.present == nil then
			return point
		end
	end
	return nil
end

function placeAt(present: Present, point: SpawnPoint)
	if point.timer then
		task.cancel(point.timer) -- this present fills the point, so no new one is needed
		point.timer = nil
	end
	if present.weld then
		present.weld:Destroy()
		present.weld = nil
	end
	local box = present.box
	setPartsCarried(present, false)
	box.Anchored = true
	local padTop = point.part.Size.Y / 2
	box.CFrame = point.part.CFrame * CFrame.new(0, padTop + box.Size.Y / 2, 0)
	present.state = "Resting"
	present.carrier = nil
	present.point = point
	point.present = present
	addPrompt(present)
end

-- Wrapping per rarity (step 5.4): paper colour and material, ribbon colour and material, sparkles.
-- Safe to call again on a wrapped present (the tutorial re-wraps one as Rare, 6.5).
local function wrapAs(model: Model, box: BasePart, rarity: Types.Rarity)
	local old = box:FindFirstChild("WrapSparkles")
	if old then
		old:Destroy()
	end
	local wrapping = Config.Wrapping[rarity]
	box.Color = Config.Rarities[rarity].color
	box.Material = wrapping.paper
	box.Reflectance = wrapping.reflectance
	-- Every other part of the template is ribbon or bow (RibbonX/Z, BowL/R).
	local ribbonColor = Config.Rarities[rarity].ribbonColor
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= box then
			part.Color = ribbonColor
			part.Material = wrapping.ribbon
		end
	end
	if wrapping.sparkles > 0 then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "WrapSparkles"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds" -- ships with the client
		emitter.Color = ColorSequence.new(ribbonColor:Lerp(Color3.new(1, 1, 1), 0.5))
		emitter.LightEmission = 1
		emitter.Rate = wrapping.sparkles
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(0.4, 1)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Parent = box
	end
	model:SetAttribute("Rarity", rarity)
end

-- A new present of `rarity`, wrapped to match, in the Presents folder. Not placed yet.
local function buildPresent(rarity: Types.Rarity, zone: number): Present?
	if not template then
		return nil
	end
	local model = template:Clone()
	local box = model.PrimaryPart
	if not box then
		model:Destroy()
		return nil
	end
	wrapAs(model, box, rarity)
	model:SetAttribute("Zone", zone)
	CollectionService:AddTag(model, PRESENT_TAG)
	local present: Present = {
		model = model,
		box = box,
		zone = zone,
		rarity = rarity,
		state = "Resting",
		point = nil,
		carrier = nil,
		weld = nil,
		prompt = nil,
		returnTimer = nil,
		grabbedFrom = nil,
		grabbedAt = nil,
	}
	model.Parent = folder
	return present
end

local function spawnAt(point: SpawnPoint)
	if point.present then
		return
	end
	local present = buildPresent(rollRarity(Config.Zones[point.zone].rarityWeights), point.zone)
	if present then
		placeAt(present, point)
	end
end

function scheduleRespawn(point: SpawnPoint)
	if point.timer then
		return
	end
	local delaySeconds = rng:NextNumber(Config.Presents.RespawnMinSeconds, Config.Presents.RespawnMaxSeconds)
	point.timer = task.delay(delaySeconds, function()
		point.timer = nil
		spawnAt(point)
	end)
end

local function returnToZone(present: Present)
	present.returnTimer = nil
	if present.state ~= "Dropped" then
		return
	end
	local point = freePointIn(present.zone)
	if point then
		placeAt(present, point)
	else
		destroyPresent(present)
	end
end

-- Takes the present off the carrier and leaves it on the ground below where it was.
-- `character` is the body it rode on. Don't use player.Character here: by CharacterRemoving
-- time it can already be the NEW character standing at the spawn (found in the 2.1 playtest).
local function drop(present: Present, player: Player, character: Model?)
	local list = carriedBy[player]
	if list then
		local index = table.find(list, present)
		if index then
			table.remove(list, index)
		end
	end
	if present.weld then
		present.weld:Destroy()
		present.weld = nil
	end

	local box = present.box
	local from = box.Position -- it rode on the carrier's back, so this is where they were
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { folder }
	if character then
		table.insert(exclude, character)
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(from, Vector3.new(0, -DROP_RAY_LENGTH, 0), params)
	local ground = if hit then hit.Position else from
	setPartsCarried(present, false)
	box.Anchored = true
	box.CFrame = CFrame.new(ground + Vector3.new(0, box.Size.Y / 2, 0))

	present.state = "Dropped"
	present.carrier = nil
	present.returnTimer = task.delay(Config.Presents.DroppedReturnSeconds, returnToZone, present)
	addPrompt(present) -- 6.4: anyone nearby may pick it up before it goes home
end

local function dropAll(player: Player, character: Model?)
	local list = carriedBy[player]
	if not list or #list == 0 then
		return
	end
	for _, present in table.clone(list) do
		drop(present, player, character)
	end
	refreshCarrier(player)
end

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local connections = playerConnections[player]
	if not connections or not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	table.insert(
		connections,
		humanoid.Died:Connect(function()
			dropAll(player, character)
		end)
	)
end

local function onPlayerAdded(player: Player)
	if playerConnections[player] then
		return
	end
	carriedBy[player] = {}
	local connections: { RBXScriptConnection } = {}
	playerConnections[player] = connections
	table.insert(
		connections,
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
	)
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function(character)
			dropAll(player, character)
		end)
	)
	local character = player.Character
	if character then
		task.spawn(watchCharacter, player, character)
	end
	refreshCarrier(player)
end

local function onPlayerRemoving(player: Player)
	dropAll(player, player.Character)
	local connections = playerConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	playerConnections[player] = nil
	carriedBy[player] = nil
end

function PresentService:Init()
	local templates = ServerStorage:FindFirstChild("Templates")
	local found = templates and templates:FindFirstChild("Present")
	if found and found:IsA("Model") and found.PrimaryPart then
		template = found
	else
		warn("[PresentService] ServerStorage/Templates/Present (a Model with a PrimaryPart) is missing")
	end

	local existing = workspace:FindFirstChild("Presents")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Presents"
		folder.Parent = workspace
	end

	for _, part in CollectionService:GetTagged("PresentSpawn") do
		local zone = part:GetAttribute("Zone")
		if not part:IsA("BasePart") or not part:IsDescendantOf(workspace) or type(zone) ~= "number" then
			continue
		end
		if zone > Config.LaunchZones or Config.Zones[zone] == nil then
			continue
		end
		local list = pointsByZone[zone]
		if not list then
			list = {}
			pointsByZone[zone] = list
		end
		table.insert(list, { part = part, zone = zone, present = nil, timer = nil })
	end
end

function PresentService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	for _, list in pointsByZone do
		for _, point in list do
			spawnAt(point)
		end
	end
end

-- True if any carried present would have had to move faster than any legal player to reach
-- `position` by now (straight line, horizontal only, so it never punishes a winding route).
-- Catches a teleport from the zone to the drop mat. Step 2.4 security review.
function PresentService:CarriedTooFast(player: Player, position: Vector3): boolean
	local list = carriedBy[player]
	if not list then
		return false
	end
	local limit = Config.AntiCheat.MaxTravelSpeed * Config.AntiCheat.TravelSpeedSlack
	local now = os.clock()
	for _, present in list do
		local from, at = present.grabbedFrom, present.grabbedAt
		if from and at then
			local flat = Vector3.new(position.X - from.X, 0, position.Z - from.Z).Magnitude
			local elapsed = math.max(now - at, 0.001)
			if flat / elapsed > limit then
				return true
			end
		end
	end
	return false
end

-- How many presents the player is carrying right now.
-- The present models on this player's back (the disguise hides them inside the box).
function PresentService:GetCarriedModels(player: Player): { Model }
	local models: { Model } = {}
	local list: { Present } = carriedBy[player] or {}
	for _, present in list do
		table.insert(models, present.model)
	end
	return models
end

function PresentService:GetCarriedCount(player: Player): number
	local list = carriedBy[player]
	return if list then #list else 0
end

-- Hands over everything the player carries (for delivery). The models stay in Workspace,
-- unwelded and anchored where they are; the caller animates and destroys them.
function PresentService:TakeCarried(player: Player): { Delivered }
	local list = carriedBy[player]
	if not list or #list == 0 then
		return {}
	end
	local delivered: { Delivered } = {}
	for _, present in list do
		if present.weld then
			present.weld:Destroy()
			present.weld = nil
		end
		setPartsCarried(present, false)
		present.box.Anchored = true
		present.state = "Delivered"
		present.carrier = nil
		CollectionService:RemoveTag(present.model, PRESENT_TAG)
		table.insert(delivered, { model = present.model, box = present.box, zone = present.zone, rarity = present.rarity })
	end
	carriedBy[player] = {}
	refreshCarrier(player)
	return delivered
end

-- Sends everything the player carries straight back to its zone (used when caught, Phase 3).
function PresentService:ReturnCarried(player: Player)
	local list = carriedBy[player]
	if not list or #list == 0 then
		return
	end
	for _, present in table.clone(list) do
		drop(present, player, player.Character)
		if present.returnTimer then
			task.cancel(present.returnTimer)
		end
		returnToZone(present)
	end
	refreshCarrier(player)
end

-- Sleigh Raid (6.4): `count` presents of Rare or better (Config.SleighRaid.RarityWeights) in a ring
-- around `center` (the pad's top). Zone 0 = the Town: everyone may take them, and a dropped one
-- disappears instead of going home (there is no spawn point for it).
function PresentService:SpawnRaidPresents(center: CFrame, count: number, ringStuds: number)
	for i = 1, count do
		local present = buildPresent(rollRarity(Config.SleighRaid.RarityWeights), 0)
		if present then
			local angle = (i - 1) / count * math.pi * 2
			local spot = center * CFrame.new(math.cos(angle) * ringStuds, 0, math.sin(angle) * ringStuds)
			present.box.Anchored = true
			present.box.CFrame = spot * CFrame.new(0, present.box.Size.Y / 2, 0)
			present.state = "Resting"
			eventPresents[present] = true
			addPrompt(present)
		end
	end
end

-- The sleigh leaves (6.4): raid presents nobody is carrying disappear with it.
function PresentService:ClearRaidPresents()
	for present in table.clone(eventPresents) do
		if present.state ~= "Carried" then
			destroyPresent(present)
		end
	end
end

-- A snowball hit (6.4): everything the player carries falls to the ground at their feet, where
-- anyone can pick it up. Returns how many presents fell.
function PresentService:KnockLoose(player: Player): number
	local list = carriedBy[player]
	local count = if list then #list else 0
	if count > 0 then
		dropAll(player, player.Character)
	end
	return count
end

-- Tutorial (6.5): raises `present` to at least `rarity`, re-wrapping it to match.
local function raiseTo(present: Present, rarity: Types.Rarity)
	local wanted = table.find(Config.RarityOrder, rarity) or 1
	local current = table.find(Config.RarityOrder, present.rarity) or 1
	if current >= wanted then
		return
	end
	present.rarity = rarity
	wrapAs(present.model, present.box, rarity)
	if present.prompt then
		addPrompt(present) -- the prompt shows the rarity and its hold time
	end
	if present.carrier then
		refreshCarrier(present.carrier) -- a heavier present slows the carrier more
	end
end

-- Tutorial (6.5): the resting present in `zone` nearest to `position`, as a Model (nil if none).
-- `keep` is returned instead while it is still resting there, so the trail doesn't jump around.
function PresentService:NearestResting(zone: number, position: Vector3, keep: Model?): Model?
	local best: Model?, bestDistance = nil, math.huge
	local points = pointsByZone[zone]
	if not points then
		return nil
	end
	for _, point in points do
		local present = point.present
		if present and present.state == "Resting" then
			if present.model == keep then
				return keep
			end
			local distance = (present.box.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = present.model, distance
			end
		end
	end
	return best
end

-- Tutorial (6.5): the resting present `model` becomes at least `rarity` (the guaranteed first Rare).
function PresentService:RaiseResting(model: Model, rarity: Types.Rarity)
	for _, list in pointsByZone do
		for _, point in list do
			local present = point.present
			if present and present.model == model and present.state == "Resting" then
				raiseTo(present, rarity)
				return
			end
		end
	end
end

-- Tutorial (6.5): everything `player` carries becomes at least `rarity`. Used on the first grab, in
-- case the new player took a different present from the one the trail led to.
function PresentService:RaiseCarried(player: Player, rarity: Types.Rarity)
	local list = carriedBy[player]
	if not list then
		return
	end
	for _, present in list do
		raiseTo(present, rarity)
	end
end

-- Re-shows the carry capacity after it changed (Big Sack bought, 6.2).
function PresentService:RefreshCapacity(player: Player)
	if player.Parent then
		refreshCarrier(player)
	end
end

return PresentService

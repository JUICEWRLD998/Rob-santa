--!strict
-- Presents: spawn on PresentSpawn points, get grabbed (ProximityPrompt), ride on the thief's back,
-- and go back to their zone if dropped. Delivery and unwrapping live in UnwrapService.
--
-- Rules (docs/01-GAME-DESIGN.md sections 3 and 6):
-- * The wrapping IS the rarity: rolled from the zone table at spawn, wrapping coloured to match.
-- * A grabbed present frees its spawn point, which spawns a new present in 20-40 s.
-- * A dropped present (death, reset, leaving) lies where it fell for 10 s, then goes to a free
--   spawn point in its zone. If the zone is full, it disappears.
-- * Every grab is checked on the server: present still resting, player alive and close, hands free.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local MovementService = require(script.Parent.MovementService)

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
local playerConnections: { [Player]: { RBXScriptConnection } } = {}

-- Forward declarations (these functions call each other).
local placeAt: (present: Present, point: SpawnPoint) -> ()
local scheduleRespawn: (point: SpawnPoint) -> ()

local function rollRarity(zone: number): Types.Rarity
	local weights = Config.Zones[zone].rarityWeights
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll = rng:NextNumber(0, total)
	for tier, weight in weights do
		roll -= weight
		if roll < 0 and weight > 0 then
			return Config.RarityOrder[tier]
		end
	end
	return Config.RarityOrder[1]
end

local function capacityOf(_player: Player): number
	return Config.Presents.CarryCapacity -- Big Sack (Phase 6) raises this to CarryCapacityBigSack
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
	if present.state ~= "Resting" then
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
	local list = carriedBy[player]
	if not list or #list >= capacityOf(player) then
		return
	end
	if not attachToBack(present, character, #list + 1) then
		return
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
	table.insert(list, present)
	refreshCarrier(player)
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

local function spawnAt(point: SpawnPoint)
	if point.present or not template then
		return
	end
	local rarity: Types.Rarity = rollRarity(point.zone)
	local model = template:Clone()
	local box = model.PrimaryPart
	if not box then
		model:Destroy()
		return
	end
	box.Color = Config.Rarities[rarity].color
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Zone", point.zone)
	CollectionService:AddTag(model, PRESENT_TAG)
	local present: Present = {
		model = model,
		box = box,
		zone = point.zone,
		rarity = rarity,
		state = "Resting",
		point = nil,
		carrier = nil,
		weld = nil,
		prompt = nil,
		returnTimer = nil,
	}
	model.Parent = folder
	placeAt(present, point)
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

-- Takes the present off the carrier and leaves it on the ground below them.
local function drop(present: Present, player: Player)
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
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local from = if root and root:IsA("BasePart") then root.Position else box.Position
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
end

local function dropAll(player: Player)
	local list = carriedBy[player]
	if not list or #list == 0 then
		return
	end
	for _, present in table.clone(list) do
		drop(present, player)
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
			dropAll(player)
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
		player.CharacterRemoving:Connect(function()
			dropAll(player)
		end)
	)
	local character = player.Character
	if character then
		task.spawn(watchCharacter, player, character)
	end
	refreshCarrier(player)
end

local function onPlayerRemoving(player: Player)
	dropAll(player)
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

-- How many presents the player is carrying right now.
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
		drop(present, player)
		if present.returnTimer then
			task.cancel(present.returnTimer)
		end
		returnToZone(present)
	end
	refreshCarrier(player)
end

return PresentService

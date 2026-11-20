--!strict
-- Owns the 8 hideouts (cabins). Each joining player gets the lowest-numbered free one, their name
-- goes on its NameSign, and every time their character spawns it is moved onto the hideout's
-- spawn pad, facing the door. The hideout is freed when the player leaves.
-- Hideout parts are found by CollectionService tag + "Hideout" index attribute, never by path.
-- Ownership is mirrored as attributes so clients and other services can read it:
--   hideout Model: OwnerUserId = <UserId>      Player: Hideout = <index>

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local FREE_SIGN_TEXT = "Free Hideout"
local INDEX_ATTRIBUTE = "Hideout" -- on the map parts, and on the Player once assigned
local OWNER_ATTRIBUTE = "OwnerUserId"
local ROOT_WAIT_SECONDS = 10
local SPAWN_CLEARANCE = 0.1 -- studs between feet and pad, so the character never starts inside it

type Hideout = {
	index: number,
	model: Model,
	spawnPad: BasePart,
	sign: BasePart?,
	signLabel: TextLabel?,
	owner: Player?,
}

local PlotService = {}

local hideouts: { Hideout } = {} -- sorted by index
local hideoutOf: { [Player]: Hideout } = {}
local spawnConnections: { [Player]: RBXScriptConnection } = {}

type Listener = (player: Player, index: number) -> ()
local assignedListeners: { Listener } = {}
local releasedListeners: { Listener } = {}

local function notify(listeners: { Listener }, player: Player, index: number)
	for _, listener in listeners do
		task.spawn(listener, player, index)
	end
end

-- The tagged instance in Workspace whose Hideout attribute equals `index`.
local function findTagged(tag: string, index: number): Instance?
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsDescendantOf(workspace) and instance:GetAttribute(INDEX_ATTRIBUTE) == index then
			return instance
		end
	end
	return nil
end

local function setSign(hideout: Hideout, text: string)
	if hideout.signLabel then
		hideout.signLabel.Text = text
	end
end

-- Puts the character's feet on the spawn pad, facing the NameSign (which hangs over the door).
local function moveToHideout(player: Player, character: Model)
	local hideout = hideoutOf[player]
	if not hideout then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", ROOT_WAIT_SECONDS)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	-- The player may have left, or been given another hideout, while we waited.
	if not root or not root:IsA("BasePart") or not humanoid or hideoutOf[player] ~= hideout then
		return
	end

	local pad = hideout.spawnPad
	local padTop = pad.Position.Y + pad.Size.Y / 2
	local rootHeight = humanoid.HipHeight + root.Size.Y / 2 + SPAWN_CLEARANCE
	local position = Vector3.new(pad.Position.X, padTop + rootHeight, pad.Position.Z)

	local facing = pad.CFrame.LookVector
	if hideout.sign then
		local toSign = hideout.sign.Position - position
		local flat = Vector3.new(toSign.X, 0, toSign.Z)
		if flat.Magnitude > 0.01 then
			facing = flat.Unit
		end
	end
	character:PivotTo(CFrame.lookAt(position, position + facing))
end

local function assign(player: Player)
	if hideoutOf[player] then
		return
	end
	local free: Hideout? = nil
	for _, hideout in hideouts do
		if hideout.owner == nil then
			free = hideout
			break
		end
	end
	if not free then
		warn(`[PlotService] no free hideout for {player.Name}; check MaxPlayersPerServer vs hideout count`)
		return
	end

	free.owner = player
	hideoutOf[player] = free
	free.model:SetAttribute(OWNER_ATTRIBUTE, player.UserId)
	player:SetAttribute(INDEX_ATTRIBUTE, free.index)
	-- DisplayName is already filtered by Roblox, so it can be shown without TextService.
	setSign(free, `{player.DisplayName}'s Hideout`)

	spawnConnections[player] = player.CharacterAdded:Connect(function(character)
		moveToHideout(player, character)
	end)
	-- The character can exist before this runs (common in Studio playtests).
	local character = player.Character
	if character then
		task.spawn(moveToHideout, player, character)
	end
	notify(assignedListeners, player, free.index)
end

local function release(player: Player)
	local connection = spawnConnections[player]
	if connection then
		connection:Disconnect()
		spawnConnections[player] = nil
	end
	local hideout = hideoutOf[player]
	if not hideout then
		return
	end
	hideoutOf[player] = nil
	hideout.owner = nil
	hideout.model:SetAttribute(OWNER_ATTRIBUTE, nil)
	setSign(hideout, FREE_SIGN_TEXT)
	notify(releasedListeners, player, hideout.index)
end

function PlotService:Init()
	for _, instance in CollectionService:GetTagged("Hideout") do
		local index = instance:GetAttribute(INDEX_ATTRIBUTE)
		if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) or type(index) ~= "number" then
			continue
		end
		local pad = findTagged("HideoutSpawn", index)
		if not pad or not pad:IsA("BasePart") then
			warn(`[PlotService] Hideout {index} has no HideoutSpawn part; skipping it`)
			continue
		end
		local sign = findTagged("NameSign", index)
		local signPart = if sign and sign:IsA("BasePart") then sign else nil
		local label = sign and sign:FindFirstChildWhichIsA("TextLabel", true)
		local hideout: Hideout = {
			index = index,
			model = instance,
			spawnPad = pad,
			sign = signPart,
			signLabel = if label and label:IsA("TextLabel") then label else nil,
			owner = nil,
		}
		table.insert(hideouts, hideout)
		setSign(hideout, FREE_SIGN_TEXT)
	end
	table.sort(hideouts, function(a, b)
		return a.index < b.index
	end)
	if #hideouts == 0 then
		warn("[PlotService] found no tagged hideouts in Workspace")
	end
end

function PlotService:Start()
	Players.PlayerAdded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
	-- Players who joined before Start ran (common in Studio playtests).
	for _, player in Players:GetPlayers() do
		task.spawn(assign, player)
	end
end

-- The player's hideout model, or nil if they have none.
function PlotService:GetHideout(player: Player): Model?
	local hideout = hideoutOf[player]
	return if hideout then hideout.model else nil
end

-- The player's hideout number (1-8), or nil if they have none.
function PlotService:GetHideoutIndex(player: Player): number?
	local hideout = hideoutOf[player]
	return if hideout then hideout.index else nil
end

-- Who owns hideout `index`, or nil if it is free.
function PlotService:GetOwner(index: number): Player?
	for _, hideout in hideouts do
		if hideout.index == index then
			return hideout.owner
		end
	end
	return nil
end

-- Calls `listener(player, hideoutIndex)` each time a player is given a hideout.
-- Register in Init: assignments start in Start, so nothing is missed.
function PlotService:OnAssigned(listener: Listener)
	table.insert(assignedListeners, listener)
end

-- Calls `listener(player, hideoutIndex)` each time a player's hideout is freed (they left).
function PlotService:OnReleased(listener: Listener)
	table.insert(releasedListeners, listener)
end

-- Moves the player's current character into their hideout (e.g. after jail). No-op if not spawned.
function PlotService:SendHome(player: Player)
	local character = player.Character
	if character then
		task.spawn(moveToHideout, player, character)
	end
end

return PlotService

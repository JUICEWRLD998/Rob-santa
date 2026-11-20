--!strict
-- The ONE place that sets a player's WalkSpeed. Other services never write WalkSpeed directly;
-- they set a named modifier ("carry" = -2, later "boots" = +3, "speedPass" = +4, ...) and this
-- service adds them to Config.Player.WalkSpeed. Modifiers survive respawns.
-- Not exploit-proof on its own: the client owns its character, so speed hacks are checked in Phase 7.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MIN_WALK_SPEED = 4 -- never let stacked slowdowns freeze a player completely

local MovementService = {}

local modifiersOf: { [Player]: { [string]: number } } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

local function apply(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local speed = Config.Player.WalkSpeed
	local modifiers = modifiersOf[player]
	if modifiers then
		for _, amount in modifiers do
			speed += amount
		end
	end
	humanoid.WalkSpeed = math.max(speed, MIN_WALK_SPEED)
end

local function onPlayerAdded(player: Player)
	if characterConnections[player] then
		return
	end
	modifiersOf[player] = modifiersOf[player] or {}
	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid", 10)
		apply(player)
	end)
	apply(player)
end

local function onPlayerRemoving(player: Player)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
	end
	characterConnections[player] = nil
	modifiersOf[player] = nil
end

function MovementService:Init() end

function MovementService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- Sets (or replaces) one named speed change, in studs/second. Pass 0 or nil to remove it.
function MovementService:SetModifier(player: Player, name: string, amount: number?)
	if player.Parent == nil then
		return
	end
	local modifiers = modifiersOf[player]
	if not modifiers then
		modifiers = {}
		modifiersOf[player] = modifiers
	end
	if amount == nil or amount == 0 then
		modifiers[name] = nil
	else
		modifiers[name] = amount
	end
	apply(player)
end

return MovementService

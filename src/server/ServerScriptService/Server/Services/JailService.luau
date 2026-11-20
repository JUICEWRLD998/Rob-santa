--!strict
-- Naughty Jail (step 3.3). docs/01-GAME-DESIGN.md section 8. Every number is in Config.Jail.
-- Caught by an elf: the carried present goes back to its zone, a "NAUGHTY!" stamp plays (the
-- player is held still), then the player is in the coal-mine cell under the Town Square.
-- Three ways out: wait Jail.WaitSeconds; mine Jail.CoalToEscape coal rocks (each rock once per
-- visit); or Bail Out with Robux (Phase 6, will call JailService:Release). Coal mined is kept.
-- No coins are lost: only the present you were carrying.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local PresentService = require(script.Parent.PresentService)

local JAILED_ATTRIBUTE = "Jailed" -- set on the player while jailed (the client reads it)

type Phase = "Stamp" | "Cell"
type Visit = {
	phase: Phase,
	endsAt: number, -- server time (Workspace:GetServerTimeNow) when the wait is over
	mined: { [number]: boolean }, -- CoalRock Index -> mined this visit
	coal: number,
	timer: thread?,
}

local JailService = {}

local visits: { [Player]: Visit } = {}
local rocks: { [number]: BasePart } = {}
local jailSpawn: BasePart? = nil
local jailUpdate: RemoteEvent

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function send(player: Player, visit: Visit?)
	local payload: Types.JailUpdate
	if not visit then
		payload = { state = "Free" }
	else
		local mined: { number } = {}
		for index in visit.mined do
			table.insert(mined, index)
		end
		payload = {
			state = if visit.phase == "Stamp" then "Caught" else "Jailed",
			endsAt = visit.endsAt,
			coal = visit.coal,
			coalNeeded = Config.Jail.CoalToEscape,
			mined = mined,
		}
	end
	jailUpdate:FireClient(player, payload)
end

-- Into the cell, standing on the JailSpawn pad, facing the room.
local function putInCell(player: Player)
	local character = player.Character
	local spawnPad = jailSpawn
	if not character or not spawnPad then
		return
	end
	local standAt = spawnPad.Position + Vector3.new(0, 3, 0)
	local facing = standAt + spawnPad.CFrame.LookVector
	character:PivotTo(CFrame.lookAt(standAt, Vector3.new(facing.X, standAt.Y, facing.Z)))
end

local function release(player: Player)
	local visit = visits[player]
	if not visit then
		return
	end
	visits[player] = nil
	local timer = visit.timer
	if timer and timer ~= coroutine.running() then
		task.cancel(timer)
	end
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	player:SetAttribute(JAILED_ATTRIBUTE, nil)
	PlotService:SendHome(player)
	send(player, nil)
end

local function enterCell(player: Player, visit: Visit)
	if visits[player] ~= visit then
		return
	end
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	visit.phase = "Cell"
	visit.endsAt = Workspace:GetServerTimeNow() + Config.Jail.WaitSeconds
	putInCell(player)
	send(player, visit)
	visit.timer = task.delay(Config.Jail.WaitSeconds, function()
		if visits[player] == visit then
			release(player)
		end
	end)
end

local function tryMine(player: Player, index: number)
	local visit = visits[player]
	local rock = rocks[index]
	if not visit or visit.phase ~= "Cell" or visit.mined[index] or not rock then
		return
	end
	local root = rootOf(player)
	local maxDistance = Config.Jail.MinePromptDistance + Config.Jail.MinePromptDistanceSlack
	if not root or (root.Position - rock.Position).Magnitude > maxDistance then
		return
	end
	visit.mined[index] = true
	visit.coal += 1
	EconomyService:AddCoal(player, 1)
	if visit.coal >= Config.Jail.CoalToEscape then
		release(player)
	else
		send(player, visit)
	end
end

local function setupRocks()
	for _, instance in CollectionService:GetTagged("CoalRock") do
		local index = instance:GetAttribute("Index")
		if instance:IsA("BasePart") and type(index) == "number" then
			rocks[index] = instance
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Mine"
			prompt.ObjectText = "Coal"
			prompt.HoldDuration = Config.Jail.MineHoldSeconds
			prompt.MaxActivationDistance = Config.Jail.MinePromptDistance
			prompt.RequiresLineOfSight = false
			-- Shown only to jailed players by JailController; the server checks anyway.
			prompt.Parent = instance
			prompt.Triggered:Connect(function(player)
				tryMine(player, index)
			end)
		else
			warn(`[JailService] CoalRock {instance:GetFullName()} needs a number Index attribute`)
		end
	end
end

local function onCharacterAdded(player: Player)
	-- Resetting doesn't get you out: back into the cell. PlotService moves a new character to the
	-- hideout on spawn, so wait for that first, then move it here.
	task.delay(0.3, function()
		local visit = visits[player]
		if visit and visit.phase == "Cell" then
			putInCell(player)
		end
	end)
end

function JailService:Init()
	jailUpdate = Remotes.get("JailUpdate")
	local spawns = CollectionService:GetTagged("JailSpawn")
	local first = spawns[1]
	if first and first:IsA("BasePart") then
		jailSpawn = first
	else
		warn("[JailService] no JailSpawn-tagged part; catching will not jail anyone")
	end
	setupRocks()
end

function JailService:Start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local visit = visits[player]
		if visit and visit.timer then
			task.cancel(visit.timer)
		end
		visits[player] = nil
	end)
end

-- Sends a caught player to jail. Returns false if they were already jailed (or can't be).
function JailService:Jail(player: Player): boolean
	if visits[player] or not jailSpawn then
		return false
	end
	PresentService:ReturnCarried(player)
	local visit: Visit = { phase = "Stamp", endsAt = 0, mined = {}, coal = 0, timer = nil }
	visits[player] = visit
	player:SetAttribute(JAILED_ATTRIBUTE, true)
	local root = rootOf(player)
	if root then
		root.Anchored = true -- hold still while the stamp plays
	end
	send(player, visit)
	visit.timer = task.delay(Config.Jail.StampSeconds, enterCell, player, visit)
	return true
end

function JailService:IsJailed(player: Player): boolean
	return visits[player] ~= nil
end

-- Lets the player out now (Phase 6: Bail Out calls this after ProcessReceipt grants it).
function JailService:Release(player: Player)
	release(player)
end

return JailService

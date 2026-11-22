--!strict
-- Snowballs (step 6.4, docs/01-GAME-DESIGN.md sections 7 and 9). Numbers in Config.Upgrades.Snowball
-- and Config.MostWanted.
--   The client only sends where its camera looks (RequestSnowball). The server checks you own the
--   Snowball (Gadget Shop), aren't jailed or wrapped, and the cooldown, then picks the target: the
--   nearest elf, or player carrying a present, in range, inside the aim cone, with a clear line.
--   * Elf    -> stunned for elfStunSeconds (GuardService:StunElf): it stops, can't see, drops a chase.
--   * Player -> everything they carry falls at their feet (PresentService:KnockLoose); anyone may
--               pick it up. If they are Most Wanted, the thrower earns BountyFraction of their coins,
--               paid by the game (nothing is taken from them), at most once per BountyCooldownSeconds
--               per hunter and target.
--   Everyone sees the throw (SnowballFx); the hit lands when the ball arrives.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local DataService = require(script.Parent.DataService)
local DisguiseService = require(script.Parent.DisguiseService)
local EconomyService = require(script.Parent.EconomyService)
local GuardService = require(script.Parent.GuardService)
local JailService = require(script.Parent.JailService)
local MostWantedService = require(script.Parent.MostWantedService)
local PresentService = require(script.Parent.PresentService)

local THROW_HEIGHT = 1.5 -- studs above the thrower's root the ball leaves from

type Target = { kind: "Elf" | "Player", root: BasePart, model: Model, player: Player? }

local SnowballService = {}

local lastThrowAt: { [Player]: number } = {}
local bountyAt: { [Player]: { [number]: number } } = {} -- hunter -> target UserId -> os.clock
local notify: RemoteEvent
local fx: RemoteEvent
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function message(player: Player, text: string)
	if player.Parent then
		notify:FireClient(player, text)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isFinite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < math.huge and math.abs(v.Y) < math.huge and math.abs(v.Z) < math.huge
end

-- Nothing solid between the ball and the target (presents and the two characters don't count).
local function clearLine(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local filter = table.clone(ignore)
	for _, present in CollectionService:GetTagged("Present") do
		table.insert(filter, present)
	end
	rayParams.FilterDescendantsInstances = filter
	return Workspace:Raycast(from, to - from, rayParams) == nil
end

local function candidates(thrower: Player): { Target }
	local list: { Target } = {}
	for _, root in GuardService:GetElfRoots() do
		local model = root.Parent
		if model and model:IsA("Model") then
			table.insert(list, { kind = "Elf", root = root, model = model, player = nil })
		end
	end
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local model = player.Character
		if
			player ~= thrower
			and root
			and model
			and PresentService:GetCarriedCount(player) > 0
			and not DisguiseService:IsDisguised(player)
			and not JailService:IsJailed(player)
		then
			table.insert(list, { kind = "Player", root = root, model = model, player = player })
		end
	end
	return list
end

-- The nearest target in range, inside the aim cone, with a clear line from `origin`.
local function pickTarget(thrower: Player, origin: Vector3, aim: Vector3): Target?
	local settings = Config.Upgrades.Snowball
	local minDot = math.cos(math.rad(settings.aimAngle / 2))
	local ignore: { Instance } = {}
	if thrower.Character then
		table.insert(ignore, thrower.Character)
	end
	local best: Target?, bestDistance = nil, math.huge
	for _, target in candidates(thrower) do
		local offset = target.root.Position - origin
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local distance = flat.Magnitude
		if distance <= settings.rangeStuds and distance < bestDistance and distance > 0.5 then
			if flat.Unit:Dot(aim) >= minDot then
				local ignoreBoth = table.clone(ignore)
				table.insert(ignoreBoth, target.model)
				if clearLine(origin, target.root.Position, ignoreBoth) then
					best, bestDistance = target, distance
				end
			end
		end
	end
	return best
end

local function payBounty(hunter: Player, target: Player)
	if MostWantedService:GetMostWanted() ~= target then
		return
	end
	local settings = Config.MostWanted
	local byTarget = bountyAt[hunter]
	if not byTarget then
		byTarget = {}
		bountyAt[hunter] = byTarget
	end
	local last = byTarget[target.UserId]
	if last and os.clock() - last < settings.BountyCooldownSeconds then
		message(hunter, `You hit {target.DisplayName}! No bounty again so soon.`)
		return
	end
	local amount = math.floor(EconomyService:GetCoins(target) * settings.BountyFraction)
	if amount > 0 and EconomyService:AddCoins(hunter, amount) then
		byTarget[target.UserId] = os.clock()
		message(hunter, `MOST WANTED HIT! Bounty +{StoreCatalog.withCommas(amount)} coins`)
	end
end

local function land(thrower: Player, target: Target, origin: Vector3)
	local settings = Config.Upgrades.Snowball
	if target.kind == "Elf" then
		GuardService:StunElf(target.root, settings.elfStunSeconds)
		return
	end
	local victim = target.player
	if not victim or not victim.Parent or not rootOf(victim) then
		return
	end
	-- It may have moved while the ball flew: still close enough, still not hidden or jailed.
	local flat = Vector3.new(target.root.Position.X - origin.X, 0, target.root.Position.Z - origin.Z).Magnitude
	if flat > settings.rangeStuds + settings.rangeSlackStuds then
		return
	end
	if DisguiseService:IsDisguised(victim) or JailService:IsJailed(victim) then
		return
	end
	if PresentService:KnockLoose(victim) > 0 then
		message(victim, `{thrower.DisplayName} hit you with a snowball! Your present fell.`)
		payBounty(thrower, victim)
	end
end

local function onRequest(player: Player, aim: any)
	if typeof(aim) ~= "Vector3" or not isFinite(aim) then
		return
	end
	local flatAim = Vector3.new(aim.X, 0, aim.Z)
	if flatAim.Magnitude < 0.05 then
		return
	end
	flatAim = flatAim.Unit
	local data = DataService:GetData(player)
	if not data or not data.upgrades.snowball then
		return
	end
	local settings = Config.Upgrades.Snowball
	local now = os.clock()
	local last = lastThrowAt[player]
	if last and now - last < settings.cooldownSeconds then
		return
	end
	local root = rootOf(player)
	if not root or JailService:IsJailed(player) or DisguiseService:IsDisguised(player) then
		return
	end
	lastThrowAt[player] = now
	local origin = root.Position + Vector3.new(0, THROW_HEIGHT, 0)
	local target = pickTarget(player, origin, flatAim)
	if not target then
		-- A throw into the snow: it still flies, so the player sees why nothing happened.
		local to = origin + flatAim * settings.rangeStuds * 0.6 - Vector3.new(0, THROW_HEIGHT + 2, 0)
		fx:FireAllClients(origin, to, (to - origin).Magnitude / settings.flightStudsPerSecond, "Miss")
		return
	end
	local to = target.root.Position
	local seconds = (to - origin).Magnitude / settings.flightStudsPerSecond
	fx:FireAllClients(origin, to, seconds, target.kind)
	task.delay(seconds, land, player, target, origin)
end

function SnowballService:Init() end

function SnowballService:Start()
	notify = Remotes.get("Notify")
	fx = Remotes.get("SnowballFx")
	Remotes.get("RequestSnowball").OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player)
		lastThrowAt[player] = nil
		bountyAt[player] = nil
	end)
end

return SnowballService

--!strict
-- Elf guards. Part 1 (step 3.1): spawn elves per zone and walk each one around its zone's
-- ElfWaypoint route on a loop. Seeing, chasing and catching come in step 3.2.
-- docs/01-GAME-DESIGN.md section 4. Every number is in Config.Guards.
--
-- The server owns elf physics (SetNetworkOwner(nil)) so every player sees the same elf in the same
-- place. Elves sit in their own collision group so two elves never block each other.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local ELF_GROUP = "Elves"
local FOLDER_NAME = "Guards" -- Workspace/Guards, created at boot, holds the live elves
local REACH_DISTANCE = 2.5 -- studs (flat) that count as "arrived at the waypoint"
local CHECK_SECONDS = 0.25
local PROGRESS_STUDS = 0.5 -- moving less than this between checks counts as no progress
-- Roblox's default R15 walk and idle (read from a fresh rig's Animate script, 2026-11-20).
-- Placeholder until the elf's own animations in Phase 5.
local WALK_ANIMATION = "rbxassetid://913402848"
local IDLE_ANIMATION = "rbxassetid://507766388"
local WALK_ANIMATION_BASE_SPEED = 12 -- walk cycle plays at WalkSpeed / this, so feet roughly match

type Route = { BasePart } -- waypoints sorted by their Index attribute

type Elf = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	zone: number,
	route: Route,
	nextIndex: number,
}

local GuardService = {}

local folder: Folder
local routesByZone: { [number]: { [number]: Route } } = {}
local elves: { Elf } = {}
local random = Random.new()

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function collectRoutes()
	for _, instance in CollectionService:GetTagged("ElfWaypoint") do
		local zone = instance:GetAttribute("Zone")
		local routeId = instance:GetAttribute("Route")
		local index = instance:GetAttribute("Index")
		if instance:IsA("BasePart") and type(zone) == "number" and type(routeId) == "number" and type(index) == "number" then
			local routes = routesByZone[zone]
			if not routes then
				routes = {}
				routesByZone[zone] = routes
			end
			local route = routes[routeId]
			if not route then
				route = {}
				routes[routeId] = route
			end
			table.insert(route, instance)
		else
			warn(`[GuardService] ElfWaypoint {instance:GetFullName()} needs number attributes Zone, Route, Index`)
		end
	end
	for _, routes in routesByZone do
		for _, route in routes do
			table.sort(route, function(a, b)
				return (a:GetAttribute("Index") :: number) < (b:GetAttribute("Index") :: number)
			end)
		end
	end
end

local function setupCollisionGroup()
	if not PhysicsService:IsCollisionGroupRegistered(ELF_GROUP) then
		PhysicsService:RegisterCollisionGroup(ELF_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(ELF_GROUP, ELF_GROUP, false)
end

-- Plays the walk cycle while the elf moves and the idle while it stands.
local function animate(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local function load(id: string, priority: Enum.AnimationPriority): AnimationTrack
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = (animator :: Animator):LoadAnimation(animation)
		track.Priority = priority
		track.Looped = true
		return track
	end
	local walk = load(WALK_ANIMATION, Enum.AnimationPriority.Movement)
	local idle = load(IDLE_ANIMATION, Enum.AnimationPriority.Idle)
	idle:Play()
	humanoid.Running:Connect(function(speed: number)
		if speed > 0.5 then
			if not walk.IsPlaying then
				walk:Play(0.2)
			end
			walk:AdjustSpeed(speed / WALK_ANIMATION_BASE_SPEED)
		elseif walk.IsPlaying then
			walk:Stop(0.2)
		end
	end)
end

local function spawnElf(template: Model, zone: number, route: Route, startIndex: number): Elf?
	local model = template:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		warn("[GuardService] Templates/ElfGuard needs a Humanoid and a HumanoidRootPart")
		model:Destroy()
		return nil
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = ELF_GROUP
		end
	end
	humanoid.WalkSpeed = Config.Guards.PatrolWalkSpeed
	humanoid.BreakJointsOnDeath = false
	-- Elves never climb, swim or sit; turning those states off saves work and odd poses.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

	local here = route[startIndex].Position
	local nextIndex = startIndex % #route + 1
	local ahead = route[nextIndex].Position
	local standAt = here + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 + 0.5, 0)
	model:PivotTo(CFrame.lookAt(standAt, Vector3.new(ahead.X, standAt.Y, ahead.Z)))
	model:SetAttribute("Zone", zone)
	model.Name = `Elf_Zone{zone}`
	model.Parent = folder
	root:SetNetworkOwner(nil)
	animate(humanoid)

	return {
		model = model,
		humanoid = humanoid,
		root = root,
		zone = zone,
		route = route,
		nextIndex = nextIndex,
	}
end

-- Walks toward `target` until close, re-issuing MoveTo (it times out after 8 s on its own).
-- If the elf makes no progress for PatrolStuckSeconds and `allowPath` is set, it computes a path
-- around whatever blocks it and follows that instead. Returns true when it arrived.
local followPath: (elf: Elf, target: Vector3) -> boolean

local function walkTo(elf: Elf, target: Vector3, allowPath: boolean): boolean
	local lastPosition = elf.root.Position
	local lastProgressAt = os.clock()
	while elf.model.Parent do
		if flatDistance(elf.root.Position, target) <= REACH_DISTANCE then
			return true
		end
		elf.humanoid:MoveTo(target)
		task.wait(CHECK_SECONDS)
		local position = elf.root.Position
		if (position - lastPosition).Magnitude > PROGRESS_STUDS then
			lastPosition = position
			lastProgressAt = os.clock()
		elseif os.clock() - lastProgressAt > Config.Guards.PatrolStuckSeconds then
			if allowPath then
				return followPath(elf, target)
			end
			return false
		end
	end
	return false
end

followPath = function(elf: Elf, target: Vector3): boolean
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function(): any
		path:ComputeAsync(elf.root.Position, target)
		return nil
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return false
	end
	for i, waypoint in path:GetWaypoints() do
		if i > 1 and not walkTo(elf, waypoint.Position, false) then
			return false
		end
	end
	return true
end

local function patrol(elf: Elf)
	while elf.model.Parent do
		local waypoint = elf.route[elf.nextIndex]
		if not walkTo(elf, waypoint.Position, true) then
			warn(`[GuardService] {elf.model.Name} could not reach waypoint {elf.nextIndex}; skipping it`)
		end
		elf.humanoid:MoveTo(elf.root.Position) -- stop on the spot
		elf.nextIndex = elf.nextIndex % #elf.route + 1
		task.wait(Config.Guards.PatrolPauseSeconds)
	end
end

function GuardService:Init()
	setupCollisionGroup()
	collectRoutes()
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
end

function GuardService:Start()
	local templates = ServerStorage:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("ElfGuard")
	if not template or not template:IsA("Model") then
		warn("[GuardService] ServerStorage/Templates/ElfGuard is missing; no elves spawned")
		return
	end
	for zone = 1, Config.LaunchZones do
		local settings = Config.Guards.ByZone[zone]
		local routes = routesByZone[zone]
		if settings and routes then
			-- All of a zone's elves share its routes, spread out evenly along them.
			local count = random:NextInteger(settings.elvesMin, settings.elvesMax)
			local routeList: { Route } = {}
			for _, route in routes do
				if #route >= 2 then
					table.insert(routeList, route)
				end
			end
			for i = 1, count do
				local route = routeList[(i - 1) % #routeList + 1]
				if route then
					local startIndex = math.floor((i - 1) * #route / count) % #route + 1
					local elf = spawnElf(template, zone, route, startIndex)
					if elf then
						table.insert(elves, elf)
						task.spawn(patrol, elf)
					end
				end
			end
		end
	end
	print(`[GuardService] {#elves} elves on patrol`)
end

return GuardService

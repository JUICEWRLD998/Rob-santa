--!strict
-- Elf guards. docs/01-GAME-DESIGN.md section 4. Every number is in Config.Guards.
--   Part 1 (step 3.1): spawn elves per zone; each walks its zone's ElfWaypoint route on a loop.
--   Part 2 (step 3.2): a vision cone (drawn on the floor) plus a line-of-sight raycast, checked
--   VisionChecksPerSecond times a second. Seeing a player: "HEY!" + whistle, "!" over its head,
--   then a chase at the zone's chase speed for up to ChaseMaxSeconds, giving up after
--   GiveUpAfterLostSightSeconds without sight. Touching the player while chasing = caught.
--   For now a catch only prints "CAUGHT"; Naughty Jail is step 3.3.
--
-- The server owns elf physics (SetNetworkOwner(nil)) so every player sees the same elf in the same
-- place. Elves sit in their own collision group so two elves never block each other.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local ELF_GROUP = "Elves"
local FOLDER_NAME = "Guards" -- Workspace/Guards, created at boot, holds the live elves
local REACH_DISTANCE = 2.5 -- studs (flat) that count as "arrived at the waypoint"
local CHECK_SECONDS = 0.25
local PROGRESS_STUDS = 0.5 -- moving less than this between checks counts as no progress
local CATCH_HEIGHT = 4 -- a player standing on cover this far above the elf can't be grabbed
-- Roblox's default R15 walk and idle (read from a fresh rig's Animate script, 2026-11-20).
-- Placeholder until the elf's own animations in Phase 5.
local WALK_ANIMATION = "rbxassetid://913402848"
local IDLE_ANIMATION = "rbxassetid://507766388"
local WALK_ANIMATION_BASE_SPEED = 12 -- walk cycle plays at WalkSpeed / this, so feet roughly match
-- Floor cone colours (placeholder look until Phase 5): calm when patrolling, red when chasing.
local CONE_PATROL_COLOR = Color3.fromRGB(255, 214, 64)
local CONE_CHASE_COLOR = Color3.fromRGB(255, 72, 64)
local CONE_THICKNESS = 0.05

type Route = { BasePart } -- waypoints sorted by their Index attribute
type State = "Patrol" | "Chase"

type Elf = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	head: BasePart,
	zone: number,
	route: Route,
	nextIndex: number,
	state: State,
	target: Player?,
	ignoreUntil: { [Player]: number },
	cone: { BasePart },
	alert: BillboardGui?,
	alertText: TextLabel?,
	alertSound: Sound?,
}

local GuardService = {}

local folder: Folder
local routesByZone: { [number]: { [number]: Route } } = {}
local elves: { Elf } = {}
local random = Random.new()
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

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

-- One flat triangle on the floor, from two wedges (the standard two-WedgePart triangle).
local function triangle(a: Vector3, b: Vector3, c: Vector3, parent: Instance, out: { BasePart })
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local shapes = {
		{ size = Vector3.new(CONE_THICKNESS, height, math.abs(ab:Dot(back))), cframe = CFrame.fromMatrix((a + b) / 2, right, up, back) },
		{ size = Vector3.new(CONE_THICKNESS, height, math.abs(ac:Dot(back))), cframe = CFrame.fromMatrix((a + c) / 2, -right, up, -back) },
	}
	for _, shape in shapes do
		local wedge = Instance.new("WedgePart")
		wedge.Size = shape.size
		wedge.CFrame = shape.cframe
		wedge.Anchored = false
		wedge.CanCollide = false
		wedge.CanTouch = false
		wedge.CanQuery = false
		wedge.CastShadow = false
		wedge.Massless = true
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.Color = CONE_PATROL_COLOR
		wedge.Transparency = Config.Guards.ConeTransparency
		wedge.CollisionGroup = ELF_GROUP
		wedge.Parent = parent
		table.insert(out, wedge)
	end
end

-- The vision cone drawn on the floor in front of the elf, welded to it so it follows.
local function buildCone(model: Model, root: BasePart, humanoid: Humanoid, range: number, angle: number): { BasePart }
	local cone: { BasePart } = {}
	local coneFolder = Instance.new("Model")
	coneFolder.Name = "VisionCone"
	coneFolder.Parent = model
	local floorY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2 + 0.08
	local apex = Vector3.new(root.Position.X, floorY, root.Position.Z)
	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	local slices = Config.Guards.ConeSlices
	local half = math.rad(angle / 2)
	local points: { Vector3 } = {}
	for i = 0, slices do
		local theta = -half + (2 * half) * i / slices
		local direction = CFrame.Angles(0, theta, 0):VectorToWorldSpace(forward)
		table.insert(points, apex + direction * range)
	end
	for i = 1, slices do
		triangle(apex, points[i], points[i + 1], coneFolder, cone)
	end
	for _, part in cone do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	return cone
end

local function setConeColor(elf: Elf, color: Color3)
	for _, part in elf.cone do
		part.Color = color
	end
end

local function spawnElf(template: Model, zone: number, route: Route, startIndex: number): Elf?
	local settings = Config.Guards.ByZone[zone]
	local model = template:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if not humanoid or not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") then
		warn("[GuardService] Templates/ElfGuard needs a Humanoid, a HumanoidRootPart and a Head")
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
	local cone = buildCone(model, root, humanoid, settings.visionRange, settings.visionAngle)
	model:SetAttribute("Zone", zone)
	model.Name = `Elf_Zone{zone}`
	model.Parent = folder
	root:SetNetworkOwner(nil)
	animate(humanoid)

	local alert = head:FindFirstChild("Alert")
	local alertText = alert and alert:FindFirstChild("Text")
	local alertSound = head:FindFirstChild("AlertSound")
	return {
		model = model,
		humanoid = humanoid,
		root = root,
		head = head,
		zone = zone,
		route = route,
		nextIndex = nextIndex,
		state = "Patrol",
		target = nil,
		ignoreUntil = setmetatable({}, { __mode = "k" }) :: any,
		cone = cone,
		alert = if alert and alert:IsA("BillboardGui") then alert else nil,
		alertText = if alertText and alertText:IsA("TextLabel") then alertText else nil,
		alertSound = if alertSound and alertSound:IsA("Sound") then alertSound else nil,
	}
end

----------------------------------------------------------------------------------------------------
-- Sight

-- Clear line from the elf's head to the player's head or body. Walls and cover block it; elves,
-- the player's own character and presents (a carried box on your back) do not.
local function hasLineOfSight(elf: Elf, character: Model): boolean
	local filter: { Instance } = { folder, character }
	for _, present in CollectionService:GetTagged("Present") do
		table.insert(filter, present)
	end
	rayParams.FilterDescendantsInstances = filter
	local origin = elf.head.Position
	for _, name in { "Head", "HumanoidRootPart" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			if not Workspace:Raycast(origin, part.Position - origin, rayParams) then
				return true
			end
		end
	end
	return false
end

local function inCone(elf: Elf, position: Vector3, range: number, angle: number): boolean
	local offset = Vector3.new(position.X - elf.root.Position.X, 0, position.Z - elf.root.Position.Z)
	local distance = offset.Magnitude
	if distance > range then
		return false
	end
	if distance < 0.5 then
		return true
	end
	local look = elf.root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	return forward:Dot(offset.Unit) >= math.cos(math.rad(angle / 2))
end

type Target = { character: Model, humanoid: Humanoid, root: BasePart }

local function liveTarget(player: Player): Target?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return { character = character, humanoid = humanoid, root = root }
	end
	return nil
end

-- The nearest player this patrolling elf can see right now, if any.
local function findVisiblePlayer(elf: Elf): Player?
	local settings = Config.Guards.ByZone[elf.zone]
	local now = os.clock()
	local best: Player?, bestDistance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local ignoredUntil = elf.ignoreUntil[player]
		local target = liveTarget(player)
		if target and not (ignoredUntil and now < ignoredUntil) then
			local position = target.root.Position
			if inCone(elf, position, settings.visionRange, settings.visionAngle) and hasLineOfSight(elf, target.character) then
				local distance = flatDistance(elf.root.Position, position)
				if distance < bestDistance then
					best, bestDistance = player, distance
				end
			end
		end
	end
	return best
end

----------------------------------------------------------------------------------------------------
-- Moving

-- Walks toward `target` until close, re-issuing MoveTo (it times out after 8 s on its own).
-- If the elf makes no progress for PatrolStuckSeconds and `allowPath` is set, it computes a path
-- around whatever blocks it and follows that instead. Stops early when the elf leaves Patrol
-- (it spotted someone). Returns true when it arrived.
local followPath: (elf: Elf, target: Vector3) -> boolean

local function walkTo(elf: Elf, target: Vector3, allowPath: boolean): boolean
	local lastPosition = elf.root.Position
	local lastProgressAt = os.clock()
	while elf.model.Parent and elf.state == "Patrol" do
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

local function computePath(from: Vector3, to: Vector3): { Vector3 }?
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
	local ok = pcall(function(): any
		path:ComputeAsync(from, to)
		return nil
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local points: { Vector3 } = {}
	for _, waypoint in path:GetWaypoints() do
		table.insert(points, waypoint.Position)
	end
	return points
end

followPath = function(elf: Elf, target: Vector3): boolean
	local points = computePath(elf.root.Position, target)
	if not points then
		return false
	end
	for i, point in points do
		if i > 1 and not walkTo(elf, point, false) then
			return false
		end
	end
	return true
end

local function nearestWaypointIndex(elf: Elf): number
	local best, bestDistance = 1, math.huge
	for i, waypoint in elf.route do
		local distance = flatDistance(elf.root.Position, waypoint.Position)
		if distance < bestDistance then
			best, bestDistance = i, distance
		end
	end
	return best
end

----------------------------------------------------------------------------------------------------
-- Patrol and chase

local function patrolStep(elf: Elf)
	local waypoint = elf.route[elf.nextIndex]
	local arrived = walkTo(elf, waypoint.Position, true)
	if elf.state ~= "Patrol" then
		return -- spotted someone on the way; the chase takes over
	end
	if not arrived then
		warn(`[GuardService] {elf.model.Name} could not reach waypoint {elf.nextIndex}; skipping it`)
	end
	elf.humanoid:MoveTo(elf.root.Position) -- stop on the spot
	elf.nextIndex = elf.nextIndex % #elf.route + 1
	local pauseUntil = os.clock() + Config.Guards.PatrolPauseSeconds
	while elf.state == "Patrol" and os.clock() < pauseUntil do
		task.wait(CHECK_SECONDS)
	end
end

local function setAlert(elf: Elf, on: boolean)
	local alert, text = elf.alert, elf.alertText
	if alert then
		alert.Enabled = on
	end
	setConeColor(elf, if on then CONE_CHASE_COLOR else CONE_PATROL_COLOR)
	if on then
		if text then
			text.Text = "HEY!"
			task.delay(Config.Guards.HeyShowSeconds, function()
				if elf.state == "Chase" then
					text.Text = "!"
				end
			end)
		end
		if elf.alertSound then
			elf.alertSound:Play()
		end
	end
end

local function onCaught(elf: Elf, player: Player)
	-- TEMPORARY until Naughty Jail (step 3.3): just report it and leave the player alone a moment.
	print(`[GuardService] CAUGHT {player.Name} (elf in zone {elf.zone})`)
	elf.ignoreUntil[player] = os.clock() + Config.Guards.CaughtIgnoreSeconds
end

local function runChase(elf: Elf)
	local guards = Config.Guards
	local settings = guards.ByZone[elf.zone]
	local player = elf.target
	elf.humanoid.WalkSpeed = settings.chaseSpeed
	setAlert(elf, true)
	local startedAt = os.clock()
	local lastSeenAt = startedAt
	local lastSeenPosition: Vector3? = nil
	local pathPoints: { Vector3 }? = nil
	local pathTried = false
	local pathIndex = 2
	while elf.model.Parent and player and player.Parent do
		local target = liveTarget(player)
		local now = os.clock()
		if not target or now - startedAt > guards.ChaseMaxSeconds then
			break
		end
		local targetPosition = target.root.Position
		if
			flatDistance(elf.root.Position, targetPosition) <= guards.CatchDistance
			and math.abs(elf.root.Position.Y - targetPosition.Y) <= CATCH_HEIGHT
		then
			onCaught(elf, player)
			break
		end
		-- While chasing, the elf has turned toward you: sight = in range + clear line, any angle.
		local seen = flatDistance(elf.root.Position, targetPosition) <= settings.visionRange
			and hasLineOfSight(elf, target.character)
		if seen then
			lastSeenAt = now
			lastSeenPosition = targetPosition
			pathPoints, pathTried = nil, false
			elf.humanoid:MoveTo(targetPosition)
		elseif now - lastSeenAt > guards.GiveUpAfterLostSightSeconds then
			break
		elseif lastSeenPosition then
			-- Lost sight: path around the corner to where it last saw you.
			if not pathTried then
				pathTried = true
				pathPoints = computePath(elf.root.Position, lastSeenPosition)
				pathIndex = 2
			end
			local points = pathPoints
			local goal = lastSeenPosition
			if points and points[pathIndex] then
				if flatDistance(elf.root.Position, points[pathIndex]) <= REACH_DISTANCE then
					pathIndex += 1
				end
				goal = points[pathIndex] or lastSeenPosition
			end
			elf.humanoid:MoveTo(goal)
		end
		task.wait(guards.ChaseTickSeconds)
	end
	-- Back to patrol from the nearest point on its route.
	elf.state = "Patrol"
	elf.target = nil
	elf.humanoid.WalkSpeed = guards.PatrolWalkSpeed
	setAlert(elf, false)
	elf.nextIndex = nearestWaypointIndex(elf)
end

local function run(elf: Elf)
	while elf.model.Parent do
		if elf.state == "Chase" then
			runChase(elf)
		else
			patrolStep(elf)
		end
	end
end

-- About VisionChecksPerSecond times a second, every patrolling elf looks for players.
local function visionLoop()
	local interval = 1 / Config.Guards.VisionChecksPerSecond
	while true do
		task.wait(interval)
		for _, elf in elves do
			if elf.state == "Patrol" and elf.model.Parent then
				local player = findVisiblePlayer(elf)
				if player then
					elf.target = player
					elf.state = "Chase"
				end
			end
		end
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
						task.spawn(run, elf)
					end
				end
			end
		end
	end
	task.spawn(visionLoop)
	print(`[GuardService] {#elves} elves on patrol`)
end

return GuardService

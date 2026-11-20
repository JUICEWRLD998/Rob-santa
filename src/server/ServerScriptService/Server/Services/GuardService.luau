--!strict
-- Elf guards. docs/01-GAME-DESIGN.md section 4. Every number is in Config.Guards.
--   Part 1 (step 3.1): spawn elves per zone; each walks its zone's ElfWaypoint route on a loop.
--   Part 2 (step 3.2): a vision cone (drawn on the floor) plus a line-of-sight raycast, checked
--   VisionChecksPerSecond times a second. Seeing a player: "HEY!" + whistle, "!" over its head,
--   then a chase at the zone's chase speed for up to ChaseMaxSeconds, giving up after
--   GiveUpAfterLostSightSeconds without sight. Touching the player while chasing = caught.
--   A catch sends the player to Naughty Jail (JailService, step 3.3).
--   Disguise (step 3.4): patrollers ignore a still gift box; a chasing elf walks up and sniffs it.
--   Step 3.5: Snowman Cameras (zone 2+) sweep and ring a bell: every patrolling elf in the zone
--   runs to where it saw you for alarmChaseSeconds. Head Elf (zone 3): 1.3x, faster, sniffs 5 s.
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
local DisguiseService = require(script.Parent.DisguiseService)
local JailService = require(script.Parent.JailService)

local ELF_GROUP = "Elves"
local FOLDER_NAME = "Guards" -- Workspace/Guards, created at boot, holds the live elves
local REACH_DISTANCE = 2.5 -- studs (flat) that count as "arrived at the waypoint"
local CHECK_SECONDS = 0.25
local PROGRESS_STUDS = 0.5 -- moving less than this between checks counts as no progress
local CATCH_HEIGHT = 4 -- a player standing on cover this far above the elf can't be grabbed
local INSPECT_STEP_SECONDS = 0.05 -- distance checks while creeping up on a gift box
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
	isHead: boolean, -- Head Elf (zone 3): bigger, faster, sniffs longer
	chaseSpeed: number,
	inspectSeconds: number,
	alarmPosition: Vector3?, -- set by a Snowman Camera bell: chase starts toward here
}

-- Snowman Camera (step 3.5): stands still, turns left and right, rings a bell when it sees you.
type Snowman = {
	model: Model,
	head: BasePart, -- sight starts here
	base: CFrame, -- facing the middle of the sweep
	zone: number,
	cone: { BasePart },
	bell: BillboardGui,
	ringUntil: number, -- os.clock: cone red and "DING DING!" shown until then
	cooldown: { [Player]: number },
}

local GuardService = {}

local folder: Folder
local routesByZone: { [number]: { [number]: Route } } = {}
local zoneAreas: { [number]: BasePart } = {} -- ZoneArea-tagged box per zone: elves never chase past it
local elves: { Elf } = {}
local snowmen: { Snowman } = {}
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

local function collectZoneAreas()
	for _, instance in CollectionService:GetTagged("ZoneArea") do
		local zone = instance:GetAttribute("Zone")
		if zone == nil and instance.Parent then
			zone = instance.Parent:GetAttribute("Zone")
		end
		if instance:IsA("BasePart") and type(zone) == "number" then
			zoneAreas[zone] = instance
		end
	end
end

-- Elves guard their own room only: a player outside it can't be spotted, and a chase that would
-- cross the edge counts as losing sight (the elf stops where it last saw you, inside the zone).
local function insideZone(zone: number, position: Vector3): boolean
	local area = zoneAreas[zone]
	if not area then
		return true -- no ZoneArea box for this zone: don't limit (warned once at boot)
	end
	local localPosition = area.CFrame:PointToObjectSpace(position)
	local half = area.Size / 2
	return math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y and math.abs(localPosition.Z) <= half.Z
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

-- The Head Elf's mark until Phase 5 art: a gold hat (it is also 1.3x taller).
local function addHeadElfHat(head: BasePart)
	local hat = Instance.new("Part")
	hat.Name = "HeadElfHat"
	hat.Shape = Enum.PartType.Cylinder
	hat.Size = Vector3.new(0.5, head.Size.X * 1.1, head.Size.X * 1.1)
	hat.Color = Color3.fromRGB(255, 196, 40)
	hat.Material = Enum.Material.Neon
	hat.CanCollide = false
	hat.CanTouch = false
	hat.CanQuery = false
	hat.Massless = true
	hat.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.25, 0) * CFrame.Angles(0, 0, math.rad(90))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = hat
	weld.Parent = hat
	hat.Parent = head
end

local function spawnElf(template: Model, zone: number, route: Route, startIndex: number, isHead: boolean): Elf?
	local settings = Config.Guards.ByZone[zone]
	local headSettings = Config.Guards.HeadElf
	local model = template:Clone()
	if isHead then
		model:ScaleTo(headSettings.scale)
	end
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
	if isHead then
		addHeadElfHat(head)
	end
	model:SetAttribute("Zone", zone)
	model.Name = if isHead then `HeadElf_Zone{zone}` else `Elf_Zone{zone}`
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
		isHead = isHead,
		chaseSpeed = if isHead then headSettings.chaseSpeed else settings.chaseSpeed,
		inspectSeconds = if isHead then headSettings.inspectSeconds else Config.Disguise.InspectSeconds,
		alarmPosition = nil,
	}
end

----------------------------------------------------------------------------------------------------
-- Sight

-- Clear line from the elf's head to the player's head or body. Walls and cover block it; elves,
-- the player's own character and presents (a carried box on your back) do not.
local function lineOfSightFrom(origin: Vector3, character: Model): boolean
	local filter: { Instance } = { folder, character }
	for _, present in CollectionService:GetTagged("Present") do
		table.insert(filter, present)
	end
	rayParams.FilterDescendantsInstances = filter
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

local function hasLineOfSight(elf: Elf, character: Model): boolean
	return lineOfSightFrom(elf.head.Position, character)
end

-- Is `position` inside the flat cone at `origin` facing `look` (range in studs, full angle in degrees)?
local function coneContains(origin: Vector3, look: Vector3, position: Vector3, range: number, angle: number): boolean
	local offset = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
	local distance = offset.Magnitude
	if distance > range then
		return false
	end
	if distance < 0.5 then
		return true
	end
	local forward = Vector3.new(look.X, 0, look.Z).Unit
	return forward:Dot(offset.Unit) >= math.cos(math.rad(angle / 2))
end

local function inCone(elf: Elf, position: Vector3, range: number, angle: number): boolean
	return coneContains(elf.root.Position, elf.root.CFrame.LookVector, position, range, angle)
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
		-- A patrolling elf walks right past a still gift box (a disguised player is always still).
		if target and not (ignoredUntil and now < ignoredUntil) and not DisguiseService:IsDisguised(player) then
			local position = target.root.Position
			if
				insideZone(elf.zone, position)
				and inCone(elf, position, settings.visionRange, settings.visionAngle)
				and hasLineOfSight(elf, target.character)
			then
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
	elf.ignoreUntil[player] = os.clock() + Config.Guards.CaughtIgnoreSeconds
	JailService:Jail(player)
end

-- Puts words over the elf's head (the same sign as "HEY!").
local function say(elf: Elf, text: string)
	if elf.alert then
		elf.alert.Enabled = true
	end
	if elf.alertText then
		elf.alertText.Text = text
	end
end

-- The disguise moment (section 5). The player turned into a gift box mid-chase: walk to the box,
-- stop, face it and sniff for InspectSeconds.
--   Fooled  = they held still the whole time (or the elf couldn't reach the box).
--   Gotcha  = they moved while being sniffed.
--   Visible = they popped out before the elf got there: keep chasing.
--   Gone    = they left or the elf was removed.
type InspectResult = "Fooled" | "Gotcha" | "Visible" | "Gone"

local function inspect(elf: Elf, player: Player): InspectResult
	local settings = Config.Disguise
	local tick = Config.Guards.ChaseTickSeconds
	local boxAt = DisguiseService:GetBoxPosition(player)
	if not boxAt then
		return "Visible"
	end
	-- Creep up on the box: slow to a walk for the last few studs and check often, so a fast elf
	-- never overshoots and shoves the hidden player (a shove counted as "you moved" = an unfair
	-- GOTCHA, found in 3.5 testing with the Head Elf at speed 17). Bigger elves stop further back.
	local reach = settings.InspectReachStuds * (if elf.isHead then Config.Guards.HeadElf.scale else 1)
	local walkStart = os.clock()
	while true do
		local distance = flatDistance(elf.root.Position, boxAt)
		if distance <= reach then
			break
		elseif not elf.model.Parent or not liveTarget(player) then
			return "Gone"
		elseif not DisguiseService:IsDisguised(player) then
			elf.humanoid.WalkSpeed = elf.chaseSpeed
			return "Visible"
		elseif os.clock() - walkStart > settings.InspectWalkMaxSeconds then
			return "Fooled" -- blocked on the way: it loses interest
		end
		if distance <= reach + settings.InspectCreepStuds then
			elf.humanoid.WalkSpeed = Config.Guards.PatrolWalkSpeed
		end
		elf.humanoid:MoveTo(boxAt)
		task.wait(if distance <= reach + settings.InspectCreepStuds then INSPECT_STEP_SECONDS else tick)
	end
	elf.humanoid:MoveTo(elf.root.Position)
	local here = elf.root.Position
	elf.root.CFrame = CFrame.lookAt(here, Vector3.new(boxAt.X, here.Y, boxAt.Z))
	if not DisguiseService:IsDisguised(player) then
		return "Visible"
	end
	DisguiseService:BeginInspect(player)
	local result: InspectResult = "Fooled"
	local endsAt = os.clock() + elf.inspectSeconds
	local step = 0
	while os.clock() < endsAt do
		if not elf.model.Parent or not liveTarget(player) then
			result = "Gone"
			break
		elseif not DisguiseService:IsDisguised(player) then
			result = "Gotcha"
			break
		end
		say(elf, if (step // 5) % 2 == 0 then "*sniff*" else "*sniff sniff*")
		step += 1
		task.wait(0.1)
	end
	DisguiseService:EndInspect(player, result == "Fooled")
	return result
end

local function runChase(elf: Elf)
	local guards = Config.Guards
	local settings = guards.ByZone[elf.zone]
	local player = elf.target
	elf.humanoid.WalkSpeed = elf.chaseSpeed
	setAlert(elf, true)
	local startedAt = os.clock()
	local lastSeenAt = startedAt
	-- A Snowman Camera bell: run to where the snowman saw you, and keep looking for the whole
	-- alarm time instead of giving up 3 s after losing sight.
	local alarmedAt = elf.alarmPosition
	elf.alarmPosition = nil
	local chaseLimit = if alarmedAt then guards.SnowmanCamera.alarmChaseSeconds else guards.ChaseMaxSeconds
	local lostSightLimit = if alarmedAt then chaseLimit else guards.GiveUpAfterLostSightSeconds
	local lastSeenPosition: Vector3? = alarmedAt
	local pathPoints: { Vector3 }? = nil
	local pathTried = false
	local pathIndex = 2
	local lastWords: string? = nil -- said after the chase ends ("...Huh. Just a present.", "GOTCHA!")
	while elf.model.Parent and player and player.Parent do
		local target = liveTarget(player)
		local now = os.clock()
		if not target or now - startedAt > chaseLimit then
			break
		end
		if DisguiseService:IsDisguised(player) then
			local result = inspect(elf, player)
			if result == "Gotcha" then
				lastWords = "GOTCHA!"
				onCaught(elf, player)
				break
			elseif result == "Fooled" then
				lastWords = "...Huh. Just a present."
				elf.ignoreUntil[player] = os.clock() + Config.Disguise.FooledIgnoreSeconds
				break
			elseif result == "Gone" then
				break
			end
			lastSeenAt = os.clock() -- "Visible": they popped out in front of it; chase on
			elf.humanoid.WalkSpeed = elf.chaseSpeed -- back to full speed after creeping up
			continue
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
		-- Leaving its zone counts as lost sight, so it never follows you out.
		local seen = insideZone(elf.zone, targetPosition)
			and flatDistance(elf.root.Position, targetPosition) <= settings.visionRange
			and hasLineOfSight(elf, target.character)
		if seen then
			lastSeenAt = now
			lastSeenPosition = targetPosition
			pathPoints, pathTried = nil, false
			elf.humanoid:MoveTo(targetPosition)
		elseif now - lastSeenAt > lostSightLimit then
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
	-- Back to patrol from the nearest point on its route. It leaves this player alone a moment,
	-- otherwise it would re-spot them the same instant and the chase limit would mean nothing.
	if player then
		local cooldownEnd = os.clock() + guards.GiveUpCooldownSeconds
		elf.ignoreUntil[player] = math.max(elf.ignoreUntil[player] or 0, cooldownEnd)
	end
	elf.state = "Patrol"
	elf.target = nil
	elf.humanoid.WalkSpeed = guards.PatrolWalkSpeed
	setAlert(elf, false)
	elf.nextIndex = nearestWaypointIndex(elf)
	local words = lastWords
	if words then
		say(elf, words)
		task.delay(Config.Disguise.HuhShowSeconds, function()
			local text = elf.alertText
			if elf.alert and elf.state == "Patrol" and text and text.Text == words then
				elf.alert.Enabled = false
			end
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- Snowman Camera (step 3.5, section 4). Placeholder snowman built from parts until Phase 5 art.

-- Every patrolling elf in the zone hears the bell and runs to where the snowman saw the player.
local function soundAlarm(zone: number, player: Player, position: Vector3)
	local now = os.clock()
	for _, elf in elves do
		local ignoredUntil = elf.ignoreUntil[player]
		if elf.zone == zone and elf.state == "Patrol" and elf.model.Parent and not (ignoredUntil and now < ignoredUntil) then
			elf.alarmPosition = position
			elf.target = player
			elf.state = "Chase"
		end
	end
end

local function snowPart(model: Model, name: string, shape: Enum.PartType, size: Vector3, offset: CFrame, base: CFrame, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = base * offset
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = name == "Base" -- you bump into the snowman, not its hat
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.Parent = model
	return part
end

local function buildSnowman(spot: BasePart, zone: number): Snowman?
	local area = zoneAreas[zone]
	local settings = Config.Guards.SnowmanCamera
	local floorY = spot.Position.Y + spot.Size.Y / 2
	local at = Vector3.new(spot.Position.X, floorY, spot.Position.Z)
	-- Face the middle of the room (the spots themselves all face -Z).
	local middle = if area then area.Position else at + spot.CFrame.LookVector
	local base = CFrame.lookAt(at, Vector3.new(middle.X, floorY, middle.Z))
	local model = Instance.new("Model")
	model.Name = `SnowmanCamera_Zone{zone}`
	local white = Color3.fromRGB(245, 248, 255)
	local snow = Enum.Material.Snow
	local ball = Enum.PartType.Ball
	local bottom = snowPart(model, "Base", ball, Vector3.one * 4.4, CFrame.new(0, 2.2, 0), base, white, snow)
	snowPart(model, "Middle", ball, Vector3.one * 3.2, CFrame.new(0, 5.3, 0), base, white, snow)
	local head = snowPart(model, "Head", ball, Vector3.one * 2.4, CFrame.new(0, 7.7, 0), base, white, snow)
	local black = Color3.fromRGB(20, 20, 24)
	snowPart(model, "EyeL", ball, Vector3.one * 0.35, CFrame.new(-0.42, 8.0, -1.05), base, black, Enum.Material.SmoothPlastic)
	snowPart(model, "EyeR", ball, Vector3.one * 0.35, CFrame.new(0.42, 8.0, -1.05), base, black, Enum.Material.SmoothPlastic)
	snowPart(model, "Nose", Enum.PartType.Block, Vector3.new(0.3, 0.3, 1), CFrame.new(0, 7.7, -1.5), base, Color3.fromRGB(255, 140, 40), Enum.Material.SmoothPlastic)
	snowPart(model, "Hat", Enum.PartType.Cylinder, Vector3.new(1.4, 1.8, 1.8), CFrame.new(0, 9.4, 0) * CFrame.Angles(0, 0, math.rad(90)), base, black, Enum.Material.SmoothPlastic)
	local lantern = snowPart(model, "Lantern", Enum.PartType.Block, Vector3.one * 0.8, CFrame.new(1.9, 5.4, -1.3), base, Color3.fromRGB(255, 210, 90), Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = lantern
	model.PrimaryPart = bottom

	-- Its sight drawn on the floor, like an elf's cone; turns with the snowman.
	local cone: { BasePart } = {}
	local apex = Vector3.new(at.X, floorY + 0.08, at.Z)
	local forward = base.LookVector
	local half = math.rad(settings.visionAngle / 2)
	local slices = Config.Guards.ConeSlices
	local points: { Vector3 } = {}
	for i = 0, slices do
		local theta = -half + (2 * half) * i / slices
		table.insert(points, apex + CFrame.Angles(0, theta, 0):VectorToWorldSpace(forward) * settings.visionRange)
	end
	for i = 1, slices do
		triangle(apex, points[i], points[i + 1], model, cone)
	end
	for _, part in cone do
		part.Anchored = true
	end

	-- "DING DING!" over its hat when it rings (AlwaysOnTop off: screen_capture can't see it on).
	local bell = Instance.new("BillboardGui")
	bell.Name = "Bell"
	bell.Size = UDim2.fromScale(6, 2)
	bell.StudsOffset = Vector3.new(0, 3, 0)
	bell.AlwaysOnTop = false
	bell.Enabled = false
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.fromRGB(255, 72, 64)
	text.TextStrokeTransparency = 0
	text.Text = "DING DING!"
	text.Parent = bell
	bell.Parent = head

	model.Parent = folder -- inside Guards: sight rays skip it, like elves
	return {
		model = model,
		head = head,
		base = base * CFrame.new(0, 2.2, 0), -- pivot = the base ball's centre
		zone = zone,
		cone = cone,
		bell = bell,
		ringUntil = 0,
		cooldown = setmetatable({}, { __mode = "k" }) :: any,
	}
end

local function setSnowmanRinging(snowman: Snowman, on: boolean)
	snowman.bell.Enabled = on
	for _, part in snowman.cone do
		part.Color = if on then CONE_CHASE_COLOR else CONE_PATROL_COLOR
	end
end

-- Turns every snowman left and right: sweepDegrees in total, one edge to the other in sweepSeconds.
local function sweepLoop()
	local settings = Config.Guards.SnowmanCamera
	local amplitude = math.rad(settings.sweepDegrees / 2)
	local period = settings.sweepSeconds * 2
	while true do
		local now = os.clock()
		local yaw = amplitude * math.sin(2 * math.pi * now / period)
		for _, snowman in snowmen do
			if snowman.model.Parent then
				snowman.model:PivotTo(snowman.base * CFrame.Angles(0, yaw, 0))
				if snowman.bell.Enabled and now >= snowman.ringUntil then
					setSnowmanRinging(snowman, false)
				end
			end
		end
		task.wait(1 / 30)
	end
end

-- One sight check for one snowman: rings for the first player it sees (not a still gift box).
local function snowmanLook(snowman: Snowman)
	local settings = Config.Guards.SnowmanCamera
	local now = os.clock()
	local origin = snowman.model:GetPivot()
	for _, player in Players:GetPlayers() do
		local target = liveTarget(player)
		local cooldownEnd = snowman.cooldown[player]
		if target and not (cooldownEnd and now < cooldownEnd) and not DisguiseService:IsDisguised(player) then
			local position = target.root.Position
			if
				insideZone(snowman.zone, position)
				and coneContains(origin.Position, origin.LookVector, position, settings.visionRange, settings.visionAngle)
				and lineOfSightFrom(snowman.head.Position, target.character)
			then
				snowman.cooldown[player] = now + settings.alarmCooldownSeconds
				snowman.ringUntil = now + settings.bellShowSeconds
				setSnowmanRinging(snowman, true)
				soundAlarm(snowman.zone, player, position)
				return
			end
		end
	end
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
		for _, snowman in snowmen do
			if snowman.model.Parent then
				snowmanLook(snowman)
			end
		end
	end
end

function GuardService:Init()
	setupCollisionGroup()
	collectRoutes()
	collectZoneAreas()
	for zone = 1, Config.LaunchZones do
		if not zoneAreas[zone] then
			warn(`[GuardService] no ZoneArea part for zone {zone}: its elves can chase anywhere`)
		end
	end
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
			-- Head Elves (zone 3) walk the same routes, as extra elves.
			local regular = random:NextInteger(settings.elvesMin, settings.elvesMax)
			local count = regular + settings.headElves
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
					local elf = spawnElf(template, zone, route, startIndex, i > regular)
					if elf then
						table.insert(elves, elf)
						task.spawn(run, elf)
					end
				end
			end
		end
	end
	-- Snowman Cameras stand on SnowmanCameraSpot parts (Zone attribute), up to the zone's count.
	local spotsByZone: { [number]: { BasePart } } = {}
	for _, spot in CollectionService:GetTagged("SnowmanCameraSpot") do
		local zone = spot:GetAttribute("Zone")
		if spot:IsA("BasePart") and type(zone) == "number" then
			spotsByZone[zone] = spotsByZone[zone] or {}
			table.insert(spotsByZone[zone], spot)
		end
	end
	for zone = 1, Config.LaunchZones do
		local wanted = Config.Guards.ByZone[zone].snowmanCameras
		local spots = spotsByZone[zone] or {}
		table.sort(spots, function(a, b)
			return ((a:GetAttribute("Index") or 0) :: number) < ((b:GetAttribute("Index") or 0) :: number)
		end)
		if #spots < wanted then
			warn(`[GuardService] zone {zone} wants {wanted} Snowman Camera(s) but has {#spots} SnowmanCameraSpot(s)`)
		end
		for i = 1, math.min(wanted, #spots) do
			local snowman = buildSnowman(spots[i], zone)
			if snowman then
				table.insert(snowmen, snowman)
			end
		end
	end
	task.spawn(sweepLoop)
	task.spawn(visionLoop)
	print(`[GuardService] {#elves} elves on patrol, {#snowmen} snowman camera(s)`)
end

return GuardService

--!strict
-- The tutorial on this screen (step 6.5). Display only: TutorialService decides the step and sends
-- it on TutorialSync (Types.TutorialSync). This draws:
--   * one short hint line (TutorialGui.Hint, place file) under the coins. It steps aside while a
--     toast is showing, so the two never overlap.
--   * a glowing footprint trail on the ground from you to the target, and a bobbing arrow over it.
--   * a pulse on the button the step needs: Wrap! while the tutorial elf chases you, SHOP at the end.
-- The trail and arrow are local parts (CanCollide/CanQuery/CanTouch off) that only this player sees.

local ContextActionService = game:GetService("ContextActionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local GUI_WAIT_SECONDS = 15
local REFRESH_SECONDS = 0.2
local WRAP_BUTTON_LOOKUP_SECONDS = 2 -- how often the Wrap! button is looked up again (it can be rebuilt)
local HINT_PADDING = 28 -- pixels of pill around the hint text
local HINT_HEIGHT = 30 -- pixels, one line
local HINT_MIN_WIDTH = 200 -- pixels: the measuring width never goes below this
local HINT_FONT = Enum.Font.FredokaOne -- the Hint label's font, for measuring
local HINT_MAX_WIDTH = 0.9 -- of the screen width
local TRAIL_COLOR = Color3.fromRGB(255, 214, 64) -- the HUD gold
local FOOT_SIZE = Vector3.new(0.7, 0.08, 1.1)
local FOOT_SIDE_STUDS = 0.4 -- left and right prints sit this far either side of the path
local TRAIL_START_STUDS = 2.5 -- the first print sits this far ahead of you
local ARROW_HEIGHT = 5 -- studs above the target's top
local ARROW_BOB_STUDS = 0.8
local ARROW_SPIN_DEGREES = 90 -- per second, so it reads from every side
local PULSE = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local PULSE_SCALE = 1.18

local TutorialController = {}

local player = Players.LocalPlayer
local step: Types.TutorialStep = "Off"
local target: Instance? = nil
local wrapped = false

local trailFolder: Folder? = nil
local footprints: { BasePart } = {}
local arrow: Model? = nil
local pathPoints: { Vector3 } = {}
local pathFor: Instance? = nil
local pathAt = 0
local computing = false

local pulsing: { [Instance]: Tween } = {}

local function lastInput(): "Touch" | "Gamepad" | "Keyboard"
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		return "Touch"
	elseif string.find(last.Name, "Gamepad") then
		return "Gamepad"
	end
	return "Keyboard"
end

local function hintText(): string?
	local input = lastInput()
	if step == "Grab" then
		return "Steal Santa's presents! Follow the footprints."
	elseif step == "Bring" then
		if wrapped then
			return "Don't move! Let it sniff..."
		elseif (player:GetAttribute("ChasedBy") or 0) :: number > 0 then
			local how = if input == "Touch" then "Tap Wrap!" elseif input == "Gamepad" then "Press Y" else "Press Q"
			return `An elf saw you! {how} to turn into a present!`
		end
		return "Bring it home to your mat!"
	elseif step == "Shelf" then
		return "Put your toy on a shelf!"
	elseif step == "Earn" then
		return "Your toy earns coins every second!"
	elseif step == "Shop" then
		local how = if input == "Touch" then "Tap" else "Click"
		return `Here are some coins! {how} SHOP and buy Boots.`
	elseif step == "Done" then
		return "Deeper zones have better loot... Good luck, thief!"
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Trail and arrow

local function newPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = TRAIL_COLOR
	return part
end

local function ensureTrail(): Folder
	local existing = trailFolder
	if existing and existing.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "TutorialTrail"
	folder.Parent = Workspace
	trailFolder = folder
	footprints = {}
	for i = 1, Config.Tutorial.FootprintCount do
		local foot = newPart(`Footprint{i}`, FOOT_SIZE)
		foot.Transparency = 1
		foot.Parent = folder
		footprints[i] = foot
	end
	-- A downward chevron: two bars in a V, spinning slowly.
	local model = Instance.new("Model")
	model.Name = "TutorialArrow"
	local left = newPart("Left", Vector3.new(0.5, 2.4, 0.5))
	local right = newPart("Right", Vector3.new(0.5, 2.4, 0.5))
	left.CFrame = CFrame.new(-0.75, 0, 0) * CFrame.Angles(0, 0, math.rad(35))
	right.CFrame = CFrame.new(0.75, 0, 0) * CFrame.Angles(0, 0, math.rad(-35))
	left.Parent = model
	right.Parent = model
	model.WorldPivot = CFrame.new() -- the V's centre; PivotTo moves both bars together
	model.Parent = folder
	arrow = model
	return folder
end

local function hideTrail()
	for _, foot in footprints do
		foot.Transparency = 1
	end
	local model = arrow
	if model then
		model:PivotTo(CFrame.new(0, -500, 0))
	end
end

local function targetPosition(): (Vector3?, number)
	local current = target
	if current and current:IsA("BasePart") and current:IsDescendantOf(Workspace) then
		return current.Position, current.Size.Y / 2
	elseif current and current:IsA("Model") and current:IsDescendantOf(Workspace) then
		local cframe, size = current:GetBoundingBox()
		return cframe.Position, size.Y / 2
	end
	return nil, 0
end

local function rootOf(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Path from you to the target, re-computed every TrailRefreshSeconds in the background.
local function refreshPath(from: Vector3, to: Vector3)
	if computing or (pathFor == target and os.clock() - pathAt < Config.Tutorial.TrailRefreshSeconds) then
		return
	end
	computing = true
	local wanted = target
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function(): any
			path:ComputeAsync(from, to)
			return nil
		end)
		local points: { Vector3 } = {}
		if ok and path.Status == Enum.PathStatus.Success then
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
		else
			points = { from, to } -- no path found: a straight line still points the way
		end
		if wanted == target then
			pathPoints = points
			pathFor = wanted
			pathAt = os.clock()
		end
		computing = false
	end)
end

-- Lays the prints along the path, starting a little ahead of you, alternating left and right.
local function drawFootprints(root: BasePart)
	local spacing = Config.Tutorial.FootprintSpacing
	local points = pathPoints
	if #points < 2 then
		return
	end
	-- Start from the path point nearest to you, so the trail doesn't lag behind once you walk on.
	local startIndex, nearest = 1, math.huge
	for i, point in points do
		local distance = (Vector3.new(point.X, 0, point.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
		if distance < nearest then
			startIndex, nearest = i, distance
		end
	end
	local placed = 0
	local walked = -TRAIL_START_STUDS
	local nextAt = 0
	for i = math.max(1, startIndex), #points - 1 do
		local a, b = points[i], points[i + 1]
		local segment = b - a
		local flat = Vector3.new(segment.X, 0, segment.Z)
		local length = flat.Magnitude
		if length < 0.01 then
			continue
		end
		local direction = flat.Unit
		local side = Vector3.new(-direction.Z, 0, direction.X)
		while nextAt <= walked + length and placed < #footprints do
			local along = nextAt - walked
			if along >= 0 then
				placed += 1
				local spot = a + segment * (along / length)
				local offset = side * (if placed % 2 == 0 then FOOT_SIDE_STUDS else -FOOT_SIDE_STUDS)
				local foot = footprints[placed]
				local position = spot + offset + Vector3.new(0, FOOT_SIZE.Y / 2 + 0.03, 0)
				foot.CFrame = CFrame.lookAt(position, position + direction)
				-- Prints fade out further along the trail.
				foot.Transparency = 0.15 + 0.6 * (placed / #footprints)
			end
			nextAt += spacing
		end
		walked += length
		if placed >= #footprints then
			break
		end
	end
	for i = placed + 1, #footprints do
		footprints[i].Transparency = 1
	end
end

local function updateTrail()
	local position, halfHeight = targetPosition()
	local root = rootOf()
	if not position or not root or player:GetAttribute("Jailed") == true then
		hideTrail()
		return
	end
	ensureTrail()
	refreshPath(root.Position, position)
	if pathFor == target then
		drawFootprints(root)
	end
	local model = arrow
	if model then
		local t = os.clock()
		local bob = math.sin(t * 3) * ARROW_BOB_STUDS
		local spin = math.rad(t * ARROW_SPIN_DEGREES)
		model:PivotTo(CFrame.new(position + Vector3.new(0, halfHeight + ARROW_HEIGHT + bob, 0)) * CFrame.Angles(0, spin, 0))
	end
end

----------------------------------------------------------------------------------------------------
-- Button pulses

local function setPulse(button: GuiObject?, on: boolean)
	if not button then
		return
	end
	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = button
	local current = pulsing[button]
	if on and not current then
		scale.Scale = 1
		local tween = TweenService:Create(scale, PULSE, { Scale = PULSE_SCALE })
		pulsing[button] = tween
		tween:Play()
	elseif not on and current then
		current:Cancel()
		pulsing[button] = nil
		scale.Scale = 1
	end
end

----------------------------------------------------------------------------------------------------

function TutorialController:Init() end

function TutorialController:Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("TutorialGui", GUI_WAIT_SECONDS)
	if not gui then
		warn("[TutorialController] still waiting for PlayerGui/TutorialGui (StarterGui in the place file)")
		gui = playerGui:WaitForChild("TutorialGui")
	end
	local hud = playerGui:WaitForChild("HudGui", GUI_WAIT_SECONDS) or playerGui:WaitForChild("HudGui")
	local hint = gui:WaitForChild("Hint", GUI_WAIT_SECONDS)
	local label = hint and hint:FindFirstChild("Text")
	if not (hint and hint:IsA("Frame") and label and label:IsA("TextLabel")) then
		warn("[TutorialController] TutorialGui needs a Hint frame with a Text label")
		return
	end
	local toast = hud:FindFirstChild("Toast")
	local shopButton = hud:FindFirstChild("ShopButton")
	hint.Visible = false

	Remotes.get("TutorialSync").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.step) ~= "string" then
			return
		end
		step = (payload.step :: any) :: Types.TutorialStep
		target = if typeof(payload.target) == "Instance" then payload.target else nil
		pathPoints = {}
		pathFor = nil
		if step ~= "Bring" then
			wrapped = false
		end
	end)
	Remotes.get("DisguiseUpdate").OnClientEvent:Connect(function(update: any)
		if type(update) == "table" then
			wrapped = update.state == "Wrapped" or update.state == "Inspected"
		end
	end)

	local shownText: string? = nil
	RunService.RenderStepped:Connect(function()
		if target then
			updateTrail()
		elseif arrow then
			hideTrail()
		end
	end)
	-- One refresh of the hint and the button pulses. Run inside pcall by the loop below, so one bad
	-- refresh (a button the engine owns, a screen that is not ready) can never stop the hint for good.
	local warned = false
	-- ContextActionService:GetButton can yield on a touch device; looked up in its own thread, so a
	-- slow lookup never holds up the hint (on the phone emulator the hint never appeared, 2026-11-22).
	local cachedWrapButton: GuiObject? = nil
	task.spawn(function()
		while true do
			cachedWrapButton = ContextActionService:GetButton("Disguise")
			task.wait(WRAP_BUTTON_LOOKUP_SECONDS)
		end
	end)
	local function refreshHint()
		local text = hintText()
		-- The hint steps aside while a toast is showing (they share the spot under the coins).
		local toastShowing = toast ~= nil and toast:IsA("GuiObject") and toast.Visible
		hint.Visible = text ~= nil and not toastShowing
		if text and text ~= shownText then
			shownText = text
			label.Text = text
			label.TextWrapped = true
			label.TextTruncate = Enum.TextTruncate.None
		end
		if text then
			-- Measured, not read from TextBounds (a truncated label reports its cut width). A line
			-- too long for a phone wraps onto a second line instead of being cut off. Measured every
			-- refresh, and never below HINT_MIN_WIDTH: on a phone the screen size reads tiny for
			-- a moment at start, and a negative width made GetTextSize throw and stop this loop.
			local camera = Workspace.CurrentCamera
			local screen = if camera then camera.ViewportSize.X else 800
			local maxWidth = math.max(HINT_MIN_WIDTH, screen * HINT_MAX_WIDTH)
			local ok, size = pcall(TextService.GetTextSize, TextService, text, label.TextSize, HINT_FONT, Vector2.new(maxWidth - HINT_PADDING, 1000))
			if ok then
				hint.Size = UDim2.fromOffset(math.ceil(size.X) + HINT_PADDING, math.max(HINT_HEIGHT, math.ceil(size.Y) + 10))
			end
		end
		local chased = ((player:GetAttribute("ChasedBy") or 0) :: number) > 0
		local wrapButton = cachedWrapButton
		setPulse(wrapButton, step == "Bring" and chased and not wrapped)
		setPulse(if shopButton and shopButton:IsA("GuiObject") then shopButton else nil, step == "Shop")
	end
	task.spawn(function()
		while true do
			-- (pcall of a function returning nothing types as one value: CLAUDE.md, check.sh gotcha)
			local ok, err = pcall(function(): any
				refreshHint()
				return nil
			end)
			if not ok and not warned then
				warned = true
				warn(`[TutorialController] hint refresh failed: {err}`)
			end
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return TutorialController

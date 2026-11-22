--!strict
-- Snowballs on this screen (step 6.4). Input and display only; SnowballService decides.
--   Input: F on PC, ButtonB on console, a "Snow" button left of the Wrap! button on phone
--   (ContextActionService). Bound only once you own the Snowball (Shop_Snowball attribute) and
--   hidden while you're in jail or a gift box. Sends where the camera looks; the server picks the target.
--   Every throw anyone makes (SnowballFx) is drawn here: a white ball on an arc and a puff of snow.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))

local ACTION = "Snowball"
local OWNED_ATTRIBUTE = ShopCatalog.attributeName("Snowball")
local TOUCH_BUTTON_SIZE = 56 -- pixels: smaller than the jump button, so the right side stays clear (2026-11-22)
local TOUCH_BUTTON_GAP = 10 -- pixels between the Snow button and the Wrap! button
local TITLE_REFRESH_SECONDS = 0.2
local BALL_SIZE = 0.9
local ARC_HEIGHT_PER_STUD = 0.12 -- (my pick) how high the ball arcs, per stud it flies
local PUFF_PARTICLES = 14

local SnowballController = {}

local player = Players.LocalPlayer
local bound = false
local readyAt = 0 -- os.clock; the server keeps the real cooldown, this only drives the title

local function owned(): boolean
	local level = player:GetAttribute(OWNED_ATTRIBUTE)
	return type(level) == "number" and level >= 1
end

local function onAction(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local camera = Workspace.CurrentCamera
	if not camera or os.clock() < readyAt then
		return Enum.ContextActionResult.Sink
	end
	readyAt = os.clock() + Config.Upgrades.Snowball.cooldownSeconds
	Remotes.get("RequestSnowball"):FireServer(camera.CFrame.LookVector)
	return Enum.ContextActionResult.Sink
end

-- Left of the Wrap! button, in the bottom row with it and the jump button. Above the jump
-- button it touched the ROBUX button on small phones, and above Wrap! it met the toast (A06, 2026-11-22).
local watched: GuiObject? = nil
local function placeTouchButton()
	local button = ContextActionService:GetButton(ACTION)
	local wrap = ContextActionService:GetButton("Disguise")
	local frame = button and button.Parent
	if not button or not wrap or not frame or not frame:IsA("GuiObject") then
		return
	end
	button.Size = UDim2.fromOffset(TOUCH_BUTTON_SIZE, TOUCH_BUTTON_SIZE)
	local x = wrap.AbsolutePosition.X - frame.AbsolutePosition.X - TOUCH_BUTTON_SIZE - TOUCH_BUTTON_GAP
	local y = wrap.AbsolutePosition.Y - frame.AbsolutePosition.Y + (wrap.AbsoluteSize.Y - TOUCH_BUTTON_SIZE) / 2
	ContextActionService:SetPosition(ACTION, UDim2.fromOffset(x, y))
	if watched ~= wrap then
		-- The Wrap! button moves once the touch controls arrive; follow it.
		watched = wrap
		wrap:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeTouchButton)
		wrap:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTouchButton)
	end
end

local function refreshButton()
	local button = ContextActionService:GetButton(ACTION)
	if not button then
		return
	end
	button.Visible = player:GetAttribute("Jailed") ~= true and player:GetAttribute("Disguised") ~= true
	local left = readyAt - os.clock()
	ContextActionService:SetTitle(ACTION, if left > 0 then `{math.ceil(left)}s` else "Snow")
end

local function refreshBinding()
	if owned() and not bound then
		bound = true
		ContextActionService:BindAction(ACTION, onAction, true, Enum.KeyCode.F, Enum.KeyCode.ButtonB)
		placeTouchButton()
		refreshButton()
	elseif not owned() and bound then
		bound = false
		ContextActionService:UnbindAction(ACTION)
	end
end

-- A puff of snow where the ball lands.
local function puff(at: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = at
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds" -- ships with the client
	emitter.Color = ColorSequence.new(Color3.fromRGB(245, 250, 255))
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Rate = 0
	emitter.Parent = anchor
	anchor.Parent = Workspace
	emitter:Emit(PUFF_PARTICLES)
	Debris:AddItem(anchor, 1)
end

local function onThrow(from: any, to: any, seconds: any, _hit: any)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or type(seconds) ~= "number" then
		return
	end
	local duration = math.clamp(seconds, 0.05, 3)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE)
	ball.Color = Color3.fromRGB(248, 252, 255)
	ball.Material = Enum.Material.Snow
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Position = from
	ball.Parent = Workspace
	local arc = (to - from).Magnitude * ARC_HEIGHT_PER_STUD
	local started = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - started) / duration)
		ball.Position = from:Lerp(to, t) + Vector3.new(0, arc * 4 * t * (1 - t), 0)
		if t >= 1 then
			if connection then
				connection:Disconnect()
			end
			ball:Destroy()
			puff(to)
		end
	end)
end

function SnowballController:Init() end

function SnowballController:Start()
	Remotes.get("SnowballFx").OnClientEvent:Connect(onThrow)
	player:GetAttributeChangedSignal(OWNED_ATTRIBUTE):Connect(refreshBinding)
	player:GetAttributeChangedSignal("Jailed"):Connect(refreshButton)
	player:GetAttributeChangedSignal("Disguised"):Connect(refreshButton)
	refreshBinding()
	-- TouchGui (thumbstick and jump) only exists on touch devices and can arrive after this runs.
	local playerGui = player:WaitForChild("PlayerGui")
	playerGui.DescendantAdded:Connect(function(added)
		if added.Name == "JumpButton" and bound then
			task.defer(placeTouchButton)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(TITLE_REFRESH_SECONDS)
			if bound and watched == nil then
				placeTouchButton() -- the Wrap! button may not exist yet when the Snowball is bound
			end
			if bound then
				refreshButton()
			end
		end
	end)
end

return SnowballController

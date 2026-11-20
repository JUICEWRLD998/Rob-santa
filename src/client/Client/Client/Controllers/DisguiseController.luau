--!strict
-- The gift-box disguise on this screen (step 3.4). Display and input only; DisguiseService decides.
--   Input: Q on PC, ButtonY on console, a big "Wrap!" button on phone (ContextActionService).
--   HUD:   HudGui.Wraps shows Wraps left and the cooldown; HudGui.DontMove pulses while an elf
--          is sniffing you, and the camera pushes in slightly (section 5 "Feel").

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local ACTION = "Disguise"
local GUI_WAIT_SECONDS = 15
local STATUS_REFRESH_SECONDS = 0.2
local PUSH_IN_FOV = 58 -- camera field of view while an elf sniffs you (default is 70)
local CAMERA_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local PULSE = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local TOUCH_BUTTON_SIZE = 90 -- pixels: "a big gift-box button on phone"

local DisguiseController = {}

local player = Players.LocalPlayer
local wrapsCount: TextLabel? = nil
local wrapsStatus: TextLabel? = nil
local dontMove: TextLabel? = nil
local dontMovePulse: Tween? = nil

local wrapped = false
local endsAt = 0
local readyAt = 0
local normalFov: number? = nil

local function wraps(): number
	local value = player:GetAttribute("Wraps")
	return if type(value) == "number" then value else 0
end

local function refreshHud()
	local now = Workspace:GetServerTimeNow()
	local status: string
	if wrapped then
		status = `Wrapped {math.max(0, math.ceil(endsAt - now))}s`
	elseif now < readyAt then
		status = `Ready in {math.ceil(readyAt - now)}s`
	elseif wraps() <= 0 then
		status = "Refill at home"
	else
		status = "Press Q"
	end
	if wrapsCount then
		wrapsCount.Text = `Wraps {wraps()}`
	end
	if wrapsStatus then
		wrapsStatus.Text = status
	end
	ContextActionService:SetTitle(ACTION, if wrapped then "Unwrap" else `Wrap! ({wraps()})`)
end

local function pushCamera(on: boolean)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if on then
		normalFov = normalFov or camera.FieldOfView
		TweenService:Create(camera, CAMERA_TWEEN, { FieldOfView = PUSH_IN_FOV }):Play()
	elseif normalFov then
		TweenService:Create(camera, CAMERA_TWEEN, { FieldOfView = normalFov }):Play()
		normalFov = nil
	end
end

local function showDontMove(on: boolean)
	local label = dontMove
	if not label then
		return
	end
	label.Visible = on
	if dontMovePulse then
		dontMovePulse:Cancel()
		dontMovePulse = nil
	end
	local scale = label:FindFirstChildOfClass("UIScale")
	if on and scale then
		scale.Scale = 1
		local pulse = TweenService:Create(scale, PULSE, { Scale = 1.12 })
		dontMovePulse = pulse
		pulse:Play()
	end
end

local function onUpdate(value: any)
	if type(value) ~= "table" then
		return
	end
	local state = value.state
	if type(value.endsAt) == "number" then
		endsAt = value.endsAt
	end
	if type(value.readyAt) == "number" then
		readyAt = value.readyAt
	end
	if state == "Wrapped" then
		wrapped = true
	elseif state == "Inspected" then
		wrapped = true
		showDontMove(true)
		pushCamera(true)
	elseif state == "Fooled" or state == "Gotcha" then
		showDontMove(false)
		pushCamera(false)
	elseif state == "Ended" then
		wrapped = false
		showDontMove(false)
		pushCamera(false)
	end
	refreshHud()
end

local function onAction(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		Remotes.get("RequestDisguise"):FireServer()
	end
	return Enum.ContextActionResult.Sink
end

function DisguiseController:Init() end

function DisguiseController:Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("HudGui", GUI_WAIT_SECONDS)
	if not gui then
		-- Slow devices can take longer: say so, then keep waiting rather than give up for good.
		warn("[DisguiseController] still waiting for PlayerGui/HudGui")
		gui = playerGui:WaitForChild("HudGui")
	end
	if gui then
		local pill = gui:FindFirstChild("Wraps")
		local count = pill and pill:FindFirstChild("Count")
		local status = pill and pill:FindFirstChild("Status")
		local warning = gui:FindFirstChild("DontMove")
		wrapsCount = if count and count:IsA("TextLabel") then count else nil
		wrapsStatus = if status and status:IsA("TextLabel") then status else nil
		dontMove = if warning and warning:IsA("TextLabel") then warning else nil
	end
	if not wrapsCount or not dontMove then
		warn("[DisguiseController] HudGui.Wraps or HudGui.DontMove is missing (StarterGui/HudGui in the place file)")
	end

	ContextActionService:BindAction(ACTION, onAction, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	local button = ContextActionService:GetButton(ACTION)
	if button then
		button.Size = UDim2.fromOffset(TOUCH_BUTTON_SIZE, TOUCH_BUTTON_SIZE)
		ContextActionService:SetPosition(ACTION, UDim2.new(1, -(TOUCH_BUTTON_SIZE + 110), 1, -(TOUCH_BUTTON_SIZE + 20)))
	end

	Remotes.get("DisguiseUpdate").OnClientEvent:Connect(onUpdate)
	player:GetAttributeChangedSignal("Wraps"):Connect(refreshHud)
	task.spawn(function()
		while true do
			refreshHud()
			task.wait(STATUS_REFRESH_SECONDS)
		end
	end)
end

return DisguiseController

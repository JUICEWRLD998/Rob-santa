--!strict
-- Naughty Jail on screen (step 3.3). Fills and animates PlayerGui.JailGui (built in the place file):
--   Caught -> the "NAUGHTY!" stamp slams in.
--   Jailed -> the top panel shows "Free in Ns" and "Coal c / n"; the bottom hint says how to mine;
--             coal rock prompts show only for rocks not mined yet this visit (mined ones fade).
--   Free   -> everything hides, rock prompts off.
-- Display only: JailService decides when you're in, when you're out, and counts the coal.
-- Payload shape: Types.JailUpdate (validated field by field below; the client trusts nothing).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local GUI_WAIT_SECONDS = 15 -- same as HudController; PlayerGui fills when the character first loads
local TIMER_REFRESH_SECONDS = 0.2
local STAMP_START_SCALE = 2.6
local STAMP_SLAM = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local STAMP_FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local MINED_FADE = 0.75 -- how see-through a mined rock gets

local JailController = {}

local player = Players.LocalPlayer
local stamp: Frame
local stampScale: UIScale
local stampText: TextLabel
local stampStroke: UIStroke
local panel: Frame
local timerLabel: TextLabel
local coalLabel: TextLabel
local hint: TextLabel? -- bottom-of-screen "how to get out" line (JailGui.Hint)

-- nil when free; otherwise the CoalRock indexes already mined this visit.
local minedRocks: { [number]: boolean }? = nil
local endsAt = 0
local timerThread: thread? = nil

-- Prompts only while jailed and only on rocks not mined yet. A mined rock also fades and its
-- ember goes dark, on this screen only (LocalTransparencyModifier), so you can see which are left.
local function setRockPrompts()
	local mined = minedRocks
	for _, rock in CollectionService:GetTagged("CoalRock") do
		local index = rock:GetAttribute("Index")
		local done = mined ~= nil and type(index) == "number" and mined[index] == true
		local prompt = rock:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = mined ~= nil and type(index) == "number" and not done
		end
		local fade = if done then MINED_FADE else 0
		if rock:IsA("BasePart") then
			rock.LocalTransparencyModifier = fade
		end
		local ember = rock:FindFirstChild("Ember")
		if ember and ember:IsA("BasePart") then
			ember.LocalTransparencyModifier = if done then 1 else 0 -- neon still glows when half-faded
			local light = ember:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = not done
			end
		end
	end
end

-- Since 2026-11-21 the jail panel sits in the top bar, in the HUD's Wraps box spot (no wrapping in
-- jail), so nothing covers the middle of the screen while you mine.
local function setWrapsShown(shown: boolean)
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("HudGui")
	local wraps = hud and hud:FindFirstChild("Wraps")
	if wraps and wraps:IsA("GuiObject") then
		wraps.Visible = shown
	end
end

local function slamStamp()
	stamp.Visible = true
	stampScale.Scale = STAMP_START_SCALE
	stampText.TextTransparency = 0
	stampStroke.Transparency = 0
	TweenService:Create(stampScale, STAMP_SLAM, { Scale = 1 }):Play()
end

local function hideStamp()
	if not stamp.Visible then
		return
	end
	TweenService:Create(stampText, STAMP_FADE, { TextTransparency = 1 }):Play()
	local fade = TweenService:Create(stampStroke, STAMP_FADE, { Transparency = 1 })
	fade.Completed:Once(function()
		stamp.Visible = false
	end)
	fade:Play()
end

local function refreshTimer()
	local left = math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
	timerLabel.Text = `Free in {left}s`
end

local function startTimer()
	if timerThread then
		return
	end
	timerThread = task.spawn(function()
		while minedRocks ~= nil do
			refreshTimer()
			task.wait(TIMER_REFRESH_SECONDS)
		end
		timerThread = nil
	end)
end

local function onUpdate(value: any)
	if type(value) ~= "table" then
		return
	end
	local state = value.state
	if state == "Caught" then
		minedRocks = nil
		panel.Visible = false
		slamStamp()
	elseif state == "Jailed" then
		local mined: { [number]: boolean } = {}
		if type(value.mined) == "table" then
			for _, index in value.mined do
				if type(index) == "number" then
					mined[index] = true
				end
			end
		end
		minedRocks = mined
		endsAt = if type(value.endsAt) == "number" then value.endsAt else 0
		local coal = if type(value.coal) == "number" then value.coal else 0
		local needed = if type(value.coalNeeded) == "number" then value.coalNeeded else 0
		coalLabel.Text = `Coal {coal} / {needed}`
		local left = math.max(0, needed - coal)
		local h = hint
		if h then
			-- Short: it is the panel's small third line (the Mine prompt explains the rest).
			h.Text = if left == 1 then "Mine 1 more glowing rock" else `Mine {left} glowing rocks`
		end
		hideStamp()
		panel.Visible = true
		setWrapsShown(false)
		startTimer()
	elseif state == "Free" then
		minedRocks = nil
		panel.Visible = false
		setWrapsShown(true)
		hideStamp()
	end
	setRockPrompts()
end

function JailController:Init() end

function JailController:Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("JailGui", GUI_WAIT_SECONDS)
	if not gui then
		-- Slow devices can take longer: say so, then keep waiting rather than give up for good.
		warn("[JailController] still waiting for PlayerGui/JailGui (StarterGui/JailGui in the place file)")
		gui = playerGui:WaitForChild("JailGui")
	end
	stamp = gui:WaitForChild("Stamp") :: Frame
	stampScale = stamp:WaitForChild("Scale") :: UIScale
	stampText = stamp:WaitForChild("Text") :: TextLabel
	stampStroke = stamp:FindFirstChildOfClass("UIStroke") :: UIStroke
	panel = gui:WaitForChild("Panel") :: Frame
	timerLabel = panel:WaitForChild("Timer") :: TextLabel
	coalLabel = panel:WaitForChild("Coal") :: TextLabel
	local hintLabel = gui:FindFirstChild("Hint", true) -- inside Panel since 2026-11-21
	hint = if hintLabel and hintLabel:IsA("TextLabel") then hintLabel else nil
	stamp.Visible = false
	panel.Visible = false

	-- Rock prompts are made by the server; keep them hidden until we're jailed.
	setRockPrompts()
	CollectionService:GetInstanceAddedSignal("CoalRock"):Connect(function(rock)
		rock.ChildAdded:Connect(setRockPrompts)
		setRockPrompts()
	end)
	for _, rock in CollectionService:GetTagged("CoalRock") do
		rock.ChildAdded:Connect(setRockPrompts)
	end

	Remotes.get("JailUpdate").OnClientEvent:Connect(onUpdate)
end

return JailController


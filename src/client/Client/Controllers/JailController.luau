--!strict
-- Naughty Jail on screen (step 3.3). Fills and animates PlayerGui.JailGui (built in the place file):
--   Caught -> the "NAUGHTY!" stamp slams in.
--   Jailed -> the panel shows "Free in Ns" and "Coal mined: c / n"; coal rock prompts show only
--             for rocks not mined yet this visit.
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

local JailController = {}

local player = Players.LocalPlayer
local stamp: Frame
local stampScale: UIScale
local stampText: TextLabel
local stampStroke: UIStroke
local panel: Frame
local timerLabel: TextLabel
local coalLabel: TextLabel

-- nil when free; otherwise the CoalRock indexes already mined this visit.
local minedRocks: { [number]: boolean }? = nil
local endsAt = 0
local timerThread: thread? = nil

local function setRockPrompts()
	for _, rock in CollectionService:GetTagged("CoalRock") do
		local prompt = rock:FindFirstChildOfClass("ProximityPrompt")
		local index = rock:GetAttribute("Index")
		if prompt then
			local mined = minedRocks
			prompt.Enabled = mined ~= nil and type(index) == "number" and not mined[index]
		end
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
		coalLabel.Text = `Coal mined: {coal} / {needed}`
		hideStamp()
		panel.Visible = true
		startTimer()
	elseif state == "Free" then
		minedRocks = nil
		panel.Visible = false
		hideStamp()
	end
	setRockPrompts()
end

function JailController:Init() end

function JailController:Start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("JailGui", GUI_WAIT_SECONDS)
	if not gui then
		warn("[JailController] PlayerGui/JailGui is missing (StarterGui/JailGui in the place file)")
		return
	end
	stamp = gui:WaitForChild("Stamp") :: Frame
	stampScale = stamp:WaitForChild("Scale") :: UIScale
	stampText = stamp:WaitForChild("Text") :: TextLabel
	stampStroke = stamp:FindFirstChildOfClass("UIStroke") :: UIStroke
	panel = gui:WaitForChild("Panel") :: Frame
	timerLabel = panel:WaitForChild("Timer") :: TextLabel
	coalLabel = panel:WaitForChild("Coal") :: TextLabel
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

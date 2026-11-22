--!strict
-- The Blizzard banner (step 6.2): while a Blizzard blows, every player sees who bought it and how
-- long it lasts. MonetizationService sets the Workspace attributes BlizzardEndsAt (server time) and
-- BlizzardBy (the buyer's display name); SnowController makes the snow heavier. Display only.
-- HudGui.Blizzard (a Frame with a Text label) lives in the place file.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GUI_WAIT_SECONDS = 15
local REFRESH_SECONDS = 0.25
local POP_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local MAX_NAME_LENGTH = 20

local BlizzardController = {}

local player = Players.LocalPlayer

function BlizzardController:Init() end

function BlizzardController:Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("HudGui", GUI_WAIT_SECONDS)
	if not hud then
		warn("[BlizzardController] still waiting for PlayerGui/HudGui (StarterGui in the place file)")
		hud = playerGui:WaitForChild("HudGui")
	end
	local banner = hud:WaitForChild("Blizzard", GUI_WAIT_SECONDS)
	local text = banner and banner:FindFirstChild("Text")
	if not (banner and banner:IsA("Frame") and text and text:IsA("TextLabel")) then
		warn("[BlizzardController] HudGui needs a Blizzard frame with a Text label")
		return
	end
	banner.Visible = false
	local scale = banner:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = banner

	local running = false
	local function run()
		if running then
			return
		end
		running = true
		scale.Scale = 0.6
		banner.Visible = true
		TweenService:Create(scale, POP_TWEEN, { Scale = 1 }):Play()
		while true do
			local endsAt = Workspace:GetAttribute("BlizzardEndsAt")
			local left = if type(endsAt) == "number" then math.ceil(endsAt - Workspace:GetServerTimeNow()) else 0
			if left <= 0 then
				break
			end
			local by = Workspace:GetAttribute("BlizzardBy")
			local name = if type(by) == "string" then by:sub(1, MAX_NAME_LENGTH) else "someone"
			text.Text = `BLIZZARD! Elves can barely see. Thanks, {name}!  {left}s`
			task.wait(REFRESH_SECONDS)
		end
		banner.Visible = false
		running = false
	end

	Workspace:GetAttributeChangedSignal("BlizzardEndsAt"):Connect(function()
		task.spawn(run)
	end)
	if Workspace:GetAttribute("BlizzardEndsAt") ~= nil then
		task.spawn(run) -- joined while one was already blowing
	end
end

return BlizzardController

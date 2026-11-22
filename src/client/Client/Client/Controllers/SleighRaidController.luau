--!strict
-- The Sleigh Raid on the HUD (step 6.4). Display only: SleighRaidService sets the Workspace
-- attributes SleighRaidState ("Waiting" | "Warning" | "Active"), SleighRaidLandsAt and
-- SleighRaidEndsAt (server time).
-- HudGui.RaidTimer (a Frame with a Text label, place file) is hidden while Waiting. Only during
-- the warning and the raid itself (about 70 s every 12 minutes) does it show, as one more tile in
-- the top-left button column, under SHOP, the same size as that button:
--   Warning -> "SLEIGH 7s" (orange).  Active -> "RAID 0:42" (red).
-- (2026-11-22: the owner found a centre banner, and then a centre pill, covered the screen on phones.)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GUI_WAIT_SECONDS = 15
local REFRESH_SECONDS = 0.25
local COLUMN_GAP = 6 -- pixels between the tile and the SHOP button above it (same as INDEX to SHOP)
local POP_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local WARNING_COLOR = Color3.fromRGB(232, 118, 18) -- orange: white text stays readable on it
local ACTIVE_COLOR = Color3.fromRGB(214, 48, 48)
local LIGHT_TEXT = Color3.fromRGB(255, 255, 255)

local SleighRaidController = {}

local player = Players.LocalPlayer

local function clock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function attributeNumber(name: string): number
	local value = Workspace:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

-- Puts the tile directly under SHOP, matching its size, so it reads as part of that column.
local function placeUnderShop(hud: Instance, frame: Frame)
	local shop = hud:FindFirstChild("ShopButton")
	if not shop or not shop:IsA("GuiObject") then
		return
	end
	frame.AnchorPoint = shop.AnchorPoint
	frame.Size = shop.Size
	frame.Position = shop.Position + UDim2.fromOffset(0, shop.Size.Y.Offset + COLUMN_GAP)
end

function SleighRaidController:Init() end

function SleighRaidController:Start()
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("HudGui", GUI_WAIT_SECONDS)
	if not hud then
		warn("[SleighRaidController] still waiting for PlayerGui/HudGui (StarterGui in the place file)")
		hud = playerGui:WaitForChild("HudGui")
	end
	local frame = hud:WaitForChild("RaidTimer", GUI_WAIT_SECONDS)
	local text = frame and frame:FindFirstChild("Text")
	if not (frame and frame:IsA("Frame") and text and text:IsA("TextLabel")) then
		warn("[SleighRaidController] HudGui needs a RaidTimer frame with a Text label")
		return
	end
	placeUnderShop(hud, frame)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.Size = UDim2.new(1, -8, 1, -8)
	text.TextScaled = true
	text.TextWrapped = true
	text.TextColor3 = LIGHT_TEXT
	local scale = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = frame

	local shownState: string? = nil
	local function refresh()
		local state = Workspace:GetAttribute("SleighRaidState")
		local now = Workspace:GetServerTimeNow()
		local showing = state == "Warning" or state == "Active"
		frame.Visible = showing
		if not showing then
			shownState = nil
			return
		end
		if state ~= shownState then
			shownState = state
			frame.BackgroundColor3 = if state == "Warning" then WARNING_COLOR else ACTIVE_COLOR
			scale.Scale = 1.15 -- a quick pop so the change is noticed, then back to normal
			TweenService:Create(scale, POP_TWEEN, { Scale = 1 }):Play()
		end
		if state == "Warning" then
			text.Text = `SLEIGH\n{math.max(0, math.ceil(attributeNumber("SleighRaidLandsAt") - now))}s`
		else
			text.Text = `RAID\n{clock(attributeNumber("SleighRaidEndsAt") - now)}`
		end
	end

	refresh()
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			refresh()
		end
	end)
end

return SleighRaidController

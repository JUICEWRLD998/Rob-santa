--!strict
-- The on-screen HUD (docs/01 section 13). Step 2.3: coins (top centre), income per second, and
-- short server messages (Notify). Carried present, Wraps, buttons and the raid timer come later.
-- The HUD itself (StarterGui/HudGui) lives in the place file; this only fills it.
-- Reads the Coins / IncomePerSecond attributes the server sets on the Player. Display only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local GUI_WAIT_SECONDS = 15
local TOAST_SECONDS = 2.5
local BUMP_SCALE = 1.12 -- the coin number swells briefly when it goes up
local BUMP_SECONDS = 0.15
local MAX_MESSAGE_LENGTH = 120

local HudController = {}

local player = Players.LocalPlayer
local toastToken = 0

-- 1234567 -> "1,234,567"
local function withCommas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

local function findLabel(gui: Instance, path: { string }): TextLabel?
	local node: Instance? = gui
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return if node and node:IsA("TextLabel") then node else nil
end

function HudController:Init() end

function HudController:Start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("HudGui", GUI_WAIT_SECONDS)
	if not gui then
		warn("[HudController] PlayerGui/HudGui is missing (StarterGui/HudGui in the place file)")
		return
	end
	local amount = findLabel(gui, { "Coins", "Amount" })
	local income = findLabel(gui, { "Coins", "Income" })
	local toast = findLabel(gui, { "Toast" })
	if not amount or not income or not toast then
		warn("[HudController] HudGui is missing Coins/Amount, Coins/Income or Toast")
		return
	end
	local scale = Instance.new("UIScale")
	scale.Parent = amount

	local shown = 0
	local function showCoins()
		local value = player:GetAttribute("Coins")
		local coins = if type(value) == "number" then value else 0
		amount.Text = withCommas(coins)
		if coins > shown then
			scale.Scale = BUMP_SCALE
			TweenService:Create(scale, TweenInfo.new(BUMP_SECONDS), { Scale = 1 }):Play()
		end
		shown = coins
	end
	local function showIncome()
		local value = player:GetAttribute("IncomePerSecond")
		local perSecond = if type(value) == "number" then value else 0
		income.Text = `+{withCommas(perSecond)} / s`
	end
	player:GetAttributeChangedSignal("Coins"):Connect(showCoins)
	player:GetAttributeChangedSignal("IncomePerSecond"):Connect(showIncome)
	showCoins()
	showIncome()

	Remotes.get("Notify").OnClientEvent:Connect(function(text: any)
		if type(text) ~= "string" then
			return
		end
		toastToken += 1
		local token = toastToken
		toast.Text = text:sub(1, MAX_MESSAGE_LENGTH)
		toast.Visible = true
		task.delay(TOAST_SECONDS, function()
			if toastToken == token then
				toast.Visible = false
			end
		end)
	end)
end

return HudController

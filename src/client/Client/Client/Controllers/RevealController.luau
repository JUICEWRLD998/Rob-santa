--!strict
-- Shows the unwrap reveal popup when the server sends UnwrapReveal (step 2.2).
-- The popup itself (StarterGui/RevealGui) lives in the place file. This only fills and animates it.
-- Higher rarity pops bigger. Reveals that arrive together are shown one after another.
-- PLACEHOLDER: Phase 5 replaces this with the full-screen burst described in docs/01 section 13.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))
local Types = require(Shared:WaitForChild("Types"))

local GUI_WAIT_SECONDS = 15

local RevealController = {}

local queue: { Types.UnwrapResult } = {}
local showing = false

type Card = {
	frame: Frame,
	stroke: UIStroke,
	scale: UIScale,
	toyName: TextLabel,
	rarity: TextLabel,
	mutation: TextLabel,
}
local card: Card? = nil

local function findCard(): Card?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("RevealGui", GUI_WAIT_SECONDS)
	local frame = gui and gui:FindFirstChild("Card")
	if not frame or not frame:IsA("Frame") then
		warn("[RevealController] PlayerGui/RevealGui/Card is missing (StarterGui/RevealGui in the place file)")
		return nil
	end
	local stroke = frame:FindFirstChild("Stroke")
	local scale = frame:FindFirstChild("Scale")
	local toyName = frame:FindFirstChild("ToyName")
	local rarity = frame:FindFirstChild("Rarity")
	local mutation = frame:FindFirstChild("Mutation")
	if
		not (stroke and stroke:IsA("UIStroke"))
		or not (scale and scale:IsA("UIScale"))
		or not (toyName and toyName:IsA("TextLabel"))
		or not (rarity and rarity:IsA("TextLabel"))
		or not (mutation and mutation:IsA("TextLabel"))
	then
		warn("[RevealController] RevealGui/Card is missing a child (Stroke, Scale, ToyName, Rarity, Mutation)")
		return nil
	end
	return { frame = frame, stroke = stroke, scale = scale, toyName = toyName, rarity = rarity, mutation = mutation }
end

local function tierOf(rarity: Types.Rarity): number
	return table.find(Config.RarityOrder, rarity) or 1
end

local function play(ui: Card, result: Types.UnwrapResult)
	local toy = Toys.get(result.toyId)
	local color = Config.Rarities[result.rarity].color
	ui.toyName.Text = if toy then toy.name else result.toyId
	ui.rarity.Text = result.rarity
	ui.rarity.TextColor3 = color
	ui.stroke.Color = color
	ui.mutation.Text = if result.mutation then `{result.mutation}!` else ""
	for _, entry in Config.Mutations do
		if entry.name == result.mutation then
			ui.mutation.TextColor3 = entry.color -- step 4.3: each mutation has its own stamp colour
		end
	end

	local target = 1 + (tierOf(result.rarity) - 1) * Config.Reveal.ScalePerTier
	ui.scale.Scale = 0.4
	ui.frame.Visible = true
	local pop = TweenService:Create(
		ui.scale,
		TweenInfo.new(Config.Reveal.PopSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = target }
	)
	pop:Play()
	task.wait(Config.Reveal.PopSeconds + Config.Reveal.HoldSeconds)
	local hide = TweenService:Create(
		ui.scale,
		TweenInfo.new(Config.Reveal.HideSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0 }
	)
	hide:Play()
	hide.Completed:Wait()
	ui.frame.Visible = false
end

local function drain()
	if showing then
		return
	end
	showing = true
	while #queue > 0 do
		local result = table.remove(queue, 1)
		if not card then
			card = findCard()
		end
		if result and card then
			play(card, result)
		end
	end
	showing = false
end

-- The server is trusted here, but a bad payload should not break the popup.
local function isResult(value: any): boolean
	return type(value) == "table"
		and type(value.toyId) == "string"
		and type(value.rarity) == "string"
		and table.find(Config.RarityOrder, value.rarity) ~= nil
		and (value.mutation == nil or type(value.mutation) == "string")
end

function RevealController:Init() end

function RevealController:Start()
	Remotes.get("UnwrapReveal").OnClientEvent:Connect(function(payload: any)
		if not isResult(payload) then
			warn("[RevealController] ignored a malformed UnwrapReveal")
			return
		end
		table.insert(queue, payload :: Types.UnwrapResult)
		task.spawn(drain)
	end)
end

return RevealController

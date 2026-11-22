--!strict
-- The unwrap reveal (step 2.2, made a celebration in 5.5; docs/01 section 13): the rarity colour
-- floods the screen, the toy pops up and spins, confetti bursts, and a mutation is stamped on.
-- Everything grows with rarity (Config.Reveal): more colour, more confetti, a longer hold; light
-- rays from Rare up, a white flash from Legendary up. Reveals that arrive together play in turn.
-- The stage (StarterGui/RevealGui: Burst, Rays, Toy, Card, Confetti, Flash) lives in the place
-- file; this only fills and animates it. Toy meshes come from ReplicatedStorage/ToyMeshes
-- (published by the server at boot); without one the card still plays.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Toys = require(Shared:WaitForChild("Toys"))
local Types = require(Shared:WaitForChild("Types"))

local GUI_WAIT_SECONDS = 15
local GOLD = Color3.fromRGB(255, 206, 64)
local WHITE = Color3.new(1, 1, 1)

local RevealController = {}

local queue: { Types.UnwrapResult } = {}
local showing = false
local random = Random.new()

type Stage = {
	burst: Frame,
	rays: Frame,
	toy: ViewportFrame,
	toyScale: UIScale,
	confetti: Frame,
	piece: Frame,
	flash: Frame,
	card: Frame,
	stroke: UIStroke,
	scale: UIScale,
	toyName: TextLabel,
	rarity: TextLabel,
	mutation: TextLabel,
	stamp: UIScale,
}
local stage: Stage? = nil

local function child(parent: Instance?, name: string, className: string): any
	local found = parent and parent:FindFirstChild(name)
	if found and found:IsA(className) then
		return found
	end
	return nil
end

local function findStage(): Stage?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("RevealGui", GUI_WAIT_SECONDS)
	if not gui then
		warn("[RevealController] still waiting for PlayerGui/RevealGui (StarterGui/RevealGui in the place file)")
		gui = playerGui:WaitForChild("RevealGui")
	end
	local card = child(gui, "Card", "Frame")
	local toy = child(gui, "Toy", "ViewportFrame")
	local confetti = child(gui, "Confetti", "Frame")
	local mutation = child(card, "Mutation", "TextLabel")
	local built: { [string]: any } = {
		burst = child(gui, "Burst", "Frame"),
		rays = child(gui, "Rays", "Frame"),
		toy = toy,
		toyScale = child(toy, "Scale", "UIScale"),
		confetti = confetti,
		piece = child(confetti, "PieceTemplate", "Frame"),
		flash = child(gui, "Flash", "Frame"),
		card = card,
		stroke = child(card, "Stroke", "UIStroke"),
		scale = child(card, "Scale", "UIScale"),
		toyName = child(card, "ToyName", "TextLabel"),
		rarity = child(card, "Rarity", "TextLabel"),
		mutation = mutation,
		stamp = child(mutation, "StampScale", "UIScale"),
	}
	for _, key in { "burst", "rays", "toy", "toyScale", "confetti", "piece", "flash", "card", "stroke", "scale", "toyName", "rarity", "mutation", "stamp" } do
		if built[key] == nil then
			warn(`[RevealController] RevealGui is missing {key}`)
			return nil
		end
	end
	return built :: any
end

local function tierOf(rarity: Types.Rarity): number
	return table.find(Config.RarityOrder, rarity) or 1
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function mutationColor(name: string?): Color3?
	for _, entry in Config.Mutations do
		if entry.name == name then
			return entry.color
		end
	end
	return nil
end

-- Puts the toy's mesh in the viewport with a camera that fits it. Returns the model to spin.
local function setupToy(ui: Stage, toyId: string, mutation: string?): Model?
	for _, old in ui.toy:GetChildren() do
		if not old:IsA("UIScale") then
			old:Destroy()
		end
	end
	local meshes = ReplicatedStorage:FindFirstChild("ToyMeshes")
	local source = meshes and meshes:FindFirstChild(toyId)
	local box = source and source:GetAttribute("BoxSize")
	if not source or not source:IsA("Model") or typeof(box) ~= "Vector3" then
		return nil
	end
	local model = source:Clone()
	-- A mutated toy shows its mutation colour, like the shelf toy drops its texture for its look.
	local tint = mutationColor(mutation)
	if tint then
		for _, part in model:GetDescendants() do
			if part:IsA("MeshPart") then
				part.TextureID = ""
				part.Color = tint
			end
		end
	end
	model.Parent = ui.toy
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local size = math.max(box.X, box.Y, box.Z)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, size * 0.25, size * 2.4), Vector3.zero)
	camera.Parent = ui.toy
	ui.toy.CurrentCamera = camera
	return model
end

local function burstConfetti(ui: Stage, tier: number, color: Color3)
	local count = Config.Reveal.ConfettiPerTier * tier
	local palette = { color, WHITE, GOLD, color:Lerp(WHITE, 0.4) }
	for _ = 1, count do
		local piece = ui.piece:Clone()
		piece.BackgroundColor3 = palette[random:NextInteger(1, #palette)]
		piece.Position = UDim2.fromScale(0.5, 0.31)
		piece.Rotation = random:NextNumber(0, 360)
		piece.Visible = true
		piece.Parent = ui.confetti
		local angle = random:NextNumber(0, 2 * math.pi)
		local reach = random:NextNumber(0.18, 0.55)
		local seconds = random:NextNumber(1.1, 1.8)
		-- Out from the toy, then down past where they started, as if falling.
		local goal = UDim2.fromScale(0.5 + math.cos(angle) * reach, 0.31 + math.sin(angle) * reach * 0.7 + 0.35)
		tween(piece, seconds, { Position = goal, Rotation = piece.Rotation + random:NextNumber(-540, 540), BackgroundTransparency = 1 })
		task.delay(seconds, function()
			piece:Destroy()
		end)
	end
end

local function play(ui: Stage, result: Types.UnwrapResult)
	local settings = Config.Reveal
	local tier = tierOf(result.rarity)
	local toy = Toys.get(result.toyId)
	local color = Config.Rarities[result.rarity].color

	ui.toyName.Text = if toy then toy.name else result.toyId
	ui.rarity.Text = result.rarity
	ui.rarity.TextColor3 = color
	ui.stroke.Color = color
	ui.mutation.Text = ""
	ui.mutation.TextColor3 = mutationColor(result.mutation) or WHITE

	-- Colour floods in.
	ui.burst.BackgroundColor3 = color
	ui.burst.BackgroundTransparency = 1
	ui.burst.Visible = true
	tween(ui.burst, 0.25, { BackgroundTransparency = settings.BurstTransparency[tier] or 0.6 })
	if tier >= settings.FlashFromTier then
		ui.flash.BackgroundTransparency = 0.05
		ui.flash.Visible = true
		tween(ui.flash, 0.6, { BackgroundTransparency = 1 })
	end

	-- Rays and the toy turn every frame until the reveal ends.
	local showRays = tier >= settings.RaysFromTier
	ui.rays.Visible = showRays
	for _, ray in ui.rays:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = color:Lerp(WHITE, 0.55)
		end
	end
	local model = setupToy(ui, result.toyId, result.mutation)
	ui.toy.Visible = model ~= nil
	local spin = 0
	local spinner = RunService.RenderStepped:Connect(function(dt)
		spin += dt
		if model then
			model:PivotTo(CFrame.Angles(0, spin * 2 * math.pi / settings.SpinSeconds, 0))
		end
		if showRays then
			for _, ray in ui.rays:GetChildren() do
				if ray:IsA("Frame") then
					ray.Rotation += settings.RaysDegreesPerSecond * dt
				end
			end
		end
	end)

	-- Pop: toy and card spring in, confetti bursts.
	-- The toy grows with rarity; the card only a little, or it covers the toy on small phones.
	local target = 1 + (tier - 1) * settings.ScalePerTier
	-- On short screens (phones) the card shrinks so it stays clear of the thumbstick and jump button.
	local camera = workspace.CurrentCamera
	local fit = if camera then math.clamp(camera.ViewportSize.Y / settings.CardFitHeight, settings.CardMinFit, 1) else 1
	local cardTarget = (1 + (tier - 1) * settings.CardScalePerTier) * fit
	ui.toyScale.Scale = 0
	ui.scale.Scale = 0.4
	ui.card.Visible = true
	tween(ui.toyScale, settings.PopSeconds + 0.1, { Scale = target }, Enum.EasingStyle.Back)
	tween(ui.scale, settings.PopSeconds, { Scale = cardTarget }, Enum.EasingStyle.Back)
	burstConfetti(ui, tier, color)

	-- The mutation stamp slams in a moment later.
	local mutation = result.mutation
	if mutation then
		task.delay(settings.StampDelay, function()
			ui.mutation.Text = `{mutation}!`
			ui.mutation.Rotation = -8
			ui.stamp.Scale = 2.6
			tween(ui.stamp, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end

	task.wait(settings.PopSeconds + settings.HoldSeconds + (tier - 1) * settings.HoldPerTier)

	tween(ui.burst, settings.HideSeconds, { BackgroundTransparency = 1 })
	tween(ui.toyScale, settings.HideSeconds, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(ui.scale, settings.HideSeconds, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
	spinner:Disconnect()
	ui.card.Visible = false
	ui.toy.Visible = false
	ui.rays.Visible = false
	ui.burst.Visible = false
	ui.flash.Visible = false
end

local function drain()
	if showing then
		return
	end
	showing = true
	while #queue > 0 do
		local result = table.remove(queue, 1)
		if not stage then
			stage = findStage()
		end
		local ui = stage
		if result and ui then
			play(ui, result)
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

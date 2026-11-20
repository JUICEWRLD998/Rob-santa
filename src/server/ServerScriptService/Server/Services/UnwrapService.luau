--!strict
-- Delivery and unwrapping (docs/01-GAME-DESIGN.md section 3, step 2.2).
-- A carrier standing on their OWN hideout's DropMat hands over what they carry. Each present goes
-- on their UnwrapTable and unwraps for Config.Presents.UnwrapSeconds. The server then picks the toy
-- (equal chance among toys of the present's rarity) and rolls the mutation. A placeholder toy
-- appears on the table, and the player gets an UnwrapReveal. Another player's DropMat does nothing.
-- TEMPORARY: unwrapped toys live in memory here. Step 2.3 moves them to shelves and Phase 4 saves them.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Toys = require(ReplicatedStorage.Shared.Toys)
local Types = require(ReplicatedStorage.Shared.Types)
local PlotService = require(script.Parent.PlotService)
local PresentService = require(script.Parent.PresentService)

local INDEX_ATTRIBUTE = "Hideout"
local TOY_GAP = 0.4 -- studs between displayed toys on the table

-- Placeholder looks until Phase 5 art (docs/01 section 6, "Look" column).
type MutationLook = { color: Color3?, material: Enum.Material, light: boolean }
local MUTATION_LOOKS: { [string]: MutationLook } = {
	Frosted = { color = Color3.fromRGB(170, 225, 255), material = Enum.Material.Ice, light = false },
	Gingerbread = { color = Color3.fromRGB(150, 90, 45), material = Enum.Material.Sand, light = false },
	Glowing = { color = nil, material = Enum.Material.Neon, light = true },
	Golden = { color = Color3.fromRGB(255, 200, 60), material = Enum.Material.Foil, light = false },
}

type Queue = {
	pending: { PresentService.Delivered },
	running: boolean,
}

local UnwrapService = {}

local rng = Random.new()
local unwrapReveal: RemoteEvent
local toyTemplate: Model? = nil
local matOf: { [number]: BasePart } = {}
local tableOf: { [number]: BasePart } = {}
local toysOf: { [Player]: { Types.OwnedToy } } = {}
local displayOf: { [Player]: { Model } } = {}
local queueOf: { [Player]: Queue } = {}

local function collect(tag: string, into: { [number]: BasePart })
	for _, part in CollectionService:GetTagged(tag) do
		local index = part:GetAttribute(INDEX_ATTRIBUTE)
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) and type(index) == "number" then
			into[index] = part
		end
	end
end

local function rollMutation(): Types.Mutation?
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, mutation in Config.Mutations do
		cumulative += mutation.chance
		if roll < cumulative then
			return mutation.name :: Types.Mutation
		end
	end
	return nil
end

local function pickToy(rarity: Types.Rarity): Types.ToyDef?
	local choices = Toys.ofRarity(rarity)
	if #choices == 0 then
		return nil
	end
	return choices[rng:NextInteger(1, #choices)]
end

-- True if the root is above the mat's footprint and no higher than DeliveryMatHeight.
local function isOnMat(root: BasePart, mat: BasePart): boolean
	local relative = mat.CFrame:PointToObjectSpace(root.Position)
	return math.abs(relative.X) <= mat.Size.X / 2
		and math.abs(relative.Z) <= mat.Size.Z / 2
		and relative.Y >= -1
		and relative.Y <= Config.Presents.DeliveryMatHeight
end

-- Lines the newest toys up along the table top; the oldest leave the table first.
local function layoutToys(displays: { Model }, tablePart: BasePart)
	while #displays > Config.Presents.ToysShownOnTable do
		local oldest = table.remove(displays, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	local count = #displays
	for slot, model in displays do
		local body = model.PrimaryPart
		if body then
			local spacing = body.Size.X + TOY_GAP
			local x = (slot - (count + 1) / 2) * spacing
			local y = tablePart.Size.Y / 2 + body.Size.Y / 2
			model:PivotTo(tablePart.CFrame * CFrame.new(x, y, 0))
		end
	end
end

local function showToy(player: Player, tablePart: BasePart, toy: Types.ToyDef, mutation: Types.Mutation?)
	local displays = displayOf[player]
	if not toyTemplate or not displays then
		return
	end
	local model = toyTemplate:Clone()
	local body = model.PrimaryPart
	if not body then
		model:Destroy()
		return
	end
	local rarityColor = Config.Rarities[toy.rarity].color
	body.Color = rarityColor
	if mutation then
		local look = MUTATION_LOOKS[mutation]
		body.Material = look.material
		if look.color then
			body.Color = look.color
		end
		if look.light then
			local light = Instance.new("PointLight")
			light.Color = rarityColor
			light.Range = 8
			light.Parent = body
		end
	end
	local nameLabel = body:FindFirstChild("ToyName", true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = if mutation then `{mutation} {toy.name}` else toy.name
	end
	local rarityLabel = body:FindFirstChild("Rarity", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Text = toy.rarity
		rarityLabel.TextColor3 = rarityColor
	end
	model.Parent = tablePart
	table.insert(displays, model)
	layoutToys(displays, tablePart)
end

-- The present sits on the table and spins for UnwrapSeconds, then the toy is rolled and shown.
local function unwrapOne(player: Player, present: PresentService.Delivered)
	local index = PlotService:GetHideoutIndex(player)
	local tablePart = if index then tableOf[index] else nil
	local box = present.box
	if tablePart then
		local top = tablePart.Size.Y / 2 + box.Size.Y / 2
		box.CFrame = tablePart.CFrame * CFrame.new(0, top, 0)
		local spin = TweenService:Create(
			box,
			TweenInfo.new(Config.Presents.UnwrapSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = box.CFrame * CFrame.new(0, 1, 0) * CFrame.Angles(0, math.rad(720), 0) }
		)
		spin:Play()
	end
	task.wait(Config.Presents.UnwrapSeconds)
	present.model:Destroy()
	if player.Parent == nil then
		return
	end

	local toy = pickToy(present.rarity)
	if not toy then
		warn(`[UnwrapService] no toys of rarity {present.rarity} in Toys.luau`)
		return
	end
	local mutation: Types.Mutation? = rollMutation()
	local owned: Types.OwnedToy = { uid = HttpService:GenerateGUID(false), toyId = toy.id, mutation = mutation }
	local list = toysOf[player]
	if list then
		table.insert(list, owned)
	end
	if tablePart then
		showToy(player, tablePart, toy, mutation)
	end
	local result: Types.UnwrapResult = { toyId = toy.id, rarity = toy.rarity, mutation = mutation }
	unwrapReveal:FireClient(player, result)
end

-- Unwraps one present at a time, in delivery order.
local function runQueue(player: Player)
	local queue = queueOf[player]
	if not queue or queue.running then
		return
	end
	queue.running = true
	while #queue.pending > 0 and player.Parent ~= nil do
		local present = table.remove(queue.pending, 1)
		if not present then
			break
		end
		-- The inner function returns `any` so pcall types as (ok, err); see CLAUDE.md "xpcall" note.
		local ok, err = pcall(function(): any
			unwrapOne(player, present)
			return nil
		end)
		if not ok then
			warn(`[UnwrapService] unwrap failed for {player.Name}: {err}`)
		end
	end
	queue.running = false
end

local function checkDelivery(player: Player)
	if PresentService:GetCarriedCount(player) == 0 then
		return
	end
	local index = PlotService:GetHideoutIndex(player)
	local mat = if index then matOf[index] else nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not mat or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	local queue = queueOf[player]
	if not queue or not isOnMat(root, mat) then
		return
	end
	for _, present in PresentService:TakeCarried(player) do
		table.insert(queue.pending, present)
	end
	task.spawn(runQueue, player)
end

local function onPlayerAdded(player: Player)
	if not toysOf[player] then
		toysOf[player] = {}
	end
	if not displayOf[player] then
		displayOf[player] = {}
	end
	if not queueOf[player] then
		queueOf[player] = { pending = {}, running = false }
	end
end

local function onPlayerRemoving(player: Player)
	local queue = queueOf[player]
	if queue then
		for _, present in queue.pending do
			present.model:Destroy()
		end
	end
	local displays = displayOf[player]
	if displays then
		for _, model in displays do
			model:Destroy()
		end
	end
	toysOf[player] = nil
	displayOf[player] = nil
	queueOf[player] = nil
end

function UnwrapService:Init()
	unwrapReveal = Remotes.get("UnwrapReveal")
	collect("DropMat", matOf)
	collect("UnwrapTable", tableOf)
	local templates = ServerStorage:FindFirstChild("Templates")
	local found = templates and templates:FindFirstChild("Toy")
	if found and found:IsA("Model") and found.PrimaryPart then
		toyTemplate = found
	else
		warn("[UnwrapService] ServerStorage/Templates/Toy (a Model with a PrimaryPart) is missing")
	end
end

function UnwrapService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	-- A short poll is steadier than Touched for "standing on the mat", and only carriers are checked.
	task.spawn(function()
		while true do
			task.wait(Config.Presents.DeliveryCheckSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(function(): any
					checkDelivery(player)
					return nil
				end)
				if not ok then
					warn(`[UnwrapService] delivery check failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

-- Every toy the player has unwrapped this session (step 2.3 places them on shelves).
function UnwrapService:GetToys(player: Player): { Types.OwnedToy }
	return toysOf[player] or {}
end

return UnwrapService

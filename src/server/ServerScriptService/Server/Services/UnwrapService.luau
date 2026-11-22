--!strict
-- Delivery and unwrapping (docs/01-GAME-DESIGN.md section 3, step 2.2).
-- A carrier standing on their OWN hideout's DropMat hands over what they carry. Each present goes
-- on their UnwrapTable and unwraps for Config.Presents.UnwrapSeconds. The server then picks the toy
-- (equal chance among toys of the present's rarity) and rolls the mutation, hands the toy to
-- ShelfService (it waits on the table) and sends the player an UnwrapReveal.
-- Another player's DropMat does nothing.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Toys = require(ReplicatedStorage.Shared.Toys)
local Types = require(ReplicatedStorage.Shared.Types)
local IndexService = require(script.Parent.IndexService)
local PlotService = require(script.Parent.PlotService)
local PresentService = require(script.Parent.PresentService)
local ShelfService = require(script.Parent.ShelfService)

local INDEX_ATTRIBUTE = "Hideout"

type Queue = {
	pending: { PresentService.Delivered },
	running: boolean,
}

local UnwrapService = {}

local rng = Random.new()
local unwrapReveal: RemoteEvent
local matOf: { [number]: BasePart } = {}
local tableOf: { [number]: BasePart } = {}
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

-- The present sits on the table and spins for UnwrapSeconds, then the toy is rolled.
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
	-- Display only (step 5.6): the client plays a drumroll while this is set.
	player:SetAttribute("Unwrapping", true)
	task.wait(Config.Presents.UnwrapSeconds)
	if player.Parent then
		player:SetAttribute("Unwrapping", nil)
	end
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
	if not ShelfService:AddUnwrapped(player, owned) then
		warn(`[UnwrapService] could not put {toy.id} on {player.Name}'s table`)
	end
	local result: Types.UnwrapResult = { toyId = toy.id, rarity = toy.rarity, mutation = mutation }
	unwrapReveal:FireClient(player, result)
	IndexService:Record(player, toy.id, mutation) -- step 4.4: first find pays a bonus
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
	-- Step 2.4: a present that reached the mat faster than any legal player could run was
	-- teleported. Send it back to its zone. Measured to the mat (server truth), not the character.
	if PresentService:CarriedTooFast(player, mat.Position) then
		warn(`[UnwrapService] refused delivery from {player.Name} ({player.UserId}): too fast from the zone`)
		PresentService:ReturnCarried(player)
		return
	end
	for _, present in PresentService:TakeCarried(player) do
		table.insert(queue.pending, present)
	end
	task.spawn(runQueue, player)
end

local function onPlayerAdded(player: Player)
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
	queueOf[player] = nil
end

function UnwrapService:Init()
	unwrapReveal = Remotes.get("UnwrapReveal")
	collect("DropMat", matOf)
	collect("UnwrapTable", tableOf)
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

return UnwrapService

--!strict
-- Most Wanted (step 6.4, docs/01-GAME-DESIGN.md section 9). Every number is in Config.MostWanted.
--   * The richest thief in the server (saved coins) is Most Wanted. Re-checked every RefreshSeconds;
--     a tie keeps the current one.
--   * The wanted poster (MostWantedBoard-tagged part, its WantedGui SurfaceGui in the place file)
--     shows their head shot, name and coins.
--   * They get a red outline (a Highlight in their character) while at least MinPlayersForOutline
--     players are in the server. Hidden while they are a gift box (it would give the box away) or
--     in jail.
--   * SnowballService asks GetMostWanted() to pay the bounty. Workspace attribute MostWantedUserId
--     tells clients who it is.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local OUTLINE_NAME = "MostWantedOutline"

local MostWantedService = {}

local current: Player? = nil
local photo: ImageLabel? = nil
local nameLabel: TextLabel? = nil
local coinsLabel: TextLabel? = nil
local emptyLabel: TextLabel? = nil

local function richest(): Player?
	local best: Player? = current
	local bestCoins = -1
	if best and best.Parent and DataService:GetData(best) then
		bestCoins = EconomyService:GetCoins(best)
	else
		best = nil
	end
	for _, player in Players:GetPlayers() do
		if DataService:GetData(player) then
			local coins = EconomyService:GetCoins(player)
			if coins > bestCoins then
				best, bestCoins = player, coins
			end
		end
	end
	return best
end

local function updateOutline(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local existing = character:FindFirstChild(OUTLINE_NAME)
	local wanted = player == current
		and #Players:GetPlayers() >= Config.MostWanted.MinPlayersForOutline
		and player:GetAttribute("Disguised") ~= true
		and player:GetAttribute("Jailed") ~= true
	if wanted and not existing then
		local outline = Instance.new("Highlight")
		outline.Name = OUTLINE_NAME
		outline.FillTransparency = 1
		outline.OutlineColor = Config.MostWanted.OutlineColor
		outline.OutlineTransparency = 0
		-- Seen only where the player is in plain view, so hiding behind cover still works.
		outline.DepthMode = Enum.HighlightDepthMode.Occluded
		outline.Parent = character
	elseif not wanted and existing then
		existing:Destroy()
	end
end

local function updateBoard()
	local player = current
	if emptyLabel then
		emptyLabel.Visible = player == nil
	end
	if photo then
		photo.Visible = player ~= nil
		photo.Image = if player then `rbxthumb://type=AvatarHeadShot&id={player.UserId}&w=150&h=150` else ""
	end
	if nameLabel then
		nameLabel.Visible = player ~= nil
		nameLabel.Text = if player then player.DisplayName else ""
	end
	if coinsLabel then
		coinsLabel.Visible = player ~= nil
		coinsLabel.Text = if player then `{StoreCatalog.withCommas(EconomyService:GetCoins(player))} coins` else ""
	end
end

local function refresh()
	local best = richest()
	if best ~= current then
		current = best
		Workspace:SetAttribute("MostWantedUserId", if best then best.UserId else nil)
	end
	updateBoard()
	for _, player in Players:GetPlayers() do
		updateOutline(player)
	end
end

local function findBoard()
	local board = CollectionService:GetTagged("MostWantedBoard")[1]
	local gui = board and board:FindFirstChild("WantedGui")
	if not gui then
		warn("[MostWantedService] the MostWantedBoard part needs a WantedGui SurfaceGui (place file)")
		return
	end
	local function label(name: string): TextLabel?
		local found = gui:FindFirstChild(name, true)
		return if found and found:IsA("TextLabel") then found else nil
	end
	local image = gui:FindFirstChild("Photo", true)
	photo = if image and image:IsA("ImageLabel") then image else nil
	nameLabel = label("PlayerName")
	coinsLabel = label("Coins")
	emptyLabel = label("Empty")
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(updateOutline, player)
	end)
	player:GetAttributeChangedSignal("Disguised"):Connect(function()
		updateOutline(player)
	end)
	player:GetAttributeChangedSignal("Jailed"):Connect(function()
		updateOutline(player)
	end)
end

function MostWantedService:Init()
	findBoard()
end

function MostWantedService:Start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if player == current then
			current = nil
		end
		task.defer(refresh) -- after they're gone, so the outline rule counts the right players
	end)
	updateBoard()
	task.spawn(function()
		while true do
			refresh()
			task.wait(Config.MostWanted.RefreshSeconds)
		end
	end)
end

-- The Most Wanted player right now, or nil.
function MostWantedService:GetMostWanted(): Player?
	local player = current
	return if player and player.Parent then player else nil
end

return MostWantedService

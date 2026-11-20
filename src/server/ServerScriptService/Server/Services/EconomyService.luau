--!strict
-- Owns every coin change. Only the server ever changes coins.
-- TEMPORARY (step 1.2): coins live in a "Coins" leaderstat that starts at 0 and is NOT saved.
-- Phase 4 (DataService + ProfileStore) replaces the starting value with the player's saved data.

local Players = game:GetService("Players")

local EconomyService = {}

local function coinsValue(player: Player): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	return if coins and coins:IsA("IntValue") then coins else nil
end

local function setupLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats" -- this exact name makes Roblox show it on the player list
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = stats
	stats.Parent = player
	-- The HUD reads this attribute, so it keeps working when Phase 4 replaces the leaderstat.
	player:SetAttribute("Coins", coins.Value)
	coins.Changed:Connect(function(value)
		player:SetAttribute("Coins", value)
	end)
end

function EconomyService:Init() end

function EconomyService:Start()
	Players.PlayerAdded:Connect(setupLeaderstats)
	-- Players who joined before Start ran (common in Studio playtests).
	for _, player in Players:GetPlayers() do
		task.spawn(setupLeaderstats, player)
	end
end

function EconomyService:GetCoins(player: Player): number
	local coins = coinsValue(player)
	return if coins then coins.Value else 0
end

-- Adds a positive whole number of coins. Returns false (and changes nothing) if it can't.
function EconomyService:AddCoins(player: Player, amount: number): boolean
	local coins = coinsValue(player)
	if not coins or amount ~= amount or amount <= 0 or amount ~= math.floor(amount) or amount == math.huge then
		return false
	end
	coins.Value += amount
	return true
end

-- Coal: mined in Naughty Jail, kept forever, spent later on Naughty gadgets and Advent doors.
-- TEMPORARY like coins: a player attribute that starts at 0 and is NOT saved until Phase 4.
function EconomyService:GetCoal(player: Player): number
	local coal = player:GetAttribute("Coal")
	return if type(coal) == "number" then coal else 0
end

function EconomyService:AddCoal(player: Player, amount: number): boolean
	if amount ~= amount or amount <= 0 or amount ~= math.floor(amount) or amount == math.huge then
		return false
	end
	player:SetAttribute("Coal", EconomyService:GetCoal(player) + amount)
	return true
end

-- Spends coins only if the player can afford it. Check and spend happen with no yield between.
function EconomyService:TrySpend(player: Player, amount: number): boolean
	local coins = coinsValue(player)
	if not coins or amount ~= amount or amount <= 0 or amount ~= math.floor(amount) or coins.Value < amount then
		return false
	end
	coins.Value -= amount
	return true
end

return EconomyService

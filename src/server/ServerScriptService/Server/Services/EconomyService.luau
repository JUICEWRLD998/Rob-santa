--!strict
-- Owns every coin and coal change. Only the server ever changes them.
-- Since step 4.1 the numbers live in the player's saved data (DataService). This module shows
-- them to the client: the "Coins" leaderstat (the player list) and the Coins / Coal attributes
-- (the HUD and the jail panel). Those are display copies; changing them changes nothing.
-- Until a player's data has loaded, every change is refused (returns false).

local DataService = require(script.Parent.DataService)

local EconomyService = {}

-- A positive whole number that isn't NaN or infinite.
local function isValidAmount(amount: number): boolean
	return amount == amount and amount > 0 and amount ~= math.huge and amount == math.floor(amount)
end

local function coinsValue(player: Player): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	return if coins and coins:IsA("IntValue") then coins else nil
end

-- Copies the saved numbers onto the display copies the client reads.
local function show(player: Player)
	local data = DataService:GetData(player)
	if not data or not player.Parent then
		return
	end
	local coins = coinsValue(player)
	if coins then
		coins.Value = data.coins
	end
	player:SetAttribute("Coins", data.coins)
	player:SetAttribute("Coal", data.coal)
end

local function setupLeaderstats(player: Player)
	if not player:FindFirstChild("leaderstats") then
		local stats = Instance.new("Folder")
		stats.Name = "leaderstats" -- this exact name makes Roblox show it on the player list
		local coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = stats
		stats.Parent = player
	end
	show(player)
end

function EconomyService:Init()
	-- Registered in Init so no player's load is missed (DataService:Start loads them).
	DataService:OnLoaded(setupLeaderstats)
end

function EconomyService:GetCoins(player: Player): number
	local data = DataService:GetData(player)
	return if data then data.coins else 0
end

-- Adds a positive whole number of coins. Returns false (and changes nothing) if it can't.
function EconomyService:AddCoins(player: Player, amount: number): boolean
	local data = DataService:GetData(player)
	if not data or not isValidAmount(amount) then
		return false
	end
	data.coins += amount
	show(player)
	return true
end

-- Spends coins only if the player can afford it. Check and spend happen with no yield between.
function EconomyService:TrySpend(player: Player, amount: number): boolean
	local data = DataService:GetData(player)
	if not data or not isValidAmount(amount) or data.coins < amount then
		return false
	end
	data.coins -= amount
	show(player)
	return true
end

-- Coal: mined in Naughty Jail, kept forever, spent later on Naughty gadgets and Advent doors.
function EconomyService:GetCoal(player: Player): number
	local data = DataService:GetData(player)
	return if data then data.coal else 0
end

function EconomyService:AddCoal(player: Player, amount: number): boolean
	local data = DataService:GetData(player)
	if not data or not isValidAmount(amount) then
		return false
	end
	data.coal += amount
	show(player)
	return true
end

return EconomyService

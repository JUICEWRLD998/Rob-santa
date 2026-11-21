--!strict
-- Zone ownership and the barriers (the striped gates into Zone 2 and Zone 3, tagged Barrier with a
-- Zone attribute). Zones are bought in the Gadget Shop (ShopService, step 4.2) and saved in
-- data.zonesOwned. The barrier only disappears for owners, and only on their own screen
-- (ZoneController makes it walk-through locally), so for everyone else it stays solid.
-- A barrier alone can't stop an exploiter who walks through walls, so PresentService also asks
-- OwnsZone on every grab: loot in a zone you don't own can't be taken.
-- Config.Debug.OpenZonesInStudio opens every barrier for everyone in Studio playtests only.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local OPEN_TRANSPARENCY = 0.75 -- an opened test barrier stays faintly visible

local ZoneService = {}

local openForEveryone = RunService:IsStudio() and Config.Debug.OpenZonesInStudio

local function openForTesting(barrier: BasePart)
	for _, part in barrier:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Transparency = math.max(part.Transparency, OPEN_TRANSPARENCY)
		end
	end
	barrier.CanCollide = false
	barrier.Transparency = math.max(barrier.Transparency, OPEN_TRANSPARENCY)
end

function ZoneService:Init() end

function ZoneService:Start()
	if openForEveryone then
		local opened = 0
		for _, barrier in CollectionService:GetTagged("Barrier") do
			if barrier:IsA("BasePart") then
				openForTesting(barrier)
				opened += 1
			end
		end
		print(`[ZoneService] Studio test: {opened} zone barrier(s) open (Config.Debug.OpenZonesInStudio)`)
	end
end

-- True if the player may take loot in `zone`. Zone 1 is free; the others must be bought.
-- False while the player's save is still loading.
function ZoneService:OwnsZone(player: Player, zone: number): boolean
	if zone <= 1 or openForEveryone then
		return true
	end
	local data = DataService:GetData(player)
	return data ~= nil and table.find(data.zonesOwned, zone) ~= nil
end

return ZoneService

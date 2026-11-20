--!strict
-- Zone barriers (the striped gates into Zone 2 and Zone 3, tagged Barrier with a Zone attribute).
-- For now: a Studio-only test switch (Config.Debug.OpenZonesInStudio) opens them so zones 2-3 can
-- be playtested before zones can be bought. Step 4.2 adds buying a zone here, and then
-- PresentService must also check zone ownership on every grab (docs/08-SECURITY.md, known gaps).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local OPEN_TRANSPARENCY = 0.75 -- an opened test barrier stays faintly visible

local ZoneService = {}

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
	if RunService:IsStudio() and Config.Debug.OpenZonesInStudio then
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

return ZoneService

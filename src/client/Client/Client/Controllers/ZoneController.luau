--!strict
-- Opens the zone barriers you own, on your screen only (step 4.2). Barriers are tagged Barrier
-- with a Zone attribute; ownership comes from the Shop_Zone2 / Shop_Zone3 attributes ShopService
-- sets on the Player. Your character is moved by your own client, so a barrier that is
-- walk-through here lets you in, while it stays solid for everyone who hasn't bought the zone.
-- Decides nothing: the server refuses grabs in zones you don't own (ZoneService:OwnsZone).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local OPEN_TRANSPARENCY = 0.8 -- an owned barrier stays faintly visible, like an open gate

local ZoneController = {}

local player = Players.LocalPlayer
-- Each barrier part's original look, so it can be put back.
local original: { [BasePart]: { transparency: number, canCollide: boolean } } = {}

local function partsOf(barrier: BasePart): { BasePart }
	local parts = { barrier }
	for _, descendant in barrier:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function owns(zone: number): boolean
	local level = player:GetAttribute(`Shop_Zone{zone}`) -- ShopCatalog.attributeName("Zone2"/"Zone3")
	return type(level) == "number" and level >= 1
end

local function apply(barrier: Instance)
	local zone = barrier:GetAttribute("Zone")
	if not barrier:IsA("BasePart") or type(zone) ~= "number" then
		return
	end
	local open = owns(zone)
	for _, part in partsOf(barrier) do
		local saved = original[part]
		if not saved then
			saved = { transparency = part.Transparency, canCollide = part.CanCollide }
			original[part] = saved
		end
		part.CanCollide = if open then false else saved.canCollide
		part.Transparency = if open then math.max(saved.transparency, OPEN_TRANSPARENCY) else saved.transparency
	end
end

local function applyAll()
	for _, barrier in CollectionService:GetTagged("Barrier") do
		apply(barrier)
	end
end

function ZoneController:Init() end

function ZoneController:Start()
	CollectionService:GetInstanceAddedSignal("Barrier"):Connect(apply)
	for _, zone in { 2, 3 } do
		player:GetAttributeChangedSignal(`Shop_Zone{zone}`):Connect(applyAll)
	end
	applyAll()
end

return ZoneController

--!strict
-- Step 5.4: the Mythic present's animated rainbow ribbon (docs/04 section 4). Looks only: each
-- client cycles the ribbon colour on its own screen, so the server sends nothing per frame.
-- A present is a Model tagged "Present" with a Rarity attribute (set by PresentService); its
-- PrimaryPart is the box, every other part is ribbon or bow.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PRESENT_TAG = "Present"

local PresentFxController = {}

-- Ribbon parts of every rainbow present on screen, refreshed when presents come and go.
local ribbons: { [Model]: { BasePart } } = {}

local function track(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local rarity = instance:GetAttribute("Rarity")
	local wrapping = if type(rarity) == "string" then (Config.Wrapping :: any)[rarity] else nil
	if not wrapping or not wrapping.rainbowRibbon then
		return
	end
	local parts: { BasePart } = {}
	for _, part in instance:GetDescendants() do
		if part:IsA("BasePart") and part ~= instance.PrimaryPart then
			table.insert(parts, part)
		end
	end
	ribbons[instance] = parts
end

function PresentFxController:Init() end

function PresentFxController:Start()
	CollectionService:GetInstanceAddedSignal(PRESENT_TAG):Connect(function(instance)
		task.defer(track, instance) -- let its parts and attributes arrive first
	end)
	CollectionService:GetInstanceRemovedSignal(PRESENT_TAG):Connect(function(instance)
		ribbons[instance :: Model] = nil
	end)
	for _, instance in CollectionService:GetTagged(PRESENT_TAG) do
		track(instance)
	end
	local period = Config.Wrapping.RainbowSeconds
	RunService.RenderStepped:Connect(function()
		if next(ribbons) == nil then
			return
		end
		local hue = (os.clock() / period) % 1
		for model, parts in ribbons do
			if not model.Parent then
				ribbons[model] = nil
				continue
			end
			for i, part in parts do
				-- Each piece a little further round the wheel, so the colour runs along the ribbon.
				part.Color = Color3.fromHSV((hue + i * 0.08) % 1, 0.75, 1)
			end
		end
	end)
end

return PresentFxController

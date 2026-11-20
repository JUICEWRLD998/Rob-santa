--!strict
-- Hides every "Steal" prompt on this screen while the player's hands are full, so they are not
-- offered a grab the server would refuse. Display only: the server still checks every grab.
-- Reads the CarryCount / CarryCapacity attributes PresentService sets on the Player.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local PRESENT_TAG = "Present"

local PresentController = {}

local player = Players.LocalPlayer
local watched: { [Instance]: RBXScriptConnection } = {}

local function handsFull(): boolean
	local count = player:GetAttribute("CarryCount")
	local capacity = player:GetAttribute("CarryCapacity")
	if type(count) ~= "number" or type(capacity) ~= "number" then
		return false
	end
	return count >= capacity
end

local function applyTo(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Enabled = not handsFull()
	end
end

local function applyAll()
	for _, model in CollectionService:GetTagged(PRESENT_TAG) do
		for _, descendant in model:GetDescendants() do
			applyTo(descendant)
		end
	end
end

local function watch(model: Instance)
	if watched[model] then
		return
	end
	-- The server makes a fresh prompt each time a present comes to rest.
	watched[model] = model.DescendantAdded:Connect(applyTo)
	for _, descendant in model:GetDescendants() do
		applyTo(descendant)
	end
end

local function unwatch(model: Instance)
	local connection = watched[model]
	if connection then
		connection:Disconnect()
		watched[model] = nil
	end
end

function PresentController:Init() end

function PresentController:Start()
	CollectionService:GetInstanceAddedSignal(PRESENT_TAG):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(PRESENT_TAG):Connect(unwatch)
	for _, model in CollectionService:GetTagged(PRESENT_TAG) do
		watch(model)
	end
	player:GetAttributeChangedSignal("CarryCount"):Connect(applyAll)
	player:GetAttributeChangedSignal("CarryCapacity"):Connect(applyAll)
end

return PresentController

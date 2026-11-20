--!strict
-- Hides prompts on things that belong to someone else (another player's toys), so you are never
-- offered "Sell" on a toy that isn't yours. Display only: the server checks the owner anyway.
-- Works on any model tagged "OwnerOnly" with an OwnerUserId attribute (set by ShelfService).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local OWNER_TAG = "OwnerOnly"
local OWNER_ATTRIBUTE = "OwnerUserId"

local OwnerPromptController = {}

local player = Players.LocalPlayer
local watched: { [Instance]: RBXScriptConnection } = {}

local function isMine(model: Instance): boolean
	return model:GetAttribute(OWNER_ATTRIBUTE) == player.UserId
end

local function apply(model: Instance, descendant: Instance)
	if descendant:IsA("ProximityPrompt") then
		descendant.Enabled = isMine(model)
	end
end

local function watch(model: Instance)
	if watched[model] then
		return
	end
	watched[model] = model.DescendantAdded:Connect(function(descendant)
		apply(model, descendant)
	end)
	for _, descendant in model:GetDescendants() do
		apply(model, descendant)
	end
end

local function unwatch(model: Instance)
	local connection = watched[model]
	if connection then
		connection:Disconnect()
		watched[model] = nil
	end
end

function OwnerPromptController:Init() end

function OwnerPromptController:Start()
	CollectionService:GetInstanceAddedSignal(OWNER_TAG):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(OWNER_TAG):Connect(unwatch)
	for _, model in CollectionService:GetTagged(OWNER_TAG) do
		watch(model)
	end
end

return OwnerPromptController

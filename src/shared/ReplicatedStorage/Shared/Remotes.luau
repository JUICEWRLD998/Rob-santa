--!strict
-- One list of every RemoteEvent name. The server creates them at boot under
-- ReplicatedStorage/Remotes (outside the synced Shared folder, which holds scripts only).
-- The client only ever waits for them. Every ClientToServer remote must be validated on the
-- server: player state, distance, ownership, cooldown, rate limit, argument types.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local CLIENT_WAIT_SECONDS = 10

export type Direction = "ServerToClient" | "ClientToServer"

-- Add a remote here first, then use it. Typos fail loudly in Remotes.get.
-- RULE (step 2.4 security review): add a ClientToServer remote in the SAME change as its
-- validated server handler. A remote with no handler is still callable by exploiters, and the
-- server queues their events. Planned: RequestSnowball (6.4: throw intent, server picks the target).
local EVENTS: { [string]: Direction } = {
	UnwrapReveal = "ServerToClient", -- unwrap result: toy, rarity, mutation
	Notify = "ServerToClient", -- banners and short messages
	JailUpdate = "ServerToClient", -- jail timer and coal count
	RequestDisguise = "ClientToServer", -- no arguments; DisguiseService validates (3.4)
	DisguiseUpdate = "ServerToClient", -- disguise state for the button, camera and sounds
	RequestPurchase = "ClientToServer", -- item id only, never a price; ShopService validates (4.2)
	ShopResult = "ServerToClient", -- Types.ShopResult: bought or why not, for the shop screen
	IndexSync = "ServerToClient", -- { string }: every Index key the player has found (4.4)
	RequestBailOut = "ClientToServer", -- no arguments: use a saved free Bail Out; MonetizationService validates (6.2)
	RequestAdventDoor = "ClientToServer", -- (day, "Free" | "Coal" | "Robux"); DailyService validates (6.3)
	DailySync = "ServerToClient", -- Types.DailySync: calendar, streak and quests for the Daily screen (6.3)
}

local Remotes = {}

-- Server only. Safe to call twice.
function Remotes.createAll()
	assert(RunService:IsServer(), "Remotes.createAll is server-only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.get(name: string): RemoteEvent
	assert(EVENTS[name], `unknown remote "{name}" (add it to Remotes.luau)`)
	local remote: Instance?
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		remote = folder and folder:FindFirstChild(name)
	else
		local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_WAIT_SECONDS)
		remote = folder and folder:WaitForChild(name, CLIENT_WAIT_SECONDS)
	end
	assert(remote and remote:IsA("RemoteEvent"), `remote "{name}" missing (did the server call createAll?)`)
	return remote
end

function Remotes.direction(name: string): Direction?
	return EVENTS[name]
end

return table.freeze(Remotes)

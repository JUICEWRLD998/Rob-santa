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

-- Add a remote here first, then use it. Unused entries are fine; typos are not.
local EVENTS: { [string]: Direction } = {
	UnwrapReveal = "ServerToClient", -- unwrap result: toy, rarity, mutation
	Notify = "ServerToClient", -- banners and short messages
	JailUpdate = "ServerToClient", -- jail timer and coal count
	RequestDisguise = "ClientToServer", -- Q / gift-box button / ButtonY
	RequestSnowball = "ClientToServer", -- throw intent; server picks the target
	RequestPurchase = "ClientToServer", -- shop item id only, never a price
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

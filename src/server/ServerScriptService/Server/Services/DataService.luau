--!strict
-- The ONLY module that touches saved data (step 4.1). Uses ProfileStore (Lib/ProfileStore.luau, by
-- loleris), which session-locks each player's save: only one server can own it at a time, so items
-- can't be duplicated by joining two servers. It saves every 5 minutes, when the player leaves and
-- when the server shuts down.
-- Other services read and change the table from GetData(); changes are saved automatically.
-- Never call DataStoreService anywhere else.
-- In Studio, saving needs Game Settings > Security > "Enable Studio Access to API Services".
-- Without it ProfileStore prints "data will not be saved" and keeps everything in memory only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProfileStore = require(script.Parent.Parent.Lib.ProfileStore)

local STORE_NAME = "PlayerData"
local KEY_PREFIX = "Player_"

-- One shelved toy. `mutation` is left out when the toy has none.
export type SavedShelfToy = { slot: number, toyId: string, mutation: string? }
-- One toy waiting on the unwrap table.
export type SavedTableToy = { toyId: string, mutation: string? }

export type PlayerData = {
	dataVersion: number,
	coins: number,
	coal: number,
	shelves: { SavedShelfToy },
	tableToys: { SavedTableToy },
	shelvesBought: number, -- extra shelves on top of Config.Shelves.Start (step 4.2)
	upgrades: { boots: number, extraWrap: number, quietSteps: number, snowball: boolean },
	zonesOwned: { number }, -- zone numbers; Zone 1 is free
	index: { [string]: boolean }, -- "toyId" or "toyId:Mutation" -> found (step 4.4)
	adventDoors: { number }, -- December days opened (step 6.3)
	loginStreak: number, -- days in a row (step 6.3)
	lastLoginTime: number, -- os.time() of the latest join
	lastSeen: number, -- os.time() of the latest save; offline earnings count from here
	purchases: { [string]: boolean }, -- PurchaseIds already granted (Phase 6, ProcessReceipt)
}

-- New players start with this. When a field is added later, Reconcile() fills it in for old saves.
local TEMPLATE: PlayerData = {
	dataVersion = 1,
	coins = 0,
	coal = 0,
	shelves = {},
	tableToys = {},
	shelvesBought = 0,
	upgrades = { boots = 0, extraWrap = 0, quietSteps = 0, snowball = false },
	zonesOwned = { 1 },
	index = {},
	adventDoors = {},
	loginStreak = 0,
	lastLoginTime = 0,
	lastSeen = 0,
	purchases = {},
}

type Session = {
	profile: any, -- ProfileStore's Profile (the library is not typed)
	offlineSeconds: number, -- time since the last save, paid once by ShelfService
	previousLoginTime: number, -- lastLoginTime before this join (for the login streak, 6.3)
}

type Listener = (player: Player, data: PlayerData) -> ()

local DataService = {}

local store: any
local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local loadedListeners: { Listener } = {}
local waiting: { [Player]: { thread } } = {}

local function wakeWaiters(player: Player)
	local threads = waiting[player]
	waiting[player] = nil
	if threads then
		for _, thread in threads do
			task.spawn(thread)
		end
	end
end

local function onPlayerAdded(player: Player)
	if sessions[player] or loading[player] then
		return
	end
	loading[player] = true
	local profile = store:StartSessionAsync(`{KEY_PREFIX}{player.UserId}`, {
		Cancel = function(): boolean
			return player.Parent ~= Players
		end,
	})
	loading[player] = nil
	if profile == nil then
		-- Another server kept the lock, or Roblox's data servers are down. Playing on would mean
		-- playing with progress that can't be saved, so send them back to try again.
		wakeWaiters(player)
		if player.Parent == Players then
			player:Kick("Your save couldn't be loaded. Please rejoin.")
		end
		return
	end
	profile:AddUserId(player.UserId) -- GDPR: lets Roblox erase this save on request
	profile:Reconcile()

	if player.Parent ~= Players then
		-- Left while the save was loading.
		profile:EndSession()
		wakeWaiters(player)
		return
	end

	local data = profile.Data :: PlayerData
	local now = os.time()
	local session: Session = {
		profile = profile,
		offlineSeconds = if data.lastSeen > 0 then math.max(0, now - data.lastSeen) else 0,
		previousLoginTime = data.lastLoginTime,
	}
	data.lastLoginTime = now
	data.lastSeen = now
	-- Stamp the time on every save, so the next join knows how long the player was away.
	profile.OnSave:Connect(function()
		data.lastSeen = os.time()
	end)
	profile.OnSessionEnd:Connect(function()
		sessions[player] = nil
		if player.Parent == Players then
			-- Another server took the save (the player joined somewhere else).
			player:Kick("Your save was opened in another server. Please rejoin.")
		end
	end)
	sessions[player] = session

	wakeWaiters(player)
	for _, listener in loadedListeners do
		task.spawn(listener, player, data)
	end
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session then
		session.profile:EndSession() -- saves one last time and releases the lock
	end
	wakeWaiters(player)
end

function DataService:Init()
	store = ProfileStore.New(STORE_NAME, TEMPLATE)
	-- Problems inside ProfileStore (DataStore outages, throttling) arrive here instead of erroring.
	ProfileStore.OnError:Connect(function(message: string, storeName: string, key: string)
		warn(`[DataService] ProfileStore error ({storeName} / {key}): {message}`)
	end)
end

-- Studio-only test hook (Config.Debug.DataHookInStudio). Test code runs in its own copy of the
-- modules, so it can't see `sessions`; this BindableFunction reaches the real one.
--   Invoke("get", player)               -> a copy of the player's data (nil if not loaded)
--   Invoke("set", player, field, value) -> replaces one top-level field; true if it worked
local function createDebugHook()
	if not (RunService:IsStudio() and Config.Debug.DataHookInStudio) then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "DebugData"
	hook.OnInvoke = function(action: string, player: Player, field: string?, value: any): any
		local data = DataService:GetData(player) :: any
		if not data then
			return nil
		end
		if action == "get" then
			return table.clone(data)
		elseif action == "set" and type(field) == "string" and data[field] ~= nil then
			data[field] = value
			return true
		end
		return nil
	end
	hook.Parent = ServerStorage
end

function DataService:Start()
	createDebugHook()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Players who joined before Start ran (common in Studio playtests).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- The player's saved data, or nil if it hasn't loaded yet (or they left). Change it in place;
-- ProfileStore saves it. Don't hold on to it after a yield: the player may have left.
function DataService:GetData(player: Player): PlayerData?
	local session = sessions[player]
	return if session then session.profile.Data :: PlayerData else nil
end

-- Yields until the player's data has loaded. Returns nil if they left or it failed to load.
function DataService:WaitForData(player: Player): PlayerData?
	local data = DataService:GetData(player)
	if data or player.Parent ~= Players then
		return data
	end
	local threads = waiting[player]
	if not threads then
		threads = {}
		waiting[player] = threads
	end
	table.insert(threads, coroutine.running())
	coroutine.yield()
	return DataService:GetData(player)
end

-- Calls `listener(player, data)` each time a player's data finishes loading. Register in Init.
function DataService:OnLoaded(listener: Listener)
	table.insert(loadedListeners, listener)
end

-- Seconds the player was away since their last save. Returns it once, then 0, so offline
-- earnings can never be paid twice in one session.
function DataService:TakeOfflineSeconds(player: Player): number
	local session = sessions[player]
	if not session then
		return 0
	end
	local seconds = session.offlineSeconds
	session.offlineSeconds = 0
	return seconds
end

-- os.time() of the join before this one (0 for a new player). For the login streak in 6.3.
function DataService:GetPreviousLoginTime(player: Player): number
	local session = sessions[player]
	return if session then session.previousLoginTime else 0
end

return DataService

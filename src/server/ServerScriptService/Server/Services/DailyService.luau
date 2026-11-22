--!strict
-- Reasons to come back (step 6.3, docs/01-GAME-DESIGN.md section 11). Every date is UTC.
--   Advent Calendar: doors 1-25 of December. Door N opens free on December N ("Today"). Earlier
--     doors not opened are "Missed": open them with Config.Advent.CatchUpCoal coal, or with the
--     Advent catch-up developer product (MonetizationService calls GrantAdventCatchUp from its
--     ProcessReceipt). Rewards in Config.Advent.Rewards; day 25 is a guaranteed Mythic. A toy
--     reward goes on the unwrap table with the full reveal. After Christmas, missed doors can be
--     caught up until January CatchUpUntilJanuaryDay; a new December clears the calendar.
--   Login streak: paid once per UTC day (on join, or at midnight while playing). Missing a day
--     starts again at day 1; day 8 onward keeps paying the day-7 reward.
--   Daily quests: Config.Quests.Count picked per player per UTC day from Config.Quests.Pool (the
--     same picks all day, even after a rejoin). Progress comes from Lib/GameEvents; a quest pays
--     the moment its goal is reached.
-- The Daily screen (client DailyController) only displays DailySync; the server decides everything.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StoreCatalog = require(ReplicatedStorage.Shared.StoreCatalog)
local Toys = require(ReplicatedStorage.Shared.Toys)
local Types = require(ReplicatedStorage.Shared.Types)
local GameEvents = require(script.Parent.Parent.Lib.GameEvents)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local IndexService = require(script.Parent.IndexService)
local ShelfService = require(script.Parent.ShelfService)

type PlayerData = DataService.PlayerData
type Clock = { time: number, year: number, month: number, day: number, dayNumber: number }
type Season = { year: number, available: number, today: number? }
type Quest = {
	id: string,
	text: string,
	goal: number,
	event: string,
	coinMinutes: number,
	minCoins: number,
}

local SECONDS_PER_DAY = 86400
local METHODS = { Free = true, Coal = true, Robux = true }

local DailyService = {}

local notify: RemoteEvent
local dailySync: RemoteEvent
local unwrapReveal: RemoteEvent
local clockOffset = 0 -- whole days, Studio test hook only: pretend it is another date
local lastRequest: { [Player]: number } = {}
local pendingDoor: { [Player]: number } = {} -- the missed door a Robux catch-up was asked for

local function message(player: Player, text: string)
	if player.Parent then
		notify:FireClient(player, text)
	end
end

local function clock(): Clock
	local now = os.time() + clockOffset
	local date = os.date("!*t", now)
	return {
		time = now,
		year = date.year,
		month = date.month,
		day = date.day,
		dayNumber = now // SECONDS_PER_DAY,
	}
end

-- Days since 1970-01-01 for a UTC date (Howard Hinnant's days_from_civil). Test hook only.
local function daysFromCivil(year: number, month: number, day: number): number
	local y = if month <= 2 then year - 1 else year
	local era = y // 400
	local yearOfEra = y - era * 400
	local dayOfYear = (153 * (if month > 2 then month - 3 else month + 9) + 2) // 5 + day - 1
	local dayOfEra = yearOfEra * 365 + yearOfEra // 4 - yearOfEra // 100 + dayOfYear
	return era * 146097 + dayOfEra - 719468
end

-- Which December the calendar belongs to right now, how many doors have come up, and today's door.
-- nil = the calendar is closed (before December, or after the January catch-up days).
local function seasonOf(now: Clock): Season?
	local lastDay = Config.Advent.LastDay
	if now.month == 12 then
		return {
			year = now.year,
			available = math.min(now.day, lastDay),
			today = if now.day <= lastDay then now.day else nil,
		}
	elseif now.month == 1 and now.day <= Config.Advent.CatchUpUntilJanuaryDay then
		return { year = now.year - 1, available = lastDay, today = nil }
	end
	return nil
end

-- A new December starts a fresh calendar. Call before changing adventDoors.
local function syncSeason(data: PlayerData, season: Season)
	if data.adventYear ~= season.year then
		data.adventYear = season.year
		data.adventDoors = {}
	end
end

local function doorState(data: PlayerData, season: Season?, day: number): Types.AdventDoorState
	if season and data.adventYear == season.year and table.find(data.adventDoors, day) then
		return "Opened"
	elseif season and season.today == day then
		return "Today"
	elseif season and day <= season.available then
		return "Missed"
	end
	return "Locked"
end

local function rewardCoins(player: Player, coinMinutes: number, minCoins: number): number
	return StoreCatalog.incomeCoins(ShelfService:GetIncomePerSecond(player), coinMinutes * 60, minCoins)
end

----------------------------------------------------------------------------------------------------
-- Quests

local function questsFor(player: Player, dayNumber: number): { Quest }
	local pool = Config.Quests.Pool :: { Quest }
	local order = {}
	for index = 1, #pool do
		order[index] = index
	end
	-- Same seed all day for this player, so the picks survive a rejoin or a server change.
	local rng = Random.new(player.UserId * 1000 + dayNumber)
	for index = #order, 2, -1 do
		local swap = rng:NextInteger(1, index)
		order[index], order[swap] = order[swap], order[index]
	end
	local picked = {}
	for index = 1, math.min(Config.Quests.Count, #order) do
		table.insert(picked, pool[order[index]])
	end
	return picked
end

local function questText(quest: Quest): string
	return if string.find(quest.text, "%%d") then string.format(quest.text, quest.goal) else quest.text
end

----------------------------------------------------------------------------------------------------
-- Sync

local function buildSync(player: Player, data: PlayerData): Types.DailySync
	local now = clock()
	local season = seasonOf(now)
	local doors: { Types.AdventDoorState } = {}
	local rewards: { string } = {}
	for day = 1, Config.Advent.LastDay do
		doors[day] = doorState(data, season, day)
		local reward = Config.Advent.Rewards[day]
		rewards[day] = if reward and reward.rarity then reward.rarity else "Coins"
	end
	local streakRewards = {}
	for index, reward in Config.LoginStreak.Rewards do
		streakRewards[index] = rewardCoins(player, reward.coinMinutes, reward.minCoins)
	end
	local quests: { Types.DailyQuest } = {}
	local progress = if data.quests.day == now.dayNumber then data.quests.progress else {}
	for _, quest in questsFor(player, now.dayNumber) do
		local done = math.min(quest.goal, progress[quest.id] or 0)
		table.insert(quests, {
			text = questText(quest),
			progress = done,
			goal = quest.goal,
			reward = rewardCoins(player, quest.coinMinutes, quest.minCoins),
			done = done >= quest.goal,
		})
	end
	return {
		doors = doors,
		rewards = rewards,
		calendarOpen = season ~= nil,
		catchUpCoal = Config.Advent.CatchUpCoal,
		coal = data.coal,
		streak = if data.lastStreakDay == now.dayNumber then data.loginStreak else 0,
		streakRewards = streakRewards,
		quests = quests,
		secondsToNextDay = SECONDS_PER_DAY - now.time % SECONDS_PER_DAY,
	}
end

local function sync(player: Player)
	local data = DataService:GetData(player)
	if data and player.Parent then
		dailySync:FireClient(player, buildSync(player, data))
	end
end

----------------------------------------------------------------------------------------------------
-- New day: streak and quest reset

local function checkDay(player: Player, data: PlayerData)
	local today = clock().dayNumber
	if data.quests.day ~= today then
		data.quests = { day = today, progress = {} }
	end
	if data.lastStreakDay == today then
		return
	end
	data.loginStreak = if data.lastStreakDay == today - 1 then data.loginStreak + 1 else 1
	data.lastStreakDay = today
	local rewards = Config.LoginStreak.Rewards
	local reward = rewards[math.min(data.loginStreak, #rewards)]
	local coins = rewardCoins(player, reward.coinMinutes, reward.minCoins)
	EconomyService:AddCoins(player, coins)
	message(player, `Day {data.loginStreak} login streak! +{StoreCatalog.withCommas(coins)} coins`)
end

local function onQuestEvent(eventName: string, player: Player, amount: number)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	checkDay(player, data)
	local changed = false
	for _, quest in questsFor(player, data.quests.day) do
		if quest.event ~= eventName then
			continue
		end
		local before = data.quests.progress[quest.id] or 0
		if before >= quest.goal then
			continue
		end
		local after = math.min(quest.goal, before + math.max(1, math.floor(amount)))
		data.quests.progress[quest.id] = after
		changed = true
		if after >= quest.goal then
			local coins = rewardCoins(player, quest.coinMinutes, quest.minCoins)
			EconomyService:AddCoins(player, coins)
			message(player, `Quest done: {questText(quest)}! +{StoreCatalog.withCommas(coins)} coins`)
		end
	end
	if changed then
		sync(player)
	end
end

----------------------------------------------------------------------------------------------------
-- Advent doors

-- Gives door `day`'s reward and marks it opened. Never yields (it runs inside ProcessReceipt).
-- Returns false and changes nothing if the reward can't be given.
local function openDoor(player: Player, data: PlayerData, day: number): boolean
	local reward = Config.Advent.Rewards[day]
	if not reward then
		return false
	end
	local rarity = reward.rarity
	if rarity then
		local choices = Toys.ofRarity(rarity :: Types.Rarity)
		if #choices == 0 then
			return false
		end
		local toy = choices[math.random(1, #choices)]
		local owned: Types.OwnedToy = { uid = HttpService:GenerateGUID(false), toyId = toy.id, mutation = nil }
		if not ShelfService:AddUnwrapped(player, owned) then
			return false
		end
		table.insert(data.adventDoors, day)
		local result: Types.UnwrapResult = { toyId = toy.id, rarity = toy.rarity, mutation = nil }
		unwrapReveal:FireClient(player, result)
		IndexService:Record(player, toy.id, nil)
		message(player, `Advent day {day}: a {rarity} {toy.name}! It's on your unwrap table.`)
	else
		local coins = rewardCoins(player, reward.coinMinutes or 0, reward.minCoins or 0)
		if not EconomyService:AddCoins(player, coins) then
			return false
		end
		table.insert(data.adventDoors, day)
		message(player, `Advent day {day}: +{StoreCatalog.withCommas(coins)} coins!`)
	end
	return true
end

local function firstMissed(data: PlayerData, season: Season): number?
	for day = 1, season.available do
		if doorState(data, season, day) == "Missed" then
			return day
		end
	end
	return nil
end

local function onDoorRequest(player: Player, day: any, method: any)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < Config.Advent.RequestCooldownSeconds then
		return
	end
	lastRequest[player] = now
	if type(day) ~= "number" or day ~= math.floor(day) or day < 1 or day > Config.Advent.LastDay then
		return
	end
	if type(method) ~= "string" or not METHODS[method] then
		return
	end
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local season = seasonOf(clock())
	if not season then
		message(player, "The Advent Calendar opens on December 1!")
		return
	end
	syncSeason(data, season)
	local state = doorState(data, season, day)
	if method == "Free" then
		if state ~= "Today" then
			return
		end
		openDoor(player, data, day)
	elseif method == "Coal" then
		if state ~= "Missed" then
			return
		end
		local cost = Config.Advent.CatchUpCoal
		if not EconomyService:TrySpendCoal(player, cost) then
			message(player, `You need {cost} coal. Mine it in Naughty Jail!`)
			return
		end
		if not openDoor(player, data, day) then
			EconomyService:AddCoal(player, cost) -- refund: the door didn't open
		end
	elseif method == "Robux" then
		if state ~= "Missed" then
			return
		end
		if data.adventKeys > 0 then
			-- A catch-up bought earlier, when no door was missed.
			if openDoor(player, data, day) then
				data.adventKeys -= 1
			end
		else
			local productId = Config.DevProducts.AdventCatchUp.id
			if productId > 0 then
				pendingDoor[player] = day
				MarketplaceService:PromptProductPurchase(player, productId)
			end
			return -- the receipt opens it (GrantAdventCatchUp)
		end
	end
	sync(player)
end

----------------------------------------------------------------------------------------------------

local function onLoaded(player: Player, data: PlayerData)
	checkDay(player, data)
	sync(player)
end

local function checkEveryone()
	for _, player in Players:GetPlayers() do
		local data = DataService:GetData(player)
		if data then
			checkDay(player, data)
			sync(player)
		end
	end
end

-- Studio-only test hook (Config.Debug.DailyHookInStudio).
--   Invoke("date", "2026-12-10") -> pretends it is that UTC date (time of day kept); "" = real date.
--                                   Runs the new-day check, so moving a day forward pays the streak.
--   Invoke("check")              -> runs the new-day check for every player now
--   Invoke("event", "ToySold", player, amount?) -> fires a GameEvents event in the game's own copy
--                                   of Lib/GameEvents (a test's require gets a separate copy)
-- Returns the date it now thinks it is.
local function createDebugHook()
	if not (RunService:IsStudio() and Config.Debug.DailyHookInStudio) then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "DebugDaily"
	hook.OnInvoke = function(action: string, value: string?, player: Player?, amount: number?): any
		if action == "event" and value and player then
			GameEvents.fire(value, player, amount)
			return true
		end
		if action == "date" then
			local year, month, day = string.match(value or "", "^(%d+)-(%d+)-(%d+)$")
			if year and month and day then
				local target = daysFromCivil(tonumber(year) :: number, tonumber(month) :: number, tonumber(day) :: number)
				clockOffset = (target - os.time() // SECONDS_PER_DAY) * SECONDS_PER_DAY
			else
				clockOffset = 0
			end
		end
		if action == "date" or action == "check" then
			checkEveryone()
			local now = clock()
			return `{now.year}-{now.month}-{now.day}`
		end
		return nil
	end
	hook.Parent = ServerStorage
end

-- Called by MonetizationService inside ProcessReceipt for the Advent catch-up product. Must not
-- yield. Opens the door the player picked (or the earliest missed one); if none is missed, the
-- catch-up is saved for later (adventKeys). Errors if it can't grant, so the receipt is retried.
function DailyService:GrantAdventCatchUp(player: Player, data: PlayerData)
	local season = seasonOf(clock())
	local day: number? = nil
	if season then
		syncSeason(data, season)
		local wanted = pendingDoor[player]
		day = if wanted and doorState(data, season, wanted) == "Missed" then wanted else firstMissed(data, season)
	end
	pendingDoor[player] = nil
	if day then
		if not openDoor(player, data, day) then
			error(`Advent door {day} could not be opened`)
		end
	else
		data.adventKeys += 1
		message(player, "No missed door right now, so your catch-up is saved for the next one.")
	end
	task.defer(sync, player)
end

function DailyService:Init()
	notify = Remotes.get("Notify")
	dailySync = Remotes.get("DailySync")
	unwrapReveal = Remotes.get("UnwrapReveal")
	DataService:OnLoaded(onLoaded)
	local events: { [string]: boolean } = {}
	for _, quest in Config.Quests.Pool do
		events[quest.event] = true
	end
	for eventName in events do
		GameEvents.on(eventName, function(player: Player, amount: number)
			onQuestEvent(eventName, player, amount)
		end)
	end
end

function DailyService:Start()
	Remotes.get("RequestAdventDoor").OnServerEvent:Connect(onDoorRequest)
	createDebugHook()
	-- The "Advent Calendar" prompt on the Town board. The client opens the Daily screen when it is
	-- triggered (DailyController); the server has nothing to do for it.
	for _, board in CollectionService:GetTagged("AdventCalendar") do
		if board:IsA("BasePart") and not board:FindFirstChildOfClass("ProximityPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Open"
			prompt.ObjectText = "Advent Calendar"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = Config.Advent.PromptDistance
			prompt.RequiresLineOfSight = false
			prompt.Parent = board
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		pendingDoor[player] = nil
	end)
	-- Notices a new UTC day for players already in the game, and refreshes the reward numbers as
	-- income grows.
	task.spawn(function()
		while true do
			task.wait(Config.Quests.CheckSeconds)
			checkEveryone()
		end
	end)
end

return DailyService

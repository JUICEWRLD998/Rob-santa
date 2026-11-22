--!strict
-- The first 3 minutes (step 6.5, docs/01-GAME-DESIGN.md section 14), for brand-new players only.
-- The server decides every step; TutorialController only draws the hint, the footprint trail, the
-- arrow and the pulsing buttons from TutorialSync. Numbers are in Config.Tutorial.
--   1 Grab:  footprints lead from the hideout to the nearest Zone 1 present, re-wrapped as Rare.
--            Other elves can't see the new player until the first present is home (TutorialSafe).
--   2 Bring: SpotDelaySeconds after the grab, one Zone 1 elf spots them on purpose
--            (GuardService:TutorialSpot): a slow chase that never catches, while the Wrap! button
--            pulses. Footprints lead home to the drop mat; the present unwraps there as usual.
--   3 Shelf: footprints lead to the toy on the unwrap table: "Put it on a shelf".
--     Earn:  "Your toy earns coins every second!", and GiftCoins arrive (the price of Boots 1).
--   4 Shop:  the SHOP button pulses until Boots level 1 is bought. Then the closing line, done.
-- Progress is saved (data.tutorial), so a player who leaves halfway resumes at their step.
-- Each step is logged once as an AnalyticsService onboarding funnel step (see FUNNEL below).

local AnalyticsService = game:GetService("AnalyticsService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local GameEvents = require(script.Parent.Parent.Lib.GameEvents)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local GuardService = require(script.Parent.GuardService)
local PlotService = require(script.Parent.PlotService)
local PresentService = require(script.Parent.PresentService)
local ShelfService = require(script.Parent.ShelfService)

local TUTORIAL_ZONE = 1
local SAFE_ATTRIBUTE = "TutorialSafe" -- GuardService: other elves ignore this player
local DROP_MAT_TAG = "DropMat"
local HIDEOUT_ATTRIBUTE = "Hideout"

-- Saved values of data.tutorial.
local SAVED_NEW = 0
local SAVED_GRAB = 1
local SAVED_BRING = 2
local SAVED_SHELF = 3
local SAVED_SHOP = 4
local SAVED_DONE = 100

-- Onboarding funnel steps. Never renumber: the Analytics dashboard keeps history per number; add
-- new steps at the end instead.
local FUNNEL = {
	Joined = { number = 1, name = "Player Joined" },
	Grabbed = { number = 2, name = "Grabbed First Present" },
	Escaped = { number = 3, name = "Escaped The Elf" }, -- fooled the elf, or got home without being caught
	Unwrapped = { number = 4, name = "Unwrapped First Present" },
	Shelved = { number = 5, name = "Shelved First Toy" },
	BoughtBoots = { number = 6, name = "Bought Boots (Tutorial Done)" },
}

type Session = {
	step: Types.TutorialStep,
	target: Instance?,
	logged: { [number]: boolean },
	spotted: boolean, -- the tutorial elf has been sent for this trip
	emptySince: number?, -- os.clock when they stopped carrying anything during Bring
}

local TutorialService = {}

local syncRemote: RemoteEvent
local sessions: { [Player]: Session } = {}

type FunnelStep = { number: number, name: string }

local function logFunnel(player: Player, session: Session, entry: FunnelStep)
	local number, name = entry.number, entry.name
	if session.logged[number] then
		return
	end
	session.logged[number] = true
	-- Analytics must never break the tutorial (it can throw when the rate limit is hit).
	local ok, err = pcall(function(): any
		AnalyticsService:LogOnboardingFunnelStepEvent(player, number, name)
		return nil
	end)
	if not ok then
		warn(`[TutorialService] onboarding step {number} not logged: {err}`)
	end
end

local function send(player: Player, session: Session)
	if player.Parent then
		local payload: Types.TutorialSync = { step = session.step, target = session.target }
		syncRemote:FireClient(player, payload)
	end
end

local function setStep(player: Player, session: Session, step: Types.TutorialStep, target: Instance?)
	session.step = step
	session.target = target
	session.emptySince = nil
	-- Elves leave a new player alone until their first present is home (section 14).
	player:SetAttribute(SAFE_ATTRIBUTE, if step == "Grab" or step == "Bring" then true else nil)
	send(player, session)
end

local function save(player: Player, value: number)
	local data = DataService:GetData(player)
	if data then
		data.tutorial = value
	end
end

local function dropMatOf(player: Player): BasePart?
	local index = PlotService:GetHideoutIndex(player)
	for _, mat in CollectionService:GetTagged(DROP_MAT_TAG) do
		if mat:IsA("BasePart") and mat:GetAttribute(HIDEOUT_ATTRIBUTE) == index then
			return mat
		end
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function finish(player: Player, session: Session)
	logFunnel(player, session, FUNNEL.BoughtBoots)
	save(player, SAVED_DONE)
	setStep(player, session, "Done", nil)
	task.delay(Config.Tutorial.DoneShowSeconds, function()
		if sessions[player] == session and session.step == "Done" then
			sessions[player] = nil
			setStep(player, session, "Off", nil)
		end
	end)
end

local function enterShop(player: Player, session: Session)
	local data = DataService:GetData(player)
	if data and data.upgrades.boots >= 1 then
		finish(player, session)
		return
	end
	setStep(player, session, "Shop", nil)
end

-- The first toy is on a shelf: say what that means, hand over the coins for Boots, then the shop.
local function enterEarn(player: Player, session: Session)
	local data = DataService:GetData(player)
	if data and data.tutorial < SAVED_SHOP then
		-- Saved together with the gift, so a rejoin can never pay it twice.
		data.tutorial = SAVED_SHOP
		EconomyService:AddCoins(player, Config.Tutorial.GiftCoins)
	end
	setStep(player, session, "Earn", nil)
	task.delay(Config.Tutorial.EarnShowSeconds, function()
		if sessions[player] == session and session.step == "Earn" then
			enterShop(player, session)
		end
	end)
end

local function enterShelf(player: Player, session: Session)
	save(player, SAVED_SHELF)
	setStep(player, session, "Shelf", ShelfService:GetTableToy(player))
end

local function enterGrab(player: Player, session: Session)
	save(player, SAVED_GRAB)
	session.spotted = false
	setStep(player, session, "Grab", nil) -- the check loop picks the present
end

local function enterBring(player: Player, session: Session)
	save(player, SAVED_BRING)
	setStep(player, session, "Bring", dropMatOf(player))
	if session.spotted then
		return
	end
	session.spotted = true
	task.delay(Config.Tutorial.SpotDelaySeconds, function()
		if sessions[player] == session and session.step == "Bring" and PresentService:GetCarriedCount(player) > 0 then
			GuardService:TutorialSpot(player, TUTORIAL_ZONE)
		end
	end)
end

-- Runs every CheckSeconds for each player in the tutorial: keeps the target current and notices
-- the steps no event reports (a lost present, an emptied table).
local function check(player: Player, session: Session)
	local step = session.step
	if step == "Grab" then
		local root = rootOf(player)
		if not root then
			return
		end
		local keep = session.target
		local present = PresentService:NearestResting(TUTORIAL_ZONE, root.Position, if keep and keep:IsA("Model") then keep else nil)
		if present and present ~= session.target then
			PresentService:RaiseResting(present, Config.Tutorial.FirstPresentRarity)
			session.target = present
			send(player, session)
		end
	elseif step == "Bring" then
		if PresentService:GetCarriedCount(player) > 0 or player:GetAttribute("Unwrapping") == true then
			session.emptySince = nil
		elseif not session.emptySince then
			session.emptySince = os.clock()
		elseif os.clock() - (session.emptySince :: number) > Config.Tutorial.LostPresentSeconds then
			enterGrab(player, session) -- dropped it (reset, snowball): go and get another one
		end
	elseif step == "Shelf" then
		local toy = ShelfService:GetTableToy(player)
		if not toy then
			-- Sold or shelved some other way: carry on if a toy is earning, else wait for one.
			if ShelfService:GetShelvedCount(player) > 0 then
				enterEarn(player, session)
			end
		elseif toy ~= session.target then
			session.target = toy
			send(player, session)
		end
	end
end

local function start(player: Player, data: DataService.PlayerData)
	if data.tutorial == SAVED_NEW then
		-- Reconcile gives old saves 0 too: only someone who never played before is new.
		local brandNew = DataService:GetPreviousLoginTime(player) == 0
			and #data.shelves == 0
			and #data.tableToys == 0
			and next(data.index) == nil
		data.tutorial = if brandNew then SAVED_GRAB else SAVED_DONE
	end
	if data.tutorial >= SAVED_DONE or player.Parent ~= Players then
		return
	end
	local session: Session = { step = "Off", target = nil, logged = {}, spotted = false, emptySince = nil }
	sessions[player] = session
	logFunnel(player, session, FUNNEL.Joined)
	local saved = data.tutorial
	if saved <= SAVED_BRING then
		enterGrab(player, session) -- a present carried when they left went home; fetch a new one
	elseif saved == SAVED_SHELF then
		enterShelf(player, session)
	else
		enterShop(player, session)
	end
end

local function on(name: string, handler: (player: Player, session: Session) -> ())
	GameEvents.on(name, function(player: Player)
		local session = sessions[player]
		if session then
			handler(player, session)
		end
	end)
end

-- Studio-only test hook (Config.Debug.TutorialHookInStudio):
--   ServerStorage.DebugTutorial:Invoke("restart", player) -> the tutorial starts again from Grab
--   ServerStorage.DebugTutorial:Invoke("skip", player)    -> the tutorial ends now
--   ServerStorage.DebugTutorial:Invoke("state", player)   -> the current step ("Off" if none)
local function createDebugHook()
	if not (RunService:IsStudio() and Config.Debug.TutorialHookInStudio) then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "DebugTutorial"
	hook.OnInvoke = function(action: string, player: Player): any
		local data = DataService:GetData(player)
		if not data then
			return nil
		end
		if action == "restart" then
			data.tutorial = SAVED_GRAB
			sessions[player] = nil
			start(player, data)
		elseif action == "skip" then
			data.tutorial = SAVED_DONE
			local session = sessions[player]
			sessions[player] = nil
			if session then
				setStep(player, session, "Off", nil)
			end
		end
		local session = sessions[player]
		return if session then session.step else "Off"
	end
	hook.Parent = ServerStorage
end

function TutorialService:Init()
	syncRemote = Remotes.get("TutorialSync")
	DataService:OnLoaded(function(player, data)
		start(player, data)
	end)

	on("PresentGrabbed", function(player, session)
		if session.step ~= "Grab" then
			return
		end
		-- Guaranteed Rare, even if they took a different present from the one the trail led to.
		PresentService:RaiseCarried(player, Config.Tutorial.FirstPresentRarity)
		logFunnel(player, session, FUNNEL.Grabbed)
		enterBring(player, session)
	end)
	on("InspectionSurvived", function(player, session)
		if session.step == "Bring" then
			logFunnel(player, session, FUNNEL.Escaped)
		end
	end)
	on("PresentUnwrapped", function(player, session)
		if session.step ~= "Bring" and session.step ~= "Grab" then
			return
		end
		logFunnel(player, session, FUNNEL.Escaped) -- home with it = they got away
		logFunnel(player, session, FUNNEL.Unwrapped)
		-- The toy reaches the table after the reveal starts; wait a moment so the trail finds it.
		task.delay(1, function()
			if sessions[player] == session then
				enterShelf(player, session)
			end
		end)
	end)
	on("ToyShelved", function(player, session)
		if session.step == "Shelf" or session.step == "Grab" or session.step == "Bring" then
			logFunnel(player, session, FUNNEL.Shelved)
			enterEarn(player, session)
		end
	end)
	on("ShopBought", function(player, session)
		local data = DataService:GetData(player)
		if session.step == "Shop" and data and data.upgrades.boots >= 1 then
			finish(player, session)
		end
	end)
end

function TutorialService:Start()
	createDebugHook()
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Tutorial.CheckSeconds)
			for player, session in sessions do
				if player.Parent then
					check(player, session)
				end
			end
		end
	end)
end

return TutorialService

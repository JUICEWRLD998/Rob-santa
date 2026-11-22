--!strict
-- The Sleigh Raid (step 6.4, docs/01-GAME-DESIGN.md section 9). Every number is in Config.SleighRaid.
--   Waiting -> nothing on screen (the HUD tile is hidden).
--   Warning -> WarningSeconds before landing: a chime and a small HUD tile under SHOP; the sleigh
--              (ServerStorage/Templates/Sleigh, place file) flies down onto the SleighPad.
--   Active  -> DurationSeconds: Rare-or-better presents in a ring round the sleigh (PresentService)
--              and raid elves guarding the whole Town Square (GuardService). Free-for-all.
--   Then the sleigh lifts off; raid presents nobody carries and the raid elves go with it.
-- The client reads three Workspace attributes (SleighRaidController): SleighRaidState,
-- SleighRaidLandsAt and SleighRaidEndsAt (server time, Workspace:GetServerTimeNow()).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GuardService = require(script.Parent.GuardService)
local PresentService = require(script.Parent.PresentService)

local CHECK_SECONDS = 0.25
local LIFT_OFF_SECONDS = 2 -- (my pick) the sleigh flies away this fast once the raid ends
local FLY_IN_DISTANCE = 80 -- (my pick) studs: it comes in from behind the pad and leaves ahead of it

type RaidState = "Waiting" | "Warning" | "Active"

local SleighRaidService = {}

local pad: BasePart? = nil
local template: Model? = nil
local landsAt = 0 -- server time of the next (or current) landing
local endsAt = 0 -- server time the current raid ends
local state: RaidState = "Waiting"

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function setState(newState: RaidState)
	state = newState
	Workspace:SetAttribute("SleighRaidState", newState)
	Workspace:SetAttribute("SleighRaidLandsAt", landsAt)
	Workspace:SetAttribute("SleighRaidEndsAt", endsAt)
end

-- The pad's top surface, facing the pad's front.
local function padTop(): CFrame?
	local part = pad
	if not part then
		return nil
	end
	return part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)
end

-- Moves `model` from `from` to `to` over `seconds`, stepped every frame (a server tween would
-- stall while Studio sits in the background, CLAUDE.md). easeIn speeds up; otherwise it slows down.
local function fly(model: Model, from: CFrame, to: CFrame, seconds: number, easeIn: boolean)
	local started = os.clock()
	while model.Parent do
		local t = math.clamp((os.clock() - started) / seconds, 0, 1)
		local eased = if easeIn then t * t else 1 - (1 - t) * (1 - t)
		model:PivotTo(from:Lerp(to, eased))
		if t >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

local function waitUntil(condition: () -> boolean)
	while not condition() do
		task.wait(CHECK_SECONDS)
	end
end

local function runOnce()
	local top = padTop()
	local raid = Config.SleighRaid

	setState("Waiting")
	waitUntil(function()
		return now() >= landsAt - raid.WarningSeconds
	end)

	setState("Warning")
	local sleigh: Model? = nil
	if top and template then
		local model = template:Clone()
		local high = top * CFrame.new(0, raid.FlyHeightStuds, FLY_IN_DISTANCE)
		model:PivotTo(high)
		model.Parent = Workspace
		sleigh = model
		waitUntil(function()
			return now() >= landsAt - raid.DescendSeconds
		end)
		fly(model, high, top, math.max(0.1, landsAt - now()), false)
	end
	waitUntil(function()
		return now() >= landsAt
	end)

	endsAt = landsAt + raid.DurationSeconds
	setState("Active")
	if top then
		PresentService:SpawnRaidPresents(top, raid.Presents, raid.PresentRingStuds)
		GuardService:StartRaid(top)
	end
	waitUntil(function()
		return now() >= endsAt
	end)

	PresentService:ClearRaidPresents()
	GuardService:EndRaid()
	-- Next landing one interval after this one; a raid started early by the test hook still leaves
	-- a full warning before the next.
	landsAt = math.max(landsAt + raid.IntervalSeconds, now() + raid.WarningSeconds + 1)
	setState("Waiting")
	local model = sleigh
	if model and top then
		task.spawn(function()
			fly(model, top, top * CFrame.new(0, raid.FlyHeightStuds, -FLY_IN_DISTANCE), LIFT_OFF_SECONDS, true)
			model:Destroy()
		end)
	end
end

-- Studio-only test hook (Config.Debug.RaidHookInStudio):
--   ServerStorage.DebugRaid:Invoke("start") -> the warning starts now (only while Waiting)
--   ServerStorage.DebugRaid:Invoke("end")   -> a running raid ends now
--   ServerStorage.DebugRaid:Invoke("state") -> "Waiting" | "Warning" | "Active"
local function createDebugHook()
	if not (RunService:IsStudio() and Config.Debug.RaidHookInStudio) then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "DebugRaid"
	hook.OnInvoke = function(action: string): any
		if action == "start" and state == "Waiting" then
			landsAt = now() + Config.SleighRaid.WarningSeconds
			Workspace:SetAttribute("SleighRaidLandsAt", landsAt)
		elseif action == "end" and state == "Active" then
			endsAt = now()
			Workspace:SetAttribute("SleighRaidEndsAt", endsAt)
		end
		return state
	end
	hook.Parent = ServerStorage
end

function SleighRaidService:Init()
	local found = CollectionService:GetTagged("SleighPad")[1]
	if found and found:IsA("BasePart") then
		pad = found
	else
		warn("[SleighRaidService] no SleighPad-tagged part: the Sleigh Raid has nowhere to land")
	end
	local templates = ServerStorage:FindFirstChild("Templates")
	local sleigh = templates and templates:FindFirstChild("Sleigh")
	if sleigh and sleigh:IsA("Model") then
		template = sleigh
	else
		warn("[SleighRaidService] ServerStorage/Templates/Sleigh is missing: raids run without a sleigh")
	end
end

function SleighRaidService:Start()
	createDebugHook()
	landsAt = now() + Config.SleighRaid.FirstRaidSeconds
	task.spawn(function()
		while true do
			-- (pcall of a function returning nothing types as one value: CLAUDE.md, check.sh gotcha)
			local ok, err = pcall(function(): any
				runOnce()
				return nil
			end)
			if not ok then
				-- Never let one bad raid stop the timer for the rest of the server's life.
				warn(`[SleighRaidService] raid failed: {err}`)
				PresentService:ClearRaidPresents()
				GuardService:EndRaid()
				landsAt = now() + Config.SleighRaid.IntervalSeconds
			end
		end
	end)
end

return SleighRaidService

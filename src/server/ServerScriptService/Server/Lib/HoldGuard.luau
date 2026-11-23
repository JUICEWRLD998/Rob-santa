--!strict
-- Server-side check that a hold prompt was really held (step 7.2 exploit review).
-- ProximityPrompt.HoldDuration is only timed on the client. An exploit can fire Triggered at once
-- (or set HoldDuration to 0 on its own copy), so a 1.4 s Epic steal or a coal swing would take no
-- time at all. The server sees PromptButtonHoldBegan from the same client, so it times the hold
-- itself: Triggered only counts if the hold began at least HoldDuration - HoldSlackSeconds ago.
-- Prompts with HoldDuration 0 always pass.
--
--   local held = HoldGuard.watch(prompt)
--   prompt.Triggered:Connect(function(player) if held(player) then ... end end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local HoldGuard = {}

function HoldGuard.watch(prompt: ProximityPrompt): (player: Player) -> boolean
	-- Weak keys: a player who leaves mid-hold does not stay in memory through a long-lived prompt.
	local beganAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		beganAt[player] = os.clock()
	end)
	-- Not cleared on PromptButtonHoldEnded: a finished hold ends just before Triggered arrives.
	return function(player: Player): boolean
		local hold = prompt.HoldDuration
		if hold <= 0 then
			return true
		end
		local began = beganAt[player]
		beganAt[player] = nil -- one hold, one trigger
		return began ~= nil and os.clock() - began >= hold - Config.AntiCheat.HoldSlackSeconds
	end
end

return HoldGuard

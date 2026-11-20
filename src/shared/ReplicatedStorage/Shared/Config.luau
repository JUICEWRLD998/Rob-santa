--!strict
-- EVERY tunable number in the game lives here. Source: docs/01-GAME-DESIGN.md.
-- "Make elves slower" should be a one-number change in this file.
-- Values marked (my pick) are not in the design doc; change the doc too if you keep them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local function deepFreeze<T>(t: T): T
	for _, v in t :: any do
		if type(v) == "table" and not table.isfrozen(v) then
			deepFreeze(v)
		end
	end
	return table.freeze(t :: any) :: any
end

-- Ordered lowest to highest. Index = tier (used for Lucky Wrap "one rarity higher").
local RARITY_ORDER: { Types.Rarity } = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local Config = {
	Player = {
		WalkSpeed = 16, -- Roblox default
		MaxPlayersPerServer = 8, -- set in experience settings too (Phase 8)
	},

	RarityOrder = RARITY_ORDER,

	-- Section 6: rarity values. Sell price = 45 seconds of shelf income.
	-- grabHoldSeconds: doc says "0.5s Common, up to 2s Mythic"; the steps between are (my pick).
	-- Colours follow docs/04 wrappings (Mythic is a rainbow ribbon; this is its base colour).
	Rarities = {
		Common = { incomePerSecond = 1, sellPrice = 45, carrySlowdown = 0, grabHoldSeconds = 0.5, color = Color3.fromRGB(176, 133, 90) },
		Uncommon = { incomePerSecond = 4, sellPrice = 180, carrySlowdown = 1, grabHoldSeconds = 0.8, color = Color3.fromRGB(70, 185, 90) },
		Rare = { incomePerSecond = 15, sellPrice = 675, carrySlowdown = 2, grabHoldSeconds = 1.1, color = Color3.fromRGB(60, 130, 235) },
		Epic = { incomePerSecond = 60, sellPrice = 2700, carrySlowdown = 3, grabHoldSeconds = 1.4, color = Color3.fromRGB(150, 80, 220) },
		Legendary = { incomePerSecond = 250, sellPrice = 11250, carrySlowdown = 4, grabHoldSeconds = 1.7, color = Color3.fromRGB(245, 190, 40) },
		Mythic = { incomePerSecond = 1000, sellPrice = 45000, carrySlowdown = 5, grabHoldSeconds = 2.0, color = Color3.fromRGB(255, 80, 160) },
	} :: { [Types.Rarity]: Types.RarityDef },

	-- Section 6: mutations, rolled at unwrap, at most one. Chance is a fraction (0.1 = 10%).
	Mutations = {
		{ name = "Golden" :: Types.Mutation, chance = 0.005, incomeMultiplier = 5 },
		{ name = "Glowing" :: Types.Mutation, chance = 0.02, incomeMultiplier = 3 },
		{ name = "Gingerbread" :: Types.Mutation, chance = 0.05, incomeMultiplier = 2 },
		{ name = "Frosted" :: Types.Mutation, chance = 0.10, incomeMultiplier = 1.5 },
	},

	-- Sections 2 + 6: zones. Weights are percent per present, in RarityOrder.
	Zones = {
		[1] = { name = "Wrapping Room", unlockCost = 0, rarityWeights = { 70, 25, 5, 0, 0, 0 } },
		[2] = { name = "Toy Factory", unlockCost = 2500, rarityWeights = { 40, 40, 17, 3, 0, 0 } },
		[3] = { name = "Candy Cane Mine", unlockCost = 25000, rarityWeights = { 0, 35, 40, 20, 5, 0 } },
		[4] = { name = "Reindeer Stables", unlockCost = 250000, rarityWeights = { 0, 0, 40, 40, 18, 2 }, update = 1 },
		[5] = { name = "Santa's Vault", unlockCost = 2500000, rarityWeights = { 0, 0, 0, 50, 40, 10 }, update = 1 },
	},
	LaunchZones = 3,

	-- Section 3: presents and the core loop.
	Presents = {
		RespawnMinSeconds = 20,
		RespawnMaxSeconds = 40,
		DroppedReturnSeconds = 10, -- dropped anywhere but your own drop mat
		CarryCapacity = 1,
		CarryCapacityBigSack = 2,
		UnwrapSeconds = 2,
		GrabDistance = 8, -- (my pick) ProximityPrompt range, studs
		GrabDistanceSlack = 4, -- (my pick) extra studs the server allows for lag before refusing a grab
		DeliveryCheckSeconds = 0.2, -- (my pick) how often the server checks carriers against their drop mat
		DeliveryMatHeight = 8, -- (my pick) studs above the drop mat that still count as standing on it
		ToysShownOnTable = 4, -- (my pick) unplaced toys displayed on the unwrap table (step 2.3 moves them)
	},

	-- Step 2.4 security: a delivery is refused if the present would have had to travel faster than
	-- this from where it was grabbed (straight line, horizontal). Fastest legal player: 16 walk
	-- + 9 (Boots 6) + 4 (Speed Boots pass) = 29. Slack covers lag. Raise MaxTravelSpeed if a new
	-- speed source is added (e.g. a sleigh), or real players will lose deliveries.
	AntiCheat = {
		MaxTravelSpeed = 29,
		TravelSpeedSlack = 1.3,
	},

	-- Section 13: the unwrap reveal popup (placeholder until Phase 5). All (my pick).
	Reveal = {
		PopSeconds = 0.35,
		HoldSeconds = 2.2,
		HideSeconds = 0.2,
		ScalePerTier = 0.08, -- "bigger for higher rarity": Common 1.0, Mythic 1.4
	},

	-- Section 4: guards.
	Guards = {
		PatrolWalkSpeed = 8,
		PatrolPauseSeconds = 1.2, -- (my pick) stands still at each waypoint, like it's looking around
		PatrolStuckSeconds = 2, -- (my pick) no progress for this long = blocked: path around the obstacle
		ChaseMaxSeconds = 8,
		GiveUpAfterLostSightSeconds = 3,
		VisionChecksPerSecond = 5,
		-- visionAngle below is the cone's FULL width (70 = 35 degrees each side of where it faces).
		ChaseTickSeconds = 0.2, -- (my pick) how often a chasing elf re-aims at you
		CatchDistance = 3.5, -- (my pick) studs between elf and player that count as "touching"
		HeyShowSeconds = 1.2, -- (my pick) "HEY!" over its head, then just "!" for the rest of the chase
		CaughtIgnoreSeconds = 5, -- after a catch the elf ignores you this long (covers the stamp moment)
		GiveUpCooldownSeconds = 3, -- (my pick) after a chase ends the elf ignores that player this long,
		-- or the 8 s chase limit means nothing: it would re-spot you the same instant (found in 3.2 testing)
		ConeSlices = 8, -- (my pick) triangles per floor cone; more = smoother edge
		ConeTransparency = 0.6, -- (my pick) 0.72 faded into the pale Zone 1 floor at player height
		ByZone = {
			[1] = { visionRange = 28, visionAngle = 70, chaseSpeed = 13, elvesMin = 1, elvesMax = 2, snowmanCameras = 0, headElves = 0 },
			[2] = { visionRange = 32, visionAngle = 80, chaseSpeed = 14, elvesMin = 3, elvesMax = 3, snowmanCameras = 1, headElves = 0 },
			[3] = { visionRange = 36, visionAngle = 90, chaseSpeed = 15, elvesMin = 3, elvesMax = 3, snowmanCameras = 2, headElves = 1 },
		},
		HeadElf = {
			chaseSpeed = 17,
			inspectSeconds = 5,
			scale = 1.3, -- (my pick) "taller": the whole elf at 1.3x
		},
		SnowmanCamera = {
			sweepDegrees = 90, -- full turn, left edge to right edge
			sweepSeconds = 4, -- one sweep from one edge to the other
			visionRange = 40,
			visionAngle = 50,
			alarmChaseSeconds = 5, -- every elf in the zone chases this long after the bell
			alarmCooldownSeconds = 8, -- (my pick) one snowman rings for the same player at most this often
			bellShowSeconds = 2, -- (my pick) "DING DING!" over the snowman and its cone stays red this long
		},
	},

	-- Section 5: the gift-box disguise.
	Disguise = {
		WrapsPerTrip = 2, -- refilled when you touch your hideout
		MaxSeconds = 6,
		CooldownSeconds = 8,
		InspectSeconds = 3, -- normal elf; Head Elf uses Guards.HeadElf.inspectSeconds
		MoveCancelStuds = 1.2, -- (my pick) drifting further than this from where you wrapped = you moved
		MoveCheckSeconds = 0.1, -- (my pick) how often the server checks that you're still
		BoxScale = 2.2, -- (my pick) disguise box size vs a zone present (2 studs): 4.4 studs hides an avatar
		InspectReachStuds = 4, -- (my pick) a chasing elf stops this close to the box to sniff it
		InspectCreepStuds = 6, -- (my pick) for the last this-many studs it slows to walk speed (no shoving)
		InspectWalkMaxSeconds = 6, -- (my pick) gives up walking to the box after this long (blocked)
		FooledIgnoreSeconds = 5, -- (my pick) a fooled elf leaves you alone this long, so popping out
		-- right after "Just a present" doesn't restart the chase on the spot
		HideoutRefillPadding = 2, -- (my pick) studs around the hideout's box that count as "touching" it
		RequestCooldownSeconds = 0.3, -- (my pick) rate limit on RequestDisguise
		HuhShowSeconds = 2.5, -- (my pick) "...Huh. Just a present." stays this long
	},

	-- Section 6: shelves and offline income.
	Shelves = {
		Start = 4,
		Max = 20,
		CostBase = 500, -- cost = CostBase * CostGrowth ^ (shelves bought)
		CostGrowth = 1.8,
		IncomeTickSeconds = 1, -- shelved toys pay every this many seconds
		PromptDistance = 8, -- (my pick) "Put on shelf" / "Sell" prompt range, studs
		PromptDistanceSlack = 4, -- (my pick) extra studs the server allows for lag
		PlaceHoldSeconds = 0.3, -- (my pick)
		SellHoldSeconds = 0.6, -- (my pick) a little longer, so nobody sells by accident
		InactiveTransparency = 0.75, -- (my pick) how see-through a not-yet-bought shelf slot looks
	},
	-- Town Square dealer: buys every toy waiting on your unwrap table (not shelved ones).
	BlackMarket = {
		PromptDistance = 14, -- (my pick) the stall is big, so the prompt reaches further
		HoldSeconds = 0.5, -- (my pick)
	},
	Offline = {
		MaxHours = 2,
		MaxHoursVip = 4,
	},

	-- Section 7: upgrades and gadgets.
	Upgrades = {
		Boots = { speedPerLevel = 1.5, costs = { 300, 900, 2700, 8000, 24000, 72000 } },
		ExtraWrap = { wrapsByLevel = { 3, 4 }, costs = { 1500, 15000 } },
		QuietSteps = { visionReductionPerLevel = 0.10, costs = { 2000, 12000, 60000 } },
		Snowball = { cost = 5000, elfStunSeconds = 3, cooldownSeconds = 8 },
	},

	-- Section 8: Naughty Jail.
	Jail = {
		WaitSeconds = 20,
		CoalToEscape = 8,
		StampSeconds = 1.5, -- (my pick) the "NAUGHTY!" stamp plays this long, then you're in the cell
		MineHoldSeconds = 0.5, -- (my pick) hold time on a coal rock's "Mine" prompt
		MinePromptDistance = 8, -- (my pick) studs
		MinePromptDistanceSlack = 4, -- (my pick) extra studs the server allows for lag
	},

	-- Section 9: social and events.
	SleighRaid = {
		IntervalSeconds = 12 * 60,
		WarningSeconds = 10,
		DurationSeconds = 60,
		Presents = 6, -- Rare or better
		MinRarity = "Rare" :: Types.Rarity,
		Elves = 3,
	},
	MostWanted = {
		BountyFraction = 0.10, -- paid by the game, never taken from the target
	},

	-- Section 6: Collection Index.
	Index = {
		ZoneCompleteIncomeBonus = 0.05,
		DiscoveryBonusSeconds = 60, -- (my pick) first find pays 60 s of that toy's shelf income
	},

	-- Section 10: Robux. Prices are display/reference only; IDs are added in Phase 6.
	GamePasses = {
		Vip = { price = 199, coinMultiplier = 2 },
		BigSack = { price = 299 },
		SpeedBoots = { price = 149, extraWalkSpeed = 4 },
		WrapMaster = { price = 99, extraWraps = 2, cooldownReductionSeconds = 4 },
	},
	DevProducts = {
		BailOut = { price = 15 },
		LuckyWrap = { price = 39 }, -- paid random item: show odds, check PolicyService
		Blizzard = { price = 99, durationSeconds = 60, elfVisionMultiplier = 0.5 },
		CoinPackSmall = { price = 25 },
		CoinPackMedium = { price = 99 },
		CoinPackLarge = { price = 299 },
		AdventCatchUp = { price = 19 },
	},

	-- Section 11: reasons to come back.
	Advent = {
		LastDay = 25, -- day 25 = guaranteed Mythic; doors open by real UTC date
		Month = 12,
	},
	LoginStreakDays = 7,
	DailyQuestCount = 3,
}

return deepFreeze(Config)

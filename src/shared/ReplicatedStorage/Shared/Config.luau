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

	-- Section 4: guards.
	Guards = {
		PatrolWalkSpeed = 8,
		ChaseMaxSeconds = 8,
		GiveUpAfterLostSightSeconds = 3,
		VisionChecksPerSecond = 5,
		ByZone = {
			[1] = { visionRange = 28, visionAngle = 70, chaseSpeed = 13, elvesMin = 1, elvesMax = 2, snowmanCameras = 0, headElves = 0 },
			[2] = { visionRange = 32, visionAngle = 80, chaseSpeed = 14, elvesMin = 3, elvesMax = 3, snowmanCameras = 1, headElves = 0 },
			[3] = { visionRange = 36, visionAngle = 90, chaseSpeed = 15, elvesMin = 3, elvesMax = 3, snowmanCameras = 2, headElves = 1 },
		},
		HeadElf = { chaseSpeed = 17, inspectSeconds = 5 },
		SnowmanCamera = { sweepDegrees = 90, sweepSeconds = 4, visionRange = 40, visionAngle = 50, alarmChaseSeconds = 5 },
	},

	-- Section 5: the gift-box disguise.
	Disguise = {
		WrapsPerTrip = 2, -- refilled when you touch your hideout
		MaxSeconds = 6,
		CooldownSeconds = 8,
		InspectSeconds = 3, -- normal elf; Head Elf uses Guards.HeadElf.inspectSeconds
	},

	-- Section 6: shelves and offline income.
	Shelves = {
		Start = 4,
		Max = 20,
		CostBase = 500, -- cost = CostBase * CostGrowth ^ (shelves bought)
		CostGrowth = 1.8,
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

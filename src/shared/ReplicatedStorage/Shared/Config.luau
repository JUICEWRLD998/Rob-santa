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
	-- ribbonColor (my pick, step 4.3): ribbon and bow on the present, picked to stand out on each paper.
	Rarities = {
		Common = { incomePerSecond = 1, sellPrice = 45, carrySlowdown = 0, grabHoldSeconds = 0.5, color = Color3.fromRGB(176, 133, 90), ribbonColor = Color3.fromRGB(230, 215, 180) },
		Uncommon = { incomePerSecond = 4, sellPrice = 180, carrySlowdown = 1, grabHoldSeconds = 0.8, color = Color3.fromRGB(70, 185, 90), ribbonColor = Color3.fromRGB(205, 35, 45) },
		Rare = { incomePerSecond = 15, sellPrice = 675, carrySlowdown = 2, grabHoldSeconds = 1.1, color = Color3.fromRGB(60, 130, 235), ribbonColor = Color3.fromRGB(240, 244, 255) },
		Epic = { incomePerSecond = 60, sellPrice = 2700, carrySlowdown = 3, grabHoldSeconds = 1.4, color = Color3.fromRGB(150, 80, 220), ribbonColor = Color3.fromRGB(250, 205, 70) },
		Legendary = { incomePerSecond = 250, sellPrice = 11250, carrySlowdown = 4, grabHoldSeconds = 1.7, color = Color3.fromRGB(245, 190, 40), ribbonColor = Color3.fromRGB(190, 25, 40) },
		Mythic = { incomePerSecond = 1000, sellPrice = 45000, carrySlowdown = 5, grabHoldSeconds = 2.0, color = Color3.fromRGB(255, 80, 160), ribbonColor = Color3.fromRGB(255, 255, 255) },
	} :: { [Types.Rarity]: Types.RarityDef },

	-- Step 5.4: present wrapping per rarity (docs/04 section 4). Paper colour = Rarities[r].color,
	-- ribbon colour = Rarities[r].ribbonColor; this adds the materials and the extras.
	-- sparkles = particles per second off the box (0 = none). rainbowRibbon: the ribbon cycles
	-- through the rainbow every rainbowSeconds (each client animates it, the server doesn't).
	Wrapping = {
		Common = { paper = Enum.Material.Cardboard, ribbon = Enum.Material.Fabric, reflectance = 0, sparkles = 0 }, -- brown kraft paper, twine
		Uncommon = { paper = Enum.Material.Fabric, ribbon = Enum.Material.SmoothPlastic, reflectance = 0, sparkles = 0 },
		Rare = { paper = Enum.Material.SmoothPlastic, ribbon = Enum.Material.SmoothPlastic, reflectance = 0.05, sparkles = 0 },
		Epic = { paper = Enum.Material.Foil, ribbon = Enum.Material.SmoothPlastic, reflectance = 0.1, sparkles = 0 },
		Legendary = { paper = Enum.Material.Foil, ribbon = Enum.Material.SmoothPlastic, reflectance = 0.2, sparkles = 2 },
		Mythic = { paper = Enum.Material.Foil, ribbon = Enum.Material.Neon, reflectance = 0.15, sparkles = 4, rainbowRibbon = true },
		RainbowSeconds = 3, -- (my pick) one full trip round the colour wheel
	},

	-- Section 6: mutations, rolled at unwrap, at most one. Chance is a fraction (0.1 = 10%).
	-- color (my pick, step 4.3): the mutation stamp on the reveal card. Toy looks: Lib/ToyModel.
	Mutations = {
		{ name = "Golden" :: Types.Mutation, chance = 0.005, incomeMultiplier = 5, color = Color3.fromRGB(255, 205, 70) },
		{ name = "Glowing" :: Types.Mutation, chance = 0.02, incomeMultiplier = 3, color = Color3.fromRGB(120, 255, 200) },
		{ name = "Gingerbread" :: Types.Mutation, chance = 0.05, incomeMultiplier = 2, color = Color3.fromRGB(215, 140, 75) },
		{ name = "Frosted" :: Types.Mutation, chance = 0.10, incomeMultiplier = 1.5, color = Color3.fromRGB(150, 215, 255) },
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
		-- Step 5.5 celebration, bigger with rarity (tier 1 = Common ... 6 = Mythic). All my picks.
		CardScalePerTier = 0.03, -- the name card grows less than the toy (ScalePerTier), so it never covers it
		CardFitHeight = 460, -- screens shorter than this many pixels shrink the card to fit ...
		CardMinFit = 0.72, -- ... but never below this
		HoldPerTier = 0.35, -- extra seconds on screen per tier above Common
		BurstTransparency = { 0.82, 0.74, 0.64, 0.52, 0.42, 0.32 }, -- rarity colour over the screen, by tier
		ConfettiPerTier = 10, -- pieces of confetti per tier (Mythic: 60)
		RaysFromTier = 3, -- light rays spin behind the toy from Rare up
		RaysDegreesPerSecond = 40,
		FlashFromTier = 5, -- a white flash from Legendary up
		SpinSeconds = 2.4, -- one full turn of the toy
		StampDelay = 0.45, -- the mutation stamp slams in this long after the pop
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

	-- Step 5.3: generated R15 animations (Studio MCP generate_animation), published under the game's
	-- owner. An animation owned by anyone else plays in Studio but NOT in the live game.
	-- speed = playback speed; seconds = how long it plays before it is stopped (the generated clips
	-- run 3 to 9 s, longer than these moments).
	Animations = {
		ElfLookAround = { id = "rbxassetid://116136038909543", speed = 1, seconds = 2.6 },
		ElfSniff = { id = "rbxassetid://117688415760927", speed = 1, seconds = 0 }, -- loops for the whole sniff
		ElfShrug = { id = "rbxassetid://115282132021549", speed = 1.4, seconds = 1.8 },
		ElfGrab = { id = "rbxassetid://115427447723879", speed = 1.3, seconds = 1.6 },
		PlayerMine = { id = "rbxassetid://90781438526960", speed = 1.3, seconds = 1.2 },
		NpcIdle = { id = "rbxassetid://507766388" }, -- Roblox's own R15 idle (plays in any game)
		LookAroundChance = 0.5, -- (my pick) share of waypoint stops where the elf looks around
	},

	-- Testing switches. They only work inside Roblox Studio (RunService:IsStudio()); a published
	-- game ignores them completely.
	Debug = {
		-- true = Zone 2/3 barriers open for everyone in Studio playtests, as if every zone were
		-- owned (quick zone testing). false since 4.2, so buying a zone can be tested.
		OpenZonesInStudio = false,
		-- ServerStorage/DebugData (a BindableFunction) lets Claude's Studio tests read a player's
		-- save and set a field in it. Server-only: players can never reach ServerStorage.
		DataHookInStudio = true,
		-- ServerStorage/DebugMonetization (BindableFunction, step 6.2): Claude's Studio tests can
		-- give a pass or run a fake receipt through the real purchase code. Studio only.
		MonetizationHookInStudio = true,
		-- ServerStorage/DebugDaily (BindableFunction, step 6.3): Claude's Studio tests can pretend
		-- it is another UTC date (to open December doors in November) and re-check the day. Studio only.
		DailyHookInStudio = true,
		-- ServerStorage/DebugRaid (BindableFunction, step 6.4): "start" begins the 10 s warning now,
		-- "end" ends a running raid. Studio only.
		RaidHookInStudio = true,
		-- ServerStorage/DebugTutorial (BindableFunction, step 6.5): "restart" runs the tutorial again
		-- for a player, "skip" ends it, "state" reads the step. Studio only.
		TutorialHookInStudio = true,
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

	-- Step 4.2: the Gadget Shop. Prices are in Upgrades, Shelves and Zones.
	Shop = {
		RequestCooldownSeconds = 0.25, -- (my pick) rate limit on RequestPurchase; a double tap buys once
		PromptDistance = 14, -- (my pick) the shop counter is big, like the Black Market stall
	},

	-- Section 7: upgrades and gadgets.
	Upgrades = {
		Boots = { speedPerLevel = 1.5, costs = { 300, 900, 2700, 8000, 24000, 72000 } },
		ExtraWrap = { wrapsByLevel = { 3, 4 }, costs = { 1500, 15000 } },
		QuietSteps = { visionReductionPerLevel = 0.10, costs = { 2000, 12000, 60000 } },
		Snowball = {
			cost = 5000,
			elfStunSeconds = 3,
			cooldownSeconds = 8,
			-- Step 6.4 (all my picks). You aim with the camera; the server picks the target: the
			-- nearest elf, or player carrying a present, within range and inside the aim cone, with a
			-- clear line. No target = a throw into the snow (it still uses the cooldown).
			rangeStuds = 45,
			aimAngle = 50, -- FULL cone width in degrees around where the camera looks
			flightStudsPerSecond = 70, -- the hit lands after distance / this
			rangeSlackStuds = 6, -- extra studs allowed when the hit lands (the target kept moving)
		},
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
		IntervalSeconds = 12 * 60, -- from one landing to the next
		FirstRaidSeconds = 12 * 60, -- (my pick) after the server starts
		WarningSeconds = 10,
		DurationSeconds = 60,
		Presents = 6, -- Rare or better
		-- (my pick) percent per raid present, in RarityOrder (Common, Uncommon, Rare, Epic, Legendary, Mythic).
		RarityWeights = { 0, 0, 55, 30, 12, 3 },
		Elves = 3,
		-- (my pick) raid elves: like a Zone 2 elf. They guard the Town Square only (its SafeZone box).
		Elf = { visionRange = 30, visionAngle = 80, chaseSpeed = 14 },
		PresentRingStuds = 12, -- (my pick) presents stand in a ring this far from the pad's centre
		-- (my pick) raid elves walk an oval round the pad, this far out sideways (X) and front-to-back (Z);
		-- the Town tree stands 22 studs south of the pad centre, so Z stays short of it.
		ElfRouteStuds = { x = 24, z = 15 },
		ElfRoutePoints = 8,
		DescendSeconds = 3, -- (my pick) the sleigh flies down onto the pad during the warning's last seconds
		FlyHeightStuds = 70, -- (my pick) where it flies in from and leaves to
	},
	MostWanted = {
		BountyFraction = 0.10, -- of the target's coins, paid by the game, never taken from the target
		-- (my pick) one hunter earns a bounty on the same Most Wanted player at most this often, so
		-- two friends can't farm bounties off each other.
		BountyCooldownSeconds = 5 * 60,
		RefreshSeconds = 3, -- (my pick) how often the richest player is re-checked
		MinPlayersForOutline = 2, -- (my pick) alone in a server, nobody is hunting you: no red outline
		OutlineColor = Color3.fromRGB(255, 50, 50),
	},

	-- Section 14 (step 6.5): the first 3 minutes, for brand-new players only. All (my pick) unless noted.
	Tutorial = {
		FirstPresentRarity = "Rare" :: Types.Rarity, -- section 14: "guaranteed Rare"
		SpotDelaySeconds = 2, -- after the first grab, one Zone 1 elf spots you on purpose
		ElfChaseSpeed = 9, -- that elf is slow (a Zone 1 elf runs 13) and can't catch you
		ElfChaseSeconds = 15, -- it follows this long at most, giving you time to wrap
		LostPresentSeconds = 5, -- carrying nothing this long (dropped it, reset) = back to "grab a present"
		EarnShowSeconds = 4, -- "Your toy earns coins every second!" stays this long
		DoneShowSeconds = 6, -- the closing line stays this long
		CheckSeconds = 0.5, -- how often the server re-checks the player's step
		-- Coins handed over after the first shelf, to buy Boots level 1 (= Upgrades.Boots.costs[1]).
		GiftCoins = 300,
		-- Client: the footprint trail.
		TrailRefreshSeconds = 1.2, -- path re-computed this often
		FootprintSpacing = 2.2, -- studs between prints
		FootprintCount = 16, -- prints drawn ahead of you
	},

	-- docs/04 section 5 (step 5.1): light snowfall, drawn on each client above its own camera.
	-- All (my pick). Rate is flakes per second; keep it low for phones.
	Snow = {
		Rate = 70,
		AreaStuds = 90, -- width and depth of the snowing area around the camera
		HeightAboveCamera = 30,
		FallSpeed = { min = 5, max = 8 }, -- studs per second
		FlakeSize = { min = 0.15, max = 0.3 },
		LifetimeSeconds = 7,
		OffBelowY = -20, -- no snow underground (Naughty Jail sits at y -60)
	},

	-- docs/04 section 6 (step 5.6). The sounds themselves are in SoundService/Sfx and
	-- SoundService/Music (place file; each has a Source attribute naming its library track).
	-- Volumes there are the base volumes. Everything below is my pick.
	Audio = {
		MusicFadeSeconds = 1.5, -- crossfade between the Town, Explore and Chase music
		ChaseLingerSeconds = 1.5, -- the chase music stays this long after the last elf gives up
		MusicCheckSeconds = 0.5, -- how often the client checks where you are for the music
		SniffEverySeconds = 1.6, -- a sniff sound this often while an elf inspects you
		CoinsMinIncomeSeconds = 3, -- clink only when coins jump by more than this many seconds of
		-- income, so the passive income tick each second stays quiet
		CoinsCooldownSeconds = 0.4,
		-- Unwrap fanfare per rarity tier (Common ... Mythic) and its volume: bigger per rarity.
		FanfareByTier = { "Chime", "Chime", "FanfareRare", "FanfareRare", "FanfareLegendary", "FanfareLegendary" },
		FanfareVolumeByTier = { 0.35, 0.5, 0.4, 0.55, 0.55, 0.8 },
		FanfareSeconds = 3.5, -- long fanfares fade out after this
	},

	-- Section 6: Collection Index.
	Index = {
		ZoneCompleteIncomeBonus = 0.05, -- per completed page, added together (2 pages = +10%)
		DiscoveryBonusSeconds = 60, -- (my pick) first find pays 60 s of that toy's shelf income
		-- (my pick, step 4.4) A zone's page holds the toys of the rarities that first drop in
		-- that zone (section 6 table). Mythic first drops in Zone 4 (Update 1); at launch it
		-- comes only from Lucky Wrap and the Sleigh Raid.
		Pages = {
			{ zone = 1, rarities = { "Common", "Uncommon", "Rare" } :: { Types.Rarity } },
			{ zone = 2, rarities = { "Epic" } :: { Types.Rarity } },
			{ zone = 3, rarities = { "Legendary" } :: { Types.Rarity } },
			{ zone = 4, rarities = { "Mythic" } :: { Types.Rarity } },
		},
		-- (my pick) false: a page is complete when every toy on it is found in ANY form.
		-- true: every toy in every mutation (80 entries; Golden is 0.5%, so very slow).
		PageNeedsAllMutations = false,
	},

	-- Section 10: Robux (step 6.2). `id` = the pass / product ID from Creator Hub (created by the
	-- owner in 6.1; 0 = not created yet, so it is not sold). `price` is only a fallback for the store
	-- screen: the real price is whatever Creator Hub says, read live (GetProductInfoAsync).
	-- Changing a price happens in Creator Hub, never here.
	GamePasses = {
		Vip = { id = 2096410164, price = 199, coinMultiplier = 2 }, -- also the 4 h offline cap (Offline.MaxHoursVip)
		BigSack = { id = 2093346188, price = 299 }, -- carry Presents.CarryCapacityBigSack
		SpeedBoots = { id = 2093820219, price = 149, extraWalkSpeed = 4 },
		WrapMaster = { id = 2092740170, price = 99, extraWraps = 2, cooldownReductionSeconds = 4 },
	},
	DevProducts = {
		BailOut = { id = 3734661198, price = 15 },
		LuckyWrap = { id = 3734661911, price = 39 }, -- paid random item: odds on screen, PolicyService check
		Blizzard = {
			id = 3734662463,
			price = 99,
			durationSeconds = 60, -- buying again while one runs adds another 60 s
			elfVisionMultiplier = 0.5,
			elfSpeedMultiplier = 0.75, -- (my pick) "slowed": chase 13-17 becomes about 10-13
			snowMultiplier = 5, -- (my pick) snowflakes per second on every screen, x this
		},
		-- Coin packs grow with the player (my pick, so a pack is still worth buying late in the
		-- game): incomeSeconds of the buyer's current income per second, but never less than
		-- minCoins. Bigger packs give more per Robux.
		CoinPackSmall = { id = 3734662915, price = 25, incomeSeconds = 5 * 60, minCoins = 1000 },
		CoinPackMedium = { id = 3734663330, price = 99, incomeSeconds = 25 * 60, minCoins = 5000 },
		CoinPackLarge = { id = 3734663722, price = 299, incomeSeconds = 90 * 60, minCoins = 20000 },
		AdventCatchUp = { id = 3734667673, price = 19 }, -- opens one missed Advent door (DailyService, 6.3)
	},
	Store = {
		PassCheckRetries = 3, -- (my pick) UserOwnsGamePassAsync attempts per pass on join
		PassesWaitSeconds = 10, -- (my pick) offline earnings wait this long for the VIP check
		ReceiptSaveWaitSeconds = 30, -- (my pick) a purchase is confirmed only once it is saved
		RequestCooldownSeconds = 0.5, -- (my pick) rate limit on RequestBailOut
		VipTagColor = Color3.fromRGB(255, 205, 60),
	},

	-- Section 11: reasons to come back (step 6.3). DailyService runs all three; every date is UTC.
	-- Coin rewards grow with the player (my pick, like the coin packs): `minutes` of their current
	-- shelf income, but never less than `min`, rounded to 2 significant figures.
	Advent = {
		LastDay = 25, -- doors 1-25 of December; door N opens free on December N
		-- (my pick) after Christmas, missed doors can still be caught up until January 6, then the
		-- calendar closes until next December (a new December starts a fresh calendar).
		CatchUpUntilJanuaryDay = 6,
		CatchUpCoal = 10, -- (my pick) one missed door for coal; a jail visit gives up to Jail.CoalToEscape
		-- (my pick) odd days coins, even days a toy of rising rarity, day 25 a guaranteed Mythic.
		-- A toy goes on the unwrap table with the full reveal (no mutation roll).
		Rewards = {
			{ coinMinutes = 3, minCoins = 300 }, -- 1
			{ rarity = "Uncommon" },
			{ coinMinutes = 4, minCoins = 400 },
			{ rarity = "Uncommon" },
			{ coinMinutes = 5, minCoins = 500 }, -- 5
			{ rarity = "Uncommon" },
			{ coinMinutes = 6, minCoins = 700 },
			{ rarity = "Uncommon" },
			{ coinMinutes = 7, minCoins = 900 },
			{ rarity = "Rare" }, -- 10
			{ coinMinutes = 8, minCoins = 1100 },
			{ rarity = "Rare" },
			{ coinMinutes = 9, minCoins = 1300 },
			{ rarity = "Rare" },
			{ coinMinutes = 10, minCoins = 1600 }, -- 15
			{ rarity = "Rare" },
			{ coinMinutes = 11, minCoins = 1900 },
			{ rarity = "Epic" },
			{ coinMinutes = 12, minCoins = 2200 },
			{ rarity = "Epic" }, -- 20
			{ coinMinutes = 13, minCoins = 2600 },
			{ rarity = "Epic" },
			{ coinMinutes = 15, minCoins = 3000 },
			{ rarity = "Legendary" },
			{ rarity = "Mythic" }, -- 25: Christmas Day
		} :: { { coinMinutes: number?, minCoins: number?, rarity: Types.Rarity? } },
		PromptDistance = 12, -- the "Advent Calendar" prompt on the Town board
		RequestCooldownSeconds = 0.4, -- (my pick) rate limit on RequestAdventDoor
	},
	-- Daily login streak: paid once per UTC day, on join or at midnight while playing. Day 8 onward
	-- keeps paying the day-7 reward (my pick); missing a day starts again at day 1.
	LoginStreak = {
		Rewards = {
			{ coinMinutes = 2, minCoins = 200 },
			{ coinMinutes = 3, minCoins = 300 },
			{ coinMinutes = 4, minCoins = 500 },
			{ coinMinutes = 5, minCoins = 800 },
			{ coinMinutes = 7, minCoins = 1200 },
			{ coinMinutes = 10, minCoins = 1800 },
			{ coinMinutes = 15, minCoins = 3000 },
		},
	},
	-- Daily quests: Count picked per player per UTC day from Pool (the same 3 all day). Paid the
	-- moment the goal is reached. `event` names a server GameEvents event (Lib/GameEvents.luau).
	Quests = {
		Count = 3,
		Pool = {
			{ id = "Steal", text = "Steal %d presents", goal = 10, event = "PresentGrabbed", coinMinutes = 5, minCoins = 500 },
			{ id = "Fool", text = "Survive %d elf inspections", goal = 2, event = "InspectionSurvived", coinMinutes = 6, minCoins = 600 },
			{ id = "MineOut", text = "Escape jail by mining", goal = 1, event = "MinedOut", coinMinutes = 4, minCoins = 400 },
			{ id = "Unwrap", text = "Unwrap %d presents", goal = 5, event = "PresentUnwrapped", coinMinutes = 5, minCoins = 500 },
			{ id = "Sell", text = "Sell %d toys", goal = 3, event = "ToySold", coinMinutes = 3, minCoins = 300 },
		},
		CheckSeconds = 30, -- how often a new UTC day is noticed for players already in the game
	},
}

return deepFreeze(Config)

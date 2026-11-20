--!strict
-- Shared type definitions. Server and client both require this, so it holds types only, no logic.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type Mutation = "Frosted" | "Gingerbread" | "Glowing" | "Golden"

export type ToyDef = {
	id: string, -- stable save key: never rename once players own it
	name: string, -- display name, safe to change
	rarity: Rarity,
}

export type RarityDef = {
	incomePerSecond: number,
	sellPrice: number,
	carrySlowdown: number, -- subtracted from walk speed while carried
	grabHoldSeconds: number, -- ProximityPrompt hold time
	color: Color3,
}

-- One owned toy. `uid` tells apart two copies of the same toy.
export type OwnedToy = {
	uid: string,
	toyId: string,
	mutation: Mutation?,
}

-- Sent server -> client on UnwrapReveal.
export type UnwrapResult = {
	toyId: string,
	rarity: Rarity,
	mutation: Mutation?,
}

-- Sent server -> client on JailUpdate.
--   Caught: play the "NAUGHTY!" stamp. Jailed: show the panel (endsAt is server time, from
--   workspace:GetServerTimeNow()). Free: hide everything.
-- Sent server -> client on DisguiseUpdate (3.4).
--   Wrapped: you're a box until `endsAt`.  Inspected: an elf is sniffing you, don't move.
--   Fooled: the elf gave up ("Just a present").  Gotcha: you moved while sniffed.
--   Ended: you're yourself again; the next disguise is ready at `readyAt`.
export type DisguiseState = "Wrapped" | "Inspected" | "Fooled" | "Gotcha" | "Ended"
export type DisguiseUpdate = {
	state: DisguiseState,
	endsAt: number?, -- server time
	readyAt: number?, -- server time
}

export type JailState = "Caught" | "Jailed" | "Free"
export type JailUpdate = {
	state: JailState,
	endsAt: number?,
	coal: number?, -- mined this visit
	coalNeeded: number?,
	mined: { number }?, -- CoalRock Index values already mined this visit (their prompts hide)
}

-- The contract every server Service and client Controller module follows.
-- Init runs for all modules first (set up state, no yielding); Start runs after (may yield).
export type Module = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

return nil

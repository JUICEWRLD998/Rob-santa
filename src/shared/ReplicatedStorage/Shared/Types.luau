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

-- The contract every server Service and client Controller module follows.
-- Init runs for all modules first (set up state, no yielding); Start runs after (may yield).
export type Module = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
}

return nil

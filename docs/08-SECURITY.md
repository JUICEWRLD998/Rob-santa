# 08 — Security review

Every way a player's client can reach the server, what an exploiter could send, and what the server
checks. First written at step 2.4 (2026-11-20). Re-run it at step 7.2 and whenever a remote or
prompt is added.

An exploiter controls their own client completely: they can fire any RemoteEvent with any
arguments, trigger any ProximityPrompt (skipping the hold time), and move or teleport their own
character. They cannot change anything on the server directly.

## Client → server inputs (step 2.4)

| # | Input | What an exploiter could send | Server checks | Verdict |
|---|---|---|---|---|
| 1 | **Steal** prompt on a present (`PresentService` tryGrab) | Trigger it from far away, spam it, trigger a present someone else is carrying, trigger it while already carrying | Present must still be `Resting`; player alive; within `GrabDistance + GrabDistanceSlack` (12 studs) of the present; hands not full (`CarryCapacity`). Each grab changes the present's state at once, so spam gets nothing extra | OK |
| 2 | **Delivery** (standing on a drop mat; no remote, the server polls) | Stand on someone else's mat; teleport from the zone straight onto their own mat | Only the player's OWN mat counts (`PlotService` index). **New in 2.4:** refused if the present would have had to travel faster than `AntiCheat.MaxTravelSpeed × TravelSpeedSlack` (29 × 1.3 studs/s) in a straight line from where it was grabbed; the present goes back to its zone and the server logs a warning | Fixed in 2.4 |
| 3 | **Put on shelf** prompt on a table toy (`ShelfService` placeOnShelf) | Trigger another player's toy; trigger after the toy has moved; spam | The prompt's handler is bound to one owner and one toy; the server ignores anyone else (`who == player`), checks the toy is still on that player's table, and checks distance. The client also hides other players' prompts (`OwnerOnly` tag) | OK |
| 4 | **Sell** prompt on a shelved toy (`ShelfService` sellShelved) | Sell someone else's toy; sell the same toy twice; sell from across the map | Owner only; the toy must still be in that exact shelf slot (a second trigger finds it gone and pays nothing); distance check. The price comes from `ToyMath` on the server, never from the client | OK |
| 5 | **Black Market** prompt (`ShelfService` sellAllWaiting) | Spam it; trigger it from anywhere | Distance check (`BlackMarket.PromptDistance` + slack). It only sells the player's own table toys, which it empties before paying, so spam pays once | OK |
| 7 | **Mine** prompt on a coal rock (`JailService` tryMine, step 3.3) | Mine while not in jail; mine the same rock twice; mine from across the room; spam to escape instantly | Player must be jailed and past the stamp (in the cell); each rock counts once per visit (server-side `mined` set); distance check (`MinePromptDistance` + slack). Escape needs `CoalToEscape` different rocks. The client only hides prompts; it decides nothing | OK |
| 8 | **Getting caught** (no remote: `GuardService` decides) | Reset the character to leave jail | A new character of a jailed player is put back in the cell (tested 3.3) | OK |
| 9 | **`RequestPurchase`** remote (`ShopService`, step 4.2) | Send a price; send a table, a number or an unknown id; buy level 7 Boots; buy Zone 3 without Zone 2; double-tap to buy twice; buy with no coins | Only an item id is read, through `ShopCatalog.get` (anything else is ignored). The level comes from the save and the price from `ShopCatalog.cost` on the server; maxed items, missing prerequisites and missing coins are refused; `TrySpend` checks and spends with no yield; rate limit `Shop.RequestCooldownSeconds` (0.25 s). Tested 4.2: junk ids ignored, two fires in one frame bought once, Zone 3 refused before Zone 2, refusal when 200 coins short | OK |
| 10 | **Zone barriers** (`ZoneController`, client) and grabs in a zone (`PresentService` tryGrab) | Walk or teleport through a barrier into a zone they don't own and steal there | The barrier opens only on the owner's own client. Grabs ask `ZoneService:OwnsZone` (the save), so loot in an unowned zone can't be taken. Tested 4.2: Zone 3 grab refused without Zone 3 in the save, allowed with it | Fixed in 4.2 |
| 6 | RemoteEvents `RequestDisguise`, `RequestSnowball`, `RequestPurchase` | Fire them with anything | **Removed in 2.4.** They had no handler, but anyone could still fire them and the server queued the events. Rule now in `Remotes.luau`: add a client-to-server remote only together with its validated handler | Fixed in 2.4 |

Server → client remotes (`UnwrapReveal`, `Notify`, `JailUpdate`, `ShopResult`) carry no authority. The client
type-checks their payloads so a bad one cannot break the UI.

Coins: only `EconomyService` changes them. `AddCoins` and `TrySpend` reject non-whole, negative,
NaN and infinite amounts, and `TrySpend` checks and spends with no yield in between.

## Known gaps (deliberately later)

| Gap | Why it is OK for now | When |
|---|---|---|
| Speed hacks (client sets its own WalkSpeed) | The delivery travel check caps what speed can earn. Elves (Phase 3) make speed matter more | Server-side movement check in 7.2 |
| Prompt hold time skipped (instant grab) | The hold is a feel thing; all the real checks above still run | Revisit in 7.2 if it matters |
| Walking through zone barriers into Zones 2–3 without buying them | Fixed in 4.2 (row 10): they can walk in, but can't take anything | Done |
| Grabbing through a thin wall (prompt line of sight is checked on the client only) | Distance is still capped at 12 studs | 7.2 |
| Hideout raids (stealing from other players' shelves) | Not in the launch build | Update 1 |

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
| 6 | RemoteEvents `RequestDisguise`, `RequestSnowball`, `RequestPurchase` | Fire them with anything | **Removed in 2.4.** They had no handler, but anyone could still fire them and the server queued the events. Rule now in `Remotes.luau`: add a client-to-server remote only together with its validated handler | Fixed in 2.4 |

Server → client remotes (`UnwrapReveal`, `Notify`, `JailUpdate`) carry no authority. The client
type-checks their payloads so a bad one cannot break the UI.

Coins: only `EconomyService` changes them. `AddCoins` and `TrySpend` reject non-whole, negative,
NaN and infinite amounts, and `TrySpend` checks and spends with no yield in between.

## Known gaps (deliberately later)

| Gap | Why it is OK for now | When |
|---|---|---|
| Speed hacks (client sets its own WalkSpeed) | The delivery travel check caps what speed can earn. Elves (Phase 3) make speed matter more | Server-side movement check in 7.2 |
| Prompt hold time skipped (instant grab) | The hold is a feel thing; all the real checks above still run | Revisit in 7.2 if it matters |
| Walking through zone barriers into Zones 2–3 without buying them | Zone ownership does not exist yet | 4.2 must also check ownership on every grab (`PresentService` tryGrab), not only hide the barrier |
| Grabbing through a thin wall (prompt line of sight is checked on the client only) | Distance is still capped at 12 studs | 7.2 |
| Hideout raids (stealing from other players' shelves) | Not in the launch build | Update 1 |

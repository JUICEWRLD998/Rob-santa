# Rob Santa! — rules for Claude in this project

A Roblox game (Luau), built by vibecoding. The owner is **new to Roblox development**. He directs, plays and judges. You build, test and explain.

## Read first
- `README.md` — progress list (which phase we're on) and key dates.
- `docs/01-GAME-DESIGN.md` — the source of truth for every rule and number. If a request conflicts with it, say so and ask which wins. When a design decision changes, update this doc in the same change.
- `docs/05-BUILD-PLAN.md` — the current phase and step. Do only that step.
- `docs/04-CHARACTERS-AND-ART.md` — for any visual, character, animation or sound work.

## Talking to the owner
- Plain words, short. After each change: what you built (2–4 lines), which files changed, **how he can test it in Studio** (exact clicks).
- No jargon without a one-line explanation. Never paste large code blocks into chat unless asked; the code is in the files.
- He can't judge code quality yet, so be honest: if something is a temporary hack, say so.

## Tools
- **Roblox Studio MCP** (built into Studio). Use it to build/edit the world (`execute_luau` with datamodel_type Edit), inspect the tree, generate avatars/meshes/materials/animations, search/insert assets, playtest (`start_stop_play`, `get_console_output`, `screen_capture`, character/keyboard input), and `save_place` after world edits. If the MCP is not connected, stop and tell him to check Studio → Assistant → … → Manage MCP Servers (see docs/02-SETUP.md step 5).
- **Script Sync** mirrors scripts between Studio and `src/`. Write scripts as files in `src/`, never by creating Script instances through `execute_luau` (they wouldn't exist on disk or in git).

| Disk | Studio |
|---|---|
| Disk (verified 2026-11-19, both directions) | Studio |
|---|---|
| `src/server/ServerScriptService/Server/` | `ServerScriptService/Server` |
| `src/client/Client/` | `StarterPlayer/StarterPlayerScripts/Client` |
| `src/shared/ReplicatedStorage/Shared/` | `ReplicatedStorage/Shared` |

Script Sync nests the service name inside the linked folder (server, shared), but not for the client. A file placed at the top of `src/server/`, `src/client/` or `src/shared/` is NOT picked up. Always write to the full paths in the table. Studio's `Instance.new("Script")` syncs to disk as `X.legacy.luau`; a `X.server.luau` file arrives in Studio as a Script with RunContext Server.

File names: `X.luau` = ModuleScript, `X.server.luau` = Script, `X.local.luau` = LocalScript, folder = Folder.
Script Sync caveats: never put attributes or tags on scripts; don't put non-script instances in synced folders.

- Parts, models, UI and sounds live in the **place file**, not on disk. After world/UI edits, `save_place`.

## Architecture
```
src/shared/  Config.luau (EVERY tunable number), Toys.luau (toy list), Remotes.luau (remote names), Types.luau
src/server/  Main.server.luau (requires each module in Services/ and calls :Init() then :Start())
             Services/  PlotService, PresentService, ShelfService, EconomyService, GuardService,
                        DisguiseService, JailService, DataService, ShopService, EventService,
                        MonetizationService, AdventService, TutorialService
             Lib/ProfileStore.luau
src/client/  Main.local.luau (requires each module in Controllers/)
             Controllers/  HudController, RevealController, DisguiseController, ShopController,
                           JailController, IndexController, AdventController, TutorialController
ServerStorage/Templates (place file): present, toy, elf, snowman models
Workspace/Map (place file): world, with CollectionService tags + attributes for gameplay spots
```
- **Server-authoritative, always.** The client only sends intents through RemoteEvents. The server validates every remote: player state, distance, ownership, cooldowns, rate limits, and argument types. Coins, rolls, steals, sells, unlocks, jail and purchases happen only on the server.
- Remotes are created by the server at boot under `ReplicatedStorage/Remotes`; the client uses `WaitForChild`.
- **All numbers in `Config.luau`.** "Make elves slower" should be a one-number change.
- Find gameplay spots by CollectionService tags (PresentSpawn, ElfWaypoint, DropMat, ShelfSlot, Barrier, CoalRock...) with attributes (Zone, Route, Index). Never by hard-coded paths into the map.
- **Data:** only `DataService` touches persistence, through ProfileStore (session-locked). Never call DataStoreService elsewhere.
- **Purchases:** `ProcessReceipt` must grant each purchase exactly once (record the PurchaseId in the profile before returning PurchaseGranted).
- **Paid random items:** Lucky Wrap changes a random roll, so treat it as a paid random item. Show the odds in the UI before purchase, and check `PolicyService:GetPolicyInfoForPlayerAsync(...).ArePaidRandomItemsRestricted`. Hide the product where it's restricted.
- NPC guards: server network ownership, own collision group, PathfindingService for chases, raycast line-of-sight, vision checks ~5×/sec (not every frame).
- Every action must work on **phone** (ProximityPrompts, ContextActionService buttons), PC and console.

## Luau style
- `--!strict` at the top of every file where practical. Typed function signatures.
- `task.wait/task.spawn/task.delay`, never `wait/spawn/delay`. No deprecated APIs.
- Disconnect connections and clean up per-player state on `PlayerRemoving`.
- Small modules with one job each. Short comments explaining *why*, not *what*.
- Unsure about a Roblox API? Check the docs (Studio MCP `http_get` on create.roblox.com, or Context7) before writing code.

## Testing (every step)
1. Playtest through the MCP, read `get_console_output`, fix every error and warning you caused.
2. Screenshot when the change is visual.
3. Say plainly what you could NOT test (multi-player, phone, purchases' live behaviour) and give him the exact steps to test it (e.g. Test → Clients and Servers → Local Server, 2 players).
4. Never claim it works without a playtest result.

## Assets and safety
- Every inserted Creator Store model: list and delete any scripts inside unless he asked for a scripted model. Props have zero scripts.
- Audio only from the Creator Store. No copyrighted songs.
- Content stays kid-safe (docs/01-GAME-DESIGN.md section 15): no weapons that hurt, no blood, no death.
- Original names and art only. Never copy names, UI, art or layouts from Steal An Egg, Steal a Brainrot or any other game.

## Never without his explicit go
- Publish to Roblox, change experience settings, make the game public, change prices.
- Create or delete game passes/products, upload assets that cost Robux, spend money.
- Delete map areas or rewrite large parts of working systems.
- `git push` or anything that rewrites git history.

## Git
- After he says a step works: `git add -A && git commit -m "<phase>.<step>: <short what>"`.
- Remind him to save a `.rbxl` copy into `places/` at the end of each phase.

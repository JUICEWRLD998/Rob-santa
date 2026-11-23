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

| Disk (verified 2026-11-20, both directions) | Studio |
|---|---|
| `src/server/ServerScriptService/Server/` | `ServerScriptService/Server` |
| `src/client/Client/Client/` | `StarterPlayer/StarterPlayerScripts/Client` |
| `src/shared/ReplicatedStorage/Shared/` | `ReplicatedStorage/Shared` |

Script Sync nests the LINKED INSTANCE's name inside the folder you pick. Server and shared are linked on the service, so the service name nests. Since the 2026-11-20 re-link (step 3.4), the client link sits on `StarterPlayerScripts/Client` → `src\client\Client`, so `Client` nests again: `src/client/Client/Client/`. After any re-link, find where Studio actually writes (`find src -newer <a recent file>`) before editing, and fix this table and `tools/sourcemap.mjs` to match. A file placed at the top of `src/server/`, `src/client/` or `src/shared/` is NOT picked up. Always write to the full paths in the table. Studio's `Instance.new("Script")` syncs to disk as `X.legacy.luau`; a `X.server.luau` file arrives in Studio as a Script with RunContext Server.

File names: `X.luau` = ModuleScript, `X.server.luau` = Script, `X.local.luau` = LocalScript, folder = Folder.
Script Sync caveats: never put attributes or tags on scripts; don't put non-script instances in synced folders.
**One synced folder can silently stop syncing while the others still work** (2026-11-20, step 2.1): after Studio reconnected, edits to `Shared/Config.luau` and a brand-new file in `Shared/` never reached Studio, while `Services/` and `Controllers/` synced fine. The playtest would have run stale numbers. Before a playtest that depends on an edit, compare `#script.Source` in Studio (`execute_luau`) with the file's byte count (`wc -c`). Reopening the place (auto-resume sync on) fixed it; re-linking the folder should too. To tell a stuck file from a dead link, drop a new probe file in the folder: if it never arrives, the whole link is dead for this Studio session. Deleting the stuck script in Studio does NOT make it re-sync (2026-11-20: it only left Studio with no Config at all). Reopening fixed it once (2.1) but not the second time (2.4). What worked: re-linking. The link sits on the SERVICE (ReplicatedStorage linked to `src\shared`), which is why Shared's own Script Sync menu only offers "Show in disk" / "Show root instance"; have him stop and re-link ReplicatedStorage to `src\shared`.
**Never write a synced script's `.Source` through `execute_luau`, even to copy the disk text in** (2026-11-20, step 2.4). I did that to Config.luau as a workaround during the outage above. Afterwards Script Sync kept updating every other file but never took Config from disk again: a later Config change never arrived, and the live game crashed on `Config.AntiCheat = nil`. If a file is stuck, stop and have him re-link or resolve the sync in Studio.

- Parts, models, UI and sounds live in the **place file**, not on disk. After world/UI edits, `save_place`.
- **`screen_capture` does not draw BillboardGuis with `AlwaysOnTop = true`** (2026-11-20, step 3.2). The elf's "HEY!" was enabled on the client and never appeared; a plain control sign failed the same way and passed with AlwaysOnTop off. Keep AlwaysOnTop off where a screenshot must prove the sign, or the check is blind.
- **Before driving a playtest, check he isn't playing in it** (move a sample over a few seconds). Twice in 3.1/3.2 he was; my teleports and a Scriptable camera fought his controls. A custom-camera `screen_capture` also snaps back to his live camera while he moves.
- **To click a UI button in a playtest, use `user_mouse_input` with screen `x`/`y` read off a `screen_capture`** (2026-11-21, step 4.4). With the device emulator on, the `instance_path` form clicked nothing once and hung past 120 s the second time. Scripted clicks don't work either: `VirtualInputManager` needs RobloxScript capability.
- **Playtest `screen_capture` can come back with UI but no 3D world** (same session, emulator off at the time). Edit-mode captures rendered fine, and later playtest captures did too. Don't read a blank world as a broken build: check instances through `execute_luau`, or capture in Edit.
- **`screen_capture` and `generate_avatar` can hang or time out while `execute_luau` still works** (2026-11-22, step 5.3). Captures came back blank, then ran past 120 s ("Target is not reachable ... DMN_RSRVD_FOCUSED"), and two avatar generations timed out. `generate_animation` still worked. The likely cause is a Studio window that is minimized or in the background. Ask him to bring Studio to the front before visual checks, and don't report a look as checked when no capture came back.
- **TweenService stalls while Studio is in the background; Heartbeat keeps running** (2026-11-22, step 5.6). A tween on a plain NumberValue stayed `Playing` at 0 after 1.5 s, while 90 Heartbeats ran. The music never faded in. Fades that a test must observe should be stepped on Heartbeat (SoundController does this). Don't read a stalled tween as a bug in the game.
- **Two `execute_luau` calls in one message run one after the other.** A server call with `task.wait` blocks, so a client listener started in the next call misses everything. Schedule the server side with `task.delay` and return at once, then listen on the client.
- **Multiplayer tests (Local Server, 2026-11-23, step 7.1).** `list_roblox_studios` lists one id per window: the edit window (named), the server window (state says Focused: Server), and one per player (unnamed; read `LocalPlayer.Name` to tell which is which, the order is not Player1 first). To press a prompt as a player, run a Client `execute_luau` in that player's window: set the camera to Scriptable at `target + Vector3.new(7, 6, 0)` looking at the target, wait 1 s, then `prompt:InputHoldBegin()` (restore CameraType Custom after; a camera placed behind the character kept the prompt hidden, step 7.2), wait `HoldDuration + 0.2`, `InputHoldEnd()`. Without the camera step the hold silently does nothing (it looked like a broken grab twice). It also does nothing while that window is in the background: prompts are only shown on rendered frames. Count `RunService.RenderStepped` for 1 s on the client; 0 means ask him to bring the window to the front (step 7.2: every hold failed this way, in solo Play too). Each `execute_luau` call takes several seconds, so for a "both at once" test the server sets a Workspace attribute with a time 40 s ahead (`GetServerTimeNow() + 40`) and each client waits for it; 8 to 25 s was too short. Dropped presents go back to their zone after `Config.Presents.DroppedReturnSeconds` (10 s), so knock loose and pick up in ONE client call. Set `TutorialSafe` on test players so elves ignore them, and reset it, `upgrades`, `zonesOwned` and `coins` (DebugData) afterwards.
- **To photograph a short effect, fire it with no wait and call `screen_capture` in the next call** (2026-11-22, step 5.5). A capture takes seconds to arrive. A reveal fired with `task.wait(1)` inside the same `execute_luau` was already gone, and two blank captures looked like a broken reveal.
- **Device emulator:** `SetOrientationAsync` errors unless a phone or tablet is active, so call `SetDeviceAsync` first. Set the device in Edit, before Play. The touch controls differ by device: on a Galaxy A06 (705×338, GUI 280 px tall under a 58 px inset) the jump button is 70 px at (610,190), and on an iPad it is 120 px. Place our own touch buttons relative to `PlayerGui.TouchGui...JumpButton` (DisguiseController does this), never at a fixed offset. Read live positions with a Client `execute_luau` (AbsolutePosition works there). Call `StopSimulationAsync()` when done.
- Freeze an NPC for a screenshot with `HumanoidRootPart.Anchored = true` (it walks out of frame between tool calls), and release it after.
- **A ProximityPrompt only shows while its part is on camera** (2026-11-20, step 4.2). After teleporting the character with `root.CFrame = ...`, the follow camera can end up between the character and the target, facing back, and the prompt stays hidden: E did nothing, which looked like a broken shop prompt. Before pressing a prompt key, point the camera at the target (`workspace.CurrentCamera.CFrame = CFrame.lookAt(behindCharacter, target)`) and confirm with `ProximityPromptService.PromptShown`.

## Skills and static checks (installed 2026-11-19)
- **Project skills** in `.claude/skills/` (load them by name for any Roblox work):
  - `roblox-dev-skill` (MSayib, v2.22.0, MIT): verified Luau/Roblox API facts, security, ProfileStore, ProcessReceipt, Studio MCP limits. Its version line is a date, not today's engine version.
  - `roblox-simulator-economy` (gamedev-skills, Apache-2.0): cost curves, income/sec, offline earnings; run its calculator with `tools/bin/lune.exe run .claude/skills/roblox-simulator-economy/scripts/balance.luau <file.json>`.
- **Roblox's own skills** come through the Studio MCP `skill` tool (`list_skills` lists them). Use `rbx-permissions` before DataStore or Open Cloud work, `rbx-device-simulator-lua` for phone checks, `rbx-unit-test` for module tests, `rbx-instrument-analytics` for the tutorial funnel. `rbx-open-cloud-usage` can create passes/products, which still needs his explicit go.
- **Before every playtest** that follows a script change: `bash tools/check.sh` (selene lint + luau-lsp type check over `src/`, using a sourcemap built from the Script Sync table). Fix what it reports first. Verified 2026-11-19 with planted errors: luau-lsp catches type errors and deprecated `wait()`; selene catches unused and undefined variables but does NOT flag `wait()`, so both are needed. `require()` resolution through the generated sourcemap is proven (step 1.2: a planted wrong type through `require(ReplicatedStorage.Shared.Config)` and a missing module were both flagged). Gotcha it found: `xpcall` on a function returning nothing types as one return value; wrap it so the inner function returns `any` (same for `pcall`). **Gate a commit on the output, not on a pipe:** `bash tools/check.sh | tail && git commit` commits even when the check fails, because the pipe returns `tail`'s exit code (this happened once in step 2.1). Use `bash tools/check.sh > out.txt 2>&1; grep -q "== CLEAN" out.txt && git commit ...`. Tools live in `tools/bin/` (gitignored): selene 0.32.0, luau-lsp 1.70.1, lune 0.11.1, from each project's GitHub releases.

## Architecture
```
src/shared/  Config.luau (EVERY tunable number), Toys.luau (toy list), Remotes.luau (remote names), Types.luau,
             ToyMath.luau (income and sell price, shared so server and UI agree),
             IndexBook.luau (4.4: Index pages, entry keys, find bonus, income multiplier; shared too)
src/server/  Main.server.luau (requires each module in Services/ and calls :Init() then :Start())
             Services/  PlotService, PresentService, UnwrapService, MovementService, ShelfService,
                        EconomyService, GuardService, DisguiseService, JailService, DataService,
                        ShopService, EventService, MonetizationService, DailyService (6.3: Advent, streak, quests),
                        SleighRaidService, MostWantedService, SnowballService (6.4), TutorialService (6.5: section 14, saved in data.tutorial),
                        NpcService (5.3: idle loop on IdleNpc-tagged models), ZoneService (barriers; Config.Debug.OpenZonesInStudio opens them in Studio only),
                        IndexService (4.4: records finds from UnwrapService, pays the bonus, sends
                        IndexSync; ShelfService multiplies income by IndexBook.incomeMultiplier)
                        (MovementService is the ONLY writer of WalkSpeed: set a named modifier)
             Lib/ToyModel.luau (toy builder: mesh from ServerStorage/ToyMeshes/<id> since 5.4, mutation
             looks, tag), Lib/ProfileStore.luau (4.1, vendored: loleris
             v1.0.3, commit 45c9847; no GitHub releases exist. selene.toml and check.sh skip it)
src/client/  Main.local.luau (requires each module in Controllers/)
             Controllers/  HudController, PresentController, RevealController, OwnerPromptController,
                           DisguiseController,
                           ShopController, JailController, IndexController, AdventController,
                           TutorialController, SoundController (5.6),
                           StoreController and BlizzardController (6.2), DailyController (6.3),
                           SleighRaidController and SnowballController (6.4)
ServerStorage/Templates (place file): Present, Toy (2.1/2.2), ElfGuard and HeadElf (5.3: generated R15 elf +
lantern; Head/Alert and Head/AlertSound are required). ServerStorage/CharacterOptions holds the unpicked options.
Animation IDs live in Config.Animations (owned by the game owner); GuardService plays the elf's, JailController the
mining swing. Snowman Camera is built in code. Workspace/Map/Town/BlackMarketDealer: generated R15, anchored root, tagged
IdleNpc (NpcService plays the default idle on every IdleNpc model). JailService welds a parts pickaxe
(JailPickaxe) to the right hand while in the cell.
Workspace/Guards: live elves, Head Elf and Snowman Cameras, all created by GuardService at boot
(elves in collision group "Elves"; snowmen are built from parts on SnowmanCameraSpot-tagged pads)
StarterGui (place file): RevealGui (2.2), HudGui (2.3; ShopButton on the left, 4.2), ShopGui (4.2: Panel with
Title, Coins, Status, Close, List/ItemTemplate), IndexGui (4.4: same panel; Bonus label, List/PageTemplate and
List/RowTemplate with Cells/CellTemplate; HudGui.IndexButton sits above ShopButton, clear of the phone
thumbstick); controllers fill and animate them, they don't build them.
5.5 skin: RevealGui is a full-screen stage (IgnoreGuiInset; Burst, Rays, Toy ViewportFrame, Card with
Mutation/StampScale, Confetti/PieceTemplate, Flash). HUD layout (2026-11-22, the owner found the top bar crowded): every top button is 56 px. INDEX and SHOP are in the top-left column, DAILY and ROBUX in the top-right column. In the centre, Coins (176x44) and Wraps (96x44) form one pair; while jailed, JailGui.Panel (128x44: "Free in Ns" and "Mine coal c/n") takes the Wraps spot, with BailOutButton (88x44) beside it, and DAILY plus the Wrap! touch button hide. DontMove sits at y 0.55 so it clears the Wrap! button on small phones. RaidTimer (6.4) is a 56 px tile in the top-left column under SHOP, hidden except during the raid warning ("SLEIGH 7s", orange) and the raid ("RAID 0:42", red); the owner found a centre banner and then a centre pill covered the phone screen, so nothing about the raid goes in the centre and there is no raid toast. Toast at y 58, Blizzard banner at y 94. On phone the bottom-right row is Snow (56 px), Wrap! (90 px), Jump; the Snow button follows the Wrap! button (SnowballController). Toy name tags on the unwrap table alternate height (ShelfService) so neighbours do not run together.
Shop and Index panels are `UDim2.new(1,-230,0.82,0)` wide (max 620), leaving 115 px clear on each side for
the thumbstick and jump button. Every ScreenGui uses ZIndexBehavior Global, and each DropShadow sits at its
parent's ZIndex - 1. Numbers use Luckiest Guy; everything else uses Fredoka One.
Sound (5.6): SoundService/Sfx and SoundService/Music (place file; APM Music / Pro Sound Effects only, each
Sound has a Source attribute). SoundController (client) plays them from player attributes the server sets:
CarryCount, ChasedBy (GuardService: elves chasing you), Jailed, Unwrapping (UnwrapService), Coins, plus the
DisguiseUpdate and UnwrapReveal remotes. Numbers in Config.Audio.
ReplicatedStorage/ToyMeshes is copied from ServerStorage at boot (ToyModel.publishMeshes). It is NOT in
the place file, because ReplicatedStorage is a synced folder.
Shop (4.2): Shared/ShopCatalog.luau (items + prices, shared like ToyMath) -> ShopService (RequestPurchase,
item id only) -> Player attributes Shop_<ItemId> = owned level. GuardService reads Shop_QuietSteps,
DisguiseService reads Shop_ExtraWrap, ZoneController reads Shop_Zone2/3; ZoneService:OwnsZone reads the save.
Player attributes the server sets for the UI: Hideout, CarryCount, CarryCapacity, Coins, IncomePerSecond,
Jailed (3.3), Coal (3.3). Coins/Coal (and the Coins leaderstat) are display copies EconomyService writes
from the saved data (4.1). StarterGui/JailGui (3.3): Stamp + Panel; Panel.BailOutButton (6.2) is wired
by JailController.
Robux (6.2): MonetizationService is the ONLY setter of MarketplaceService.ProcessReceipt. Products are granted
through DataService:ProcessPurchase (grant + PurchaseId in one non-yielding step, then wait for the save).
IDs and effect numbers live in Config.GamePasses / Config.DevProducts; Shared/StoreCatalog.luau holds the store
cards, coin pack amounts and the Lucky Wrap odds text. Pass effects reach other services as Player attributes
`Pass_<Key>` (ShelfService: Vip; PresentService: BigSack; DisguiseService: WrapMaster; SpeedBoots is a
MovementService modifier), plus PassesChecked, LuckyWraps, BailCredits and PaidRandomItemsRestricted.
Blizzard: Workspace attributes BlizzardEndsAt (server time) and BlizzardBy, plus GuardService:SetBlizzard.
Client: StoreController (StoreGui, HudGui.StoreButton top-right, under DAILY), BlizzardController (HudGui.Blizzard
banner), and SnowController (heavier snow). Studio test hook: `ServerStorage.DebugMonetization:Invoke("receipt",
player, productKey, purchaseId?)` runs a fake receipt; `("pass", player, passKey)` grants a pass. In a Studio
playtest the real purchase prompt is free and goes through ProcessReceipt too.
Live prices come from GetProductInfoAsync, and Config prices are only a fallback. On 2026-11-22 the live prices
differed from the Config prices (Blizzard 59, Lucky Wrap 25, coins 15/59/169), so trust the store screen.
Daily (6.3): DailyService runs the Advent Calendar, the login streak and the daily quests (UTC dates). It sends
DailySync (Types.DailySync) and handles RequestAdventDoor(day, "Free"|"Coal"|"Robux"). For Robux, the server
remembers the door and opens the purchase prompt itself, and MonetizationService's receipt calls
DailyService:GrantAdventCatchUp. Quest progress comes from Server/Lib/GameEvents.luau: services call
`GameEvents.fire(name, player, amount?)` (PresentGrabbed, InspectionSurvived, MinedOut, PresentUnwrapped,
ToySold) instead of requiring DailyService. The "Advent Calendar" prompt on the AdventCalendar-tagged Town board
is made by DailyService, and DailyController opens the screen when it fires. Place file: DailyGui (Panel/List with
HeaderTemplate, QuestTemplate, StreakRow/DayTemplate, DoorGrid/DoorTemplate, ActionRow) and HudGui.DailyButton
(top-right corner, with a Badge; hidden while jailed). Studio test hook:
`ServerStorage.DebugDaily:Invoke("date", "2026-12-10")` pretends it is that UTC date ("" = real), and
`("event", "ToySold", player, n)` fires a GameEvents event. **Reset a test player's adventDoors, adventYear,
lastStreakDay and quests afterwards**: doors opened on a pretend December date stay opened in the real one.
DailyService rate-limits RequestAdventDoor (0.4 s), so a test that fires several requests in a row must wait
longer between them, or some are dropped without an error.
**`user_mouse_input` clicks missed the HUD with the phone emulator on** (2026-11-22, step 6.3): both the
AbsolutePosition and the screenshot coordinates clicked nothing. For a screenshot of a panel, set it Visible
from a Client `execute_luau`; the controller fills it on every sync even while it is closed.
Sleigh Raid, Most Wanted, Snowball (6.4): SleighRaidService sets the Workspace attributes SleighRaidState
("Waiting" | "Warning" | "Active"), SleighRaidLandsAt and SleighRaidEndsAt, flies ServerStorage/Templates/Sleigh
(place file, parts, pivot at the bottom centre, nose to -Z) onto the SleighPad, and calls
PresentService:SpawnRaidPresents/ClearRaidPresents (zone 0 = Town presents) and GuardService:StartRaid/EndRaid
(raid elves use the SafeZone box as their zone; Elf.settings replaced the ByZone lookups). Test hook:
`ServerStorage.DebugRaid:Invoke("start" | "end" | "state")`. MostWantedService fills the WantedGui SurfaceGui on
the MostWantedBoard part and puts a Highlight (MostWantedOutline) in the character; Workspace attribute
MostWantedUserId. SnowballService handles RequestSnowball(aim) and fires SnowballFx to everyone; it uses
GuardService:GetElfRoots/StunElf and PresentService:KnockLoose. Dropped presents now carry a Steal prompt.
Tutorial (6.5): TutorialService moves a brand-new player through section 14 and sends TutorialSync
(Types.TutorialSync: step + target Instance). TutorialController draws the hint (StarterGui/TutorialGui.Hint,
place file, at y 58: it hides while HudGui.Toast is visible), a local gold footprint trail
(Workspace/TutorialTrail, client only) and a spinning arrow, and pulses the Wrap! and SHOP buttons. The
TutorialSafe player attribute makes every elf ignore the player except the one GuardService:TutorialSpot
sends (slow, never catches, lets a moved box go once). Steps advance on GameEvents (PresentGrabbed,
InspectionSurvived, PresentUnwrapped, ToyShelved, ShopBought). PresentService:NearestResting/RaiseResting/
RaiseCarried make the first present Rare. Test hook: `ServerStorage.DebugTutorial:Invoke("restart" | "skip" |
"state", player)`. Each step logs an AnalyticsService onboarding funnel step once per player.
**`ContextActionService:GetButton` can yield inside a game LocalScript on a touch device** (2026-11-22, step 6.5). The tutorial hint loop called it every refresh and never got past it on the phone emulator: no error, no warning, and the hint stayed hidden. The same call returned at once from `execute_luau`, so a command-bar test does not prove it is safe. Look the button up in its own thread and keep the result (TutorialController does this).
**A SurfaceGui's MaxDistance seems to count from the character, not the camera** (2026-11-22, step 6.4): the
poster stayed blank in a `screen_capture` taken from 17 studs while the character stood in its hideout. WantedGui
uses MaxDistance 0. Remember this before reading a blank SurfaceGui in a screenshot as broken.
**Testing raid elves or snowballs by teleporting next to an elf usually ends in jail** (the other elves see
you). Test a snowball from 12 studs behind a lone Zone 1 elf, and wait 0.3 s after the teleport before
firing, or the server still has the old position and the throw misses.
Zone edges: each zone has a ZoneVolume part tagged ZoneArea; elves never chase past it.
Models tagged OwnerOnly (+ OwnerUserId attribute): the client hides their prompts from everyone else.
Comparing Studio `#Source` with `wc -c`: git may have checked the file out with CRLF endings and
Studio stores LF, so compare `tr -d '\r' < file | wc -c`.
Workspace/Map (place file): world, with CollectionService tags + attributes for gameplay spots
Workspace/Map/Lights (5.1): cabin glows, Town lanterns, per-zone lights (invisible, CanQuery off so elf
raycasts ignore them). Lighting settings are in docs/04 section 5. SnowController (client) draws snow.
PresentFxController (5.4, client) animates the rainbow ribbon on presents whose Config.Wrapping has rainbowRibbon.
`Lighting.Technology` can't be read or set through `execute_luau` (lacks RobloxScript capability): the
owner sets it by hand.
Art (5.2) is decoration on top of the greybox: each Hideout, the Town and each zone area has a `Decor`
model (cabins: snow caps, windows, chimney, bulbs; Town: tree, stall awnings and signs, jail hut,
board frames, sleigh-pad stripes), parts CanQuery/CanTouch off and CanCollide off except a few solid
bases (tree trunk and lowest tier, gifts). Gameplay parts (tagged) keep their position
and size; only Material/Color change. The Baseplate grid texture is hidden (Transparency 1), not deleted.
```
- **Server-authoritative, always.** The client only sends intents through RemoteEvents. The server validates every remote: player state, distance, ownership, cooldowns, rate limits, and argument types. Coins, rolls, steals, sells, unlocks, jail and purchases happen only on the server.
- Remotes are created by the server at boot under `ReplicatedStorage/Remotes`; the client uses `WaitForChild`.
- **All numbers in `Config.luau`.** "Make elves slower" should be a one-number change.
- Find gameplay spots by CollectionService tags (PresentSpawn, ElfWaypoint, DropMat, ShelfSlot, Barrier, CoalRock...) with attributes (Zone, Route, Index). Never by hard-coded paths into the map.
- **Data:** only `DataService` touches persistence, through ProfileStore (session-locked). Never call DataStoreService elsewhere. Other services change `DataService:GetData(player)` in place (nil until loaded; wait with `WaitForData` or `OnLoaded`). A new saved field goes into DataService's `PlayerData` type and `TEMPLATE`; `Reconcile()` adds it to old saves.
- **`execute_luau` gets its own copy of every ModuleScript** (2026-11-20, step 4.1). `require(...DataService)` from a test returned an empty module (`GetData` = nil) while the game's copy had the player loaded. To read or seed live state, use a Studio-only BindableFunction the game creates: `ServerStorage.DebugData:Invoke("get", player)` / `("set", player, field, value)` (Config.Debug.DataHookInStudio). Instances and attributes are shared; module tables are not.
- **Purchases:** `ProcessReceipt` must grant each purchase exactly once (record the PurchaseId in the profile before returning PurchaseGranted).
- **Paid random items:** Lucky Wrap changes a random roll, so treat it as a paid random item. Show the odds in the UI before purchase, and check `PolicyService:GetPolicyInfoForPlayerAsync(...).ArePaidRandomItemsRestricted`. Hide the product where it's restricted.
- NPC guards: server network ownership, own collision group, PathfindingService for chases, raycast line-of-sight, vision checks ~5×/sec (not every frame).
- **A controller that needs a ScreenGui must never give up waiting for it.** `WaitForChild(name, 15)`, then warn, then `WaitForChild(name)` with no timeout. On a slow join PlayerGui filled after more than 15 s, and Shop/Index (built 4.2/4.4) had returned early, so the SHOP and INDEX buttons stayed dead for the whole session (2026-11-21, the same bug 3.4 fixed in HudController).
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

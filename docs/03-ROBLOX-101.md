# 03 — Roblox 101

The minimum you need to understand to direct Claude well and spot when something is wrong. You don't need to memorise code. You need the **map of how a Roblox game is put together**.

Read it once before Phase 0. Come back when Claude uses a word you don't know (glossary at the bottom).

---

## 1. Experience, place, server

- **Experience** = your game as players see it on Roblox (page, icon, title). Older word: "game".
- **Place** = one world inside the experience. Rob Santa has one place.
- **Server** = one running copy of the place. Roblox starts as many servers as needed, each holding up to 8 players (our setting). Players in different servers never see each other.

---

## 2. The Explorer tree (where things live)

Everything in a Roblox game is an **Instance** (an object) in one big tree, the **DataModel**. The top-level folders are called **services**:

| Service | What goes there | In Rob Santa |
|---|---|---|
| **Workspace** | The 3D world. Anything here can be seen and touched | Map, hideouts, zones, elves, presents |
| **ReplicatedStorage** | Things **both** server and players can read | `Shared` folder: config, toy list, remotes |
| **ServerScriptService** | Code that only runs on the server. Players can't see it | `Server` folder: all game rules |
| **ServerStorage** | Things only the server can read | Templates: present models, elf rig, toy models |
| **StarterPlayer → StarterPlayerScripts** | Code copied to each player's device when they join | `Client` folder: UI, buttons, effects |
| **StarterGui** | Screens (UI) given to each player | HUD, shop, unwrap reveal |
| **Lighting** | Sky, time of day, fog, sun | Snowy night look |
| **SoundService** | Sounds and music settings | Music, sound effects |

---

## 3. Server vs client: the most important rule

Every game runs in two places at once:

- The **server**: Roblox's computer. One per server. It holds the truth.
- The **client**: each player's own phone/PC. It shows the game and reads that player's input.

> **Golden rule: the server decides everything that matters.** Coins, steals, sells, unlocks, jail, rarity rolls. The client only *asks*.

Why: some players use cheat tools ("exploits") that let them run any code on **their own client**. If the client could say "give me 1,000,000 coins" and be believed, every exploiter would be rich in a minute. So:

- Client: "I'd like to grab present #12."
- Server: "Are you close enough? Are your hands free? Is that present still there? OK, it's yours."

Claude follows this rule automatically (it's in CLAUDE.md). Your job is to notice if anything ever trusts the client.

---

## 4. The three kinds of script

| Kind | Runs on | File name in `src/` | Used for |
|---|---|---|---|
| **Script** | Server | `Name.server.luau` | Game rules, guards, money |
| **LocalScript** | Client | `Name.local.luau` | UI, buttons, camera, effects |
| **ModuleScript** | Wherever it's loaded | `Name.luau` | Shared code and data (config, toy list, services) |

Rob Santa uses **one** Script (`Main.server.luau`) that loads many ModuleScripts ("services"), and **one** LocalScript (`Main.local.luau`) that loads client ModuleScripts ("controllers"). This keeps code organised and easy for Claude to work on.

---

## 5. How server and client talk: Remotes

They're separate computers, so they send messages:

- **RemoteEvent** = a one-way message. Client → server ("I pressed disguise") or server → client ("show the unwrap reveal: Golden Robot Buddy!").
- **RemoteFunction** = a question with an answer. Client asks, server replies. We'll mostly use RemoteEvents.

The server must **check every message** it receives (distance, cooldowns, ownership), because an exploiter can send fake ones.

---

## 6. The 3D basics

| Word | Meaning |
|---|---|
| **Part** | A basic block (or ball, cylinder, wedge). Everything starts as parts |
| **MeshPart** | A part with a custom 3D shape (a toy, a sleigh) |
| **Model** | A group of parts treated as one thing (a cabin, an elf) |
| **Anchored** | If on, the part doesn't move or fall. Map pieces are anchored |
| **CanCollide** | If on, things bump into it. Off = walk-through |
| **Position / CFrame** | Where something is. CFrame = position + rotation |
| **Vector3** | Three numbers (X, Y, Z) for a position, size or direction |
| **Stud** | Roblox's unit of length. A player is about 5 studs tall |
| **Humanoid** | The thing that makes a model a character: it can walk, jump, have health |
| **Character** | A player's avatar in the world (a Model with a Humanoid) |
| **R15 / R6** | The two body types. R15 = 15 parts, smoother animation. We use R15 for elves |

---

## 7. Luau in 2 minutes

Luau is Roblox's programming language (based on Lua). Claude writes it, but here's how to read it:

```lua
-- This is a comment. Lua ignores it.
local coins = 100                      -- a variable
local toy = { name = "Teddy Bear", rarity = "Uncommon" }  -- a table (like a list/dictionary)

local function addCoins(player, amount)  -- a function
    print(player.Name .. " got " .. amount .. " coins")  -- .. joins text
end

-- Events: "when X happens, do Y"
game.Players.PlayerAdded:Connect(function(player)
    print("Welcome, " .. player.Name)
end)

task.wait(2)  -- pause this code for 2 seconds
```

You'll often see `--!strict` at the top of files. It tells Luau to check types strictly, which catches mistakes early.

---

## 8. Built-in tools we'll use

| Tool | What it does in Rob Santa |
|---|---|
| **ProximityPrompt** | The "Hold E" bubble near an object. Works on phone, PC and console automatically. Grab, deliver, unwrap, shop |
| **TweenService** | Smooth movement and fades (UI popping in, toy spinning) |
| **PathfindingService** | Finds a walking path around walls (elves chasing) |
| **Raycast** | Shoots an invisible line to see if something blocks it (can the elf actually see you?) |
| **CollectionService (tags)** | Labels on parts like "PresentSpawn", "ElfWaypoint", so code finds them all |
| **Attributes** | Small named values stored on an instance (e.g., `Zone = 2` on a spawn point) |
| **DataStoreService** | Saves player data between sessions. We wrap it with the **ProfileStore** library, which prevents lost or duplicated saves |
| **MarketplaceService** | Robux purchases: game passes and developer products |
| **ContextActionService** | Makes on-screen buttons on phone and key binds on PC (disguise, snowball) |
| **AnalyticsService** | Custom events for the tutorial funnel |

---

## 9. Testing modes (Test tab)

| Mode | Use it for |
|---|---|
| **Play** | Normal test: you spawn as a player |
| **Play Here** | Spawn where the camera is. Handy for testing one zone |
| **Run** | Server runs with no player. Watch elves patrol |
| **Clients and Servers → Local Server, 2–3 players** | Opens several windows, one per fake player. **The only way to test multiplayer things** (Sleigh Raid, Most Wanted, snowballs) |
| **Device emulator** | Shows the game as a phone or tablet. Check buttons and UI size |

Claude can start and stop **Play** itself through the MCP and read the Output. Multi-player tests and the final "does it feel fun?" check are yours.

---

## 10. Reading an error

Errors show in **Output** in red, like:

```
ServerScriptService.Server.Services.PresentService:57: attempt to index nil with 'Position'
```

- `ServerScriptService.Server.Services.PresentService` = which script (`src/server/Services/PresentService.luau`)
- `57` = line number
- the rest = what went wrong ("attempt to index nil" means "you asked for something that doesn't exist")

You don't need to fix it. **Copy the whole red line and paste it to Claude.** Claude can also read Output itself through the MCP. Ask: `check the Output for errors`.

---

## Glossary

| Word | Meaning |
|---|---|
| CCU | Concurrent users: players online right now |
| D1 / D7 retention | % of new players who come back 1 day / 7 days later |
| DevEx | Developer Exchange: turning earned Robux into real money |
| Game pass | One-time Robux purchase (VIP, Big Sack) |
| Developer product | Purchase you can buy again (Bail Out, coin packs) |
| Creator Store / Toolbox | Library of free (and paid) models, meshes, audio |
| Free model | Something from the Toolbox. Can contain hidden bad scripts; always check (04-CHARACTERS-AND-ART.md) |
| Exploiter | A player using cheat software |
| Remote | RemoteEvent/RemoteFunction: a client↔server message |
| MCP | The connection that lets Claude Code control Studio |
| Script Sync | The Studio feature that mirrors scripts to files in `src/` |
| FTUE | First-time user experience: the tutorial and first minutes |
| Greybox | A rough map made of plain blocks, before art |
| StreamingEnabled | Roblox only loads the part of the map near the player. Helps phones |

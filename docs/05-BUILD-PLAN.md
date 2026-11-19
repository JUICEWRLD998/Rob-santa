# 05 — Build plan

The step-by-step build, from an empty baseplate to a live game. Ten phases. Each step has:
- **Prompt:** what to paste to Claude (edit the words if you want; the meaning is what matters)
- **Test:** how *you* check it works
- **Done when:** the bar to move on

Rules for every step (more in 06-VIBECODING-WITH-CLAUDE.md):
1. One step at a time. Don't paste two steps together.
2. Claude builds, then tests through the MCP. Then **you** press Play and try it yourself.
3. Works → `commit this`. Broken → describe what you saw and paste the error.
4. End of each phase → save a `.rbxl` copy into `places\` and tick README.md.

---

## Calendar

| Phase | Dates | What |
|---|---|---|
| 0 | Fri Nov 20 | Setup (02-SETUP.md) |
| 1 | Sat Nov 21 – Sun Nov 22 | Greybox world |
| 2 | Mon Nov 23 – Wed Nov 25 | Core loop |
| 3 | Thu Nov 26 – Sat Nov 28 | Elves, jail, disguise |
| 4 | Sun Nov 29 – Tue Dec 1 | Saving, upgrades, zones 2–3, index |
| 5 | Wed Dec 2 – Fri Dec 4 | The look. **Dec 2: also fill in the Maturity & Compliance questionnaire (your account turns 30 days old)** |
| 6 | Sat Dec 5 – Sun Dec 6 | Money, events, tutorial |
| 7 | Mon Dec 7 | Test and harden |
| **8** | **Tue Dec 8** | **Launch** |
| 9 | Dec 9 – Jan 4 | Live updates |

Behind schedule? Use the **cut list** at the bottom. Don't move the launch.

---

## Phase 0 — Setup (Fri Nov 20)

Follow **02-SETUP.md** from top to bottom. It ends with Claude making a cube appear in Studio and a synced script printing in a playtest.

---

## Phase 1 — Greybox world (Sat Nov 21 – Sun Nov 22)

**Goal:** the whole map exists as plain blocks, with every important spot labelled, so code can find it. No art yet. Ugly is correct here.

### 1.1 Block out the map
**Prompt:**
```
Read docs/01-GAME-DESIGN.md sections 2 and 3. Using the Studio MCP in Edit mode, build a greybox
North Pole map from plain anchored parts inside Workspace/Map, in this order from safe to dangerous:
- a row of 8 small hideout cabins (Workspace/Map/Hideouts/Hideout1..8), each with: a DropMat part,
  an UnwrapTable part, 20 ShelfSlot parts (numbered), a SpawnLocation-style spawn point, and a NameSign
- a Town Square with spots for BlackMarket, GadgetShop, MostWantedBoard, AdventCalendar, SleighPad, JailEntrance
- Zone 1 Wrapping Room, Zone 2 Toy Factory, Zone 3 Candy Cane Mine: rooms with walls, corners and
  cover to hide behind (sneaking needs cover), 4-8 PresentSpawn points each, and an elf patrol route
  of 4-6 ElfWaypoint parts each
- candy-cane Barrier walls blocking Zones 2 and 3
- a Jail room below the Town Square with 8 CoalRock parts
Use CollectionService tags and attributes (e.g. tag PresentSpawn with attribute Zone=1; tag ElfWaypoint
with Zone, Route, Index). Make walk distances feel right: Zone 1 about 15 seconds' walk from the cabins,
Zone 3 about 40 seconds. Use simple colours per area. Save the place, take a top-down screenshot and
describe the layout to me.
```
**Test:** fly around in Studio. Walk it in Play mode and time the walk to Zone 1 and Zone 3.
**Done when:** you can walk from your cabin through all three zones. There's cover to hide behind in each zone.

### 1.2 Code foundation
**Prompt:**
```
Set up the code foundation described in CLAUDE.md: src/shared/Config.luau (every number from
docs/01-GAME-DESIGN.md), src/shared/Toys.luau (the toy list), src/shared/Remotes.luau,
src/server/Main.server.luau that loads every module in src/server/Services, and
src/client/Main.local.luau that loads every module in src/client/Controllers.
Add a temporary "Coins" leaderstat. Playtest, check Output has no errors, and explain in
5 lines how the pieces connect.
```
**Done when:** a playtest runs with zero red errors, and you understood the 5-line explanation.

### 1.3 Hideout assignment
**Prompt:**
```
Build PlotService: when a player joins, give them a free hideout, spawn them in it, and show their
name on the NameSign. Free the hideout when they leave. Playtest to check it.
```
**Test:** Test tab → Clients and Servers → Local Server with **2 players**. Each window gets a different cabin with the right name.
**Done when:** the 2-player test passes.

**Phase 1 done:** save `places\RobSanta-phase1.rbxl`, tick README.

---

## Phase 2 — Core loop (Mon Nov 23 – Wed Nov 25)

**Goal:** steal → carry → run home → unwrap → shelf → coins → sell works end to end, with no enemies yet. If this isn't satisfying with no guards, guards won't fix it.

### 2.1 Presents spawn and can be grabbed
**Prompt:**
```
Build PresentService per docs/01-GAME-DESIGN.md section 3: presents spawn on PresentSpawn points
(placeholder box models in ServerStorage/Templates, coloured by wrapping tier), respawn every 20-40s,
and can be grabbed with a ProximityPrompt (hold time by tier). Grabbing is validated on the server
(distance, hands free, present still there). The present attaches to the player's back and slows
them by the carry slowdown in Config. If a carried present is dropped (player leaves or resets), it
returns to its zone after 10 seconds. Playtest and screenshot me carrying one.
```
**Test:** grab one. You get slower. You can't grab a second.

### 2.2 Deliver and unwrap
**Prompt:**
```
Build delivery and unwrapping: touching your OWN hideout's DropMat with a present puts it on your
UnwrapTable, a 2-second unwrap plays, the SERVER rolls rarity (by zone table) and mutation (Config),
and a placeholder toy appears. Send the result to the client and show a simple reveal popup
(toy name, rarity colour, mutation). Make another player's DropMat do nothing for you.
```
**Test:** deliver 10 presents. You see different rarities. Delivering at someone else's cabin (2-player test) does nothing.

### 2.3 Shelves, income, selling
**Prompt:**
```
Build ShelfService and EconomyService: after unwrapping, a prompt lets you place the toy on your first
free active shelf (4 active at start). Shelved toys add coins every second (income x mutation).
Each shelved toy has a "Sell" prompt, and the Black Market buys toys too. Show coins on a simple HUD
label (top centre). All money changes happen on the server only.
```
**Test:** shelve 4 toys, watch coins rise, sell one, watch coins jump.

### 2.4 Security check
**Prompt:**
```
Review every RemoteEvent handler in src/server. For each one, tell me what an exploiter could send
and confirm the server rejects it (wrong distance, not their hideout, spam, fake ids). Fix anything weak.
```
**Done when:** Claude lists each remote with its checks, and nothing trusts the client.

**Phase 2 done when:** you play the loop for 5 minutes and want to keep going. Save `phase2.rbxl`, commit, tick README.

---

## Phase 3 — Elves, jail and the disguise (Thu Nov 26 – Sat Nov 28)

**Goal:** the heist. This phase decides whether the game is fun. Leave time to tune.

### 3.1 Elves patrol
**Prompt:**
```
Build GuardService part 1 per docs/01-GAME-DESIGN.md section 4: a temporary ElfGuard (simple R15 rig
is fine for now) in ServerStorage/Templates; spawn elves per zone; they walk their ElfWaypoint route
on a loop at walk speed 8. Server owns their physics. Elves don't collide with each other.
Use the MCP Run mode to watch them patrol and screenshot it.
```

### 3.2 Seeing and chasing
**Prompt:**
```
Build GuardService part 2: vision cone (range and angle per zone from Config) plus a raycast
line-of-sight check, checked about 5 times per second. Draw each elf's cone on the floor as a pale
translucent shape that follows it. When an elf sees a player: "!" above its head, a "HEY!" sound
placeholder, then chase with PathfindingService at the zone's chase speed for up to 8 seconds,
giving up after 3 seconds without sight. Touching the player while chasing = caught (just print
"CAUGHT" for now). Tell me how you tested each part.
```
**Test:** walk into a cone → chase. Hide behind a wall → it gives up. Empty-handed you can outrun it. Carrying a Rare, it's close.

### 3.3 Naughty Jail
**Prompt:**
```
Build JailService per section 8: caught = "NAUGHTY!" stamp on screen, carried present returns to its
zone, player teleports to a jail cell. Leave after 20 seconds, OR mine 8 CoalRocks (prompt each) to
leave early. Coal mined is counted. Show a jail screen with the timer and the coal counter.
Leave a clearly marked spot for a "Bail Out" button (wired in Phase 6).
```

### 3.4 The gift-box disguise (signature mechanic: take your time)
**Prompt:**
```
Build the disguise per docs/01-GAME-DESIGN.md section 5 exactly: Q on PC, a big gift-box button on
phone (ContextActionService), ButtonY on console. Server validates wraps left and cooldown. Hide the
avatar and show a present the size of zone presents. Moving cancels it. Patrolling elves ignore a
still gift box. A CHASING elf walks up and inspects for 3 seconds: if the player moves, caught;
if not, the elf says "...Huh. Just a present." and returns to patrol. Wraps refill at your hideout.
Show wraps left on the HUD. Placeholder sounds are fine.
```
**Test (the most important test in the whole build):** get spotted carrying a present, disguise, hold still. Then do it again and move. Ask a friend or sibling to try it **without explaining**. Do they laugh? Do they understand?

### 3.5 Snowman Cameras and Head Elf
**Prompt:**
```
Add the Snowman Camera (zone 2+) and Head Elf (zone 3) per section 4. Camera sweeps, rings a bell
when it sees you, and every elf in that zone chases for 5 seconds. Head Elf is taller, faster and
inspects for 5 seconds.
```

### 3.6 Tune the feel
Play 15 minutes. Then tell Claude in plain words, for example:
```
Zone 1 feels too easy, I never get caught. Zone 2 feels unfair: the camera spots me before I
can see it. The inspection is the best part; make the elf lean in closer.
```
Claude changes the numbers in `Config.luau`.

**Phase 3 done when:** getting spotted is exciting, escaping feels clever, getting caught feels funny. Save `phase3.rbxl`, commit, tick README.

---

## Phase 4 — Saving and progression (Sun Nov 29 – Tue Dec 1)

**Goal:** progress is saved, and there's always something to save up for.

### 4.1 Saving with ProfileStore
**Prompt:**
```
Add the ProfileStore library (by loleris, official GitHub release) at src/server/Lib/ProfileStore.luau.
Build DataService that saves and loads per player: coins, coal, shelved toys (toy id + mutation +
shelf slot), upgrade levels, zones owned, index entries, advent doors opened, login streak, last
login time. Pay offline earnings on join (cap from Config). Replace the temporary leaderstat with
real data. No other code may touch DataStores directly.
```
**Test:** play, earn, leave. Rejoin: everything is back, plus offline coins. In Studio, saving needs "Enable Studio Access to API Services" (done in Phase 0).

### 4.2 Shop and zone unlocks
**Prompt:**
```
Build ShopService + a shop screen (opened at the GadgetShop and by a HUD button): Boots 1-6,
Extra Wrap 1-2, Quiet Steps 1-3, Snowball, extra shelves (cost formula from Config), and Zone 2/3
unlocks (the barrier disappears only for players who own the zone). Server checks money and levels.
```

### 4.3 Zones 2–3 loot and mutations
**Prompt:**
```
Make Zones 2 and 3 use their own rarity tables and present wrappings. Add the mutation visuals on
toys (Frosted tint+sparkle, Gingerbread, Glowing outline+light, Golden material). Placeholder toy
models are fine; real ones come in Phase 5.
```

### 4.4 Collection Index
**Prompt:**
```
Build the Collection Index screen: every toy x mutation, greyed out until found. A first discovery
pays a coin bonus. Completing a zone's page gives +5% income (badge comes later).
```

**Phase 4 done when:** a fresh player has a clear goal at every point in the first hour, and nothing is lost on rejoin. Commit, save, tick.

---

## Phase 5 — The look (Wed Dec 2 – Fri Dec 4)

**Goal:** it looks like a real game in screenshots and on a phone. Read 04-CHARACTERS-AND-ART.md first.

### 5.1 Lighting and mood
```
Apply the lighting from docs/04-CHARACTERS-AND-ART.md section 5: Future lighting, early night,
moonlight, Atmosphere, snowfall particles, a starry skybox, warm window lights, and a light colour
per zone. Screenshot the Town Square, Zone 1 and Zone 3.
```

### 5.2 Replace the greybox, one area at a time
Do these as **separate prompts**: cabins → Town Square → Zone 1 → Zone 2 → Zone 3 → Jail.
```
Replace the greybox of <AREA> with real art per docs/04-CHARACTERS-AND-ART.md: build from parts,
procedural models or generated meshes, keep every tagged gameplay part and its position working,
chunky cartoon shapes, few big details. No free-model scripts. Screenshot before and after.
```
**Check every time:** play the area. Do elves still patrol and see properly? Do prompts still work?

### 5.3 Characters and animations
```
Following docs/04-CHARACTERS-AND-ART.md sections 2 and 3: generate the ElfGuard avatar (show me 3
options), the Head Elf version, the Snowman Camera model, and the Black Market dealer. Then the
animations: patrol look-around, the sniff/inspect, the shrug, the GOTCHA grab, the coal mining.
Wire them into the guard code. Publish animations under the game's owner.
```
Pick the elf you like. The sniff animation gets extra rounds until it makes you laugh.

### 5.4 Toys and wrappings
```
Generate the 16 toy meshes listed in docs/01-GAME-DESIGN.md section 6 (simple, chunky, bright,
readable when small) and the present wrapping per rarity (Mythic gets an animated ribbon).
Replace the placeholders.
```

### 5.5 UI skin
```
Restyle all UI per docs/04-CHARACTERS-AND-ART.md section 5 (UI style). Make the unwrap reveal a
proper celebration that gets bigger with rarity. Check every screen in the device emulator on a
small phone and a tablet; nothing may overlap the thumbstick or jump button.
```

### 5.6 Sound and music
```
Add the sounds and music from docs/04-CHARACTERS-AND-ART.md section 6, using Creator Store audio only.
Chase music fades in when an elf chases you and out when it gives up.
```

**Phase 5 done when:** you'd happily post a screenshot of it. Runs smoothly on your phone. Commit, save, tick.

---

## Phase 6 — Money, events and the first 3 minutes (Sat Dec 5 – Sun Dec 6)

### 6.1 Create the products (you do this part)
In **Creator Hub → your experience → Monetization**, create the 4 game passes and the developer products from 01-GAME-DESIGN.md section 10. Give each an icon (Claude can make icon images from in-game shots). Copy every **ID** into a message to Claude.

### 6.2 Wire purchases
```
Here are the pass and product IDs: <paste>. Build MonetizationService: pass ownership checks,
a correct ProcessReceipt for developer products (handle each purchase exactly once, even if the
server crashes mid-way), and the effects from docs/01-GAME-DESIGN.md section 10, including the
server-wide Blizzard with a banner naming the buyer. Wire the Bail Out button in jail. Add a Robux
store screen. Test purchases in Studio (they are free there) and confirm each effect.
```

### 6.3 Advent Calendar, streak, quests
```
Build the Advent Calendar per section 11 (doors by real UTC date up to Dec 25; day 25 = guaranteed
Mythic; missed doors open with coal or the Advent catch-up product), the 7-day login streak, and
3 daily quests. Use the data fields from DataService.
```

### 6.4 Sleigh Raid and Most Wanted
```
Build the Sleigh Raid (every 12 minutes, 10s warning banner, sleigh lands on SleighPad with 6
Rare-or-better presents and 3 elves, 60s, Town Square unsafe during the raid, countdown on HUD)
and the Most Wanted board + red outline + snowball bounty per section 9. Test with Local Server, 3 players.
```

### 6.5 The first 3 minutes (tutorial)
```
Build the tutorial exactly as docs/01-GAME-DESIGN.md section 14 describes, only for brand-new players.
Log each step with AnalyticsService onboarding funnel events so I can see where people quit.
```
**Test:** use a fresh test (Claude can reset your data) and play it as if you'd never seen the game.

**Phase 6 done when:** a new player is taught the disguise within 90 seconds, and every purchase works in Studio. Commit, save, tick.

---

## Phase 7 — Test and harden (Mon Dec 7)

| Step | How |
|---|---|
| 7.1 Multiplayer | Local Server with 3 players: raid, snowballs, Most Wanted, two people grabbing the same present at once |
| 7.2 Exploit review | Prompt: `Audit every remote and every purchase handler for exploits and race conditions. Fix and list what you changed.` |
| 7.3 Phone | Device emulator, then your real phone through the Roblox app. Every button reachable with a thumb |
| 7.4 Performance | Prompt: `Check performance: part count, scripts running every frame, memory. Fix anything that would hurt phones.` |
| 7.5 Data safety | Join, earn, leave fast. Rejoin. Shut the server down mid-session. Nothing lost, nothing doubled |
| 7.6 Friends test | 3–5 friends play while **you watch and say nothing**. Write down every moment they look confused. Fix the top 3 |
| 7.7 Error sweep | Prompt: `Play through the whole game and read Output. Fix every error and warning.` |

**Phase 7 done when:** no red errors, no lost data, friends wanted to keep playing. Commit, save, tick.

---

## Phase 8 — Launch (Tue Dec 8)

Follow **07-LAUNCH-AND-GROWTH.md**, sections 2–6:
- [ ] 8.1 Maturity & Compliance questionnaire done (label showing)
- [ ] 8.2 Search Roblox for "Rob Santa" and similar names; final title `[🎄] Rob Santa! 🎁`
- [ ] 8.3 Description, genre, icon, thumbnails
- [ ] 8.4 Settings: 8 players, all devices, private server price
- [ ] 8.5 Rename the experience (drop "(dev)") and make it **public**
- [ ] 8.6 Start a small Sponsored Ads campaign
- [ ] 8.7 Post the first clip (the disguise moment) on TikTok/Shorts; open a Roblox Community for updates

---

## Phase 9 — Live updates (Dec 9 – Jan 4)

### Every day (20 minutes)
1. Creator Hub → Analytics: players, D1 retention, session time, Robux.
2. Creator Hub → error report. Paste the top error to Claude.
3. Read comments and your Discord/Community. One fix per day beats ten ideas.

### Update 1 — Fri Dec 18 (school holidays start)
Zone 4 Reindeer Stables + Zone 5 Santa's Vault (sleeping Santa + Noise Meter) + hideout raids with door lock. Title tag `[🦌 NEW ZONES]`.

### Update 2 — Thu Dec 24
Christmas Eve event: Santa is awake all day in the Town Square, double Mythic chance, last Advent doors, festive skybox. Tag `[🎅 CHRISTMAS EVE]`.

### Update 3 — Thu Dec 31
New Year: Rebirth ("New Year's Resolution"), fireworks over the North Pole at midnight UTC. Tag `[🎆 NEW YEAR]`.

### Mon Jan 5 — the decision
Read 00-IDEA.md section 7 and your numbers. Rob the Holidays, or game #2.

---

## Cut list (if you fall behind)

Cut from the top. **Never cut the bottom block.**

1. Daily quests
2. Most Wanted board + Snowball PvP
3. Collection Index (keep the data; skip the screen)
4. Zone 3 (launch with 2 zones, add Zone 3 in Update 1)
5. Mutations' special visuals (keep the multiplier, use a simple tint)
6. Sleigh Raid (move to Update 1)

**Never cut:** the core loop, the elves seeing and chasing, the disguise, saving, phone controls, the tutorial, at least 2 passes + Bail Out.

---

## When you're stuck

- Same bug 3 times? Say: `Stop. Find the root cause before changing anything else. Read the Output and explain what's actually happening.`
- Claude changed too much? Say: `Undo the last change back to the last commit.`
- Lost? Say: `Where are we in the build plan, what's done, what's next?`
- Something feels off but you can't say why? Record a short screen video, describe it, and ask Claude what could cause it.

# 00 — The idea

How we got from "Christmas + crime" to **Rob Santa!**, and why it beats the other options. Read this once. Come back to section 7 in January.

---

## 1. The brief

- Theme: Christmas, crime.
- You: first Roblox game, no Roblox experience, building everything by vibecoding with Claude Code.
- Goal: a game that can actually grow, not a practice project.
- Date: today is Thu 2026-11-19. Christmas Day is 36 days away.

---

## 2. What the market says

Each point below comes with the lesson we took from it.

**1. The "steal formula" is the strongest loop on Roblox right now.**
Live trackers (Nov 10–16, 2026) put **Steal An Egg** at #1 on the whole platform, with snapshots between 498K and 1.5M players online at once. Its loop: take an egg from a guarded nest, a guardian chases you, run back to your base, the egg hatches into a pet that earns money. Steal a Brainrot set the platform record in 2025 with the same skeleton.
→ *Lesson:* "grab from a guarded place → get chased → run home → it earns for you" is a proven genre loop, the way "tycoon" is a genre. We build on that skeleton. Everything on top of it is ours.

**2. Thief games have real but limited demand. Your own scouting data shows the ceiling.**
From the screenshots in `Desktop\theif sim` and `Desktop\theif simulator`:
- "Thief Simulator": 165 players online at once, 4.4-minute sessions. Growth started with **Sponsored Ads** on Oct 21. **Home Recommendation** (the algorithm) took over around Nov 2.
- "thief sim": 327 players online at once, about 10K new users in the 7-day view, **Day-1 retention 8.68%**, average playtime 19.8 min, about 3,300 Robux spent per day, 152K monthly users.
→ *Lessons:* (a) the theft theme gets clicks; (b) D1 retention under 9% means most players never come back, so our design spends a lot of effort on *reasons to return*; (c) a small ad budget at launch can start the engine, and the algorithm only takes over if players stay.

**3. Players are global, young and mostly on phones.**
The thief sim's country split: US 13%, Indonesia 9%, Brazil 9%, Russia 5%, Malaysia 5%, Philippines 4%...
→ *Lesson:* the game must make sense without reading. Big buttons. Every action must work on a touchscreen.

**4. Event tags in titles are normal practice.**
Games in your scouting list carry `[🎃]` and `[Event]` tags.
→ *Lesson:* launch as `[🎄] Rob Santa! 🎁` and change the tag with every update.

**5. Seasonal games spike, then die.**
Christmas games get a December rush and lose most of it after New Year.
→ *Lesson:* Christmas should be the *launch theme*, but the core loop must survive January (section 7).

**6. A new game starts nearly empty.**
At launch you will often have 1–3 players per server.
→ *Lesson:* the game must be fun **alone**. Any idea that needs 6+ players (cops vs robbers, murder mystery) dies at launch.

---

## 3. The gates every idea had to pass

1. Christmas belongs in the idea. It is not a reskin.
2. Crime is the main verb (steal, sneak, escape), not decoration.
3. Fun with 1 player in the server.
4. A 10-year-old understands it from the thumbnail in 5 seconds.
5. A beginner with Claude can build a launchable version in about 3 weeks.
6. Has a life after December 26.
7. Kid-safe: no guns, no blood, no death. This keeps the maturity label at Minimal/Mild, so the youngest (largest) audience can find it.
8. Not a recreation of one specific existing game.

---

## 4. The candidates

Ten ideas, short. Scored 1–5 on six things:
**Pull** (proven demand), **Fresh** (not what everyone else ships this December), **Solo** (fun with 1 player), **Build** (beginner-buildable), **After** (life after Christmas), **Clip** (makes moments people film for TikTok/YouTube Shorts).

| # | Idea | One line | Pull | Fresh | Solo | Build | After | Clip | Total |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Steal Santa's Sack | Plain steal-formula reskin: grab presents, run home, presents earn | 5 | 1 | 4 | 4 | 3 | 2 | 19 |
| 2 | Chimney Burglars | Slide down chimneys on Christmas Eve, rob houses without waking the family | 3 | 3 | 5 | 3 | 3 | 3 | 20 |
| **3** | **Rob Santa!** | **Steal from Santa's workshop past elf guards that can SEE you; disguise as a gift box; caught = Naughty Jail** | **5** | **4** | **5** | **3** | **4** | **5** | **26** |
| 4 | Naughty vs Nice | Cops vs robbers in a snowy town | 4 | 2 | 1 | 2 | 3 | 3 | 15 |
| 5 | Krampus Among Us | One thief hides among elves at a party, others find them | 4 | 2 | 1 | 3 | 2 | 3 | 15 |
| 6 | Trap the Burglars | Defend your house on Christmas Eve with slapstick traps vs waves of burglars | 4 | 4 | 5 | 2 | 3 | 4 | 22 |
| 7 | Elf Mafia Tycoon | Idle tycoon: run a candy-cane smuggling ring | 3 | 3 | 5 | 4 | 3 | 1 | 19 |
| 8 | Sleigh Getaway | Driving chase: escape the North Pole police on a stolen sleigh | 3 | 3 | 4 | 2 | 3 | 3 | 18 |
| 9 | Naughty Jail Escape | Obby: escape Santa's coal prison | 4 | 2 | 5 | 5 | 2 | 2 | 20 |
| 10 | Christmas Detective | Solve who stole the presents | 2 | 4 | 4 | 3 | 1 | 2 | 16 |

**What everyone else will ship this December:** "Steal a Christmas [thing]" reskins, Christmas tycoons, Santa obbies, holiday updates on big games. Idea 1 lands right in that crowd. Idea 3 uses the same proven skeleton but has three things the crowd won't have (next section).

---

## 5. The pick: Rob Santa!

> **Sneak into Santa's workshop, steal the presents, outrun the elf guards, and hide in plain sight by turning into a gift box.**

### The loop (30–90 seconds, repeated)
1. Leave your hideout and run into a workshop zone.
2. Sneak past elf guards. They have vision cones, which you can see on the floor.
3. Grab a wrapped present. You don't know what's inside.
4. **RUN.** Heavy presents slow you down. If an elf sees you, it chases.
5. In trouble? **Turn into a gift box** and freeze. The elf walks up, sniffs, stares... and if you don't move, it shrugs and leaves.
6. Get home. Unwrap: a toy pops out with a rarity (Common → Mythic) and sometimes a mutation (Frosted, Gingerbread, Glowing, Golden).
7. Put the toy on a shelf (it earns coins every second) or sell it at the Black Market.
8. Spend coins on faster boots, more shelves, more disguises. Unlock deeper zones with better loot and harder guards.

Caught? You go to **Naughty Jail** (a coal mine). Mine your way out, wait, or pay to leave.

### Why it wins
- **The proven skeleton.** Grab → chase → home → it earns. Players already know this loop from the #1 games, so they understand Rob Santa in seconds.
- **Three things the reskins won't have:**
  1. **Elves that see, not just chase.** Vision cones and line of sight make sneaking a skill. You can win by being smart, not only fast.
  2. **The gift-box disguise.** This is the signature moment: an elf sniffing a present while the player holds still. It's funny and tense, and it's the shot for TikTok, the thumbnail and the trailer.
  3. **Naughty Jail instead of dying.** Getting caught is a joke, not a punishment. That keeps the game kid-safe and gives you a second place to monetize (bail).
- **Christmas is the premise, not a skin.** Santa is the richest guy on Earth with a warehouse full of presents and elves for security. The heist writes itself.
- **Fun alone, better with friends.** Elves are NPCs, so 1 player works. Friends add co-op: one distracts the guard, the other grabs.
- **Built-in reasons to return:** Advent Calendar (a door per day to Christmas), toys earn while you're offline, the Sleigh Raid server event, a collection index.
- **Beginner-buildable.** One map. Players use their own avatars, so the only characters to make are elves (and Santa later). Guard AI is simple: walk a path, look, chase, give up.

### What makes it ours, not a copy
We share a *genre loop* with Steal An Egg and Steal a Brainrot. That's allowed and normal, the way every tycoon shares the tycoon loop. We do **not** copy their names, UI, art, map layouts, pets or characters. North Pole, elves with sight, the disguise, jail, the Sleigh Raid and the Most Wanted board are our own.

### Name
- Working title: **Rob Santa!** On Roblox: `[🎄] Rob Santa! 🎁`
- It's short, funny and searchable (players type "rob", "santa", "steal", "christmas").
- Backups: *Santa Heist*, *Naughty List Heist*, *Steal From Santa*.
- Before launch, search Roblox for existing "Rob Santa" games and check you're not walking into a name clash (step 8.2 in the build plan).

---

## 6. The backups (if you want a different direction)

**B — Trap the Burglars (22 points).** Christmas Eve. Burglars (NPC waves) try to break into your house. You set slapstick traps (paint-can swings, marble floors, ornament mines, snow cannons) and upgrade them. Tower defense in a house.
*Why it's second:* very clip-able and fun solo, but tower defense needs a lot of balancing and content (many traps, many enemy types) and is harder for a first game. It also sits close to a famous Christmas movie, so it needs care to stay original.

**C — Chimney Burglars (20 points).** Same thief fantasy as Rob Santa, but you rob family homes one at a time.
*Why it's third:* every house is a new level to design (more content work), and robbing kids' presents reads meaner than robbing Santa.

To switch, tell Claude: `Switch the plan to backup B` and it will rewrite 01-GAME-DESIGN.md and the build plan before any code.

---

## 7. After Christmas: the plan for January

Christmas is the launch theme, not the whole life of the game.

- **Dec 8 – Jan 4:** Rob Santa! Christmas season (launch + 3 updates).
- **Jan 5 decision**, based on the numbers (D1 retention, players online, Robux per day):
  - **Numbers good → "Rob the Holidays".** Every holiday adds a new vault to rob: Valentine's Chocolate Factory (Feb), Easter Bunny's Egg Vault (Apr), Summer Ice-Cream Truck, Halloween Candy Mansion (Oct), and back to Santa for Christmas 2027. Same loop and code, a new zone and new loot each season. Title becomes `[💘] Rob the Holidays!` and so on.
  - **Numbers weak → keep what you learned, start game #2 faster.** By then you'll know Studio, Luau and the Claude workflow, and your second game will take a third of the time.

---

## 8. Honest odds

- Most first Roblox games get very few players. That's the normal outcome, not failure.
- For comparison, the two thief games you scouted sit at 165–327 players online at once. Reaching that range would be a good first result.
- What moves the odds: launching on time (Dec 8), a strong thumbnail, a small ad budget to start the engine, and D1 retention above about 12%. That last one decides whether the algorithm keeps sending players.
- Treat Christmas 2026 as **ship + learn + earn something**. The design is built so a good result can keep growing all year.

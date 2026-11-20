# 01 — Game design: Rob Santa!

This is the source of truth for **what** the game is. Claude reads this before building any feature. If you change your mind about a rule, change it here first, then build.

All numbers are **starting values**. They live in one code file (`src/shared/ReplicatedStorage/Shared/Config.luau`), so you can tune them later without touching game logic.

---

## 1. The game in one breath

You're a thief at the North Pole. Sneak into Santa's workshop zones, grab wrapped presents, and run them back to your hideout while elf guards hunt you. Unwrap presents into toys. Toys on your shelves earn coins. Coins buy gear and open deeper zones, where the loot is better and the guards are smarter. Get caught and you land in Naughty Jail. Your escape trick: turn into a gift box and hold still.

```
   HIDEOUT ──run──▶ ZONE ──sneak──▶ GRAB ──RUN!──▶ HIDEOUT
      ▲                                │ seen?          │
      │                                ▼                ▼
   UPGRADE ◀── coins ◀── SHELF/SELL ◀── UNWRAP     [disguise or JAIL]
```

---

## 2. The map (North Pole)

One place, laid out as a line from safe to dangerous. The farther the zone, the better the loot and the longer the run home. That distance is the risk.

```
 [HIDEOUT ROW: 8 cabins, one per player]
                 │
          [TOWN SQUARE]  Black Market · Gadget Shop · Most Wanted board
                 │       Advent Calendar · Sleigh landing pad · Jail entrance
                 │
   ┌─────────────┼───────────────────────────────────────────────┐
   Zone 1        Zone 2          Zone 3            Zone 4            Zone 5
   Wrapping      Toy Factory     Candy Cane Mine   Reindeer Stables  Santa's Vault
   Room          (conveyors)     (dark tunnels)    (UPDATE 1)        (UPDATE 1)
   free          2,500 coins     25,000 coins      250,000 coins     2,500,000 coins
```

- **Hideouts:** 8 small cabins (max 8 players per server). Each player gets one when they join. Each has a **drop mat** (deliver presents here), an **unwrap table**, and **shelves** for toys.
- **Town Square:** safe zone. Guards never enter (except during the Sleigh Raid, section 9).
- **Zones** are gated by a candy-cane barrier that opens when you've bought the zone.
- **Naughty Jail:** a coal mine under the Town Square.

---

## 3. The core loop in detail

| Step | What happens | Rules |
|---|---|---|
| Grab | Walk to a present and hold the prompt | Uses a ProximityPrompt (works on phone, PC and console). Hold time: 0.5s Common, up to 2s Mythic |
| Carry | Present sits on your back | You can carry 1 (2 with Big Sack). You get slower depending on weight (table in section 6). You can't grab another while full |
| Run home | Get to your own hideout's drop mat | Presents dropped anywhere else return to their zone after 10s |
| Unwrap | 2-second unwrap animation on the table | Server rolls rarity and mutation. Big reveal popup, bigger for higher rarity |
| Display or sell | Put the toy on a free shelf, or sell it | Shelves earn coins every second. Selling pays a lump sum right away |
| Upgrade | Spend coins | Boots, Big Sack, more shelves, more disguises, Snowballs, zone unlocks |

Presents respawn on fixed spawn points in each zone every 20–40 seconds (random). Each zone has 4–8 spawn points.

---

## 4. The guards

The guards are what make this a heist instead of a shopping trip.

### Elf Guard (zones 1–3)
- **Patrol:** walks between waypoints in its zone at walk speed 8, pausing about a second at each one (like it's looking around). Several elves in one zone share its route, spread out along it.
- **Sight:** a vision cone (angle and range per zone, table below) plus a line-of-sight check (walls block sight). The cone is drawn on the floor as a soft translucent shape, so players can read it. This matters for kids and for phones.
- **Seeing you:** if you're in the cone, in line of sight and *not* a still gift box, a "!" pops over its head and it says "HEY!". Then it **chases**.
- **Chase:** runs at you (speed per zone) for up to 8 seconds. Gives up if it loses sight of you for 3 seconds, then walks back to patrol. After giving up it ignores you for 3 seconds, so you get a real window to get away (otherwise it re-spots you instantly).
- **Catch:** touching you while chasing = caught. You go to Naughty Jail, and the present you carried returns to its zone.

| Zone | Elf vision range | Vision angle | Chase speed | Elves |
|---|---|---|---|---|
| 1 Wrapping Room | 28 studs | 70° | 13 | 1–2 |
| 2 Toy Factory | 32 studs | 80° | 14 | 3 + 1 Snowman Camera |
| 3 Candy Cane Mine | 36 studs | 90° | 15 | 3 + 1 Head Elf + 2 Snowman Cameras |

Player walk speed is 16 (Roblox default). An empty-handed player outruns every elf. A player carrying a heavy present does **not**, and needs to break sight, use the disguise, or have upgraded boots. That is the whole risk/reward system in one rule.

### Snowman Camera (zone 2+)
A snowman with a lantern that slowly turns left and right (90° sweep over 4 seconds), range 40 studs, angle 50°. It doesn't move or chase. If it sees you, it **rings a bell**: every elf in the zone gets your position and chases for 5 seconds.

### Head Elf (zone 3)
Taller, faster (chase speed 17), and **inspects disguised presents for 5 seconds instead of 3**.

### Later (Update 1)
- **Reindeer** (zone 4): sleep in stalls; walking near wakes them; short fast charge (speed 24 for 2s).
- **Santa** (zone 5): asleep in a chair; a **Noise Meter** fills when players run, grab or ring bells. At 100% Santa wakes up and the whole vault goes on alarm for 20 seconds. Santa can't be fooled by the disguise.

---

## 5. Signature mechanic: the gift-box disguise

This is the moment the trailer, thumbnail and TikToks are built around. Spend polish here.

- **Use:** press Q (PC), the gift-box button (phone), or ButtonY (console).
- **Effect:** your avatar is hidden and replaced by a wrapped present the same size as zone presents. If you're carrying a present, it's hidden inside.
- **Wraps:** each disguise uses 1 Wrap. You start with 2 Wraps per trip, refilled when you touch your hideout. Upgrade to 3 and then 4.
- **Duration:** up to 6 seconds, then you pop out automatically. Moving cancels it right away.
- **Guards:** a guard on patrol ignores a still gift box. A guard **already chasing you** runs to the box and **inspects** it: stops, leans in, sniffs (3 seconds, 5 for the Head Elf). If you stay still the whole time, it says "...Huh. Just a present." and walks away, and the chase ends. If you move during the inspection: "GOTCHA!" and you're caught on the spot.
- **Cooldown:** 8 seconds after the disguise ends.
- **Feel:** a quick "wrap" pop (paper sound, ribbon spin) going in, a tense heartbeat sound during inspection, a confetti "phew" coming out. The inspection camera pushes in slightly. The elf's sniff animation is the comedy.

---

## 6. Presents, toys and money

### Rarity by zone (chance per present, %)

| Zone | Common | Uncommon | Rare | Epic | Legendary | Mythic |
|---|---|---|---|---|---|---|
| 1 Wrapping Room | 70 | 25 | 5 | 0 | 0 | 0 |
| 2 Toy Factory | 40 | 40 | 17 | 3 | 0 | 0 |
| 3 Candy Cane Mine | 0 | 35 | 40 | 20 | 5 | 0 |
| 4 Reindeer Stables (Update 1) | 0 | 0 | 40 | 40 | 18 | 2 |
| 5 Santa's Vault (Update 1) | 0 | 0 | 0 | 50 | 40 | 10 |

You can see a present's wrapping colour before you grab it. Better wrapping in the same zone means a better roll. The roll itself always happens on the server.

How this works in code (decided 2026-11-20, step 2.1): the wrapping **is** the rarity. The server rolls the rarity from the zone table when the present spawns, and colours the wrapping to match (docs/04: one wrapping colour per rarity). Hold time and carry slowdown come from that rarity. At unwrap the server picks which toy of that rarity you get (equal chance per toy) and rolls the mutation. Lucky Wrap moves the unwrap one rarity up.

### Rarity values

| Rarity | Coins/sec on shelf | Sell price | Carry slowdown | Example toys (original names) |
|---|---|---|---|---|
| Common | 1 | 45 | 0 | Wool Sock, Candy Cane, Rubber Duck |
| Uncommon | 4 | 180 | −1 | Teddy Bear, Yo-Yo, Toy Drum |
| Rare | 15 | 675 | −2 | Toy Train, Snow Globe, RC Sled |
| Epic | 60 | 2,700 | −3 | Robot Buddy, Rocket Skis, Dragon Kite |
| Legendary | 250 | 11,250 | −4 | Golden Rocking Horse, Crystal Nutcracker |
| Mythic | 1,000 | 45,000 | −5 | Star of the North, Santa's Pocket Watch |

Sell price = 45 seconds of shelf income. Keep good toys on shelves and sell the weak ones when shelves are full. That's the constant small decision.

Selling (step 2.3): a mutation multiplies the sell price too, since it multiplies income (a Golden Common sells for 45 × 5 = 225). Unwrapped toys wait on your unwrap table. From there you put one on your first free shelf (prompt), or sell everything on the table at the Black Market in the Town Square. Each shelved toy has its own Sell prompt.

### Mutations (rolled at unwrap, at most one)

| Mutation | Chance | Income × | Look |
|---|---|---|---|
| Frosted | 10% | ×1.5 | Icy blue tint + sparkle |
| Gingerbread | 5% | ×2 | Brown with icing trim |
| Glowing | 2% | ×3 | Neon outline + soft light |
| Golden | 0.5% | ×5 | Gold material + shine |

### Shelves
- Start with 4 shelves. Buy more, up to 20. Cost: `500 × 1.8^(shelves bought)`.
- Toys earn while you're offline, up to **2 hours** of income (4 hours with VIP). It's paid when you rejoin.

### Collection Index
- A book listing every toy × every mutation. Discovering a new entry pays a one-time coin bonus.
- Completing a zone's page gives a badge and a permanent +5% income.

---

## 7. Upgrades and gadgets

| Item | Effect | Cost (coins) |
|---|---|---|
| Boots (levels 1–6) | +1.5 walk speed per level (16 → 25) | 300, 900, 2.7K, 8K, 24K, 72K |
| Extra Wrap (levels 1–2) | 3, then 4 disguises per trip | 1,500, 15,000 |
| Quiet Steps (levels 1–3) | Elves notice you 10% later per level (shorter vision range against you) | 2K, 12K, 60K |
| Snowball | Throw at an elf: stunned for 3s (8s cooldown). Throw at a player carrying a present: they drop it | 5,000 |
| Big Sack | Carry 2 presents | Game pass (section 10) |

---

## 8. Naughty Jail

- Caught = a short "NAUGHTY!" stamp animation, then you're in a coal-mine cell.
- **Three ways out:** wait 20 seconds; **mine 8 coal lumps** (tap rocks) to leave early; or pay 15 Robux (**Bail Out**).
- Coal you mine is kept. Coal buys **Naughty gadgets** later and can open missed Advent Calendar doors.
- No coins are lost. You only lose the present you were carrying. Losing toys for getting caught would make kids quit.

---

## 9. Social and events

### Sleigh Raid (server event, every 12 minutes)
- A 10-second banner: "SANTA'S SLEIGH IS LANDING!" Then the sleigh lands on the Town Square pad with 6 premium presents (Rare or better) and 3 elves around it.
- For 60 seconds it's a free-for-all, and the Town Square is not safe during the raid.
- It gives players a reason to stay in the server ("next raid in 4:12" timer on screen).

### Most Wanted board
- A wanted poster in the Town Square shows the **richest thief in the server**, with their avatar and coin total.
- The Most Wanted player gets a red outline. Any player who hits them with a Snowball while they carry a present makes them drop it and earns a 10% coin bounty from the game. Nothing is taken from the target's coins.
- It's light PvP that works with 2 players and gives top players a status symbol.

### Hideout raids (Update 1, not at launch)
- Other players can walk into your hideout and steal a toy off your shelf, then run it to theirs (the steal-formula social layer).
- You can **lock your door** for 60 seconds (90-second cooldown).
- Left out of launch on purpose: with 1–3 players per server it adds little, and it's the hardest feature to make exploit-proof.

### Co-op
No special system needed. Friends naturally split roles (one distracts, one grabs). The Sleigh Raid rewards everyone who grabs, so friends don't compete for one prize.

---

## 10. Money (Robux)

Rule: **free players must have a complete, fair game.** Paid items save time or show off. Nothing makes free players lose.

### Game passes (one-time purchase)

| Pass | What | Starting price (R$) |
|---|---|---|
| VIP | ×2 coins forever, 4h offline cap, gold name tag | 199 |
| Big Sack | Carry 2 presents | 299 |
| Speed Boots | +4 walk speed on top of upgrades | 149 |
| Wrap Master | +2 disguises per trip, 4s faster cooldown | 99 |

### Developer products (buy again and again)

| Product | What | Starting price (R$) |
|---|---|---|
| Bail Out | Leave jail now | 15 |
| Lucky Wrap | Your next unwrap rolls one rarity higher | 39 |
| Blizzard | **Server-wide:** all elves half vision and slowed for 60s. Everyone benefits, and the buyer's name goes on a banner | 99 |
| Coin packs | Small / medium / large | 25 / 99 / 299 |
| Advent catch-up | Open a missed Advent door | 19 |

Server-wide purchases like Blizzard work well on Roblox: one player pays, the whole server cheers, and the buyer gets public credit.

**Lucky Wrap is a paid random item** (Robux changes a random roll). Roblox rules: show the odds on the purchase screen before buying, and hide the product for players in places where paid random items are restricted (the game checks this automatically through PolicyService).

Also: **private servers** at a small monthly price (set in Phase 8).

---

## 11. Reasons to come back

| Hook | How it works |
|---|---|
| **Advent Calendar** | A door opens each real day until Dec 25 (UTC). Day 25 = a guaranteed Mythic. Missed days can be opened with coal or Robux |
| Offline income | Shelves earn while you're away (cap above) |
| Daily login streak | Escalating coin reward for day 1–7; resets if a day is missed |
| Daily quests | 3 per day ("Steal 10 presents", "Survive 2 inspections", "Escape jail by mining") |
| Collection Index | Completion bonuses and badges |
| Updates | New zone Dec 18, Christmas Eve event Dec 24, New Year event Dec 31 |
| Rebirth (Update 3, New Year) | "New Year's Resolution": reset coins, zones and upgrades for a permanent +25% income per rebirth. Toys and Index are kept |

---

## 12. Controls

| Action | PC | Phone | Console |
|---|---|---|---|
| Move / jump | WASD / Space | Thumbstick / jump button | Left stick / A |
| Grab, deliver, unwrap | Hold E (prompt) | Tap and hold the prompt | Hold X (prompt) |
| Disguise | Q | Gift-box button (bottom right) | ButtonY |
| Snowball | F | Snowball button | ButtonB |
| Menus | Buttons on the left of the screen | Same | Same (selectable) |

Phone is the main platform. Test every action on the phone emulator before you call it done.

---

## 13. Screens and UI

- **HUD:** coins (top centre), carried present icon, Wraps left, disguise button, snowball button, next Sleigh Raid timer.
- **Unwrap reveal:** full-screen burst. The toy spins, rarity colour fills the screen, then the mutation stamp. Mythic gets a server-wide announcement.
- **Shop** (Gadget Shop counter in the Town Square, and a button), **Index**, **Advent Calendar**, **Jail screen** (timer + "mine coal" counter + Bail button), **Event banner**, **Robux store**.
- Style: chunky, rounded, high contrast, big icons, very little text. Colours in 04-CHARACTERS-AND-ART.md.

---

## 14. The first 3 minutes (tutorial)

New players decide in the first minute whether to stay, so this gets built properly in Phase 6.

1. Spawn in your hideout facing Zone 1. A glowing footprint trail leads to the first present. Text: "Steal Santa's presents!"
2. First present is a **guaranteed Rare** (sets up the first big unwrap).
3. On the way back, one slow elf spots you **on purpose**. The disguise button pulses: "Turn into a present! Don't move!" The elf inspects and leaves. The player learns the signature mechanic in the first 90 seconds.
4. Arrow to the drop mat → unwrap → big reveal → arrow to a shelf → "Your toy earns coins every second!"
5. Arrow to the Gadget Shop → buy Boots level 1 with the coins you were just given. The tutorial ends: "Deeper zones have better loot..."

Each step fires an analytics funnel event, so you can see where new players quit (07-LAUNCH-AND-GROWTH.md).

---

## 15. Content rating (keep it Minimal/Mild)

- No weapons that hurt. Snowballs stun or knock loot loose; nobody gets hurt.
- No blood, no death. Getting caught = jail with a comedy stamp.
- "Crime" is a cartoon caper. Answer the Maturity & Compliance questionnaire honestly (07-LAUNCH-AND-GROWTH.md).
- Chat uses Roblox's default filtered chat.

---

## 16. Not at launch (on purpose)

Hideout raids, Zones 4–5, Reindeer, Santa, Rebirth, trading, pets, vehicles, custom player outfits, voice lines. They come in updates or not at all. **Launching on Dec 8 matters more than any of these.**

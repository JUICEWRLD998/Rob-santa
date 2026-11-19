# 04 — Characters and art

How Rob Santa gets its characters, animations, props, look and sound. Most of the work happens in **Phase 5**, but skim this early so you know what's coming.

---

## 1. Good news: players bring their own characters

Every player uses **their own Roblox avatar**. You don't design or animate a player character at all. Walking, jumping and running animations come built in.

The characters **you** make are NPCs (non-player characters):

| Character | Needed by | Rig? | Notes |
|---|---|---|---|
| **Elf Guard** | Launch | R15 rig | The main enemy. Green uniform, red hat with bell, lantern. Most important character in the game |
| **Head Elf** | Launch (zone 3) | Same rig, scaled up | Taller, darker uniform, whistle |
| **Snowman Camera** | Launch (zone 2+) | **No rig** | Just a model that rotates. Easiest "guard" |
| **Black Market dealer** | Launch | R15 rig, stands still | A shady snowman or a raccoon in a scarf. Flavour only |
| **Santa** | Update 1 | R15 rig | Asleep in a chair; wakes up angry |
| **Reindeer** | Update 1 | Custom animal rig | Hardest one; that's why it's an update |

---

## 2. Three ways to make an NPC (fastest first)

### Way A — Generate it with Claude (try first)
The Studio MCP has a `generate_avatar` tool that creates a **rigged R15 avatar from a text description**. Ask Claude:

```
Use the Studio MCP to generate an R15 avatar: a short, chubby Christmas elf security guard,
green uniform with gold buttons, red pointy hat with a bell, holding a lantern,
friendly cartoon style, bright colours, simple shapes. Put it in ServerStorage/Templates as "ElfGuard".
Then take a screenshot so I can see it.
```

Look at the screenshot. Don't like it? Ask for changes ("rounder face", "bigger hat", "less detail"). Generate 3–4 versions and keep the best.

### Way B — Rig Builder + Creator Store clothes (reliable fallback)
1. **Avatar tab → Rig Builder → R15 → Block Rig** (or another body type). A plain character appears.
2. Dress it with free accessories from the **Toolbox** (search "elf hat", "elf ears", "lantern"). Drop each onto the rig.
3. Set skin colour with **Body Colors**, and scale it smaller (elves are short).
4. Claude can do all of this for you through the MCP (`search_asset`, `insert_asset`).

### Way C — Custom mesh in Blender (skip for launch)
Model a character in Blender, import it, and use **Avatar tab → Avatar Setup** to rig it. Best results, but a big learning curve. Save it for later games.

### Make the NPC actually work
Claude handles these, but you should know they exist:
- The model needs a **Humanoid** and a **HumanoidRootPart**, and must not be anchored.
- The server should own its physics (`SetNetworkOwner(nil)`) so it moves the same for everyone.
- Elves get their own **collision group** so they don't get stuck on each other.
- Each elf gets a **floor cone** (translucent shape showing where it can see).

---

## 3. Animations

| Animation | Who | How |
|---|---|---|
| Walk, run, idle | Elves | Copy the default **Animate** script from a player character (Claude can do this) |
| Look around, suspicious | Elf on patrol | Generate |
| **Sniff / inspect** (signature moment) | Elf inspecting a gift box | Generate, then polish. **This is the most important animation in the game** |
| Shrug "huh" | Elf leaving a gift box | Generate |
| "GOTCHA!" grab | Elf catching | Generate |
| Unwrap | Player at the unwrap table | Generate (short arm motion) or skip and animate the present instead |
| Mining coal | Player in jail | Generate (pickaxe swing) |

**Generate:** the MCP's `generate_animation` makes an R15 animation from text. Ask Claude:
```
Generate an R15 animation for the ElfGuard: leans forward, sniffs a present 3 times
with exaggerated head bobs, then pauses suspiciously. About 3 seconds, cartoon timing.
```

**Edit by hand:** **Avatar tab → Animation Editor**. Select a rig, add keyframes on a timeline, move body parts. Good for small fixes.

> **Beginner trap:** an animation only plays in your game if it's **published under the same owner as the game** (your account, or your Community if the game belongs to the Community). If an animation works in Studio but not in the live game, this is almost always why.

---

## 4. Props and the world

### Sources, in order of preference
1. **Built from parts by Claude** (MCP runs build code, or `generate_procedural_model`). Clean, light, and nothing hidden inside. Great for cabins, shelves, barriers, conveyors, candy canes, fences.
2. **Generated meshes** (MCP `generate_mesh`, or `/generate` in Studio's Assistant). Great for toys: "a cartoon teddy bear, simple shapes, bright colours, low detail".
3. **Generated materials** (MCP `generate_material`): candy-cane stripes, wrapping paper patterns, snowy wood.
4. **Creator Store / Toolbox models.** Big library, but see the safety rule below.

### Free model safety rule (important)
Some free models hide **malicious scripts** (backdoors that let strangers control your game, or spam). After inserting any Toolbox model:
- Ask Claude: `Search the model I just inserted for any Script, LocalScript or ModuleScript and list them.`
- Delete every script you didn't ask for. Props should have **zero** scripts.
- Prefer meshes and models from well-known creators with many favourites.

### Toys (what comes out of presents)
- 16 toys at launch (6 rarities, table in 01-GAME-DESIGN.md). Generate each as a mesh, keep them **simple and chunky**, and readable at small size.
- Mutations are visual layers on top of the same mesh (tint, material, outline, light), so 16 meshes give you 80 looks.
- Present wrappings: one present model with **colour/pattern per rarity** (Common = brown paper, Uncommon = green, Rare = blue, Epic = purple, Legendary = gold, Mythic = animated rainbow ribbon).

---

## 5. The look (art direction)

### The feeling
**"Cozy North Pole at night, and you're not supposed to be here."** Warm and inviting (Christmas), with a sneaky tension (crime). Cartoon, never realistic.

### Colours
| Use | Colour |
|---|---|
| Snow, ground | Soft blue-white |
| Night sky, shadows | Deep navy |
| Warm lights (windows, lanterns) | Orange-yellow glow |
| Candy-cane accents, danger, alarms | Red |
| Elves, trees | Pine green |
| Money, Legendary | Gold |
| Vision cones | Pale yellow at low opacity (like lantern light on snow) |

Warm light against cool blue snow is the whole palette. It makes screenshots pop and makes **the cones readable**.

### Lighting (Lighting service)
- Technology: **Future** (best lights). Drop to ShadowMap if phones struggle.
- Time: early night (ClockTime around 19–20) with moonlight, so lanterns and windows glow.
- **Atmosphere** for soft depth, light falling **snow particles**, a coloured skybox with stars.
- PointLights in windows and lanterns. Every zone gets a light colour of its own (Factory = warm orange, Mine = cold purple-blue, Vault = gold).

### Shapes
- Chunky, rounded, slightly oversized props (big candy canes, huge presents).
- Clear silhouettes: you should recognise an elf, a present and a door from far away on a phone.
- Few, big details instead of many small ones (better for phones, and looks less generated).

### UI style
- Rounded buttons with thick outlines and a slight drop shadow. Large icons. Very little text.
- Coin counter: gold coin icon + chunky number.
- Rarity colours used everywhere a toy appears (same colours as the wrappings).
- Font: a bold rounded font (Studio includes several, e.g. Fredoka One / Luckiest Guy style). Keep one font for headings and one for numbers.

---

## 6. Sound and music

| Moment | Sound |
|---|---|
| Grab | Paper rustle + "ding" |
| Spotted | "HEY!" + short alarm sting |
| Chase | Faster music layer kicks in |
| Disguise in | Wrapping-paper "fwip" + ribbon twinkle |
| Inspection | Heartbeat + sniff sounds |
| Inspection passed | Relieved "phew" + soft chime |
| Caught | Whistle + "NAUGHTY!" stamp |
| Unwrap | Drumroll → reveal fanfare (bigger per rarity) |
| Coins | Soft coin clinks |
| Sleigh Raid | Sleigh bells + horn |

- Use audio from the **Creator Store** only (it's licensed for Roblox). **Never upload copyrighted songs or recordings.** Roblox removes them and it can hurt your account.
- Music: one calm sneaky jingle for exploring, one faster version for chases, one festive tune for the Town Square.

---

## 7. Performance (phones first)

- Keep the part count low. Merge decorative parts or use meshes.
- Turn on **StreamingEnabled** (Workspace property) so phones only load what's near the player.
- Prefer few strong lights over many small ones.
- Test in the device emulator and on your real phone. If it stutters, ask Claude: `Find what makes the game slow on phones and fix it.`

---

## 8. Icon and thumbnails

These decide whether anyone clicks. Full launch details in 07-LAUNCH-AND-GROWTH.md. The rules:
- **Icon:** one elf's surprised face looking at a gift box (with eyes peeking out of it). Bright, simple, readable at tiny size.
- **Main thumbnail:** the signature moment. An elf sniffing a gift box in a glowing workshop, a player's eyes peeking out, big text "DON'T MOVE!".
- Make them from real in-game screenshots (Claude can pose the scene and capture it), then add text and touch-ups.

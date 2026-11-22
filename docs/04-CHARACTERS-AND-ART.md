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

What was built in step 5.3:
- **Elf Guard** = generated Option A (slim elf, red pointy hat with a bell, white collar), plus a brass lantern with a warm light welded to its right hand. `ServerStorage/Templates/ElfGuard`. The other generated options (B, B (1), C) and the old 3.1 placeholder are kept in `ServerStorage/CharacterOptions`. To swap in another option, copy it into Templates as `ElfGuard`, then move `Head/Alert` and `Head/AlertSound` from the current elf into its Head.
- **Head Elf** = the same elf with a darker uniform (SurfaceAppearance tint on clothing parts only), a silver whistle on a red cord, and the lantern. `Templates/HeadElf`, scaled 1.3x by the code. If that template is missing, the code falls back to the plain elf with a gold hat.
- **Snowman Camera** is built in code (GuardService `buildSnowman`), so it stays on disk. It now has a hat brim and red band, a striped scarf, coal buttons, stick arms, and a small security camera on its hat. The camera's red light flares while the bell rings.
- **Black Market dealer** = a generated R15 raccoon-style merchant (the owner's pick of two), beside the stall at `Workspace/Map/Town/BlackMarketDealer`. Its root is anchored. It's tagged `IdleNpc`, so NpcService loops Roblox's default idle on it instead of a T-pose. The other generated dealer and the parts-snowman dealer are in `ServerStorage/CharacterOptions`.
- **Jail pickaxe:** JailService welds a pickaxe made from plain parts to your right hand while you're in the cell, and removes it when you're let out. It isn't a Tool, so it can't be dropped or carried out of jail.
- **Animations**, all published under the game owner's account, IDs in `Config.Animations`: look around (about half the waypoint stops; the stop lasts as long as the look), sniff (loops for the whole sniff), shrug (after "...Huh. Just a present."), GOTCHA grab (on any catch, then back to patrol), and the player's pickaxe swing (while holding Mine on a coal rock; loaded when you enter jail). The editable clips are in `ServerStorage/RBX_ASSISTANT_ANIMGEN`. The generated clips run 3–9 s, so each has a `seconds` cut-off and a `speed`.

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

What was built in step 5.4:
- **16 toy meshes**, made with the MCP `generate_mesh` (one textured MeshPart each, 2,000–3,000 triangles, sized so the longest side is 1.8 studs). They live in `ServerStorage/ToyMeshes/<toy id>`; the `Source` attribute holds the prompt each one came from. `Lib/ToyModel` puts the mesh on the toy. Mutations take the texture off and paint the whole shape: Frosted ice, Gingerbread brown with a white icing outline, Glowing neon, Golden foil. A toy with no mesh still falls back to the old coloured ball.
- **Wrapping per rarity** (`Config.Wrapping`): Common is kraft cardboard with fabric twine, Uncommon green fabric, Rare smooth blue, Epic purple foil, Legendary gold foil with sparkles, and Mythic pink foil with sparkles and a neon ribbon. The ribbon cycles through the rainbow on each player's screen (`PresentFxController`). Mythic presents only spawn from Update 1 (zones 4–5).

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

What was set in step 5.1 (place file; tune by eye in Studio): ClockTime 19.8, Brightness 2.2, Ambient 80,90,130, OutdoorAmbient 130,145,190 (raised after the owner found it too dark without Future lighting; phones fall back from Future too), moon top light 150,170,230, Exposure 0.2, the default sky with 3,000 stars and a bigger moon (16). Every DropMat is green Neon with a soft light, so your base reads at night. Atmosphere: Density 0.32, Haze 1.2, navy blue colour. Bloom 0.6 (threshold 1.8), SunRays off, a NightGrade colour correction (slightly cooler, +12% saturation). Lights live in `Workspace/Map/Lights`: a warm orange glow in each cabin, 8 lantern posts in the Town Square, 4 lights per zone (Zone 1 soft warm white, the Wrapping Room's own colour and my pick; Zone 2 warm orange; Zone 3 purple-blue) and one in each corridor. Light parts are invisible and have CanQuery off, so they never block elf vision or prompts. Snow: `SnowController` on each client, numbers in `Config.Snow`, off underground. **Technology = Future must be set by hand** (Lighting → Properties): Studio's MCP can't read or write that property.

What was built in step 5.2 (place file, all from plain parts, zero scripts): each area got a `Decor` model on top of the greybox. Gameplay parts kept their position and size; only their colour and material changed. The elf waypoint and present spawn markers are now invisible. Decor parts never block raycasts, prompts or touches. Only the tree base, the gifts under it and the cane bottoms are solid. The areas:
- **Cabins:** log planks, snow on the wall tops, warm orange windows, chimney smoke, string bulbs, velvet shelf pads, a wooden unwrap bench.
- **Town Square:** snowy cobbles, a low-poly Christmas tree with ornaments, a star and gifts. The Gadget Shop and Black Market got striped awnings and signs. Also a stone jail hut with a barred door, framed Most Wanted and Advent boards, a candy-stripe sleigh pad, snow drifts and candy canes.
- **Wrapping Room:** red fabric walls with garlands and bulbs, a wooden floor, wrapping counters with paper rolls, giant gift boxes as cover.
- **Toy Factory:** brick walls, a diamond-plate floor, conveyor belts carrying toys, red toy machines with gears and steam, hazard stripes.
- **Candy Cane Mine:** rock walls with wooden supports, candy-striped boulders, glowing crystals, giant candy canes.
- **Naughty Jail:** a rock mine with beams, lanterns, coal piles and a Naughty List sign.

### Shapes
- Chunky, rounded, slightly oversized props (big candy canes, huge presents).
- Clear silhouettes: you should recognise an elf, a present and a door from far away on a phone.
- Few, big details instead of many small ones (better for phones, and looks less generated).

### UI style
- Rounded buttons with thick outlines and a slight drop shadow. Large icons. Very little text.
- Coin counter: gold coin icon + chunky number.
- Rarity colours used everywhere a toy appears (same colours as the wrappings).
- Font: a bold rounded font (Studio includes several, e.g. Fredoka One / Luckiest Guy style). Keep one font for headings and one for numbers.

What was built in step 5.5 (place file + RevealController):
- **Fonts:** Fredoka One for headings and words, Luckiest Guy for every number (coins, wraps, timers, prices, the Index bonus). Close buttons stay in Fredoka One, because Luckiest Guy's "X" reads as a blob.
- **Buttons and panels:** 4 px outlines, rounded corners, and a soft drop shadow under each pill, button and panel. The shadow is a `DropShadow` frame one ZIndex below its parent. Every ScreenGui uses ZIndexBehavior Global.
- **Icons instead of words:** a gold coin built from frames (the 🪙 emoji does not render in Roblox), 🎁 next to the wraps count, and 🛒 / 📖 on the SHOP and INDEX buttons with one short word under each.
- **Unwrap reveal** (docs/01 section 13): the rarity colour floods the screen, the toy's mesh pops up and spins, confetti bursts out, and a mutation is stamped on with a slam. It all grows with rarity: more colour, more confetti (10 pieces per tier) and a longer hold. Light rays spin from Rare up, and a white flash goes off from Legendary up. The numbers are in `Config.Reveal`. Toy meshes reach the client through `ReplicatedStorage/ToyMeshes`, which the server copies at boot.
- **Phones and tablets** (checked on a Galaxy A06, 705×338, and an iPad 10th gen):
  - The SHOP and INDEX buttons are 72 px, anchored top-left. Before this change, SHOP overlapped the thumbstick on the A06 by 1 px.
  - The Shop and Index panels leave 115 px free on each side, so the thumbstick and jump button stay uncovered.
  - The reveal card shrinks on short screens (`Config.Reveal.CardFitHeight`).
  - The Wrap! button sits just left of the jump button on every device. The jump button is 70 px on phones and 120 px on tablets, and a fixed spot overlapped it on the iPad.

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

What was built in step 5.6. All audio comes from the two libraries Roblox licenses for every game: APM Music and Pro Sound Effects. The Sounds are in `SoundService/Sfx` and `SoundService/Music` in the place file; each has a `Source` attribute that names its track. To swap a sound, change its SoundId and keep the name. `SoundController` (client) plays them, and the numbers are in `Config.Audio`.

| Moment | What plays | Notes |
|---|---|---|
| Grab | paper rustle, then a high chime "ding" | |
| Spotted | alarm sting; the elf's own AlertSound still plays at the elf | |
| Chase | Chase music fades in; it fades out 1.5 s after the last elf gives up | the server sets the `ChasedBy` player attribute |
| Disguise in | whoosh "fwip" + the chime, high and quiet (the ribbon twinkle) | |
| Inspection | heartbeat loop + a sniff every 1.6 s | |
| Inspection passed | soft chime | no "phew" voice in the licensed libraries yet |
| Caught | whistle, then a stamp thud | |
| Unwrap | drumroll while the present spins, then a fanfare: chime for Common and Uncommon, "Winner" for Rare and Epic, "Top Prize" for Legendary and Mythic, louder per tier; a thud when a mutation is stamped | the server sets the `Unwrapping` player attribute |
| Coins | coin clinks when coins jump (a sale or a bonus), never on the per-second income | |
| Sleigh Raid | not yet; the raid itself is built in Phase 6 | |

Music: **Town** (festive, outside the zones), **Explore** (sneaky, inside any `ZoneArea` box and in the jail), **Chase**. They crossfade over 1.5 s.

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

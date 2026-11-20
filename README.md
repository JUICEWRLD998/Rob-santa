# Rob Santa! (working title)

Plan for your first Roblox game, from idea to launch. You build it by vibecoding with Claude Code, one step at a time.

> **The pitch:** Sneak into Santa's workshop, steal the presents, outrun the elf guards, and hide in plain sight by turning into a gift box.

---

## Read in this order

| # | File | What it gives you | When |
|---|---|---|---|
| 1 | [docs/00-IDEA.md](docs/00-IDEA.md) | How the idea was chosen: market evidence, 10 candidates, scores, the pick, two backups | Today |
| 2 | [docs/01-GAME-DESIGN.md](docs/01-GAME-DESIGN.md) | The full game design: loop, map, elves, disguise, loot, economy, money, events | Today |
| 3 | [docs/03-ROBLOX-101.md](docs/03-ROBLOX-101.md) | Roblox concepts for a total beginner. Short, and you need it | Before Phase 0 |
| 4 | [docs/02-SETUP.md](docs/02-SETUP.md) | Install Studio, connect Claude Code to Studio, sync code to this folder | Phase 0 |
| 5 | [docs/06-VIBECODING-WITH-CLAUDE.md](docs/06-VIBECODING-WITH-CLAUDE.md) | How to work with Claude: the loop, prompt templates, rules | Phase 0 |
| 6 | [docs/05-BUILD-PLAN.md](docs/05-BUILD-PLAN.md) | The build itself: 10 phases, exact prompts, "done when" checks | Every session |
| 7 | [docs/04-CHARACTERS-AND-ART.md](docs/04-CHARACTERS-AND-ART.md) | NPC characters, animations, props, the look, sound | Phase 5 (skim earlier) |
| 8 | [docs/07-LAUNCH-AND-GROWTH.md](docs/07-LAUNCH-AND-GROWTH.md) | Publishing, the maturity questionnaire, page, ads, metrics, updates, money | Phase 0 (one step) and Phase 8 |

`CLAUDE.md` in this folder holds the rules Claude follows in every session. You don't need to edit it.

---

## Key dates

| Date | What |
|---|---|
| Thu 2026-11-19 | Plan written (today) |
| Fri 2026-11-20 | Phase 0: setup |
| **Wed 2026-12-02** | **Account turns 30 days old (joined 2026-11-02): fill in the Maturity & Compliance questionnaire that day** (07-LAUNCH-AND-GROWTH.md, section 2) |
| Sun 2026-12-06 | Questionnaire label still not showing? Contact Roblox Support that day |
| **Tue 2026-12-08** | **Public launch** (gives the algorithm about 10 days before school holidays start) |
| Fri 2026-12-18 | Update 1: Santa's Vault + hideout raids |
| Thu 2026-12-24 | Update 2: Christmas Eve event |
| Thu 2026-12-31 | Update 3: New Year |
| Mon 2027-01-05 | Decide what comes after Christmas (see 00-IDEA.md, section 7) |

**The seasonal rule:** a Christmas game that launches on December 22 has missed Christmas. If you fall behind, cut features (cut list in 05-BUILD-PLAN.md), not the date. Hard stop: launch by **Tue 2026-12-15** with whatever works.

---

## Progress

Tick these as you go. Claude reads this list to know where you are.

- [x] Phase 0: Setup (Studio installed, Claude connected, code syncing, git)
- [x] Phase 1: Greybox world (map blocked out, hideouts, zones)
- [ ] Phase 2: Core loop (grab, carry, run home, unwrap, display, sell)
- [ ] Phase 3: Elves, jail and the gift-box disguise
- [ ] Phase 4: Saving, upgrades, zones 2 and 3, rarities, index
- [ ] Phase 5: The look (art, characters, animations, UI, sound)
- [ ] Phase 6: Money and reasons to return (passes, advent calendar, Sleigh Raid, tutorial)
- [ ] Phase 7: Test and harden (multiplayer, phone, exploits, friends)
- [ ] Phase 8: Launch
- [ ] Phase 9: Live updates through New Year

---

## How to start every work session

1. Open Roblox Studio and open the **Rob Santa (dev)** place.
2. Open a terminal in this folder (`C:\Users\fadhm\Desktop\rob-santa`) and run `claude`.
3. Paste:

```
Read CLAUDE.md, README.md (progress list) and docs/05-BUILD-PLAN.md.
We are on Phase <N>, step <N.x>. Check that the Roblox Studio MCP is connected, then let's do this step.
```

4. When a step works, say `commit this`. When a phase is done, tick it above.

## Folder layout

```
rob-santa/
  README.md        this file
  CLAUDE.md        rules for Claude in this project
  docs/            the plan (00 to 07)
  src/             game code, synced into Studio by Script Sync (created in Phase 0)
    server/        -> ServerScriptService/Server
    client/        -> StarterPlayer/StarterPlayerScripts/Client
    shared/        -> ReplicatedStorage/Shared
  places/          backup copies of the .rbxl place file (created in Phase 0)
```

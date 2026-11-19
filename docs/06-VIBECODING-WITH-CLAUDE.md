# 06 — Vibecoding with Claude

How to build a whole Roblox game by talking to Claude, without writing code yourself, and without ending up with a mess you can't fix.

---

## 1. Who does what

| Claude does | You do |
|---|---|
| Writes all code (`src/`, synced into Studio) | Decide what the game is and how it should feel |
| Builds and edits the world through the Studio MCP | Press Play and **judge if it's fun** |
| Generates characters, animations, meshes, materials | Pick between options, say what's wrong |
| Starts playtests, reads Output, takes screenshots, moves the test character | Multi-player tests (Local Server), phone tests, friend tests |
| Explains what it changed, in plain words | Say "commit this" when something works |
| Fixes errors | Create game passes/products, fill in the questionnaire, publish, spend money |

Claude never publishes the game, changes its public settings or spends money. Those are yours (rule in CLAUDE.md).

---

## 2. Before every session

1. Studio open, **Rob Santa (dev)** place open (not the start page).
2. Assistant → … → Manage MCP Servers shows a green dot (after you start Claude).
3. Terminal in `C:\Users\fadhm\Desktop\rob-santa`, run `claude`.
4. Paste the session starter:

```
Read CLAUDE.md, README.md (progress list) and docs/05-BUILD-PLAN.md.
We are on Phase <N>, step <N.x>. Check that the Roblox Studio MCP is connected, then let's do this step.
```

---

## 3. The loop (for every single step)

```
 1. ASK      paste the step's prompt from 05-BUILD-PLAN.md
 2. PLAN     for big steps, Claude says what it will do (you can say "go" or adjust)
 3. BUILD    Claude writes code / builds in Studio
 4. SELF-TEST Claude playtests through the MCP, reads Output, screenshots
 5. YOU PLAY you press Play and try it like a player would
 6. VERDICT  works → "commit this" | broken → describe + paste error | meh → say what feels wrong
```

The most valuable thing you bring is step 5. Claude can check that code *runs*. Only you can tell if it's *fun*.

---

## 4. Prompt templates

### A new feature
```
Build <feature> per docs/01-GAME-DESIGN.md section <N>.
Before coding, tell me in 5 lines what you'll create and which files change. Then build it and test it.
```

### A bug
```
Bug: <what I did> → I expected <X> → but <Y> happened.
Output says: <paste the red error line, if any>
Find the root cause first, explain it in one or two lines, then fix it.
```

### A feeling ("tuning")
```
<thing> feels <too easy / too slow / unfair / boring>.
What I want: <how it should feel>. Change the numbers in Config first; only change code if numbers can't do it.
```

### Explain it to me
```
Explain how <system> works like I'm new to Roblox: which scripts, what talks to what, and what
the server checks. Max 10 lines.
```

### Visual work
```
Make <area/thing> look like docs/04-CHARACTERS-AND-ART.md describes. Show me 2-3 options as
screenshots before you commit to one.
```

### Big feature: use Plan Mode
Press **Shift+Tab** in Claude Code to switch to Plan Mode for big steps (guards, saving, monetization). Claude writes a plan without touching anything. You read it, then approve.

---

## 5. Rules that keep the project healthy

1. **One step per message.** Two features at once = twice the bugs and no idea which one broke.
2. **Commit after every working step** (`commit this`). Commits are your undo button.
3. **Never let the same bug go 3 rounds.** On the 3rd try say: `Stop. Find the root cause before changing anything else.`
4. **Numbers live in Config.** If you say "make elves slower", the change should be one number in `src/shared/Config.luau`.
5. **Save the place** after world changes. Claude can do it through the MCP (`save the place`). Scripts are safe on disk; parts and models only live in the place file.
6. **Fresh context between phases.** Type `/clear` when you start a new phase; the docs and CLAUDE.md bring Claude back up to speed.
7. **Keep README progress ticked.** Claude reads it to know where you are.
8. **Don't paste random code from YouTube or forums.** Describe what you saw instead, and let Claude build it to fit our structure.
9. **Close places you don't want touched.** The MCP can edit any open place.

---

## 6. When Claude gets it wrong

| Symptom | Say |
|---|---|
| It changed a lot more than you asked | `Undo everything since the last commit.` |
| It says "fixed" but it isn't | `Show me proof: playtest it, read the Output, and screenshot the result.` |
| It keeps adding features | `Only do what the step says. Nothing extra.` |
| You don't understand what it did | `Explain the change in 3 plain lines.` |
| It seems confused about the project | `/clear`, then the session starter again |
| Something worked yesterday, broken today | `Compare with the last commit where it worked and find what changed.` |

---

## 7. What Claude can see through the MCP

Useful to know what to ask for:

| Ask | Claude uses |
|---|---|
| "Test it" | Starts Play, reads console output, stops |
| "Show me" | Screenshot of the Studio viewport |
| "Walk to Zone 2 and grab a present" | Moves the test character and simulates keys |
| "What's in the map?" | Searches the Explorer tree, inspects parts |
| "Find a free sleigh model" | Searches the Creator Store, inserts by ID |
| "Make an elf / a teddy bear / a sniff animation" | Generates an avatar / mesh / animation |
| "Save the place" | Saves without dialogs |

It **can't** feel the game, test on your phone, or run 3-player tests by itself. Those are yours.

---

## 8. Learning as you go (optional, but it compounds)

You'll get faster if you understand a bit more each week. Cheap ways:
- After each phase: `Teach me the 3 most important things you used in this phase, with a tiny example each.`
- Open one script a day and ask Claude to walk you through it line by line.
- By January you'll be able to read most of the code, and game #2 will go much faster.

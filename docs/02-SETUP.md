# 02 — Setup (Phase 0)

Goal: by the end of this file, Claude Code can **see and change your game in Roblox Studio**, and the game's code lives in this folder, where Claude edits it and git saves every version.

Time: 1–2 hours. Do the steps in order. Each step ends with a **Check** so you know it worked.

What this machine has today (checked 2026-11-19): git 2.50.1, Claude Code 2.1.328. **Roblox Studio is not installed yet.**

---

## Step 1 — Your Roblox account

1. Log in at roblox.com with the account that will **own** the game.
2. Account age: **the account must be at least 30 days old** to fill in the Maturity & Compliance questionnaire. Without that questionnaire, Roblox treats the game as "Moderate" and won't recommend it to younger players, who are most of your audience.
   - **Your account joined 2026-11-02, so it's eligible from Wed 2026-12-02.** Use this account. Don't borrow anyone else's: the owner account receives the Robux.
   - Everything before Dec 2 (building, private testing) works normally. Only the questionnaire waits.
3. Turn on **2-Step Verification** (Settings → Security). You're about to hold real money in this account.
4. Optional but smart: create a **Community** (group) to own the game. Groups make it easier to add a teammate, split revenue, or sell or transfer the game later. Creating one costs Robux; check the current fee on the Create Community page. If you skip this, publish under your own account. It still works.

**Check:** you know the account's join date, and 2-Step Verification is on.

---

## Step 2 — Install Roblox Studio

1. Go to **create.roblox.com** and click the button to start creating / download Studio.
2. Run the installer and log in with the account from Step 1.
3. Studio opens on a start page with templates.

**Check:** Studio opens and shows your username at the top right.

---

## Step 3 — A 5-minute tour of Studio

Open the **Baseplate** template (a flat grey world). Find these panels. If one is missing, open it from the **View** menu or tab.

| Panel | What it is |
|---|---|
| **Viewport** | The 3D world in the middle. Right-click + drag to look, WASD to fly, scroll to zoom |
| **Explorer** | The tree of everything in the game (Workspace, ServerScriptService...). Read 03-ROBLOX-101.md for what each part is |
| **Properties** | Settings of whatever you selected (size, colour, position...) |
| **Output** | Messages and **errors**. Keep it open, always. When something breaks, the answer is usually here |
| **Toolbox** | The Creator Store: free models, meshes, sounds |
| **Assistant** | Roblox's built-in AI chat. You'll use it once, to switch on the connection for Claude |
| **Test tab** | **Play** (test as a player), **Stop**, and multi-player testing (Clients and Servers) |

Try it: click **Play**, walk around with WASD, then click **Stop**. Everything you do during Play is thrown away when you stop. That's normal.

**Check:** you can Play and Stop, and you can see the Output panel.

---

## Step 4 — Create and publish the dev place

1. From the start page, create a new **Baseplate**.
2. **File → Publish to Roblox**. Create a new experience:
   - Name: `Rob Santa (dev)`
   - Owner: your account (or your Community from Step 1)
   - Leave it **private**. Nobody can play it until you choose to launch.
3. Open **Game Settings** (Home tab) → **Security** → turn on **Enable Studio Access to API Services**. Saving player data in tests needs this. Save.
4. Also in Game Settings → **Places/Server settings**: max players **8**. If you can't find it now, do it in Phase 8.
5. Make the backup folder: in Windows, create `C:\Users\fadhm\Desktop\rob-santa\places`.
6. **File → Save to File As…** → `C:\Users\fadhm\Desktop\rob-santa\places\RobSanta.rbxl`.

From now on, **Ctrl+S / File → Save to Roblox** saves the cloud version, and Roblox keeps version history. Save a local `.rbxl` copy into `places\` at the end of each phase.

**Check:** the experience shows up in **Creator Hub → Creations** as private.

---

## Step 5 — Connect Claude Code to Studio (the important one)

Roblox Studio has a **built-in MCP server**. MCP is the plug that lets Claude Code talk to Studio directly. Once connected, Claude can:
- read and edit scripts in your place,
- build and move things in the world (it runs Luau code in Studio),
- generate 3D meshes, materials, **rigged R15 characters** and **animations** from a text description,
- search and insert Creator Store assets,
- **start and stop playtests, read the Output, take screenshots, and move the test character**, so it can test its own work,
- save the place.

> **Security note (from Roblox's docs):** MCP clients can read and modify content in your open Roblox places. Only connect clients you trust, and close any place you don't want Claude to touch.

### 5a. Turn the server on in Studio
1. Open the **Assistant** panel.
2. Click **… → Manage MCP Servers**.
3. Turn on **Enable Studio as MCP server**.

### 5b. Quick-connect Claude Code (try this first)
1. In **Assistant Settings → MCP Servers**, open the **Quick connect** dropdown.
2. Turn on **Claude Code**. (If it's not listed: Claude Code must be installed, which it is. Restart Studio and look again.)
3. Close and reopen any running Claude Code terminal.

### 5c. Manual connect (only if 5b didn't work)
Open a terminal and run this once:

```
claude mcp add --scope user Roblox_Studio -- cmd.exe /c "%LOCALAPPDATA%\Roblox\mcp.bat"
```

`--scope user` makes it work from every folder. The `mcp.bat` file is created by Studio when you turn the server on in 5a. If the command complains, check that this file exists: `C:\Users\fadhm\AppData\Local\Roblox\mcp.bat`.

### 5d. Check it works
1. In Studio: **Assistant → … → Manage MCP Servers**. A **green dot** under "Enable Studio as MCP server" means a client is connected.
2. In a terminal in `C:\Users\fadhm\Desktop\rob-santa`, run `claude`, then type `/mcp`. You should see the Roblox Studio server listed as connected.
3. Ask Claude:
   ```
   Using the Roblox Studio MCP, create a bright red anchored part named HelloPart, size 4x4x4, at position 0, 10, 0 in Workspace. Then take a screenshot of the viewport.
   ```
   The red cube should appear in Studio.
4. Ask Claude to delete HelloPart.

**If it fails:** restart both Studio and Claude Code. Make sure the place is open in Studio (not just the start page).

**Check:** Claude made a red cube appear in your Studio window.

---

## Step 6 — Script Sync: code lives in this folder

Script Sync keeps scripts in Studio mirrored as `.luau` text files on disk, in both directions. Claude edits the files, and Studio updates by itself. Git can then save every version of your code.

### 6a. Make three folders in Studio (Explorer panel)
Hover the service, click **+**, and insert a **Folder**. Rename each:

| In Studio | Folder name |
|---|---|
| ServerScriptService | `Server` |
| ReplicatedStorage | `Shared` |
| StarterPlayer → StarterPlayerScripts | `Client` |

### 6b. Make the matching folders on disk
Create these (empty) folders in Windows:
```
C:\Users\fadhm\Desktop\rob-santa\src\server
C:\Users\fadhm\Desktop\rob-santa\src\shared
C:\Users\fadhm\Desktop\rob-santa\src\client
```

### 6c. Connect each pair
For each Studio folder: right-click it → **Script Sync → Sync with Directory…** → pick the matching disk folder → **Save**.

Then open **Studio Settings** (Alt+S), search "sync", and turn on **Auto resume sync on place open**.

### 6d. Test it
Ask Claude:
```
Create src/server/ServerScriptService/Server/Hello.server.luau that prints "Hello from the server!" when the game starts. Then start a playtest with the MCP, read the console output, stop the playtest, and tell me if the message appeared.
```
You should see `Hello` appear under ServerScriptService → Server in Explorer, and the message in Output.

### File name rules (Claude knows these; this is for you)

| File on disk | Becomes in Studio |
|---|---|
| `Name.luau` | ModuleScript (shared code that other scripts load) |
| `Name.server.luau` | Script (runs on the server) |
| `Name.local.luau` | LocalScript (runs on each player's device) |
| `Folder/` | Folder |

### Script Sync rules
- Only **scripts and folders** sync. Parts, models, UI and sounds do **not**. They live in the place file (cloud + your `places\` backup).
- **Never put attributes or tags on a script.** Script Sync ignores them and you can lose data. (Attributes and tags on *parts* are fine.)
- Don't put non-script things (parts, models) inside the three synced folders.

**Check:** Claude created a file, it showed up in Studio, and the playtest printed the message.

---

## Step 7 — Git (save points for your code)

In a terminal in `C:\Users\fadhm\Desktop\rob-santa`:

```
git init
git add -A
git commit -m "Plan and setup"
```

From now on just tell Claude `commit this` after each thing that works. If something breaks badly later, Claude can return the code to any earlier commit.

Optional: push to a **private** GitHub repo for an off-machine backup. Ask Claude to walk you through it.

**Check:** `git log` shows your first commit.

---

## Step 8 — Optional comfort tools

- **VS Code** with the **Luau Language Server** extension (`JohnnyMorganz.luau-lsp`) and its Studio companion plugin. This is for when you want to read the code with colours and hints. Claude doesn't need it.
- **Roblox app on your phone**, logged into the same account. As the owner you can play your private game on your phone. This is the only true phone test.

---

## Step 9 — Do the questionnaire early

Your account becomes eligible on **Wed 2026-12-02**. Fill in the **Maturity & Compliance questionnaire** for `Rob Santa (dev)` that day (steps in 07-LAUNCH-AND-GROWTH.md, section 2). If Studio or Creator Hub still says the account is too young, try again on Dec 3. Answers can be updated later. Skip this step in Phase 0.

---

## Phase 0 done when

- [ ] Account checked (age, 2-Step Verification)
- [ ] Studio installed, tour done
- [ ] `Rob Santa (dev)` published as private, API access on, backup saved in `places\`
- [ ] Claude made a cube appear through the MCP
- [ ] Script Sync: a file Claude wrote ran in a playtest
- [ ] First git commit made

Tick **Phase 0** in README.md and move to Phase 1 in 05-BUILD-PLAN.md.

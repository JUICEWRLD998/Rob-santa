--!strict
-- The Daily screen (step 6.3): login streak, today's 3 quests and the Advent Calendar.
-- Opens from the DAILY button (top-right corner) or the "Advent Calendar" prompt on the Town
-- board. DailyGui and HudGui.DailyButton live in the place file; this fills them from DailySync.
-- Display only: DailyService decides every door, streak payment and quest. A door click only asks
-- (RequestAdventDoor); a missed door shows two choices, coal or Robux.

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local StoreCatalog = require(Shared:WaitForChild("StoreCatalog"))

local GUI_WAIT_SECONDS = 15
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POP_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_FROM_SCALE = 0.85
local MAX_MESSAGE_LENGTH = 120
local ROBUX = utf8.char(0xE002)
local MONTH_NAME = "December"

local MUTED_TEXT = Color3.fromRGB(200, 210, 230)
local GOOD_TEXT = Color3.fromRGB(120, 230, 140)
local GOLD = Color3.fromRGB(255, 220, 110)
local CARD = Color3.fromRGB(32, 42, 68)
local CARD_EDGE = Color3.fromRGB(70, 85, 120)
local DONE_GREEN = Color3.fromRGB(40, 150, 85)
local DOOR_RED = Color3.fromRGB(200, 45, 55)
local DOOR_MISSED = Color3.fromRGB(110, 70, 80)
local DOOR_LOCKED = Color3.fromRGB(45, 52, 75)

type Door = { button: TextButton, number: TextLabel, reward: TextLabel, edge: UIStroke? }
type QuestRow = { frame: Frame, name: TextLabel, info: TextLabel, state: TextButton }

local DailyController = {}

local player = Players.LocalPlayer
local request: RemoteEvent
local panel: Frame
local panelScale: UIScale?
local status: TextLabel
local coalLabel: TextLabel?
local badge: GuiObject?
local dailyButton: GuiObject
local streakHeader: TextLabel
local questHeader: TextLabel
local adventHeader: TextLabel
local streakCells: { Frame } = {}
local questRows: { QuestRow } = {}
local doors: { Door } = {}
local actionRow: Frame
local coalButton: TextButton
local robuxButton: TextButton
local questTemplate: Frame
local list: ScrollingFrame

local latest: { [string]: any }? = nil
local nextDayAt = 0 -- os.clock() of the next UTC midnight, from the latest sync
local selectedDay: number? = nil
local catchUpPrice = Config.DevProducts.AdventCatchUp.price
local isOpen = false
local closeToken = 0

local function setStatus(text: string, color: Color3)
	status.Text = text
	status.TextColor3 = color
end

local function formatWait(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	return if hours > 0 then `{hours}h {minutes}m` else `{minutes}m {seconds % 60}s`
end

local function rarityColor(name: string): Color3?
	local rarity = (Config.Rarities :: any)[name]
	-- Lightened: the raw blue and purple are too dark to read on the navy and maroon doors.
	return if type(rarity) == "table" then rarity.color:Lerp(Color3.new(1, 1, 1), 0.4) else nil
end

local function refreshHeaders()
	local sync = latest
	if not sync then
		return
	end
	local streak = if type(sync.streak) == "number" then sync.streak else 0
	streakHeader.Text = if streak > 0 then `Login streak: day {streak}` else "Login streak"
	questHeader.Text = `Daily quests (new ones in {formatWait(nextDayAt - os.clock())})`
	adventHeader.Text = if sync.calendarOpen == true then "Advent Calendar" else `Advent Calendar (opens {MONTH_NAME} 1)`
end

local function refreshStreak(sync: { [string]: any })
	local streak = if type(sync.streak) == "number" then sync.streak else 0
	local rewards = if type(sync.streakRewards) == "table" then sync.streakRewards else {}
	local current = math.min(streak, #streakCells)
	for day, cell in streakCells do
		local coins = cell:FindFirstChild("Coins") :: TextLabel
		local dayLabel = cell:FindFirstChild("Day") :: TextLabel
		local edge = cell:FindFirstChild("Edge") :: UIStroke?
		local amount = rewards[day]
		coins.Text = if type(amount) == "number" then StoreCatalog.withCommas(amount) else "-"
		dayLabel.Text = if day == #streakCells then `Day {day}+` else `Day {day}`
		local isToday = day == current
		cell.BackgroundColor3 = if isToday then DONE_GREEN elseif day < current then Color3.fromRGB(40, 70, 70) else CARD
		if edge then
			edge.Color = if isToday then GOLD else CARD_EDGE
			edge.Thickness = if isToday then 3 else 2
		end
	end
end

local function questRow(index: number): QuestRow
	local existing = questRows[index]
	if existing then
		return existing
	end
	local frame = questTemplate:Clone()
	frame.Name = `Quest{index}`
	frame.LayoutOrder = 30 + index
	frame.Parent = list
	local row: QuestRow = {
		frame = frame,
		name = frame:FindFirstChild("ItemName") :: TextLabel,
		info = frame:FindFirstChild("Info") :: TextLabel,
		state = frame:FindFirstChild("State") :: TextButton,
	}
	questRows[index] = row
	return row
end

local function refreshQuests(sync: { [string]: any })
	local quests = if type(sync.quests) == "table" then sync.quests else {}
	for index, quest in quests do
		if type(quest) ~= "table" then
			continue
		end
		local row = questRow(index)
		row.frame.Visible = true
		row.name.Text = if type(quest.text) == "string" then quest.text else "?"
		local reward = if type(quest.reward) == "number" then quest.reward else 0
		row.info.Text = `Reward: {StoreCatalog.withCommas(reward)} coins`
		if quest.done == true then
			row.state.Text = "DONE!"
			row.state.BackgroundColor3 = DONE_GREEN
			row.state.TextColor3 = Color3.new(1, 1, 1)
		else
			local progress = if type(quest.progress) == "number" then quest.progress else 0
			local goal = if type(quest.goal) == "number" then quest.goal else 1
			row.state.Text = `{progress} / {goal}`
			row.state.BackgroundColor3 = GOLD
			row.state.TextColor3 = Color3.fromRGB(22, 30, 51)
		end
	end
	for index = #quests + 1, #questRows do
		questRows[index].frame.Visible = false
	end
end

local function doorStateOf(day: number): string
	local sync = latest
	local states = sync and sync.doors
	local state = if type(states) == "table" then states[day] else nil
	return if type(state) == "string" then state else "Locked"
end

local function refreshDoors(sync: { [string]: any })
	local rewards = if type(sync.rewards) == "table" then sync.rewards else {}
	for day, door in doors do
		local state = doorStateOf(day)
		local reward = rewards[day]
		local rewardName = if type(reward) == "string" then reward else "Coins"
		door.number.Text = if state == "Opened" then "✓" else tostring(day)
		door.reward.Text = if state == "Opened" then `Day {day}` else rewardName
		local plain = Color3.fromRGB(255, 235, 190)
		door.reward.TextColor3 = if state == "Opened" then plain else rarityColor(rewardName) or plain
		door.button.BackgroundColor3 = if state == "Today"
			then DOOR_RED
			elseif state == "Missed" then DOOR_MISSED
			elseif state == "Opened" then DONE_GREEN
			else DOOR_LOCKED
		local edge = door.edge
		if edge then
			edge.Color = if state == "Today" then GOLD else CARD_EDGE
			edge.Thickness = if state == "Today" then 4 else 2
		end
		door.button.AutoButtonColor = state == "Today" or state == "Missed"
	end
	-- The picked missed door may have opened meanwhile.
	local selected = selectedDay
	if selected and doorStateOf(selected) ~= "Missed" then
		selectedDay = nil
	end
	actionRow.Visible = selectedDay ~= nil
	local coal = if type(sync.coal) == "number" then sync.coal else 0
	local cost = if type(sync.catchUpCoal) == "number" then sync.catchUpCoal else Config.Advent.CatchUpCoal
	coalButton.Text = `Open with {cost} coal`
	coalButton.AutoButtonColor = coal >= cost
	coalButton.BackgroundTransparency = if coal >= cost then 0 else 0.4
	robuxButton.Text = `Open with {ROBUX} {catchUpPrice}`
	local label = coalLabel
	if label then
		label.Text = `Coal {StoreCatalog.withCommas(coal)}`
	end
end

local function refreshBadge()
	local waiting = false
	for day = 1, #doors do
		if doorStateOf(day) == "Today" then
			waiting = true
		end
	end
	local b = badge
	if b then
		b.Visible = waiting
	end
end

local function refreshAll()
	local sync = latest
	if not sync then
		return
	end
	refreshHeaders()
	refreshStreak(sync)
	refreshQuests(sync)
	refreshDoors(sync)
	refreshBadge()
end

local function pop(scale: UIScale?, size: number)
	if scale then
		scale.Scale = size
		TweenService:Create(scale, POP_TWEEN, { Scale = 1 }):Play()
	end
end

local function open()
	if isOpen then
		return
	end
	isOpen = true
	closeToken += 1
	selectedDay = nil
	refreshAll()
	setStatus("Come back every day: the streak and quests reset at midnight (UTC).", MUTED_TEXT)
	panel.Visible = true
	if panelScale then
		panelScale.Scale = OPEN_FROM_SCALE
		TweenService:Create(panelScale, OPEN_TWEEN, { Scale = 1 }):Play()
	end
	-- Keep the "new quests in" countdown ticking while the screen is open.
	local token = closeToken
	task.spawn(function()
		while isOpen and token == closeToken do
			refreshHeaders()
			task.wait(1)
		end
	end)
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	closeToken += 1
	local token = closeToken
	if panelScale then
		TweenService:Create(panelScale, CLOSE_TWEEN, { Scale = OPEN_FROM_SCALE }):Play()
		task.delay(CLOSE_TWEEN.Time, function()
			if token == closeToken then
				panel.Visible = false
			end
		end)
	else
		panel.Visible = false
	end
end

local function onDoorClicked(day: number)
	local state = doorStateOf(day)
	if state == "Today" then
		selectedDay = nil
		actionRow.Visible = false
		request:FireServer(day, "Free")
		setStatus(`Opening door {day}...`, MUTED_TEXT)
	elseif state == "Missed" then
		selectedDay = day
		actionRow.Visible = true
		setStatus(`Door {day} was missed. Open it with coal or Robux:`, GOLD)
	elseif state == "Opened" then
		setStatus(`Door {day} is already open.`, MUTED_TEXT)
	else
		local sync = latest
		setStatus(
			if sync and sync.calendarOpen == true
				then `Door {day} opens on {MONTH_NAME} {day}.`
				else `The Advent Calendar opens on {MONTH_NAME} 1.`,
			MUTED_TEXT
		)
	end
end

local function makeHeader(template: TextLabel, order: number): TextLabel
	local header = template:Clone()
	header.LayoutOrder = order
	header.Visible = true
	header.Parent = list
	return header
end

function DailyController:Init() end

function DailyController:Start()
	local playerGui = player:WaitForChild("PlayerGui")
	-- Never give up waiting for the GUI (CLAUDE.md: slow joins left buttons dead once).
	local function waitForGui(name: string): Instance
		local found = playerGui:WaitForChild(name, GUI_WAIT_SECONDS)
		if not found then
			warn(`[DailyController] still waiting for PlayerGui/{name} (StarterGui in the place file)`)
			found = playerGui:WaitForChild(name)
		end
		return found :: Instance
	end
	local gui = waitForGui("DailyGui")
	local hud = waitForGui("HudGui")
	local foundPanel = gui:FindFirstChild("Panel")
	local foundList = foundPanel and foundPanel:FindFirstChild("List")
	local foundStatus = foundPanel and foundPanel:FindFirstChild("Status")
	local closeButton = foundPanel and foundPanel:FindFirstChild("Close")
	local headerTemplate = foundList and foundList:FindFirstChild("HeaderTemplate")
	local foundQuest = foundList and foundList:FindFirstChild("QuestTemplate")
	local streakRow = foundList and foundList:FindFirstChild("StreakRow")
	local doorGrid = foundList and foundList:FindFirstChild("DoorGrid")
	local foundActions = foundList and foundList:FindFirstChild("ActionRow")
	local button = hud:FindFirstChild("DailyButton")
	if
		not (foundPanel and foundPanel:IsA("Frame"))
		or not (foundList and foundList:IsA("ScrollingFrame"))
		or not (foundStatus and foundStatus:IsA("TextLabel"))
		or not (closeButton and closeButton:IsA("TextButton"))
		or not (headerTemplate and headerTemplate:IsA("TextLabel"))
		or not (foundQuest and foundQuest:IsA("Frame"))
		or not (streakRow and streakRow:IsA("Frame"))
		or not (doorGrid and doorGrid:IsA("Frame"))
		or not (foundActions and foundActions:IsA("Frame"))
		or not (button and button:IsA("TextButton"))
	then
		warn("[DailyController] DailyGui or HudGui.DailyButton is missing a part; the Daily screen is off")
		return
	end
	panel = foundPanel
	list = foundList
	status = foundStatus
	questTemplate = foundQuest
	actionRow = foundActions
	dailyButton = button
	panelScale = panel:FindFirstChildOfClass("UIScale")
	local foundCoal = panel:FindFirstChild("Coal")
	coalLabel = if foundCoal and foundCoal:IsA("TextLabel") then foundCoal else nil
	local foundBadge = button:FindFirstChild("Badge")
	badge = if foundBadge and foundBadge:IsA("GuiObject") then foundBadge else nil
	coalButton = actionRow:WaitForChild("CoalButton") :: TextButton
	robuxButton = actionRow:WaitForChild("RobuxButton") :: TextButton
	request = Remotes.get("RequestAdventDoor")
	panel.Visible = false

	-- Build the screen once, in this order: streak, quests, calendar.
	streakHeader = makeHeader(headerTemplate, 10)
	streakRow.LayoutOrder = 11
	streakRow.Visible = true
	local dayTemplate = streakRow:WaitForChild("DayTemplate") :: Frame
	for day = 1, #Config.LoginStreak.Rewards do
		local cell = dayTemplate:Clone()
		cell.Name = `Day{day}`
		cell.LayoutOrder = day
		cell.Visible = true
		cell.Size = UDim2.new(1 / #Config.LoginStreak.Rewards, -6, 1, 0)
		cell.Parent = streakRow
		streakCells[day] = cell
	end
	questHeader = makeHeader(headerTemplate, 30)
	for index = 1, Config.Quests.Count do
		questRow(index).frame.Visible = false
	end
	adventHeader = makeHeader(headerTemplate, 50)
	doorGrid.LayoutOrder = 51
	doorGrid.Visible = true
	actionRow.LayoutOrder = 52
	local doorTemplate = doorGrid:WaitForChild("DoorTemplate") :: TextButton
	for day = 1, Config.Advent.LastDay do
		local doorButton = doorTemplate:Clone()
		doorButton.Name = `Door{day}`
		doorButton.LayoutOrder = day
		doorButton.Visible = true
		doorButton.Parent = doorGrid
		doors[day] = {
			button = doorButton,
			number = doorButton:FindFirstChild("Number") :: TextLabel,
			reward = doorButton:FindFirstChild("Reward") :: TextLabel,
			edge = doorButton:FindFirstChild("Edge") :: UIStroke?,
		}
		doorButton.Activated:Connect(function()
			onDoorClicked(day)
		end)
	end

	coalButton.Activated:Connect(function()
		local day = selectedDay
		if day then
			pop(coalButton:FindFirstChildOfClass("UIScale"), 0.9)
			request:FireServer(day, "Coal")
		end
	end)
	robuxButton.Activated:Connect(function()
		local day = selectedDay
		if day then
			pop(robuxButton:FindFirstChildOfClass("UIScale"), 0.9)
			request:FireServer(day, "Robux") -- the server opens Roblox's purchase prompt
		end
	end)
	closeButton.Activated:Connect(close)
	local buttonScale = button:FindFirstChildOfClass("UIScale")
	button.Activated:Connect(function()
		pop(buttonScale, 0.9)
		if isOpen then
			close()
		else
			open()
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local parent = prompt.Parent
		if parent and CollectionService:HasTag(parent, "AdventCalendar") then
			open()
		end
	end)
	-- Hidden while jailed: nothing to collect in the cell, and the screen stays clear.
	local function refreshJailed()
		dailyButton.Visible = player:GetAttribute("Jailed") ~= true
		if not dailyButton.Visible then
			close()
		end
	end
	player:GetAttributeChangedSignal("Jailed"):Connect(refreshJailed)
	refreshJailed()

	-- Live price of the catch-up product; Config's price is only the fallback.
	task.spawn(function()
		local id = Config.DevProducts.AdventCatchUp.id
		if id <= 0 then
			return
		end
		local ok, info = pcall(function(): any
			return MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			catchUpPrice = info.PriceInRobux
			refreshAll()
		end
	end)

	Remotes.get("DailySync").OnClientEvent:Connect(function(sync: any)
		if type(sync) ~= "table" then
			return
		end
		latest = sync
		if type(sync.secondsToNextDay) == "number" then
			nextDayAt = os.clock() + sync.secondsToNextDay
		end
		refreshAll()
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(text: any)
		if isOpen and type(text) == "string" then
			setStatus(text:sub(1, MAX_MESSAGE_LENGTH), GOOD_TEXT)
		end
	end)
end

return DailyController

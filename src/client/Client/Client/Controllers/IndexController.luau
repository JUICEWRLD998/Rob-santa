--!strict
-- The Collection Index screen (step 4.4). Opens from the INDEX button on the left of the HUD.
-- IndexGui and HudGui.IndexButton live in the place file; this fills one header per page and one
-- row per toy from Panel/List/PageTemplate and RowTemplate (5 cells: plain + each mutation).
-- The server sends the found keys (IndexSync); the page and bonus numbers come from the shared
-- IndexBook, so they match what the server pays. Display only.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local IndexBook = require(Shared:WaitForChild("IndexBook"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local GUI_WAIT_SECONDS = 15
local MAX_KEYS = 500 -- far above the 80 real entries; anything longer is ignored
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POP_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_FROM_SCALE = 0.85

local NAVY = Color3.fromRGB(22, 30, 51)
local EMPTY_CELL = Color3.fromRGB(42, 52, 80)
local EMPTY_TEXT = Color3.fromRGB(125, 137, 168)
local MUTED_TEXT = Color3.fromRGB(200, 210, 230)
local DIM_NAME = Color3.fromRGB(120, 130, 155)
local DONE_TEXT = Color3.fromRGB(120, 230, 140)
local PLAIN_LABEL = "Plain"
local SHORT_NAMES: { [string]: string } = { Gingerbread = "Ginger" } -- fits a phone-width cell

type Cell = { frame: Frame, label: TextLabel, mutation: Types.Mutation? }
type Row = { toy: Types.ToyDef, name: TextLabel, cells: { Cell } }
type Header = { page: IndexBook.Page, progress: TextLabel }

local IndexController = {}

local player = Players.LocalPlayer
local found: IndexBook.Found = {}
local rows: { Row } = {}
local headers: { Header } = {}
local panel: Frame
local panelScale: UIScale?
local status: TextLabel
local bonusLabel: TextLabel?
local isOpen = false
local closeToken = 0

local function mutationColor(mutation: Types.Mutation): Color3
	for _, entry in Config.Mutations do
		if entry.name == mutation then
			return entry.color
		end
	end
	return MUTED_TEXT
end

local function refresh()
	for _, row in rows do
		local rarityColor = Config.Rarities[row.toy.rarity].color
		local anyFound = IndexBook.formsFound(found, row.toy.id) > 0
		row.name.TextColor3 = if anyFound then Color3.new(1, 1, 1) else DIM_NAME
		for _, cell in row.cells do
			local isFound = IndexBook.isFound(found, row.toy.id, cell.mutation)
			local fill = if cell.mutation then mutationColor(cell.mutation) else rarityColor
			cell.frame.BackgroundColor3 = if isFound then fill else EMPTY_CELL
			cell.label.TextColor3 = if isFound then NAVY else EMPTY_TEXT
			local name = if cell.mutation then SHORT_NAMES[cell.mutation] or cell.mutation else PLAIN_LABEL
			cell.label.Text = name -- greyed until found, so every column says which form it is
		end
	end
	for _, header in headers do
		local done, total = IndexBook.pageProgress(found, header.page)
		local percent = math.round(Config.Index.ZoneCompleteIncomeBonus * 100)
		if done == total and total > 0 then
			header.progress.Text = `COMPLETE  +{percent}% income`
			header.progress.TextColor3 = DONE_TEXT
		else
			header.progress.Text = `{done}/{total} toys  (+{percent}% when complete)`
			header.progress.TextColor3 = MUTED_TEXT
		end
	end
	local entries, totalEntries = IndexBook.count(found)
	status.Text = `{entries} of {totalEntries} found. A new find pays coins!`
	if bonusLabel then
		local bonus = math.round((IndexBook.incomeMultiplier(found) - 1) * 100)
		bonusLabel.Text = `+{bonus}% income`
	end
end

local function open()
	if isOpen then
		return
	end
	isOpen = true
	closeToken += 1
	refresh()
	panel.Visible = true
	if panelScale then
		panelScale.Scale = OPEN_FROM_SCALE
		TweenService:Create(panelScale, OPEN_TWEEN, { Scale = 1 }):Play()
	end
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	closeToken += 1
	local token = closeToken
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panel) then
		GuiService.SelectedObject = nil
	end
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

local function onSync(keys: any)
	if type(keys) ~= "table" or #keys > MAX_KEYS then
		return
	end
	local fresh: IndexBook.Found = {}
	for _, key in keys do
		if IndexBook.isValidKey(key) then
			fresh[key] = true
		end
	end
	found = fresh
	if isOpen then
		refresh()
	end
end

local function makeCell(cells: Frame, template: Frame, order: number, mutation: Types.Mutation?): Cell
	local frame = template:Clone()
	frame.Name = if mutation then mutation else PLAIN_LABEL
	frame.LayoutOrder = order
	frame.Visible = true
	frame.Parent = cells
	return { frame = frame, label = frame:FindFirstChild("Label") :: TextLabel, mutation = mutation }
end

local function build(list: ScrollingFrame, pageTemplate: Frame, rowTemplate: Frame): boolean
	local cellsTemplate = rowTemplate:FindFirstChild("Cells")
	local cellTemplate = cellsTemplate and cellsTemplate:FindFirstChild("CellTemplate")
	if not (cellTemplate and cellTemplate:IsA("Frame")) then
		return false
	end
	local order = 0
	for _, page in IndexBook.Pages do
		order += 1
		local header = pageTemplate:Clone()
		header.Name = `Page{page.zone}`
		header.LayoutOrder = order
		header.Visible = true
		local zone = Config.Zones[page.zone]
		local later = zone and zone.update ~= nil
		local pageName = header:FindFirstChild("PageName") :: TextLabel
		pageName.Text = if later then `{page.name} (coming soon)` else page.name
		header.Parent = list
		table.insert(headers, { page = page, progress = header:FindFirstChild("Progress") :: TextLabel })
		for _, toy in page.toys do
			order += 1
			local frame = rowTemplate:Clone()
			frame.Name = toy.id
			frame.LayoutOrder = order
			frame.Visible = true
			local toyName = frame:FindFirstChild("ToyName") :: TextLabel
			toyName.Text = toy.name
			local rarity = frame:FindFirstChild("Rarity") :: TextLabel
			rarity.Text = toy.rarity
			rarity.TextColor3 = Config.Rarities[toy.rarity].color
			local cells = frame:FindFirstChild("Cells") :: Frame
			local template = cells:FindFirstChild("CellTemplate") :: Frame
			local row: Row = { toy = toy, name = toyName, cells = {} }
			table.insert(row.cells, makeCell(cells, template, 1, nil))
			for i, mutation in IndexBook.Mutations do
				table.insert(row.cells, makeCell(cells, template, i + 1, mutation :: Types.Mutation))
			end
			template:Destroy()
			frame.Parent = list
			table.insert(rows, row)
		end
	end
	pageTemplate.Visible = false
	rowTemplate.Visible = false
	return true
end

function IndexController:Init() end

function IndexController:Start()
	-- Connect first: the server may send the list as soon as the save loads.
	Remotes.get("IndexSync").OnClientEvent:Connect(onSync)

	local playerGui = player:WaitForChild("PlayerGui")
	-- Slow joins can take longer than GUI_WAIT_SECONDS to fill PlayerGui: warn, then keep waiting.
	-- Giving up left the INDEX button dead for the whole session (seen 2026-11-21).
	local function waitForGui(name: string): Instance
		local screen = playerGui:WaitForChild(name, GUI_WAIT_SECONDS)
		if not screen then
			warn(`[IndexController] still waiting for PlayerGui/{name} (StarterGui in the place file)`)
			screen = playerGui:WaitForChild(name)
		end
		return screen :: Instance
	end
	local gui = waitForGui("IndexGui")
	local hud = waitForGui("HudGui")
	local foundPanel = gui:FindFirstChild("Panel")
	local list = foundPanel and foundPanel:FindFirstChild("List")
	local pageTemplate = list and list:FindFirstChild("PageTemplate")
	local rowTemplate = list and list:FindFirstChild("RowTemplate")
	local foundStatus = foundPanel and foundPanel:FindFirstChild("Status")
	local closeButton = foundPanel and foundPanel:FindFirstChild("Close")
	local indexButton = hud:FindFirstChild("IndexButton")
	if
		not (foundPanel and foundPanel:IsA("Frame"))
		or not (list and list:IsA("ScrollingFrame"))
		or not (pageTemplate and pageTemplate:IsA("Frame"))
		or not (rowTemplate and rowTemplate:IsA("Frame"))
		or not (foundStatus and foundStatus:IsA("TextLabel"))
		or not (closeButton and closeButton:IsA("TextButton"))
		or not (indexButton and indexButton:IsA("TextButton"))
	then
		warn("[IndexController] IndexGui needs Panel/List/PageTemplate+RowTemplate, Panel/Status, Panel/Close and HudGui/IndexButton")
		return
	end
	panel = foundPanel
	panelScale = panel:FindFirstChildOfClass("UIScale")
	status = foundStatus
	local foundBonus = panel:FindFirstChild("Bonus")
	bonusLabel = if foundBonus and foundBonus:IsA("TextLabel") then foundBonus else nil
	panel.Visible = false
	if not build(list, pageTemplate, rowTemplate) then
		warn("[IndexController] RowTemplate needs Cells/CellTemplate")
		return
	end

	closeButton.Activated:Connect(close)
	local buttonScale = indexButton:FindFirstChildOfClass("UIScale")
	indexButton.Activated:Connect(function()
		if buttonScale then
			buttonScale.Scale = 0.9
			TweenService:Create(buttonScale, POP_TWEEN, { Scale = 1 }):Play()
		end
		if isOpen then
			close()
		else
			open()
		end
	end)
	refresh()
end

return IndexController

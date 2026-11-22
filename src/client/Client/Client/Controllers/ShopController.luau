--!strict
-- The Gadget Shop screen (step 4.2). Opens from the SHOP button on the left of the HUD and from a
-- "Shop" prompt at the Gadget Shop counter in the Town Square (made here, on this client only:
-- opening a screen decides nothing). ShopGui and HudGui.ShopButton live in the place file; this
-- fills one card per ShopCatalog item from StarterGui/ShopGui/Panel/List/ItemTemplate.
-- Buying sends RequestPurchase with the item id only. The server decides and answers ShopResult;
-- the card then reads the new level from the Player attributes the server sets. Display only.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))

local GUI_WAIT_SECONDS = 15
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POP_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_FROM_SCALE = 0.85
local SHAKE_PIXELS = 6 -- how far the Buy button jiggles when the server says no
local MAX_MESSAGE_LENGTH = 120

local GOLD = Color3.fromRGB(245, 190, 40)
local LOCKED = Color3.fromRGB(70, 80, 105) -- can't buy yet (too expensive, or needs a zone)
local MAXED = Color3.fromRGB(70, 185, 90)
local NAVY = Color3.fromRGB(22, 30, 51)
local MUTED_TEXT = Color3.fromRGB(200, 210, 230)
local GOOD_TEXT = Color3.fromRGB(120, 230, 140)
local BAD_TEXT = Color3.fromRGB(255, 130, 120)

type Card = {
	item: ShopCatalog.Item,
	frame: Frame,
	itemName: TextLabel,
	level: TextLabel,
	info: TextLabel,
	buy: TextButton,
	buyScale: UIScale?,
}

local ShopController = {}

local player = Players.LocalPlayer
local cards: { Card } = {}
local panel: Frame
local panelScale: UIScale?
local status: TextLabel
local coinsLabel: TextLabel? -- the panel covers the HUD's coin counter, so it shows its own
local isOpen = false
local closeToken = 0

local function withCommas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return if formatted:sub(1, 1) == "," then formatted:sub(2) else formatted
end

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function levelOf(id: ShopCatalog.ItemId): number
	return numberAttribute(ShopCatalog.attributeName(id))
end

local function refreshCard(card: Card)
	local item = card.item
	local level = levelOf(item.id)
	local cost = ShopCatalog.cost(item.id, level)
	local needed = ShopCatalog.get(item.requires)
	card.itemName.Text = item.name
	card.info.Text = item.describe(level)
	card.level.Text = if item.maxLevel > 1 then `Lv {level}/{item.maxLevel}` else ""
	if not cost then
		card.buy.Text = if item.maxLevel > 1 then "MAX" else "OWNED"
		card.buy.BackgroundColor3 = MAXED
		card.buy.TextColor3 = Color3.new(1, 1, 1)
		card.buy.AutoButtonColor = false
	elseif needed and levelOf(needed.id) < 1 then
		card.buy.Text = `Needs {needed.name}`
		card.buy.BackgroundColor3 = LOCKED
		card.buy.TextColor3 = MUTED_TEXT
		card.buy.AutoButtonColor = false
	else
		card.buy.Text = withCommas(cost)
		local affordable = numberAttribute("Coins") >= cost
		card.buy.BackgroundColor3 = if affordable then GOLD else LOCKED
		card.buy.TextColor3 = if affordable then NAVY else MUTED_TEXT
		card.buy.AutoButtonColor = affordable
	end
end

local function refreshAll()
	if coinsLabel then
		coinsLabel.Text = withCommas(numberAttribute("Coins")) -- next to the coin icon (5.5)
	end
	for _, card in cards do
		refreshCard(card)
	end
end

local function setStatus(text: string, color: Color3)
	status.Text = text
	status.TextColor3 = color
end

local function open()
	if isOpen then
		return
	end
	isOpen = true
	closeToken += 1
	refreshAll()
	setStatus("Upgrades are saved forever. Spend your coins!", MUTED_TEXT)
	panel.Visible = true
	if panelScale then
		panelScale.Scale = OPEN_FROM_SCALE
		TweenService:Create(panelScale, OPEN_TWEEN, { Scale = 1 }):Play()
	end
	-- On a controller, put the selection on the first Buy button so the D-pad works straight away.
	if UserInputService.GamepadEnabled and cards[1] then
		GuiService.SelectedObject = cards[1].buy
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

local function pop(scale: UIScale?, size: number)
	if scale then
		scale.Scale = size
		TweenService:Create(scale, POP_TWEEN, { Scale = 1 }):Play()
	end
end

local function shake(button: TextButton)
	local home = button.Position
	for _, dx in { SHAKE_PIXELS, -SHAKE_PIXELS, SHAKE_PIXELS / 2, 0 } do
		button.Position = home + UDim2.fromOffset(dx, 0)
		task.wait(0.04)
	end
	button.Position = home
end

local function cardFor(itemId: string): Card?
	for _, card in cards do
		if card.item.id == itemId then
			return card
		end
	end
	return nil
end

local function onResult(result: any)
	if type(result) ~= "table" or type(result.itemId) ~= "string" or type(result.message) ~= "string" then
		return
	end
	local ok = result.ok == true
	setStatus(string.sub(result.message, 1, MAX_MESSAGE_LENGTH), if ok then GOOD_TEXT else BAD_TEXT)
	local card = cardFor(result.itemId)
	if card then
		refreshCard(card)
		if ok then
			pop(card.buyScale, 1.15)
		else
			task.spawn(shake, card.buy)
		end
	end
end

local function buildCards(list: ScrollingFrame, template: Frame, request: RemoteEvent)
	for order, item in ShopCatalog.Items do
		local frame = template:Clone()
		frame.Name = item.id
		frame.LayoutOrder = order
		frame.Visible = true
		local buy = frame:FindFirstChild("Buy") :: TextButton
		local card: Card = {
			item = item,
			frame = frame,
			itemName = frame:FindFirstChild("ItemName") :: TextLabel,
			level = frame:FindFirstChild("Level") :: TextLabel,
			info = frame:FindFirstChild("Info") :: TextLabel,
			buy = buy,
			buyScale = buy:FindFirstChildOfClass("UIScale"),
		}
		buy.Activated:Connect(function()
			request:FireServer(item.id) -- the id only; the server works out the price
		end)
		frame.Parent = list
		table.insert(cards, card)
	end
	template.Visible = false
end

-- A "Shop" prompt on each Gadget Shop counter, made on this client only.
local function addShopPrompt(counter: Instance)
	if not counter:IsA("BasePart") or counter:FindFirstChild("ShopPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Shop"
	prompt.ObjectText = "Gadget Shop"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Shop.PromptDistance
	prompt.RequiresLineOfSight = false -- the counter is one big block; its centre is inside it
	prompt.Triggered:Connect(open)
	prompt.Parent = counter
end

function ShopController:Init() end

function ShopController:Start()
	local playerGui = player:WaitForChild("PlayerGui")
	-- Slow joins can take longer than GUI_WAIT_SECONDS to fill PlayerGui: warn, then keep waiting.
	-- Giving up left the SHOP button dead for the whole session (seen 2026-11-21, like 3.4's HUD).
	local function waitForGui(name: string): Instance
		local found = playerGui:WaitForChild(name, GUI_WAIT_SECONDS)
		if not found then
			warn(`[ShopController] still waiting for PlayerGui/{name} (StarterGui in the place file)`)
			found = playerGui:WaitForChild(name)
		end
		return found :: Instance
	end
	local gui = waitForGui("ShopGui")
	local hud = waitForGui("HudGui")
	local foundPanel = gui:FindFirstChild("Panel")
	local list = foundPanel and foundPanel:FindFirstChild("List")
	local template = list and list:FindFirstChild("ItemTemplate")
	local foundStatus = foundPanel and foundPanel:FindFirstChild("Status")
	local closeButton = foundPanel and foundPanel:FindFirstChild("Close")
	local shopButton = hud:FindFirstChild("ShopButton")
	if
		not (foundPanel and foundPanel:IsA("Frame"))
		or not (list and list:IsA("ScrollingFrame"))
		or not (template and template:IsA("Frame"))
		or not (foundStatus and foundStatus:IsA("TextLabel"))
		or not (closeButton and closeButton:IsA("TextButton"))
		or not (shopButton and shopButton:IsA("TextButton"))
	then
		warn("[ShopController] ShopGui needs Panel/List/ItemTemplate, Panel/Status, Panel/Close and HudGui/ShopButton")
		return
	end
	panel = foundPanel
	panelScale = panel:FindFirstChildOfClass("UIScale")
	status = foundStatus
	local foundCoins = panel:FindFirstChild("Coins")
	coinsLabel = if foundCoins and foundCoins:IsA("TextLabel") then foundCoins else nil
	panel.Visible = false

	buildCards(list, template, Remotes.get("RequestPurchase"))
	Remotes.get("ShopResult").OnClientEvent:Connect(onResult)

	closeButton.Activated:Connect(close)
	local buttonScale = shopButton:FindFirstChildOfClass("UIScale")
	shopButton.Activated:Connect(function()
		pop(buttonScale, 0.9)
		if isOpen then
			close()
		else
			open()
		end
	end)

	player:GetAttributeChangedSignal("Coins"):Connect(function()
		if isOpen then
			refreshAll()
		end
	end)
	for _, item in ShopCatalog.Items do
		player:GetAttributeChangedSignal(ShopCatalog.attributeName(item.id)):Connect(refreshAll)
	end

	for _, counter in CollectionService:GetTagged("GadgetShop") do
		addShopPrompt(counter)
	end
	CollectionService:GetInstanceAddedSignal("GadgetShop"):Connect(addShopPrompt)
	refreshAll()
end

return ShopController

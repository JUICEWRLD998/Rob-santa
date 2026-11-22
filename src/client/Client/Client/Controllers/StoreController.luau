--!strict
-- The Robux store screen (step 6.2). Opens from the ROBUX button (top-right, under DAILY).
-- StoreGui (a copy of the Gadget Shop panel, with an Icon on each card) and HudGui.StoreButton live
-- in the place file; this fills one card per StoreCatalog entry.
-- Prices and icons come live from Creator Hub (GetProductInfoAsync); Config's prices are only a
-- fallback. Buying opens Roblox's own purchase prompt; the server grants (MonetizationService) and
-- its thank-you message shows in the status line here. Display only: nothing here grants anything.
-- Lucky Wrap is a paid random item: its card shows the odds, and it is hidden unless the server
-- says paid random items are allowed for this player (PaidRandomItemsRestricted == false).

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local StoreCatalog = require(Shared:WaitForChild("StoreCatalog"))

local GUI_WAIT_SECONDS = 15
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POP_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_FROM_SCALE = 0.85
local MAX_MESSAGE_LENGTH = 120
local ROBUX = utf8.char(0xE002) -- Roblox draws this as the Robux sign
local CARD_HEIGHT = 96
local LUCKY_CARD_HEIGHT = 150 -- the odds take a few lines
local LUCKY_INFO_HEIGHT = 100

local ROBUX_GREEN = Color3.fromRGB(40, 190, 110)
local OWNED = Color3.fromRGB(70, 80, 105)
local MUTED_TEXT = Color3.fromRGB(200, 210, 230)
local GOOD_TEXT = Color3.fromRGB(120, 230, 140)

type Card = {
	entry: StoreCatalog.Entry,
	frame: Frame,
	info: TextLabel,
	level: TextLabel,
	buy: TextButton,
	buyScale: UIScale?,
	price: number?, -- live price; nil until loaded (then the fallback is shown)
	forSale: boolean,
}

local StoreController = {}

local player = Players.LocalPlayer
local cards: { Card } = {}
local panel: Frame
local panelScale: UIScale?
local status: TextLabel
local coinsLabel: TextLabel?
local isOpen = false
local closeToken = 0

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function ownsPass(card: Card): boolean
	return card.entry.kind == "Pass" and player:GetAttribute(`Pass_{card.entry.key}`) == true
end

local function refreshCard(card: Card)
	local entry = card.entry
	card.info.Text = entry.describe(numberAttribute("IncomePerSecond"))
	if entry.key == "LuckyWrap" then
		card.frame.Visible = player:GetAttribute("PaidRandomItemsRestricted") == false
		local saved = numberAttribute("LuckyWraps")
		card.level.Text = if saved > 0 then `{saved} saved` else ""
	end
	if ownsPass(card) then
		card.buy.Text = "OWNED"
		card.buy.BackgroundColor3 = OWNED
		card.buy.AutoButtonColor = false
	elseif not card.forSale then
		card.buy.Text = "Soon"
		card.buy.BackgroundColor3 = OWNED
		card.buy.AutoButtonColor = false
	else
		card.buy.Text = `{ROBUX} {card.price or entry.fallbackPrice}`
		card.buy.BackgroundColor3 = ROBUX_GREEN
		card.buy.AutoButtonColor = true
	end
end

local function refreshAll()
	if coinsLabel then
		coinsLabel.Text = StoreCatalog.withCommas(numberAttribute("Coins"))
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
	setStatus("Every purchase helps keep the game growing. Thank you!", MUTED_TEXT)
	panel.Visible = true
	if panelScale then
		panelScale.Scale = OPEN_FROM_SCALE
		TweenService:Create(panelScale, OPEN_TWEEN, { Scale = 1 }):Play()
	end
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

-- Live price and icon from Creator Hub. Failing is fine: the card keeps the fallback price.
local function loadInfo(card: Card, icon: ImageLabel)
	local infoType = if card.entry.kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	local ok, info = pcall(function(): any
		return MarketplaceService:GetProductInfoAsync(card.entry.id, infoType)
	end)
	if not ok or type(info) ~= "table" then
		warn(`[StoreController] no product info for {card.entry.key}: {info}`)
		return
	end
	if type(info.PriceInRobux) == "number" then
		card.price = info.PriceInRobux
	elseif card.entry.kind == "Pass" and info.IsForSale == false then
		card.forSale = false -- a pass that isn't on sale in Creator Hub yet
	end
	if type(info.IconImageAssetId) == "number" and info.IconImageAssetId > 0 then
		icon.Image = `rbxassetid://{info.IconImageAssetId}`
	end
	refreshCard(card)
end

local function buy(card: Card)
	if ownsPass(card) or not card.forSale then
		return
	end
	pop(card.buyScale, 0.9)
	if card.entry.kind == "Pass" then
		MarketplaceService:PromptGamePassPurchase(player, card.entry.id)
	else
		MarketplaceService:PromptProductPurchase(player, card.entry.id)
	end
end

local function buildCards(list: ScrollingFrame, template: Frame)
	for order, entry in StoreCatalog.Entries do
		if entry.id <= 0 then
			continue
		end
		local frame = template:Clone()
		frame.Name = entry.key
		frame.LayoutOrder = order
		frame.Visible = true
		local itemName = frame:FindFirstChild("ItemName") :: TextLabel
		local info = frame:FindFirstChild("Info") :: TextLabel
		local level = frame:FindFirstChild("Level") :: TextLabel
		local buyButton = frame:FindFirstChild("Buy") :: TextButton
		local icon = frame:FindFirstChild("Icon") :: ImageLabel
		itemName.Text = entry.name
		level.Text = ""
		if entry.key == "LuckyWrap" then
			frame.Size = UDim2.new(1, 0, 0, LUCKY_CARD_HEIGHT)
			info.Size = UDim2.new(info.Size.X.Scale, info.Size.X.Offset, 0, LUCKY_INFO_HEIGHT)
			frame.Visible = false -- until the server says paid random items are allowed here
		else
			frame.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
		end
		local card: Card = {
			entry = entry,
			frame = frame,
			info = info,
			level = level,
			buy = buyButton,
			buyScale = buyButton:FindFirstChildOfClass("UIScale"),
			price = nil,
			forSale = true,
		}
		buyButton.Activated:Connect(function()
			buy(card)
		end)
		frame.Parent = list
		table.insert(cards, card)
		task.spawn(loadInfo, card, icon)
	end
	template.Visible = false
end

function StoreController:Init() end

function StoreController:Start()
	local playerGui = player:WaitForChild("PlayerGui")
	-- Never give up waiting for the GUI (CLAUDE.md: slow joins left buttons dead once).
	local function waitForGui(name: string): Instance
		local found = playerGui:WaitForChild(name, GUI_WAIT_SECONDS)
		if not found then
			warn(`[StoreController] still waiting for PlayerGui/{name} (StarterGui in the place file)`)
			found = playerGui:WaitForChild(name)
		end
		return found :: Instance
	end
	local gui = waitForGui("StoreGui")
	local hud = waitForGui("HudGui")
	local foundPanel = gui:FindFirstChild("Panel")
	local list = foundPanel and foundPanel:FindFirstChild("List")
	local template = list and list:FindFirstChild("ItemTemplate")
	local foundStatus = foundPanel and foundPanel:FindFirstChild("Status")
	local closeButton = foundPanel and foundPanel:FindFirstChild("Close")
	local storeButton = hud:FindFirstChild("StoreButton")
	if
		not (foundPanel and foundPanel:IsA("Frame"))
		or not (list and list:IsA("ScrollingFrame"))
		or not (template and template:IsA("Frame"))
		or not (foundStatus and foundStatus:IsA("TextLabel"))
		or not (closeButton and closeButton:IsA("TextButton"))
		or not (storeButton and storeButton:IsA("TextButton"))
	then
		warn("[StoreController] StoreGui needs Panel/List/ItemTemplate, Panel/Status, Panel/Close and HudGui/StoreButton")
		return
	end
	panel = foundPanel
	panelScale = panel:FindFirstChildOfClass("UIScale")
	status = foundStatus
	local foundCoins = panel:FindFirstChild("Coins")
	coinsLabel = if foundCoins and foundCoins:IsA("TextLabel") then foundCoins else nil
	panel.Visible = false

	buildCards(list, template)

	closeButton.Activated:Connect(close)
	local buttonScale = storeButton:FindFirstChildOfClass("UIScale")
	storeButton.Activated:Connect(function()
		pop(buttonScale, 0.9)
		if isOpen then
			close()
		else
			open()
		end
	end)

	-- The server's thank-you (Notify) would sit under this panel; show it on the panel too.
	Remotes.get("Notify").OnClientEvent:Connect(function(text: any)
		if isOpen and type(text) == "string" then
			setStatus(text:sub(1, MAX_MESSAGE_LENGTH), GOOD_TEXT)
			refreshAll()
		end
	end)
	for _, name in { "Coins", "IncomePerSecond", "LuckyWraps", "PaidRandomItemsRestricted" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if isOpen or name == "PaidRandomItemsRestricted" then
				refreshAll()
			end
		end)
	end
	for _, key in StoreCatalog.PassKeys do
		player:GetAttributeChangedSignal(StoreCatalog.passAttribute(key :: StoreCatalog.PassKey)):Connect(refreshAll)
	end
	refreshAll()
end

return StoreController

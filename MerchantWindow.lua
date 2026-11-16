local _, ns = ...
local E, T, Text, Public = ns.vendor, ns.Theme, ns.Text, ns.Public
local W = Sintezza_Theme:CreateWidgets(T)
local labels = ns.MerchantLabels
local BUYBACK_PANEL_WIDTH = 200
local BUYBACK_DIVIDER_OFFSET = 136
local tabs = { "catalog", "buyback", "review", "journal" }
local tabNames = {
    catalog = Text("Merchant", "Торговец"), buyback = Text("Buyback", "Выкуп"),
    review = Text("Loot Review", "Разбор добычи"), journal = Text("Journal", "Журнал"),
}
local kinds = { buy = Text("Bought", "Покупка"), sell = Text("Sold", "Продажа"), buyback = tabNames.buyback }
local cyrillic = {}
do
    local lower = "абвгде\209\145жзийклмнопрстуфхцчшщъыьэюя"
    local upper = "АБВГДЕ\208\129ЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
    for i = 1, #upper, 2 do cyrillic[upper:sub(i, i + 1)] = lower:sub(i, i + 1) end
end

function ns.FoldText(value)
    return (value:lower():gsub("[\208\209][\128-\191]", cyrillic)):gsub("\209\145", "е")
end

local Fold = ns.FoldText

local function Coins(value)
    return C_CurrencyInfo.GetCoinTextureString(value or 0, 12)
end

local function TimeText(format, value)
    return type(value) == "number" and date(format, value) or "—"
end

local function Button(parent, label, width, callback, primary)
    local button = W:Button(parent, label, callback, primary)
    button:SetSize(width, 24)
    return button
end

local function Available(button, state)
    button:SetEnabled(not not state)
end

local function Label(parent, size, color)
    local label = W:Label(parent, "", size, color)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

local function HideBuybackTooltip(button)
    if not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip:IsOwned(button) then
        GameTooltip:Hide()
    end
end

local function CreateQuickBuyback(window)
    local panel = CreateFrame("Frame", nil, window, "BackdropTemplate")
    panel:SetSize(BUYBACK_PANEL_WIDTH, 58)
    panel:SetPoint("BOTTOMRIGHT", -14, 52)
    T:Backdrop(panel, T.input, T.lineSoft)
    local title = Label(panel, 10, T.brass)
    title:SetPoint("TOPLEFT", 9, -4)
    title:SetText(labels.lastSale)

    local button = W:Button(panel, "", function(self)
        HideBuybackTooltip(self)
        if self.offer then E:RequestPurchase(self.offer) end
    end)
    button:SetPoint("TOPLEFT", 1, -19)
    button:SetPoint("BOTTOMRIGHT", -1, 1)
    button:RegisterForClicks("LeftButtonUp")
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    panel.button = button

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(28, 28)
    button.icon:SetPoint("LEFT", 7, 0)
    button.icon:SetTexCoord(.08, .92, .08, .92)
    button.border = T:FrameIcon(button, button.icon)
    button.count = Label(button, 9, T.text)
    button.count:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", -1, 1)
    button.iconDivider = button:CreateTexture(nil, "BORDER")
    button.iconDivider:SetSize(1, 28)
    button.iconDivider:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
    Sintezza_Theme:SnapTexture(button.iconDivider)
    Sintezza_Theme:Tint(button.iconDivider, "SetColorTexture", T.line)
    button.arrow = Label(button, 17, T.text)
    button.arrow:SetPoint("LEFT", button.icon, "RIGHT", 9, 0)
    local atlas = "common-icon-rotateleft"
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    button.arrow:SetText(hasAtlas and ("|A:%s:14:14|a"):format(atlas) or "←")
    button.price = Label(button, 10, T.text)
    button.price:SetPoint("RIGHT", -7, 0)
    button.price:SetJustifyH("RIGHT")
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", button.arrow, "RIGHT", 5, 0)
    button.text:SetPoint("RIGHT", button.price, "LEFT", -5, 0)
    button.text:SetJustifyH("LEFT")
    button.empty = Label(button, 10, T.muted)
    button.empty:SetPoint("CENTER")
    button.empty:SetText(labels.buybackEmpty)

    button:HookScript("OnEnter", function(self)
        local offer = self.offer
        if not offer or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if offer.link then GameTooltip:SetHyperlink(offer.link) else GameTooltip:SetText(offer.name) end
        if offer.price then GameTooltip:AddLine(E:OfferPrice(offer), unpack(T.text, 1, 3)) end
        if self.reason then GameTooltip:AddLine(self.reason, unpack(T.warning, 1, 3)) end
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", HideBuybackTooltip)
    button:HookScript("OnHide", function(self)
        HideBuybackTooltip(self)
        self.offer = nil
    end)
    panel:Hide()
    return panel
end

local function RefreshQuickBuyback(panel)
    local button = panel.button
    local offer = button.offer
    local checking = E.purchaseActive and E.purchaseActive.buyback
        or offer and E.purchaseConfirm == offer
    if not checking then
        local count = Public(GetNumBuybackItems(), "number")
        -- The stock merchant's shortcut uses the last occupied buyback slot.
        local latest = count and count > 0 and E:GetOffer(count, true) or nil
        if offer and (not latest or offer.index ~= latest.index or offer.link ~= latest.link
            or offer.price ~= latest.price or offer.count ~= latest.count) then
            HideBuybackTooltip(button)
        end
        offer = latest
        button.offer = offer
    end

    local affordable, reason
    if offer then affordable, reason = E:CanBuyOffer(offer) end
    button.reason = reason
    local enabled = affordable and not E:LootReviewBusy() and E:CanInteract()
    Available(button, enabled)
    local hasOffer = offer ~= nil
    button.icon:SetShown(hasOffer)
    button.border:SetShown(hasOffer)
    button.iconDivider:SetShown(hasOffer)
    button.arrow:SetShown(hasOffer)
    button.text:SetShown(hasOffer)
    button.empty:SetShown(not hasOffer)
    button.icon:SetTexture(offer and (offer.texture or 134400))
    button.icon:SetDesaturated(not enabled)
    T:PaintItemBorder(button.border, offer and offer.quality)
    button.count:SetText(offer and offer.count and offer.count > 1 and tostring(offer.count) or "")
    button.text:SetText(labels.buyBack)
    button.price:SetText(offer and (offer.price and E:OfferPrice(offer) or "—") or "")
    Sintezza_Theme:Tint(button.price, "SetTextColor", enabled and T.text or T.muted)
    Sintezza_Theme:Tint(button.arrow, "SetTextColor", enabled and T.text or T.muted)
    Sintezza_Theme:Tint(panel, "SetBackdropBorderColor", hasOffer and T.brass or T.lineSoft)
end

local function FormatLogCost(entry)
    local value = Coins(entry.gold)
    for _, currency in ipairs(type(entry.currencies) == "table" and entry.currencies or {}) do
        local icon = currency.texture and ("|T%s:13|t"):format(tostring(currency.texture)) or currency.name or "?"
        value = value .. "  " .. tostring(currency.amount or 0) .. " " .. icon
    end
    return (entry.kind == "sell" and "+" or "−") .. value
end

local function CreateCard(parent)
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    T:Backdrop(card, T.panel, T.lineSoft)
    card:EnableMouse(true)
    card:RegisterForClicks("LeftButtonUp")
    local iconBox = CreateFrame("Frame", nil, card)
    iconBox:SetSize(34, 34)
    iconBox:SetPoint("LEFT", 7, 0)
    card.icon = iconBox:CreateTexture(nil, "ARTWORK")
    card.icon:SetAllPoints()
    card.icon:SetTexCoord(.08, .92, .08, .92)
    card.border = T:FrameIcon(iconBox, card.icon)
    card.title = Label(card, 12, T.text)
    card.title:SetPoint("TOPLEFT", iconBox, "TOPRIGHT", 8, 0)
    card.title:SetPoint("RIGHT", -6, 0)
    card.detail = Label(card, 10, T.muted)
    card.detail:SetPoint("BOTTOMLEFT", iconBox, "BOTTOMRIGHT", 8, 0)
    card.detail:SetPoint("RIGHT", -6, 0)
    card.level = Label(iconBox, 9, T.text)
    card.level:SetPoint("TOPRIGHT")
    card:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(T.accentLine))
        local item = self.item
        if not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.kind == "catalog" then
            GameTooltip:SetMerchantItem(item.index)
        elseif self.kind == "buyback" then
            GameTooltip:SetBuybackItem(item.index)
        elseif item.link then
            GameTooltip:SetHyperlink(item.link)
        else
            GameTooltip:SetText(item.name or "")
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(T.lineSoft))
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    card:SetScript("OnClick", function(self)
        local item = self.item
        if not item or InCombatLockdown() then return end
        if item.link and IsModifiedClick("CHATLINK") then
            HandleModifiedItemClick(item.link)
        elseif self.kind ~= "journal" then
            E:RequestPurchase(item)
        end
    end)
    return card
end

local function DrawCard(card, item, kind)
    card.item, card.kind = item, kind
    card.icon:SetTexture(item.texture or 134400)
    T:PaintItemBorder(card.border, item.quality)
    local color = ITEM_QUALITY_COLORS[item.quality or 1]
    local prefix = kind == "journal" and ((kinds[item.kind] or "") .. " · ") or ""
    card.title:SetText(prefix .. (color and color.hex or "") .. (item.name or "?") .. "|r"
        .. ((item.count or item.quantity or 1) > 1 and (" ×" .. (item.count or item.quantity)) or ""))
    local equip = kind == "catalog" and (item.classID == 2 or item.classID == 4)
    card.level:SetText(E.profile.showItemLevelsOnIcons and equip and item.itemLevel or "")
    local text
    if kind == "journal" then
        text = FormatLogCost(item) .. "  ·  " .. (item.vendor or "") .. "  ·  " .. TimeText("%H:%M", item.time)
    else
        text = E:OfferPrice(item) .. (item.stock == 0 and Text(" · Sold out", " · Нет в наличии") or "")
    end
    card.detail:SetText(text)
    local canBuy = kind == "catalog" or kind == "buyback"
    local colorCost = canBuy and E.profile.colorCostsByAffordability
    local tint = colorCost and (E:CanBuyOffer(item) and {.48,.82,.58,1} or {.88,.43,.39,1}) or T.muted
    Sintezza_Theme:Tint(card.detail, "SetTextColor", tint)
    card:Show()
end

local function Catalogue(kind)
    local items, buyback = {}, kind == "buyback"
    local count = Public(buyback and GetNumBuybackItems() or GetMerchantNumItems(), "number") or 0
    for i = 1, count do
        local offer = E:GetOffer(i, buyback)
        if offer then items[#items + 1] = offer end
    end
    return items
end

local function WindowSession(window)
    local sessions = E:GetJournal() or {}
    window.session = math.max(0, math.min(window.session, #sessions - 1))
    return sessions[#sessions - window.session], #sessions
end

local function VisibleItems(window)
    if window.tab == "journal" then
        local session = WindowSession(window)
        local items = {}
        if session and type(session.entries) == "table" then
            for i = #session.entries, 1, -1 do
                if type(session.entries[i]) == "table" then items[#items + 1] = session.entries[i] end
            end
        end
        return items
    end
    local query, results = Fold(window.search:GetText()), {}
    for _, item in ipairs(Catalogue(window.tab)) do
        if query == "" or Fold(item.name):find(query, 1, true) then results[#results + 1] = item end
    end
    return results
end

local function RepairServices()
    local repair = CanMerchantRepair and Public(CanMerchantRepair(), "boolean") == true
    return repair, repair and CanGuildBankRepair and Public(CanGuildBankRepair(), "boolean") == true
end

local function RepairCost()
    if not GetRepairAllCost then return end
    local cost, available = GetRepairAllCost()
    cost = Public(cost, "number")
    if Public(available, "boolean") and cost and cost > 0 then return cost end
end

local function RepairTip(tooltip)
    local cost = RepairCost()
    if cost then tooltip:AddLine(Coins(cost)) end
end

local function RepairAll(useGuild)
    if not E:CanInteract() or E:LootReviewBusy() then return end
    local repair, guild = RepairServices()
    local cost = RepairCost()
    if not repair or not cost then return end
    if useGuild then
        if guild then RepairAllItems(true) end
    elseif (Public(GetMoney(), "number") or 0) >= cost then
        RepairAllItems()
    end
end

local function JunkItems()
    local merchant = C_MerchantFrame
    if merchant and merchant.GetNumJunkItems and Public(merchant.GetNumJunkItems(), "number") == 0 then return {} end
    return E:GetJunkSaleItems()
end

local function RefreshFooter(window, active, journal)
    local money = Public(GetMoney(), "number")
    window.balanceText:SetText(money and Coins(money) or "—")
    window.balance:SetWidth(math.max(102, window.balanceText:GetStringWidth() + 18))
    window.stock:SetShown(active)

    local trading = active and not journal
    window.tools:SetShown(trading)
    if not trading then return end
    local repair, guild = RepairServices()
    local busy = E:LootReviewBusy()
    local repairMode = InRepairMode and Public(InRepairMode(), "boolean") == true
    local cost = repair and RepairCost()
    local canInteract = not busy and E:CanInteract()
    local function Update(button, visible, enabled, selected, index)
        button:SetShown(visible)
        if not visible then return index end
        button:ClearAllPoints()
        button:SetPoint("LEFT", window.tools, "LEFT", index * (ns.merchantIconSize + 5), 0)
        Available(button, enabled)
        button.icon:SetDesaturated(not enabled)
        T:PaintButton(button, selected == true)
        return index + 1
    end
    local nextButton = Update(window.repairOne, not not repair,
        not busy and (repairMode or canInteract) and type(MerchantRepairItemButton_OnClick) == "function", repairMode, 0)
    nextButton = Update(window.repairAll, not not repair, canInteract and cost and money and money >= cost, false, nextButton)
    nextButton = Update(window.repairGuild, not not guild, canInteract and cost, false, nextButton)
    Update(window.sellJunk, true, canInteract and #JunkItems() > 0, false, nextButton)
end

function E:RefreshMerchantWindow()
    local window = self.merchantWindow
    if not window or not window:IsShown() then return end
    local tab = window.tab
    local journal, catalog, review = tab == "journal", tab == "catalog", tab == "review"
    local active = not not self:HasActiveMerchant()
    RefreshFooter(window, active, journal)
    local showQuickBuyback = catalog and active
    if window.quickBuyback:IsShown() ~= showQuickBuyback then
        window.quickBuyback:SetShown(showQuickBuyback)
        window.buybackDivider:SetShown(showQuickBuyback)
        window.body:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, showQuickBuyback and BUYBACK_DIVIDER_OFFSET + 6 or 86)
        window.status:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", showQuickBuyback and -BUYBACK_PANEL_WIDTH - 24 or -12, 68)
    end
    if showQuickBuyback then RefreshQuickBuyback(window.quickBuyback) end
    for key, button in pairs(window.tabs) do T:PaintButton(button, key == tab) end
    window.body:SetShown(not review)
    window.status:SetShown(not review)
    window.pageLabel:SetShown(not review)
    window.left:SetShown(not review)
    window.right:SetShown(not review)
    window.search:SetShown(not journal and not review)
    window.view:SetShown(catalog or tab == "buyback")
    window.view.text:SetText(self.profile.merchantItemViewMode == "list" and Text("Grid", "Сетка") or Text("List", "Список"))
    window.journalTools:SetShown(journal)
    if review then return end
    if journal then
        local session, count = WindowSession(window)
        window.sessionTitle:SetText(session and (TimeText("%d.%m.%Y %H:%M", session.startedAt)
            .. "  ·  +" .. Coins(session.goldGained) .. "  /  −" .. Coins(session.goldSpent))
            or Text("No transactions", "Нет операций"))
        Available(window.older, window.session + 1 < count)
        Available(window.newer, window.session > 0)
    end
    local items = VisibleItems(window)
    local grid = not journal and self.profile.merchantItemViewMode ~= "list"
    local width, height = window.body:GetSize()
    if width <= 0 or height <= 0 then return end
    local columns = grid and math.max(1, math.floor((width + 6) / 158)) or 1
    local cardWidth = (width - 6 * (columns - 1)) / columns
    local perPage = columns * math.max(1, math.floor(height / 51))
    local pages = math.max(1, math.ceil(#items / perPage))
    window.page = math.min(math.max(1, window.page), pages)
    for index = 1, perPage do
        local item = items[(window.page - 1) * perPage + index]
        if not item then break end
        local card = window.cards[index] or CreateCard(window.body)
        window.cards[index] = card
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", window.body, "TOPLEFT", ((index - 1) % columns) * (cardWidth + 6),
            -math.floor((index - 1) / columns) * 51)
        card:SetSize(cardWidth, 46)
        DrawCard(card, item, tab)
    end
    local shown = math.min(perPage, math.max(0, #items - (window.page - 1) * perPage))
    for index = shown + 1, #window.cards do window.cards[index]:Hide() end
    window.pageLabel:SetText(window.page .. " / " .. pages)
    Available(window.left, window.page > 1)
    Available(window.right, window.page < pages)
    window.empty:SetShown(#items == 0)
    window.status:SetText(self.merchantMessage or "")
end

local function CreateWindow()
    local frame = CreateFrame("Frame", "Sintezza_VendorMerchant", UIParent, "BackdropTemplate")
    local profile = E.profile
    frame:SetSize(760, 530)
    frame:SetPoint("CENTER")
    if profile.merchantFrameUserPlaced and tonumber(profile.merchantFrameCenterX) and tonumber(profile.merchantFrameCenterY) then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", profile.merchantFrameCenterX, profile.merchantFrameCenterY)
    end
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:Hide()
    T:WindowSurface(frame)
    local header = W:WindowHeader(frame, { title = "Sintezza Vendor", icon = ns.Icon })
    local settings = W:Button(header, Text("Settings", "Настройки"), function() E:OpenSettings() end)
    settings:SetWidth(100)
    settings:SetPoint("RIGHT", header.close, "LEFT", -4, 0)
    header.title:SetPoint("RIGHT", settings, "LEFT", -8, 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not E.windowAppearance:CanMove() then return end
        frame.vendorDragging = true
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        if not frame.vendorDragging then return end
        frame.vendorDragging = nil
        frame:StopMovingOrSizing()
        profile.merchantFrameCenterX, profile.merchantFrameCenterY = frame:GetCenter()
        profile.merchantFrameUserPlaced = true
    end)
    frame.tabs, frame.cards, frame.page, frame.session = {}, {}, 1, 0
    UISpecialFrames[#UISpecialFrames + 1] = frame:GetName()
    local previous
    for _, key in ipairs(tabs) do
        local button = Button(frame, tabNames[key], key == "review" and 138 or 99, function() E:OpenMerchantWindow(key) end)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 5, 0) else button:SetPoint("TOPLEFT", 12, -51) end
        previous, frame.tabs[key] = button, button
    end
    frame.search = W:EditBox(frame, Text("Search items", "Поиск предметов"), function() end)
    frame.search:SetPoint("TOPLEFT", 12, -87)
    frame.search:SetWidth(172)
    frame.search:HookScript("OnTextChanged", function() frame.page = 1; E:RefreshMerchantWindow() end)
    frame.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.view = Button(frame, "", 74, function()
        profile.merchantItemViewMode = profile.merchantItemViewMode == "list" and "icons" or "list"
        frame.page = 1
        E:RefreshMerchantWindow()
    end)
    frame.view:SetPoint("TOPRIGHT", -12, -88)
    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", 12, -125)
    frame.body:SetPoint("BOTTOMRIGHT", -12, 86)
    frame.empty = Label(frame.body, 13, T.muted)
    frame.empty:SetText(Text("No items to display", "Нет предметов для показа"))
    frame.empty:SetPoint("CENTER")
    frame.journalTools = CreateFrame("Frame", nil, frame)
    frame.journalTools:SetSize(540, 28)
    frame.journalTools:SetPoint("TOPLEFT", 12, -87)
    local function StepSession(delta)
        frame.session, frame.page = frame.session + delta, 1
        E:RefreshMerchantWindow()
    end
    frame.older = T:ButtonArrow(Button(frame.journalTools, "", 25, function() StepSession(1) end), "left")
    frame.older:SetPoint("LEFT")
    frame.newer = T:ButtonArrow(Button(frame.journalTools, "", 25, function() StepSession(-1) end), "right")
    frame.newer:SetPoint("LEFT", frame.older, "RIGHT", 4, 0)
    frame.sessionTitle = Label(frame.journalTools, 11, T.text)
    frame.sessionTitle:SetPoint("LEFT", frame.newer, "RIGHT", 8, 0)
    frame.journalData = Button(frame.journalTools, Text("Journal data", "Данные журнала"), 130, function(self)
        E:OpenJournalData(self)
    end)
    frame.journalData:SetPoint("RIGHT")
    local function Step(delta)
        frame.page = frame.page + delta
        E:RefreshMerchantWindow()
    end
    frame.pageLabel = Label(frame, 11, T.muted)
    frame.pageLabel:SetPoint("BOTTOM", 0, 18)
    frame.left = T:ButtonArrow(Button(frame, "", 26, function() Step(-1) end), "left")
    frame.left:SetPoint("RIGHT", frame.pageLabel, "LEFT", -8, 0)
    frame.right = T:ButtonArrow(Button(frame, "", 26, function() Step(1) end), "right")
    frame.right:SetPoint("LEFT", frame.pageLabel, "RIGHT", 8, 0)
    frame.body:EnableMouseWheel(true)
    frame.body:SetScript("OnMouseWheel", function(_, delta) Step(delta > 0 and -1 or 1) end)
    frame.status = Label(frame, 10, T.muted)
    frame.status:SetPoint("BOTTOMLEFT", 12, 68)
    frame.status:SetPoint("BOTTOMRIGHT", -12, 68)
    frame.tools = CreateFrame("Frame", nil, frame)
    frame.tools:SetSize(4 * (ns.merchantIconSize + 5), ns.merchantIconSize)
    frame.tools:SetPoint("BOTTOMLEFT", 12, 10)
    frame.repairOne = ns.CreateMerchantIcon(frame.tools, {
        atlas = "SpellIcon-256x256-Repair", texture = "Interface\\Icons\\INV_Hammer_01", crop = .13,
    }, labels.repairOne, function()
        if not E:HasActiveMerchant() or E:LootReviewBusy() or type(MerchantRepairItemButton_OnClick) ~= "function" then return end
        local repair = RepairServices()
        if repair and ((InRepairMode and Public(InRepairMode(), "boolean")) or E:CanInteract()) then
            MerchantRepairItemButton_OnClick()
            E:RefreshMerchantWindow()
        end
    end)
    frame.repairAll = ns.CreateMerchantIcon(frame.tools, {
        atlas = "SpellIcon-256x256-RepairAll", texture = "Interface\\Icons\\Trade_BlackSmithing", crop = .13,
    }, labels.repairAll, function() RepairAll(false) end, RepairTip)
    frame.repairGuild = ns.CreateMerchantIcon(frame.tools, {
        atlas = "SpellIcon-256x256-RepairAllGuild", texture = "Interface\\Icons\\INV_Misc_Coin_01", crop = .13,
    }, labels.repairGuild, function() RepairAll(true) end, function(tooltip)
        RepairTip(tooltip)
        tooltip:AddLine(labels.repairGuildTip, .85, .8, .68, true)
    end)
    frame.sellJunk = ns.CreateMerchantIcon(frame.tools, {
        atlas = "SpellIcon-256x256-SellJunk", texture = "Interface\\Icons\\INV_Misc_Bag_10", crop = .13,
    }, labels.sellJunk, function()
        if not E:CanInteract() or E:LootReviewBusy() then return end
        E:SelectNativeBuyTab()
        E:RequestQuickSale(JunkItems(), true)
    end)
    frame.stock = ns.CreateMerchantIcon(frame, {
        atlas = "common-icon-backarrow", texture = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
    }, labels.stock, function() E:ShowStandardMerchant() end)
    frame.stock:SetPoint("BOTTOMRIGHT", -32, 10)
    frame.balance = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.balance:SetSize(102, ns.merchantIconSize)
    frame.balance:SetPoint("RIGHT", frame.stock, "LEFT", -6, 0)
    T:Backdrop(frame.balance, T.input, T.lineSoft)
    frame.balanceText = Label(frame.balance, 12, T.text)
    frame.balanceText:SetPoint("CENTER")
    frame.buybackDivider = frame:CreateTexture(nil, "BORDER")
    frame.buybackDivider:SetPoint("BOTTOMLEFT", 12, BUYBACK_DIVIDER_OFFSET)
    frame.buybackDivider:SetPoint("BOTTOMRIGHT", -12, BUYBACK_DIVIDER_OFFSET)
    frame.buybackDivider:SetHeight(1)
    Sintezza_Theme:SnapTexture(frame.buybackDivider)
    Sintezza_Theme:Tint(frame.buybackDivider, "SetColorTexture", T.line)
    frame.buybackDivider:Hide()
    frame.quickBuyback = CreateQuickBuyback(frame)
    frame:SetScript("OnSizeChanged", function() E:RefreshMerchantWindow() end)
    frame:SetScript("OnHide", function()
        frame.vendorDragging = nil
        frame:StopMovingOrSizing()
        frame.search:ClearFocus()
        E:CancelPurchase()
        E:CloseLootReview()
        E:MerchantViewHidden()
    end)
    E.windowAppearance:Bind(frame, {
        defaultLayer = "HIGH",
        resize = {
            minWidth = 650, minHeight = 430, maxWidth = 1000, maxHeight = 760,
            read = function() return profile.merchantFrameWidth, profile.merchantFrameHeight end,
            save = function(width, height) profile.merchantFrameWidth, profile.merchantFrameHeight = width, height end,
        },
    })
    return frame
end

function E:OpenMerchantWindow(tab)
    tab = tab or "catalog"
    local active = self:HasActiveMerchant()
    if InCombatLockdown() or (tab ~= "journal" and not active) then return end
    if active and not self:ConcealNativeMerchant() then return end
    self.merchantWindow = self.merchantWindow or CreateWindow()
    local window = self.merchantWindow
    if window.tab ~= tab then
        self:CancelPurchase()
        self:CloseLootReview()
        window.tab, window.page = tab, 1
        window.search:SetText("")
    end
    if tab ~= "journal" then self:SelectNativeBuyTab() end
    self:ApplyAppearance()
    window:Show()
    window:Raise()
    self:RefreshMerchantWindow()
    if tab == "review" then self:ShowLootReview(window) end
end

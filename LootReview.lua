local _, ns = ...
local Text = ns.Text
local E, T = ns.vendor, ns.Theme
local widgets = Sintezza_Theme:CreateWidgets(T)
local ROW_HEIGHT = 34
local MAX_ROWS = 24
local AUCTION_CUT = .05
local PRICE_LABELS = { Text("Vendor", "Торговец"), Text("Auction", "Аукцион"), Text("Disenchant", "Распыление") }

local function SafeNumber(value)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value))
        and value >= 0 and value < math.huge
end

local function MarketPrice(item)
    if item.bound == nil then return end
    if item.bindType ~= 0 and item.bindType ~= 2 and item.bindType ~= 3 then return end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or not api.GetAuctionPriceByItemLink or not item.link then return end
    local ok, copper = pcall(api.GetAuctionPriceByItemLink, E.addonName, item.link)
    if ok and SafeNumber(copper) and copper > 0 then return copper * item.count end
end

local function DisenchantPrice(item)
    if item.quality < 2 or item.quality > 4 or item.equipLoc == "" or item.subclassID == 5 and item.classID == 4
        or (item.classID and item.classID ~= 2 and item.classID ~= 4) then return nil, false, true end
    if not item.equipLoc or not item.classID then return end
    local api = Sintezza_DisenchantAPI
    if type(api) == "table" and type(api.GetDisenchantEstimate) == "function" then
        local ok, copper, missing = pcall(api.GetDisenchantEstimate, item)
        if ok and SafeNumber(copper) and copper > 0 then
            return copper * item.count, not (SafeNumber(missing) and missing == 0)
        end
    end
    local auction = Auctionator and Auctionator.API and Auctionator.API.v1
    if auction and auction.GetDisenchantPriceByItemLink then
        local ok, copper = pcall(auction.GetDisenchantPriceByItemLink, E.addonName, item.link)
        -- Auctionator can omit materials with no scan price.
        if ok and SafeNumber(copper) and copper > 0 then return copper * item.count, true end
    end
end

local function AfterAuctionCut(value, alreadyNet)
    if value and not alreadyNet then return math.floor(value * (1 - AUCTION_CUT) + .5) end
    return value
end

local function ComparePrices(item, advice)
    if advice and (advice.guid ~= item.guid or advice.link ~= item.link or advice.count ~= item.count) then advice = nil end
    item.advice = advice
    local vendor = SafeNumber(item.value) and item.value or nil
    local market, disenchant, marketFallback, disenchantFallback
    item.marketReason = (item.bound or item.bindType == 1) and Text("Soulbound", "Привязан") or nil
    if not item.marketReason then
        local price = advice and advice.auction
        if price and price > 0 then
            market = AfterAuctionCut(price * item.count, advice.afterAuctionCut)
        else
            market, marketFallback = AfterAuctionCut(MarketPrice(item)), true
        end
    end
    local price = advice and advice.disenchant
    local api = Sintezza_DisenchantAPI
    local checked, blocked
    if type(api) == "table" and type(api.IsDisenchantBlocked) == "function" then
        checked, blocked = pcall(api.IsDisenchantBlocked, item)
    end
    if checked and not (issecretvalue and issecretvalue(blocked)) and blocked == true then
        item.partial, item.disenchantUnavailable = false, true
    elseif price and price > 0 then
        disenchant = AfterAuctionCut(price * item.count, advice.afterAuctionCut)
        item.partial, item.disenchantUnavailable = false, nil
    else
        disenchant, item.partial, item.disenchantUnavailable = DisenchantPrice(item)
        disenchant = AfterAuctionCut(disenchant)
        disenchantFallback = not item.disenchantUnavailable
    end
    item.priceFallback = marketFallback or disenchantFallback
    item.netPrices = { vendor, market, disenchant }
    item.incomplete = vendor == nil or (market == nil and not item.marketReason)
        or (disenchant == nil and not item.disenchantUnavailable) or item.partial == true
    local best = math.max(vendor or 0, market or 0, disenchant or 0)
    item.bestPrice = not item.incomplete and best > 0 and best or nil
end

local function VendorWins(item)
    local vendor, market, disenchant = unpack(item.netPrices, 1, 3)
    local verdict = item.advice and item.advice.verdict
    if verdict and verdict ~= "vendor" and verdict ~= "unknown"
        and not (verdict == "disenchant" and item.disenchantUnavailable) then return false end
    return item.bestPrice ~= nil and item.bestPrice == vendor
        and vendor > (market or 0) and vendor > (disenchant or 0)
end

function E:IsLootReviewOpen()
    return self.lootReviewPanel and self.lootReviewPanel:IsVisible()
end

function E:ValidateLootReviewStack(expected, current)
    if not current or current.itemID ~= expected.itemID or current.link ~= expected.link
        or current.count ~= expected.count or current.value ~= expected.value
        or not expected.guid or current.guid ~= expected.guid then
        return false, Text("the stack changed", "стопка изменилась")
    end
    local ready, reason = self:CanSellItem(current, expected.manualSale)
    if not ready then return false, reason end
    if expected.vendorOnly then
        ComparePrices(current, expected.advice)
        if not VendorWins(current) then return false, Text("the vendor no longer pays the most", "торговец больше не лучший вариант") end
    end
    return true
end

local function OrderReviewItems(panel)
    local selected = panel.selected
    table.sort(panel.items, function(a, b)
        if panel.selectedFirst then
            local aSelected, bSelected = selected[a.key] ~= nil, selected[b.key] ~= nil
            if aSelected ~= bSelected then return aSelected end
        end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.name ~= b.name then return a.name < b.name end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
end

function E:ScanLootReview(panel, items)
    local previous, selected = panel.selected, {}
    items = items or self:BagItems()
    for _, item in ipairs(items) do
        item.sellable, item.reason = self:CanSellItem(item, true)
        ComparePrices(item, panel.advice and panel.advice[item.key])
        local prior = previous[item.key]
        if prior and item.sellable and self:ValidateLootReviewStack(prior, item) then
            item.vendorOnly = prior.vendorOnly
            item.manualSale = prior.manualSale
            selected[item.key] = item
        end
    end
    panel.items, panel.selected = items, selected
    OrderReviewItems(panel)
end

local function Label(parent, text, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY")
    T:Font(label, size, "", color)
    label:SetText(text)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

local function Button(parent, text, width, click, primary)
    local button = widgets:Button(parent, text, click, primary)
    button:SetWidth(width)
    return button
end

local function PriceColumn(row, text, column)
    local label = Label(row, text, 11, T.muted)
    label:SetWidth(82)
    label:SetJustifyH("RIGHT")
    label:SetPoint("RIGHT", row, "RIGHT", -8 - (3 - column) * 88, 0)
    return label
end

local function CreateRow(panel, i)
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", panel.heading, "BOTTOMLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", panel.heading, "BOTTOMRIGHT", 0, -(i - 1) * ROW_HEIGHT)
    local rule = row:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    Sintezza_Theme:Tint(rule, "SetColorTexture", T.lineSoft, .45)
    row.fill = row:CreateTexture(nil, "BACKGROUND")
    row.fill:SetAllPoints(row)
    row.check = CreateFrame("CheckButton", nil, row, "BackdropTemplate")
    row.check:SetSize(18, 18)
    row.check:SetPoint("LEFT", row, "LEFT", 6, 0)
    T:SkinCheckButton(row.check, 16)
    if row.check.SetMotionScriptsWhileDisabled then row.check:SetMotionScriptsWhileDisabled(true) end
    row.exclude = Button(row, "x", 22, function()
        local item = row.item
        if not item or E:LootReviewBusy() then return end
        local current = E:GetBagItem(item.bag, item.slot)
        if current and current.itemID == item.itemID then
            E:ToggleExcluded(item.itemID)
        else
            E:RefreshLootReview(true)
        end
    end)
    row.exclude:SetPoint("LEFT", row.check, "RIGHT", 5, 0)
    row.exclude:HookScript("OnEnter", function(self)
        local item = row.item
        if not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(E:IsExcluded(item.itemID) and ns.MerchantLabels.include or ns.MerchantLabels.exclude)
        GameTooltip:Show()
    end)
    row.exclude:HookScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    row.iconFrame = CreateFrame("Frame", nil, row)
    row.iconFrame:SetSize(22, 22)
    row.iconFrame:SetPoint("LEFT", row.exclude, "RIGHT", 7, 0)
    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetAllPoints(row.iconFrame)
    row.icon:SetTexCoord(.07, .93, .07, .93)
    row.iconBorder = T:FrameIcon(row.iconFrame, row.icon)
    row.level = Label(row.iconFrame, "", 9, T.text)
    row.level:SetPoint("BOTTOMRIGHT")
    row.name = Label(row, "", 11, T.text)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.prices = {}
    for col = 1, 3 do row.prices[col] = PriceColumn(row, "", col) end
    row.name:SetPoint("RIGHT", row.prices[1], "LEFT", -8, 0)
    local function Click()
        local item = row.item
        if item and not E:LootReviewBusy() then
            if not item.sellable then
                panel.message = item.reason
                E:RefreshLootReview(false)
                return
            end
            panel.message = nil
            if panel.selected[item.key] then
                panel.selected[item.key] = nil
            else
                item.vendorOnly = nil
                item.manualSale = true
                panel.selected[item.key] = item
            end
        end
        E:RefreshLootReview(false)
    end
    row:SetScript("OnClick", Click)
    row.check:SetScript("OnClick", Click)
    local function Tooltip(owner)
        if not row.item then return end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(row.item.bag, row.item.slot)
        if row.item.advice then GameTooltip:AddLine("Mastercraft · " .. row.item.advice.label, .75, .66, .95) end
        if row.item.incomplete then
            GameTooltip:AddLine(Text("Not enough data to compare.", "Для сравнения не хватает данных."), unpack(T.muted, 1, 3))
        elseif row.item.bestPrice then
            local best = {}
            for i, label in ipairs(PRICE_LABELS) do
                if row.item.netPrices[i] == row.item.bestPrice then best[#best + 1] = label end
            end
            local prefix = #best == 1 and Text("Best return · ", "Выгоднее · ") or Text("Same return · ", "Одинаковая выручка · ")
            GameTooltip:AddLine(prefix .. table.concat(best, " / "), unpack(T.accent, 1, 3))
        end
        if not row.item.sellable then
            GameTooltip:AddLine(row.item.reason, .79, .74, .64, true)
        end
        GameTooltip:Show()
    end
    row:SetScript("OnEnter", Tooltip)
    row.check:HookScript("OnEnter", Tooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.check:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function CreatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", 2, -86)
    panel:SetPoint("BOTTOMRIGHT", -2, 40)
    panel:Hide()
    panel.items, panel.selected, panel.rows, panel.advice, panel.page = {}, {}, {}, {}, 1
    local banner = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    banner:SetPoint("TOPLEFT", 10, 0)
    banner:SetPoint("TOPRIGHT", -10, 0)
    banner:SetHeight(26)
    T:SectionSurface(banner)
    local note = Label(banner, Text("Compare proceeds per stack. Auction and disenchant values include the 5% fee.",
        "Сравни выручку за стопку. Аукцион и распыление показаны с учетом комиссии 5%."), 10, T.muted)
    note:SetPoint("LEFT", 8, 0)
    note:SetPoint("RIGHT", -8, 0)
    local heading = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    heading:SetPoint("TOPLEFT", banner, "BOTTOMLEFT")
    heading:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT")
    heading:SetHeight(24)
    T:Backdrop(heading, T.sidebar, T.lineSoft)
    panel.heading = heading
    Label(heading, Text("Item", "Предмет"), 11, T.text):SetPoint("LEFT", 7, 0)
    for i, name in ipairs(PRICE_LABELS) do PriceColumn(heading, name, i) end
    panel.summary = Label(panel, "", 11, T.text)
    panel.summary:SetPoint("BOTTOMLEFT", 12, 25)
    panel.markBest = Button(panel, Text("Mark vendor picks", "Отметить выгодные"), 122, function() E:SelectVendorWinners() end)
    panel.markBest:SetPoint("BOTTOMLEFT", 10, 57)
    panel.status = Label(panel, "", 10, T.muted)
    panel.status:SetPoint("BOTTOMLEFT", 12, 85)
    panel.status:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    panel.clear = Button(panel, Text("Clear", "Снять все"), 77, function()
        panel.selected, panel.selectedFirst, panel.page = {}, nil, 1
        OrderReviewItems(panel)
        E:RefreshLootReview(false)
    end)
    panel.clear:SetPoint("LEFT", panel.markBest, "RIGHT", 6, 0)
    panel.refresh = Button(panel, Text("Refresh", "Обновить"), 77, function()
        panel.message = nil
        E:RefreshLootReview(true)
    end)
    panel.refresh:SetPoint("LEFT", panel.clear, "RIGHT", 6, 0)
    panel.priceSource = Label(panel, "", 10, T.warning)
    panel.priceSource:SetPoint("LEFT", panel.refresh, "RIGHT", 8, 0)
    panel.priceSource:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    panel.priceSource:SetJustifyH("RIGHT")
    panel.priceSource:SetWordWrap(true)
    panel.sell = Button(panel, Text("Sell", "Продать"), 96, function() E:ConfirmLootReview() end, true)
    panel.sell:SetPoint("BOTTOMRIGHT", -10, 10)
    panel.previous = T:ButtonArrow(Button(panel, "", 22, function() E:ChangeLootReviewPage(-1) end), "left")
    panel.next = T:ButtonArrow(Button(panel, "", 22, function() E:ChangeLootReviewPage(1) end), "right")
    panel.pageText = Label(panel, "", 11, T.muted)
    panel.pageText:SetPoint("BOTTOM", 0, 23)
    panel.previous:SetPoint("RIGHT", panel.pageText, "LEFT", -6, 0)
    panel.next:SetPoint("LEFT", panel.pageText, "RIGHT", 6, 0)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta) E:ChangeLootReviewPage(delta > 0 and -1 or 1) end)
    panel:SetScript("OnSizeChanged", function() E:RefreshLootReview(false) end)
    return panel
end

function E:LootReviewBusy(ignorePurchaseQueue)
    return self.saleActive or self.lootReviewConfirm or self.quickSale or self.purchaseActive
        or self.purchaseConfirm or (not ignorePurchaseQueue and self.purchaseQueue) or InCombatLockdown()
end

local function SetEnabled(button, enabled)
    if enabled then button:Enable() else button:Disable() end
end

local function Money(value)
    if value == nil then return "—" end
    return C_CurrencyInfo.GetCoinTextureString(math.floor(value + .5), 12)
end

local function PaintPrices(row, item)
    local vendor, market, disenchant = unpack(item.netPrices, 1, 3)
    row.prices[1]:SetText(vendor == nil and Text("No price", "Нет цены") or (vendor > 0 and Money(vendor) or "—"))
    row.prices[2]:SetText(item.marketReason or (market == nil and Text("No price", "Нет цены") or Money(market)))
    row.prices[3]:SetText(disenchant and ("≈ " .. Money(disenchant) .. (item.partial and "*" or ""))
        or (item.disenchantUnavailable and "—" or Text("No data", "Нет данных")))
    for i, label in ipairs(row.prices) do
        local value = item.netPrices[i]
        local winning = item.bestPrice and value == item.bestPrice
        Sintezza_Theme:Tint(label, "SetTextColor", winning and T.accent or value and value > 0 and T.text or T.muted)
    end
end

function E:RefreshLootReview(scan)
    if ns.PerfBridge then ns.PerfBridge.Count("refresh") end
    if not self:IsLootReviewOpen() then return end
    local panel = self.lootReviewPanel
    if scan then self:ScanLootReview(panel) end
    local perPage = math.max(1, math.min(MAX_ROWS, math.floor((panel:GetHeight() - 153) / ROW_HEIGHT)))
    local pages = math.max(1, math.ceil(#panel.items / perPage))
    panel.page = math.max(1, math.min(panel.page, pages))
    local busy = self:LootReviewBusy()
    for i = 1, perPage do
        local item = panel.items[(panel.page - 1) * perPage + i]
        local row = panel.rows[i]
        if item then
            row = row or CreateRow(panel, i)
            panel.rows[i], row.item = row, item
            row.icon:SetTexture(item.texture or 134400)
            T:PaintItemBorder(row.iconBorder, item.quality)
            row.level:SetText(self.profile.showItemLevelsOnIcons and item.equipLoc and item.equipLoc ~= ""
                and item.itemLevel or "")
            local color = ITEM_QUALITY_COLORS[item.quality]
            row.name:SetText((color and color.hex or "") .. item.name .. "|r"
                .. (item.count > 1 and (" ×" .. item.count) or "")
                .. (item.advice and (" · " .. item.advice.label) or ""))
            PaintPrices(row, item)
            local checked = panel.selected[item.key] ~= nil
            row.check:SetChecked(checked)
            local noVendorValue = item.noValue == true or item.value ~= nil and item.value <= 0
            local fill = checked and T.accentDim or noVendorValue and T.danger or T.text
            local alpha = checked and .30 or noVendorValue and .10 or (i % 2 == 0 and .04 or .015)
            Sintezza_Theme:Tint(row.fill, "SetColorTexture", fill, alpha)
            SetEnabled(row.check, not busy)
            local excluded = self:IsExcluded(item.itemID)
            row.icon:SetDesaturated(excluded)
            row.icon:SetAlpha(excluded and .55 or 1)
            row.name:SetAlpha(excluded and .60 or 1)
            row.exclude.text:SetText(excluded and "+" or "x")
            SetEnabled(row.exclude, self.blacklist and not busy)
            T:PaintButton(row.exclude, excluded)
            row:Show()
        elseif row then row:Hide() end
    end
    for i = perPage + 1, #panel.rows do panel.rows[i]:Hide() end
    local total, stacks = 0, 0
    for _, item in pairs(panel.selected) do total, stacks = total + item.value, stacks + 1 end
    panel.summary:SetText((Text("%d stacks selected · %s", "Выбрано стопок: %d · %s")):format(stacks, Money(total)))
    local status = panel.message
    if not status then
        if #panel.items == 0 then
            status = Text("No item data available in your bags.", "В сумках нет доступных данных.")
        else
            for _, item in ipairs(panel.items) do
                if item.partial then status = Text("* Incomplete disenchant estimate.", "* Неполная оценка распыления."); break end
            end
        end
    end
    panel.status:SetText(status or "")
    panel.priceSource:SetText(panel.priceSourceMessage or "")
    panel.pageText:SetText(panel.page .. " / " .. pages)
    SetEnabled(panel.previous, panel.page > 1)
    SetEnabled(panel.next, panel.page < pages)
    SetEnabled(panel.clear, stacks > 0 and not busy)
    local merchant = not busy and self:CanUseSale()
    SetEnabled(panel.sell, stacks > 0 and merchant)
    SetEnabled(panel.markBest, #panel.items > 0 and not busy)
end

function E:ChangeLootReviewPage(delta)
    self.lootReviewPanel.page = self.lootReviewPanel.page + delta
    self:RefreshLootReview(false)
end

function E:OpenLootReview()
    self:OpenMerchantWindow("review")
end

function E:ShowLootReview(parent)
    self.lootReviewPanel = self.lootReviewPanel or CreatePanel(parent)
    self.lootReviewPanel:Show()
    self:RefreshLootReview(true)
end

function E:CancelLootReviewConfirmation()
    if not self.lootReviewConfirm then return end
    self:HideSaleConfirmation()
    self.lootReviewConfirm = nil
end

function E:CloseLootReview()
    self:CancelLootReviewConfirmation()
    local panel = self.lootReviewPanel
    if panel then
        panel.selected, panel.selectedFirst = {}, nil
        panel.advice = {}
        panel.message, panel.priceSourceMessage, panel.page = nil, nil, 1
        if panel:IsShown() then panel:Hide() end
    end
end

local function SelectedSale(panel)
    local items, total = {}, 0
    for _, item in ipairs(panel.items) do
        if panel.selected[item.key] then
            items[#items + 1] = item
            total = total + item.value
        end
    end
    if #items > 0 then return { items = items, total = total } end
end

function E:SelectVendorWinners()
    if not self:IsLootReviewOpen() or self:LootReviewBusy() then return end
    local panel = self.lootReviewPanel
    local items = self:BagItems()
    local advice, fallback = self:ReadMastercraft(items, panel)
    panel.advice = advice or {}
    panel.selected = {}
    self:ScanLootReview(panel, items)
    for _, item in ipairs(panel.items) do
        if item.sellable and self:CanSellItem(item) then
            if not fallback and (not item.advice or item.priceFallback) then
                fallback = Text("Partial Mastercraft data · fallback", "Часть данных Mastercraft недоступна · резервная оценка")
            end
            if VendorWins(item) then
                item.vendorOnly = true
                panel.selected[item.key] = item
            end
        end
    end
    panel.selectedFirst, panel.page = true, 1
    OrderReviewItems(panel)
    panel.priceSourceMessage = fallback
    panel.message = not next(panel.selected) and Text("No stacks return more at the vendor than either alternative.",
        "Нет стопок, для которых торговец строго выгоднее.") or nil
    self:RefreshLootReview(false)
end

function E:ConfirmLootReview()
    if not self:IsLootReviewOpen() or self:LootReviewBusy() or not self:CanUseSale() then return end
    local pending = SelectedSale(self.lootReviewPanel)
    if not pending then return end
    self.lootReviewConfirm = pending
    local function Cancel()
        if self.lootReviewConfirm ~= pending then return end
        self.lootReviewConfirm = nil
        self:RefreshLootReview(false)
    end
    if not self:ShowSaleConfirmation(pending.items, pending.total, function() self:AcceptLootReview(pending) end, Cancel) then
        self.lootReviewConfirm = nil
    end
    self:RefreshLootReview(false)
end

function E:AcceptLootReview(pending)
    if not pending or self.lootReviewConfirm ~= pending then return end
    self.lootReviewConfirm = nil
    if self:LootReviewBusy() or not self:IsLootReviewOpen() or not self:CanUseSale() then
        self:RefreshLootReview(false)
        return
    end
    for _, item in ipairs(pending.items) do
        if not self:ValidateLootReviewStack(item, self:GetBagItem(item.bag, item.slot)) then
            self.lootReviewPanel.message = Text("The stack or price changed. Check your selection.", "Стопка или цена изменились. Проверь выбор.")
            self:RefreshLootReview(true)
            return
        end
    end
    self.lootReviewPanel.message = Text("Selling selected items…", "Продажа выбранных вещей…")
    self:BeginSale(pending.items)
end

function E:LootReviewSaleFinished(queue, stopped)
    local message = (Text("%d stacks sold · %s", "Продано стопок: %d · %s")):format(queue.soldStacks, Money(queue.soldTotal))
    if stopped then
        message = message .. Text(" · Sale stopped", " · Продажа остановлена")
    end
    self.merchantMessage = message
    if not self:IsLootReviewOpen() then return end
    self.lootReviewPanel.message = message
    self:RefreshLootReview(true)
end

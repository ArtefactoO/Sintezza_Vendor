local _, ns = ...
local E, Public = ns.vendor, ns.Public
local Text = ns.Text
local MAX_CHECKS = 12
local CHECK_INTERVAL = .10
local SALE_ROW_HEIGHT = 34
local SALE_VISIBLE_ROWS = 4

local function CreateSaleConfirmation()
    local T = ns.Theme
    local W = Sintezza_Theme:CreateWidgets(T)
    local dialog = CreateFrame("Frame", "Sintezza_VendorSaleWindow", UIParent, "BackdropTemplate")
    dialog:Hide()
    dialog:SetSize(440, 254)
    dialog:SetPoint("CENTER", UIParent, "CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    T:WindowSurface(dialog)
    local header = W:WindowHeader(dialog, { title = Text("Confirm sale", "Подтверждение продажи"), icon = ns.Icon })
    local scroll, body, bar = W:ScrollFrame(dialog, nil, SALE_ROW_HEIGHT)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 14, -10)
    scroll:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -27, -10)
    scroll:SetHeight(SALE_ROW_HEIGHT * SALE_VISIBLE_ROWS)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    scroll:HookScript("OnSizeChanged", function(_, width) body:SetWidth(math.max(1, width)) end)
    dialog.scroll, dialog.body, dialog.rows = scroll, body, {}
    dialog.total = W:Label(dialog, "", 11, T.text)
    dialog.total:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 14, 44)
    dialog.total:SetPoint("RIGHT", dialog, "RIGHT", -14, 0)
    local cancel = W:Button(dialog, Text("Cancel", "Отмена"), function() dialog:Hide() end)
    cancel:SetSize(112, 24)
    cancel:SetPoint("BOTTOMRIGHT", -12, 10)
    local accept = W:Button(dialog, Text("Sell", "Продать"), function()
        local pending = dialog.pending
        if not pending then return end
        dialog.pending = nil
        dialog:Hide()
        pending.accept()
    end, true)
    accept:SetSize(112, 24)
    accept:SetPoint("RIGHT", cancel, "LEFT", -6, 0)
    dialog:SetScript("OnHide", function()
        local pending = dialog.pending
        dialog.pending = nil
        if GameTooltip:IsOwned(dialog) then GameTooltip:Hide() end
        if pending and pending.cancel then pending.cancel() end
    end)
    UISpecialFrames[#UISpecialFrames + 1] = dialog:GetName()
    return dialog
end

local function SaleRow(dialog, index)
    local T = ns.Theme
    local W = Sintezza_Theme:CreateWidgets(T)
    local row = CreateFrame("Frame", nil, dialog.body)
    row:SetHeight(SALE_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", dialog.body, "TOPLEFT", 0, -(index - 1) * SALE_ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", dialog.body, "TOPRIGHT", 0, -(index - 1) * SALE_ROW_HEIGHT)
    local iconBox = CreateFrame("Frame", nil, row)
    iconBox:SetSize(27, 27)
    iconBox:SetPoint("LEFT", 2, 0)
    row.icon = iconBox:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints()
    row.icon:SetTexCoord(.07, .93, .07, .93)
    row.border = T:FrameIcon(iconBox, row.icon)
    row.price = W:Label(row, "", 11, T.text)
    row.price:SetWidth(110)
    row.price:SetJustifyH("RIGHT")
    row.price:SetPoint("RIGHT", -3, 0)
    row.name = W:Label(row, "", 11, T.text)
    row.name:SetPoint("LEFT", iconBox, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -8, 0)
    row.name:SetWordWrap(false)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(owner)
        if not owner.item or not owner.item.link then return end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(owner.item.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(owner) if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end end)
    row:SetScript("OnHide", function(owner) if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end end)
    return row
end

function E:ShowSaleConfirmation(items, total, accept, cancel)
    local dialog = self.saleDialog or CreateSaleConfirmation()
    self.saleDialog = dialog
    if dialog.pending then return false end
    dialog.pending = { accept = accept, cancel = cancel }
    for index, item in ipairs(items) do
        local row = dialog.rows[index] or SaleRow(dialog, index)
        dialog.rows[index], row.item = row, item
        row.icon:SetTexture(item.texture or 134400)
        ns.Theme:PaintItemBorder(row.border, item.quality)
        local color = ITEM_QUALITY_COLORS[item.quality or 1]
        row.name:SetText((color and color.hex or "") .. (item.name or "?") .. "|r"
            .. (item.count > 1 and (" ×" .. item.count) or ""))
        row.price:SetText(C_CurrencyInfo.GetCoinTextureString(item.value, 12))
        row:Show()
    end
    for index = #items + 1, #dialog.rows do dialog.rows[index]:Hide() end
    dialog.body:SetHeight(math.max(1, #items * SALE_ROW_HEIGHT))
    dialog.scroll:SetVerticalScroll(0)
    dialog.total:SetText(Text("Total: ", "Итого: ") .. C_CurrencyInfo.GetCoinTextureString(total, 12))
    dialog:Show()
    dialog.scroll:RefreshRange()
    dialog:Raise()
    return true
end

function E:HideSaleConfirmation()
    if self.saleDialog then self.saleDialog:Hide() end
end

local function SaleKey(itemID, price, count)
    return itemID .. ":" .. price .. ":" .. count
end

local function BuybackCounts()
    local matches = {}
    local count = Public(GetNumBuybackItems(), "number")
    if not count then return end
    for index = 1, count do
        local _, _, price, quantity = GetBuybackItemInfo(index)
        local link = Public(GetBuybackItemLink(index), "string")
        price, quantity = Public(price, "number"), Public(quantity, "number")
        if not link or not price or not quantity then return end
        local itemID = tonumber(link:match("|Hitem:(%d+)"))
        if not itemID then return end
        local key = SaleKey(itemID, price, quantity)
        matches[key] = (matches[key] or 0) + 1
    end
    return matches
end

function E:SnapshotManualSales()
    if not self:HasActiveMerchant() or InCombatLockdown() then return end
    local buybacks = BuybackCounts()
    if not buybacks then self.manualSaleSnapshot = nil; return end
    local snapshot = {}
    for _, item in ipairs(self:BagItems()) do
        if item.value and item.value > 0 then
            item.saleKey = SaleKey(item.itemID, item.value, item.count)
            item.buybackCount = buybacks[item.saleKey] or 0
            snapshot[item.bag .. ":" .. item.slot] = item
        end
    end
    self.manualSaleSnapshot = snapshot
end

function E:InstallManualSaleObserver()
    if self.manualSaleObserver then return end
    self.manualSaleObserver = true
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
        if E.saleActive or E.purchaseActive or not E.interaction or not E:CanUseSale() then return end
        if not Public(bag, "number") or not Public(slot, "number") then return end
        local item = E.manualSaleSnapshot and E.manualSaleSnapshot[bag .. ":" .. slot]
        if not item or item.buybackCount == nil then return end
        E.manualSalePending = E.manualSalePending or {}
        local group = E.manualSalePending[item.saleKey]
        if not group or group.interaction ~= E.interaction then
            group = { interaction = E.interaction, baseline = item.buybackCount, confirmed = 0, slots = {} }
            E.manualSalePending[item.saleKey] = group
        end
        local slotKey = bag .. ":" .. slot
        if group.slots[slotKey] then return end
        local interaction = E.interaction
        local vendor, vendorID = E:MerchantIdentity()
        local pending = {}
        group.slots[slotKey] = pending
        local function Release()
            group.slots[slotKey] = nil
            if not next(group.slots) and E.manualSalePending[item.saleKey] == group then
                E.manualSalePending[item.saleKey] = nil
            end
        end
        local checks = 0
        local function ConfirmManualSale()
            if group.slots[slotKey] ~= pending then return end
            if E.interaction ~= interaction or InCombatLockdown() then Release(); return end
            local raw = C_Container.GetContainerItemInfo(bag, slot)
            local current = Public(raw, "table")
            local currentID = current and Public(current.itemID, "number")
            local buybacks = BuybackCounts()
            if not (issecretvalue and issecretvalue(raw)) and raw == nil
                and buybacks and (buybacks[item.saleKey] or 0) > group.baseline + group.confirmed then
                group.confirmed = group.confirmed + 1
                Release()
                E:RecordTransaction("sell", item, item.count, item.value, vendor, nil, vendorID)
                E:SnapshotManualSales()
                E:RefreshMerchantWindow()
                return
            end
            checks = checks + 1
            if checks >= MAX_CHECKS or currentID and currentID ~= item.itemID then
                Release()
                E:SnapshotManualSales()
            else
                C_Timer.After(CHECK_INTERVAL, ConfirmManualSale)
            end
        end
        C_Timer.After(CHECK_INTERVAL, ConfirmManualSale)
    end)
end

local function Finish(queue, stopped)
    if E.saleActive ~= queue then return end
    E.saleActive = nil
    E:LootReviewSaleFinished(queue, stopped)
    E:RefreshMerchantWindow()
end

local function SellNext(queue)
    if E.saleActive ~= queue then return end
    local expected = queue.items[queue.index]
    if not expected then Finish(queue); return end
    if queue.stopping or not E:CanUseSale() then Finish(queue, true); return end
    local bag, slot = expected.bag, expected.slot
    if not E:ValidateLootReviewStack(expected, E:GetBagItem(bag, slot)) then
        Finish(queue, true)
        return
    end

    local moneyBefore = GetMoney()
    if (issecretvalue and issecretvalue(moneyBefore)) or type(moneyBefore) ~= "number" then
        Finish(queue, true)
        return
    end
    if not pcall(C_Container.UseContainerItem, bag, slot) then
        Finish(queue, true)
        return
    end

    local checks = 0
    local function ConfirmSale()
        if E.saleActive ~= queue then return end
        local slotID, money = C_Container.GetContainerItemID(bag, slot), GetMoney()
        if not (issecretvalue and (issecretvalue(slotID) or issecretvalue(money)))
            and slotID == nil and type(money) == "number" and money - moneyBefore == expected.value then
            queue.soldStacks = queue.soldStacks + 1
            queue.soldTotal = queue.soldTotal + expected.value
            E:RecordTransaction("sell", expected, expected.count, expected.value, queue.vendorName, nil, queue.vendorID)
            queue.index = queue.index + 1
            SellNext(queue)
            return
        end
        checks = checks + 1
        if checks >= MAX_CHECKS or queue.stopping or not E:CanUseSale() then
            Finish(queue, true)
        else
            C_Timer.After(CHECK_INTERVAL, ConfirmSale)
        end
    end
    C_Timer.After(CHECK_INTERVAL, ConfirmSale)
end

function E:BeginSale(items)
    if self.saleActive or self.purchaseActive or #items == 0 then return end
    local vendorName, vendorID = self:MerchantIdentity()
    local queue = { items = items, index = 1, soldStacks = 0, soldTotal = 0, vendorName = vendorName, vendorID = vendorID }
    self.saleActive = queue
    self:RefreshLootReview(false)
    SellNext(queue)
end

function E:CancelSaleActions()
    if self.saleActive then self.saleActive.stopping = true end
    self:CancelLootReviewConfirmation()
    if self.quickSale then
        self:HideSaleConfirmation()
        self.quickSale = nil
    end
end

function E:GetJunkSaleItems()
    local result = {}
    for _, item in ipairs(self:BagItems()) do
        if item.quality == 0 and self:CanSellItem(item) then
            result[#result + 1] = item
        end
    end
    return result
end

function E:RequestQuickSale(items, confirm)
    if self:LootReviewBusy() or #items == 0 or not self:CanUseSale() then return end
    if not confirm then self:BeginSale(items); return end
    local value = 0
    for _, item in ipairs(items) do value = value + item.value end
    self.quickSale = items
    local function Release()
        if self.quickSale == items then
            self.quickSale = nil
            self:RefreshMerchantWindow()
        end
    end
    local function Accept()
        if self.quickSale ~= items then return end
        self.quickSale = nil
        if not self:CanUseSale() then return end
        for _, item in ipairs(items) do
            if not self:ValidateLootReviewStack(item, self:GetBagItem(item.bag, item.slot)) then
                self:RefreshMerchantWindow()
                return
            end
        end
        self:BeginSale(items)
    end
    if not self:ShowSaleConfirmation(items, value, Accept, Release) then self.quickSale = nil end
    self:RefreshMerchantWindow()
end

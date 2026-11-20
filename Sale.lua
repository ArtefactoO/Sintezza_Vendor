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

local function ReadSaleState(money)
    money = money or Public(GetMoney(), "number")
    local count = Public(GetNumBuybackItems(), "number")
    if not money or not count then return end
    local offers = {}
    for index = 1, count do
        local name, _, price, quantity = GetBuybackItemInfo(index)
        local link = Public(GetBuybackItemLink(index), "string")
        local identity = link or Public(name, "string")
        price, quantity = Public(price, "number"), Public(quantity, "number")
        if not identity or not price or not quantity then return end
        offers[index] = { key = identity .. "\001" .. price .. "\001" .. quantity, price = price,
            itemID = link and tonumber(link:match("|Hitem:(%d+)")), count = quantity }
    end
    return { money = money, offers = offers }
end

local function RetainedBuybacksMatch(before, after, count)
    local offset = #before - count
    if offset < 0 then return false end
    for index = 1, count do
        if before[offset + index].key ~= after[index].key then return false end
    end
    return true
end

local function FirstNewSale(old, current, gained)
    if gained <= 0 or #current < #old then return end
    local total = 0
    for index = #current, 1, -1 do
        total = total + current[index].price
        if total >= gained then
            local retained = index - 1
            local limit = Public(BUYBACK_ITEMS_PER_PAGE, "number") or 12
            -- A full buyback list can drop its oldest entries as new sales arrive.
            if total == gained and (retained == #old or #current == limit)
                and RetainedBuybacksMatch(old, current, retained) then return index end
            return
        end
    end
end

function E:CapturePurchaseSales(money, buyback)
    local snapshot = self.manualSaleSnapshot
    if not buyback and snapshot and snapshot.money == money then return snapshot end
    return ReadSaleState(money)
end

function E:CountItemsInMatchingSales(before, offer, afterCoins, price)
    local proceeds = afterCoins - before.money + price
    if proceeds <= 0 then return end
    local after = ReadSaleState(afterCoins)
    if not after then return end
    local old = before.offers
    if offer.buyback then
        local remaining = {}
        if not old[offer.index] then return end
        for index, row in ipairs(old) do
            if index ~= offer.index then remaining[#remaining + 1] = row end
        end
        old = remaining
    end
    local first = FirstNewSale(old, after.offers, proceeds)
    if not first then return end
    local count = 0
    if offer.itemID and not offer.currencyID then
        for index = first, #after.offers do
            local row = after.offers[index]
            if row.itemID == offer.itemID then count = count + row.count end
        end
    end
    return count
end

function E:AccountForPurchaseSales(before, offer, price)
    local snapshot = self.manualSaleSnapshot
    if not snapshot then return end
    snapshot.money = snapshot.money - price
    if not offer.buyback then return end
    local bought = before and before.offers[offer.index]
    local previous = snapshot.offers[offer.index]
    if bought and previous and bought.key == previous.key then table.remove(snapshot.offers, offer.index) end
end

function E:SnapshotManualSales()
    if self:HasActiveMerchant() and not InCombatLockdown() then self.manualSaleSnapshot = ReadSaleState() end
end

function E:ObserveManualSales(final, merchantUpdated)
    if self.saleActive or not self:HasActiveMerchant() or InCombatLockdown() then return end
    if self.purchaseActive then return false end
    local before, after = self.manualSaleSnapshot, ReadSaleState()
    if not after then return false end
    local sameBuybacks = before and #before.offers == #after.offers
        and RetainedBuybacksMatch(before.offers, after.offers, #after.offers)
    local firstSale = before and (merchantUpdated or not sameBuybacks)
        and FirstNewSale(before.offers, after.offers, after.money - before.money)
    if not firstSale and before and not final and after.money >= before.money then
        if after.money > before.money or not sameBuybacks then return false end
    end
    self.manualSaleSnapshot = after
    if not firstSale then return end

    local vendor, vendorID = self:MerchantIdentity()
    local singleItem
    for index = firstSale, #after.offers do
        local item = self:GetOffer(index, true)
        if item then
            self:RecordTransaction("sell", item, item.count, after.offers[index].price, vendor, nil, vendorID)
            if index == firstSale and index == #after.offers then singleItem = item end
        end
    end
    self:RefreshMerchantBalanceAndStatus()
    self:QueueMerchantRefresh()
    local window = self.merchantWindow
    self:ShowTransactionAmount("sell", singleItem, singleItem and singleItem.count, after.money - before.money, nil,
        window and window.balance)
end

local function Finish(queue, stopped)
    if E.saleActive ~= queue then return end
    E.saleActive = nil
    if E.interaction == queue.interaction then E:SnapshotManualSales() end
    E:LootReviewSaleFinished(queue, stopped)
    E:RefreshMerchantWindow()
    if queue.unshownProceeds and E.interaction == queue.interaction then
        local item = queue.unshownItem
        E:ShowTransactionAmount("sell", item, item and item.count, queue.unshownProceeds)
    end
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

    local beforeSale = ReadSaleState()
    local moneyBefore = beforeSale and beforeSale.money or Public(GetMoney(), "number")
    if not moneyBefore then
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
        local proceeds
        if not (issecretvalue and (issecretvalue(slotID) or issecretvalue(money)))
            and slotID == nil and type(money) == "number" and money > moneyBefore then
            local gain = money - moneyBefore
            if gain == expected.value then
                proceeds = gain
            elseif beforeSale then
                local afterSale = ReadSaleState()
                local first = afterSale and FirstNewSale(beforeSale.offers, afterSale.offers, gain)
                local item = first and first == #afterSale.offers and E:GetOffer(first, true)
                if item and item.itemID == expected.itemID then proceeds = gain end
            end
        end
        if proceeds then
            queue.soldStacks = queue.soldStacks + 1
            queue.soldTotal = queue.soldTotal + proceeds
            E:RecordTransaction("sell", expected, expected.count, proceeds, queue.vendorName, nil, queue.vendorID)
            if E.interaction == queue.interaction then
                local anchor = E:FindSaleAmountAnchor(expected)
                if anchor then
                    E:ShowTransactionAmount("sell", expected, expected.count, proceeds, nil, anchor)
                else
                    queue.unshownItem = not queue.unshownProceeds and expected or nil
                    queue.unshownProceeds = (queue.unshownProceeds or 0) + proceeds
                end
            end
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
    local queue = { items = items, index = 1, soldStacks = 0, soldTotal = 0, vendorName = vendorName, vendorID = vendorID,
        interaction = self.interaction }
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

local _, ns = ...
local E, Public, Text = ns.vendor, ns.Public, ns.Text
local COPPER_PER_GOLD = 10000
local MAX_PURCHASE_LIMIT_GOLD = math.floor(2 ^ 53 / COPPER_PER_GOLD)

function ns.ParsePurchaseLimit(value)
    if type(value) == "string" then value = tonumber(value:match("^%s*(%d+)%s*$")) end
    if type(value) == "number" and value >= 0 and value <= MAX_PURCHASE_LIMIT_GOLD and value == math.floor(value) then
        return value
    end
end

local function Coins(amount)
    return C_CurrencyInfo.GetCoinTextureString(amount, 12)
end

local function ReadCost(index)
    local costs = {}
    local count = Public(GetMerchantItemCostInfo(index), "number")
    if not count or count <= 0 then return end
    for i = 1, count do
        local icon, amount, link, name = GetMerchantItemCostItem(index, i)
        amount, link = Public(amount, "number"), Public(link, "string")
        if not amount or amount <= 0 or not link then return end
        local currencyID = tonumber(link:match("currency:(%d+)"))
        local itemID = tonumber(link:match("item:(%d+)"))
        if not currencyID and not itemID then return end
        costs[#costs + 1] = {
            amount = amount, texture = Public(icon, "number") or Public(icon, "string"),
            link = link, name = Public(name, "string") or Public((C_Item.GetItemInfo(link)), "string"),
            currencyID = currencyID, itemID = itemID,
        }
    end
    return costs
end

function E:GetOffer(index, buyback)
    local item
    if buyback then
        local name, texture, price, count = GetBuybackItemInfo(index)
        item = { name = name, texture = texture, price = price, stackCount = count }
    else
        item = Public(C_MerchantFrame.GetItemInfo(index), "table")
    end
    local name = item and Public(item.name, "string")
    if not name then return end
    local link = buyback and Public(GetBuybackItemLink(index), "string") or not buyback and Public(GetMerchantItemLink(index), "string")
    if not link then link = nil end
    local currencyID = Public(item.currencyID, "number")
    local itemID, quality, itemLevel, classID
    if link then
        itemID = Public(C_Item.GetItemInfoInstant(link), "number") or tonumber(link:match("|Hitem:(%d+)"))
        local _, _, q, level, _, _, _, _, _, _, _, class = C_Item.GetItemInfo(link)
        quality, itemLevel, classID = Public(q, "number"), Public(level, "number"), Public(class, "number")
    end
    local quantity = Public(item.stackCount, "number")
    local price = Public(item.price, "number")
    local extended = Public(item.hasExtendedCost, "boolean")
    local costs = extended and ReadCost(index) or nil
    local texture = Public(item.texture, "number") or Public(item.texture, "string")
    return {
        index = index, buyback = buyback, name = name, link = link, texture = texture,
        quality = quality, itemLevel = itemLevel, itemID = itemID, currencyID = currencyID, classID = classID,
        count = quantity, price = price, stock = Public(item.numAvailable, "number"),
        extended = extended, costs = costs,
        available = buyback or Public(item.isPurchasable, "boolean") == true,
    }
end

function E:OfferPrice(offer)
    local pieces = {}
    if offer.price and offer.price > 0 then pieces[#pieces + 1] = Coins(offer.price) end
    for _, cost in ipairs(offer.costs or {}) do
        local icon = cost.texture and ("|T%s:13|t"):format(tostring(cost.texture)) or cost.name or "?"
        pieces[#pieces + 1] = tostring(cost.amount) .. " " .. icon
    end
    if offer.extended and not offer.costs then pieces[#pieces + 1] = Text("Other currency", "Другая валюта") end
    return #pieces > 0 and table.concat(pieces, "  ") or Coins(offer.price or 0)
end

local function Balance(currencyID, itemID)
    if currencyID then
        local info = Public(C_CurrencyInfo.GetCurrencyInfo(currencyID), "table")
        return info and Public(info.quantity, "number")
    elseif itemID then
        return Public(C_Item.GetItemCount(itemID, false, false, false, false), "number")
    end
end

local function Signature(offer)
    local parts = { offer.name, offer.link or "", offer.itemID or "", offer.currencyID or "",
        offer.count or "", offer.price or "", tostring(offer.extended) }
    for _, cost in ipairs(offer.costs or {}) do
        parts[#parts + 1] = cost.currencyID and ("c" .. cost.currencyID) or ("i" .. cost.itemID)
        parts[#parts + 1] = cost.amount
    end
    return table.concat(parts, "\001")
end

local function PurchaseBatchLimit(offer)
    local maxStack = GetMerchantItemMaxStack and Public(GetMerchantItemMaxStack(offer.index), "number")
    if not maxStack or not offer.stock then return end
    -- The API caps the number of items per transaction, and stock is counted in merchant batches.
    local batches = math.floor(maxStack / offer.count)
    if offer.stock >= 0 then batches = math.min(batches, offer.stock) end
    return batches
end

local function AffordableBatches(offer)
    local batches = PurchaseBatchLimit(offer)
    local money = Public(GetMoney(), "number")
    if not batches or not money then return end
    if offer.price > 0 then batches = math.min(batches, math.floor(money / offer.price)) end
    for _, cost in ipairs(offer.costs or {}) do
        local amount = Balance(cost.currencyID, cost.itemID)
        if not amount then return end
        batches = math.min(batches, math.floor(amount / cost.amount))
    end
    return batches
end

local function PurchaseTotal(offer, batches)
    if not batches or batches == 1 then return offer end
    local total = { count = offer.count * batches, price = offer.price * batches, extended = offer.extended }
    if offer.costs then
        total.costs = {}
        for i, cost in ipairs(offer.costs) do
            local entry = {}
            for key, value in pairs(cost) do entry[key] = value end
            entry.amount = cost.amount * batches
            total.costs[i] = entry
        end
    end
    return total
end

function E:CanBuyOffer(offer, total)
    if offer.stock == 0 then return false, Text("Sold out.", "Товара нет в наличии.") end
    if not offer.available then return false, Text("This offer is unavailable.", "Покупка недоступна.") end
    local money = Public(GetMoney(), "number")
    if not offer.price or offer.price < 0 or not offer.count or offer.count < 1 or not money
        or (not offer.buyback and offer.extended == nil) or (offer.extended and not offer.costs)
        or not (offer.itemID or offer.currencyID) then
        return false, Text("Offer data is unavailable. Reopen the merchant and try again.",
            "Данные о товаре недоступны. Открой торговца заново.")
    end
    total = total or offer
    if money < total.price then return false, Text("Not enough money.", "Недостаточно денег.") end
    if not offer.buyback and CanAffordMerchantItem and Public(CanAffordMerchantItem(offer.index), "boolean") == false then
        return false, Text("You cannot afford this offer.", "Недостаточно денег или валюты.")
    end
    for _, cost in ipairs(total.costs or {}) do
        local amount = Balance(cost.currencyID, cost.itemID)
        if not amount or amount < cost.amount then
            return false, Text("Not enough currency or required items.", "Недостаточно валюты или предметов для обмена.")
        end
    end
    return true
end

local function PurchaseMessage(self, message)
    self.merchantMessage = message
    self:RefreshMerchantWindow()
end

local function PurchaseBlocker(self)
    if self:LootReviewBusy() then
        return Text("Finish the current transaction first.", "Сначала заверши текущую операцию.")
    end
    if not self:CanInteract() then
        return Text("Open the merchant with an empty cursor and exit repair mode.",
            "Открой торговца, освободи курсор и выйди из режима ремонта.")
    end
end

local function Purchase(self, offer, batches)
    local blocker = PurchaseBlocker(self)
    if blocker then return PurchaseMessage(self, blocker) end
    local current = self:GetOffer(offer.index, offer.buyback)
    if not current or Signature(current) ~= Signature(offer) then
        return PurchaseMessage(self, Text("The offer changed. Check the price.", "Предложение изменилось. Проверь цену."))
    end
    local order = PurchaseTotal(current, batches)
    local allowed, reason = self:CanBuyOffer(current, order)
    if not allowed then return PurchaseMessage(self, reason) end
    if batches and batches > (PurchaseBatchLimit(current) or 0) then
        return PurchaseMessage(self, Text("That quantity is no longer available.", "Это количество больше недоступно."))
    end

    local coins = Public(GetMoney(), "number")
    local total = Balance(current.currencyID, current.itemID)
    if not coins or not total then
        return PurchaseMessage(self, Text("Could not read the current balance.", "Не удалось получить данные о деньгах или предметах."))
    end
    local name, vendorID = self:MerchantIdentity()
    local costs = {}
    for _, cost in ipairs(order.costs or {}) do
        local before = Balance(cost.currencyID, cost.itemID)
        if not before then
            return PurchaseMessage(self, Text("Could not read the currency balance.", "Не удалось получить текущий остаток валюты."))
        end
        costs[#costs + 1] = { cost = cost, before = before }
    end
    self.purchaseActive, self.merchantMessage = current, nil
    local ok, result
    if current.buyback then
        ok, result = pcall(BuybackItem, current.index)
    elseif batches and batches > 1 then
        ok, result = pcall(BuyMerchantItem, current.index, order.count)
    else
        ok, result = pcall(BuyMerchantItem, current.index)
    end
    if not ok or Public(result, "boolean") == false then
        self.purchaseActive = nil
        return PurchaseMessage(self, Text("The game refused the purchase.", "Игра отклонила покупку."))
    end

    local attempts = 0
    local function Check()
        if self.purchaseActive ~= current then return end
        attempts = attempts + 1
        local afterCoins = Public(GetMoney(), "number")
        local afterTotal = Balance(current.currencyID, current.itemID)
        local verified = afterTotal and afterTotal - total >= order.count
            and afterCoins and coins - afterCoins == order.price
        if verified then
            for _, check in ipairs(costs) do
                local cost = check.cost
                local amount = Balance(cost.currencyID, cost.itemID)
                if not amount or check.before - amount ~= cost.amount then verified = false; break end
            end
        end
        if verified then
            self:RecordTransaction(current.buyback and "buyback" or "buy", current, order.count, order.price, name, order.costs, vendorID)
            self.merchantMessage = current.buyback and Text("Bought back.", "Предмет выкуплен.") or Text("Purchased.", "Покупка завершена.")
        elseif attempts < 18 then
            C_Timer.After(.10, Check)
            return
        else
            self.merchantMessage = Text("No purchase confirmation received.", "Игра не подтвердила покупку.")
        end
        self.purchaseActive = nil
        self:RefreshMerchantWindow()
    end
    C_Timer.After(.10, Check)
    self:RefreshMerchantWindow()
end

local function SelectedBatches(dialog)
    local batches = tonumber(dialog.amount:GetText())
    if batches and batches >= 1 and batches <= dialog.maxBatches and batches == math.floor(batches) then
        return batches
    end
end

local function RefreshPurchaseDetails(dialog)
    local offer = dialog.item
    if not offer then return end
    local batches = not dialog.maxBatches and 1 or SelectedBatches(dialog)
    local order = PurchaseTotal(offer, batches)
    local color = ITEM_QUALITY_COLORS[offer.quality or 1]
    dialog.itemName:SetText((color and color.hex or "") .. offer.name .. "|r"
        .. (order.count > 1 and (" ×" .. order.count) or ""))
    dialog.price:SetText(batches and E:OfferPrice(order)
        or Text("Enter a number from 1 to %d.", "Введи число от 1 до %d."):format(dialog.maxBatches))
    dialog.action:SetEnabled(batches ~= nil)
end

function E:RequestPurchase(offer, chooseQuantity)
    if self.purchaseConfirm and self.purchaseDialog and self.purchaseDialog:IsVisible() then
        self.purchaseDialog:Raise()
        return
    end
    local blocker = PurchaseBlocker(self)
    if blocker then return PurchaseMessage(self, blocker) end
    local allowed, reason = self:CanBuyOffer(offer)
    if not allowed then return PurchaseMessage(self, reason) end
    local limit = self.profile.purchaseLimitGold
    local maxBatches
    if chooseQuantity and not offer.buyback then
        maxBatches = AffordableBatches(offer)
        if not maxBatches or maxBatches < 1 then
            return PurchaseMessage(self, Text("No quantity available to buy.", "Нет доступного количества для покупки."))
        end
    elseif not offer.buyback and offer.extended == false and limit > 0 and offer.price <= limit * COPPER_PER_GOLD then
        return Purchase(self, offer)
    end
    self.purchaseDialog = self.purchaseDialog or self:CreatePurchasePopup()
    local dialog = self.purchaseDialog
    self.purchaseConfirm, self.merchantMessage = offer, nil
    dialog.header.title:SetText(offer.buyback and Text("Buyback", "Выкуп") or Text("Purchase", "Покупка"))
    dialog.action.text:SetText(offer.buyback and Text("Buy back", "Выкупить") or Text("Buy", "Купить"))
    dialog.itemIcon:SetTexture(offer.texture or 134400)
    ns.Theme:PaintItemBorder(dialog.itemBorder, offer.quality)
    dialog.item, dialog.maxBatches = offer, maxBatches
    dialog:SetHeight(maxBatches and 190 or 156)
    dialog.quantityRow:SetShown(maxBatches ~= nil)
    if maxBatches then
        dialog.quantityLabel:SetText(offer.count == 1 and Text("Quantity", "Количество")
            or Text("Batches of %d", "Порции по %d"):format(offer.count))
        dialog.amount:SetText("1")
    end
    RefreshPurchaseDetails(dialog)
    dialog:Show()
    dialog:Raise()
    self:RefreshMerchantWindow()
end

function E:CancelPurchase()
    self.purchaseConfirm = nil
    if self.purchaseDialog then self.purchaseDialog:Hide() end
end

function E:AcceptPurchase(offer)
    if not offer or self.purchaseConfirm ~= offer then return end
    local dialog = self.purchaseDialog
    local batches = dialog.maxBatches and SelectedBatches(dialog)
    if dialog.maxBatches and not batches then return end
    self.purchaseConfirm = nil
    Purchase(self, offer, batches)
    return true
end

function E:CreatePurchasePopup()
    local T = ns.Theme
    local W = Sintezza_Theme:CreateWidgets(T)
    local dialog = CreateFrame("Frame", "Sintezza_VendorPurchaseWindow", self.merchantWindow or UIParent, "BackdropTemplate")
    dialog:Hide()
    dialog:SetSize(414, 156)
    dialog:SetPoint("CENTER", UIParent, "CENTER")
    if dialog.SetIgnoreParentAlpha then dialog:SetIgnoreParentAlpha(true) end
    if dialog.SetIgnoreParentScale then dialog:SetIgnoreParentScale(true) end
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    T:WindowSurface(dialog)
    local header = W:WindowHeader(dialog, { title = Text("Purchase", "Покупка"), icon = ns.Icon })
    dialog.header = header
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if self.windowAppearance:CanMove() then dialog:StartMoving() end
    end)
    header:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
    local item = CreateFrame("Frame", nil, dialog)
    item:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 14, -12)
    item:SetSize(36, 36)
    dialog.itemIcon = item:CreateTexture(nil, "ARTWORK")
    dialog.itemIcon:SetAllPoints()
    dialog.itemIcon:SetTexCoord(.07, .93, .07, .93)
    dialog.itemBorder = T:FrameIcon(item, dialog.itemIcon)
    item:EnableMouse(true)
    item:SetScript("OnEnter", function(owner)
        if not dialog.item or not dialog.item.link then return end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(dialog.item.link)
        GameTooltip:Show()
    end)
    item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    dialog.itemName = W:Label(dialog, "", 12, T.text)
    dialog.itemName:SetPoint("TOPLEFT", item, "TOPRIGHT", 10, -2)
    dialog.itemName:SetPoint("RIGHT", dialog, "RIGHT", -14, 0)
    dialog.itemName:SetWordWrap(false)
    dialog.price = W:Label(dialog, "", 11, T.muted)
    dialog.price:SetPoint("BOTTOMLEFT", item, "BOTTOMRIGHT", 10, 2)

    local quantityRow = CreateFrame("Frame", nil, dialog)
    quantityRow:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 0, -12)
    quantityRow:SetPoint("RIGHT", dialog, "RIGHT", -12, 0)
    quantityRow:SetHeight(26)
    dialog.quantityRow = quantityRow
    dialog.quantityLabel = W:Label(quantityRow, "", 12, T.text)
    dialog.quantityLabel:SetPoint("LEFT")
    local amount = W:EditBox(quantityRow, "", function() end)
    amount:SetSize(70, 26)
    amount:SetNumeric(true)
    amount:SetJustifyH("RIGHT")
    amount:HookScript("OnTextChanged", function() RefreshPurchaseDetails(dialog) end)
    amount:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    amount:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    dialog.amount = amount
    local maxButton = W:Button(quantityRow, Text("Max", "Макс."), function()
        amount:SetText(tostring(dialog.maxBatches))
    end)
    maxButton:SetSize(70, 26)
    maxButton:SetPoint("RIGHT")
    amount:SetPoint("RIGHT", maxButton, "LEFT", -6, 0)

    local cancel = W:Button(dialog, Text("Cancel", "Отмена"), function() dialog:Hide() end)
    cancel:SetSize(112, 24)
    cancel:SetPoint("BOTTOMRIGHT", -12, 10)
    local buy = W:Button(dialog, Text("Buy", "Купить"), function()
        if self:AcceptPurchase(self.purchaseConfirm) then dialog:Hide() end
    end, true)
    buy:SetSize(112, 24)
    buy:SetPoint("RIGHT", cancel, "LEFT", -6, 0)
    dialog.action = buy
    dialog:HookScript("OnHide", function()
        dialog:StopMovingOrSizing()
        if dialog:IsShown() then dialog:Hide() end
        self.purchaseConfirm = nil
        dialog.item, dialog.maxBatches = nil, nil
        amount:ClearFocus()
        self:RefreshMerchantWindow()
    end)
    UISpecialFrames[#UISpecialFrames + 1] = dialog:GetName()
    return dialog
end

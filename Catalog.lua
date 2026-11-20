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
    return batches, maxStack
end

local function AffordableBatches(offer)
    local batches, maxStack = PurchaseBatchLimit(offer)
    local money = Public(GetMoney(), "number")
    if not batches or not money then return end
    if maxStack <= 1 then return 0 end
    if offer.price > 0 then batches = math.min(batches, math.floor(money / offer.price)) end
    for _, cost in ipairs(offer.costs or {}) do
        local amount = Balance(cost.currencyID, cost.itemID)
        if not amount then return end
        batches = math.min(batches, math.floor(amount / cost.amount))
    end
    return batches
end

local function WatchPurchase(self, check)
    self.purchaseCheck = check
    if check() then return end

    local remaining = 18
    local function Poll()
        if self.purchaseCheck ~= check then return end
        remaining = remaining - 1
        if not check(remaining == 0) then C_Timer.After(.10, Poll) end
    end
    C_Timer.After(.10, Poll)
end

function E:CheckCursorPurchase(interactionEnded)
    if not self.cursorPurchase or (not interactionEnded and Public(GetCursorInfo(), "string") == "merchant") then return end
    local check = self.cursorPurchase
    self.cursorPurchase = nil
    WatchPurchase(self, check)
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
    self:RefreshMerchantBalanceAndStatus()
end

local function PurchaseBlocker(self, fromQueue)
    if self:LootReviewBusy(fromQueue) then
        return Text("Finish the current transaction first.", "Сначала заверши текущую операцию.")
    end
    if not self:CanInteract() then
        return Text("Open the merchant with an empty cursor and exit repair mode.",
            "Открой торговца, освободи курсор и выйди из режима ремонта.")
    end
end

local function CanBuyImmediately(self, offer)
    local limit = self.profile.purchaseLimitGold
    return not offer.buyback and offer.extended == false and limit > 0
        and offer.price and offer.price <= limit * COPPER_PER_GOLD
end

local Purchase
local function ScheduleNextPurchase(self)
    local queue = self.purchaseQueue
    if not queue or queue.scheduled then return end
    queue.scheduled = true
    C_Timer.After(0, function()
        if self.purchaseQueue ~= queue then return end
        if self.interaction ~= queue.interaction then self.purchaseQueue = nil; return end
        queue.scheduled = false
        local offer = table.remove(queue, 1)
        if #queue == 0 then self.purchaseQueue = nil end
        if not CanBuyImmediately(self, offer) then
            self.purchaseQueue = nil
            PurchaseMessage(self, Text("The purchase now needs confirmation.", "Теперь покупка требует подтверждения."))
        elseif not Purchase(self, offer, nil, false, true) then
            self.purchaseQueue = nil
        end
    end)
end

Purchase = function(self, offer, batches, pickup, fromQueue)
    local blocker = PurchaseBlocker(self, fromQueue)
    if blocker then return PurchaseMessage(self, blocker) end
    local current = self:GetOffer(offer.index, offer.buyback)
    if not current or Signature(current) ~= Signature(offer) then
        self:InvalidateMerchantCatalogue()
        self:QueueMerchantRefresh()
        return PurchaseMessage(self, Text("The offer changed. Check the price.", "Предложение изменилось. Проверь цену."))
    end
    if current.stock ~= offer.stock or current.available ~= offer.available then
        self:InvalidateMerchantCatalogue()
        self:QueueMerchantRefresh()
    end
    local order = PurchaseTotal(current, batches)
    local allowed, reason = self:CanBuyOffer(current, order)
    if not allowed then return PurchaseMessage(self, reason) end
    if batches and batches > (PurchaseBatchLimit(current) or 0) then
        return PurchaseMessage(self, Text("That quantity is no longer available.", "Это количество больше недоступно."))
    end
    if pickup and (MerchantFrame.extendedCost or MerchantFrame.highPrice) then
        return PurchaseMessage(self, Text("Right-click to buy this item.", "Нажми ПКМ, чтобы купить этот товар."))
    end

    local coins = Public(GetMoney(), "number")
    local total = Balance(current.currencyID, current.itemID)
    if not coins or not total then
        return PurchaseMessage(self, Text("Could not read the current balance.", "Не удалось получить данные о деньгах или предметах."))
    end
    local name, vendorID = self:MerchantIdentity()
    local interaction = self.interaction
    local saleState = self:CapturePurchaseSales(coins, current.buyback)
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
    elseif pickup then
        ok, result = pcall(PickupMerchantItem, current.index)
    elseif batches and batches > 1 then
        ok, result = pcall(BuyMerchantItem, current.index, order.count)
    else
        ok, result = pcall(BuyMerchantItem, current.index)
    end
    if not ok or Public(result, "boolean") == false or (pickup and Public(GetCursorInfo(), "string") ~= "merchant") then
        self.purchaseActive = nil
        return PurchaseMessage(self, Text("The game refused the purchase.", "Игра отклонила покупку."))
    end

    local function Check(timedOut, merchantUpdated)
        local afterCoins = Public(GetMoney(), "number")
        local afterTotal = Balance(current.currencyID, current.itemID)
        local received = afterTotal and afterTotal - total
        local paid = afterCoins and coins - afterCoins
        local verified = received and received >= order.count and paid == order.price
        if not verified and saleState and received and paid and paid < order.price
            and (received ~= 0 or paid ~= 0 or merchantUpdated or timedOut) and self.interaction == interaction then
            local sold = self:CountItemsInMatchingSales(saleState, current, afterCoins, order.price)
            verified = sold and received + sold >= order.count
        end
        if verified then
            for _, check in ipairs(costs) do
                local cost = check.cost
                local amount = Balance(cost.currencyID, cost.itemID)
                if not amount or check.before - amount ~= cost.amount then verified = false; break end
            end
        end
        if not verified and not timedOut then return end

        self.purchaseActive, self.purchaseCheck = nil, nil
        if verified then
            if self.interaction == interaction then self:AccountForPurchaseSales(saleState, current, order.price) end
            if current.stock and current.stock > 0 then self:InvalidateMerchantCatalogue() end
            self:RecordTransaction(current.buyback and "buyback" or "buy", current, order.count, order.price, name, order.costs, vendorID)
            self.merchantMessage = current.buyback and Text("Bought back.", "Предмет выкуплен.") or Text("Purchased.", "Покупка завершена.")
            if current.buyback and self.interaction == interaction then
                self:ShowTransactionAmount("buyback", current, order.count, order.price)
            end
        elseif not pickup then
            self.merchantMessage = Text("No purchase confirmation received.", "Игра не подтвердила покупку.")
        end
        if not verified then self.purchaseQueue = nil end
        self:RefreshMerchantBalanceAndStatus()
        self:QueueMerchantRefresh()
        self:QueueManualSaleObservation()
        if verified and not current.buyback and self.interaction == interaction then
            local card = self:MarkPurchasedOffer(current)
            self:ShowTransactionAmount("buy", current, order.count, order.price, order.costs, card)
        end
        if verified then ScheduleNextPurchase(self) end
        return true
    end
    if pickup then
        self.cursorPurchase = Check
    else
        WatchPurchase(self, Check)
    end
    if self.purchaseActive then self:RefreshMerchantBalanceAndStatus() end
    return true
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
    if dialog.maxBatches then
        dialog.less:SetEnabled(batches ~= 1)
        dialog.more:SetEnabled(batches ~= dialog.maxBatches)
        dialog.maxButton:SetEnabled(batches ~= dialog.maxBatches)
    end
    if dialog.displayedBatches ~= batches then
        dialog.displayedBatches = batches
        if batches and dialog.maxBatches and dialog:IsVisible() and Sintezza_Theme.animateControls ~= false then
            dialog.animateDetails(0, 0)
            dialog.animateDetails(1, 0, .22)
        else
            dialog.animateDetails(1, 0)
        end
    end
end

function E:RequestPurchase(offer, action)
    if self.purchaseConfirm and self.purchaseDialog and self.purchaseDialog:IsVisible() then
        self.purchaseDialog:Raise()
        return
    end
    local pickup = action == "pickup" and not offer.buyback
    if action ~= "quantity" and CanBuyImmediately(self, offer) then
        if not pickup and self.interaction and (self.purchaseActive or self.purchaseQueue) and self:CanInteract() then
            local queue = self.purchaseQueue
            if not queue or queue.interaction ~= self.interaction then
                queue = { interaction = self.interaction }
                self.purchaseQueue = queue
            end
            queue[#queue + 1] = offer
            if not self.purchaseActive then ScheduleNextPurchase(self) end
            return PurchaseMessage(self, Text("Queued purchases: %d", "Покупок в очереди: %d"):format(#queue))
        end
        return Purchase(self, offer, nil, pickup)
    end
    local blocker = PurchaseBlocker(self)
    if blocker then return PurchaseMessage(self, blocker) end
    local allowed, reason = self:CanBuyOffer(offer)
    if not allowed then return PurchaseMessage(self, reason) end
    local maxBatches
    if action == "quantity" and not offer.buyback then
        maxBatches = AffordableBatches(offer)
        if maxBatches == 0 then return end
        if not maxBatches or maxBatches < 1 then
            return PurchaseMessage(self, Text("No quantity available to buy.", "Нет доступного количества для покупки."))
        end
    end
    self.purchaseDialog = self.purchaseDialog or self:CreatePurchasePopup()
    local dialog = self.purchaseDialog
    self.purchaseConfirm, self.merchantMessage = offer, nil
    dialog.header.title:SetText(offer.buyback and Text("Buyback", "Выкуп") or Text("Purchase", "Покупка"))
    dialog.action.text:SetText(offer.buyback and Text("Buy back", "Выкупить")
        or pickup and Text("Pick up", "Взять на курсор") or Text("Buy", "Купить"))
    dialog.itemIcon:SetTexture(offer.texture or 134400)
    ns.Theme:PaintItemBorder(dialog.itemBorder, offer.quality)
    dialog.item, dialog.maxBatches, dialog.pickup = offer, maxBatches, pickup
    dialog:SetHeight(maxBatches and 150 or 120)
    dialog.quantityRow:SetShown(maxBatches ~= nil)
    if maxBatches then
        dialog.quantityLabel:SetText(offer.count == 1 and Text("Quantity", "Количество")
            or Text("Batches of %d", "Порции по %d"):format(offer.count))
        dialog.amount:SetText("1")
    end
    RefreshPurchaseDetails(dialog)
    dialog:Show()
    dialog:Raise()
    self:RefreshMerchantBalanceAndStatus()
    self:QueueMerchantRefresh()
end

function E:CancelPurchase()
    self.purchaseConfirm = nil
    self.purchaseQueue = nil
    if self.purchaseDialog then self.purchaseDialog:Hide() end
end

function E:AcceptPurchase(offer)
    if not offer or self.purchaseConfirm ~= offer then return end
    local dialog = self.purchaseDialog
    local batches = dialog.maxBatches and SelectedBatches(dialog)
    if dialog.maxBatches and not batches then return end
    self.purchaseConfirm = nil
    Purchase(self, offer, batches, dialog.pickup)
    return true
end

function E:CreatePurchasePopup()
    local T = ns.Theme
    local W = Sintezza_Theme:CreateWidgets(T)
    local dialog = CreateFrame("Frame", "Sintezza_VendorPurchaseWindow", self.merchantWindow or UIParent, "BackdropTemplate")
    dialog:Hide()
    dialog:SetSize(360, 120)
    dialog:SetPoint("CENTER", UIParent, "CENTER")
    if dialog.SetIgnoreParentAlpha then dialog:SetIgnoreParentAlpha(true) end
    if dialog.SetIgnoreParentScale then dialog:SetIgnoreParentScale(true) end
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    T:WindowSurface(dialog)
    local header = W:WindowHeader(dialog, { title = Text("Purchase", "Покупка"), icon = ns.Icon, height = 36, titleSize = 15 })
    dialog.header = header
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if self.windowAppearance:CanMove() then dialog:StartMoving() end
    end)
    header:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
    local item = CreateFrame("Frame", nil, dialog)
    item:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -8)
    item:SetSize(34, 34)
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
    dialog.itemName:SetPoint("TOPLEFT", item, "TOPRIGHT", 9, -2)
    dialog.itemName:SetPoint("RIGHT", dialog, "RIGHT", -12, 0)
    dialog.itemName:SetWordWrap(false)
    dialog.price = W:Label(dialog, "", 11, T.muted)
    dialog.price:SetPoint("BOTTOMLEFT", item, "BOTTOMRIGHT", 9, 2)
    dialog.price:SetPoint("RIGHT", dialog, "RIGHT", -12, 0)
    dialog.price:SetJustifyH("LEFT")
    dialog.price:SetWordWrap(false)
    dialog.animateDetails = Sintezza_Theme:AnimateControl(dialog, function(position)
        dialog.itemName:SetAlpha(.86 + .14 * position)
        dialog.price:SetAlpha(.76 + .24 * position)
    end)

    local quantityRow = CreateFrame("Frame", nil, dialog)
    quantityRow:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 0, -7)
    quantityRow:SetPoint("RIGHT", dialog, "RIGHT", -12, 0)
    quantityRow:SetHeight(24)
    dialog.quantityRow = quantityRow
    dialog.quantityLabel = W:Label(quantityRow, "", 12, T.text)
    dialog.quantityLabel:SetPoint("LEFT")
    local amount = W:EditBox(quantityRow, "", function() end)
    amount:SetSize(44, 24)
    amount:SetTextInsets(5, 5, 0, 0)
    amount:SetNumeric(true)
    amount:SetJustifyH("RIGHT")
    amount:HookScript("OnTextChanged", function() RefreshPurchaseDetails(dialog) end)
    amount:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    amount:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    dialog.amount = amount
    local function Step(delta)
        local value = tonumber(amount:GetText())
        local nextValue = value and math.floor(value) + delta or 1
        amount:SetText(tostring(math.max(1, math.min(dialog.maxBatches, nextValue))))
    end
    dialog.maxButton = W:Button(quantityRow, Text("Max", "Макс."), function()
        amount:SetText(tostring(dialog.maxBatches))
    end)
    dialog.maxButton:SetSize(54, 24)
    dialog.maxButton:SetPoint("RIGHT")
    dialog.more = W:Button(quantityRow, "+", function() Step(1) end)
    dialog.more:SetSize(24, 24)
    dialog.more:SetPoint("RIGHT", dialog.maxButton, "LEFT", -6, 0)
    amount:SetPoint("RIGHT", dialog.more, "LEFT", -3, 0)
    dialog.less = W:Button(quantityRow, "−", function() Step(-1) end)
    dialog.less:SetSize(24, 24)
    dialog.less:SetPoint("RIGHT", amount, "LEFT", -3, 0)

    local cancel = W:Button(dialog, Text("Cancel", "Отмена"), function() dialog:Hide() end)
    cancel:SetSize(92, 24)
    cancel:SetPoint("BOTTOMRIGHT", -12, 8)
    local buy = W:Button(dialog, Text("Buy", "Купить"), function()
        if self:AcceptPurchase(self.purchaseConfirm) then dialog:Hide() end
    end, true)
    buy:SetSize(108, 24)
    buy:SetPoint("RIGHT", cancel, "LEFT", -6, 0)
    dialog.action = buy
    dialog:HookScript("OnHide", function()
        dialog:StopMovingOrSizing()
        if dialog:IsShown() then dialog:Hide() end
        self.purchaseConfirm = nil
        dialog.item, dialog.maxBatches, dialog.pickup, dialog.displayedBatches = nil, nil, nil, nil
        dialog.animateDetails(1, 0)
        amount:ClearFocus()
        self:RefreshMerchantBalanceAndStatus()
        self:QueueMerchantRefresh()
    end)
    UISpecialFrames[#UISpecialFrames + 1] = dialog:GetName()
    return dialog
end

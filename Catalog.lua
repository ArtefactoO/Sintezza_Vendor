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

function E:CanBuyOffer(offer)
    if offer.stock == 0 then return false, Text("Sold out.", "Товара нет в наличии.") end
    if not offer.available then return false, Text("This offer is unavailable.", "Покупка недоступна.") end
    local money = Public(GetMoney(), "number")
    if not offer.price or offer.price < 0 or not offer.count or offer.count < 1 or not money
        or (not offer.buyback and offer.extended == nil) or (offer.extended and not offer.costs)
        or not (offer.itemID or offer.currencyID) then
        return false, Text("Offer data is unavailable. Reopen the merchant and try again.",
            "Данные о товаре недоступны. Открой торговца заново.")
    end
    if money < offer.price then return false, Text("Not enough money.", "Недостаточно денег.") end
    if not offer.buyback and CanAffordMerchantItem and Public(CanAffordMerchantItem(offer.index), "boolean") == false then
        return false, Text("You cannot afford this offer.", "Недостаточно денег или валюты.")
    end
    for _, cost in ipairs(offer.costs or {}) do
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

local function Purchase(self, offer)
    local blocker = PurchaseBlocker(self)
    if blocker then return PurchaseMessage(self, blocker) end
    local current = self:GetOffer(offer.index, offer.buyback)
    if not current or Signature(current) ~= Signature(offer) then
        return PurchaseMessage(self, Text("The offer changed. Check the price.", "Предложение изменилось. Проверь цену."))
    end
    local allowed, reason = self:CanBuyOffer(current)
    if not allowed then return PurchaseMessage(self, reason) end

    local coins = Public(GetMoney(), "number")
    local total = Balance(current.currencyID, current.itemID)
    if not coins or not total then
        return PurchaseMessage(self, Text("Could not read the current balance.", "Не удалось получить данные о деньгах или предметах."))
    end
    local name = self:MerchantName()
    local costs = {}
    for _, cost in ipairs(current.costs or {}) do
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
        local verified = afterTotal and afterTotal - total >= current.count
            and afterCoins and coins - afterCoins == current.price
        if verified then
            for _, check in ipairs(costs) do
                local cost = check.cost
                local amount = Balance(cost.currencyID, cost.itemID)
                if not amount or check.before - amount ~= cost.amount then verified = false; break end
            end
        end
        if verified then
            self:RecordTransaction(current.buyback and "buyback" or "buy", current, current.count, current.price, name, current.costs)
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

function E:RequestPurchase(offer)
    if self.purchaseConfirm and self.purchaseDialog and self.purchaseDialog:IsVisible() then
        self.purchaseDialog:Raise()
        return
    end
    local blocker = PurchaseBlocker(self)
    if blocker then return PurchaseMessage(self, blocker) end
    local allowed, reason = self:CanBuyOffer(offer)
    if not allowed then return PurchaseMessage(self, reason) end
    local limit = self.profile.purchaseLimitGold
    if not offer.buyback and offer.extended == false and limit > 0 and offer.price <= limit * COPPER_PER_GOLD then
        return Purchase(self, offer)
    end
    self.purchaseDialog = self.purchaseDialog or self:CreatePurchasePopup()
    local dialog = self.purchaseDialog
    self.purchaseConfirm, self.merchantMessage = offer, nil
    local label = offer.name .. (offer.count > 1 and (" ×" .. offer.count) or "")
    dialog.details:SetText(Text("Buy %s for %s?", "Купить %s за %s?"):format(label, self:OfferPrice(offer)))
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
    self.purchaseConfirm = nil
    Purchase(self, offer)
end

function E:CreatePurchasePopup()
    local T = ns.Theme
    local W = Sintezza_Theme:CreateWidgets(T)
    local dialog = CreateFrame("Frame", "Sintezza_VendorPurchaseWindow", self.merchantWindow or UIParent, "BackdropTemplate")
    dialog:Hide()
    dialog:SetSize(414, 144)
    dialog:SetPoint("CENTER", UIParent, "CENTER")
    if dialog.SetIgnoreParentAlpha then dialog:SetIgnoreParentAlpha(true) end
    if dialog.SetIgnoreParentScale then dialog:SetIgnoreParentScale(true) end
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    T:WindowSurface(dialog)
    local header = W:WindowHeader(dialog, { title = Text("Purchase", "Покупка"), icon = ns.Icon })
    dialog.details = W:Label(dialog, "", 12, T.text)
    dialog.details:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 14, -8)
    dialog.details:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 42)
    dialog.details:SetWordWrap(true)
    local cancel = W:Button(dialog, Text("Cancel", "Отмена"), function() dialog:Hide() end)
    cancel:SetSize(112, 24)
    cancel:SetPoint("BOTTOMRIGHT", -12, 10)
    local buy = W:Button(dialog, Text("Buy", "Купить"), function()
        self:AcceptPurchase(self.purchaseConfirm)
        dialog:Hide()
    end, true)
    buy:SetSize(112, 24)
    buy:SetPoint("RIGHT", cancel, "LEFT", -6, 0)
    dialog:HookScript("OnHide", function()
        if dialog:IsShown() then dialog:Hide() end
        self.purchaseConfirm = nil
        self:RefreshMerchantWindow()
    end)
    UISpecialFrames[#UISpecialFrames + 1] = dialog:GetName()
    return dialog
end

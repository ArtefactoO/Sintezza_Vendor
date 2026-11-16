local _, ns = ...
local E = ns.vendor
local Text = ns.Text
local MAX_CHECKS = 12
local CHECK_INTERVAL = .10
local QUICK_CONFIRM = "SINTEZZA_VENDOR_CONFIRM_QUICK_SALE"

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
            E:RecordTransaction("sell", expected, expected.count, expected.value, queue.vendorName)
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
    local queue = { items = items, index = 1, soldStacks = 0, soldTotal = 0, vendorName = self:MerchantName() }
    self.saleActive = queue
    self:RefreshLootReview(false)
    SellNext(queue)
end

function E:CancelSaleActions()
    if self.saleActive then self.saleActive.stopping = true end
    self:CancelLootReviewConfirmation()
    if self.quickSale then
        self.quickSale = nil
        StaticPopup_Hide(QUICK_CONFIRM)
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
    if not StaticPopup_Show(QUICK_CONFIRM, tostring(#items), C_CurrencyInfo.GetCoinTextureString(value, 12), items) then
        self.quickSale = nil
    end
    self:RefreshMerchantWindow()
end

function E:CreateQuickSalePopup()
    local function Release(_, items)
        if self.quickSale == items then
            self.quickSale = nil
            self:RefreshMerchantWindow()
        end
    end
    StaticPopupDialogs[QUICK_CONFIRM] = {
        text = Text("Sell %s stacks for %s?", "Продать стопки (%s) за %s?"),
        button1 = Text("Sell", "Продать"),
        button2 = CANCEL or Text("Cancel", "Отмена"),
        timeout = 0, hideOnEscape = 1, OnCancel = Release, OnHide = Release,
        OnAccept = function(_, items)
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
        end,
    }
end

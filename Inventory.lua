local addonName, ns = ...
local Text = ns.Text
local vendor = { addonName = addonName }
ns.vendor = vendor

local function Public(value, kind)
    if issecretvalue and issecretvalue(value) then return end
    if type(value) == kind then return value end
end
ns.Public = Public

function vendor:HasActiveMerchant()
    if not MerchantFrame or not MerchantFrame:IsVisible() then return false end
    local manager = C_PlayerInteractionManager
    local merchant = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Merchant
    return merchant ~= nil and manager and manager.IsInteractingWithNpcOfType
        and Public(manager.IsInteractingWithNpcOfType(merchant), "boolean") == true
end

function vendor:CanInteract()
    if InCombatLockdown() or not self:HasActiveMerchant() then return false end
    local cursor = GetCursorInfo()
    return not (issecretvalue and issecretvalue(cursor)) and cursor == nil
        and not SpellIsTargeting() and not (InRepairMode and InRepairMode())
end

function vendor:CanUseSale()
    return self:CanInteract() and Public(MerchantFrame.selectedTab, "number") == 1
end

function vendor:SelectNativeBuyTab()
    local tab = MerchantFrame and MerchantFrameTab1
    if tab and not InCombatLockdown() and MerchantFrame.selectedTab ~= 1 then
        local click = tab:GetScript("OnClick")
        if click then click(tab, "LeftButton") end
    end
end

function vendor:GetBagItem(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not Public(info, "table") then return end
    local link = Public(info.hyperlink, "string")
    local itemID = Public(info.itemID, "number")
    local count = Public(info.stackCount, "number")
    if not link or not itemID or not count or count < 1 then return end

    local name, _, quality, level, _, _, _, _, equipLoc, _, price, classID, subclassID, bindType, _, _, reagent =
        C_Item.GetItemInfo(link)
    name = Public(name, "string")
    quality = Public(quality, "number")
    if not name or not quality then return end

    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local guid = Public(C_Item.GetItemGUID(location), "string")
    local inSet = C_Container.GetContainerItemEquipmentSetInfo(bag, slot)
    equipLoc = Public(equipLoc, "string")
    price = Public(price, "number")
    local levelForItem = Public(C_Item.GetCurrentItemLevel(location), "number") or Public(level, "number")
    return {
        bag = bag, slot = slot, guid = guid, link = link, itemID = itemID, count = count,
        name = name, quality = quality, itemLevel = levelForItem, equipLoc = equipLoc,
        texture = Public(info.iconFileID, "number"),
        value = price and price * count,
        bound = Public(info.isBound, "boolean"),
        locked = Public(info.isLocked, "boolean") ~= false,
        noValue = Public(info.hasNoValue, "boolean") ~= false,
        equipmentSet = Public(inSet, "boolean"),
        classID = Public(classID, "number"), subclassID = Public(subclassID, "number"),
        bindType = Public(bindType, "number"), reagent = Public(reagent, "boolean"),
    }
end

function vendor:BagItems()
    local items = {}
    for bag = 0, NUM_BAG_SLOTS do
        local slots = Public(C_Container.GetContainerNumSlots(bag), "number") or 0
        for slot = 1, slots do
            local item = self:GetBagItem(bag, slot)
            if item then
                item.key = bag .. ":" .. slot
                items[#items + 1] = item
            end
        end
    end
    return items
end

function vendor:IsExcluded(itemID)
    return self.blacklist and (self.blacklist[itemID] or self.blacklist[tostring(itemID)]) and true or false
end

function vendor:ToggleExcluded(itemID)
    self:SetExcluded(itemID, not self:IsExcluded(itemID))
end

function vendor:SetExcluded(itemID, excluded)
    if not self.blacklist or type(itemID) ~= "number" then return end
    self.blacklist[tostring(itemID)] = nil
    self.blacklist[itemID] = excluded and true or nil
    self:RefreshMerchantWindow()
    self:RefreshLootReview(true)
    self:RefreshExclusions()
end

local function KnownBound(item)
    if item.bound == false then return false end
    if item.bound == nil then return true end
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return true end
    local data = Public(C_TooltipInfo.GetBagItem(item.bag, item.slot), "table")
    local lines = data and Public(data.lines, "table")
    if not lines then return true end
    for _, line in ipairs(lines) do
        local info = Public(line, "table")
        local text = info and Public(info.leftText, "string")
        if text and (text == ITEM_SPELL_KNOWN or text == SPELL_KNOWN
            or text == "Already known" or text == "Уже известно") then return true end
    end
    return false
end

function vendor:CanSellItem(item)
    if not item.guid or not item.equipLoc or item.locked then
        return false, Text("Item data is unavailable or the stack is locked.", "Данные недоступны или стопка заблокирована.")
    end
    if item.noValue or not item.value or item.value <= 0 then
        return false, Text("The vendor does not pay for this item.", "Торговец не платит за этот предмет.")
    end
    local protectedSet = item.equipmentSet == nil or item.equipmentSet and self.profile.protectEquipmentSets ~= false
    if item.reagent ~= false or protectedSet or item.quality >= 6 or item.classID == nil
        or item.classID == Enum.ItemClass.Profession
        or item.equipLoc == "INVTYPE_PROFESSION_TOOL" or item.equipLoc == "INVTYPE_PROFESSION_GEAR" then
        return false, Text("Protected item.", "Предмет защищен от продажи.")
    end
    if self.profile.protectKnownBoundItems and KnownBound(item) then
        return false, Text("Known bound items are protected.", "Изученные привязанные предметы защищены.")
    end
    if self:IsExcluded(item.itemID) then
        return false, Text("Excluded in your Vendor profile.", "Предмет исключен в профиле Vendor.")
    end
    local binding = self.profile.sellBindingFilter
    if binding == "boe" and (item.bindType ~= 2 or item.bound ~= false)
        or binding == "sb" and item.bound ~= true then
        return false, Text("Excluded by your binding filter.", "Предмет исключен фильтром привязки.")
    end
    return true
end

local addonName, ns = ...
local E, T, Text = ns.vendor, ns.Theme, ns.Text
local title = "Sintezza Vendor"
local icon = ns.Icon
local windowAppearance = Sintezza_Theme:NewWindowPreferences(function() return E.profile end, function(profile)
    return { scale = (tonumber(profile.uiScale) or 1) * 100, layer = profile.merchantFrameStrata }
end)
E.windowAppearance = windowAppearance
if Sintezza_Theme.RegisterGlobalWindowPreferences then
    Sintezza_Theme:RegisterGlobalWindowPreferences("Sintezza Vendor", windowAppearance)
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(title .. ": " .. message)
end

function E:ApplyAppearance()
    windowAppearance:Apply()
end

function windowAppearance:OnReset()
    E.profile.merchantFrameUserPlaced = nil
    E.profile.merchantFrameCenterX, E.profile.merchantFrameCenterY = nil, nil
end

function windowAppearance:OnResetSize()
    E.profile.merchantFrameWidth, E.profile.merchantFrameHeight = nil, nil
end

function windowAppearance:OnChanged(key)
    if key == "layer" and E.settings and E.settings:IsShown() then E.settings:Raise() end
end

local nativeOffscreenX = 64

local function ReadMerchantPoints(frame, omitConcealedPoint)
    local points = {}
    for i = 1, frame:GetNumPoints() do
        local point, relative, side, x, y = frame:GetPoint(i)
        if not (omitConcealedPoint and point == "TOPLEFT" and relative == UIParent
            and side == "TOPRIGHT" and x == nativeOffscreenX and y == 0) then
            points[#points + 1] = { point, relative, side, x, y }
        end
    end
    return points
end

local function PositionNativeMerchant(state, concealed)
    local frame = state.frame
    if InCombatLockdown() and frame:IsProtected() then return false end
    state.positioning = true
    local ok = pcall(function()
        frame:SetClampedToScreen(false)
        frame:ClearAllPoints()
        if concealed then
            frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", nativeOffscreenX, 0)
            frame:SetAlpha(0)
        else
            for _, point in ipairs(state.points) do frame:SetPoint(unpack(point, 1, 5)) end
            frame:SetClampedToScreen(state.clamped)
            frame:SetAlpha(state.alpha)
        end
    end)
    state.positioning = nil
    return ok
end

function E:RestoreNativeMerchant()
    local state = self.nativeMerchant
    if not state then return end
    state.restoring = true
    if PositionNativeMerchant(state, false) then self.nativeMerchant = nil end
end

function E:ConcealNativeMerchant()
    if InCombatLockdown() or not self:HasActiveMerchant() then return false end
    if self.nativeMerchant then return not self.nativeMerchant.restoring end
    local frame = MerchantFrame
    local points = ReadMerchantPoints(frame)
    if #points == 0 then return false end
    -- OnHide would end the merchant interaction. Alpha plus an off-screen
    -- position keeps the native session alive and its buttons off the cursor.
    local state = { frame = frame, points = points, alpha = frame:GetAlpha(), clamped = frame:IsClampedToScreen() }
    self.nativeMerchant = state
    if PositionNativeMerchant(state, true) then return true end
    self:RestoreNativeMerchant()
    return false
end

local function HideCustomMerchant()
    E.hidingMerchantViews = true
    if E.merchantWindow then E.merchantWindow:Hide() end
    E:CloseLootReview()
    E.hidingMerchantViews = nil
    E:CancelSaleActions()
    E:CancelPurchase()
end

function E:ShowStandardMerchant()
    HideCustomMerchant()
    self:RestoreNativeMerchant()
end

function E:MerchantViewHidden()
    if self.hidingMerchantViews or self:IsLootReviewOpen()
        or (self.merchantWindow and self.merchantWindow:IsShown()) then return end
    local wasConcealed = self.nativeMerchant ~= nil
    self:ShowStandardMerchant()
    if wasConcealed and self:HasActiveMerchant() then _G.CloseMerchant() end
end

local function AttachMerchantButton()
    if not MerchantFrame or InCombatLockdown() then return end
    if not E.merchantButton then
        local button = ns.CreateMerchantIcon(MerchantFrame, { texture = icon }, ns.MerchantLabels.addon, function()
            E:OpenMerchantWindow()
        end)
        button:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", -4, -4)
        E.merchantButton = button
        MerchantFrame:HookScript("OnHide", function() E:ShowStandardMerchant() end)
        hooksecurefunc(MerchantFrame, "SetPoint", function()
            local state = E.nativeMerchant
            if not state or state.positioning or state.restoring or state.repositionQueued then return end
            state.repositionQueued = true
            C_Timer.After(0, function()
                state.repositionQueued = nil
                if E.nativeMerchant ~= state or state.restoring or InCombatLockdown() or not E:HasActiveMerchant() then return end
                local points = ReadMerchantPoints(state.frame, true)
                if #points > 0 then state.points = points end
                if not PositionNativeMerchant(state, true) then E:ShowStandardMerchant() end
            end)
        end)
    end
end

local function Initialize()
    if type(Sintezza_VendorDB) ~= "table" then Sintezza_VendorDB = {} end
    local db = Sintezza_VendorDB
    if type(db.profile) ~= "table" then db.profile = {} end
    if type(db.minimap) ~= "table" then db.minimap = { minimapPos = 255 } end
    E.profile = db.profile
    local profile = E.profile
    profile.purchaseLimitGold = ns.ParsePurchaseLimit(profile.purchaseLimitGold) or 100
    profile.sellBindingFilter = profile.sellBindingFilter == "boe" and "boe"
        or profile.sellBindingFilter == "sb" and "sb" or "all"
    for _, key in ipairs({ "showPanelOnVendor", "protectEquipmentSets" }) do
        profile[key] = profile[key] ~= false
    end
    local name, realm = UnitName("player"), GetRealmName()
    if not (issecretvalue and (issecretvalue(name) or issecretvalue(realm))) and name and realm then
        if type(db.characters) ~= "table" then db.characters = {} end
        local key = realm .. " - " .. name
        local character = db.characters[key]
        if type(character) ~= "table" then character = {}; db.characters[key] = character end
        if type(character.blacklist) ~= "table" then character.blacklist = {} end
        if type(character.transactionLogs) ~= "table" then character.transactionLogs = {} end
        E.character, E.blacklist = character, character.blacklist
    end
    local function OpenSettings() E:OpenSettings() end
    ns.Launcher:RegisterSettings(title, OpenSettings)
    ns.Launcher:RegisterMinimap(title, icon, db.minimap, OpenSettings)
    E:CreateLootReviewPopup()
    E:CreateQuickSalePopup()
end

SLASH_SINTEZZA_VENDOR1 = "/svendor"
SLASH_SINTEZZA_VENDOR2 = "/sintezzavendor"
SlashCmdList.SINTEZZA_VENDOR = function(message)
    if message == "status" then
        local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or title
        Print(version .. " · " .. (E:HasActiveMerchant() and Text("Merchant open", "Торговец открыт")
            or Text("Merchant closed", "Торговец закрыт")))
    elseif message == "review" and E:HasActiveMerchant() and not InCombatLockdown() then
        E:OpenLootReview()
    elseif message == "merchant" then
        E:OpenMerchantWindow()
    elseif message == "logs" then
        E:OpenMerchantWindow("journal")
    else
        E:OpenSettings()
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE",
    "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_MONEY", "CURRENCY_DISPLAY_UPDATE", "CURSOR_CHANGED", "UPDATE_INVENTORY_DURABILITY",
    "GUILDBANK_UPDATE_MONEY", "GUILDBANK_UPDATE_WITHDRAWMONEY" }) do
    events:RegisterEvent(event)
end
local refreshQueued, rescanReview
local function QueueRefresh(scan)
    rescanReview = rescanReview or scan
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(.1, function()
        refreshQueued = nil
        local rescan = rescanReview
        rescanReview = nil
        E:RefreshMerchantWindow()
        if not E.saleActive then E:RefreshLootReview(rescan) end
    end)
end

local toolScanQueued, exclusionsRefreshQueued
local function QueueToolScan()
    if toolScanQueued then return end
    toolScanQueued = true
    C_Timer.After(.1, function()
        toolScanQueued = nil
        E:ScanProfessionTools()
    end)
end

local function QueueExclusionsRefresh()
    if exclusionsRefreshQueued then return end
    exclusionsRefreshQueued = true
    C_Timer.After(.1, function()
        exclusionsRefreshQueued = nil
        E:RefreshExclusions()
    end)
end

events:SetScript("OnEvent", function(_, event, itemID, loaded)
    if event == "PLAYER_LOGIN" then
        Initialize()
        AttachMerchantButton()
        QueueToolScan()
    elseif event == "MERCHANT_SHOW" then
        local interaction = {}
        E.interaction = interaction
        E.merchantMessage = nil
        C_Timer.After(0, function()
            if E.interaction ~= interaction or not E.profile or InCombatLockdown() or not E:HasActiveMerchant() then return end
            AttachMerchantButton()
            E:ScanProfessionTools()
            if E.profile.showPanelOnVendor then E:OpenMerchantWindow() end
            if E.profile.autoSellJunk == true and E:CanUseSale() then
                E:RequestQuickSale(E:GetJunkSaleItems(), false)
            end
        end)
    elseif event == "MERCHANT_CLOSED" or event == "PLAYER_REGEN_DISABLED" then
        E.interaction = nil
        E:ShowStandardMerchant()
    elseif event == "PLAYER_REGEN_ENABLED" then
        E:ScanProfessionTools()
        if E.nativeMerchant and E.nativeMerchant.restoring then E:RestoreNativeMerchant() end
        AttachMerchantButton()
    elseif event == "GET_ITEM_INFO_RECEIVED" and loaded then
        itemID = ns.Public(itemID, "number")
        if itemID and E.professionToolPending and E.professionToolPending[itemID] then QueueToolScan() end
        if itemID and E:IsExcluded(itemID) then QueueExclusionsRefresh() end
        if E:IsLootReviewOpen() or E.merchantWindow and E.merchantWindow:IsShown() then QueueRefresh(true) end
    elseif event == "BAG_UPDATE_DELAYED" then
        QueueToolScan()
        if E:IsLootReviewOpen() or E.merchantWindow and E.merchantWindow:IsShown() then QueueRefresh(true) end
    elseif E:IsLootReviewOpen() or E.merchantWindow and E.merchantWindow:IsShown() then
        if event ~= "GET_ITEM_INFO_RECEIVED" then
            QueueRefresh(event == "BAG_UPDATE_DELAYED")
        end
    end
end)

local _, ns = ...
local E, T, Text, Public = ns.vendor, ns.Theme, ns.Text, ns.Public
local W = Sintezza_Theme:CreateWidgets(T)
local SETTINGS_HEIGHT = 544

local function SetOption(key, value)
    E.profile[key] = value
    E:RefreshMerchantWindow()
    E:RefreshLootReview(true)
end

local function Place(row, previous, parent)
    if previous then row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -3)
    else row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -10) end
    row:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
    return row
end

local function Toggle(parent, previous, key, label, description)
    return Place(W:Toggle(parent, label, function() return E.profile[key] end,
        function(value) SetOption(key, value) end, description), previous, parent)
end

local function BuildPurchaseLimit(parent, previous)
    local row = Place(W:SettingRow(parent,
        Text("Instant purchase limit (gold, 0 = always confirm)",
            "Лимит покупки без подтверждения (золото, 0 — всегда спрашивать)")), previous, parent)
    local edit = W:EditBox(row, "", function() end)
    edit:SetSize(112, 24)
    edit:SetPoint("RIGHT", row, "RIGHT")
    edit:SetJustifyH("RIGHT")
    local function Restore()
        edit:SetText(("%.0f"):format(E.profile.purchaseLimitGold))
    end
    edit:HookScript("OnEditFocusGained", function(self)
        W:SetInputError(row)
        self:HighlightText()
    end)
    edit:HookScript("OnEditFocusLost", Restore)
    edit:SetScript("OnEnterPressed", function(self)
        local value = ns.ParsePurchaseLimit(self:GetText())
        if value then E.profile.purchaseLimitGold = value end
        self:ClearFocus()
        W:SetInputError(row, not value and Text("Enter a whole amount of gold.", "Введи целое число золотых.") or nil)
    end)
    row:HookScript("OnHide", function()
        edit:ClearFocus()
        W:SetInputError(row)
    end)
    Restore()
    return row
end

local function BuildSale(parent, select)
    local row = Toggle(parent, nil, "showPanelOnVendor",
        Text("Open Sintezza Vendor at merchants", "Открывать Sintezza Vendor у торговца"))
    row = Toggle(parent, row, "colorCostsByAffordability",
        Text("Highlight affordable purchases", "Подсвечивать доступность покупки"))
    row = BuildPurchaseLimit(parent, row)
    row = Place(W:ChoiceRow(parent, Text("Binding filter", "Фильтр по привязке"), {
        all = Text("Any", "Любая"),
        sb = Text("Bound only", "Только привязанные"),
        boe = Text("Unbound BoE only", "Только непривязанные BoE"),
    }, function() return E.profile.sellBindingFilter end,
        function(value) SetOption("sellBindingFilter", value) end, { all = 1, sb = 2, boe = 3 }), row, parent)
    if W.Help then
        W:Help(row, Text("Limits which items can be sold through Sintezza Vendor by their binding status.",
            "Ограничивает продажу через Sintezza Vendor по типу привязки предмета."))
    end
    row = Place(W:ActionRow(parent, Text("Character exclusions", "Исключения персонажа"),
        Text("Open", "Открыть"), function() select("excluded") end), row, parent)

    local advanced, arrow
    local function SetAdvanced(shown)
        advanced:SetShown(shown)
        arrow:SetRotation(shown and -math.pi / 2 or 0)
    end
    local disclosure = Place(W:Button(parent, Text("Advanced", "Дополнительно"),
        function() SetAdvanced(not advanced:IsShown()) end), row, parent)
    arrow = T:DropdownArrow(disclosure)
    advanced = CreateFrame("Frame", nil, parent)
    advanced:SetPoint("TOPLEFT", disclosure, "BOTTOMLEFT", -12, -2)
    advanced:SetPoint("BOTTOMRIGHT")
    row = Toggle(advanced, nil, "autoSellJunk", Text("Sell poor items when a merchant opens", "Продавать серый хлам при открытии торговца"),
        Text("Also applies when the standard merchant opens.", "Автопродажа хлама действует и при открытии штатного торговца."))
    row = Toggle(advanced, row, "protectEquipmentSets",
        Text("Protect equipment set items", "Беречь предметы из комплектов"))
    row = Toggle(advanced, row, "protectKnownBoundItems",
        Text("Protect known bound items", "Защищать изученные привязанные предметы"))
    Toggle(advanced, row, "showItemLevelsOnIcons", Text("Show item levels", "Показывать уровни предметов"))
    SetAdvanced(false)
end

local function BuildExclusions(panel, parent)
    local search = W:EditBox(parent, Text("Find an excluded item", "Найти исключенный предмет"), function() end)
    search:SetPoint("TOPLEFT", 12, -10)
    search:SetPoint("TOPRIGHT", -12, -10)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    parent:HookScript("OnHide", function() search:ClearFocus() end)
    local scroll, body, bar = W:ScrollFrame(parent, nil, 30)
    scroll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 12)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    scroll:HookScript("OnSizeChanged", function(self, width) body:SetWidth(math.max(1, width)) end)
    local empty = W:Label(body, Text("No excluded items found.", "Предметы не найдены."), 11, T.muted)
    empty:SetPoint("TOPLEFT", 0, -6)
    local rows = {}
    function panel:RefreshExclusions()
        if not self:IsShown() or not parent:IsShown() then return end
        local query = ns.FoldText(search:GetText())
        local items, seen = {}, {}
        for key in pairs(E.blacklist or {}) do
            local id = tonumber(key)
            if id and id > 0 and id == math.floor(id) and not seen[id] and E:IsExcluded(id) then
                seen[id] = true
                local name = Public(C_Item.GetItemInfo(id), "string")
                local label = name or Text("Item #", "Предмет №") .. id
                local folded = ns.FoldText(label)
                if folded:find(query, 1, true) or tostring(id):find(query, 1, true) then
                    items[#items + 1] = { id = id, label = label, folded = folded }
                end
            end
        end
        table.sort(items, function(a, b)
            if a.folded == b.folded then return a.id < b.id end
            return a.folded < b.folded
        end)
        for index, item in ipairs(items) do
            local row = rows[index]
            if not row then
                row = W:ActionRow(body, "", Text("Remove exclusion", "Снять исключение"), function()
                    if row.itemID and not InCombatLockdown() then E:SetExcluded(row.itemID, false) end
                end)
                row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(index - 1) * 30)
                row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -(index - 1) * 30)
                rows[index] = row
            end
            row.itemID = item.id
            row.label:SetText(item.label)
            row:Show()
        end
        for index = #items + 1, #rows do rows[index]:Hide() end
        body:SetHeight(math.max(22, #items * 30))
        empty:SetShown(#items == 0)
        scroll:RefreshRange()
    end
    parent:HookScript("OnShow", function() panel:RefreshExclusions() end)
    search:HookScript("OnTextChanged", function()
        scroll:SetVerticalScroll(0)
        panel:RefreshExclusions()
    end)
end

function E:RefreshExclusions()
    if self.settings then self.settings:RefreshExclusions() end
end

local function CreateSettings()
    local panel = CreateFrame("Frame", "Sintezza_VendorSettings", UIParent, "BackdropTemplate")
    local appearance = E.windowAppearance
    panel:SetSize(650, SETTINGS_HEIGHT)
    panel:SetFrameStrata("DIALOG")
    panel:SetPoint("CENTER")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:Hide()
    T:WindowSurface(panel)
    local header = W:WindowHeader(panel, { title = Text("Sintezza Vendor Settings", "Настройки Sintezza Vendor"), icon = ns.Icon })
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if appearance:CanMove() then panel:StartMoving() end
    end)
    header:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)
    panel:HookScript("OnHide", function() panel:StopMovingOrSizing() end)

    local keys = { "sale", "excluded", "window" }
    local labels = { Text("Buying and selling", "Покупка и продажа"), Text("Exclusions", "Исключения"),
        Text("Window and minimap", "Окно и миникарта") }
    local pages, current, tabs = {}, "sale"
    local function Select(key)
        current = pages[key] and key or "sale"
        for id, page in pairs(pages) do page:SetShown(id == current) end
        tabs:Refresh()
    end
    tabs = W:Segmented(panel, labels, keys, function() return current end, Select, true)
    tabs:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -4)
    tabs:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -12, -4)
    for _, key in ipairs(keys) do
        local page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -4)
        page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 8)
        pages[key] = page
    end
    BuildSale(pages.sale, Select)
    BuildExclusions(panel, pages.excluded)
    local options = Sintezza_Theme:CreateWindowOptions(pages.window, T, {
        windows = { { prefs = appearance } },
        getMinimap = function() return not Sintezza_VendorDB.minimap.hide end,
        setMinimap = function(value)
            Sintezza_VendorDB.minimap.hide = not value
            ns.Launcher:RefreshMinimap(Sintezza_VendorDB.minimap)
        end,
    })
    options:SetPoint("TOPLEFT", 0, -6)
    options:SetPoint("TOPRIGHT", 0, -6)
    panel.SelectPage = Select
    Select(current)

    UISpecialFrames[#UISpecialFrames + 1] = panel:GetName()
    appearance:Bind(panel, { resize = { minWidth = 625, minHeight = SETTINGS_HEIGHT, maxWidth = 940, maxHeight = 800 } })
    return panel
end

function E:OpenSettings(page)
    if not self.profile or InCombatLockdown() then return end
    self.settings = self.settings or CreateSettings()
    if page then self.settings.SelectPage(page) end
    self.settings:Show()
    self.settings:Raise()
end

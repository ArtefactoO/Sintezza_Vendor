local addonName, ns = ...
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
        Text("Instant purchase limit", "Лимит покупки без подтверждения")), previous, parent)
    if W.Help then
        W:Help(row, Text("Maximum price in gold for a purchase without confirmation. Enter 0 to always ask. Barter and buyback always require confirmation.",
            "Максимальная цена покупки в золоте без подтверждения. Введите 0, чтобы спрашивать всегда. Обмен и выкуп всегда требуют подтверждения."))
    end
    local coin = W:Label(row, "", 12, T.text)
    local coinText = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString and C_CurrencyInfo.GetCoinTextureString(10000, 12)
    coin:SetText(type(coinText) == "string" and (coinText:match("(|A:.-|a)") or coinText:match("(|T.-|t)"))
        or "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12|t")
    coin:SetWidth(16)
    coin:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    local edit = W:EditBox(row, "", function() end)
    edit:SetSize(50, 24)
    edit:SetTextInsets(5, 5, 0, 0)
    edit:SetPoint("RIGHT", coin, "LEFT", -3, 0)
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
    row = Place(W:ChoiceRow(parent, Text("Sell by binding", "Продавать по привязке"), {
        all = Text("Any", "Любая"),
        sb = Text("Bound only", "Только привязанные"),
        boe = Text("Unbound BoE only", "Только непривязанные BoE"),
    }, function() return E.profile.sellBindingFilter end,
        function(value) SetOption("sellBindingFilter", value) end, { all = 1, sb = 2, boe = 3 }), row, parent)
    if W.Help then
        W:Help(row, Text("Limits sales through Vendor, including junk. Any: no binding restriction; Bound only: bound items; Unbound BoE only: unbound bind-on-equip items. Other protections still apply.",
            "Ограничивает продажу через Vendor, включая хлам. Любая: без ограничения; только привязанные: уже привязанные предметы; только непривязанные BoE: непривязанные предметы с привязкой при надевании. Остальные защиты сохраняются."))
    end
    row = Toggle(parent, row, "autoSellJunk", Text("Sell poor items when a merchant opens", "Продавать серый хлам при открытии торговца"),
        Text("Also applies when the standard merchant opens.", "Автопродажа хлама действует и при открытии штатного торговца."))
    row = Toggle(parent, row, "protectEquipmentSets",
        Text("Protect equipment set items", "Беречь предметы из комплектов"))
    row = Toggle(parent, row, "protectKnownBoundItems",
        Text("Protect known bound items", "Защищать изученные привязанные предметы"))
    Toggle(parent, row, "showItemLevelsOnIcons", Text("Show item levels", "Показывать уровни предметов"))
end

local function BuildExclusions(panel, parent)
    local search = W:EditBox(parent, Text("Find an excluded item", "Найти исключенный предмет"), function() end)
    search:SetPoint("TOPLEFT", 12, -10)
    search:SetWidth(370)
    parent:HookScript("OnSizeChanged", function(self, width) search:SetWidth(math.max(120, math.min(370, width - 40))) end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    parent:HookScript("OnHide", function() search:ClearFocus() end)
    local scroll, body, bar = W:ScrollFrame(parent, nil, 30)
    scroll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", -16, -8)
    scroll:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 12, 12)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    scroll:HookScript("OnSizeChanged", function(self, width) body:SetWidth(math.max(1, width)) end)
    local empty = W:Label(body, Text("No excluded items found.", "Предметы не найдены."), 11, T.muted)
    empty:SetPoint("TOPLEFT", 0, -6)
    local rows = {}
    local waitingForItems, waitScheduled, timedOut = false, false, false
    function panel:RefreshExclusions()
        if not self:IsShown() or not parent:IsShown() then return end
        local query = ns.FoldText(search:GetText())
        local items, seen, pending = {}, {}, false
        for key in pairs(E.blacklist or {}) do
            local id = tonumber(key)
            if id and id > 0 and id == math.floor(id) and not seen[id] and E:IsExcluded(id) then
                seen[id] = true
                local name, link, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(id)
                name, link, quality, texture = Public(name, "string"), Public(link, "string"), Public(quality, "number"), Public(texture, "number")
                if not name or not quality or not texture then pending = true end
                local label = name or Text("Item #", "Предмет №") .. id
                local folded = ns.FoldText(label)
                if folded:find(query, 1, true) or tostring(id):find(query, 1, true) then
                    items[#items + 1] = { id = id, label = label, folded = folded, link = link, quality = quality, texture = texture }
                end
            end
        end
        waitingForItems = pending
        if pending and not timedOut then
            for _, row in ipairs(rows) do row:Hide() end
            empty:SetText(Text("Loading items...", "Загрузка предметов..."))
            empty:Show()
            body:SetHeight(22)
            scroll:RefreshRange()
            if not waitScheduled then
                waitScheduled = true
                C_Timer.After(1, function()
                    waitScheduled = false
                    if waitingForItems and parent:IsVisible() then timedOut = true; panel:RefreshExclusions() end
                end)
            end
            return
        end
        table.sort(items, function(a, b)
            if timedOut then return a.id < b.id end
            if a.folded == b.folded then return a.id < b.id end
            return a.folded < b.folded
        end)
        for index, item in ipairs(items) do
            local row = rows[index]
            if not row then
                row = CreateFrame("Frame", nil, body)
                row:SetHeight(34)
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(self)
                    if not self.itemLink then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.itemLink)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(24, 24)
                row.icon:SetPoint("LEFT", 2, 0)
                row.icon:SetTexCoord(.07, .93, .07, .93)
                row.border = T:FrameIcon(row, row.icon)
                local remove = CreateFrame("Button", nil, row)
                remove:SetSize(26, 26)
                remove:SetPoint("RIGHT", -2, 0)
                local paint = T:CloseGlyph(remove)
                paint(T.accent)
                remove:SetScript("OnEnter", function(self)
                    paint(T.text)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(Text("Remove exclusion", "Снять исключение"))
                    GameTooltip:Show()
                end)
                remove:SetScript("OnLeave", function(self) paint(T.accent); if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
                remove:SetScript("OnClick", function()
                    if row.itemID and not InCombatLockdown() then E:SetExcluded(row.itemID, false) end
                end)
                row.label = W:Label(row, "", 11, T.text)
                row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                row.label:SetPoint("RIGHT", remove, "LEFT", -4, 0)
                row.label:SetWordWrap(false)
                local rule = row:CreateTexture(nil, "BORDER")
                rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
                Sintezza_Theme:Tint(rule, "SetColorTexture", T.lineSoft, .45)
                row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(index - 1) * 34)
                row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -(index - 1) * 34)
                rows[index] = row
            end
            row.itemID = item.id
            row.itemLink = item.link
            row.label:SetText(item.label)
            row.icon:SetTexture(item.texture or 134400)
            local r, g, b
            if item.quality and GetItemQualityColor then r, g, b = GetItemQualityColor(item.quality) end
            row.label:SetTextColor(r or 1, g or 1, b or 1)
            T:PaintItemBorder(row.border, item.quality)
            row:Show()
        end
        for index = #items + 1, #rows do rows[index]:Hide() end
        body:SetHeight(math.max(22, #items * 34))
        empty:SetText(Text("No excluded items found.", "Предметы не найдены."))
        empty:SetShown(#items == 0)
        scroll:RefreshRange()
    end
    parent:HookScript("OnShow", function() timedOut = false; panel:RefreshExclusions() end)
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
    local header = W:WindowHeader(panel, {
        title = Text("Sintezza Vendor Settings", "Настройки Sintezza Vendor"), addonName = addonName, icon = ns.Icon,
    })
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

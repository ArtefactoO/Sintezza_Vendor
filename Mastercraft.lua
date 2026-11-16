local _, ns = ...
local Public, Text = ns.Public, ns.Text
local E = ns.vendor
local verdicts = {
    VENDOR = "vendor", ["ТОРГОВЦУ"] = "vendor",
    AUCTION = "auction", ["АУКЦИОН"] = "auction",
    DISENCHANT = "disenchant", ["РАСПЫЛИТЬ"] = "disenchant",
    KEEP = "keep", ["ОСТАВИТЬ"] = "keep",
    ["NO PRICES"] = "unknown", ["НЕТ ЦЕН"] = "unknown",
}
local verdictLabels = {
    vendor = Text("Sell to vendor", "Продать торговцу"),
    auction = Text("Auction", "Выставить на аукцион"),
    disenchant = Text("Disenchant", "Распылить"),
    keep = Text("Keep", "Оставить"),
    unknown = Text("No prices", "Нет цен"),
}

function E:HasMastercraft()
    local addons = C_AddOns
    if not addons or not addons.IsAddOnLoaded then return false end
    local active, loaded = addons.IsAddOnLoaded("Mastercraft")
    if loaded ~= nil then return loaded == true end
    return active == true
end

local function ReadLine(tooltipName, column, index)
    local region = _G[tooltipName .. "Text" .. column .. index]
    local value = region and region:IsShown() and Public(region:GetText(), "string")
    if value then return (value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
end

local coinUnits = {
    gold = 10000, silver = 100, copper = 1,
    ["ui-goldicon"] = 10000, ["ui-silvericon"] = 100, ["ui-coppericon"] = 1,
}

local function NativeCoinTokens()
    local native = {}
    if GetMoneyString or GetCoinTextureString then
        for _, amount in ipairs({ 10000, 100, 1 }) do
            local formatted = GetMoneyString and GetMoneyString(amount, true)
                or GetCoinTextureString and GetCoinTextureString(amount)
            local token = formatted and formatted:match("|[TA]([^|]+)|[ta]")
            if token then native[token] = amount end
        end
    end
    return native
end

local function Coins(text, native)
    if not text then return end
    text = text:gsub("\194\160", " "):gsub("\226\128\175", " ")
    text = text:gsub("^%s*~?%s*", "")
    local total
    while true do
        local amount, opener, icon, closer, nextToken = text:match("^(%d[%d,. ]*)|([TA])([^|]+)|([ta])%s*()")
        if not amount then break end
        local file = (icon:match("^[^:]+") or ""):match("[^/\\]+$")
        local unit = native[icon] or (file and coinUnits[file:lower()])
        local count = tonumber((amount:gsub("%D", "")))
        if opener:lower() ~= closer or not unit or not count or count >= math.huge then return end
        total = (total or 0) + count * unit
        text = text:sub(nextToken)
    end
    -- A source and age may follow the price. Additional markup or bare digits mean the price was incomplete.
    if text:find("|", 1, true) or text:match("^%d[%d,. ]*$") then return end
    if total and total < math.huge then return total end
end

function E:ReadMastercraft(items, owner)
    if not self:HasMastercraft() then
        return nil, Text("Mastercraft unavailable · fallback", "Нет Mastercraft · резервная оценка")
    end
    local config = type(MastercraftDB) == "table" and Public(MastercraftDB.settings, "table")
    local afterAuctionCut = not config or config.ahCut ~= false
    if config and config.lootTooltip == false then
        return nil, Text("Mastercraft loot advice off · fallback", "Совет Mastercraft выключен · резервная оценка")
    end
    local tooltip = GameTooltip
    if InCombatLockdown() or not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) or tooltip:IsShown() then
        return nil, Text("Tooltip unavailable · fallback", "Подсказка недоступна · резервная оценка")
    end
    local alpha, advice = tooltip:GetAlpha(), {}
    local coins = NativeCoinTokens()
    local ok = pcall(function()
        tooltip:SetAlpha(0)
        local name = tooltip:GetName()
        for _, item in ipairs(items) do
            tooltip:SetOwner(owner, "ANCHOR_NONE")
            tooltip:ClearLines()
            tooltip:SetBagItem(item.bag, item.slot)
            local info
            for line = 1, tooltip:NumLines() do
                local left = ReadLine(name, "Left", line)
                local right = ReadLine(name, "Right", line)
                local verdict = left == "Mastercraft" and right and verdicts[right]
                if verdict then
                    info = { verdict = verdict, label = verdictLabels[verdict], guid = item.guid, link = item.link,
                        count = item.count, afterAuctionCut = afterAuctionCut }
                    advice[item.key] = info
                elseif info and (left == "Auction" or left == "Аукцион" or left == "Auction house") then
                    info.auction = Coins(right, coins)
                elseif info and (left == "Disenchant" or left == "Распыление") then
                    info.disenchant = Coins(right, coins)
                end
            end
        end
    end)
    tooltip:Hide()
    tooltip:SetAlpha(alpha)
    if ok and next(advice) then return advice end
    return nil, Text("No Mastercraft advice · fallback", "Нет советов Mastercraft · резервная оценка")
end

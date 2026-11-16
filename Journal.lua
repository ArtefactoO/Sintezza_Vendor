local _, ns = ...
local E, Public, Text = ns.vendor, ns.Public, ns.Text

function E:MerchantName()
    return Public(UnitName("npc"), "string") or Text("Vendor", "Торговец")
end

function E:GetJournal()
    return self.character and self.character.transactionLogs
end

function E:RecordTransaction(kind, item, count, money, vendor, currencies)
    local sessions = self:GetJournal()
    if not sessions then return end
    local timestamp = time()
    local session = self.journalSession
    if not session then
        session = { startedAt = timestamp, entries = {}, goldSpent = 0, goldGained = 0 }
        sessions[#sessions + 1] = session
        self.journalSession = session
        if #sessions > 100 then table.remove(sessions, 1) end
    end
    session.entries[#session.entries + 1] = {
        kind = kind, time = timestamp, vendor = vendor, name = item.name, link = item.link,
        texture = item.texture, quality = item.quality, itemID = item.itemID,
        quantity = count, gold = money, currencies = currencies,
    }
    if kind == "sell" then
        session.goldGained = session.goldGained + money
    else
        session.goldSpent = session.goldSpent + money
    end
    session.lastActivityAt = timestamp
end

function E:ClearJournal()
    if not self.character or self:LootReviewBusy() or InCombatLockdown() then return false end
    self.character.transactionLogs = {}
    self.journalSession = nil
    self:RefreshMerchantWindow()
    return true
end

local function Payload()
    return Sintezza_Theme.DataTransfer
end

local kinds = { buy = true, buyback = true, sell = true }
local invalid = Text("Invalid vendor journal entry.", "Некорректная запись журнала торговца.")
local unavailable = Text("Journal is unavailable right now.", "Журнал сейчас недоступен.")
local sessionLimit = Text("The import would exceed 100 journal sessions.", "После импорта будет больше 100 сеансов журнала.")

local function Integer(value, minimum, maximum)
    local result = tonumber(value)
    if result and result >= minimum and result <= maximum and result == math.floor(result) then return result end
end

local function Plain(value, limit)
    return type(value) == "string" and #value <= limit and not value:find("[%z\1-\31\127|]")
end

local function Texture(value)
    return value == "" or Integer(value, 1, 2147483647)
        or type(value) == "string" and #value <= 160 and value:match("^Interface[\\/][%w _\\/%.%-]+$")
end

local function Link(value)
    if value == "" then return true end
    if type(value) ~= "string" or #value > 1024 or value:find("[%z\1-\31\127]") then return false end
    local clean = value:gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("^|cnIQ%d+:", ""):gsub("|r$", "")
    local kind = clean:match("^|H([A-Za-z]+):[0-9]+[A-Za-z0-9:%-]*|h%[[^|]*%]|h$")
    return kind == "item" or kind == "currency"
end

local function SerializeRow(startedAt, entry)
    local currencies = ""
    if type(entry.currencies) == "table" and #entry.currencies > 0 then
        currencies = Payload():EncodeRecord(entry.currencies)
        if not currencies then return end
    end
    return {
        tostring(startedAt or entry.time or ""), tostring(entry.time or ""), entry.kind or "", entry.vendor or "",
        entry.name or "", entry.link or "", tostring(entry.texture or ""), tostring(entry.quality or ""),
        tostring(entry.itemID or ""), tostring(entry.quantity or ""), tostring(entry.gold or ""), currencies,
    }
end

local function ReadRow(row)
    local session = Integer(row[1], 1, 4102444800)
    local timestamp = Integer(row[2], 1, 4102444800)
    local quantity, gold = Integer(row[10], 1, 2147483647), Integer(row[11], 0, 9007199254740991)
    local quality, itemID = Integer(row[8], 0, 8), Integer(row[9], 1, 2147483647)
    if not (session and timestamp and kinds[row[3]] and Plain(row[4], 200) and Plain(row[5], 300)
        and row[5] ~= "" and Link(row[6]) and Texture(row[7]) and quantity and gold)
        or not (quality or row[8] == "") or not (itemID or row[9] == "") then return end

    local currencies
    if row[12] ~= "" then
        local raw = Payload():DecodeRecord(row[12])
        if type(raw) ~= "table" or #raw < 1 or #raw > 20 then return end
        currencies = {}
        for key in pairs(raw) do if not Integer(key, 1, #raw) or type(key) ~= "number" then return end end
        for _, value in ipairs(raw) do
            if type(value) ~= "table" then return end
            local amount = Integer(value.amount, 1, 2147483647)
            local texture, name, link = value.texture or "", value.name or "", value.link or ""
            if not (amount and Texture(texture) and Plain(name, 300) and Link(link)) then return end
            local currencyID = Integer(value.currencyID, 1, 2147483647)
            local costItemID = Integer(value.itemID, 1, 2147483647)
            if value.currencyID ~= nil and not currencyID or value.itemID ~= nil and not costItemID then return end
            currencies[#currencies + 1] = {
                amount = amount, texture = tonumber(texture) or texture ~= "" and texture or nil,
                name = name ~= "" and name or nil, link = link ~= "" and link or nil,
                currencyID = currencyID, itemID = costItemID,
            }
        end
        if #currencies ~= #raw then return end
    end
    return session, {
        time = timestamp, kind = row[3], vendor = row[4], name = row[5], link = row[6] ~= "" and row[6] or nil,
        texture = tonumber(row[7]) or row[7] ~= "" and row[7] or nil, quality = quality, itemID = itemID,
        quantity = quantity, gold = gold, currencies = currencies,
    }
end

local function Export()
    local journal = E:GetJournal()
    if not journal then return nil, unavailable end
    local rows = {}
    for _, session in ipairs(journal) do
        for _, entry in ipairs(session.entries or {}) do
            local row = SerializeRow(session.startedAt, entry)
            if not row or not ReadRow(row) then return nil, invalid end
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function Stage(rows)
    local journal = E:GetJournal()
    if not journal then return nil, unavailable end
    local existing, times = {}, {}
    for _, session in ipairs(journal) do
        if session.startedAt then times[session.startedAt] = true end
        for _, entry in ipairs(session.entries or {}) do
            local row = SerializeRow(session.startedAt, entry)
            local timestamp, normalized
            if row then timestamp, normalized = ReadRow(row) end
            local canonical = normalized and SerializeRow(timestamp, normalized)
            local key = canonical and Payload():EncodeRecord(canonical)
            if key then existing[key] = (existing[key] or 0) + 1 end
        end
    end
    local plan = { added = 0, duplicates = 0, groups = {} }
    local count = #journal
    for _, row in ipairs(rows) do
        local timestamp, entry = ReadRow(row)
        local canonical = entry and SerializeRow(timestamp, entry)
        local key = canonical and Payload():EncodeRecord(canonical)
        if not key then return nil, invalid end
        if (existing[key] or 0) > 0 then
            existing[key] = existing[key] - 1
            plan.duplicates = plan.duplicates + 1
        else
            if not times[timestamp] then
                times[timestamp], count = true, count + 1
                if count > 100 then return nil, sessionLimit end
            end
            local group = plan.groups[timestamp] or {}
            plan.groups[timestamp] = group
            group[#group + 1] = entry
            plan.added = plan.added + 1
        end
    end
    return plan
end

local function Apply(plan)
    local journal = E:GetJournal()
    if not journal or E:LootReviewBusy() or InCombatLockdown() then return nil, unavailable end
    local sessions = {}
    for _, session in ipairs(journal) do
        if session.startedAt then sessions[session.startedAt] = session end
    end
    for startedAt, entries in pairs(plan.groups) do
        local session = sessions[startedAt]
        if not session then
            session = { startedAt = startedAt, lastActivityAt = startedAt, entries = {}, goldSpent = 0, goldGained = 0 }
            journal[#journal + 1] = session
        end
        session.entries = session.entries or {}
        for _, entry in ipairs(entries) do
            session.entries[#session.entries + 1] = entry
            session.lastActivityAt = math.max(tonumber(session.lastActivityAt) or startedAt, entry.time)
            local total = entry.kind == "sell" and "goldGained" or "goldSpent"
            session[total] = (tonumber(session[total]) or 0) + entry.gold
        end
        local position = {}
        for i, entry in ipairs(session.entries) do position[entry] = i end
        table.sort(session.entries, function(a, b)
            local left, right = tonumber(a.time) or 0, tonumber(b.time) or 0
            if left == right then return position[a] < position[b] end
            return left < right
        end)
    end
    table.sort(journal, function(a, b) return (tonumber(a.startedAt) or 0) < (tonumber(b.startedAt) or 0) end)
    return true
end

local function Count()
    local count = 0
    for _, session in ipairs(E:GetJournal() or {}) do count = count + #(session.entries or {}) end
    return count
end

local spec = {
    addon = "Sintezza_Vendor",
    title = Text("Vendor journal", "Журнал торговца"),
    note = Text("Only the current character's journal. Memory includes the addon and its data.",
        "Только журнал текущего персонажа. В памяти учитываются код, интерфейс и данные аддона."),
    columns = { "session", "time", "kind", "vendor", "name", "link", "texture", "quality", "item_id", "quantity", "gold", "currencies" },
    scopes = { { key = "all", label = Text("Current character's journal", "Журнал текущего персонажа") } },
    export = Export,
    stage = Stage,
    apply = Apply,
    changed = function() E:RefreshMerchantWindow() end,
    sections = { {
        label = Text("Transactions", "Записи журнала"),
        count = Count,
        clear = function()
            if E:ClearJournal() then return true end
            return nil, unavailable
        end,
    } },
}

function E:OpenJournalData(owner)
    local transfer = Payload()
    if not transfer or InCombatLockdown() then return end
    ns.Theme:OpenMenu(owner, function(_, menu)
        menu:CreateButton(Text("Export CSV", "Экспорт CSV"), function() transfer:Open(self.merchantWindow, spec, "export") end)
        menu:CreateButton(Text("Import CSV", "Импорт CSV"), function() transfer:Open(self.merchantWindow, spec, "import") end)
        menu:CreateButton(Text("Data maintenance", "Обслуживание данных"), function() transfer:OpenMaintenance(self.merchantWindow, spec) end)
    end)
end

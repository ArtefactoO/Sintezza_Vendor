local addon, ns = ...
local api = _G.Sintezza_PerfAPI
if type(api) ~= "table" or api.version ~= 1 then return end
local module = api:RegisterModule(addon, "vendor", { title = "Loot review", titleRu = "Разбор добычи" })
if not module then return end
local call = api:RegisterPoint(module, "scan", { title = "Scan loot review", titleRu = "Сканирование добычи", memory = true })
local counter = api:RegisterPoint(module, "refresh", { kind = "counter", title = "Loot review refreshes", titleRu = "Обновления разбора" })
local bridge = {}
ns.PerfBridge = bridge
function bridge.Count(key)
    if key == "refresh" and counter then api:Count(counter) end
end
local owner = ns.vendor
if call and owner and type(owner.ScanLootReview) == "function" then
    local original = owner.ScanLootReview
    owner.ScanLootReview = function(...)
        if not api:IsActive(call) then return original(...) end
        if issecretvalue then
            for i = 1, select("#", ...) do
                if issecretvalue(select(i, ...)) then return original(...) end
            end
        end
        return api:Call(call, original, ...)
    end
end

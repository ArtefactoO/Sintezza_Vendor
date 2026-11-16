local _, ns = ...
local locale = Sintezza_Theme:GetLocale()

function ns.Text(source, russian)
    return locale == "ruRU" and russian or source
end

local Text = ns.Text
ns.MerchantLabels = {
    addon = Text("Open Sintezza Vendor", "Открыть Sintezza Vendor"),
    stock = Text("Open the standard merchant window", "Открыть штатное окно торговца"),
    repairOne = Text("Repair one item", "Починить один предмет"),
    repairAll = Text("Repair all items", "Починить все"),
    repairGuild = Text("Repair with guild funds", "Починить за счет гильдии"),
    repairGuildTip = Text("Any shortfall can be paid from your gold.", "Недостающая сумма может быть списана из твоего золота."),
    sellJunk = Text("Sell junk", "Продать хлам"),
    lastSale = Text("Last sale", "Последняя продажа"),
    buyBack = Text("Buy back", "Выкупить"),
    buybackEmpty = Text("Nothing to buy back", "Нет предметов для выкупа"),
    exclude = Text("Exclude this item from sales", "Исключить этот предмет из продаж"),
    include = Text("Remove sale exclusion", "Снять исключение из продаж"),
}

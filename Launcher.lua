local addonName, ns = ...
local Launcher = {}
ns.Launcher = Launcher

local openLabel = ns.Text("Open settings", "Открыть настройки")

function Launcher:RegisterSettings(title, open)
    local shared = Sintezza_Theme
    if self.category or not shared.RegisterLauncherPage then return end
    self.category = shared:RegisterLauncherPage({
        title = title,
        icon = ns.Icon or shared.icons[addonName],
        buttonLabel = openLabel,
        open = open,
        appearance = ns.SettingsTheme or ns.Theme,
    })
end

function Launcher:RefreshMinimap(db)
    if self.icon then self.icon:Refresh(db) end
end

function Launcher:RegisterMinimap(title, icon, db, click)
    if self.icon then self:RefreshMinimap(db); return end
    self.icon = Sintezza_Theme:CreateMinimapButton(addonName, icon, db,
        { window = function() return ns.vendor.settings end, open = click },
        function(tooltip)
            tooltip:AddLine(title)
            Sintezza_Theme:AddMinimapToggleHint(tooltip)
        end)
end

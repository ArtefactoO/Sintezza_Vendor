local addon, ns = ...
local shared = Sintezza_Theme
ns.Theme = shared:ForAddon(function() return Sintezza_VendorDB end)
ns.Icon = "Interface\\AddOns\\" .. addon .. "\\Media\\Icon"
ns.merchantIconSize = 24

function ns.CreateMerchantIcon(parent, art, label, click, tip)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    local size = ns.merchantIconSize
    button:SetSize(size, size)
    ns.Theme:SkinButton(button)
    local atlas = art.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(art.atlas)
    local body, dimension = button, size - 6
    if atlas and art.crop and button.SetClipsChildren then
        local clip = CreateFrame("Frame", nil, button)
        clip:SetSize(dimension, dimension)
        clip:SetPoint("CENTER")
        clip:SetClipsChildren(true)
        body = CreateFrame("Frame", nil, clip)
        local full = dimension / (1 - 2 * art.crop)
        body:SetSize(full, full)
        body:SetPoint("CENTER")
        dimension = full
    end
    local icon = body:CreateTexture(nil, "ARTWORK")
    icon:SetSize(dimension, dimension)
    icon:SetPoint("CENTER")
    if atlas then
        icon:SetAtlas(art.atlas, false)
    else
        icon:SetTexture(art.texture)
        if art.crop then icon:SetTexCoord(art.crop, 1 - art.crop, art.crop, 1 - art.crop) end
    end
    button.icon = icon
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    button:SetScript("OnClick", function()
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        click()
    end)
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label)
        if tip then tip(GameTooltip) end
        GameTooltip:Show()
    end)
    local function HideTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    button:HookScript("OnLeave", HideTooltip)
    button:HookScript("OnHide", HideTooltip)
    return button
end

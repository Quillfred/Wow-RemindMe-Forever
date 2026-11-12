-- RemindMe Forever: minimap button (no libraries needed).
-- Left-click: options window. Right-click: test mode on/off. Drag: move around the minimap.

local ADDON, ns = ...

local button

local function UpdatePosition()
    local angle = math.rad(ns.db.minimap.angle or 215)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
    UpdatePosition()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("RemindMe Forever")
    GameTooltip:AddLine("|cffffffffLeft-click:|r options", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffffffRight-click:|r test mode " ..
        (ns.IsTestMode() and "|cff00ff00on|r" or "|cffff0000off|r"), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffffffDrag:|r move this button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function ns.CreateMinimapButton()
    if button or not Minimap then return end
    button = CreateFrame("Button", "RemindMeForeverMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            ns.SetTestMode(not ns.IsTestMode())
            ns.Print("test mode " .. (ns.IsTestMode() and "on" or "off") .. ".")
            if GameTooltip:IsOwned(self) then ShowTooltip(self) end
        else
            ns.ToggleOptions()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    button:SetShown(not ns.db.minimap.hide)
end

function ns.SetMinimapShown(show)
    ns.db.minimap.hide = not show
    if button then button:SetShown(show) end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

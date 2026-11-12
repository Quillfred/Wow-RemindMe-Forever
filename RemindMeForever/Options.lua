-- RemindMe Forever: options window (open with /rmf or the minimap button).

local ADDON, ns = ...

local frame
local widgets = {}     -- { refresh = function() end } entries
local refreshing = false

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------
local function Header(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 20, y)
    fs:SetText(text)
    return y - 22
end

local function Checkbox(parent, y, label, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 24, y)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(label)
    cb:SetScript("OnClick", function(self)
        if not refreshing then set(self:GetChecked() and true or false) end
    end)
    table.insert(widgets, { refresh = function() cb:SetChecked(get()) end })
    return cb, y - 28
end

local SLIDER_BACKDROP = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

local function Slider(parent, y, label, minV, maxV, get, set)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 30, y)
    title:SetText(label)

    local s = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(200, 17)
    s:SetPoint("TOPLEFT", 30, y - 18)
    if s.SetBackdrop then s:SetBackdrop(SLIDER_BACKDROP) end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)

    local low = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, 0)
    low:SetText(minV)
    local high = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, 0)
    high:SetText(maxV)
    local value = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("LEFT", s, "RIGHT", 10, 0)

    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        value:SetText(v)
        if not refreshing and v ~= get() then set(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        if self:IsEnabled() then self:SetValue(self:GetValue() + delta) end
    end)

    s.SetActive = function(self, on)
        if on then self:Enable() else self:Disable() end
        local a = on and 1 or 0.4
        title:SetAlpha(a); value:SetAlpha(a); low:SetAlpha(a); high:SetAlpha(a); self:SetAlpha(a)
    end
    table.insert(widgets, { refresh = function() s:SetValue(get()); value:SetText(get()) end })
    return s, y - 50
end

local function Button(parent, y, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(180, 24)
    b:SetPoint("TOPLEFT", 28, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b, y - 32
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function Build()
    local db = ns.db
    frame = CreateFrame("Frame", "RemindMeForeverOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetWidth(340)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    table.insert(UISpecialFrames, "RemindMeForeverOptions") -- Esc closes it

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("RemindMe Forever")

    local y = -46

    -- General
    y = Header(frame, "General", y)
    local _
    _, y = Checkbox(frame, y, "Test mode (show all alert icons)",
        ns.IsTestMode, ns.SetTestMode)
    _, y = Checkbox(frame, y, "Unlock (drag the icon to move it)",
        ns.IsUnlocked, ns.SetUnlocked)
    _, y = Checkbox(frame, y, "Show minimap button",
        function() return not db.minimap.hide end,
        function(v) if ns.SetMinimapShown then ns.SetMinimapShown(v) end end)

    -- Icon size
    y = y - 8
    y = Header(frame, "Icon size", y)
    local matchCB
    matchCB, y = Checkbox(frame, y, "Match Cooldown Manager icon size",
        function() return db.matchCooldownManager end, ns.SetMatchCooldownManager)
    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", 54, y + 6)
    y = y - 12
    local sizeSlider
    sizeSlider, y = Slider(frame, y, "Size", 16, 200,
        function() return db.matchCooldownManager and ns.CurrentIconSize() or db.iconSize end,
        ns.SetIconSize)
    table.insert(widgets, { refresh = function()
        sizeSlider:SetActive(not db.matchCooldownManager)
        if not db.matchCooldownManager then
            status:SetText("")
        elseif ns.CooldownManagerFound() then
            status:SetText("Cooldown Manager found: " .. ns.CurrentIconSize())
        else
            status:SetText("Cooldown Manager not found, using " .. ns.CurrentIconSize())
        end
    end })
    _, y = Button(frame, y, "Reset position & size", function() ns.ResetLayout() end)

    -- One section per alert
    for _, alert in ipairs(ns.alerts) do
        if alert.options then
            y = y - 8
            y = Header(frame, alert.name, y)
            local s = db.alerts[alert.key]
            for _, opt in ipairs(alert.options) do
                local key = opt.key
                if opt.type == "toggle" then
                    _, y = Checkbox(frame, y, opt.label,
                        function() return s[key] end,
                        function(v) ns.SetAlertSetting(alert, key, v) end)
                elseif opt.type == "slider" then
                    _, y = Slider(frame, y, opt.label, opt.min, opt.max,
                        function() return s[key] end,
                        function(v) ns.SetAlertSetting(alert, key, v) end)
                end
            end
        end
    end

    frame:SetHeight(-y + 16)
    frame:SetScript("OnShow", ns.RefreshOptions)
    frame:Hide()
end

function ns.RefreshOptions()
    if not frame or not frame:IsShown() then return end
    refreshing = true
    for _, w in ipairs(widgets) do w.refresh() end
    refreshing = false
end

function ns.ToggleOptions()
    if not ns.db then return end
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

---------------------------------------------------------------------------
-- Entry in the game's AddOns options list, pointing at our window
---------------------------------------------------------------------------
function ns.RegisterSettingsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "RemindMe Forever"
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("RemindMe Forever")
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(200, 26)
    b:SetPoint("TOPLEFT", 16, -50)
    b:SetText("Open options window")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        if not (frame and frame:IsShown()) then ns.ToggleOptions() end
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- RemindMe Forever: shows an icon on screen when something needs your attention.
-- Core: saved settings, the icon display, event dispatch and slash commands.
-- Individual alerts live in Alerts.lua and register themselves via ns.RegisterAlert.

local ADDON, ns = ...

local PREFIX = "|cff8888ffRemindMe|r: "

local defaults = {
    point = { "CENTER", "CENTER", 0, 150 },
    iconSize = 64,
    sound = true,
    alerts = {}, -- per-alert settings, filled from each alert's own defaults
}

ns.alerts = {}       -- ordered list of registered alerts
ns.alertsByKey = {}

local db
local unlocked = false
local testUntil = 0

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end
ns.Print = Print

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

---------------------------------------------------------------------------
-- Spell helpers (work on both old GetSpellInfo and newer C_Spell APIs)
---------------------------------------------------------------------------
function ns.SpellNameAndIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, info.iconID end
    end
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end
end

-- Finds the given spell (any rank) on the pet action bar.
-- Returns slot index and the texture the game itself uses for that button.
function ns.FindPetActionSlot(spellIDs)
    if not UnitExists("pet") or not GetPetActionInfo then return nil end
    local ids = {}
    for _, id in ipairs(spellIDs) do ids[id] = true end
    local wantName = ns.SpellNameAndIcon(spellIDs[1])
    for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
        local r = { GetPetActionInfo(i) }
        local name = r[1]
        -- Classic returns (name, texture, isToken, ..., spellID); very old clients
        -- had (name, subtext, texture, ...). Pick whichever looks like a texture.
        local tex, spellID
        if type(r[2]) == "number" or (type(r[2]) == "string" and r[2]:find("[\\/]")) then
            tex, spellID = r[2], r[7]
        else
            tex, spellID = r[3], r[8]
        end
        if (spellID and ids[spellID]) or (name and name == wantName) then
            return i, tex
        end
    end
end

-- Short key text like the action bars show: CTRL-6 -> C6, SHIFT-BUTTON4 -> SM4.
function ns.ShortKey(key)
    if not key then return nil end
    key = key:upper()
    key = key:gsub("CTRL%-", "C"):gsub("SHIFT%-", "S"):gsub("ALT%-", "A"):gsub("META%-", "M")
    key = key:gsub("MOUSEWHEELUP", "MWU"):gsub("MOUSEWHEELDOWN", "MWD")
    key = key:gsub("MIDDLEMOUSE", "M3"):gsub("BUTTON", "M")
    key = key:gsub("NUMPADPLUS", "N+"):gsub("NUMPADMINUS", "N-"):gsub("NUMPAD", "N")
    key = key:gsub("SPACE", "Sp"):gsub("CAPSLOCK", "Caps")
    return key
end

-- Key bound to pet action bar slot i (Blizzard bars, plus Bartender / ElvUI pet bars).
function ns.PetSlotHotkey(slot)
    if not slot or not GetBindingKey then return nil end
    local key = GetBindingKey("BONUSACTIONBUTTON" .. slot)
        or GetBindingKey("CLICK BT4PetButton" .. slot .. ":LeftButton")
        or GetBindingKey("CLICK ElvUI_BarPetButton" .. slot .. ":LeftButton")
    return ns.ShortKey(key)
end

-- True if the current pet has the given spell (any of the listed rank IDs).
function ns.PetHasSpell(spellIDs)
    if not UnitExists("pet") then return false end
    if IsSpellKnown then
        for _, id in ipairs(spellIDs) do
            if IsSpellKnown(id, true) then return true end
        end
    end
    -- Fallback: look for the spell on the pet action bar.
    return ns.FindPetActionSlot(spellIDs) ~= nil
end

function ns.UnitHealthPercent(unit)
    local max = UnitHealthMax(unit)
    if not max or max <= 0 then return nil end
    return UnitHealth(unit) / max * 100
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "RemindMeForeverAnchor", UIParent)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", anchor.StartMoving)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.point = { point, relPoint, x, y }
end)

anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
anchor.bg:SetAllPoints()
anchor.bg:SetColorTexture(0, 0.6, 1, 0.3)
anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
anchor.label:SetText("RemindMe: drag me, then /rmf lock")

local function ApplyLayout()
    local size = db.iconSize
    anchor:SetSize(size, size)
    anchor:ClearAllPoints()
    local p = db.point
    anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    for _, alert in ipairs(ns.alerts) do
        if alert.icon then
            alert.icon:SetSize(size, size)
            alert.icon.hotkey:SetFont(STANDARD_TEXT_FONT, math.max(10, math.floor(size * 0.28)), "OUTLINE")
        end
    end
end

local function CreateIcon(alert)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false) -- never eats clicks
    f:Hide()

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -3, 3)
    f.border:SetPoint("BOTTOMRIGHT", 3, -3)
    f.border:SetColorTexture(1, 0.1, 0.1, 0.6)

    f.hotkey = f:CreateFontString(nil, "OVERLAY")
    f.hotkey:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -3)
    f.hotkey:SetFont(STANDARD_TEXT_FONT, math.max(10, math.floor(db.iconSize * 0.28)), "OUTLINE")
    f.hotkey:SetTextColor(0.9, 0.9, 0.9)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -4)
    f:SetSize(db.iconSize, db.iconSize)

    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.45)
    fade:SetDuration(0.4)
    f.pulse = ag

    alert.icon = f
    return f
end

local function PlayAlertSound()
    if not db.sound then return end
    local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING
    if kit then PlaySound(kit, "Master") end
end

-- Re-checks every alert and lays out the visible icons left-to-right.
local function Evaluate()
    if not db then return end
    local now = GetTime()
    local testing = unlocked or now < testUntil
    local shown = 0
    local size, gap = db.iconSize, 8

    for _, alert in ipairs(ns.alerts) do
        local settings = db.alerts[alert.key]
        local active, label = false, nil
        if testing then
            active, label = true, alert.name
        elseif settings.enabled and (not alert.class or alert.class == ns.playerClass) then
            active, label = alert.check(settings)
        end

        local icon = alert.icon or CreateIcon(alert)
        if active then
            local tex, hotkey
            if alert.display then tex, hotkey = alert.display(settings) end
            if not tex and alert.iconSpellID then
                local _
                _, tex = ns.SpellNameAndIcon(alert.iconSpellID)
            end
            icon.tex:SetTexture(tex or alert.iconTexture or 134400) -- 134400 = question mark
            icon.hotkey:SetText(hotkey or "")
            icon.text:SetText(label or "")
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", anchor, "LEFT", shown * (size + gap), 0)
            if not icon:IsShown() then
                icon:Show()
                icon.pulse:Play()
                if not testing then PlayAlertSound() end
            end
            shown = shown + 1
        elseif icon:IsShown() then
            icon.pulse:Stop()
            icon:Hide()
        end
    end
end
ns.Evaluate = Evaluate

local function SetUnlocked(state)
    unlocked = state
    anchor:EnableMouse(state)
    if state then anchor:Show() else anchor:Hide() end
    Evaluate()
end

---------------------------------------------------------------------------
-- Alert registration
---------------------------------------------------------------------------
-- alert = {
--   key = "uniqueKey", name = "Shown in /rmf list",
--   class = "WARLOCK" (optional),
--   iconSpellID = 7812 (or iconTexture = fileID/path),
--   events = { "UNIT_HEALTH", ... }, unitEvents = { pet = { "UNIT_HEALTH" } },
--   defaults = { enabled = true, ... },
--   check = function(settings) return isActive, labelText end,
--   display = function(settings) return texture, hotkeyText end (optional),
--   command = function(settings, args) ... end (optional, for /rmf <key> ...)
-- }
local eventFrame = CreateFrame("Frame")

local function SafeRegister(event, unit)
    if unit and eventFrame.RegisterUnitEvent then
        pcall(eventFrame.RegisterUnitEvent, eventFrame, event, unit)
    else
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
end

function ns.RegisterAlert(alert)
    table.insert(ns.alerts, alert)
    ns.alertsByKey[alert.key:lower()] = alert
    defaults.alerts[alert.key] = alert.defaults or { enabled = true }
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        RemindMeForeverDB = CopyDefaults(defaults, RemindMeForeverDB or {})
        db = RemindMeForeverDB
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ns.playerClass = select(2, UnitClass("player"))
        ApplyLayout()
        SetUnlocked(false)
        SafeRegister("PLAYER_ENTERING_WORLD")
        for _, alert in ipairs(ns.alerts) do
            if not alert.class or alert.class == ns.playerClass then
                for _, e in ipairs(alert.events or {}) do SafeRegister(e) end
                for unit, list in pairs(alert.unitEvents or {}) do
                    for _, e in ipairs(list) do SafeRegister(e, unit) end
                end
            end
        end
        Evaluate()
    else
        Evaluate()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Help()
    Print("commands (/rmf or /remindme):")
    Print("  unlock | lock  - move the icon position")
    Print("  test           - show every alert icon for 5 seconds")
    Print("  size <24-200>  - icon size")
    Print("  sound on|off   - play a sound when an icon appears")
    Print("  reset          - reset position and size")
    Print("  list           - list alerts and their settings")
    for _, alert in ipairs(ns.alerts) do
        if alert.help then Print("  " .. alert.help) end
    end
end

SLASH_REMINDMEFOREVER1 = "/rmf"
SLASH_REMINDMEFOREVER2 = "/remindme"
SlashCmdList.REMINDMEFOREVER = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "unlock" then
        SetUnlocked(true)
        Print("unlocked. Drag the blue box, then type /rmf lock.")
    elseif cmd == "lock" then
        SetUnlocked(false)
        Print("locked.")
    elseif cmd == "test" then
        testUntil = GetTime() + 5
        Evaluate()
        C_Timer.After(5.1, Evaluate)
    elseif cmd == "size" then
        local n = tonumber(rest)
        if n and n >= 24 and n <= 200 then
            db.iconSize = math.floor(n)
            ApplyLayout()
            Evaluate()
            Print("icon size " .. db.iconSize .. ".")
        else
            Print("usage: /rmf size <24-200>")
        end
    elseif cmd == "sound" then
        if rest == "on" or rest == "off" then
            db.sound = (rest == "on")
        else
            db.sound = not db.sound
        end
        Print("sound " .. (db.sound and "on" or "off") .. ".")
    elseif cmd == "reset" then
        db.point = { unpack(defaults.point) }
        db.iconSize = defaults.iconSize
        ApplyLayout()
        Evaluate()
        Print("position and size reset.")
    elseif cmd == "list" then
        for _, alert in ipairs(ns.alerts) do
            local s = db.alerts[alert.key]
            local extra = alert.describe and (" - " .. alert.describe(s)) or ""
            Print(("%s: %s%s"):format(alert.name, s.enabled and "|cff00ff00on|r" or "|cffff0000off|r", extra))
        end
    elseif ns.alertsByKey[cmd] and ns.alertsByKey[cmd].command then
        local alert = ns.alertsByKey[cmd]
        alert.command(db.alerts[alert.key], rest)
        Evaluate()
    else
        Help()
    end
end

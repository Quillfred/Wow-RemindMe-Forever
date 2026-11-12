-- RemindMe Forever: shows an icon on screen when something needs your attention.
-- Core: saved settings, the icon display, event dispatch and slash commands.
-- Individual alerts live in Alerts.lua and register themselves via ns.RegisterAlert.

local ADDON, ns = ...

local PREFIX = "|cff8888ffRemindMe|r: "

local defaults = {
    point = { "CENTER", "CENTER", 0, 150 },
    iconSize = 64,      -- used when not matching the Cooldown Manager
    matchCooldownManager = true,
    minimap = { hide = false, angle = 215 },
    alerts = {}, -- per-alert settings, filled from each alert's own defaults
}

ns.alerts = {}       -- ordered list of registered alerts
ns.alertsByKey = {}

local db
local unlocked = false
local testMode = false

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

---------------------------------------------------------------------------
-- Player action bars: find a spell (placed directly or via a macro) and
-- read the key bound to that button.
---------------------------------------------------------------------------
local MAX_ACTION_SLOT = 180

local function ActionMatches(slot, ids, wantName)
    if not HasAction(slot) then return false end
    local kind, id = GetActionInfo(slot)
    local spellID
    if kind == "spell" then
        spellID = id
    elseif kind == "macro" and GetMacroSpell then
        spellID = GetMacroSpell(id)
    end
    if not spellID then return false end
    if ids[spellID] then return true end
    return wantName ~= nil and ns.SpellNameAndIcon(spellID) == wantName
end

-- Binding commands that can trigger action slot `slot`: Blizzard bars
-- first, then Bartender4, ElvUI and Dominos.
local function ActionSlotBindings(slot)
    local list = {}
    local function add(cmd) list[#list + 1] = cmd end
    local n = (slot - 1) % 12 + 1
    if slot <= 12 then add("ACTIONBUTTON" .. slot)
    elseif slot <= 24 then -- page 2 of the main bar has no keys of its own
    elseif slot <= 36 then add("MULTIACTIONBAR3BUTTON" .. n)  -- right bar
    elseif slot <= 48 then add("MULTIACTIONBAR4BUTTON" .. n)  -- right bar 2
    elseif slot <= 60 then add("MULTIACTIONBAR2BUTTON" .. n)  -- bottom right
    elseif slot <= 72 then add("MULTIACTIONBAR1BUTTON" .. n)  -- bottom left
    elseif slot >= 145 and slot <= 156 then add("MULTIACTIONBAR5BUTTON" .. n)
    elseif slot >= 157 and slot <= 168 then add("MULTIACTIONBAR6BUTTON" .. n)
    elseif slot >= 169 and slot <= 180 then add("MULTIACTIONBAR7BUTTON" .. n)
    end
    add("CLICK BT4Button" .. slot .. ":Keybind")
    add("CLICK BT4Button" .. slot .. ":LeftButton")
    add("ELVUIBAR" .. math.ceil(slot / 12) .. "BUTTON" .. n)
    add("CLICK DominosActionButton" .. slot .. ":HOTKEY")
    return list
end

function ns.ActionSlotHotkey(slot)
    if not GetBindingKey then return nil end
    for _, cmd in ipairs(ActionSlotBindings(slot)) do
        local key = GetBindingKey(cmd)
        if key then return ns.ShortKey(key) end
    end
end

---------------------------------------------------------------------------
-- Finding the on-screen button for a spell, from any action bar addon
-- (Blizzard, Bartender4, ElvUI, Dominos, EllesmereUI, ...). Rather than
-- knowing every addon, we walk all visible buttons, work out what each one
-- casts, and read the keybind text the button itself displays.
---------------------------------------------------------------------------
local RANGE_DOT = RANGE_INDICATOR or "\226\151\143" -- the grey dot shown when unbound

local function ButtonHotkeyText(btn)
    local hk = btn.HotKey or btn.hotKey or btn.Hotkey
    if not hk then
        local name = btn:GetName()
        hk = name and _G[name .. "HotKey"]
    end
    if hk and hk.GetText and hk:IsShown() then
        local t = hk:GetText()
        if t and not ns.IsSecret(t) and t ~= "" and t ~= RANGE_DOT then return t end
    end
end

local function ButtonBindingKey(btn)
    if not GetBindingKey then return nil end
    local name = btn:GetName()
    if name then
        for _, suffix in ipairs({ ":LeftButton", ":Keybind", ":HOTKEY", "" }) do
            local key = GetBindingKey("CLICK " .. name .. suffix)
            if key then return ns.ShortKey(key) end
        end
    end
    local cmd = btn.commandName or btn.bindingAction or (btn.config and btn.config.keyBoundTarget)
    if type(cmd) == "string" then
        local key = GetBindingKey(cmd)
        if key then return ns.ShortKey(key) end
    end
end

-- What a button casts: "action", slot | "spell", spellID | "macro", id | "pet", index
local function ButtonAction(btn)
    -- LibActionButton (used by Bartender4, ElvUI and many UI suites)
    if btn._state_type and btn._state_action then
        return btn._state_type, btn._state_action
    end
    local name = btn:GetName()
    local petIndex = name and name:match("Pet.-Button(%d+)$")
    if petIndex then return "pet", tonumber(petIndex) end
    if type(btn.action) == "number" then return "action", btn.action end
    local ok, attr = pcall(btn.GetAttribute, btn, "action")
    if ok and type(attr) == "number" then return "action", attr end
end

local function ButtonTexture(btn)
    local icon = btn.icon or btn.Icon
    if not icon then
        local name = btn:GetName()
        icon = name and _G[name .. "Icon"]
    end
    return icon and icon.GetTexture and icon:GetTexture()
end

-- Calls fn(btn) for every visible button on screen; stops when fn returns true.
local function ForEachVisibleButton(fn)
    if not EnumerateFrames then return end
    local f = EnumerateFrames()
    while f do
        local ok, stop = pcall(function()
            local t = f:GetObjectType()
            if (t == "CheckButton" or t == "Button") and f:IsVisible() then
                return fn(f)
            end
        end)
        if ok and stop then return end
        f = EnumerateFrames(f)
    end
end

-- Texture and keybind for a spell. A visible button showing a keybind wins;
-- otherwise fall back to binding lookups by action slot and the pet bar.
-- Cached until bars or bindings change (see BUTTON_EVENTS below).
local buttonCache = {}
function ns.SpellButtonInfo(spellIDs)
    local cached = buttonCache[spellIDs]
    if cached and (cached.key or GetTime() < cached.retryAt) then
        return cached.tex, cached.key
    end

    local ids = {}
    for _, id in ipairs(spellIDs) do ids[id] = true end
    local wantName = ns.SpellNameAndIcon(spellIDs[1])
    local function isOurSpell(spellID)
        return spellID ~= nil and (ids[spellID] or (wantName and ns.SpellNameAndIcon(spellID) == wantName))
    end
    local petSlot, petTex = ns.FindPetActionSlot(spellIDs)
    local tex, key

    -- 1) Visible buttons from any bar addon.
    ForEachVisibleButton(function(btn)
        local kind, value = ButtonAction(btn)
        local match = false
        if kind == "action" then
            match = HasAction and ActionMatches(value, ids, wantName)
        elseif kind == "spell" then
            match = isOurSpell(value)
        elseif kind == "macro" and GetMacroSpell then
            match = isOurSpell(GetMacroSpell(value))
        elseif kind == "pet" then
            match = petSlot ~= nil and value == petSlot
        end
        if not match then return false end
        tex = tex or ButtonTexture(btn) or (kind == "pet" and petTex) or nil
        key = ButtonHotkeyText(btn) or ButtonBindingKey(btn)
            or (kind == "action" and ns.ActionSlotHotkey(value))
            or (kind == "pet" and ns.PetSlotHotkey(value)) or nil
        if key then
            tex = ButtonTexture(btn) or tex
            return true
        end
    end)

    -- 2) Action slots on bars that aren't visible (binding lookup only).
    if not key and GetActionInfo and HasAction then
        for slot = 1, MAX_ACTION_SLOT do
            if ActionMatches(slot, ids, wantName) then
                tex = tex or GetActionTexture(slot)
                key = ns.ActionSlotHotkey(slot)
                if key then break end
            end
        end
    end

    -- 3) The pet bar.
    if not key and petSlot then
        tex = tex or petTex
        key = ns.PetSlotHotkey(petSlot)
    end

    -- If nothing was found, bar addons may not have drawn their keybinds
    -- yet, so look again in a few seconds.
    buttonCache[spellIDs] = { tex = tex, key = key, retryAt = GetTime() + 5 }
    return tex, key
end

local BUTTON_EVENTS = {
    ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true, UPDATE_BINDINGS = true,
    PET_BAR_UPDATE = true, UNIT_PET = true, SPELLS_CHANGED = true, PLAYER_ENTERING_WORLD = true,
}

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

-- Secret values: in combat the game hides some numbers (like health) from addons.
-- Addons may not compare or do math on them, only hand them to widgets.
function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Health % (0-100) as a plain number, or nil if the game is hiding it right now.
function ns.UnitHealthPercent(unit)
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if ns.IsSecret(cur) or ns.IsSecret(max) then return nil end
    if not max or max <= 0 then return nil end
    return cur / max * 100
end

-- A curve that maps health fraction (0-1) to alpha: 1 at or below pct%, 0 above.
local thresholdCurves = {}
function ns.ThresholdAlphaCurve(pct)
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    local curve = thresholdCurves[pct]
    if not curve then
        curve = C_CurveUtil.CreateCurve()
        if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
            curve:SetType(Enum.LuaCurveType.Linear)
        end
        local x = pct / 100
        curve:AddPoint(0, 1)
        curve:AddPoint(x, 1)
        curve:AddPoint(x + 0.001, 0)
        curve:AddPoint(1, 0)
        thresholdCurves[pct] = curve
    end
    return curve
end

-- Secret-safe low-health check. Returns:
--   "plain", pct          when health is readable (pct may be nil if unknown)
--   "curve", alpha, text  when hidden: alpha (usually secret) is 1 below the threshold
--                          and 0 above, text is a secret "NN%" string or nil
function ns.LowHealthState(unit, threshold)
    local pct = ns.UnitHealthPercent(unit)
    if pct then return "plain", pct end
    if not UnitHealthPercent then return "plain", nil end
    local curve = ns.ThresholdAlphaCurve(threshold)
    if not curve then return "plain", nil end
    local ok, alpha = pcall(UnitHealthPercent, unit, false, curve)
    if not ok or alpha == nil then return "plain", nil end
    local text
    local scale = CurveConstants and CurveConstants.ScaleTo100
    if scale then
        local ok2, p = pcall(UnitHealthPercent, unit, false, scale)
        if ok2 and p ~= nil then
            local ok3, t = pcall(string.format, "%d%%", p)
            if ok3 then text = t end
        end
    end
    return "curve", alpha, text
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

-- Size of one Cooldown Manager icon, in UIParent units, or nil if there is none.
local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }
local function CooldownManagerIconSize()
    local parentScale = UIParent:GetEffectiveScale()
    for _, name in ipairs(VIEWERS) do
        local viewer = _G[name]
        if viewer and viewer.GetChildren then
            for _, child in ipairs({ viewer:GetChildren() }) do
                local w = child.Icon and child:GetWidth()
                if w and not ns.IsSecret(w) and w > 1 then
                    return math.floor(w * child:GetEffectiveScale() / parentScale + 0.5)
                end
            end
        end
    end
end

local currentSize = 64
local function IconSize()
    if db.matchCooldownManager then
        local s = CooldownManagerIconSize()
        if s then return s end
    end
    return db.iconSize
end

local function ApplyLayout()
    currentSize = IconSize()
    local size = currentSize
    anchor:SetSize(size, size)
    anchor:ClearAllPoints()
    local p = db.point
    anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    for _, alert in ipairs(ns.alerts) do
        if alert.icon then
            alert.icon:SetSize(size, size)
            alert.icon.inner.hotkey:SetFont(STANDARD_TEXT_FONT, math.max(10, math.floor(size * 0.28)), "OUTLINE")
        end
    end
end

local function CreateIcon(alert)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false) -- never eats clicks
    f:Hide()

    -- The outer frame's alpha is driven by the alert (it may be a secret value
    -- the game computes for us); the inner frame does the pulsing.
    local inner = CreateFrame("Frame", nil, f)
    inner:SetAllPoints()
    inner:EnableMouse(false)
    f.inner = inner
    local outer = f
    f = inner

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -3, 3)
    f.border:SetPoint("BOTTOMRIGHT", 3, -3)
    f.border:SetColorTexture(1, 0.1, 0.1, 0.6)

    f.hotkey = f:CreateFontString(nil, "OVERLAY")
    f.hotkey:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -3)
    f.hotkey:SetFont(STANDARD_TEXT_FONT, math.max(10, math.floor(currentSize * 0.28)), "OUTLINE")
    f.hotkey:SetTextColor(0.9, 0.9, 0.9)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -4)

    local ag = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.45)
    fade:SetDuration(0.4)
    f.pulse = ag

    outer:SetSize(currentSize, currentSize)
    outer.tex, outer.hotkey, outer.text, outer.pulse = f.tex, f.hotkey, f.text, f.pulse
    alert.icon = outer
    return outer
end

-- Re-checks every alert and lays out the visible icons left-to-right.
local function Evaluate()
    if not db then return end
    local now = GetTime()
    local testing = unlocked or testMode
    local shown = 0
    if IconSize() ~= currentSize then ApplyLayout() end
    local size = currentSize
    local gap = math.max(2, math.floor(size * 0.1 + 0.5))

    for _, alert in ipairs(ns.alerts) do
        local settings = db.alerts[alert.key]
        -- check() returns: active, label, alpha. alpha may be a secret value
        -- (game-hidden); the icon is then kept "armed" and the game decides
        -- whether it is visible.
        local active, label, alpha = false, nil, nil
        if testing then
            active, label = true, alert.name
        elseif settings.enabled and (not alert.class or alert.class == ns.playerClass) then
            active, label, alpha = alert.check(settings)
        end
        local secret = alpha ~= nil and ns.IsSecret(alpha)
        if active and alpha ~= nil and not secret and alpha <= 0 then active = false end

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
            if not pcall(icon.text.SetText, icon.text, label or "") then icon.text:SetText("") end
            if secret then
                if not pcall(icon.SetAlpha, icon, alpha) then icon:SetAlpha(0) end
            else
                icon:SetAlpha(1)
            end
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", anchor, "LEFT", shown * (size + gap), 0)
            if not icon:IsShown() then
                icon:Show()
                icon.pulse:Play()
            end
            shown = shown + 1
        else
            if icon:IsShown() then
                icon.pulse:Stop()
                icon:Hide()
            end
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
--   options = { { type = "toggle"|"slider", key = "settingKey", label = "...",
--                 min = 1, max = 99 }, ... } (optional, shown in the options window)
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
        db.sound = nil -- old setting, no longer used
        ns.db = db
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ns.playerClass = select(2, UnitClass("player"))
        ApplyLayout()
        SetUnlocked(false)
        for e in pairs(BUTTON_EVENTS) do SafeRegister(e) end
        for _, alert in ipairs(ns.alerts) do
            if not alert.class or alert.class == ns.playerClass then
                for _, e in ipairs(alert.events or {}) do SafeRegister(e) end
                for unit, list in pairs(alert.unitEvents or {}) do
                    for _, e in ipairs(list) do SafeRegister(e, unit) end
                end
            end
        end
        Evaluate()
        if ns.CreateMinimapButton then ns.CreateMinimapButton() end
        if ns.RegisterSettingsPanel then pcall(ns.RegisterSettingsPanel) end
    else
        if BUTTON_EVENTS[event] then
            wipe(buttonCache)
            if not self.recheckPending and C_Timer then
                self.recheckPending = true
                C_Timer.After(1, function()
                    self.recheckPending = false
                    wipe(buttonCache)
                    Evaluate()
                end)
            end
        end
        Evaluate()
    end
end)

---------------------------------------------------------------------------
-- Settings API (shared by slash commands and the options window)
---------------------------------------------------------------------------
local function Changed()
    Evaluate()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.IsUnlocked() return unlocked end
function ns.IsTestMode() return testMode end
function ns.CurrentIconSize() return currentSize end
function ns.CooldownManagerFound() return CooldownManagerIconSize() ~= nil end

function ns.SetUnlocked(state)
    SetUnlocked(state and true or false)
    Changed()
end

function ns.SetTestMode(state)
    testMode = state and true or false
    Changed()
end

function ns.SetMatchCooldownManager(state)
    db.matchCooldownManager = state and true or false
    ApplyLayout()
    Changed()
end

function ns.SetIconSize(n)
    db.iconSize = math.max(16, math.min(200, math.floor(n)))
    db.matchCooldownManager = false
    ApplyLayout()
    Changed()
end

function ns.SetAlertSetting(alert, key, value)
    db.alerts[alert.key][key] = value
    Changed()
end

function ns.ResetLayout()
    db.point = { unpack(defaults.point) }
    db.iconSize = defaults.iconSize
    db.matchCooldownManager = true
    ApplyLayout()
    Changed()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function OnOff(rest, current)
    rest = (rest or ""):lower()
    if rest == "on" then return true elseif rest == "off" then return false end
    return not current
end

local function Help()
    Print("commands (/rmf or /remindme):")
    Print("  (no command)   - open the options window")
    Print("  unlock | lock  - move the icon position")
    Print("  test [on|off]  - show every alert icon until turned off")
    Print("  size match     - same size as Cooldown Manager icons (default)")
    Print("  size <16-200>  - fixed icon size")
    Print("  minimap on|off - show or hide the minimap button")
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

    if cmd == "" or cmd == "options" or cmd == "config" then
        if ns.ToggleOptions then ns.ToggleOptions() else Help() end
    elseif cmd == "unlock" then
        ns.SetUnlocked(true)
        Print("unlocked. Drag the blue box, then type /rmf lock.")
    elseif cmd == "lock" then
        ns.SetUnlocked(false)
        Print("locked.")
    elseif cmd == "test" then
        ns.SetTestMode(OnOff(rest, testMode))
        Print("test mode " .. (testMode and "on" or "off") .. ".")
    elseif cmd == "size" then
        local n = tonumber(rest)
        if rest:lower() == "match" then
            ns.SetMatchCooldownManager(true)
            if ns.CooldownManagerFound() then
                Print("matching Cooldown Manager icon size (" .. currentSize .. ").")
            else
                Print("will match the Cooldown Manager once its icons exist; using " .. currentSize .. " for now.")
            end
        elseif n and n >= 16 and n <= 200 then
            ns.SetIconSize(n)
            Print("icon size " .. db.iconSize .. " (no longer matching Cooldown Manager).")
        else
            Print("usage: /rmf size <16-200> | match")
        end
    elseif cmd == "minimap" then
        local show = OnOff(rest, not db.minimap.hide)
        if ns.SetMinimapShown then ns.SetMinimapShown(show) end
        Print("minimap button " .. (show and "shown" or "hidden") .. ".")
    elseif cmd == "reset" then
        ns.ResetLayout()
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
        Changed()
    else
        Help()
    end
end

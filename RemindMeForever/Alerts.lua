-- RemindMe Forever: alert definitions. Add new alerts here with ns.RegisterAlert.

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Warlock: Voidwalker low HP -> Sacrifice
---------------------------------------------------------------------------
-- All ranks of the Voidwalker's Sacrifice (Classic).
local SACRIFICE_IDS = { 7812, 19438, 19440, 19441, 19442, 19443 }

-- NPC ID of the Warlock's summoned Voidwalker.
local VOIDWALKER_NPC_IDS = { [1860] = true }

-- True only when the current pet is the player's Voidwalker (not an Imp,
-- Felhunter, Succubus, enslaved demon, etc.).
local function PetIsVoidwalker()
    if not UnitExists("pet") then return false end
    local guid = UnitGUID("pet")
    if guid and not ns.IsSecret(guid) then
        local npcID = tonumber((select(6, strsplit("-", guid))))
        if npcID and VOIDWALKER_NPC_IDS[npcID] then return true end
    end
    local family = UnitCreatureFamily("pet")
    if family and not ns.IsSecret(family) and family == "Voidwalker" then return true end
    return false
end

ns.RegisterAlert({
    key = "sacrifice",
    name = "Voidwalker Sacrifice",
    class = "WARLOCK",
    iconSpellID = 7812,
    defaults = { enabled = true, threshold = 5 },
    events = { "UNIT_PET", "PET_BAR_UPDATE", "SPELLS_CHANGED" },
    unitEvents = { pet = { "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH" } },
    help = "sacrifice <1-99> | on | off - Voidwalker HP % that shows Sacrifice",
    options = {
        { type = "toggle", key = "enabled", label = "Show Sacrifice when my Voidwalker is low" },
        { type = "slider", key = "threshold", label = "Voidwalker HP %", min = 1, max = 99 },
    },

    check = function(s)
        -- Only for your summoned Voidwalker, and only once it has learned Sacrifice.
        if not PetIsVoidwalker() then return false end
        local dead = UnitIsDead("pet")
        if not ns.IsSecret(dead) and dead then return false end
        if not ns.PetHasSpell(SACRIFICE_IDS) then return false end
        local mode, value, text = ns.LowHealthState("pet", s.threshold)
        if mode == "curve" then
            -- In combat: the game hides pet HP, so let it drive the icon's alpha.
            return true, text, value
        end
        if value and value <= s.threshold then
            return true, ("%d%%"):format(math.floor(value + 0.5))
        end
        return false
    end,

    -- Use your own Sacrifice button (action bar or pet bar): same icon and its keybinding.
    display = function(s)
        return ns.SpellButtonInfo(SACRIFICE_IDS)
    end,

    describe = function(s)
        return ("shows at %d%% pet HP or less"):format(s.threshold)
    end,

    command = function(s, args)
        args = (args or ""):lower()
        local n = tonumber(args)
        if args == "on" or args == "off" then
            s.enabled = (args == "on")
            ns.Print("Sacrifice alert " .. args .. ".")
        elseif n and n >= 1 and n <= 99 then
            s.threshold = math.floor(n)
            ns.Print(("Sacrifice alert at %d%% Voidwalker HP."):format(s.threshold))
        else
            ns.Print("usage: /rmf sacrifice <1-99> | on | off")
        end
    end,
})

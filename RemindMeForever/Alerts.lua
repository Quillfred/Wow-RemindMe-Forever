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
    local family = UnitCreatureFamily and UnitCreatureFamily("pet")
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

---------------------------------------------------------------------------
-- Warlock: no pet summoned -> show the pet you want summoned
---------------------------------------------------------------------------
local SOUL_SHARD_ITEM = 6265

-- Summon spells. Felguard only exists on some clients (TBC, Season of Discovery).
local WARLOCK_PETS = {
    { value = "imp",       label = "Imp",       ids = { 688 } },
    { value = "voidwalker", label = "Voidwalker", ids = { 697 } },
    { value = "succubus",  label = "Succubus",  ids = { 712 } },
    { value = "felhunter", label = "Felhunter", ids = { 691 } },
    { value = "felguard",  label = "Felguard",  ids = { 30146, 427733 } },
}
local PET_BY_VALUE = {}
for _, pet in ipairs(WARLOCK_PETS) do PET_BY_VALUE[pet.value] = pet end

local function PetExistsInGame(pet)
    for _, id in ipairs(pet.ids) do
        if ns.SpellNameAndIcon(id) then return true end
    end
    return false
end

-- The chosen pet is saved per character, since each Warlock knows different pets.
-- nil   = never chosen: the Imp is picked automatically once it's learned.
-- false = the player unchecked everything: reminder off, no auto-pick.
local function GetChosenPet(s)
    s.chosen = s.chosen or {}
    local key = ns.CharacterKey()
    if s.chosen[key] == nil and ns.PlayerKnowsSpell(PET_BY_VALUE.imp.ids) then
        s.chosen[key] = "imp"
    end
    return s.chosen[key] or nil
end
local function SetChosenPet(s, value)
    s.chosen = s.chosen or {}
    s.chosen[ns.CharacterKey()] = value or false
end

-- Which pet to show right now: the Imp when out of Soul Shards (it's the only
-- one that doesn't need a shard), otherwise the checked pet if it's learned.
-- Returns nil if the right pet can't be summoned (e.g. Imp not learned).
local function PetToShow(s)
    local chosen = PET_BY_VALUE[GetChosenPet(s) or ""]
    if not chosen then return nil end
    local imp = PET_BY_VALUE.imp
    local impKnown = ns.PlayerKnowsSpell(imp.ids)
    -- Never suggest a pet that can't be summoned.
    if ns.GetItemCount(SOUL_SHARD_ITEM) == 0 then
        if impKnown then return imp, true end
        return nil
    end
    if ns.PlayerKnowsSpell(chosen.ids) then return chosen, false end
    if impKnown then return imp, false end
    return nil
end

local function HasLivePet()
    if not UnitExists("pet") then return false end
    local dead = UnitIsDead("pet")
    if ns.IsSecret(dead) then return true end
    return not dead
end

local petChoices = {}
for _, pet in ipairs(WARLOCK_PETS) do
    table.insert(petChoices, {
        value = pet.value,
        label = pet.label,
        exists = function() return PetExistsInGame(pet) end,
        available = function() return ns.PlayerKnowsSpell(pet.ids) end,
    })
end

ns.RegisterAlert({
    key = "missingPet",
    name = "Missing pet",
    class = "WARLOCK",
    iconSpellID = 688,
    defaults = { enabled = true },
    events = { "UNIT_PET", "SPELLS_CHANGED", "BAG_UPDATE", "BAG_UPDATE_DELAYED",
               "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
               "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_MOUNT_DISPLAY_CHANGED" },
    unitEvents = { player = { "UNIT_AURA" } },
    options = {
        { type = "toggle", key = "enabled", label = "Show my pet when none is summoned" },
        { type = "radio", label = "Pet to summon (the Imp is shown when you have no Soul Shards):",
          choices = petChoices, get = GetChosenPet, set = SetChosenPet },
    },

    check = function(s)
        if HasLivePet() then return false end
        -- Nothing to do while you can't summon anyway.
        if UnitIsDeadOrGhost("player") then return false end
        if (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player")) then return false end
        local pet, noShards = PetToShow(s)
        if not pet then return false end
        return true, noShards and (pet.label .. " (no shards)") or pet.label
    end,

    display = function(s)
        local pet = PetToShow(s) or PET_BY_VALUE.imp
        local tex, key = ns.SpellButtonInfo(pet.ids)
        if not tex then
            for _, id in ipairs(pet.ids) do
                local _, icon = ns.SpellNameAndIcon(id)
                if icon then tex = icon break end
            end
        end
        return tex, key
    end,

    describe = function(s)
        local pet = PET_BY_VALUE[GetChosenPet(s) or ""]
        return pet and ("summon " .. pet.label .. " (Imp when out of shards)") or "no pet chosen"
    end,
})

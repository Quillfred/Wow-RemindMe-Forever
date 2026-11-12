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
    testLabel = function(s) return s.threshold .. "%" end,
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
-- Automatic defaults until the player picks something themselves:
--   * once Summon Imp is learned, the Imp is checked;
--   * once Summon Voidwalker is learned, it switches to the Voidwalker (once).
-- After that, or as soon as the player changes the selection (including
-- unchecking everything, which turns the reminder off), it's all manual.
local function GetChosenPet(s)
    s.chosen = s.chosen or {}
    s.manual = s.manual or {}
    local key = ns.CharacterKey()
    local cur = s.chosen[key]
    if not s.manual[key] then
        if cur ~= nil and cur ~= "imp" then
            s.manual[key] = true -- chosen by hand in an earlier version
        elseif ns.PlayerKnowsSpell(PET_BY_VALUE.voidwalker.ids) then
            s.chosen[key] = "voidwalker"
            s.manual[key] = true
        elseif cur == nil and ns.PlayerKnowsSpell(PET_BY_VALUE.imp.ids) then
            s.chosen[key] = "imp"
        end
    end
    return s.chosen[key] or nil
end
local function SetChosenPet(s, value)
    s.chosen = s.chosen or {}
    s.manual = s.manual or {}
    local key = ns.CharacterKey()
    s.chosen[key] = value or false
    s.manual[key] = true
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
        -- The icon shows which pet; only explain when it's the Imp for lack of shards.
        return true, noShards and "0 shards" or nil
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

---------------------------------------------------------------------------
-- Warlock: out of Soul Shards in combat -> Drain Soul
---------------------------------------------------------------------------
-- All ranks of Drain Soul (Classic).
local DRAIN_SOUL_IDS = { 1120, 8288, 8289, 11675 }

-- Highest level that is grey (no experience) for a player of level p (Classic rules).
local function GreyLevel(p)
    if p <= 5 then return 0 end
    if p <= 39 then return p - math.floor(p / 10) - 5 end
    if p <= 59 then return p - math.floor(p / 5) - 1 end
    return p - 9 -- level 60: 51 and below is grey
end

-- Drain Soul only gives a shard if the target dies while drained AND the kill
-- would give experience or honor. Where the game hides a value (secret), we
-- assume it counts rather than miss a reminder.
local function TargetGivesShard()
    if not UnitExists("target") then return false end
    local function known(v) return not ns.IsSecret(v) end

    local dead = UnitIsDead("target")
    if known(dead) and dead then return false end
    local canAttack = UnitCanAttack("player", "target")
    if known(canAttack) and not canAttack then return false end
    -- Tagged by someone else: no experience for you.
    if UnitIsTapDenied then
        local denied = UnitIsTapDenied("target")
        if known(denied) and denied then return false end
    end

    local isPlayer = UnitIsPlayer("target")
    if known(isPlayer) and not isPlayer then
        -- Pets, guardians and totems give nothing.
        local controlled = UnitPlayerControlled("target")
        if known(controlled) and controlled then return false end
        local ctype = UnitCreatureType and UnitCreatureType("target")
        if ctype and known(ctype) and (ctype == "Critter" or ctype == "Totem") then return false end
    end
    -- Players count when the kill gives honor, which uses the same grey rule.

    local level, myLevel = UnitLevel("target"), UnitLevel("player")
    if not known(level) or not known(myLevel) then return true end
    if level < 0 then return true end -- "??" (far higher level / boss)
    return level > GreyLevel(myLevel)
end

ns.RegisterAlert({
    key = "drainSoul",
    testLabel = "0 shards",
    name = "Drain Soul (no shards)",
    class = "WARLOCK",
    iconSpellID = 1120,
    defaults = { enabled = true },
    events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE",
               "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "PLAYER_TARGET_CHANGED", "PLAYER_LEVEL_UP" },
    unitEvents = { target = { "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_LEVEL", "UNIT_FACTION" } },
    options = {
        { type = "toggle", key = "enabled", label = "Suggest Drain Soul in combat when I have no Soul Shards" },
    },

    check = function(s)
        if not InCombatLockdown() then return false end
        if ns.GetItemCount(SOUL_SHARD_ITEM) > 0 then return false end
        if not ns.PlayerKnowsSpell(DRAIN_SOUL_IDS) then return false end
        if not TargetGivesShard() then return false end
        return true, "0 shards"
    end,

    display = function(s)
        return ns.SpellButtonInfo(DRAIN_SOUL_IDS)
    end,

    describe = function(s)
        return "in combat with 0 Soul Shards, on a target that gives a shard"
    end,
})

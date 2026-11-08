local _, TickPulse = ...

TickPulse.Spells = TickPulse.Spells or {}
TickPulse.SpellsByName = TickPulse.SpellsByName or {}

-- Periodic spells tracked by TickPulse (WoW Forever, Classic-era 1-60 classes).
-- `id` is any rank of the spell; matching is done by spell name so every rank is covered.
-- `name` is an enUS fallback used only when the client cannot resolve `id`.
-- `interval` is the seconds between ticks. Ticks are on a fixed schedule from the moment
-- the aura was (re)applied, which is what lets TickPulse work without the combat log.
-- `self = true` means the aura lands on the caster even when a target is selected.
-- `travel = true` marks projectiles: the aura lands after the cast, so the cast time
-- cannot be used as the tick anchor while aura data is hidden in combat.
local seedSpells = {
    -- Warrior
    { class = "WARRIOR", id = 772, name = "Rend", type = "DOT", interval = 3.0 },
    { class = "WARRIOR", id = 12721, name = "Deep Wounds", type = "DOT", interval = 3.0 },

    -- Hunter
    { class = "HUNTER", id = 1978, name = "Serpent Sting", type = "DOT", interval = 3.0, travel = true },
    { class = "HUNTER", id = 3034, name = "Viper Sting", type = "DOT", interval = 2.0, travel = true },
    { class = "HUNTER", id = 13797, name = "Immolation Trap Effect", type = "DOT", interval = 3.0 },
    { class = "HUNTER", id = 13812, name = "Explosive Trap Effect", type = "DOT", interval = 2.0 },

    -- Rogue
    { class = "ROGUE", id = 703, name = "Garrote", type = "DOT", interval = 3.0 },
    { class = "ROGUE", id = 1943, name = "Rupture", type = "DOT", interval = 2.0 },
    { class = "ROGUE", id = 2818, name = "Deadly Poison", type = "DOT", interval = 3.0 },

    -- Priest
    { class = "PRIEST", id = 589, name = "Shadow Word: Pain", type = "DOT", interval = 3.0 },
    { class = "PRIEST", id = 2944, name = "Devouring Plague", type = "DOT", interval = 3.0 },
    { class = "PRIEST", id = 14914, name = "Holy Fire", type = "DOT", interval = 2.0 },
    { class = "PRIEST", id = 15407, name = "Mind Flay", type = "DOT", interval = 1.0 },
    { class = "PRIEST", id = 139, name = "Renew", type = "HOT", interval = 3.0 },

    -- Shaman
    { class = "SHAMAN", id = 8050, name = "Flame Shock", type = "DOT", interval = 3.0 },

    -- Mage
    { class = "MAGE", id = 133, name = "Fireball", type = "DOT", interval = 2.0, travel = true },
    { class = "MAGE", id = 11366, name = "Pyroblast", type = "DOT", interval = 3.0, travel = true },
    { class = "MAGE", id = 12654, name = "Ignite", type = "DOT", interval = 2.0 },
    { class = "MAGE", id = 12051, name = "Evocation", type = "HOT", interval = 2.0, self = true },

    -- Warlock
    { class = "WARLOCK", id = 172, name = "Corruption", type = "DOT", interval = 3.0 },
    { class = "WARLOCK", id = 980, name = "Curse of Agony", type = "DOT", interval = 2.0 },
    { class = "WARLOCK", id = 348, name = "Immolate", type = "DOT", interval = 3.0 },
    { class = "WARLOCK", id = 18265, name = "Siphon Life", type = "DOT", interval = 3.0 },
    { class = "WARLOCK", id = 689, name = "Drain Life", type = "DOT", interval = 1.0 },
    { class = "WARLOCK", id = 1120, name = "Drain Soul", type = "DOT", interval = 3.0 },
    { class = "WARLOCK", id = 5138, name = "Drain Mana", type = "DOT", interval = 1.0 },

    -- Druid
    { class = "DRUID", id = 740, name = "Tranquility", type = "HOT", interval = 2.0, self = true },
    { class = "DRUID", id = 774, name = "Rejuvenation", type = "HOT", interval = 3.0 },
    { class = "DRUID", id = 8936, name = "Regrowth", type = "HOT", interval = 3.0 },
    { class = "DRUID", id = 8921, name = "Moonfire", type = "DOT", interval = 3.0 },
    { class = "DRUID", id = 5570, name = "Insect Swarm", type = "DOT", interval = 2.0 },
    { class = "DRUID", id = 1079, name = "Rip", type = "DOT", interval = 2.0 },
    { class = "DRUID", id = 1822, name = "Rake", type = "DOT", interval = 3.0 },
    { class = "DRUID", id = 9007, name = "Pounce Bleed", type = "DOT", interval = 3.0 },

    -- First Aid: every bandage's channelled heal aura is named "First Aid",
    -- so one entry covers Linen through Heavy Runecloth.
    { class = "ALL", id = 746, name = "First Aid", type = "HOT", interval = 1.0 },

    -- Not in Classic 1-60. Kept in case Forever's new abilities reuse them;
    -- entries are ignored when the client has no such spell.
    { class = "PALADIN", id = 31803, type = "DOT", interval = 3.0 },  -- Holy Vengeance
    { class = "PRIEST", id = 34914, type = "DOT", interval = 3.0 },  -- Vampiric Touch
    { class = "WARLOCK", id = 30108, type = "DOT", interval = 3.0 },  -- Unstable Affliction
    { class = "DRUID", id = 33763, type = "HOT", interval = 1.0 },  -- Lifebloom
    { class = "DRUID", id = 33745, type = "DOT", interval = 3.0 },  -- Lacerate
}

-- Channelled spells that tick but leave no trackable aura on a monitored unit.
-- Used only for the cast bar tick marks; aura-tracked channels (Mind Flay,
-- Drain Life, Evocation, Tranquility, First Aid...) come from the list above.
local seedChannels = {
    { id = 5143, name = "Arcane Missiles", interval = 1.0 },
    { id = 10, name = "Blizzard", interval = 1.0 },
    { id = 5740, name = "Rain of Fire", interval = 2.0 },
    { id = 1949, name = "Hellfire", interval = 1.0 },
    { id = 755, name = "Health Funnel", interval = 1.0 },
    { id = 16914, name = "Hurricane", interval = 1.0 },
    { id = 1510, name = "Volley", interval = 1.0 },
}

local function resolveSpellName(spellId)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellId)
        if ok and name then
            return name
        end
    end

    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellId)
        if ok and name then
            return name
        end
    end

    return nil
end
TickPulse.ResolveSpellName = resolveSpellName

-- Seed spells followed by the user's custom spells (TickPulseDB.customSpells).
local function allEntries()
    local entries = {}
    for _, entry in ipairs(seedSpells) do
        entries[#entries + 1] = entry
    end

    local custom = TickPulseDB and TickPulseDB.customSpells
    if type(custom) == "table" then
        for id, spec in pairs(custom) do
            local spellId = tonumber(id)
            if spellId and type(spec) == "table" then
                entries[#entries + 1] = {
                    class = "CUSTOM",
                    id = spellId,
                    type = (spec.type == "HOT") and "HOT" or "DOT",
                    interval = tonumber(spec.interval) or 3.0,
                    self = spec.self or false,
                    custom = true,
                }
            end
        end
    end

    return entries
end

-- Builds the name index. Called at load and again at login, because spell
-- data may not be cached yet when the addon files are first executed, and
-- whenever per-spell settings change. Per-spell overrides
-- (TickPulseDB.spellOverrides, keyed by spell ID) disable a spell or change its
-- tick interval.
function TickPulse:BuildSpellIndex()
    self.SpellList = {}
    wipe(self.Spells)
    wipe(self.SpellsByName)

    local overrides = (TickPulseDB and type(TickPulseDB.spellOverrides) == "table") and TickPulseDB.spellOverrides or {}

    for _, entry in ipairs(allEntries()) do
        local override = overrides[entry.id] or {}
        local info = {
            seedId = entry.id,
            class = entry.class,
            custom = entry.custom or false,
            type = entry.type,
            defaultInterval = entry.interval,
            interval = tonumber(override.interval) or entry.interval,
            disabled = override.disabled == true,
            self = entry.self or false,
            travel = entry.travel or false,
        }

        local localized = resolveSpellName(entry.id)
        if localized then
            info.name = localized
            self.SpellsByName[localized] = info
        end

        -- Custom spells must resolve on this client; they have no fallback name.
        if entry.name and not self.SpellsByName[entry.name] then
            info.name = info.name or entry.name
            self.SpellsByName[entry.name] = info
        end

        self.Spells[entry.id] = info
        if info.name then
            self.SpellList[#self.SpellList + 1] = info
        end
    end

    self.ChannelsByName = {}
    for _, entry in ipairs(seedChannels) do
        local info = { seedId = entry.id, interval = entry.interval }
        info.name = resolveSpellName(entry.id) or entry.name
        self.ChannelsByName[info.name] = info
        self.ChannelsByName[entry.name] = self.ChannelsByName[entry.name] or info
    end
end

TickPulse:BuildSpellIndex()

TickPulse.Config = {
    enabled = true,
    showOnMainUI = true,
    showOnTargetFrame = true,
    showOnFocusFrame = true,
    showNumericTicker = false,
    showRotatingTicker = true,
    overlayOpacity = 0.65,
    trackExternalOnPlayer = true,
    showChannelTicks = true,
    showTicksLeft = false,
    clipWarning = true,
    tickFlash = false,
    tickSound = false,
    dotColor = { r = 1, g = 0.85, b = 0.1 },
    hotColor = { r = 0.3, g = 1, b = 0.45 },
    lastTickColorEnabled = false,
    lastTickColor = { r = 1, g = 0.5, b = 0 },
    monitoredUnits = {
        "target", -- DoTs on target + HoTs if friendly target
        "player", -- HoTs/DoTs on self (including other-player casts when enabled)
        "focus",  -- optional second tracked unit
    },
}

-- Config keys saved in TickPulseDB and exposed in the Settings panel.
TickPulse.PersistedKeys = {
    "showOnMainUI",
    "showOnTargetFrame",
    "showOnFocusFrame",
    "showNumericTicker",
    "showRotatingTicker",
    "overlayOpacity",
    "trackExternalOnPlayer",
    "showChannelTicks",
    "showTicksLeft",
    "clipWarning",
    "tickFlash",
    "tickSound",
    "dotColor",
    "hotColor",
    "lastTickColorEnabled",
    "lastTickColor",
}

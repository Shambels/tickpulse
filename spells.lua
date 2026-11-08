local addonName, TickPulse = ...

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
    { id = 772, name = "Rend", type = "DOT", interval = 3.0 },
    { id = 12721, name = "Deep Wounds", type = "DOT", interval = 3.0 },

    -- Hunter
    { id = 1978, name = "Serpent Sting", type = "DOT", interval = 3.0, travel = true },
    { id = 3034, name = "Viper Sting", type = "DOT", interval = 2.0, travel = true },
    { id = 13797, name = "Immolation Trap Effect", type = "DOT", interval = 3.0 },
    { id = 13812, name = "Explosive Trap Effect", type = "DOT", interval = 2.0 },

    -- Rogue
    { id = 703, name = "Garrote", type = "DOT", interval = 3.0 },
    { id = 1943, name = "Rupture", type = "DOT", interval = 2.0 },
    { id = 2818, name = "Deadly Poison", type = "DOT", interval = 3.0 },

    -- Priest
    { id = 589, name = "Shadow Word: Pain", type = "DOT", interval = 3.0 },
    { id = 2944, name = "Devouring Plague", type = "DOT", interval = 3.0 },
    { id = 14914, name = "Holy Fire", type = "DOT", interval = 2.0 },
    { id = 15407, name = "Mind Flay", type = "DOT", interval = 1.0 },
    { id = 139, name = "Renew", type = "HOT", interval = 3.0 },

    -- Shaman
    { id = 8050, name = "Flame Shock", type = "DOT", interval = 3.0 },

    -- Mage
    { id = 133, name = "Fireball", type = "DOT", interval = 2.0, travel = true },
    { id = 11366, name = "Pyroblast", type = "DOT", interval = 3.0, travel = true },
    { id = 12654, name = "Ignite", type = "DOT", interval = 2.0 },
    { id = 12051, name = "Evocation", type = "HOT", interval = 2.0, self = true },

    -- Warlock
    { id = 172, name = "Corruption", type = "DOT", interval = 3.0 },
    { id = 980, name = "Curse of Agony", type = "DOT", interval = 2.0 },
    { id = 348, name = "Immolate", type = "DOT", interval = 3.0 },
    { id = 18265, name = "Siphon Life", type = "DOT", interval = 3.0 },
    { id = 689, name = "Drain Life", type = "DOT", interval = 1.0 },
    { id = 1120, name = "Drain Soul", type = "DOT", interval = 3.0 },
    { id = 5138, name = "Drain Mana", type = "DOT", interval = 1.0 },

    -- Druid
    { id = 740, name = "Tranquility", type = "HOT", interval = 2.0, self = true },
    { id = 774, name = "Rejuvenation", type = "HOT", interval = 3.0 },
    { id = 8936, name = "Regrowth", type = "HOT", interval = 3.0 },
    { id = 8921, name = "Moonfire", type = "DOT", interval = 3.0 },
    { id = 5570, name = "Insect Swarm", type = "DOT", interval = 2.0 },
    { id = 1079, name = "Rip", type = "DOT", interval = 2.0 },
    { id = 1822, name = "Rake", type = "DOT", interval = 3.0 },
    { id = 9007, name = "Pounce Bleed", type = "DOT", interval = 3.0 },

    -- First Aid: every bandage's channelled heal aura is named "First Aid",
    -- so one entry covers Linen through Heavy Runecloth.
    { id = 746, name = "First Aid", type = "HOT", interval = 1.0 },

    -- Not in Classic 1-60. Kept in case Forever's new abilities reuse them;
    -- entries are ignored when the client has no such spell.
    { id = 31803, type = "DOT", interval = 3.0 },  -- Holy Vengeance
    { id = 34914, type = "DOT", interval = 3.0 },  -- Vampiric Touch
    { id = 30108, type = "DOT", interval = 3.0 },  -- Unstable Affliction
    { id = 33763, type = "HOT", interval = 1.0 },  -- Lifebloom
    { id = 33745, type = "DOT", interval = 3.0 },  -- Lacerate
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

-- Builds the name index. Called at load and again at login, because spell
-- data may not be cached yet when the addon files are first executed.
function TickPulse:BuildSpellIndex()
    self.SpellList = {}
    wipe(self.Spells)
    wipe(self.SpellsByName)

    for _, entry in ipairs(seedSpells) do
        local info = {
            seedId = entry.id,
            type = entry.type,
            interval = entry.interval,
            self = entry.self or false,
            travel = entry.travel or false,
        }

        local localized = resolveSpellName(entry.id)
        if localized then
            info.name = localized
            self.SpellsByName[localized] = info
        end

        if entry.name and not self.SpellsByName[entry.name] then
            info.name = info.name or entry.name
            self.SpellsByName[entry.name] = info
        end

        self.Spells[entry.id] = info
        if info.name then
            self.SpellList[#self.SpellList + 1] = info
        end
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
}

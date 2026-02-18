local addonName, TickPulse = ...

TickPulse.Spells = TickPulse.Spells or {}
TickPulse.SpellsByName = {}

local seedSpells = {
    -- Warrior
    { id = 772, type = "DOT", interval = 3.0 },    -- Rend
    { id = 12721, type = "DOT", interval = 3.0 },  -- Deep Wounds

    -- Paladin
    { id = 31803, type = "DOT", interval = 3.0 },  -- Holy Vengeance

    -- Hunter
    { id = 1978, type = "DOT", interval = 3.0 },   -- Serpent Sting
    { id = 13797, type = "DOT", interval = 3.0 },  -- Immolation Trap Effect
    { id = 13812, type = "DOT", interval = 2.0 },  -- Explosive Trap Effect

    -- Rogue
    { id = 703, type = "DOT", interval = 3.0 },    -- Garrote
    { id = 1943, type = "DOT", interval = 2.0 },   -- Rupture
    { id = 2818, type = "DOT", interval = 3.0 },   -- Deadly Poison

    -- Priest
    { id = 589, type = "DOT", interval = 3.0 },    -- Shadow Word: Pain
    { id = 2944, type = "DOT", interval = 3.0 },   -- Devouring Plague
    { id = 34914, type = "DOT", interval = 3.0 },  -- Vampiric Touch
    { id = 139, type = "HOT", interval = 3.0 },    -- Renew

    -- Shaman
    { id = 8050, type = "DOT", interval = 3.0 },   -- Flame Shock

    -- Mage
    { id = 12654, type = "DOT", interval = 2.0 },  -- Ignite

    -- Warlock
    { id = 172, type = "DOT", interval = 3.0 },    -- Corruption
    { id = 980, type = "DOT", interval = 3.0 },    -- Curse of Agony
    { id = 348, type = "DOT", interval = 3.0 },    -- Immolate (DoT component)
    { id = 30108, type = "DOT", interval = 3.0 },  -- Unstable Affliction
    { id = 18265, type = "DOT", interval = 3.0 },  -- Siphon Life

    -- Druid
    { id = 774, type = "HOT", interval = 3.0 },    -- Rejuvenation
    { id = 8936, type = "HOT", interval = 3.0 },   -- Regrowth
    { id = 33763, type = "HOT", interval = 1.0 },  -- Lifebloom
    { id = 8921, type = "DOT", interval = 3.0 },   -- Moonfire
    { id = 5570, type = "DOT", interval = 2.0 },   -- Insect Swarm
    { id = 1079, type = "DOT", interval = 2.0 },   -- Rip
    { id = 1822, type = "DOT", interval = 3.0 },   -- Rake
    { id = 33745, type = "DOT", interval = 3.0 },  -- Lacerate
}

for _, entry in ipairs(seedSpells) do
    local spellName = GetSpellInfo(entry.id)
    if spellName then
        TickPulse.SpellsByName[spellName] = {
            type = entry.type,
            interval = entry.interval,
        }
    end
end

TickPulse.Config = {
    enabled = true,
    trackExternalOnPlayer = true,
    monitoredUnits = {
        "target", -- DoTs on target + HoTs if friendly target
        "player", -- HoTs/DoTs on self (including other-player casts when enabled)
        "focus",  -- optional second tracked unit
    },
}

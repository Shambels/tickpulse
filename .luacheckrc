-- luacheck configuration for TickPulse (WoW Forever, Lua 5.1 environment).
std = "lua51"
max_line_length = false
codes = true

exclude_files = {
    ".luarocks",
    ".install",
}

ignore = {
    "212/self",  -- unused `self` in methods
}

-- Globals TickPulse writes.
globals = {
    "TickPulseDB",
    "TickPulseAPI",
    "SLASH_TICKPULSE1",
    "SLASH_TICKPULSE2",
    "SlashCmdList",
}

-- WoW API and FrameXML globals TickPulse reads.
read_globals = {
    -- Lua extensions provided by the client
    "wipe",
    "issecretvalue",
    "issecrettable",
    "strsplit",

    -- Namespaces
    "C_AddOns",
    "C_Secrets",
    "C_Spell",
    "C_Timer",
    "C_UnitAuras",

    -- Functions
    "CreateFrame",
    "GetBuildInfo",
    "GetSpellInfo",
    "GetTime",
    "InCombatLockdown",
    "PlaySound",
    "UnitCanAssist",
    "UnitChannelInfo",
    "UnitClass",
    "UnitExists",
    "UnitGUID",

    -- Frames, mixins and constants
    "UIParent",
    "ColorPickerFrame",
    "MinimalSliderWithSteppersMixin",
    "SOUNDKIT",
    "Settings",
    "CreateSettingsButtonInitializer",
    "CreateSettingsListSectionHeaderInitializer",

    -- Allow any _G lookup (frame names are resolved dynamically)
    "_G",
}

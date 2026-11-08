local _, TickPulse = ...

-- Support for unit frame addons.
--
-- TickPulse finds aura icons by searching known root frames for buttons with an
-- icon texture, then matching them by aura instance ID or icon. Other addons can
-- add their own aura containers through the public API below, and a few popular
-- unit frame addons are detected automatically.
--
-- Public API (global `TickPulseAPI`):
--
--   TickPulseAPI.RegisterAuraContainer(frame, unit, auraType)
--       frame    - a frame whose descendants are aura buttons, or a single aura button
--       unit     - "player", "target" or "focus"
--       auraType - "HELPFUL" (HoTs), "HARMFUL" (DoTs) or "ALL" (default)
--
--   TickPulseAPI.UnregisterAuraContainer(frame)
--
-- Aura buttons are recognised when they have an `Icon`/`icon` texture region.
-- Setting `button.auraInstanceID` lets TickPulse match them exactly.

TickPulse.extraRoots = {
    player = { HOT = {}, DOT = {} },
    target = { HOT = {}, DOT = {} },
    focus = { HOT = {}, DOT = {} },
}

local AURA_TYPES = {
    HELPFUL = { "HOT" },
    HARMFUL = { "DOT" },
    ALL = { "HOT", "DOT" },
}

function TickPulse:RegisterAuraContainer(frame, unit, auraType)
    local unitRoots = self.extraRoots[unit]
    local types = AURA_TYPES[auraType or "ALL"]
    if not frame or not unitRoots or not types then
        return false
    end

    for _, spellType in ipairs(types) do
        unitRoots[spellType][frame] = true
    end
    self:InvalidateButtonCache()
    return true
end

function TickPulse:UnregisterAuraContainer(frame)
    for _, unitRoots in pairs(self.extraRoots) do
        for _, roots in pairs(unitRoots) do
            roots[frame] = nil
        end
    end
    self:InvalidateButtonCache()
end

TickPulseAPI = {
    version = 1,
    RegisterAuraContainer = function(frame, unit, auraType)
        return TickPulse:RegisterAuraContainer(frame, unit, auraType)
    end,
    UnregisterAuraContainer = function(frame)
        TickPulse:UnregisterAuraContainer(frame)
    end,
}

--------------------------------------------------------------------------------
-- Built-in detection
--------------------------------------------------------------------------------

local UNIT_SUFFIXES = {
    player = { elv = "Player", suf = "player" },
    target = { elv = "Target", suf = "target" },
    focus = { elv = "Focus", suf = "focus" },
}

local detectors = {
    -- ElvUI unit frames (oUF): ElvUF_<Unit>.Buffs / .Debuffs, plus the player aura headers.
    ElvUI = function(self)
        local found = 0
        for unit, suffix in pairs(UNIT_SUFFIXES) do
            local unitFrame = _G["ElvUF_" .. suffix.elv]
            if unitFrame then
                if unitFrame.Buffs and self:RegisterAuraContainer(unitFrame.Buffs, unit, "HELPFUL") then
                    found = found + 1
                end
                if unitFrame.Debuffs and self:RegisterAuraContainer(unitFrame.Debuffs, unit, "HARMFUL") then
                    found = found + 1
                end
                if unitFrame.Auras and self:RegisterAuraContainer(unitFrame.Auras, unit, "ALL") then
                    found = found + 1
                end
            end
        end
        if _G.ElvUIPlayerBuffs and self:RegisterAuraContainer(_G.ElvUIPlayerBuffs, "player", "HELPFUL") then
            found = found + 1
        end
        if _G.ElvUIPlayerDebuffs and self:RegisterAuraContainer(_G.ElvUIPlayerDebuffs, "player", "HARMFUL") then
            found = found + 1
        end
        return found
    end,

    -- Shadowed Unit Frames: SUFUnit<unit> holds both buff and debuff rows.
    ShadowedUnitFrames = function(self)
        local found = 0
        for unit, suffix in pairs(UNIT_SUFFIXES) do
            local unitFrame = _G["SUFUnit" .. suffix.suf]
            if unitFrame and self:RegisterAuraContainer(unitFrame, unit, "ALL") then
                found = found + 1
            end
        end
        return found
    end,
}

local function isAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    return false
end

function TickPulse:DetectUnitFrameAddons(announce)
    local summary = {}
    for addon, detect in pairs(detectors) do
        if isAddOnLoaded(addon) then
            local count = detect(self)
            if count > 0 then
                summary[#summary + 1] = string.format("%s (%d)", addon, count)
            end
        end
    end

    if announce then
        if #summary > 0 then
            print("TickPulse: attached to " .. table.concat(summary, ", ") .. ".")
        else
            print("TickPulse: no supported unit frame addon detected (ElvUI, Shadowed Unit Frames). Others can use TickPulseAPI.RegisterAuraContainer.")
        end
    end
end

-- Unit frame addons build their frames during or shortly after login.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    C_Timer.After(2, function() TickPulse:DetectUnitFrameAddons(false) end)
    C_Timer.After(6, function() TickPulse:DetectUnitFrameAddons(false) end)
end)

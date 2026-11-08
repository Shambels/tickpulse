local _, TickPulse = ...

-- Per-spell settings and custom spells.
--
-- Saved in TickPulseDB:
--   spellOverrides[spellID] = { disabled = true|nil, interval = seconds|nil }
--   customSpells[spellID]   = { type = "DOT"|"HOT", interval = seconds, self = bool }
--
-- Commands (see /tpulse help):
--   /tpulse spells                          list your class's spells and their state
--   /tpulse spell <id|name> on|off          enable or disable a spell
--   /tpulse interval <id|name> <sec|reset>  override a spell's tick interval
--   /tpulse add <id> <sec> [dot|hot] [self] track a spell that isn't in the list
--   /tpulse remove <id>                     forget a custom spell

local function db()
    TickPulseDB = TickPulseDB or {}
    TickPulseDB.spellOverrides = TickPulseDB.spellOverrides or {}
    TickPulseDB.customSpells = TickPulseDB.customSpells or {}
    return TickPulseDB
end

local function playerClass()
    local _, classFile = UnitClass("player")
    return classFile
end

-- Spells shown to this character: own class, shared (First Aid) and custom.
function TickPulse:GetRelevantSpells()
    local class = playerClass()
    local list = {}
    for _, info in ipairs(self.SpellList or {}) do
        if info.class == class or info.class == "ALL" or info.custom then
            list[#list + 1] = info
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Rebuilds the spell index and re-applies it to running trackers.
function TickPulse:RefreshSpells()
    self:BuildSpellIndex()

    for key, tracked in pairs(self.active) do
        if not tracked.isTest then
            local info = self.SpellsByName[tracked.name]
            if not info or info.disabled then
                self:RemoveTracker(key)
            else
                tracked.interval = info.interval
                tracked.spellType = info.type
            end
        end
    end

    self:ScanAllUnits()
    self:UpdateLayout()
end

-- Accepts a spell ID or a (case-insensitive) spell name from the list.
function TickPulse:FindSpellByRef(ref)
    local id = tonumber(ref)
    if id then
        local info = self.Spells[id]
        if info then
            return info, info.seedId or id
        end
        -- Another rank of a listed spell: settings are stored on the listed ID.
        local name = self.ResolveSpellName(id)
        info = name and self.SpellsByName[name]
        if info then
            return info, info.seedId
        end
        return nil, id
    end

    ref = string.lower(ref or "")
    for _, info in ipairs(self.SpellList or {}) do
        if string.lower(info.name) == ref then
            return info, info.seedId
        end
    end
    return nil, nil
end

function TickPulse:SetSpellEnabled(spellId, enabled)
    local overrides = db().spellOverrides
    local override = overrides[spellId] or {}
    override.disabled = (not enabled) or nil
    overrides[spellId] = next(override) and override or nil
    self:RefreshSpells()
end

function TickPulse:SetSpellInterval(spellId, interval)
    local overrides = db().spellOverrides
    local override = overrides[spellId] or {}
    override.interval = interval
    overrides[spellId] = next(override) and override or nil
    self:RefreshSpells()
end

local function describe(info)
    local interval = string.format("every %.1fs", info.interval)
    if info.defaultInterval and info.interval ~= info.defaultInterval then
        interval = interval .. string.format(" (default %.1fs)", info.defaultInterval)
    end
    return string.format("%s [%d] %s %s%s%s", info.name, info.seedId, info.type, interval,
        info.disabled and " | OFF" or "", info.custom and " | custom" or "")
end

-- Handles spell-related slash commands. Returns true when `cmd` was one of them.
function TickPulse:HandleSpellCommand(cmd, arg)
    if cmd == "spells" then
        print("TickPulse spells for your class:")
        for _, info in ipairs(self:GetRelevantSpells()) do
            print("  " .. describe(info))
        end
        return true
    end

    if cmd == "spell" then
        local ref, state = arg:match("^(.-)%s+(%S+)$")
        local info, spellId = self:FindSpellByRef(ref)
        if not info or (state ~= "on" and state ~= "off") then
            print("TickPulse usage: /tpulse spell <spellID|name> on|off")
            return true
        end
        self:SetSpellEnabled(spellId, state == "on")
        print("TickPulse: " .. describe(self.Spells[spellId] or info))
        return true
    end

    if cmd == "interval" then
        local ref, value = arg:match("^(.-)%s+(%S+)$")
        local info, spellId = self:FindSpellByRef(ref)
        local seconds = tonumber(value)
        if not info or not (value == "reset" or (seconds and seconds >= 0.2 and seconds <= 30)) then
            print("TickPulse usage: /tpulse interval <spellID|name> <0.2-30 seconds|reset>")
            return true
        end
        self:SetSpellInterval(spellId, seconds)
        print("TickPulse: " .. describe(self.Spells[spellId] or info))
        return true
    end

    if cmd == "add" then
        local id, seconds, rest = arg:match("^(%d+)%s+([%d%.]+)%s*(.-)$")
        id, seconds = tonumber(id), tonumber(seconds)
        local name = id and self.ResolveSpellName(id)
        if not id or not seconds or seconds < 0.2 or seconds > 30 then
            print("TickPulse usage: /tpulse add <spellID> <seconds> [dot|hot] [self]")
            return true
        end
        if not name then
            print("TickPulse: spell " .. id .. " doesn't exist on this client.")
            return true
        end

        db().customSpells[id] = {
            type = rest:find("hot") and "HOT" or "DOT",
            interval = seconds,
            self = rest:find("self") and true or false,
        }
        self:RefreshSpells()
        print("TickPulse: added " .. describe(self.Spells[id]) .. ". It appears in Settings after /reload.")
        return true
    end

    if cmd == "remove" then
        local id = tonumber(arg)
        if not id or not db().customSpells[id] then
            print("TickPulse usage: /tpulse remove <spellID of a custom spell> (use /tpulse spell <id> off for built-in spells)")
            return true
        end
        db().customSpells[id] = nil
        db().spellOverrides[id] = nil
        self:RefreshSpells()
        print("TickPulse: removed custom spell " .. id .. ".")
        return true
    end

    return false
end

-- "Spells" page under TickPulse in the Settings panel.
function TickPulse:CreateSpellSettings(category)
    if not (Settings.RegisterVerticalLayoutSubcategory and Settings.RegisterProxySetting) then
        return
    end

    local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(category, "Spells")
    local varTypes = Settings.VarType or {}

    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Tracked spells for your class"))
    end

    for _, info in ipairs(self:GetRelevantSpells()) do
        local spellId = info.seedId
        local label = string.format("%s (%s, every %.1fs)", info.name, info.type, info.interval)
        local setting = Settings.RegisterProxySetting(subcategory, "TICKPULSE_SPELL_" .. spellId,
            varTypes.Boolean or "boolean", label, true,
            function()
                local current = self.Spells[spellId]
                return not (current and current.disabled)
            end,
            function(value) self:SetSpellEnabled(spellId, value and true or false) end)
        Settings.CreateCheckbox(subcategory, setting,
            "Track this spell. Change its tick interval with /tpulse interval " .. spellId .. " <seconds>.")
    end

    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(
            "More spells: /tpulse add <spellID> <seconds> [dot|hot] [self]"))
    end
end

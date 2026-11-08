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

    if self.spellTablePage and self.spellTablePage:IsShown() then
        self:RefreshSpellTable()
    end
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
        print("TickPulse: added " .. describe(self.Spells[id]) .. ".")
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

--------------------------------------------------------------------------------
-- "Spells" page: a table with Name | Category | Timer | Enabled columns
--------------------------------------------------------------------------------

local ROW_HEIGHT = 24
local COLUMNS = {
    { key = "name", title = "Name", x = 8, width = 250 },
    { key = "category", title = "Category", x = 266, width = 90 },
    { key = "timer", title = "Timer", x = 364, width = 110 },
    { key = "enabled", title = "Enabled", x = 482, width = 70 },
}
local CATEGORY_COLORS = {
    DOT = { 1, 0.45, 0.35 },
    HOT = { 0.4, 1, 0.5 },
}

local function addColumnText(parent, column, template)
    local text = parent:CreateFontString(nil, "ARTWORK", template)
    text:SetPoint("LEFT", parent, "LEFT", column.x, 0)
    text:SetWidth(column.width)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function createRow(content, index)
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

    -- Zebra striping keeps long lists readable.
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.04)
    end

    row.name = addColumnText(row, COLUMNS[1], "GameFontHighlight")
    row.category = addColumnText(row, COLUMNS[2], "GameFontHighlight")
    row.timer = addColumnText(row, COLUMNS[3], "GameFontHighlight")

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("LEFT", row, "LEFT", COLUMNS[4].x + 8, 0)
    row.check = check

    -- Hovering the row explains the timer and how to change it.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local info = self.info
        if not info then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(info.name)
        GameTooltip:AddLine(string.format("Spell ID %d", info.seedId), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(string.format("Ticks every %.1f s", info.interval), 1, 1, 1)
        if info.defaultInterval and info.interval ~= info.defaultInterval then
            GameTooltip:AddLine(string.format("Default %.1f s (/tpulse interval %d reset)", info.defaultInterval, info.seedId), 1, 0.82, 0)
        end
        GameTooltip:AddLine(string.format("Change it with /tpulse interval %d <seconds>", info.seedId), 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

function TickPulse:RefreshSpellTable()
    local page = self.spellTablePage
    if not page then
        return
    end

    local spells = self:GetRelevantSpells()
    local content = page.content

    for index, info in ipairs(spells) do
        local row = page.rows[index] or createRow(content, index)
        page.rows[index] = row
        row.info = info

        local color = CATEGORY_COLORS[info.type] or { 1, 1, 1 }
        row.name:SetText(info.name .. (info.custom and " |cff999999(custom)|r" or ""))
        row.category:SetText(info.type == "HOT" and "HoT" or "DoT")
        row.category:SetTextColor(color[1], color[2], color[3])

        local timer = string.format("%.1f s", info.interval)
        if info.defaultInterval and info.interval ~= info.defaultInterval then
            row.timer:SetText(timer .. " |cff999999*|r")
            row.timer:SetTextColor(1, 0.82, 0)
        else
            row.timer:SetText(timer)
            row.timer:SetTextColor(1, 1, 1)
        end

        local spellId = info.seedId
        row.check:SetChecked(not info.disabled)
        row.check:SetScript("OnClick", function(button)
            self:SetSpellEnabled(spellId, button:GetChecked() and true or false)
        end)

        local alpha = info.disabled and 0.5 or 1
        row.name:SetAlpha(alpha)
        row.category:SetAlpha(alpha)
        row.timer:SetAlpha(alpha)
        row:Show()
    end

    for index = #spells + 1, #page.rows do
        page.rows[index]:Hide()
        page.rows[index].info = nil
    end

    content:SetHeight(math.max(1, #spells * ROW_HEIGHT))
    page.empty:SetShown(#spells == 0)
end

function TickPulse:CreateSpellSettings(category)
    if not Settings.RegisterCanvasLayoutSubcategory then
        return
    end

    local page = CreateFrame("Frame", "TickPulseSpellSettingsPage")
    page.rows = {}

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
    title:SetText("Spells")

    local subtitle = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText("Tracked spells for your class. Untick a spell to stop tracking it.")

    -- Column headers
    local header = CreateFrame("Frame", nil, page)
    header:SetHeight(20)
    header:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -8, -14)
    header:SetPoint("RIGHT", page, "RIGHT", -36, 0)
    for _, column in ipairs(COLUMNS) do
        addColumnText(header, column, "GameFontNormal"):SetText(column.title)
    end

    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.2)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)

    local footer = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 16, 14)
    footer:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    footer:SetJustifyH("LEFT")
    footer:SetText("Change a timer: /tpulse interval <name> <seconds>   Add a spell: /tpulse add <spellID> <seconds> [dot|hot] [self]")

    -- Scrollable rows
    local template = (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("ScrollFrameTemplate"))
        and "ScrollFrameTemplate" or "UIPanelScrollFrameTemplate"
    local scroll = CreateFrame("ScrollFrame", nil, page, template)
    scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -36, 36)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(COLUMNS[4].x + COLUMNS[4].width, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
    end)
    page.content = content

    local empty = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
    empty:SetText("No tracked spells for your class yet. Add one with /tpulse add.")
    page.empty = empty

    -- Rebuild on show so custom spells and timer changes appear without /reload.
    page:SetScript("OnShow", function() self:RefreshSpellTable() end)

    self.spellTablePage = page
    Settings.RegisterCanvasLayoutSubcategory(category, page, "Spells")
end

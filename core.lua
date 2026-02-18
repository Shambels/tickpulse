local addonName, TickPulse = ...

TickPulse.active = TickPulse.active or {}
TickPulse.pool = TickPulse.pool or {}

local frame = CreateFrame("Frame")
TickPulse.frame = frame

local function now()
    return GetTime()
end

local function makeKey(destGUID, spellId, sourceGUID)
    return tostring(destGUID) .. ":" .. tostring(spellId) .. ":" .. tostring(sourceGUID or "unknown")
end

local function resolveSourceGUID(sourceUnit)
    if sourceUnit and UnitExists(sourceUnit) then
        return UnitGUID(sourceUnit)
    end
    return nil
end

function TickPulse:GetSpellInfo(spellId, spellName)
    local info = self.Spells[spellId]
    if info then
        return info
    end

    if not spellName then
        return nil
    end

    local byName = self.SpellsByName and self.SpellsByName[spellName]
    if byName then
        self.Spells[spellId] = byName
        return byName
    end

    return nil
end

function TickPulse:AcquireIcon()
    if #self.pool > 0 then
        local f = table.remove(self.pool)
        f:Show()
        return f
    end

    local iconFrame = CreateFrame("Frame", nil, self.anchor)
    iconFrame:SetSize(self.Config.iconSize, self.Config.iconSize)

    iconFrame.icon = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconFrame.icon:SetAllPoints()

    iconFrame.border = iconFrame:CreateTexture(nil, "OVERLAY")
    iconFrame.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    iconFrame.border:SetAllPoints()

    iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    iconFrame.cooldown:SetAllPoints()
    iconFrame.cooldown:SetDrawBling(false)
    iconFrame.cooldown:SetDrawEdge(true)
    iconFrame.cooldown:SetReverse(true)
    iconFrame.cooldown:SetSwipeColor(1, 0.85, 0.1, 0.65)

    iconFrame.label = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconFrame.label:SetPoint("BOTTOM", iconFrame, "TOP", 0, 2)

    return iconFrame
end

function TickPulse:ReleaseIcon(iconFrame)
    iconFrame:Hide()
    iconFrame:ClearAllPoints()
    iconFrame.spellKey = nil
    iconFrame.unit = nil
    iconFrame.label:SetText("")
    table.insert(self.pool, iconFrame)
end

function TickPulse:CreateOrRefreshTracker(unit, unitGUID, spellId, auraData, sourceGUID)
    local spellInfo = self.Spells[spellId]
    if not spellInfo then
        return
    end

    local key = makeKey(unitGUID, spellId, sourceGUID)
    local tracked = self.active[key]
    local t = now()

    if not tracked then
        tracked = {
            key = key,
            unit = unit,
            destGUID = unitGUID,
            spellId = spellId,
            sourceGUID = sourceGUID,
            spellType = spellInfo.type,
            interval = spellInfo.interval,
            cycleStart = t,
            nextTick = t + spellInfo.interval,
            lastTick = nil,
            learned = false,
            frame = nil,
        }
        self.active[key] = tracked
    else
        tracked.unit = unit
        tracked.sourceGUID = sourceGUID
    end

    tracked.name = auraData.name
    tracked.icon = auraData.icon
    tracked.duration = auraData.duration or 0
    tracked.expirationTime = auraData.expirationTime or 0

    if tracked.duration and tracked.duration > 0 and tracked.expirationTime and tracked.expirationTime > 0 then
        local remaining = tracked.expirationTime - t
        if remaining <= 0 then
            self.active[key] = nil
            return
        end
    end
end

function TickPulse:RemoveTracker(key)
    local tracked = self.active[key]
    if not tracked then
        return
    end

    if tracked.frame then
        self:ReleaseIcon(tracked.frame)
        tracked.frame = nil
    end

    self.active[key] = nil
end

function TickPulse:ScanUnit(unit)
    if not UnitExists(unit) then
        -- Remove stale trackers for this unit.
        for key, tracked in pairs(self.active) do
            if tracked.unit == unit then
                self:RemoveTracker(key)
            end
        end
        return
    end

    local unitGUID = UnitGUID(unit)
    if not unitGUID then
        return
    end

    local seen = {}

    local function scanFilter(filter, expectedType)
        for i = 1, 40 do
            local name, icon, count, debuffType, duration, expirationTime, source, isStealable,
                nameplateShowPersonal, auraSpellId = UnitAura(unit, i, filter)

            if not name then
                break
            end

            local spellInfo = TickPulse:GetSpellInfo(auraSpellId, name)
            if spellInfo and spellInfo.type == expectedType then
                local sourceGUID = resolveSourceGUID(source)
                if not sourceGUID and unit ~= "player" then
                    sourceGUID = UnitGUID("player")
                end

                local key = makeKey(unitGUID, auraSpellId, sourceGUID)
                seen[key] = true

                TickPulse:CreateOrRefreshTracker(unit, unitGUID, auraSpellId, {
                    name = name,
                    icon = icon,
                    duration = duration,
                    expirationTime = expirationTime,
                    source = source,
                }, sourceGUID)
            end
        end
    end

    if unit == "player" and self.Config.trackExternalOnPlayer then
        scanFilter("HARMFUL", "DOT")
        scanFilter("HELPFUL", "HOT")
    else
        scanFilter("HARMFUL|PLAYER", "DOT")
        scanFilter("HELPFUL|PLAYER", "HOT")
    end

    for key, tracked in pairs(self.active) do
        if tracked.unit == unit and not seen[key] then
            self:RemoveTracker(key)
        end
    end
end

function TickPulse:ScanAllUnits()
    for _, unit in ipairs(self.Config.monitoredUnits) do
        self:ScanUnit(unit)
    end
end

function TickPulse:OnPeriodicTick(destGUID, spellId, sourceGUID)
    local key = makeKey(destGUID, spellId, sourceGUID)
    local tracked = self.active[key]
    if not tracked then
        -- Fallback: allow unknown-source scan entries to resolve from combat-log source.
        for _, candidate in pairs(self.active) do
            if candidate.destGUID == destGUID and candidate.spellId == spellId and (candidate.sourceGUID == sourceGUID or candidate.sourceGUID == nil) then
                tracked = candidate
                break
            end
        end
        if not tracked then
            return
        end
    end

    local t = now()

    if tracked.lastTick then
        local delta = t - tracked.lastTick
        if delta > 0.5 and delta < 10 then
            tracked.interval = delta
            tracked.learned = true
        end
    end

    tracked.lastTick = t
    tracked.cycleStart = t
    tracked.nextTick = t + tracked.interval

    if tracked.frame then
        tracked.frame.cooldown:SetCooldown(tracked.cycleStart, tracked.interval)
    end
end

function TickPulse:UpdateLayout()
    local index = 0

    for _, tracked in pairs(self.active) do
        local t = now()

        if tracked.expirationTime and tracked.expirationTime > 0 and tracked.expirationTime <= t then
            self:RemoveTracker(tracked.key)
        else
            if not tracked.frame then
                tracked.frame = self:AcquireIcon()
            end

            local f = tracked.frame
            f.spellKey = tracked.key
            f.unit = tracked.unit
            f.icon:SetTexture(tracked.icon)
            f.label:SetText(tracked.spellType)

            if tracked.interval and tracked.interval > 0 then
                f.cooldown:SetCooldown(tracked.cycleStart, tracked.interval)
            end

            local row = math.floor(index / self.Config.perRow)
            local col = index % self.Config.perRow
            local x = col * (self.Config.iconSize + self.Config.spacing)
            local y = -row * (self.Config.iconSize + self.Config.spacing + 10)

            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", x, y)
            f:Show()

            index = index + 1
        end
    end

    -- Hide unused pooled icons just in case.
    for _, iconFrame in ipairs(self.pool) do
        iconFrame:Hide()
    end
end

function TickPulse:OnCombatLogEvent()
    local _, eventName, _, sourceGUID, _, sourceFlags, _, destGUID, _, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()

    local spellInfo = self:GetSpellInfo(spellId, spellName)
    if not spellInfo then
        return
    end

    local playerGUID = UnitGUID("player")
    local sourceIsPlayer = sourceGUID == playerGUID
    local destIsPlayer = destGUID == playerGUID
    local sourceIsOtherPlayer = sourceGUID and sourceGUID ~= playerGUID and sourceFlags and bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0

    if not sourceIsPlayer and not (self.Config.trackExternalOnPlayer and destIsPlayer and sourceIsOtherPlayer) then
        return
    end

    if eventName == "SPELL_PERIODIC_DAMAGE" and spellInfo.type == "DOT" then
        self:OnPeriodicTick(destGUID, spellId, sourceGUID)
    elseif eventName == "SPELL_PERIODIC_HEAL" and spellInfo.type == "HOT" then
        self:OnPeriodicTick(destGUID, spellId, sourceGUID)
    elseif eventName == "SPELL_AURA_REMOVED" then
        local key = makeKey(destGUID, spellId, sourceGUID)
        if self.active[key] then
            self:RemoveTracker(key)
        elseif destIsPlayer then
            self:ScanUnit("player")
        end
    elseif eventName == "SPELL_AURA_APPLIED" or eventName == "SPELL_AURA_REFRESH" then
        -- Pull freshest aura info from units we monitor.
        self:ScanAllUnits()
    end
end

local elapsedAccumulator = 0
function TickPulse:OnUpdate(elapsed)
    elapsedAccumulator = elapsedAccumulator + elapsed
    if elapsedAccumulator < 0.05 then
        return
    end
    elapsedAccumulator = 0

    self:UpdateLayout()
end

function TickPulse:InitUI()
    self.anchor = CreateFrame("Frame", "TickPulseAnchor", UIParent)
    self.anchor:SetSize(420, 180)
    self.anchor:SetPoint("CENTER", UIParent, "CENTER", 0, -180)

    self.anchor.bg = self.anchor:CreateTexture(nil, "BACKGROUND")
    self.anchor.bg:SetAllPoints()
    self.anchor.bg:SetColorTexture(0, 0, 0, 0.2)

    self.anchor.title = self.anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.anchor.title:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", 8, -6)
    self.anchor.title:SetText("TickPulse")

    self.anchor:EnableMouse(true)
    self.anchor:SetMovable(true)
    self.anchor:RegisterForDrag("LeftButton")
    self.anchor:SetScript("OnDragStart", function(f) f:StartMoving() end)
    self.anchor:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
end

function TickPulse:HandleEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        self:InitUI()
        frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
        self:ScanAllUnits()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:ScanAllUnits()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        self:ScanAllUnits()
    elseif event == "UNIT_AURA" then
        local unit = ...
        for _, monitored in ipairs(self.Config.monitoredUnits) do
            if unit == monitored then
                self:ScanUnit(unit)
                break
            end
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:OnCombatLogEvent()
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    TickPulse:HandleEvent(event, ...)
end)

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

SLASH_TICKPULSE1 = "/tickpulse"
SLASH_TICKPULSE2 = "/tpulse"
SlashCmdList.TICKPULSE = function(msg)
    local cmd = string.lower((msg or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if cmd == "hide" then
        TickPulse.anchor:Hide()
    elseif cmd == "show" then
        TickPulse.anchor:Show()
    elseif cmd == "scan" then
        TickPulse:ScanAllUnits()
    else
        print("TickPulse commands: /tpulse show | hide | scan")
    end
end

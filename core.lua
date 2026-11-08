local addonName, TickPulse = ...

-- TickPulse for WoW Forever (Interface 16001, modern Mainline client).
--
-- The Forever client inherits Midnight's addon restrictions:
--   * COMBAT_LOG_EVENT_UNFILTERED cannot be registered, so ticks are not observed.
--   * Aura data (UNIT_AURA payload, C_UnitAuras results) becomes "secret" while
--     restrictions are active (combat, encounters, PvP). Secret values cannot be
--     compared or used in arithmetic, and some lookups raise errors.
--   * The player's own spellcast events remain readable.
--
-- So instead of learning ticks from the combat log, TickPulse anchors each aura's
-- tick schedule at the moment it was applied (expirationTime - duration when aura
-- data is readable, or the player's cast time when it is not) and extrapolates
-- fixed-interval ticks from there.

TickPulse.active = TickPulse.active or {}
TickPulse.learnedDurations = TickPulse.learnedDurations or {}

local frame = CreateFrame("Frame")
TickPulse.frame = frame

local GRACE_WITHOUT_BUTTON = 5      -- seconds an unconfirmed tracker may live without a matching aura button
local BUTTON_CACHE_TTL = 0.25       -- seconds between rebuilds of the aura button candidate lists

local function now()
    return GetTime()
end

-- Returns `value` when addon code may inspect it, nil when it is a secret value.
local function readable(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end
TickPulse.readable = readable

local function isSecretTable(tbl)
    return issecrettable and issecrettable(tbl) or false
end

-- Boolean unit queries can return secret booleans; those cannot be tested directly.
local function readableBool(value, fallback)
    local v = readable(value)
    if v == nil then
        return fallback
    end
    return v and true or false
end

local function unitExists(unit)
    return readableBool(UnitExists(unit), true)
end

local function playerGUID()
    return readable(UnitGUID("player")) or "player"
end

local function makeKey(unit, spellName, sourceKey)
    return tostring(unit) .. ":" .. tostring(spellName) .. ":" .. tostring(sourceKey or "unknown")
end

local function getSpellTexture(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, spellId)
        if ok then
            return texture
        end
    end
    return nil
end

function TickPulse:IsMonitoredUnit(unit)
    for _, monitored in ipairs(self.Config.monitoredUnits) do
        if unit == monitored then
            return true
        end
    end
    return false
end

function TickPulse:GetSpellInfo(spellId, spellName)
    local info = spellId and self.Spells[spellId]
    if info then
        return info
    end

    if not spellName and spellId then
        spellName = self.ResolveSpellName(spellId)
    end

    if not spellName then
        return nil
    end

    local byName = self.SpellsByName and self.SpellsByName[spellName]
    if byName then
        if spellId then
            self.Spells[spellId] = byName
        end
        return byName
    end

    return nil
end

-- True when aura data cannot currently be read by addons.
function TickPulse:AurasAreSecret()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok then
            return readableBool(secret, true)
        end
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Aura reading
--------------------------------------------------------------------------------

-- Returns a plain table of the readable aura fields, `false` when the aura exists
-- but is restricted, or nil when there is no aura at that index.
local function readAuraByIndex(unit, index, filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        return nil
    end

    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if not ok then
        return false
    end
    if aura == nil then
        return nil
    end
    if isSecretTable(aura) then
        return false
    end

    return {
        name = readable(aura.name),
        spellId = readable(aura.spellId),
        icon = readable(aura.icon),
        duration = readable(aura.duration),
        expirationTime = readable(aura.expirationTime),
        sourceUnit = readable(aura.sourceUnit),
        auraInstanceID = readable(aura.auraInstanceID),
        auraIndex = index,
    }
end

--------------------------------------------------------------------------------
-- Aura button discovery
--------------------------------------------------------------------------------

local function getButtonIconRegion(button)
    if not button then
        return nil
    end

    local region = button.Icon or button.icon or button.IconTexture
    if not region and button.GetName then
        local name = button:GetName()
        if name then
            region = _G[name .. "Icon"]
        end
    end

    if region and region.GetTexture then
        return region
    end
    return nil
end

local function getButtonIconTexture(button)
    local region = getButtonIconRegion(button)
    if not region then
        return nil
    end
    return readable(region:GetTexture())
end

local function getButtonAuraInstanceID(button)
    local id = readable(button.auraInstanceID)
    if id then
        return id
    end

    local info = button.buttonInfo or button.auraInfo
    if type(info) == "table" and not isSecretTable(info) then
        return readable(info.auraInstanceID)
    end

    return nil
end

local function texturesEqual(left, right)
    if left == nil or right == nil then
        return false
    end
    if left == right then
        return true
    end

    local leftNumber, rightNumber = tonumber(left), tonumber(right)
    if leftNumber and rightNumber then
        return leftNumber == rightNumber
    end

    return tostring(left) == tostring(right)
end

local function isShown(widget)
    return widget and widget.IsShown and readableBool(widget:IsShown(), false)
end

local function collectAuraButtons(parentFrame, out, seen, depth)
    if not parentFrame or depth > 5 or not parentFrame.GetChildren then
        return
    end

    local children = { parentFrame:GetChildren() }
    for _, child in ipairs(children) do
        if not seen[child] then
            seen[child] = true
            -- Truthiness tests are allowed on secret values; comparisons are not.
            if child.auraInstanceID or child.buttonInfo or getButtonIconRegion(child) then
                out[#out + 1] = child
            end
            collectAuraButtons(child, out, seen, depth + 1)
        end
    end
end

-- Root frames and legacy named-button prefixes to search, per unit and aura type.
local BUTTON_SOURCES = {
    player = {
        HOT = { roots = { "BuffFrame" }, prefixes = { "BuffButton" } },
        DOT = { roots = { "DebuffFrame", "BuffFrame" }, prefixes = { "DebuffButton" } },
    },
    target = {
        HOT = { roots = { "TargetFrame" }, prefixes = { "TargetFrameBuff" } },
        DOT = { roots = { "TargetFrame" }, prefixes = { "TargetFrameDebuff" } },
    },
    focus = {
        HOT = { roots = { "FocusFrame" }, prefixes = { "FocusFrameBuff" } },
        DOT = { roots = { "FocusFrame" }, prefixes = { "FocusFrameDebuff" } },
    },
}

TickPulse.buttonCache = {}

function TickPulse:GetCandidateButtons(unit, spellType)
    local unitSources = BUTTON_SOURCES[unit]
    local source = unitSources and unitSources[spellType]
    if not source then
        return {}
    end

    local cacheKey = unit .. ":" .. spellType
    local cached = self.buttonCache[cacheKey]
    local t = now()
    if cached and (t - cached.time) < BUTTON_CACHE_TTL then
        return cached.list
    end

    local list, seen = {}, {}
    for _, prefix in ipairs(source.prefixes) do
        for i = 1, 40 do
            local button = _G[prefix .. i]
            if button and not seen[button] then
                seen[button] = true
                list[#list + 1] = button
            end
        end
    end
    for _, rootName in ipairs(source.roots) do
        collectAuraButtons(_G[rootName], list, seen, 0)
    end

    self.buttonCache[cacheKey] = { time = t, list = list }
    return list
end

function TickPulse:InvalidateButtonCache()
    wipe(self.buttonCache)
end

-- Finds the Blizzard aura button that displays `tracked`. `claimed` holds buttons
-- already bound to other trackers during this layout pass.
function TickPulse:FindAuraButton(tracked, claimed)
    claimed = claimed or {}

    -- Test-mode trackers draw on TickPulse's own icons.
    if tracked.fixedButton then
        return isShown(tracked.fixedButton) and tracked.fixedButton or nil
    end

    -- Keep an existing binding while it still looks right. When Blizzard has drawn the
    -- icon from secret aura data we cannot verify it, so the binding stays sticky.
    local bound = tracked.button
    if bound and isShown(bound) and not claimed[bound] then
        local boundId = getButtonAuraInstanceID(bound)
        local boundTexture = getButtonIconTexture(bound)
        if boundId and tracked.auraInstanceID then
            if boundId == tracked.auraInstanceID then
                return bound
            end
        elseif boundTexture then
            if texturesEqual(boundTexture, tracked.icon) then
                return bound
            end
        else
            return bound
        end
    end

    local candidates = self:GetCandidateButtons(tracked.buttonUnit or tracked.unit, tracked.spellType)
    local iconMatch
    for _, button in ipairs(candidates) do
        if not claimed[button] and isShown(button) then
            local id = getButtonAuraInstanceID(button)
            if id and tracked.auraInstanceID and id == tracked.auraInstanceID then
                return button
            end

            if not iconMatch and tracked.icon and texturesEqual(getButtonIconTexture(button), tracked.icon) then
                iconMatch = button
            end
        end
    end

    return iconMatch
end

--------------------------------------------------------------------------------
-- Overlay rendering
--------------------------------------------------------------------------------

function TickPulse:AcquireAuraOverlay(button)
    if not button then
        return nil
    end

    local overlay = button.TickPulseOverlay
    if not overlay then
        if InCombatLockdown() then
            return nil
        end

        overlay = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        local iconRegion = getButtonIconRegion(button)
        if iconRegion then
            overlay:SetAllPoints(iconRegion)
        else
            overlay:SetAllPoints(button)
        end
        overlay:SetDrawBling(false)
        overlay:SetDrawEdge(true)
        overlay:SetReverse(true)
        overlay:SetHideCountdownNumbers(true)
        overlay.noCooldownCount = true
        overlay:SetSwipeColor(1, 0.85, 0.1, 0.65)
        overlay:SetFrameLevel(button:GetFrameLevel() + 2)

        local valueText = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        valueText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
        valueText:SetText("")
        valueText:Hide()
        overlay.valueText = valueText

        button.TickPulseOverlay = overlay
    end

    overlay:Show()
    return overlay
end

local function hideOverlay(overlay)
    if not overlay then
        return
    end
    if overlay.valueText then
        overlay.valueText:SetText("")
        overlay.valueText:Hide()
    end
    overlay.tickPulseCycle = nil
    overlay:Hide()
end

function TickPulse:GetOverlayOpacity()
    local value = tonumber(self.Config.overlayOpacity) or 0.65
    value = math.max(0, math.min(1, value))
    self.Config.overlayOpacity = value
    return value
end

-- Start of the tick cycle that contains `t`.
function TickPulse:GetCycleStart(tracked, t)
    local interval = tracked.interval
    if not interval or interval <= 0 or not tracked.anchor then
        return nil
    end

    local elapsed = t - tracked.anchor
    if elapsed < 0 then
        return tracked.anchor
    end

    return tracked.anchor + math.floor(elapsed / interval) * interval
end

function TickPulse:FormatTickRemaining(seconds)
    if not seconds then
        return ""
    end
    if seconds >= 10 then
        return tostring(math.floor(seconds + 0.5))
    end
    return string.format("%.1f", seconds)
end

function TickPulse:ApplyOverlayVisuals(tracked, overlay, t, cycleStart)
    local showRotating = self.Config.showRotatingTicker ~= false
    local showNumeric = self.Config.showNumericTicker == true
    local opacity = self:GetOverlayOpacity()

    overlay:SetDrawSwipe(showRotating)
    overlay:SetDrawEdge(showRotating)
    overlay:SetSwipeColor(1, 0.85, 0.1, showRotating and opacity or 0)

    if showRotating and cycleStart then
        if overlay.tickPulseCycle ~= cycleStart or overlay.tickPulseInterval ~= tracked.interval then
            overlay:SetCooldown(cycleStart, tracked.interval)
            overlay.tickPulseCycle = cycleStart
            overlay.tickPulseInterval = tracked.interval
        end
    elseif overlay.tickPulseCycle then
        overlay:Clear()
        overlay.tickPulseCycle = nil
    end

    if overlay.valueText then
        if showNumeric and cycleStart then
            overlay.valueText:SetText(self:FormatTickRemaining(cycleStart + tracked.interval - t))
            overlay.valueText:SetTextColor(1, 1, 1, math.max(0.35, opacity))
            overlay.valueText:Show()
        else
            overlay.valueText:SetText("")
            overlay.valueText:Hide()
        end
    end
end

function TickPulse:HideAllOverlays()
    for _, tracked in pairs(self.active) do
        hideOverlay(tracked.overlay)
    end
end

function TickPulse:ShouldRenderTickerOnUnit(unit)
    if unit == "player" then
        return self.Config.showOnMainUI ~= false
    elseif unit == "target" then
        return self.Config.showOnTargetFrame ~= false
    elseif unit == "focus" then
        return self.Config.showOnFocusFrame ~= false
    end
    return true
end

--------------------------------------------------------------------------------
-- Tracker management
--------------------------------------------------------------------------------

function TickPulse:GetOrCreateTracker(unit, spellName, sourceKey, spellInfo, spellId)
    local key = makeKey(unit, spellName, sourceKey)
    local tracked = self.active[key]
    if not tracked then
        local t = now()
        tracked = {
            key = key,
            unit = unit,
            spellId = spellId,
            name = spellName,
            sourceKey = sourceKey,
            spellType = spellInfo.type,
            interval = spellInfo.interval,
            anchor = t,
            createdAt = t,
            lastSeen = nil,
        }
        self.active[key] = tracked
    end
    return tracked
end

function TickPulse:RemoveTracker(key)
    local tracked = self.active[key]
    if not tracked then
        return
    end

    hideOverlay(tracked.overlay)
    tracked.overlay = nil
    tracked.button = nil
    self.active[key] = nil
end

function TickPulse:RemoveTrackersForUnit(unit)
    for key, tracked in pairs(self.active) do
        if tracked.unit == unit then
            self:RemoveTracker(key)
        end
    end
end

-- Refreshes trackers from a readable aura. Returns the tracker key, or nil.
function TickPulse:TrackAura(unit, aura, expectedType)
    local spellName = aura.name or (aura.spellId and self.ResolveSpellName(aura.spellId))
    local spellInfo = self:GetSpellInfo(aura.spellId, spellName)
    if not spellInfo or spellInfo.type ~= expectedType then
        return nil
    end
    spellName = spellInfo.name or spellName

    local sourceKey
    if aura.sourceUnit then
        sourceKey = readable(UnitGUID(aura.sourceUnit)) or aura.sourceUnit
    elseif unit ~= "player" then
        sourceKey = playerGUID()
    end

    local tracked = self:GetOrCreateTracker(unit, spellName, sourceKey, spellInfo, aura.spellId)
    local t = now()

    tracked.spellId = aura.spellId or tracked.spellId
    tracked.icon = aura.icon or tracked.icon
    tracked.auraIndex = aura.auraIndex
    tracked.auraInstanceID = aura.auraInstanceID
    tracked.lastSeen = t

    local duration, expirationTime = aura.duration, aura.expirationTime
    if duration and duration > 0 and expirationTime and expirationTime > 0 then
        if expirationTime <= t then
            self:RemoveTracker(tracked.key)
            return nil
        end
        tracked.duration = duration
        tracked.expirationTime = expirationTime
        tracked.anchor = expirationTime - duration
        self.learnedDurations[spellName] = duration
    else
        tracked.duration = nil
        tracked.expirationTime = nil
    end

    return tracked.key
end

function TickPulse:ScanUnit(unit)
    if not unitExists(unit) then
        self:RemoveTrackersForUnit(unit)
        return
    end

    if self:AurasAreSecret() then
        return
    end

    local seen = {}
    local complete = true

    local function scanFilter(filter, expectedType)
        for i = 1, 40 do
            local aura = readAuraByIndex(unit, i, filter)
            if aura == nil then
                break
            elseif aura == false or (not aura.name and not aura.spellId) then
                complete = false
            else
                local key = self:TrackAura(unit, aura, expectedType)
                if key then
                    seen[key] = true
                end
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

    -- Only drop trackers when every aura on the unit could be inspected.
    if complete then
        for key, tracked in pairs(self.active) do
            if tracked.unit == unit and not seen[key] then
                self:RemoveTracker(key)
            end
        end
    end

    self:InvalidateButtonCache()
end

function TickPulse:ScanAllUnits()
    for _, unit in ipairs(self.Config.monitoredUnits) do
        self:ScanUnit(unit)
    end
end

-- Picks the unit a player cast most likely put its aura on.
function TickPulse:ResolveCastDestination(spellInfo)
    if spellInfo.self then
        return "player"
    end

    local hasTarget = unitExists("target")

    if spellInfo.type == "DOT" then
        return hasTarget and "target" or nil
    end

    if hasTarget and readableBool(UnitCanAssist("player", "target"), false) then
        return "target"
    end
    return "player"
end

-- Player casts stay readable during restrictions, so they anchor tick schedules
-- for newly applied or refreshed auras while aura data is secret.
function TickPulse:OnPlayerSpellCast(spellId)
    spellId = readable(spellId)
    if not spellId then
        return
    end

    local spellInfo = self:GetSpellInfo(spellId)
    if not spellInfo then
        return
    end

    local unit = self:ResolveCastDestination(spellInfo)
    if not unit or not self:IsMonitoredUnit(unit) then
        return
    end

    if not self:AurasAreSecret() then
        -- Aura data is authoritative; re-read once the aura has landed.
        C_Timer.After(0.2, function() self:ScanUnit(unit) end)
        if spellInfo.travel then
            C_Timer.After(1.0, function() self:ScanUnit(unit) end)
        end
        return
    end

    if spellInfo.travel then
        return
    end

    local spellName = spellInfo.name or self.ResolveSpellName(spellId)
    local tracked = self:GetOrCreateTracker(unit, spellName, playerGUID(), spellInfo, spellId)
    local t = now()

    tracked.anchor = t
    tracked.icon = tracked.icon or getSpellTexture(spellId)

    local duration = self.learnedDurations[spellName]
    if duration then
        tracked.duration = duration
        tracked.expirationTime = t + duration
    end
end

function TickPulse:OnUnitChanged(unit)
    self:InvalidateButtonCache()
    if self:AurasAreSecret() then
        -- The new unit's auras cannot be read; drop trackers that belonged to the old one.
        self:RemoveTrackersForUnit(unit)
    else
        self:ScanUnit(unit)
    end
end

function TickPulse:UpdateLayout()
    if not self.Config.enabled then
        self:HideAllOverlays()
        return
    end

    local t = now()
    local claimed = {}

    for key, tracked in pairs(self.active) do
        if tracked.expirationTime and tracked.expirationTime <= t then
            self:RemoveTracker(key)
        elseif not self:ShouldRenderTickerOnUnit(tracked.buttonUnit or tracked.unit) then
            hideOverlay(tracked.overlay)
        else
            local button = self:FindAuraButton(tracked, claimed)

            if not button then
                hideOverlay(tracked.overlay)
                tracked.button = nil

                local lastConfirmed = tracked.lastSeen or tracked.createdAt
                if not tracked.isTest and not tracked.expirationTime and (t - lastConfirmed) > GRACE_WITHOUT_BUTTON then
                    self:RemoveTracker(key)
                end
            else
                claimed[button] = true
                tracked.button = button
                tracked.lastSeen = t

                if tracked.overlay and tracked.overlay:GetParent() ~= button then
                    hideOverlay(tracked.overlay)
                    tracked.overlay = nil
                end

                local overlay = tracked.overlay or self:AcquireAuraOverlay(button)
                if overlay then
                    tracked.overlay = overlay
                    overlay:Show()
                    self:ApplyOverlayVisuals(tracked, overlay, t, self:GetCycleStart(tracked, t))
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Settings (modern Settings panel)
--------------------------------------------------------------------------------

-- Shipped defaults, captured before saved variables are applied.
local DEFAULTS = {}
for _, key in ipairs(TickPulse.PersistedKeys) do
    DEFAULTS[key] = TickPulse.Config[key]
end

function TickPulse:LoadSavedVariables()
    TickPulseDB = TickPulseDB or {}
    for _, key in ipairs(self.PersistedKeys) do
        if TickPulseDB[key] == nil then
            TickPulseDB[key] = self.Config[key]
        else
            self.Config[key] = TickPulseDB[key]
        end
    end

    if type(TickPulseDB.learnedDurations) == "table" then
        for name, duration in pairs(TickPulseDB.learnedDurations) do
            if self.learnedDurations[name] == nil then
                self.learnedDurations[name] = duration
            end
        end
    end
    TickPulseDB.learnedDurations = self.learnedDurations
end

function TickPulse:SetOption(key, value)
    self.Config[key] = value
    if TickPulseDB then
        TickPulseDB[key] = value
    end

    -- Changing a visibility option should not leave the addon globally disabled.
    self.Config.enabled = true
    self:ScanAllUnits()
    self:UpdateLayout()
end

function TickPulse:CreateOptionsPanel()
    if self.settingsCategory then
        return
    end

    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then
        print("TickPulse: the Settings panel is not available on this client; use /tpulse commands.")
        return
    end

    local category, layout = Settings.RegisterVerticalLayoutCategory("TickPulse")
    local varTypes = Settings.VarType or {}
    local settingsByKey = {}

    local function addHeader(text)
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    local function addCheckbox(key, label, tooltip)
        local setting = Settings.RegisterProxySetting(category, "TICKPULSE_" .. string.upper(key),
            varTypes.Boolean or "boolean", label, DEFAULTS[key] == true,
            function() return self.Config[key] == true end,
            function(value) self:SetOption(key, value and true or false) end)
        Settings.CreateCheckbox(category, setting, tooltip)
        settingsByKey[key] = setting
    end

    addHeader("Visibility")
    addCheckbox("showOnMainUI", "Show ticker on player auras", "Overlay the tick timer on your own buff and debuff icons.")
    addCheckbox("showOnTargetFrame", "Show ticker on target frame", "Overlay the tick timer on your target's aura icons.")
    addCheckbox("showOnFocusFrame", "Show ticker on focus frame", "Overlay the tick timer on your focus's aura icons.")
    addCheckbox("trackExternalOnPlayer", "Track other players' HoTs/DoTs on you",
        "Also track matching periodic auras that other players cast on you. Only possible while aura data is readable (usually out of combat).")

    addHeader("Visuals")
    addCheckbox("showRotatingTicker", "Show rotating ticker", "Draw a swipe that completes once per tick.")
    addCheckbox("showNumericTicker", "Show numeric values on ticker", "Show seconds until the next tick.")

    local opacitySetting = Settings.RegisterProxySetting(category, "TICKPULSE_OVERLAY_OPACITY",
        varTypes.Number or "number", "Ticker overlay opacity", DEFAULTS.overlayOpacity * 100,
        function() return math.floor(self:GetOverlayOpacity() * 100 + 0.5) end,
        function(value) self:SetOption("overlayOpacity", math.max(0, math.min(1, (value or 0) / 100))) end)
    local sliderOptions = Settings.CreateSliderOptions(0, 100, 5)
    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return string.format("%d%%", value)
        end)
    end
    Settings.CreateSlider(category, opacitySetting, sliderOptions, "Opacity of the tick swipe and numbers.")
    settingsByKey.overlayOpacity = opacitySetting

    if layout and CreateSettingsButtonInitializer then
        layout:AddInitializer(CreateSettingsButtonInitializer("Reset visual defaults", "Reset", function()
            settingsByKey.showNumericTicker:SetValue(DEFAULTS.showNumericTicker)
            settingsByKey.showRotatingTicker:SetValue(DEFAULTS.showRotatingTicker)
            settingsByKey.overlayOpacity:SetValue(DEFAULTS.overlayOpacity * 100)
        end, "Numeric off, rotating on, opacity 65%.", true))
    end

    Settings.RegisterAddOnCategory(category)
    self.settingsCategory = category
end

function TickPulse:OpenOptionsPanel()
    self:CreateOptionsPanel()

    if self.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.settingsCategory:GetID())
    else
        print("TickPulse: options UI is not available on this client.")
    end
end

--------------------------------------------------------------------------------
-- Test mode (/tpulse test)
--------------------------------------------------------------------------------

local TEST_SOURCE = "tickpulse-test"
local TEST_ICONS = {
    { label = "DoT", spellType = "DOT", interval = 3.0, spellId = 589, fallback = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" },
    { label = "HoT", spellType = "HOT", interval = 2.0, spellId = 139, fallback = "Interface\\Icons\\Spell_Holy_Renew" },
}

function TickPulse:CreateTestFrame()
    if self.testFrame then
        return self.testFrame
    end

    local testFrame = CreateFrame("Frame", "TickPulseTestFrame", UIParent)
    testFrame:SetSize(120, 70)
    testFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    testFrame:SetMovable(true)
    testFrame:SetClampedToScreen(true)
    testFrame:EnableMouse(true)
    testFrame:RegisterForDrag("LeftButton")
    testFrame:SetScript("OnDragStart", testFrame.StartMoving)
    testFrame:SetScript("OnDragStop", testFrame.StopMovingOrSizing)

    local background = testFrame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.5)

    local title = testFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", testFrame, "TOP", 0, -4)
    title:SetText("TickPulse test")

    testFrame.icons = {}
    for i, spec in ipairs(TEST_ICONS) do
        local button = CreateFrame("Button", "TickPulseTest" .. spec.label, testFrame)
        button:SetSize(32, 32)
        button:SetPoint("TOPLEFT", testFrame, "TOPLEFT", 16 + (i - 1) * 56, -20)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(getSpellTexture(spec.spellId) or spec.fallback)
        button.Icon = icon

        local caption = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        caption:SetPoint("TOP", button, "BOTTOM", 0, -2)
        caption:SetText(string.format("%s %.0fs", spec.label, spec.interval))

        testFrame.icons[i] = button
    end

    self.testFrame = testFrame
    return testFrame
end

-- Adds a fake tick schedule to the first buff you have, to test matching against
-- the real Blizzard buff frame. Returns the buff name, or nil with a reason.
function TickPulse:AddTestTrackerOnRealBuff(t)
    if self:AurasAreSecret() then
        return nil, "aura data is secret right now (leave combat and try again)"
    end

    for i = 1, 40 do
        local aura = readAuraByIndex("player", i, "HELPFUL")
        if aura == nil then
            break
        end
        if aura and aura.icon and aura.name then
            local tracked = self:GetOrCreateTracker("test", aura.name, TEST_SOURCE,
                { type = "HOT", interval = 3.0 }, aura.spellId)
            tracked.isTest = true
            tracked.buttonUnit = "player"
            tracked.icon = aura.icon
            tracked.auraInstanceID = aura.auraInstanceID
            tracked.anchor = t
            return aura.name
        end
    end

    return nil, "you have no readable buffs (eat food or cast a self-buff, then rerun)"
end

function TickPulse:StartTest()
    if InCombatLockdown() then
        print("TickPulse: start test mode out of combat (overlays can't be created in combat).")
        return
    end

    self:StopTest(true)
    self.Config.enabled = true

    local t = now()
    local testFrame = self:CreateTestFrame()
    testFrame:Show()

    for i, spec in ipairs(TEST_ICONS) do
        local tracked = self:GetOrCreateTracker("test", "Test " .. spec.label, TEST_SOURCE,
            { type = spec.spellType, interval = spec.interval }, nil)
        tracked.isTest = true
        tracked.fixedButton = testFrame.icons[i]
        tracked.anchor = t
    end

    local buffName, reason = self:AddTestTrackerOnRealBuff(t)
    if buffName then
        print("TickPulse test: test icons shown, and a fake 3s tick added to your buff \"" .. buffName .. "\". /tpulse test off to stop.")
    else
        print("TickPulse test: test icons shown. No real-buff test: " .. reason .. ". /tpulse test off to stop.")
    end

    self:UpdateLayout()
end

function TickPulse:StopTest(silent)
    for key, tracked in pairs(self.active) do
        if tracked.isTest then
            self:RemoveTracker(key)
        end
    end

    if self.testFrame then
        self.testFrame:Hide()
    end

    if not silent then
        print("TickPulse test mode off.")
    end
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

function TickPulse:DebugBindings(unitFilter)
    local _, _, _, interfaceVersion = GetBuildInfo()
    print(string.format("TickPulse debug | interface:%s | aura data:%s%s",
        tostring(interfaceVersion),
        self:AurasAreSecret() and "secret" or "readable",
        unitFilter and (" | unit:" .. unitFilter) or ""))

    local count = 0
    local t = now()
    for _, tracked in pairs(self.active) do
        if not unitFilter or tracked.unit == unitFilter then
            count = count + 1
            local button = self:FindAuraButton(tracked)
            local buttonLabel = button and (button:GetName() or ("unnamed:" .. tostring(getButtonAuraInstanceID(button) or "?"))) or "(missing)"
            local cycleStart = self:GetCycleStart(tracked, t)
            local nextTick = cycleStart and string.format("%.1fs", cycleStart + tracked.interval - t) or "?"

            print(string.format("  %s | unit:%s | every %.1fs | next:%s | button:%s | %s",
                tostring(tracked.name or tracked.spellId), tostring(tracked.unit), tracked.interval or 0,
                nextTick, buttonLabel, tracked.overlay and "overlay:on" or "overlay:off"))
        end
    end

    if count == 0 then
        print("  no active trackers" .. (unitFilter and (" for unit " .. unitFilter) or "") .. ".")
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local elapsedAccumulator = 0
function TickPulse:OnUpdate(elapsed)
    elapsedAccumulator = elapsedAccumulator + elapsed
    if elapsedAccumulator < 0.05 then
        return
    end
    elapsedAccumulator = 0

    self:UpdateLayout()
end

function TickPulse:HandleEvent(event, ...)
    if event == "ADDON_LOADED" then
        if ... == addonName then
            self:LoadSavedVariables()
        end
    elseif event == "PLAYER_LOGIN" then
        self:BuildSpellIndex()
        self:CreateOptionsPanel()
        frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
        self:ScanAllUnits()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED"
        or event == "ENCOUNTER_END" or event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- Restrictions may have lifted; re-read authoritative aura data.
        self:ScanAllUnits()
    elseif event == "PLAYER_TARGET_CHANGED" then
        self:OnUnitChanged("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        self:OnUnitChanged("focus")
    elseif event == "UNIT_AURA" then
        local unit = ...
        if self:IsMonitoredUnit(unit) then
            self:ScanUnit(unit)
            self:InvalidateButtonCache()
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellId = ...
        self:OnPlayerSpellCast(spellId)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    TickPulse:HandleEvent(event, ...)
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

-- Events that may not exist on every build; registering an unknown event errors.
for _, optionalEvent in ipairs({ "PLAYER_FOCUS_CHANGED", "ENCOUNTER_END", "ADDON_RESTRICTION_STATE_CHANGED" }) do
    pcall(frame.RegisterEvent, frame, optionalEvent)
end

SLASH_TICKPULSE1 = "/tickpulse"
SLASH_TICKPULSE2 = "/tpulse"
SlashCmdList.TICKPULSE = function(msg)
    local normalized = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = normalized:match("^(%S+)%s*(.-)$")
    cmd = string.lower(cmd or "")
    arg = string.lower(arg or "")

    if cmd == "hide" then
        TickPulse.Config.enabled = false
        TickPulse:HideAllOverlays()
    elseif cmd == "show" then
        TickPulse.Config.enabled = true
        TickPulse:ScanAllUnits()
    elseif cmd == "scan" then
        TickPulse:ScanAllUnits()
    elseif cmd == "options" then
        TickPulse:OpenOptionsPanel()
    elseif cmd == "debug" then
        if arg == "" then
            TickPulse:DebugBindings()
        elseif arg == "player" or arg == "target" or arg == "focus" or arg == "test" then
            TickPulse:DebugBindings(arg)
        else
            print("TickPulse debug usage: /tpulse debug [player|target|focus|test]")
        end
    elseif cmd == "test" then
        if arg == "off" or arg == "stop" then
            TickPulse:StopTest()
        else
            TickPulse:StartTest()
        end
    else
        print("TickPulse commands: /tpulse show | hide | scan | options | test [off] | debug [player|target|focus|test]")
    end
end

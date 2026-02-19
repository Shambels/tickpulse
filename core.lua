local addonName, TickPulse = ...

TickPulse.active = TickPulse.active or {}

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

local function getButtonIconTexture(button)
    if not button then
        return nil
    end

    local iconRegion = button.icon
        or button.Icon
        or button.IconTexture
        or (button.GetName and button:GetName() and _G[button:GetName() .. "Icon"])

    if iconRegion and iconRegion.GetTexture then
        return iconRegion:GetTexture()
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

    local leftNumber = tonumber(left)
    local rightNumber = tonumber(right)
    if leftNumber and rightNumber then
        return leftNumber == rightNumber
    end

    return tostring(left) == tostring(right)
end

local function findButtonByIcon(prefix, auraIndex, iconTexture)
    local exact = _G[prefix .. tostring(auraIndex)]
    if exact then
        local exactTexture = getButtonIconTexture(exact)
        if exact:IsShown() and ((not iconTexture and exactTexture ~= nil) or texturesEqual(exactTexture, iconTexture)) then
            return exact
        end
    end

    if not iconTexture then
        if exact and exact:IsShown() then
            return exact
        end
    end

    local bestMatch = nil
    for i = 1, 40 do
        local candidate = _G[prefix .. tostring(i)]
        if candidate then
            local candidateTexture = getButtonIconTexture(candidate)
            if candidate:IsShown() and texturesEqual(candidateTexture, iconTexture) then
                if candidate.GetID and candidate:GetID() == auraIndex then
                    return candidate
                end

                if not bestMatch then
                    bestMatch = candidate
                end
            end
        end
    end

    return bestMatch
end

local function findButtonByPrefixList(prefixes, auraIndex, iconTexture)
    for _, prefix in ipairs(prefixes) do
        local found = findButtonByIcon(prefix, auraIndex, iconTexture)
        if found then
            return found
        end
    end

    return nil
end

local function collectDescendantButtons(parentFrame, out, depth)
    if not parentFrame or depth > 4 then
        return
    end

    local childCount = parentFrame:GetNumChildren() or 0
    for i = 1, childCount do
        local child = select(i, parentFrame:GetChildren())
        if child then
            if child.GetObjectType and child:GetObjectType() == "Button" then
                out[#out + 1] = child
            end
            collectDescendantButtons(child, out, depth + 1)
        end
    end
end

local function findChildButtonByIcon(parentFrame, auraIndex, iconTexture)
    if not parentFrame then
        return nil
    end

    local buttons = {}
    collectDescendantButtons(parentFrame, buttons, 0)

    local bestById = nil
    for _, child in ipairs(buttons) do
        if child:IsShown() then
            local childTexture = getButtonIconTexture(child)
            if childTexture and iconTexture and tostring(childTexture) == tostring(iconTexture) then
                if child.GetID and child:GetID() == auraIndex then
                    return child
                end

                if not bestById then
                    bestById = child
                end
            end
        end
    end

    if bestById then
        return bestById
    end

    for _, candidate in ipairs(buttons) do
        if candidate:IsShown() and candidate.GetID and candidate:GetID() == auraIndex then
            return candidate
        end
    end

    return nil
end

function TickPulse:GetAuraButton(unit, spellType, auraIndex, iconTexture)
    local frameName

    if unit == "target" then
        frameName = ((spellType == "DOT") and "TargetFrameDebuff" or "TargetFrameBuff") .. tostring(auraIndex)
    elseif unit == "focus" then
        frameName = ((spellType == "DOT") and "FocusFrameDebuff" or "FocusFrameBuff") .. tostring(auraIndex)
    elseif unit == "player" then
        if spellType == "HOT" then
            return findButtonByPrefixList({
                "BuffButton",
                "BuffFrameBuff",
                "PlayerBuffButton",
            }, auraIndex, iconTexture)
                or findChildButtonByIcon(_G.BuffFrame, auraIndex, iconTexture)
        end

        return findButtonByPrefixList({
            "DebuffButton",
            "DebuffFrameDebuff",
            "BuffFrameDebuff",
            "BuffButton",
            "PlayerDebuffButton",
        }, auraIndex, iconTexture)
            or findChildButtonByIcon(_G.DebuffFrame, auraIndex, iconTexture)
            or findChildButtonByIcon(_G.BuffFrame, auraIndex, iconTexture)
    end

    if not frameName then
        return nil
    end

    return _G[frameName]
end

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
        overlay:SetAllPoints(button)
        overlay:SetDrawBling(false)
        overlay:SetDrawEdge(true)
        overlay:SetReverse(true)
        if overlay.SetHideCountdownNumbers then
            overlay:SetHideCountdownNumbers(true)
        end
        overlay.noCooldownCount = true
        overlay:SetSwipeColor(1, 0.85, 0.1, 0.65)
        overlay:SetFrameLevel(button:GetFrameLevel() + 2)

        if not button.TickPulseValueText then
            button.TickPulseValueText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            button.TickPulseValueText:SetPoint("CENTER", button, "CENTER", 0, 0)
            button.TickPulseValueText:SetDrawLayer("OVERLAY", 7)
            button.TickPulseValueText:SetText("")
            button.TickPulseValueText:Hide()
        end

        overlay.valueText = button.TickPulseValueText

        button.TickPulseOverlay = overlay
    end

    overlay:Show()
    return overlay
end

function TickPulse:GetOverlayOpacity()
    local value = tonumber(self.Config.overlayOpacity)
    if not value then
        value = 0.65
    end

    if value < 0 then
        value = 0
    elseif value > 1 then
        value = 1
    end

    self.Config.overlayOpacity = value
    return value
end

function TickPulse:GetTickRemaining(tracked, t)
    if not tracked.interval or tracked.interval <= 0 then
        return nil
    end

    local remaining = (tracked.nextTick or 0) - t
    if remaining > 0 then
        return remaining
    end

    if tracked.cycleStart then
        local elapsed = t - tracked.cycleStart
        if elapsed >= 0 then
            local progress = math.fmod(elapsed, tracked.interval)
            return tracked.interval - progress
        end
    end

    return tracked.interval
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

function TickPulse:ApplyOverlayVisuals(tracked, overlay, t)
    local showRotating = self.Config.showRotatingTicker ~= false
    local showNumeric = self.Config.showNumericTicker == true
    local opacity = self:GetOverlayOpacity()

    if overlay.SetDrawSwipe then
        overlay:SetDrawSwipe(showRotating)
    end

    if overlay.SetDrawEdge then
        overlay:SetDrawEdge(showRotating)
    end

    if overlay.SetSwipeColor then
        overlay:SetSwipeColor(1, 0.85, 0.1, showRotating and opacity or 0)
    end

    if overlay.valueText then
        if showNumeric then
            local remaining = self:GetTickRemaining(tracked, t)
            overlay.valueText:SetText(self:FormatTickRemaining(remaining))
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
        if tracked.overlay then
            tracked.overlay:Hide()
            if tracked.overlay.valueText then
                tracked.overlay.valueText:SetText("")
                tracked.overlay.valueText:Hide()
            end
        end
    end
end

function TickPulse:ShouldRenderTickerOnUnit(unit)
    if unit == "player" then
        return self.Config.showOnMainUI ~= false
    end

    if unit == "target" then
        return self.Config.showOnTargetFrame ~= false
    end

    if unit == "focus" then
        return self.Config.showOnFocusFrame ~= false
    end

    return true
end

function TickPulse:CreateOptionsPanel()
    if self.optionsPanel then
        return
    end

    if not InterfaceOptions_AddCategory and not InterfaceOptionsFrame_AddCategory and LoadAddOn then
        pcall(LoadAddOn, "Blizzard_InterfaceOptions")
    end

    local panel = CreateFrame("Frame", "TickPulseOptionsPanel", UIParent)
    panel.name = "TickPulse"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("TickPulse")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Ticker visibility and visuals")

    local mainUICheckbox = CreateFrame("CheckButton", "TickPulseOptionsMainUICheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    mainUICheckbox:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -20)
    _G[mainUICheckbox:GetName() .. "Text"]:SetText("Show ticker on main UI (player auras)")

    local targetFrameCheckbox = CreateFrame("CheckButton", "TickPulseOptionsTargetFrameCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    targetFrameCheckbox:SetPoint("TOPLEFT", mainUICheckbox, "BOTTOMLEFT", 0, -12)
    _G[targetFrameCheckbox:GetName() .. "Text"]:SetText("Show ticker on target frame")

    local focusFrameCheckbox = CreateFrame("CheckButton", "TickPulseOptionsFocusFrameCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    focusFrameCheckbox:SetPoint("TOPLEFT", targetFrameCheckbox, "BOTTOMLEFT", 0, -12)
    _G[focusFrameCheckbox:GetName() .. "Text"]:SetText("Show ticker on focus frame")

    local numericTickerCheckbox = CreateFrame("CheckButton", "TickPulseOptionsNumericTickerCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    numericTickerCheckbox:SetPoint("TOPLEFT", focusFrameCheckbox, "BOTTOMLEFT", 0, -20)
    _G[numericTickerCheckbox:GetName() .. "Text"]:SetText("Show numeric values on ticker")

    local rotatingTickerCheckbox = CreateFrame("CheckButton", "TickPulseOptionsRotatingTickerCheckbox", panel, "InterfaceOptionsCheckButtonTemplate")
    rotatingTickerCheckbox:SetPoint("TOPLEFT", numericTickerCheckbox, "BOTTOMLEFT", 0, -12)
    _G[rotatingTickerCheckbox:GetName() .. "Text"]:SetText("Show rotating ticker")

    local opacitySlider = CreateFrame("Slider", "TickPulseOptionsOpacitySlider", panel, "OptionsSliderTemplate")
    opacitySlider:SetPoint("TOPLEFT", rotatingTickerCheckbox, "BOTTOMLEFT", 0, -30)
    opacitySlider:SetWidth(240)
    opacitySlider:SetMinMaxValues(0, 100)
    opacitySlider:SetValueStep(1)
    opacitySlider:SetObeyStepOnDrag(true)
    _G[opacitySlider:GetName() .. "Text"]:SetText("Ticker overlay opacity")
    _G[opacitySlider:GetName() .. "Low"]:SetText("0%")
    _G[opacitySlider:GetName() .. "High"]:SetText("100%")

    local resetVisualsButton = CreateFrame("Button", "TickPulseOptionsResetVisualsButton", panel, "UIPanelButtonTemplate")
    resetVisualsButton:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", 0, -18)
    resetVisualsButton:SetSize(180, 22)
    resetVisualsButton:SetText("Reset Visual Defaults")

    panel._isRefreshing = false

    panel.refresh = function()
        panel._isRefreshing = true
        mainUICheckbox:SetChecked(self.Config.showOnMainUI ~= false)
        targetFrameCheckbox:SetChecked(self.Config.showOnTargetFrame ~= false)
        focusFrameCheckbox:SetChecked(self.Config.showOnFocusFrame ~= false)
        numericTickerCheckbox:SetChecked(self.Config.showNumericTicker == true)
        rotatingTickerCheckbox:SetChecked(self.Config.showRotatingTicker ~= false)
        opacitySlider:SetValue(math.floor((self:GetOverlayOpacity() * 100) + 0.5))
        panel._isRefreshing = false
    end

    local function applyOption(configKey, checked)
        self.Config[configKey] = checked and true or false

        -- Changing a visibility option should not accidentally leave the addon globally disabled.
        self.Config.enabled = true

        -- Rebind trackers broadly so one toggle doesn't strand overlays on other units.
        self:ScanAllUnits()
        self:UpdateLayout()
    end

    panel:SetScript("OnShow", panel.refresh)
    panel.refresh()

    mainUICheckbox:SetScript("OnClick", function(button)
        if panel._isRefreshing then
            return
        end
        applyOption("showOnMainUI", button:GetChecked())
    end)

    targetFrameCheckbox:SetScript("OnClick", function(button)
        if panel._isRefreshing then
            return
        end
        applyOption("showOnTargetFrame", button:GetChecked())
    end)

    focusFrameCheckbox:SetScript("OnClick", function(button)
        if panel._isRefreshing then
            return
        end
        applyOption("showOnFocusFrame", button:GetChecked())
    end)

    numericTickerCheckbox:SetScript("OnClick", function(button)
        if panel._isRefreshing then
            return
        end

        self.Config.showNumericTicker = button:GetChecked() and true or false
        self:UpdateLayout()
    end)

    rotatingTickerCheckbox:SetScript("OnClick", function(button)
        if panel._isRefreshing then
            return
        end

        self.Config.showRotatingTicker = button:GetChecked() and true or false
        self:UpdateLayout()
    end)

    opacitySlider:SetScript("OnValueChanged", function(slider, value)
        if panel._isRefreshing then
            return
        end

        self.Config.overlayOpacity = math.max(0, math.min(1, (value or 0) / 100))
        self:UpdateLayout()
    end)

    resetVisualsButton:SetScript("OnClick", function()
        self.Config.showNumericTicker = false
        self.Config.showRotatingTicker = true
        self.Config.overlayOpacity = 0.65

        panel.refresh()
        self:UpdateLayout()
    end)

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    elseif InterfaceOptionsFrame_AddCategory then
        InterfaceOptionsFrame_AddCategory(panel)
    elseif Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "TickPulse")
        Settings.RegisterAddOnCategory(category)
        panel.TickPulseSettingsCategoryID = category:GetID()
    else
        print("TickPulse: unable to register options panel on this client.")
    end

    self.optionsPanel = panel
end

function TickPulse:OpenOptionsPanel()
    if not self.optionsPanel then
        self:CreateOptionsPanel()
    end

    if not InterfaceOptionsFrame_OpenToCategory and not Settings and LoadAddOn then
        pcall(LoadAddOn, "Blizzard_InterfaceOptions")
    end

    if InterfaceOptionsFrame_OpenToCategory and self.optionsPanel then
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    elseif Settings and Settings.OpenToCategory and self.optionsPanel and self.optionsPanel.TickPulseSettingsCategoryID then
        Settings.OpenToCategory(self.optionsPanel.TickPulseSettingsCategoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory("TickPulse")
        InterfaceOptionsFrame_OpenToCategory("TickPulse")
    else
        print("TickPulse: options UI is not available on this client.")
    end
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
            overlay = nil,
        }
        self.active[key] = tracked
    else
        tracked.unit = unit
        tracked.sourceGUID = sourceGUID
    end

    tracked.name = auraData.name
    tracked.icon = auraData.icon
    tracked.auraIndex = auraData.auraIndex
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

    if tracked.overlay then
        if tracked.overlay.valueText then
            tracked.overlay.valueText:SetText("")
            tracked.overlay.valueText:Hide()
        end
        tracked.overlay:Hide()
        tracked.overlay = nil
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
                    auraIndex = i,
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

function TickPulse:OnPeriodicTick(destGUID, spellId, sourceGUID, tickEvent)
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
    tracked.lastTickEvent = tickEvent
    tracked.cycleStart = t
    tracked.nextTick = t + tracked.interval
end

function TickPulse:ResetTrackerCycle(destGUID, spellId, sourceGUID)
    local key = makeKey(destGUID, spellId, sourceGUID)
    local tracked = self.active[key]
    if not tracked then
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
    tracked.cycleStart = t
    tracked.nextTick = t + (tracked.interval or 0)
    tracked.lastTick = nil

    if tracked.overlay and self.Config.showRotatingTicker ~= false and tracked.interval and tracked.interval > 0 then
        tracked.overlay:SetCooldown(tracked.cycleStart, tracked.interval)
    end
end

function TickPulse:UpdateLayout()
    if not self.Config.enabled then
        self:HideAllOverlays()
        return
    end

    for _, tracked in pairs(self.active) do
        local t = now()

        if tracked.expirationTime and tracked.expirationTime > 0 and tracked.expirationTime <= t then
            self:RemoveTracker(tracked.key)
        elseif not self:ShouldRenderTickerOnUnit(tracked.unit) then
            if tracked.overlay then
                if tracked.overlay.valueText then
                    tracked.overlay.valueText:SetText("")
                    tracked.overlay.valueText:Hide()
                end
                tracked.overlay:Hide()
            end
        else
            local button = self:GetAuraButton(tracked.unit, tracked.spellType, tracked.auraIndex, tracked.icon)

            if not button or not button:IsShown() then
                if tracked.overlay then
                    if tracked.overlay.valueText then
                        tracked.overlay.valueText:SetText("")
                        tracked.overlay.valueText:Hide()
                    end
                    tracked.overlay:Hide()
                end
            else
                if tracked.overlay and tracked.overlay:GetParent() ~= button then
                    if tracked.overlay.valueText then
                        tracked.overlay.valueText:SetText("")
                        tracked.overlay.valueText:Hide()
                    end
                    tracked.overlay:Hide()
                    tracked.overlay = nil
                end

                local overlay = tracked.overlay or self:AcquireAuraOverlay(button)
                if overlay then
                    tracked.overlay = overlay
                    overlay:Show()

                    self:ApplyOverlayVisuals(tracked, overlay, t)

                    if self.Config.showRotatingTicker ~= false and tracked.interval and tracked.interval > 0 then
                        overlay:SetCooldown(tracked.cycleStart, tracked.interval)
                    end
                end
            end
        end
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
        self:OnPeriodicTick(destGUID, spellId, sourceGUID, "DAMAGE")
    elseif eventName == "SPELL_PERIODIC_HEAL" and spellInfo.type == "HOT" then
        self:OnPeriodicTick(destGUID, spellId, sourceGUID, "HEAL")
    elseif eventName == "SPELL_PERIODIC_ENERGIZE" and spellInfo.type == "HOT" then
        self:OnPeriodicTick(destGUID, spellId, sourceGUID, "ENERGIZE")
    elseif eventName == "SPELL_AURA_REMOVED" then
        local key = makeKey(destGUID, spellId, sourceGUID)
        if self.active[key] then
            self:RemoveTracker(key)
        elseif destIsPlayer then
            self:ScanUnit("player")
        end
    elseif eventName == "SPELL_AURA_APPLIED" or eventName == "SPELL_AURA_REFRESH" then
        self:ResetTrackerCycle(destGUID, spellId, sourceGUID)
        -- Pull freshest aura info from units we monitor.
        self:ScanAllUnits()
    end
end

function TickPulse:DebugBindings(unitFilter)
    local count = 0
    if unitFilter then
        print("TickPulse debug bindings (unit: " .. tostring(unitFilter) .. "):")
    else
        print("TickPulse debug bindings:")
    end

    for _, tracked in pairs(self.active) do
        if not unitFilter or tracked.unit == unitFilter then
            count = count + 1
            local button = self:GetAuraButton(tracked.unit, tracked.spellType, tracked.auraIndex, tracked.icon)
            local buttonName = button and button:GetName() or "(missing)"
            local overlayState = tracked.overlay and "overlay:on" or "overlay:off"
            local spellLabel = tracked.name or ("spell:" .. tostring(tracked.spellId))
            local eventLabel = tracked.lastTickEvent and (" | tick:" .. tostring(tracked.lastTickEvent)) or ""

            print(string.format("%s | unit:%s | index:%s | button:%s | %s%s", spellLabel, tostring(tracked.unit), tostring(tracked.auraIndex), tostring(buttonName), overlayState, eventLabel))

            if tracked.unit == "player" and not button then
                local buffByIndex = _G["BuffButton" .. tostring(tracked.auraIndex)] or _G["BuffFrameBuff" .. tostring(tracked.auraIndex)]
                local debuffByIndex = _G["DebuffButton" .. tostring(tracked.auraIndex)] or _G["DebuffFrameDebuff" .. tostring(tracked.auraIndex)]
                local buffName = buffByIndex and buffByIndex:GetName() or "nil"
                local debuffName = debuffByIndex and debuffByIndex:GetName() or "nil"
                print(string.format("  player lookup hints | Buff idx:%s | Debuff idx:%s", tostring(buffName), tostring(debuffName)))
            end
        end
    end

    if count == 0 then
        print("TickPulse: no active trackers" .. (unitFilter and (" for unit " .. tostring(unitFilter)) or "") .. ".")
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

function TickPulse:HandleEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        self:CreateOptionsPanel()
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
    local normalized = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = normalized:match("^(%S+)%s*(.-)$")
    cmd = string.lower(cmd or "")
    arg = string.lower((arg or ""):gsub("^%s+", ""):gsub("%s+$", ""))

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
        elseif arg == "player" or arg == "target" or arg == "focus" then
            TickPulse:DebugBindings(arg)
        else
            print("TickPulse debug usage: /tpulse debug [player|target|focus]")
        end
    else
        print("TickPulse commands: /tpulse show | hide | scan | options | debug [player|target|focus]")
    end
end

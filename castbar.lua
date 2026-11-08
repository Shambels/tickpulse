local _, TickPulse = ...

-- Tick marks on the player cast bar while channelling.
--
-- The player's own cast info stays readable during addon restrictions, so this
-- works in combat. A channel bar drains from right to left, so a tick that happens
-- a fraction `f` of the way through the channel is drawn at (1 - f) of the bar's
-- width. Marks for ticks that already happened are dimmed, which makes it easy to
-- stop right after a tick instead of wasting part of one.

local MARK_WIDTH = 2
local MARK_ALPHA_UPCOMING = 0.9
local MARK_ALPHA_PASSED = 0.25

local readable = TickPulse.readable
local events = CreateFrame("Frame")

local function getCastBar()
    return _G.PlayerCastingBarFrame or _G.CastingBarFrame
end

function TickPulse:GetChannelInterval(spellId, spellName)
    local info = (spellName and self.ChannelsByName and self.ChannelsByName[spellName])
        or self:GetSpellInfo(spellId, spellName)
    if not info or info.disabled then
        return nil
    end
    return info.interval
end

function TickPulse:HideChannelTicks()
    self.channel = nil
    local holder = self.channelTickHolder
    if holder then
        holder:Hide()
        for _, mark in ipairs(holder.marks) do
            mark:Hide()
        end
    end
end

local function readChannel()
    local name, _, _, startMS, endMS, _, _, spellId = UnitChannelInfo("player")
    name, startMS, endMS, spellId = readable(name), readable(startMS), readable(endMS), readable(spellId)
    if not (startMS and endMS) or endMS <= startMS then
        return nil
    end
    return name, startMS / 1000, endMS / 1000, spellId
end

function TickPulse:LayoutChannelTicks()
    local channel = self.channel
    local bar = getCastBar()
    if not channel or not bar then
        self:HideChannelTicks()
        return
    end

    local holder = self.channelTickHolder
    if not holder then
        holder = CreateFrame("Frame", nil, bar)
        holder.marks = {}
        holder:SetScript("OnUpdate", function() self:UpdateChannelTicks() end)
        self.channelTickHolder = holder
    end
    if holder:GetParent() ~= bar then
        holder:SetParent(bar)
    end
    holder:ClearAllPoints()
    holder:SetAllPoints(bar)
    holder:SetFrameLevel(bar:GetFrameLevel() + 5)

    local width, height = bar:GetWidth(), bar:GetHeight()
    local duration = channel.finish - channel.start
    local used = 0

    if width and width > 0 and duration > 0 then
        -- Ticks at start + k*interval, excluding the one that coincides with the end.
        local tickTime = channel.start + channel.interval
        while tickTime < channel.finish - 0.05 do
            used = used + 1
            local mark = holder.marks[used]
            if not mark then
                mark = holder:CreateTexture(nil, "OVERLAY")
                mark:SetColorTexture(1, 1, 1, 1)
                holder.marks[used] = mark
            end

            local fraction = (tickTime - channel.start) / duration
            mark:ClearAllPoints()
            mark:SetSize(MARK_WIDTH, height)
            mark:SetPoint("CENTER", holder, "LEFT", width * (1 - fraction), 0)
            mark.tickTime = tickTime
            mark:Show()

            tickTime = tickTime + channel.interval
        end
    end

    for i = used + 1, #holder.marks do
        holder.marks[i]:Hide()
    end

    holder:Show()
    self:UpdateChannelTicks()
end

function TickPulse:UpdateChannelTicks()
    local channel, holder = self.channel, self.channelTickHolder
    if not channel or not holder then
        return
    end

    local t = GetTime()
    if t > channel.finish + 0.5 or self.Config.showChannelTicks == false then
        self:HideChannelTicks()
        return
    end

    for _, mark in ipairs(holder.marks) do
        if mark:IsShown() then
            mark:SetAlpha(t >= mark.tickTime and MARK_ALPHA_PASSED or MARK_ALPHA_UPCOMING)
        end
    end
end

function TickPulse:OnChannelStart()
    if self.Config.showChannelTicks == false then
        self:HideChannelTicks()
        return
    end

    local name, start, finish, spellId = readChannel()
    local interval = name and self:GetChannelInterval(spellId, name)
    if not interval or interval <= 0 then
        self:HideChannelTicks()
        return
    end

    self.channel = { start = start, finish = finish, interval = interval }
    self:LayoutChannelTicks()
end

-- Pushback shortens the channel; ticks keep their times, so only the end moves.
function TickPulse:OnChannelUpdate()
    if not self.channel then
        return
    end

    local _, start, finish = readChannel()
    if not finish then
        return
    end

    self.channel.start = start
    self.channel.finish = finish
    self:LayoutChannelTicks()
end

events:SetScript("OnEvent", function(_, event)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        TickPulse:OnChannelStart()
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        TickPulse:OnChannelUpdate()
    else
        TickPulse:HideChannelTicks()
    end
end)

events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")

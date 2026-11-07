local _abs    = math.abs
local _ceil   = math.ceil
local _floor  = math.floor
local _huge   = math.huge
local _max    = math.max
local _min    = math.min
local _fmt    = string.format
local _ins    = table.insert
local _rem    = table.remove
local _sort   = table.sort

local MS = _G["MythicScoreboard"]
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local Abbrev, Art, Btn, ClassColor, ClassHex, DN = UI.Abbrev, UI.Art, UI.Btn, UI.ClassColor, UI.ClassHex, UI.DN
local FIGHT_BOT, FIGHT_TOP, FRAME_W, MEDIA, P, PAD_X = UI.FIGHT_BOT, UI.FIGHT_TOP, UI.FRAME_W, UI.MEDIA, UI.P, UI.PAD_X
local Solid, TL_H, Text, Tint, VGrad, WIPE_BOT = UI.Solid, UI.TL_H, UI.Text, UI.Tint, UI.VGrad, UI.WIPE_BOT
local WIPE_TOP = UI.WIPE_TOP

-- Run timeline: track, boss medallions, deaths and interrupts.

-- ===========================================================================
-- Timeline
-- ===========================================================================
-- Layout (y measured from the bottom of the strip):
--   medallion rows  : centre y 162 / 122
--   track           : y 76..90
--   death diamonds  : centre y 58 (red cuts through the track)
--   interrupt chart : y 34..45
--   axis            : ticks y 25..30, labels y 8

local TL_L      = PAD_X
local TL_TRACKW = FRAME_W - 2 - PAD_X * 2
local TL = UI.TL                     -- shared with UI_TimelineLayout.lua
local TRACK_Y, TRACK_H = TL.TRACK_Y, TL.TRACK_H
local MED_R, MED_ROWS  = TL.MED_R, TL.MED_ROWS
local DEATH_Y   = TL.DEATH_Y
local INT_BASE  = TL.INT_BASE
local INT_MAXH  = TL.INT_MAXH
local COMPACT_W = TL.COMPACT_W

local function GetTimelineDuration(r)
    if not r then return 1 end
    local isMPlus = (r.keystoneLevel or 0) > 0
    local dur = 0
    if r.duration then
        dur = r.duration
    elseif not isMPlus then
        -- Untimed live run (Normal/Heroic/etc.): rolling window that grows
        -- in 5-minute steps; UpdateLive asks for a rebuild when it fills up.
        local e = MS:GetRunDuration(r)
        dur = _ceil(_max(e + 180, e * 1.2, 600) / 300) * 300
    elseif tonumber(r.keystoneTimeLimit) and r.keystoneTimeLimit > 0 then
        dur = r.keystoneTimeLimit
    elseif MS:KnownTimeLimit(r) then
        dur = MS:KnownTimeLimit(r)
    end
    if dur <= 0 then dur = _max(1, MS:GetRunDuration(r)) end
    if isMPlus and not r.completed then
        local elapsed = MS:GetRunDuration(r)
        if elapsed >= dur - 15 then dur = _max(elapsed + 5 * 60, 30 * 60) end
    end
    if r.bosses then
        for _, b in ipairs(r.bosses) do
            if b.killTime and b.killTime > dur then dur = b.killTime + 30 end
        end
    end
    if tonumber(r.keystoneTimeLimit) and r.keystoneTimeLimit > 0 then
        dur = _max(dur, r.keystoneTimeLimit)
    end
    if isMPlus and r.completed and MS:KnownTimeLimit(r) then
        dur = _max(dur, MS:KnownTimeLimit(r))
    end
    -- A finished run that ends at the window's edge gets a little empty
    -- track after it, so the completion line doesn't sit on the last boss.
    if r.completed then
        local finish = 0
        for _, b in ipairs(r.bosses or {}) do finish = _max(finish, b.killTime or 0) end
        finish = _max(finish, MS:GetRunDuration(r))
        local room = _max(10, finish * 0.012)
        if dur - finish < room then dur = finish + room end
    end
    return dur
end

local function SegmentLabelFor(run, t)
    if not run.bosses then return nil end
    for _, boss in ipairs(run.bosses) do
        local pullT = boss.pullTime or 0
        local killT = boss.killTime or boss.wipeTime or (t + 1)
        if t >= pullT and t <= killT then
            return (boss.name or "Boss") .. ((boss.wipeTime and not boss.killTime) and " (wipe)" or "")
        end
    end
    return nil
end

local function ShowBossTooltip(owner, boss, run)
    local isWipe = boss.wipeTime and not boss.killTime
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    local tc = isWipe and P.bloodHi or P.bronzeHi
    GameTooltip:SetText((boss.name or "Boss") .. (isWipe and "  (wipe)" or ""), tc[1], tc[2], tc[3])

    local pullT = boss.pullTime or 0
    local endT  = boss.killTime or boss.wipeTime
    GameTooltip:AddLine(" ")
    if endT then
        GameTooltip:AddDoubleLine("Pulled", MS:FormatTime(pullT), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine(isWipe and "Wiped" or "Killed", MS:FormatTime(endT), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Fight length", MS:FormatTime(endT - pullT), 0.8, 0.8, 0.8, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine("Pulled", MS:FormatTime(pullT), 0.8, 0.8, 0.8, 1, 1, 1)
        endT = MS:GetRunDuration(run)
    end
    if boss.pullProgressPct then
        GameTooltip:AddDoubleLine("Enemy forces at pull", _fmt("%d%%", boss.pullProgressPct),
            0.8, 0.8, 0.8, 1, 1, 1)
    end

    if run and run.players then
        local deaths = {}
        for _, p in pairs(run.players) do
            for _, de in ipairs(p.deathEvents or {}) do
                local t = de.time or 0
                if t >= pullT and t <= endT then
                    _ins(deaths, { name = DN(p.name), class = p.class, time = t, spell = de.spell or "Unknown" })
                end
            end
        end
        _sort(deaths, function(a, b) return a.time < b.time end)
        GameTooltip:AddLine(" ")
        if #deaths == 0 then
            GameTooltip:AddLine("No deaths", P.verdHi[1], P.verdHi[2], P.verdHi[3])
        else
            GameTooltip:AddLine("Deaths: " .. #deaths, P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
            for _, d in ipairs(deaths) do
                local line = "  |cff" .. ClassHex(d.class) .. d.name .. "|r  " .. MS:FormatTime(d.time)
                    .. "  |cff999999(" .. MS:FormatTime(d.time - pullT) .. " into the fight)|r"
                if d.spell ~= "Unknown" then line = line .. "  |cffff9944" .. d.spell .. "|r" end
                GameTooltip:AddLine(line, 1, 1, 1)
            end
        end

        local byPlayer, total = {}, 0
        for _, p in pairs(run.players) do
            local cnt = 0
            for _, ie in ipairs(p.interruptEvents or {}) do
                local t = MS.EventTime(ie)
                if t >= pullT and t <= endT then cnt = cnt + 1 end
            end
            if cnt > 0 then
                _ins(byPlayer, { name = DN(p.name), class = p.class, count = cnt })
                total = total + cnt
            end
        end
        if total > 0 then
            _sort(byPlayer, function(a, b) return a.count > b.count end)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Interrupts: " .. total, P.kick[1], P.kick[2], P.kick[3])
            for _, ip in ipairs(byPlayer) do
                GameTooltip:AddLine("  |cff" .. ClassHex(ip.class) .. ip.name .. "|r  " .. ip.count, 1, 1, 1)
            end
        end
    end
    if boss.killTime or boss.wipeTime then
        local shown = UI.focus and UI.focus.boss == boss
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(shown and "Click to see the whole run again" or "Click to see this fight in the table",
            P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
    end
    GameTooltip:Show()
end

-- Builds the static chrome of the timeline strip once (title, legend).
local function BuildTimelineChrome(strip)
    -- Same stone as the rest of the frame: only a light tint, the frame's
    -- grain repeated on top, and a soft shadow under the divider so the
    -- timeline reads as recessed into the slab rather than a separate panel.
    local bg = strip:CreateTexture(nil, "BACKGROUND", nil, 2)
    bg:SetAllPoints()
    VGrad(bg, {0, 0, 0}, {0, 0, 0}, 0.02, 0.10)
    local grain = Art(strip, "Grain", "BACKGROUND", 3, true)
    grain:SetAllPoints(); grain:SetBlendMode("ADD"); grain:SetAlpha(0.5)
    local recess = strip:CreateTexture(nil, "BACKGROUND", nil, 4)
    recess:SetPoint("TOPLEFT", 0, -1); recess:SetPoint("TOPRIGHT", 0, -1); recess:SetHeight(18)
    VGrad(recess, {0, 0, 0}, {0, 0, 0}, 0, 0.35)

    local top = Solid(strip, "BORDER", 0, P.line[1], P.line[2], P.line[3], 1)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)

    local title = Text(strip, "medium", 13, P.ivory)
    title:SetPoint("TOPLEFT", strip, "TOPLEFT", PAD_X, -10)
    title:SetText("Run timeline")
    local live = Text(strip, "medium", 13, P.verd)
    live:SetPoint("LEFT", title, "RIGHT", 10, 0)
    live:SetText("Live")
    live:Hide()
    strip._liveTag = live

    -- Legend, laid out right to left.
    local items = {
        { "Interrupts", function(f)
            local hold = Solid(f, "ARTWORK", 0, 0, 0, 0, 0); hold:SetSize(14, 9)
            for i, h in ipairs({ 4, 9, 6 }) do
                local b = Solid(f, "ARTWORK", 1, P.kick[1], P.kick[2], P.kick[3], 0.5 + h / 18)
                b:SetSize(3, h); b:SetPoint("BOTTOMLEFT", hold, "BOTTOMLEFT", (i - 1) * 5, 0)
            end
            return hold end },
        { "Death", function(f)
            local r = Art(f, "Diamond", "ARTWORK", 0); r:SetSize(12, 12); Tint(r, P.bronzeHi)
            local d = Art(f, "Diamond", "ARTWORK", 1); d:SetSize(8, 8); d:SetPoint("CENTER", r)
            Tint(d, { 0.62, 0.15, 0.13 })
            return r end },
        { "Wipe", function(f) local t = f:CreateTexture(nil, "ARTWORK"); t:SetSize(16, 8); VGrad(t, WIPE_BOT, WIPE_TOP); return t end },
        { "Trash", function(f)
            local b = Solid(f, "ARTWORK", 0, 0.16, 0.14, 0.12, 1); b:SetSize(16, 8)
            local h = Art(f, "Hatch", "ARTWORK", 1, true); h:SetAllPoints(b); h:SetVertexColor(0.225, 0.195, 0.165, 1)
            return b end },
        { "Boss", function(f) local t = f:CreateTexture(nil, "ARTWORK"); t:SetSize(16, 8); VGrad(t, FIGHT_BOT, FIGHT_TOP); return t end },
    }
    local anchor, anchorPt, gap = strip, "TOPRIGHT", -20
    for _, it in ipairs(items) do
        local lbl = Text(strip, "regular", 12, P.ash)
        lbl:SetText(it[1])
        if anchor == strip then
            lbl:SetPoint("TOPRIGHT", strip, "TOPRIGHT", gap, -11)
        else
            lbl:SetPoint("RIGHT", anchor, "LEFT", -16, 0)
        end
        local sw = it[2](strip)
        sw:SetPoint("RIGHT", lbl, "LEFT", -6, 0)
        anchor = sw
    end
end

-- ── Reusing the pieces ─────────────────────────────────────────────────────
-- The game never frees a texture, text or frame once made, so the timeline
-- doesn't make new ones on each redraw: every piece is kept in a pool by what
-- it is (kind, art, layer, font), handed out again on the next redraw with
-- everything a previous use may have changed put back, and whatever isn't
-- needed this time is hidden.
--
-- A redraw costs one call into the game per change, so the pool does as few
-- as it can: a piece is hidden only when this redraw didn't use it, and a
-- texture remembers which of its settings were changed (alpha, colour,
-- blend, desaturation, tex coords) so only those are put back. Whether a
-- piece is shown, and its parent, are always set again on reuse: drawing
-- code changes both directly (a compact label hides its second line).
local function NewPools() return { byKey = {} } end

local function StartPools(pools)
    for _, list in pairs(pools.byKey) do list.n = 0 end
end

-- After the steps: what this redraw didn't use is hidden.
local function FinishPools(pools)
    for _, list in pairs(pools.byKey) do
        for i = list.n + 1, #list do
            local obj = list[i]
            if not obj._msOff then obj:Hide(); obj._msOff = true end
        end
    end
end

local TRACKED = {
    SetAlpha       = { 1 },
    SetVertexColor = { 1, 1, 1, 1 },
    SetBlendMode   = { "BLEND" },
    SetDesaturated = { false },
    SetTexCoord    = { 0, 1, 0, 1 },
}
-- Each tracked setter notes that it was used, then does its job.
local function Track(t)
    if t._msOrig then return t end
    t._msOrig, t._msDirty = {}, {}
    for name in pairs(TRACKED) do
        local orig = t[name]
        if orig then
            t._msOrig[name] = orig
            t[name] = function(self, ...) self._msDirty[name] = true; return orig(self, ...) end
        end
    end
    return t
end

local function ResetTexture(t, raw)
    t:ClearAllPoints()
    local dirty, orig = t._msDirty, t._msOrig
    for name, d in pairs(TRACKED) do
        -- (a tiled texture keeps its tex coords; they're its tiling)
        if dirty[name] and not (name == "SetTexCoord" and t._tilePx and not raw) then
            orig[name](t, unpack(d))
            dirty[name] = nil
        end
    end
    if raw then
        t:SetTexture(nil)
        local n = t.GetNumMaskTextures and t:GetNumMaskTextures() or 0
        for i = n, 1, -1 do t:RemoveMaskTexture(t:GetMaskTexture(i)) end
    end
end

-- The next free piece for key, moved onto parent; nil when one must be made.
local function Take(pools, key, parent)
    local list = pools.byKey[key]
    if not list then list = { n = 0 }; pools.byKey[key] = list end
    local i = list.n + 1
    local obj = list[i]
    if not obj then return nil, list end
    list.n = i
    -- Asked of the game each time, not remembered: the drawing code hides
    -- labels and moves them onto their medallion itself.
    if obj:GetParent() ~= parent then obj:SetParent(parent) end
    obj:Show(); obj._msOff = nil
    return obj, list
end

local function Keep(list, obj, parent)
    list.n = list.n + 1
    list[list.n] = obj
    if obj.SetTexCoord and obj.SetVertexColor then Track(obj) end   -- textures
    return obj
end

-- ── One redraw ─────────────────────────────────────────────────────────────
-- A redraw is a sequence of steps (track, axis, bosses, the end of the run,
-- key timer, completion, deaths, interrupts, live head), each its own
-- function below. What they share is set up once per redraw in the context:
-- the canvas, the time-to-x scale, pooled pieces and the drawing helpers,
-- and where the run ends on screen.
local function NewContext(strip, run, totalDur)
    -- One canvas for the life of the window; its pieces are reused.
    local cv = strip._canvas
    if not cv then
        cv = CreateFrame("Frame", nil, strip)
        cv:SetAllPoints(strip)
        cv:SetFrameLevel(strip:GetFrameLevel() + 1)
        strip._canvas = cv
        strip._pools = NewPools()
    end
    cv:Show()
    local pools = strip._pools
    StartPools(pools)

    -- Same calls as the shared helpers, drawing from the pools.
    local Solid0, Art0, Text0, Btn0 = Solid, Art, Text, Btn
    local function Solid(parent, layer, sub, r, g, b, a)
        local key = "S" .. (layer or "") .. (sub or 0)
        local t, list = Take(pools, key, parent)
        if not t then return Keep(list, Solid0(parent, layer, sub, r, g, b, a), parent) end
        ResetTexture(t)
        t:SetColorTexture(r, g, b, a or 1)
        return t
    end
    local function Art(parent, file, layer, sub, tile)
        local key = "A" .. file .. (layer or "") .. (sub or 0) .. (tile and "t" or "")
        local t, list = Take(pools, key, parent)
        if not t then return Keep(list, Art0(parent, file, layer, sub, tile), parent) end
        ResetTexture(t)
        return t
    end
    local function Tex(parent, layer, sub)
        local key = "T" .. (layer or "") .. (sub or 0)
        local t, list = Take(pools, key, parent)
        if not t then return Keep(list, parent:CreateTexture(nil, layer, nil, sub), parent) end
        ResetTexture(t, true)
        return t
    end
    local function Mask(parent)
        local m, list = Take(pools, "M", parent)
        if not m then return Keep(list, parent:CreateMaskTexture(), parent) end
        m:ClearAllPoints()
        return m
    end
    local function Text(parent, kind, size, col, justify)
        local key = "F" .. kind .. size
        local fs, list = Take(pools, key, parent)
        if not fs then return Keep(list, Text0(parent, kind, size, col, justify), parent) end
        fs:ClearAllPoints()
        col = col or P.ivory
        fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false); fs:SetMaxLines(0)
        fs:SetWidth(0); fs:SetHeight(0)
        fs:SetAlpha(1)
        fs:SetText("")
        return fs
    end
    local function Btn(parent)
        local b, list = Take(pools, "B", parent)
        if not b then return Keep(list, Btn0(parent), parent) end
        b:ClearAllPoints()
        b:SetAlpha(1)
        b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil); b:SetScript("OnClick", nil)
        b:EnableMouse(true)
        return b
    end

    if not (totalDur and totalDur > 0) then return nil end

    local W  = TL_TRACKW
    local isMPlus = (run.keystoneLevel or 0) > 0
    -- Only the run in progress (or paused) is drawn live. A saved run that
    -- wasn't cleared is finished too: drawn still, to where it ended.
    local live = not run.completed and run == MS.currentRun

    local function X(t) return TL_L + _max(0, _min(1, t / totalDur)) * W end

    local function At(region, point, x, y)
        region:SetPoint(point, cv, "BOTTOMLEFT", x, y)
    end

    local function Weather(x, w, sub)
        local grit = Art(cv, "Grit", "ARTWORK", sub, true)
        grit:SetBlendMode("MOD")
        grit:SetSize(_max(1, w), TRACK_H); At(grit, "BOTTOMLEFT", x, TRACK_Y)
        local groove = Tex(cv, "ARTWORK", sub)
        groove:SetSize(_max(1, w), 4); At(groove, "BOTTOMLEFT", x, TRACK_Y + TRACK_H - 4)
        VGrad(groove, {0, 0, 0}, {0, 0, 0}, 0, 0.55)
        return grit
    end
    local function Seg(t1, t2, kind)
        local x1, x2 = X(t1), X(t2)
        local w = x2 - x1
        if w < 1 then return nil end
        local tex
        if kind == "trash" then
            local base = Solid(cv, "ARTWORK", 0, 0.16, 0.14, 0.12, 1)
            base:SetSize(_max(1, w - 1), TRACK_H); At(base, "BOTTOMLEFT", x1, TRACK_Y)
            tex = Art(cv, "Hatch", "ARTWORK", 1, true)
            tex:SetVertexColor(0.225, 0.195, 0.165, 1)
            tex:SetSize(_max(1, w - 1), TRACK_H); At(tex, "BOTTOMLEFT", x1, TRACK_Y)
            Weather(x1, w - 1, 2)
            return base
        end
        tex = Tex(cv, "ARTWORK", 2)
        tex:SetSize(_max(1, w), TRACK_H); At(tex, "BOTTOMLEFT", x1, TRACK_Y)
        if kind == "fight" then
            VGrad(tex, FIGHT_BOT, FIGHT_TOP)
        elseif kind == "wipe" then
            VGrad(tex, WIPE_BOT, WIPE_TOP)
        elseif kind == "spare" then
            VGrad(tex, {0.30, 0.34, 0.20}, {0.60, 0.68, 0.42}, 0.25, 0.45)
        elseif kind == "over" then
            VGrad(tex, {0.40, 0.05, 0.05}, {0.75, 0.15, 0.13}, 0.75, 0.75)
        end
        if kind ~= "fight" then Weather(x1, w, 3) end
        if kind == "fight" or kind == "wipe" then
            local sheen = Solid(cv, "ARTWORK", 3, 1, 0.95, 0.85, 0.35)
            sheen:SetSize(_max(1, w), 1); At(sheen, "BOTTOMLEFT", x1, TRACK_Y + TRACK_H - 1)
        end
        return tex
    end

    local function SegButton(t1, t2, onEnter)
        local x1, x2 = X(t1), X(t2)
        if x2 - x1 < 3 then return end
        local b = Btn(cv)
        b:SetSize(x2 - x1, TRACK_H + 8)
        At(b, "BOTTOMLEFT", x1, TRACK_Y - 4)
        b:SetFrameLevel(cv:GetFrameLevel() + 3)
        b:SetScript("OnEnter", onEnter)
        b:SetScript("OnLeave", GameTooltip_Hide)
        return b
    end

    -- A label inside a segment. Boss fights too short to hold one get it
    -- just under the bar instead (skipped where it would overlap another).
    local belowRight = -math.huge
    local function InBarText(t1, t2, text, col, belowCol)
        local w = X(t2) - X(t1)
        local fs = Text(cv, "semibold", 11, col, "CENTER")
        fs:SetText(text)
        if fs:GetStringWidth() + 8 <= w then
            At(fs, "CENTER", (X(t1) + X(t2)) / 2, TRACK_Y + TRACK_H / 2)
            return
        end
        fs:Hide()
        if not belowCol then return end
        local small = Text(cv, "semibold", 10, belowCol, "CENTER")
        small:SetText(text)
        local cx, half = (X(t1) + X(t2)) / 2, small:GetStringWidth() / 2
        if cx - half < belowRight + 4 then small:Hide(); return end
        belowRight = cx + half
        At(small, "CENTER", cx, TRACK_Y - 8)
    end

    local function CountDeaths(t1, t2)
        local n = 0
        for _, p in pairs(run.players or {}) do
            for _, de in ipairs(p.deathEvents or {}) do
                local dt = de.time or 0
                if dt >= t1 and dt <= t2 then n = n + 1 end
            end
        end
        return n
    end

    local keyLimit = tonumber(run.keystoneTimeLimit)
    if keyLimit and keyLimit <= 0 then keyLimit = nil end

    -- Where the run ends on screen.
    --   compSec   : the moment the run was finished (completion marker)
    --   visualEnd : how far the drawn segments go
    --   clampT    : Mythic+ only. The final ENCOUNTER_END can be logged after
    --               the key completed; clamp to the key time so the bar, the
    --               spare time and the header all agree.
    local compSec, visualEnd, clampT
    if run.completed then
        local runEnd = run.duration
        if isMPlus and runEnd then
            compSec, visualEnd, clampT = runEnd, runEnd, runEnd
        else
            for _, b in ipairs(run.bosses or {}) do
                if b.killTime and b.killTime > (compSec or 0) then compSec = b.killTime end
            end
            visualEnd = _max(runEnd or 0, compSec or 0)
            compSec = compSec or runEnd
        end
        if compSec and compSec <= 0 then compSec = nil end
        if visualEnd and visualEnd <= 0 then visualEnd = nil end
    elseif not live then
        local runEnd = MS:GetRunDuration(run)
        if runEnd and runEnd > 0 then visualEnd = runEnd end
    end

    return {
        cv = cv, run = run, totalDur = totalDur, W = W, isMPlus = isMPlus, live = live, X = X, At = At,
        Solid = Solid, Art = Art, Tex = Tex, Mask = Mask, Text = Text, Btn = Btn,
        Seg = Seg, SegButton = SegButton, InBarText = InBarText, CountDeaths = CountDeaths, Weather = Weather,
        keyLimit = keyLimit, compSec = compSec, visualEnd = visualEnd, clampT = clampT,
    }
end

-- Each step takes what it needs from the context.

-- ── Track base ─────────────────────────────────────────────────────────────
local function DrawTrack(c)
    local cv, W, At, Solid, Art, Tex = c.cv, c.W, c.At, c.Solid, c.Art, c.Tex
    local trackBorder = Solid(cv, "BACKGROUND", 3, 0.04, 0.03, 0.03, 1)
    trackBorder:SetSize(W + 2, TRACK_H + 2); At(trackBorder, "BOTTOMLEFT", TL_L - 1, TRACK_Y - 1)
    local trackFill = Solid(cv, "BACKGROUND", 4, 0.09, 0.075, 0.06, 1)
    trackFill:SetSize(W, TRACK_H); At(trackFill, "BOTTOMLEFT", TL_L, TRACK_Y)

    -- Weathering (multiplied, so it only darkens) and a carved-groove shadow
    -- along the top edge. Applied to the empty track bed here and to each
    local bedGrit = Art(cv, "Grit", "BACKGROUND", 5, true)
    bedGrit:SetBlendMode("MOD")
    bedGrit:SetSize(W, TRACK_H); At(bedGrit, "BOTTOMLEFT", TL_L, TRACK_Y)
    local bedGroove = Tex(cv, "BACKGROUND", 6)
    bedGroove:SetSize(W, 4); At(bedGroove, "BOTTOMLEFT", TL_L, TRACK_Y + TRACK_H - 4)
    VGrad(bedGroove, {0, 0, 0}, {0, 0, 0}, 0, 0.55)
    local grooveLip = Solid(cv, "ARTWORK", 6, 1, 0.9, 0.75, 0.06)
    grooveLip:SetSize(W + 2, 1); At(grooveLip, "BOTTOMLEFT", TL_L - 1, TRACK_Y - 2)
end

-- ── Axis ───────────────────────────────────────────────────────────────────
-- Labels near the completion time are dropped (it's printed there).
local function DrawAxis(c)
    local cv, totalDur, W, X, At, Solid = c.cv, c.totalDur, c.W, c.X, c.At, c.Solid
    local Text, compSec = c.Text, c.compSec
    local skipX = compSec and X(compSec)
    local function clear(x) return not skipX or _abs(x - skipX) > 38 end
    local tickInterval
    if     totalDur <= 3*60  then tickInterval = 30
    elseif totalDur <= 8*60  then tickInterval = 60
    elseif totalDur <= 15*60 then tickInterval = 2*60
    else                          tickInterval = 5*60 end
    local t = 0
    while t <= totalDur + 0.5 do
        local x = X(t)
        local tk = Solid(cv, "ARTWORK", 0, P.ash2[1], P.ash2[2], P.ash2[3], 1)
        tk:SetSize(1, 5); At(tk, "BOTTOMLEFT", _floor(x), 25)
        if x > TL_L + 30 and x < TL_L + W - 40 and clear(x) then
            local lbl = Text(cv, "regular", 12, P.ash, "CENTER")
            At(lbl, "BOTTOM", x, 8); lbl:SetText(MS:FormatTime(t))
        end
        t = t + tickInterval
    end
    if clear(TL_L + 12) then
        local t0 = Text(cv, "regular", 12, P.ash, "LEFT"); At(t0, "BOTTOMLEFT", TL_L, 8); t0:SetText("0:00")
    end
    if clear(TL_L + W - 14) then
        local tE = Text(cv, "regular", 12, P.ash, "RIGHT"); At(tE, "BOTTOMRIGHT", TL_L + W, 8)
        tE:SetText(MS:FormatTime(totalDur))
    end
end

-- ── Segments + medallions ─────────────────────────────────────────────────
-- Returns where the drawn track ends and what is still going on there.
-- ── Medallions: labels measured, then placed ──────────────────────────────
-- Returns which bosses get no medallion of their own (wipes before a later
-- kill) and, for the rest, their labels and placement.
local function PlaceMedallions(c)
    local cv, run, X, Text, clampT = c.cv, c.run, c.X, c.Text, c.clampT
    -- A wipe followed later by a kill of the same boss shows only as its red
    -- segment; the kill's label mentions the wipes. Keeps retries from
    -- crowding the medallion rows.
    local superseded, wipesBefore, pendingWipes = {}, {}, {}
    for i, b in ipairs(run.bosses or {}) do
        local nm = b.name or "Boss"
        if b.wipeTime and not b.killTime then
            pendingWipes[nm] = pendingWipes[nm] or {}
            _ins(pendingWipes[nm], i)
        elseif b.killTime and pendingWipes[nm] then
            for _, j in ipairs(pendingWipes[nm]) do superseded[j] = true end
            wipesBefore[i] = #pendingWipes[nm]
            pendingWipes[nm] = nil
        end
    end

    -- ── Medallion placement (before drawing) ─────────────────────────────
    -- Labels are measured first, then placed by priority: the final kill
    -- claims its spot first so the run's last boss never loses its label,
    -- then everything else in time order.
    local medInfo, order = {}, {}
    local lastKillBi, lastKillT = nil, -1
    for bi, boss in ipairs(run.bosses or {}) do
        if not superseded[bi] then
            local pullT = boss.pullTime or 0
            local endT  = boss.killTime or boss.wipeTime or pullT
            if clampT then pullT = _min(pullT, clampT); endT = _min(endT, clampT) end
            local isWipe = boss.wipeTime and not boss.killTime
            local name = Text(cv, "game", 13, isWipe and P.bloodHi or P.ivory)
            name:SetText(boss.name or "Boss")
            local sub = Text(cv, "regular", 12, P.ash)
            if isWipe then sub:SetText("Wipe at " .. MS:FormatTime(endT))
            elseif boss.killTime then
                local w = wipesBefore[bi]
                sub:SetText("Killed at " .. MS:FormatTime(endT)
                    .. (w and (" after " .. w .. (w == 1 and " wipe" or " wipes")) or ""))
            else sub:SetText("In combat") end
            medInfo[bi] = { mx = (X(pullT) + X(endT)) / 2, name = name, sub = sub,
                            lblW = _max(name:GetStringWidth(), sub:GetStringWidth()) }
            if boss.killTime and boss.killTime > lastKillT then lastKillBi, lastKillT = bi, boss.killTime end
            _ins(order, bi)
        end
    end
    if lastKillBi then
        for i, bi in ipairs(order) do
            if bi == lastKillBi then _rem(order, i); _ins(order, 1, bi); break end
        end
    end
    -- Where each goes: UI_TimelineLayout.lua.
    for _, bi in ipairs(order) do
        local info = medInfo[bi]
        info.compW = _min(info.name:GetStringWidth(), COMPACT_W)
    end
    local bestPlan = UI.PlaceMedallions(medInfo, order, tostring(run))
    UI._medLayout = {}     -- for tests: what was placed where
    for _, bi in ipairs(order) do
        local p = bestPlan[bi]
        local info = medInfo[bi]
        _ins(UI._medLayout, { name = info.name:GetText(), row = p.row, cx = p.cx, x1 = p.x1, x2 = p.x2, mx = info.mx,
                              bare = p.mode.bare, compact = p.mode.compact, left = p.mode.left, elbow = p.elbow,
                              sub = info.sub:GetText() })
        info.row, info.cx, info.elbow = p.row, p.cx, p.elbow
        info.bare = p.mode.bare
        info.labelLeft = p.mode.left and true or false
        info.compact = p.mode.compact
    end
    return superseded, medInfo
end

-- One boss's medallion: stem, portrait, ring, label, and its handlers.
local function DrawMedallion(c, boss, info, pullT, endT, isWipe)
    local cv, run, X, At, Solid, Art = c.cv, c.run, c.X, c.At, c.Solid, c.Art
    local Tex, Mask, Btn = c.Tex, c.Mask, c.Btn
    local mx    = (X(pullT) + X(endT)) / 2
    local ringC = isWipe and P.blood or P.bronzeHi

    local name, sub = info.name, info.sub
    local row, labelLeft = info.row, info.labelLeft
    local bare = info.bare
    if bare then name:Hide(); sub:Hide() end
    local cy = MED_ROWS[row]

    local cx = info.cx or mx
    local stemC = isWipe and P.blood or P.bronze
    local top = TRACK_Y + TRACK_H
    local function StemPiece(w, h, x, y)
        local t = Solid(cv, "ARTWORK", 0, stemC[1], stemC[2], stemC[3], 0.55)
        t:SetSize(w, h); At(t, "BOTTOMLEFT", x, y)
    end
    if math.abs(cx - mx) < 1 then
        StemPiece(1, cy - MED_R - top, _floor(mx), top)
    else
        -- Moved aside: up from the fight, across, then up to the medallion.
        local elbow = info.elbow or (top + 7)
        StemPiece(1, elbow - top, _floor(mx), top)
        StemPiece(math.abs(_floor(cx) - _floor(mx)) + 1, 1, _min(_floor(mx), _floor(cx)), elbow)
        StemPiece(1, cy - MED_R - elbow, _floor(cx), elbow)
    end

    local med = Btn(cv)
    med:SetSize(MED_R * 2 + 6, MED_R * 2 + 6)
    At(med, "CENTER", cx, cy)
    med:SetFrameLevel(cv:GetFrameLevel() + 4)

    local halo = Art(med, "Glow", "BACKGROUND", 0)
    halo:SetBlendMode("ADD"); halo:SetSize(84, 84); halo:SetPoint("CENTER")
    Tint(halo, ringC, 0)

    local shadow = Art(med, "Disc", "BACKGROUND", 1)
    shadow:SetSize(MED_R * 2 + 6, MED_R * 2 + 6); shadow:SetPoint("CENTER", 0, -1)
    Tint(shadow, {0, 0, 0}, 0.9)

    local portrait = Tex(med, "ARTWORK", 0)
    portrait:SetSize(MED_R * 2 - 4, MED_R * 2 - 4); portrait:SetPoint("CENTER")
    local function Circle()
        local mask = Mask(med)
        mask:SetTexture(MEDIA .. "CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(portrait)
        portrait:AddMaskTexture(mask)
        if isWipe then portrait:SetDesaturated(true); portrait:SetVertexColor(0.9, 0.6, 0.6) end
    end
    local kind, art = MS:BossPortrait(boss, run)       -- Portraits.lua
    local drawn = false
    if kind == "icon" then
        portrait:SetTexture(art)
        portrait:SetTexCoord(0.25, 0.75, 0.0, 1.0)
        Circle(); drawn = true
    elseif kind == "display" and SetPortraitTextureFromCreatureDisplayID then
        drawn = pcall(SetPortraitTextureFromCreatureDisplayID, portrait, art)
        if drawn then Circle() end
    elseif kind == "file" then
        portrait:SetTexture(art)
        portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        Circle(); drawn = true
    end
    if not drawn then
        portrait:SetTexture(MEDIA .. "Crest")
        if isWipe then portrait:SetVertexColor(1, 0.55, 0.5) end
    end

    local ring = Art(med, "Ring", "OVERLAY", 0)
    ring:SetSize(MED_R * 2 + 4, MED_R * 2 + 4); ring:SetPoint("CENTER")
    Tint(ring, ringC)

    name:ClearAllPoints(); sub:ClearAllPoints()
    name:SetParent(med); sub:SetParent(med)
    if info.compact and not bare then
        -- Compact: the name alone, wrapped onto two lines.
        sub:Hide()
        name:SetWidth(COMPACT_W); name:SetWordWrap(true); name:SetMaxLines(2)
        if labelLeft then
            name:SetPoint("RIGHT", med, "LEFT", -5, 0); name:SetJustifyH("RIGHT")
        else
            name:SetPoint("LEFT", med, "RIGHT", 5, 0); name:SetJustifyH("LEFT")
        end
    elseif labelLeft then
        name:SetPoint("BOTTOMRIGHT", med, "LEFT", -5, 1)
        sub:SetPoint("TOPRIGHT", med, "LEFT", -5, -1)
        name:SetJustifyH("RIGHT"); sub:SetJustifyH("RIGHT")
    else
        name:SetPoint("BOTTOMLEFT", med, "RIGHT", 5, 1)
        sub:SetPoint("TOPLEFT", med, "RIGHT", 5, -1)
    end

    local focused = UI.focus and UI.focus.boss == boss
    Tint(halo, ringC, focused and 0.55 or 0)
    med:SetScript("OnEnter", function(self2)
        halo:SetAlpha(1); Tint(halo, ringC, 0.55)
        ShowBossTooltip(self2, boss, run)
    end)
    med:SetScript("OnLeave", function()
        Tint(halo, ringC, focused and 0.55 or 0)
        GameTooltip:Hide()
    end)
    med:SetScript("OnClick", function() UI.FocusBoss(run, boss) end)
end

-- ── Segments + medallions ─────────────────────────────────────────────────
-- Returns where the drawn track ends and what is still going on there.
local function DrawBosses(c)
    local cv, run, live, X, At, Solid = c.cv, c.run, c.live, c.X, c.At, c.Solid
    local Art, Seg, SegButton, InBarText, CountDeaths, clampT = c.Art, c.Seg, c.SegButton, c.InBarText, c.CountDeaths, c.clampT
    local prevT = 0
    local liveKind = "trash"
    local superseded, medInfo = PlaceMedallions(c)

    for bi, boss in ipairs(run.bosses or {}) do
        local pullT  = boss.pullTime or 0
        local isWipe = boss.wipeTime and not boss.killTime
        local active = not boss.killTime and not boss.wipeTime and live
        -- An in-progress fight is drawn by UpdateLive so it can grow.
        local endT   = boss.killTime or boss.wipeTime or pullT
        if clampT then
            pullT = _min(pullT, clampT)
            endT  = _min(endT, clampT)
        end

        -- Trash leading up to the pull
        if pullT > prevT then
            Seg(prevT, pullT, "trash")
            local tStart = prevT
            local pct = boss.pullProgressPct
            SegButton(tStart, pullT, function(self2)
                GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                GameTooltip:SetText("Trash", P.ivory[1], P.ivory[2], P.ivory[3])
                GameTooltip:AddDoubleLine("Duration", MS:FormatTime(pullT - tStart), 0.8, 0.8, 0.8, 1, 1, 1)
                if pct then GameTooltip:AddDoubleLine("Enemy forces at pull", _fmt("%d%%", pct), 0.8, 0.8, 0.8, 1, 1, 1) end
                local d = CountDeaths(tStart, pullT)
                if d > 0 then GameTooltip:AddDoubleLine("Deaths", d, 0.8, 0.8, 0.8, P.bloodHi[1], P.bloodHi[2], P.bloodHi[3]) end
                GameTooltip:Show()
            end)
            local trashTxt = MS:FormatTime(pullT - tStart)
            if pct then trashTxt = trashTxt .. "   " .. _floor(pct) .. "%" end
            InBarText(tStart, pullT, trashTxt, {0.62, 0.57, 0.50})
        end

        -- The fight itself, with a soft glow behind kills
        if endT > pullT then
            local mid = (X(pullT) + X(endT)) / 2
            if not isWipe then
                local glow = Art(cv, "Glow", "BACKGROUND", 5)
                glow:SetBlendMode("ADD")
                Tint(glow, P.bronzeHi, 0.45)
                glow:SetSize(X(endT) - X(pullT) + 30, 40)
                At(glow, "CENTER", mid, TRACK_Y + TRACK_H / 2)
            end
            Seg(pullT, endT, isWipe and "wipe" or "fight")
            if not active then
                InBarText(pullT, endT, MS:FormatTime(endT - pullT), isWipe and {1, 0.88, 0.85} or P.dark,
                    isWipe and P.blood or P.bronzeHi)
            end
            local sb = SegButton(pullT, endT, function(self2) ShowBossTooltip(self2, boss, run) end)
            if sb then sb:SetScript("OnClick", function() UI.FocusBoss(run, boss) end) end
            -- The fight shown in the table gets a bright frame.
            if UI.focus and UI.focus.boss == boss then
                local w = _max(2, X(endT) - X(pullT))
                for _, y in ipairs({ TRACK_Y - 3, TRACK_Y + TRACK_H + 1 }) do
                    local edge = Solid(cv, "OVERLAY", 3, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 1)
                    edge:SetSize(w + 4, 2); At(edge, "BOTTOMLEFT", X(pullT) - 2, y)
                end
                for _, x in ipairs({ X(pullT) - 2, X(pullT) + w }) do
                    local edge = Solid(cv, "OVERLAY", 3, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 1)
                    edge:SetSize(2, TRACK_H + 6); At(edge, "BOTTOMLEFT", x, TRACK_Y - 3)
                end
            end
        end

        if not superseded[bi] then DrawMedallion(c, boss, medInfo[bi], pullT, endT, isWipe) end

        if active then
            prevT, liveKind = pullT, "fight"
        else
            prevT = _max(prevT, endT)
        end
    end
    return prevT, liveKind
end

-- ── Tail of the run ────────────────────────────────────────────────────────
-- Returns the growing segment of a live run, if there is one.
local function DrawTail(c, prevT, liveKind)
    local cv, run, isMPlus, live, Solid, Art = c.cv, c.run, c.isMPlus, c.live, c.Solid, c.Art
    local Tex, Seg, SegButton, InBarText, keyLimit, visualEnd = c.Tex, c.Seg, c.SegButton, c.InBarText, c.keyLimit, c.visualEnd
    local liveSeg
    if visualEnd then
        if visualEnd > prevT then
            Seg(prevT, visualEnd, "trash")
            local tStart = prevT
            local lastPct = (run.bosses and #run.bosses > 0) and run.bosses[#run.bosses].progressPct or 0
            local txt = MS:FormatTime(visualEnd - tStart)
            if isMPlus and run.inTime and (lastPct or 0) < 100 then txt = txt .. "   100%" end
            InBarText(tStart, visualEnd, txt, {0.62, 0.57, 0.50})
            SegButton(tStart, visualEnd, function(self2)
                GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                GameTooltip:SetText("Trash", P.ivory[1], P.ivory[2], P.ivory[3])
                GameTooltip:AddDoubleLine("Duration", MS:FormatTime(visualEnd - tStart), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:Show()
            end)
        end
        if isMPlus and keyLimit then
            if run.inTime and keyLimit > visualEnd then
                Seg(visualEnd, keyLimit, "spare")
                InBarText(visualEnd, keyLimit, MS:FormatTime(keyLimit - visualEnd) .. " spare", P.verdHi)
            elseif not run.inTime and visualEnd > keyLimit then
                Seg(keyLimit, visualEnd, "over")
            end
        end
    elseif live then
        -- Growing segment from the last event to "now": hatched trash, or a
        -- lit bronze bar while a boss is engaged.
        liveSeg = {}
        if liveKind == "fight" then
            local t1 = Tex(cv, "ARTWORK", 2)
            VGrad(t1, FIGHT_BOT, FIGHT_TOP)
            liveSeg[1] = t1
        else
            liveSeg[1] = Solid(cv, "ARTWORK", 0, 0.16, 0.14, 0.12, 1)
            local h = Art(cv, "Hatch", "ARTWORK", 1, true)
            h:SetVertexColor(0.225, 0.195, 0.165, 1)
            liveSeg[2] = h
            local g = Art(cv, "Grit", "ARTWORK", 2, true)
            g:SetBlendMode("MOD")
            liveSeg[3] = g
        end
        for _, tx in ipairs(liveSeg) do tx:SetHeight(TRACK_H); tx:Hide() end
    end
    return liveSeg
end

-- ── Key timer marker (Mythic+ only) ───────────────────────────────────────
local function DrawKeyTimer(c)
    local cv, run, isMPlus, X, At, Solid = c.cv, c.run, c.isMPlus, c.X, c.At, c.Solid
    local Btn, keyLimit = c.Btn, c.keyLimit
    if isMPlus and keyLimit then
        local kx = X(keyLimit)
        local runDur = MS:GetRunDuration(run)
        local inTime = run.completed and run.inTime or (not run.completed and runDur <= keyLimit)
        local kc = inTime and P.ash2 or P.blood
        local kl = Solid(cv, "OVERLAY", 0, kc[1], kc[2], kc[3], 1)
        kl:SetSize(2, TL_H - 30 - TRACK_Y + 6)
        At(kl, "BOTTOMLEFT", _floor(kx) - 1, TRACK_Y - 6)
        local kb = Btn(cv)
        kb:SetSize(12, TL_H - 30 - TRACK_Y + 6)
        At(kb, "BOTTOMLEFT", kx - 6, TRACK_Y - 6)
        kb:SetFrameLevel(cv:GetFrameLevel() + 5)
        kb:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_TOP")
            GameTooltip:SetText("Key timer", P.ivory[1], P.ivory[2], P.ivory[3])
            GameTooltip:AddLine(MS:FormatTime(keyLimit), 1, 1, 1)
            local penalty = run.deathPenaltySeconds or 0
            if penalty > 0 then
                local deaths = 0
                for _, p in pairs(run.players or {}) do deaths = deaths + (p.deaths or 0) end
                GameTooltip:AddLine(_fmt("-%s score penalty (%d death%s)", MS:FormatTime(penalty),
                    deaths, deaths == 1 and "" or "s"), P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
            end
            if runDur > 0 then
                local diff = _abs(runDur - keyLimit)
                if inTime then
                    GameTooltip:AddLine("In time by " .. MS:FormatTime(diff), P.verdHi[1], P.verdHi[2], P.verdHi[3])
                else
                    GameTooltip:AddLine("Over by " .. MS:FormatTime(diff), P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
                end
            end
            GameTooltip:Show()
        end)
        kb:SetScript("OnLeave", GameTooltip_Hide)
    end
end

-- ── Completion marker: a line from the track down to the axis, with ──
-- ── the finishing time printed on the axis itself ────────────────────
local function DrawCompletion(c)
    local cv, run, W, isMPlus, X, At = c.cv, c.run, c.W, c.isMPlus, c.X, c.At
    local Solid, Art, Text, Btn, keyLimit, compSec = c.Solid, c.Art, c.Text, c.Btn, c.keyLimit, c.compSec
    if compSec then
        local fx = X(compSec)
        -- Finished on a boss kill: stand just clear of that boss's block
        -- (and the fight length under it) rather than on its edge.
        for _, b in ipairs(run.bosses or {}) do
            if b.killTime and math.abs(b.killTime - compSec) < 2 then
                -- A narrow block's fight length sticks out past it (about
                -- 13px either side of its middle): clear that too.
                local half = (X(b.killTime) - X(b.pullTime or b.killTime)) / 2
                fx = _min(fx + _max(6, 16 - half), TL_L + W - 1)
                break
            end
        end
        local fc = (isMPlus and not run.inTime) and P.avoid or P.verd

        local line = Solid(cv, "OVERLAY", 1, fc[1], fc[2], fc[3], 1)
        line:SetSize(2, TRACK_Y + TRACK_H + 4 - 22)
        At(line, "BOTTOMLEFT", _floor(fx) - 1, 22)
        local cap = Art(cv, "Diamond", "OVERLAY", 2)
        cap:SetSize(10, 10); Tint(cap, fc)
        At(cap, "CENTER", _floor(fx), TRACK_Y + TRACK_H + 4)
        local glow = Art(cv, "Glow", "BACKGROUND", 6)
        glow:SetBlendMode("ADD"); glow:SetSize(26, 60); Tint(glow, fc, 0.35)
        At(glow, "CENTER", fx, TRACK_Y + TRACK_H / 2)

        local ft = Text(cv, "semibold", 13, fc, "CENTER")
        ft:SetText(MS:FormatTime(compSec))
        local half = ft:GetStringWidth() / 2
        local lx = _max(TL_L + half, _min(TL_L + W - half, fx))
        At(ft, "BOTTOM", lx, 7)

        local fb = Btn(cv)
        fb:SetSize(14, TRACK_Y + TRACK_H + 8 - 4)
        At(fb, "BOTTOMLEFT", fx - 7, 4)
        fb:SetFrameLevel(cv:GetFrameLevel() + 6)
        fb:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_TOP")
            GameTooltip:SetText("Run completed", fc[1], fc[2], fc[3])
            GameTooltip:AddLine(MS:FormatTime(compSec), 1, 1, 1)
            if keyLimit and keyLimit > compSec then
                GameTooltip:AddLine("Under the timer by " .. MS:FormatTime(keyLimit - compSec),
                    P.verdHi[1], P.verdHi[2], P.verdHi[3])
            elseif keyLimit then
                GameTooltip:AddLine("Over the timer by " .. MS:FormatTime(compSec - keyLimit),
                    P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
            end
            GameTooltip:Show()
        end)
        fb:SetScript("OnLeave", GameTooltip_Hide)
    end
end

-- ── Deaths: a red cut through the track and a blood diamond below it.
-- ── The rim takes the class colour; deaths close together merge into
-- ── one diamond with a count.
local function DrawDeaths(c)
    local cv, run, W, X, At, Solid = c.cv, c.run, c.W, c.X, c.At, c.Solid
    local Art, Text, Btn, clampT = c.Art, c.Text, c.Btn, c.clampT
    local allDeaths = {}
    for _, p in pairs(run.players or {}) do
        for _, de in ipairs(p.deathEvents or {}) do
            _ins(allDeaths, { player = p, playerName = DN(p.name), playerClass = p.class,
                              time = clampT and _min(de.time or 0, clampT) or (de.time or 0),
                              rawTime = de.time or 0,
                              spell = de.spell or "Unknown", killer = de.killer or "Unknown",
                              events = de.events })
        end
    end
    _sort(allDeaths, function(a, b) return a.time < b.time end)

    local groups = {}
    for _, d in ipairs(allDeaths) do
        local x = X(d.time)
        local g = groups[#groups]
        if g and x - g.x1 < 14 then
            _ins(g.list, d); g.x2 = x
        else
            _ins(groups, { x1 = x, x2 = x, list = { d } })
        end
    end

    -- The killing blow and the hits before it, copied when the death happened.
    local function AddRecap(d)
        local events = d.events
        local kill = MS.KillingBlow(events)
        if kill then
            local line = "    |cffaaaaaaKilling blow:|r |cffff9944" .. (kill.spellName or "Unknown") .. "|r"
            if kill.caster and kill.caster ~= "" then
                line = line .. " |cff888888by|r |cffffd700" .. kill.caster .. "|r"
            end
            GameTooltip:AddLine(line, 1, 1, 1)
            for _, ev in ipairs(events) do
                local hit = "      |cff777777" .. (ev.spellName or "?") .. "|r"
                if ev.amount and ev.amount ~= 0 then hit = hit .. "  |cffff6666" .. Abbrev(-(ev.amount)) .. "|r" end
                if ev.overkill and ev.overkill > 0 then hit = hit .. " |cffff0000(killing blow)|r" end
                GameTooltip:AddLine(hit, 1, 1, 1)
            end
        elseif d.killer ~= "Unknown" then
            local line = "    |cffaaaaaaKilled by|r |cffff9944" .. d.killer .. "|r"
            if d.spell ~= "Unknown" then line = line .. " |cff888888(" .. d.spell .. ")|r" end
            GameTooltip:AddLine(line, 1, 1, 1)
        end
    end

    local lastMarkX = -_huge
    for _, g in ipairs(groups) do
        -- Cuts through the track at each exact death time.
        for _, d in ipairs(g.list) do
            local cut = Solid(cv, "ARTWORK", 5, P.bloodHi[1], P.bloodHi[2], P.bloodHi[3], 0.95)
            cut:SetSize(2, TRACK_H + 4)
            At(cut, "BOTTOMLEFT", _floor(X(d.time)) - 1, TRACK_Y - 2)
        end
        local mx = _max((g.x1 + g.x2) / 2, lastMarkX + 20)
        mx = _min(mx, TL_L + W + 6)
        lastMarkX = mx

        local stem = Solid(cv, "ARTWORK", 0, P.blood[1], P.blood[2], P.blood[3], 0.7)
        stem:SetSize(1, (TRACK_Y - 2) - (DEATH_Y + 9))
        At(stem, "BOTTOM", _floor(mx) + 0.5, DEATH_Y + 9)

        local single = (#g.list == 1)
        local rimC
        if single then rimC = { ClassColor(g.list[1].playerClass) } else rimC = P.bronzeHi end

        local mk = Btn(cv)
        mk:SetSize(20, 20)
        At(mk, "CENTER", mx, DEATH_Y)
        mk:SetFrameLevel(cv:GetFrameLevel() + 5)
        local shadow = Art(mk, "Diamond", "ARTWORK", 0); shadow:SetSize(22, 22); shadow:SetPoint("CENTER", 0, -1)
        Tint(shadow, {0, 0, 0}, 0.85)
        local rim = Art(mk, "Diamond", "ARTWORK", 1); rim:SetSize(19, 19); rim:SetPoint("CENTER")
        Tint(rim, rimC)
        local fill = Art(mk, "Diamond", "ARTWORK", 2); fill:SetSize(14, 14); fill:SetPoint("CENTER")
        Tint(fill, { 0.62, 0.15, 0.13 })
        if single then
            local sk = Art(mk, "Skull", "OVERLAY", 0); sk:SetSize(9, 9); sk:SetPoint("CENTER", 0, 0)
            Tint(sk, { 1, 0.90, 0.84 })
        else
            local n = Text(mk, "semibold", 11, { 1, 0.92, 0.86 }, "CENTER")
            n:SetPoint("CENTER", 0, 0); n:SetText(#g.list)
        end
        local hl = Art(mk, "Glow", "HIGHLIGHT", 0); hl:SetSize(40, 40); hl:SetPoint("CENTER")
        hl:SetBlendMode("ADD"); Tint(hl, P.bloodHi, 0.6)

        local list = g.list
        mk:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_TOP")
            if #list == 1 then
                local r, gg, b = ClassColor(list[1].playerClass)
                GameTooltip:SetText(list[1].playerName .. " died", r, gg, b)
            else
                GameTooltip:SetText(#list .. " deaths", P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
            end
            local seg = SegmentLabelFor(run, list[1].rawTime)
            if seg then GameTooltip:AddLine("During " .. seg, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3]) end
            GameTooltip:AddLine(" ")
            for _, d in ipairs(list) do
                GameTooltip:AddDoubleLine("|cff" .. ClassHex(d.playerClass) .. d.playerName .. "|r",
                    MS:FormatTime(d.rawTime), 1, 1, 1, 0.8, 0.8, 0.8)
                AddRecap(d)
            end
            GameTooltip:Show()
        end)
        mk:SetScript("OnLeave", GameTooltip_Hide)
    end
end

-- ── Interrupts: a small bar chart of how many kicks landed in each ──
-- ── stretch of time. (When exact kick times are hidden by the game,
-- ── the addon spaces them evenly, so per-kick ticks implied a
-- ── precision the data doesn't have.)
local function DrawInterrupts(c)
    local cv, run, totalDur, W, X, At = c.cv, c.run, c.totalDur, c.W, c.X, c.At
    local Solid, Btn, clampT = c.Solid, c.Btn, c.clampT
    do
        local BUCKET_PX = 6
        local nb = _ceil(W / BUCKET_PX)
        local buckets = {}
        local peak = 0
        for _, p in pairs(run.players or {}) do
            for _, ie in ipairs(p.interruptEvents or {}) do
                local t = MS.EventTime(ie)
                if clampT then t = _min(t, clampT) end
                local bi = _min(nb, _floor((X(t) - TL_L) / BUCKET_PX) + 1)
                local b = buckets[bi]
                if not b then b = { n = 0, who = {} }; buckets[bi] = b end
                b.n = b.n + 1
                local who = DN(p.name)
                b.who[who] = b.who[who] or { n = 0, class = p.class }
                b.who[who].n = b.who[who].n + 1
                if b.n > peak then peak = b.n end
            end
        end
        if peak > 0 then
            local base = Solid(cv, "ARTWORK", 0, P.line[1], P.line[2], P.line[3], 1)
            base:SetSize(W, 1); At(base, "BOTTOMLEFT", TL_L, INT_BASE - 1)
            for bi, b in pairs(buckets) do
                local x = TL_L + (bi - 1) * BUCKET_PX
                local f = b.n / peak
                local bar = Solid(cv, "ARTWORK", 1, P.kick[1], P.kick[2], P.kick[3], 0.35 + 0.55 * f)
                bar:SetSize(BUCKET_PX - 2, _max(2, _floor(INT_MAXH * f + 0.5)))
                At(bar, "BOTTOMLEFT", x + 1, INT_BASE)

                local hb = Btn(cv)
                hb:SetSize(BUCKET_PX, INT_MAXH + 6)
                At(hb, "BOTTOMLEFT", x, INT_BASE - 3)
                hb:SetFrameLevel(cv:GetFrameLevel() + 4)
                local hl = Solid(hb, "HIGHLIGHT", 0, 1, 1, 1, 0.12); hl:SetAllPoints()
                local t1 = (x - TL_L) / W * totalDur
                local t2 = (x + BUCKET_PX - TL_L) / W * totalDur
                hb:SetScript("OnEnter", function(self2)
                    GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                    GameTooltip:SetText("Interrupts: " .. b.n, P.kick[1], P.kick[2], P.kick[3])
                    GameTooltip:AddLine(MS:FormatTime(t1) .. " to " .. MS:FormatTime(t2), 0.8, 0.8, 0.8)
                    local seg = SegmentLabelFor(run, (t1 + t2) / 2)
                    if seg then GameTooltip:AddLine("During " .. seg, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3]) end
                    GameTooltip:AddLine(" ")
                    local rows = {}
                    for name, w in pairs(b.who) do _ins(rows, { name = name, n = w.n, class = w.class }) end
                    _sort(rows, function(a, c) return a.n > c.n end)
                    for _, r in ipairs(rows) do
                        GameTooltip:AddDoubleLine("|cff" .. ClassHex(r.class) .. r.name .. "|r", r.n, 1, 1, 1, 1, 1, 1)
                    end
                    GameTooltip:Show()
                end)
                hb:SetScript("OnLeave", GameTooltip_Hide)
            end
        end
    end
end

-- ── Live head (in-progress runs) ───────────────────────────────────────────
local function DrawLiveHead(strip, c, prevT, liveSeg)
    local cv, run, totalDur, W, live, X = c.cv, c.run, c.totalDur, c.W, c.live, c.X
    local Solid, Art, Text = c.Solid, c.Art, c.Text
    if live then
        if strip._liveTag then strip._liveTag:Show() end

        local headGlow = Art(cv, "Glow", "OVERLAY", 3)
        headGlow:SetBlendMode("ADD"); headGlow:SetSize(36, 36)
        Tint(headGlow, P.ivory, 0.8)
        local pulse = headGlow._pulse
        if not pulse then
            pulse = headGlow:CreateAnimationGroup()
            local a1 = pulse:CreateAnimation("Alpha")
            a1:SetFromAlpha(1); a1:SetToAlpha(0.25); a1:SetDuration(0.9); a1:SetSmoothing("IN_OUT")
            pulse:SetLooping("BOUNCE")
            headGlow._pulse = pulse
        end
        pulse:Play()

        local head = Solid(cv, "OVERLAY", 4, P.ivory[1], P.ivory[2], P.ivory[3], 1)
        head:SetSize(2, TRACK_H + 10)

        local headLbl = Text(cv, "semibold", 12, P.ivory, "LEFT")

        strip.UpdateLive = function(lRun, lTotalDur)
            if not lRun or not lTotalDur or lTotalDur <= 0 then return end
            local elapsed = MS:GetRunDuration(lRun)
            if (lRun.keystoneLevel or 0) == 0 and not lRun.completed
                    and elapsed >= lTotalDur - 2 and UI.RebuildTimeline then
                UI.RebuildTimeline(true)        -- rolling window is full: grow it
                return
            end
            local hx = TL_L + _min(1, elapsed / lTotalDur) * W
            if liveSeg then
                local sx = X(prevT)
                for _, tx in ipairs(liveSeg) do
                    if hx - sx >= 1 then
                        tx:ClearAllPoints()
                        tx:SetPoint("BOTTOMLEFT", cv, "BOTTOMLEFT", sx, TRACK_Y)
                        tx:SetWidth(hx - sx); tx:Show()
                    else
                        tx:Hide()
                    end
                end
            end
            head:ClearAllPoints(); head:SetPoint("BOTTOMLEFT", cv, "BOTTOMLEFT", _floor(hx) - 1, TRACK_Y - 5)
            headGlow:ClearAllPoints(); headGlow:SetPoint("CENTER", cv, "BOTTOMLEFT", hx, TRACK_Y + TRACK_H / 2)
            local txt = MS:FormatTime(elapsed)
            if (lRun.keystoneLevel or 0) > 0 then
                txt = txt .. "   " .. _floor(lRun.currentPct or 0) .. "%"
            end
            headLbl:SetText(txt)
            headLbl:ClearAllPoints()
            if hx + 8 + headLbl:GetStringWidth() > TL_L + W then
                headLbl:SetPoint("BOTTOMRIGHT", cv, "BOTTOMLEFT", hx - 8, TRACK_Y + TRACK_H + 3)
            else
                headLbl:SetPoint("BOTTOMLEFT", cv, "BOTTOMLEFT", hx + 8, TRACK_Y + TRACK_H + 3)
            end
        end

        local last = 0
        strip:SetScript("OnUpdate", function()
            local now = GetTime()
            if now - last >= 0.1 then
                last = now
                if strip.UpdateLive then strip.UpdateLive(run, totalDur) end
            end
        end)
    end
end

local function BuildTimeline(strip, run, totalDur)
    strip.UpdateLive = nil
    strip:SetScript("OnUpdate", nil)
    if strip._liveTag then strip._liveTag:Hide() end

    local c = NewContext(strip, run, totalDur)
    if not c then
        if strip._pools then FinishPools(strip._pools) end
        return strip
    end
    -- Whatever happens in the steps, the pieces left over are hidden after.
    local ok, err = pcall(function()
        DrawTrack(c)
        DrawAxis(c)
        local prevT, liveKind = DrawBosses(c)
        local liveSeg = DrawTail(c, prevT, liveKind)
        DrawKeyTimer(c)
        DrawCompletion(c)
        DrawDeaths(c)
        DrawInterrupts(c)
        DrawLiveHead(strip, c, prevT, liveSeg)
    end)
    FinishPools(strip._pools)
    if not ok then error(err, 0) end
    return strip
end

-- Published for the other UI files.
UI.BuildTimeline = BuildTimeline
UI.BuildTimelineChrome = BuildTimelineChrome
UI.GetTimelineDuration = GetTimelineDuration

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
local L = MS.L
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

-- Screen pixels. The window's UI units are only screen pixels at one UI
-- scale; at any other, a 2-unit line is 1.3 or 2.6 pixels and gaps come out
-- uneven. So the timeline works on the screen's own pixel grid: PX is one
-- screen pixel in the window's units, the track's width is a whole number of
-- them, and every position is TL_L plus whole pixels. Edges the game snaps to
-- the screen's pixels then keep exact distances wherever the window is.
local function PixelSize()
    local f = MS.UI.frame or UIParent
    local ok, scale = pcall(f.GetEffectiveScale, f)
    local _, h = (rawget(_G, "GetPhysicalScreenSize") or function() return 0, 768 end)()
    if not (ok and type(scale) == "number" and scale > 0 and h and h > 0) then return 1 end
    return 768 / h / scale
end
TL.PixelSize = PixelSize
local function TrackW(px) return _floor(TL_TRACKW / px) * px end

-- The completion line: 2 screen pixels wide. A run that ends on a kill has
-- it right against the last boss's block; one that ends at the window's edge
-- has the track end with it (nothing drawn after).
local END_LINE_PX = 2
local END_GAP_PX  = 0
TL.END_LINE_PX = END_LINE_PX

-- Whether a finished run ends on a boss kill (the line then stands just past
-- that boss's block instead of on its edge).
local function EndsOnKill(r, t)
    for _, b in ipairs(r.bosses or {}) do
        if b.killTime and math.abs(b.killTime - t) < 2 then return true end
    end
    return false
end

-- Where a cleared run (not a key) ends on the timeline: the clear, which is
-- usually the last kill. Time spent in the dungeon after it (looting, waiting
-- to leave) isn't drawn, so the completion line ends the track.
local function ClearedEnd(r)
    local lastKill = 0
    for _, b in ipairs(r.bosses or {}) do lastKill = _max(lastKill, b.killTime or 0) end
    local at = tonumber(r.clearedAt)
    if at and at > 0 then
        if lastKill > 0 and math.abs(at - lastKill) < 2 then return lastKill end
        return at
    end
    if lastKill > 0 then return lastKill end
    return r.duration
end

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
    -- A finished run that ends at the window's edge gets just enough empty
    -- track after it for the completion line and its gaps, to the pixel.
    -- A key: the track runs to the timer (or a little past an over-time
    -- finish). Anything else cleared ends exactly at the clear.
    if r.completed then
        local finish, exact
        if isMPlus then
            local lastKill = 0
            for _, b in ipairs(r.bosses or {}) do lastKill = _max(lastKill, b.killTime or 0) end
            finish = _max(lastKill, MS:GetRunDuration(r))
            if lastKill > 0 and finish - lastKill < 2 then finish = lastKill end   -- ended on the kill
        else
            finish, exact = ClearedEnd(r), true
        end
        local px = PixelSize()
        local roomPx = (finish and EndsOnKill(r, finish) and END_LINE_PX or END_LINE_PX / 2) * px
        local W = TrackW(px)
        if finish and finish > 0 and (exact or (dur - finish) / dur * W < roomPx + px) then
            dur = finish * W / (W - roomPx)
        end
    end
    return dur
end

local function SegmentLabelFor(run, t)
    if not run.bosses then return nil end
    local live = run == MS.currentRun and not run.completed
    for _, boss in ipairs(run.bosses) do
        local pullT = boss.pullTime or 0
        -- A fight with no end only runs on while the run does.
        local killT = MS.FightEnd(boss) or (live and (t + 1) or pullT)
        if t >= pullT and t <= killT then
            return (boss.name or L["Boss"]) .. MS.FightTag(boss)
        end
    end
    return nil
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
    title:SetText(L["Run timeline"])
    local live = Text(strip, "medium", 13, P.verd)
    live:SetPoint("LEFT", title, "RIGHT", 10, 0)
    live:SetText(L["Live"])
    live:Hide()
    strip._liveTag = live

    -- Legend, laid out right to left.
    local items = {
        { L["Interrupts"], function(f)
            local hold = Solid(f, "ARTWORK", 0, 0, 0, 0, 0); hold:SetSize(14, 9)
            for i, h in ipairs({ 4, 9, 6 }) do
                local b = Solid(f, "ARTWORK", 1, P.kick[1], P.kick[2], P.kick[3], 0.5 + h / 18)
                b:SetSize(3, h); b:SetPoint("BOTTOMLEFT", hold, "BOTTOMLEFT", (i - 1) * 5, 0)
            end
            return hold end },
        { L["Death"], function(f)
            local r = Art(f, "Diamond", "ARTWORK", 0); r:SetSize(12, 12); Tint(r, P.bronzeHi)
            local d = Art(f, "Diamond", "ARTWORK", 1); d:SetSize(8, 8); d:SetPoint("CENTER", r)
            Tint(d, { 0.62, 0.15, 0.13 })
            return r end },
        { L["Wipe"], function(f) local t = f:CreateTexture(nil, "ARTWORK"); t:SetSize(16, 8); VGrad(t, WIPE_BOT, WIPE_TOP); return t end },
        { L["Trash"], function(f)
            local b = Solid(f, "ARTWORK", 0, 0.16, 0.14, 0.12, 1); b:SetSize(16, 8)
            local h = Art(f, "Hatch", "ARTWORK", 1, true); h:SetAllPoints(b); h:SetVertexColor(0.225, 0.195, 0.165, 1)
            return b end },
        { L["Boss"], function(f) local t = f:CreateTexture(nil, "ARTWORK"); t:SetSize(16, 8); VGrad(t, FIGHT_BOT, FIGHT_TOP); return t end },
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
    -- Flat colour pieces (blocks, the completion line) snap their edges to
    -- the screen's pixels, so the whole-pixel gaps between them stay exact.
    local function Snap(t)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(true); t:SetTexelSnappingBias(0) end
        return t
    end
    local function Solid(parent, layer, sub, r, g, b, a)
        local key = "S" .. (layer or "") .. (sub or 0)
        local t, list = Take(pools, key, parent)
        if not t then return Snap(Keep(list, Solid0(parent, layer, sub, r, g, b, a), parent)) end
        ResetTexture(t)
        t:SetColorTexture(r, g, b, a or 1)
        return Snap(t)
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

    local px = PixelSize()
    local W  = TrackW(px)
    local END_LINE_W, END_GAP = END_LINE_PX * px, END_GAP_PX * px
    local isMPlus = (run.keystoneLevel or 0) > 0
    -- Only the run in progress (or paused) is drawn live. A saved run that
    -- wasn't cleared is finished too: drawn still, to where it ended.
    local live = not run.completed and run == MS.currentRun

    -- Whole screen pixels from the track's start, so block edges are crisp
    -- and gaps come out exact.
    local function X(t) return TL_L + _floor(_max(0, _min(1, t / totalDur)) * W / px + 0.5) * px end
    local endLineL          -- left edge of the completion line, once known

    local function At(region, point, x, y)
        region:SetPoint(point, cv, "BOTTOMLEFT", x, y)
    end

    local function Weather(x, w, sub)
        local grit = Art(cv, "Grit", "ARTWORK", sub, true)
        grit:SetBlendMode("MOD")
        grit:SetSize(_max(px, w), TRACK_H); At(grit, "BOTTOMLEFT", x, TRACK_Y)
        local groove = Tex(cv, "ARTWORK", sub)
        groove:SetSize(_max(px, w), 4); At(groove, "BOTTOMLEFT", x, TRACK_Y + TRACK_H - 4)
        VGrad(groove, {0, 0, 0}, {0, 0, 0}, 0, 0.55)
        return grit
    end
    local function Seg(t1, t2, kind)
        local x1, x2 = X(t1), X(t2)
        local w = x2 - x1
        if w < px then return nil end
        local tex
        if kind == "trash" then         -- (a one-pixel seam before what follows)
            local base = Solid(cv, "ARTWORK", 0, 0.16, 0.14, 0.12, 1)
            base:SetSize(_max(px, w - px), TRACK_H); At(base, "BOTTOMLEFT", x1, TRACK_Y)
            tex = Art(cv, "Hatch", "ARTWORK", 1, true)
            tex:SetVertexColor(0.225, 0.195, 0.165, 1)
            tex:SetSize(_max(px, w - px), TRACK_H); At(tex, "BOTTOMLEFT", x1, TRACK_Y)
            Weather(x1, w - px, 2)
            return base
        end
        tex = Tex(cv, "ARTWORK", 2)
        tex:SetSize(_max(px, w), TRACK_H); At(tex, "BOTTOMLEFT", x1, TRACK_Y)
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
        -- Kept clear of the completion line just past the last boss.
        if endLineL and cx + half > endLineL - 3 and X(t2) <= endLineL then cx = endLineL - 3 - half end
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
            compSec = ClearedEnd(run)
            visualEnd = compSec
        end
        if compSec and compSec <= 0 then compSec = nil end
        if visualEnd and visualEnd <= 0 then visualEnd = nil end
        if compSec then
            endLineL = EndsOnKill(run, compSec) and (X(compSec) + END_GAP)
                                                 or (X(compSec) - END_LINE_W / 2)
            endLineL = _min(endLineL, TL_L + W - END_LINE_W)
        end
    elseif not live then
        local runEnd = MS:GetRunDuration(run)
        if runEnd and runEnd > 0 then visualEnd = runEnd end
    end

    return {
        cv = cv, run = run, totalDur = totalDur, W = W, isMPlus = isMPlus, live = live, X = X, At = At,
        Solid = Solid, Art = Art, Tex = Tex, Mask = Mask, Text = Text, Btn = Btn,
        Seg = Seg, SegButton = SegButton, InBarText = InBarText, CountDeaths = CountDeaths, Weather = Weather,
        keyLimit = keyLimit, compSec = compSec, visualEnd = visualEnd, clampT = clampT, endLineL = endLineL,
        px = px, endLineW = END_LINE_W,
        -- Mythic+: the times for +3, +2 and +1 (marked on the axis).
        thresholds = (isMPlus and keyLimit) and { { 3, keyLimit * 0.6 }, { 2, keyLimit * 0.8 }, { 1, keyLimit } } or nil,
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
        -- (drawn by UI_TimelineBosses.lua and UI_TimelineMarks.lua)
        local prevT, liveKind = TL.DrawBosses(c)
        local liveSeg = TL.DrawTail(c, prevT, liveKind)
        TL.DrawThresholds(c)
        TL.DrawKeyTimer(c)
        TL.DrawCompletion(c)
        TL.DrawDeaths(c)
        TL.DrawInterrupts(c)
        TL.DrawLiveHead(strip, c, prevT, liveSeg)
    end)
    FinishPools(strip._pools)
    if not ok then error(err, 0) end
    return strip
end

-- Published for the other UI files.
TL.SegmentLabelFor = SegmentLabelFor     -- for the other timeline files
UI.BuildTimeline = BuildTimeline
UI.BuildTimelineChrome = BuildTimelineChrome
UI.GetTimelineDuration = GetTimelineDuration

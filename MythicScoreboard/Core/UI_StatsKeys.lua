local _floor, _max, _min = math.floor, math.max, math.min
local _fmt = string.format

local MS = _G["MythicScoreboard"]
local L = MS.L
local LK = MS.LK      -- a label kept in English, translated where it is shown
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local P, COL_HDR_H, FRAME_W = UI.P, UI.COL_HDR_H, UI.FRAME_W
local Text, Solid, Btn, Tint, Art = UI.Text, UI.Solid, UI.Btn, UI.Tint, UI.Art
local MakeScrollFrame, CT = UI.MakeScrollFrame, UI.CT

-- Stats page, part 4 (Mythic+ only): the Keys tab.
--
--   rating    your rating key by key, a line per character, each key a
--             diamond coloured by how it went
--   dungeons  per dungeon: keys, how many timed, the average upgrade, the
--             highest key timed and the highest run
--   by level  how often keys of each level were timed: where it gets hard
--
-- Built and filled from UI_Stats.lua through UI.StatsKit.

local K = UI.StatsKit                  -- shared by UI_Stats.lua
local Band, Cells, CharName, Day, HoverRow = K.Band, K.Cells, K.CharName, K.Day, K.HoverRow
local LEFT_W, LIST_ROW, Pct, Pool, RIGHT_W, RIGHT_X, S = K.LEFT_W, K.LIST_ROW, K.Pct, K.Pool, K.RIGHT_W, K.RIGHT_X, K.S
local X0 = K.X0

local KCOLS = {   -- one row per dungeon (widths add up to LEFT_W)
    { key = "name",    label = LK("Dungeon"),      w = 230, left = true },
    { key = "keys",    label = LK("Keys"),         w = 64 },
    { key = "timed",   label = LK("Timed"),        w = 86 },
    { key = "avg",     label = LK("Avg. upgrade"), w = 110 },
    { key = "best",    label = LK("Best timed"),   w = 110 },
    { key = "highest", label = LK("Highest"),      w = 100 },
}
K.KCOLS = KCOLS

local CHART_TOP = COL_HDR_H + 16
local CHART_H   = 140
local CHART_L   = X0 + 46                      -- room for the rating labels
local CHART_W   = FRAME_W - CHART_L - X0 - 14
local LIST_TOP  = CHART_TOP + CHART_H + 30
local LEVEL_W   = 56                           -- "+15"
local COUNT_W   = 86                           -- "4 of 6"

local function Thousands(n)
    n = _floor((n or 0) + 0.5)
    local B = rawget(_G, "BreakUpLargeNumbers")
    return B and B(n) or tostring(n)
end

-- How a key went, as a colour: bronze for +2/+3, ivory for +1, red over time.
local function UpgradeColor(e)
    local up = tonumber(e.up)
    if not up then return e.inTime and P.ivory or P.bloodHi end
    if up >= 2 then return P.bronzeHi end
    if up == 1 then return P.ivory end
    return P.bloodHi
end

local function KeyLine(e)
    local up = tonumber(e.up)
    return (e.dungeon or "?") .. "  " .. CT(P.bronzeHi, "+" .. (e.key or 0))
        .. (up and ("  " .. UI.Pips(up, 11)) or "")
end

-- ── Rating chart ───────────────────────────────────────────────────────────
local function MakePoint(parent)
    local b = Btn(parent)
    b:SetSize(14, 14)
    b.dot = Art(b, "PipFull", "OVERLAY")
    b.dot:SetSize(10, 10); b.dot:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self)
        local pt = self.pt
        if not pt then return end
        local e = pt.e
        self.dot:SetSize(13, 13)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(KeyLine(e), P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:AddLine(Day(e.at) .. (e.at and date("  %H:%M", e.at) or ""), P.ash[1], P.ash[2], P.ash[3])
        if S.multiChar and MS:RunOwner(e) then GameTooltip:AddLine(CharName(MS:RunOwner(e))) end
        local text, col = UI.ArchiveResult(e)
        GameTooltip:AddDoubleLine(L["Result"], text, P.ash[1], P.ash[2], P.ash[3], col[1], col[2], col[3])
        if e.r1 then
            local gain = e.r0 and (e.r1 - e.r0) or 0
            GameTooltip:AddDoubleLine(L["Rating after"], Thousands(e.r1)
                .. (gain > 0 and CT(P.verdHi, "  +" .. gain) or ""), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        elseif e.r0 then
            GameTooltip:AddDoubleLine(L["Rating going in"], Thousands(e.r0), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self.dot:SetSize(10, 10); GameTooltip:Hide() end)
    return b
end

-- A round number of rating between grid lines (50, 100, 250, ...).
local function Step(span)
    for _, s in ipairs({ 25, 50, 100, 250, 500, 1000 }) do
        if span / s <= 4 then return s end
    end
    return 1000
end

local function FillChart(k, ks)
    local c = k.chart
    -- Every point, in time order across characters: x is its place in that order.
    local all = {}
    for who, list in pairs(ks.rating) do
        for _, pt in ipairs(list) do pt.who = who; all[#all + 1] = pt end
    end
    table.sort(all, function(a, b) return a.at < b.at end)
    local n = #all
    k.noRating:SetShown(n == 0 and ks.keys > 0)
    c:SetShown(n > 0)
    if n == 0 then
        k.pointsHideFrom(1); k.linesHideFrom(1); k.gridHideFrom(1)
        return
    end
    local lo, hi = all[1].v, all[1].v
    for _, pt in ipairs(all) do lo = _min(lo, pt.v); hi = _max(hi, pt.v) end
    local step = Step(_max(hi - lo, 50))
    lo = _floor(lo / step) * step
    hi = _max(lo + step, math.ceil(hi / step) * step)
    local function Y(v) return (v - lo) / (hi - lo) * CHART_H end
    local function X(i) return n == 1 and CHART_W / 2 or (i - 1) / (n - 1) * CHART_W end

    -- Grid lines with their ratings.
    local g = 0
    for v = lo, hi, step do
        g = g + 1
        local line = k.gridAt(g)
        line.rule:ClearAllPoints()
        line.rule:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, Y(v))
        line.rule:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, Y(v))
        line.lbl:ClearAllPoints()
        line.lbl:SetPoint("RIGHT", c, "BOTTOMLEFT", -8, Y(v))
        line.lbl:SetText(Thousands(v))
    end
    k.gridHideFrom(g + 1)

    -- A line per character, in its class colour; a diamond per key.
    local seg, last = 0, {}
    for i, pt in ipairs(all) do
        local x, y = X(i), Y(pt.v)
        local prev = last[pt.who]
        if prev then
            seg = seg + 1
            local l = k.lineAt(seg)
            local info = MS:CharacterInfo(pt.who)
            local r, gg, b = UI.ClassColor(info and info.class)
            l:SetColorTexture(r, gg, b, 0.75)
            l:SetStartPoint("BOTTOMLEFT", c, prev.x, prev.y)
            l:SetEndPoint("BOTTOMLEFT", c, x, y)
        end
        last[pt.who] = { x = x, y = y }
        local p = k.pointAt(i)
        p.pt = pt
        p:ClearAllPoints()
        p:SetPoint("CENTER", c, "BOTTOMLEFT", x, y)
        Tint(p.dot, UpgradeColor(pt.e))
    end
    k.linesHideFrom(seg + 1)
    k.pointsHideFrom(n + 1)
    k.xFirst:ClearAllPoints(); k.xFirst:SetPoint("TOP", c, "BOTTOMLEFT", X(1), -6)
    k.xFirst:SetText(Day(all[1].at))
    k.xLast:ClearAllPoints(); k.xLast:SetPoint("TOP", c, "BOTTOMLEFT", X(n), -6)
    k.xLast:SetText(n > 1 and Day(all[n].at) or "")
end

-- ── Tables ─────────────────────────────────────────────────────────────────
local function MakeDungeonRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LEFT_W, LIST_ROW)
    row:EnableMouse(true)
    HoverRow(row)
    row.cells = Cells(row, KCOLS, 14)
    row:SetScript("OnEnter", function(self)
        local d = self.data
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(d.name, P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:AddLine(_fmt(L["%d of %d timed"], d.timed, d.keys), P.ash[1], P.ash[2], P.ash[3])
        if d.upN > 0 then
            GameTooltip:AddLine(L["Levels a key went up on average: 0 over time, up to +3 in time."],
                P.ash[1], P.ash[2], P.ash[3], true)
        end
        GameTooltip:AddLine(L["Click for every run in this dungeon."], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- To the dungeon's own page, with every run in it.
    row:SetScript("OnMouseUp", function(self)
        GameTooltip:Hide()
        S.tab, S.selected, S.compareA, S.compareB = "dungeons", self.data.name, nil, nil
        UI.RefreshStats(true)
    end)
    return row
end

local function MakeLevelRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(RIGHT_W, LIST_ROW)
    row:EnableMouse(true)
    HoverRow(row)
    row.level = Text(row, "semibold", 14, P.bronzeHi, "LEFT")
    row.level:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.count = Text(row, "medium", 13, P.ash, "RIGHT")
    row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    local barW = RIGHT_W - LEVEL_W - COUNT_W
    row.track = Solid(row, "BORDER", 0, 0.16, 0.14, 0.12, 1)
    row.track:SetPoint("LEFT", row, "LEFT", LEVEL_W, 0); row.track:SetSize(barW, 8)
    row.fill = Solid(row, "ARTWORK", 0, P.verd[1], P.verd[2], P.verd[3], 0.9)
    row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0); row.fill:SetHeight(8)
    row.barW = barW
    row:SetScript("OnEnter", function(self)
        local lv = self.data
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("+" .. lv.level, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        GameTooltip:AddLine(_fmt(L["%d of %d timed"], lv.timed, lv.keys), P.ash[1], P.ash[2], P.ash[3])
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function BuildKeys(parent)
    local k = CreateFrame("Frame", nil, parent)
    k:SetAllPoints()
    local band = Band(k)
    band:SetPoint("TOPLEFT", k, "TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", k, "TOPRIGHT", 0, 0)
    local title = Text(band, "medium", 13, P.ash, "LEFT")
    title:SetPoint("LEFT", band, "LEFT", X0, 0); title:SetText(L["Rating"])

    local c = CreateFrame("Frame", nil, k)
    c:SetPoint("TOPLEFT", k, "TOPLEFT", CHART_L, -CHART_TOP)
    c:SetSize(CHART_W, CHART_H)
    k.chart = c
    k.gridAt, k.gridHideFrom = Pool(function()
        local g = CreateFrame("Frame", nil, c)
        g.rule = Solid(c, "BACKGROUND", 0, P.line[1], P.line[2], P.line[3], 1)
        g.rule:SetHeight(1)
        g.lbl = Text(k, "medium", 11, P.ash, "RIGHT")
        g.Show = function(self) self.rule:Show(); self.lbl:Show() end
        g.Hide = function(self) self.rule:Hide(); self.lbl:Hide() end
        return g
    end)
    k.lineAt, k.linesHideFrom = Pool(function()
        local l = c:CreateLine(nil, "ARTWORK")
        l:SetThickness(2)
        return l
    end)
    k.pointAt, k.pointsHideFrom = Pool(function() return MakePoint(c) end)
    k.xFirst = Text(k, "medium", 11, P.ash, "CENTER")
    k.xLast = Text(k, "medium", 11, P.ash, "CENTER")
    k.noRating = Text(k, "regular", 14, P.ash, "CENTER")
    k.noRating:SetPoint("CENTER", k, "TOPLEFT", FRAME_W / 2, -(CHART_TOP + CHART_H / 2))
    k.noRating:SetWidth(620); k.noRating:SetWordWrap(true)
    k.noRating:SetText(L["No rating recorded yet. It's saved with every key from version 2.9 on."])

    -- Per dungeon (left) and per level (right).
    local dband = Band(k, KCOLS, X0)
    dband:SetPoint("TOPLEFT", k, "TOPLEFT", 0, -LIST_TOP); dband:SetPoint("TOPRIGHT", k, "TOPRIGHT", 0, -LIST_TOP)
    local lvLbl = Text(dband, "medium", 13, P.ash, "LEFT")
    lvLbl:SetPoint("LEFT", dband, "LEFT", RIGHT_X, 0); lvLbl:SetText(L["By level"])
    local tLbl = Text(dband, "medium", 13, P.ash, "RIGHT")
    tLbl:SetPoint("RIGHT", dband, "LEFT", RIGHT_X + RIGHT_W - 8, 0); tLbl:SetText(L["Timed"])
    k.sf = MakeScrollFrame(k)
    k.sf:SetPoint("TOPLEFT", k, "TOPLEFT", X0, -(LIST_TOP + COL_HDR_H))
    k.sf:SetPoint("BOTTOMLEFT", k, "BOTTOMLEFT", X0, 8)
    k.sf:SetWidth(LEFT_W + 10)
    k.rowAt, k.rowsHideFrom = Pool(function() return MakeDungeonRow(k.sf.scrollContent) end)
    k.lsf = MakeScrollFrame(k)
    k.lsf:SetPoint("TOPLEFT", k, "TOPLEFT", RIGHT_X, -(LIST_TOP + COL_HDR_H))
    k.lsf:SetPoint("BOTTOMLEFT", k, "BOTTOMLEFT", RIGHT_X, 8)
    k.lsf:SetWidth(RIGHT_W + 10)
    k.levelAt, k.levelsHideFrom = Pool(function() return MakeLevelRow(k.lsf.scrollContent) end)

    k.empty = Text(k, "regular", 15, P.ash, "CENTER")
    k.empty:SetPoint("CENTER", k, "CENTER", 0, -10)
    k.empty:SetWidth(560); k.empty:SetWordWrap(true)
    k.empty:SetText(L["No keys yet. Every Mythic+ key you finish is added here."])
    k.parts = { band, dband, k.sf, k.lsf }
    return k
end

local function FillKeys(k, ks)
    local any = ks.keys > 0
    k.empty:SetShown(not any)
    for _, part in ipairs(k.parts) do part:SetShown(any) end
    k.xFirst:SetShown(any); k.xLast:SetShown(any)
    if not any then
        k.chart:Hide(); k.noRating:Hide()
        return
    end
    FillChart(k, ks)

    local y = 0
    for i, d in ipairs(ks.dungeons) do
        local row = k.rowAt(i)
        row:SetPoint("TOPLEFT", k.sf.scrollContent, "TOPLEFT", 0, -y)
        row.data = d
        local c = row.cells
        UI.FitText(c.name, d.name, "semibold", 14, 12)
        c.keys:SetText(d.keys)
        c.timed:SetText(Pct(d.timed, d.keys))
        c.avg:SetText(d.upN > 0 and _fmt("+%.1f", d.upSum / d.upN) or CT(P.ash2, "-"))
        c.best:SetText(d.bestTimed and CT(P.bronzeHi, "+" .. d.bestTimed) or CT(P.ash2, "-"))
        c.highest:SetText("+" .. (d.highest or 0))
        y = y + LIST_ROW
    end
    k.rowsHideFrom(#ks.dungeons + 1)
    k.sf.scrollContent:SetHeight(_max(1, y))
    k.sf.UpdateRange()

    local ly = 0
    for i, lv in ipairs(ks.levels) do
        local row = k.levelAt(i)
        row:SetPoint("TOPLEFT", k.lsf.scrollContent, "TOPLEFT", 0, -ly)
        row.data = lv
        row.level:SetText("+" .. lv.level)
        row.count:SetText(lv.timed .. " / " .. lv.keys)
        local f = lv.keys > 0 and lv.timed / lv.keys or 0
        row.fill:SetShown(f > 0)
        row.fill:SetWidth(_max(1, f * row.barW))
        local col = f >= 0.5 and P.verd or P.bloodHi
        row.fill:SetColorTexture(col[1], col[2], col[3], 0.9)
        ly = ly + LIST_ROW
    end
    k.levelsHideFrom(#ks.levels + 1)
    k.lsf.scrollContent:SetHeight(_max(1, ly))
    k.lsf.UpdateRange()
end

K.BuildKeys, K.FillKeys = BuildKeys, FillKeys

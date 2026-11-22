local _ceil, _floor, _max, _min = math.ceil, math.floor, math.max, math.min
local _fmt = string.format

local MS = _G["MythicScoreboard"]
local L = MS.L
local LK = MS.LK
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local P, COL_HDR_H = UI.P, UI.COL_HDR_H
local Art, Box, Btn, CT, Solid, Text, Tint = UI.Art, UI.Box, UI.Btn, UI.CT, UI.Solid, UI.Text, UI.Tint

-- Stats page, part 5: the Trends tab. Left, how much you've played (a square
-- a day for the last six months, click one for that day's runs; this week
-- against last, your streak) and a chart run by run with its trend: DPS, HPS,
-- XP or gold an hour, run time, damage taken or deaths, for one dungeon or
-- all, over the last week, month or all time. Right (sortable by any column), on WoW Forever, the XP and
-- gold an hour each dungeon has given you (the ones near your level first);
-- elsewhere, your DPS dungeon by dungeon. Click a dungeon for its page
-- (UI_StatsDungeon.lua). Numbers from MS:TrendStats (Trends.lua);
-- built and filled from UI_Stats.lua through UI.StatsKit.

local K = UI.StatsKit                  -- shared by UI_Stats.lua
local Band, CharName, Day, HoverRow, Pool, S = K.Band, K.CharName, K.Day, K.HoverRow, K.Pool, K.S
local Hours, LIST_ROW, RIGHT_X, X0 = K.Hours, K.LIST_ROW, K.RIGHT_X, K.X0

-- ── Layout ─────────────────────────────────────────────────────────────────
local CELL, CELL_GAP = 12, 3
local GRID_TOP = 44                    -- below the tab's top
local GRID_W = MS.TRENDS_WEEKS * (CELL + CELL_GAP) - CELL_GAP
local SUM_X = X0 + GRID_W + 34          -- this week / last week / streak
local PERF_TOP = 196                    -- the chart's choices and dungeon; its trend and range under them
local CHART_L = X0 + 52                 -- room for the axis's numbers
local CHART_W, CHART_H = 648, 185     -- the height: down to the bottom (fitted again when drawn)
local CHART_TOP = PERF_TOP + 58
local MAX_ROWS = 14
local DAY_W, DAY_ROW, DAY_MAX = 430, 22, 10     -- a day's runs (click a square)
local MENU_ROW, MENU_MAX = 24, 16               -- the dungeon filter's list

-- What the chart can show on this game (Trends.lua's MS.TREND_METRICS).
local METRICS, METRIC = {}, {}
for _, m in ipairs(MS.TREND_METRICS) do
    if not m.forever or MS.Flavor.progressStats then METRICS[#METRICS + 1] = m; METRIC[m.key] = m end
end
local RANGES = { { days = 7 }, { days = 30 }, { days = nil } }

local TFCOLS = {   -- WoW Forever: XP and gold an hour, a row per dungeon
    { key = "dungeon", label = LK("Dungeon"),   w = 148, left = true },
    { key = "levels",  label = LK("Levels"),    w = 58 },
    { key = "xp",      label = LK("XP/hour"),   w = 80 },
    { key = "gold",    label = LK("Gold/hour"), w = 94 },
}
local TDCOLS = {   -- elsewhere: your DPS, a row per dungeon
    { key = "dungeon", label = LK("Dungeon"), w = 182, left = true },
    { key = "runs",    label = LK("Runs"),    w = 58 },
    { key = "avg",     label = LK("Average"), w = 70 },
    { key = "best",    label = LK("Best"),    w = 70 },
}
local COLS = MS.Flavor.progressStats and TFCOLS or TDCOLS

-- 12,345 (MS.FormatThousands is WoW Forever's; the game's own elsewhere).
local Thousands = MS.FormatThousands     -- (Util.lua)

local function Short(n)
    return UI.Abbrev and UI.Abbrev(n) or Thousands(n)
end

-- A day's square: dark with no runs, brighter bronze with more.
local function CellColor(runs, most)
    if runs == 0 then return P.line, 1 end
    local f = most > 1 and (runs - 1) / (most - 1) or 1
    local lo, hi = P.bronzeDk, P.bronzeHi
    return { lo[1] + (hi[1] - lo[1]) * (0.35 + 0.65 * f), lo[2] + (hi[2] - lo[2]) * (0.35 + 0.65 * f),
             lo[3] + (hi[3] - lo[3]) * (0.35 + 0.65 * f) }, 1
end

-- ── Building ───────────────────────────────────────────────────────────────
local function Heading(parent, x, y, text)
    local h = Text(parent, "medium", 13, P.ash, "LEFT")
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    if text then h:SetText(text) end
    return h
end

local function MakeCell(parent)
    local b = Btn(parent)
    b:SetSize(CELL, CELL)
    b.ring = Solid(b, "BACKGROUND", 0, P.ivory[1], P.ivory[2], P.ivory[3], 1)   -- the day open below
    b.ring:SetPoint("TOPLEFT", -2, 2); b.ring:SetPoint("BOTTOMRIGHT", 2, -2); b.ring:Hide()
    b.sq = Solid(b, "ARTWORK", 0, 1, 1, 1, 1)
    b.sq:SetAllPoints()
    b:SetScript("OnClick", function(self)
        local c = self.cell
        if not c or c.runs == 0 then return end
        local same = S.trendDay and date("%Y%m%d", S.trendDay) == date("%Y%m%d", c.at)
        S.trendDay = (not same) and c.at or nil
        GameTooltip:Hide()
        UI.RefreshStats(true)
    end)
    b:SetScript("OnEnter", function(self)
        local c = self.cell
        if not c then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(date("%A, ", c.at) .. Day(c.at), P.ivory[1], P.ivory[2], P.ivory[3])
        if c.runs > 0 then
            GameTooltip:AddLine(MS.Plural(c.runs, "%d run", "%d runs", c.runs) .. "  ·  " .. Hours(c.time), 1, 1, 1)
            GameTooltip:AddLine(L["Click for that day's runs."], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        else
            GameTooltip:AddLine(L["No runs"], P.ash[1], P.ash[2], P.ash[3])
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- A run's point on a chart. Its tooltip: the run, then what the chart adds
-- (c.Tip(pt): its value and trend lines).
local function MakePoint(c)
    local b = Btn(c)
    b:SetSize(12, 12)
    b.dot = Art(b, "PipFull", "OVERLAY")
    b.dot:SetSize(7, 7); b.dot:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self)
        local pt = self.pt
        if not pt then return end
        local e = pt.e
        self.dot:SetSize(10, 10)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(e.dungeon or "?", P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:AddLine(Day(e.at) .. "  ·  " .. K.Dur(e.dur or 0), P.ash[1], P.ash[2], P.ash[3])
        if S.multiChar and MS:RunOwner(e) then GameTooltip:AddLine(CharName(MS:RunOwner(e))) end
        if c.Tip then c.Tip(pt) end
        if pt.lvl then
            GameTooltip:AddDoubleLine(L["Level"], tostring(pt.lvl), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        end
        if pt.ilvl then
            GameTooltip:AddDoubleLine(L["Item level"], tostring(pt.ilvl), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self.dot:SetSize(7, 7); GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) if c.Click and self.pt then c.Click(self.pt) end end)
    return b
end

-- A line chart w x h at (x, y) in owner: a dot a run, a faint line through
-- them, and the trend through them in bronze. Axis numbers to its left.
local function Chart(owner, x, y, w, h)
    local c = CreateFrame("Frame", nil, owner)
    c:SetPoint("TOPLEFT", owner, "TOPLEFT", x, -y)
    c:SetSize(w, h)
    c.w, c.h = w, h
    c.gridLineAt, c.gridLinesHideFrom = Pool(function()
        local g = CreateFrame("Frame", nil, c)
        g.rule = Solid(c, "BACKGROUND", 0, P.line[1], P.line[2], P.line[3], 1)
        g.rule:SetHeight(1)
        g.lbl = Text(owner, "medium", 11, P.ash, "RIGHT")
        g.Show = function(self) self.rule:Show(); self.lbl:Show() end
        g.Hide = function(self) self.rule:Hide(); self.lbl:Hide() end
        return g
    end)
    c.rawAt, c.rawHideFrom = Pool(function() return UI.ChartLine(c, 2) end)
    c.avgAt, c.avgHideFrom = Pool(function() return UI.ChartLine(c, 4) end)
    c.pointAt, c.pointsHideFrom = Pool(function() return MakePoint(c) end)
    c.xFirst = Text(owner, "medium", 11, P.ash, "LEFT")
    c.xFirst:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -6)
    c.xLast = Text(owner, "medium", 11, P.ash, "RIGHT")
    c.xLast:SetPoint("TOPRIGHT", c, "BOTTOMRIGHT", 0, -6)
    c.empty = Text(owner, "regular", 14, P.ash, "CENTER")
    c.empty:SetPoint("CENTER", c, "CENTER", 0, 0)
    c.empty:SetWidth(w - 40); c.empty:SetWordWrap(true)
    c.empty:SetText(L["Your numbers show here after a couple of runs."])
    return c
end

-- Round numbers for the axis (whole steps of 1, 2 or 5 times a power of ten).
local function Step(span)
    local p = 10 ^ _floor(math.log10(_max(span, 1)))
    for _, m in ipairs({ 1, 2, 5, 10 }) do
        if span / (m * p) <= 4 then return m * p end
    end
    return 10 * p
end

-- Draws points {v, avg, e} (oldest first) on a chart from Chart; label(v)
-- writes the axis's numbers.
local function DrawChart(c, pts, label)
    local n = #pts
    c.empty:SetShown(n < 2)
    if n < 2 then
        c.pointsHideFrom(1); c.rawHideFrom(1); c.avgHideFrom(1); c.gridLinesHideFrom(1)
        c.xFirst:SetText(""); c.xLast:SetText("")
        return
    end
    label = label or Short
    local hi = 0
    for _, pt in ipairs(pts) do hi = _max(hi, pt.v) end
    local step = Step(hi)
    local top = _max(step, _ceil(hi / step) * step)
    local W, H = c.w, c.h
    local function Y(v) return v / top * H end
    local function X(i) return (i - 1) / (n - 1) * W end

    local g = 0
    for v = 0, top, step do
        g = g + 1
        local line = c.gridLineAt(g)
        line.rule:ClearAllPoints()
        line.rule:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, Y(v))
        line.rule:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, Y(v))
        line.lbl:ClearAllPoints()
        line.lbl:SetPoint("RIGHT", c, "BOTTOMLEFT", -8, Y(v))
        line.lbl:SetText(label(v))
    end
    c.gridLinesHideFrom(g + 1)

    for i, pt in ipairs(pts) do
        local x, y = X(i), Y(pt.v)
        if i > 1 then
            local prev = pts[i - 1]
            local raw = c.rawAt(i - 1)
            UI.ChartLineColor(raw, P.ash, 0.35)
            raw:SetStartPoint("BOTTOMLEFT", c, X(i - 1), Y(prev.v))
            raw:SetEndPoint("BOTTOMLEFT", c, x, y)
            local avg = c.avgAt(i - 1)
            UI.ChartLineColor(avg, P.bronzeHi, 0.95)
            avg:SetStartPoint("BOTTOMLEFT", c, X(i - 1), Y(prev.avg))
            avg:SetEndPoint("BOTTOMLEFT", c, x, Y(pt.avg))
        end
        local p = c.pointAt(i)
        p.pt = pt
        p:ClearAllPoints()
        p:SetPoint("CENTER", c, "BOTTOMLEFT", x, y)
        Tint(p.dot, P.ivory)
    end
    c.rawHideFrom(n); c.avgHideFrom(n); c.pointsHideFrom(n + 1)
    c.xFirst:SetText(Day(pts[1].e.at))
    c.xLast:SetText(Day(pts[n].e.at))
end

-- "+12%" in green, "-8%" in red: how far a trend has moved (the other way
-- round when lower is better: deaths, damage taken).
local function ChangeText(change, lowerIsBetter)
    if not change then return "" end
    local pct = _floor(change * 100 + 0.5)
    local good = lowerIsBetter and pct < 0 or not lowerIsBetter and pct > 0
    local col = pct == 0 and P.ash or good and P.verdHi or P.bloodHi
    return CT(P.ash, L["Trend"] .. "  ") .. CT(col, (pct > 0 and "+" or "") .. pct .. "%")
end

local function GoldShort(copper)
    -- To the silver: "2g 13s" (copper an hour is noise).
    return MS.FormatGold(_floor((copper or 0) / 100) * 100)
end

-- A metric's number as it's written: in the tooltip, and on the axis.
local function MetricText(m, v)
    if m.fmt == "gold" then return GoldShort(v)
    elseif m.fmt == "minutes" then return K.Dur(_floor(v * 60 + 0.5))
    elseif m.fmt == "whole" then return tostring(_floor(v + 0.5)) end
    return Thousands(v)
end
local function MetricAxis(m)
    if m.fmt == "gold" then return GoldShort
    elseif m.fmt == "minutes" then return function(v) return _fmt(L["%dm"], v) end
    elseif m.fmt == "whole" then return function(v) return tostring(_floor(v + 0.5)) end end
    return nil                                  -- 12K and the like
end

-- A choice in a row of them: plain text, the one in use in ivory and underlined.
local function Choice(parent, label)
    local b = Btn(parent)
    b.text = Text(b, "medium", 13, P.ash, "LEFT")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text:SetText(label)
    b:SetSize(_max(24, (b.text.GetStringWidth and b.text:GetStringWidth() or 60) + 4), 22)
    b.line = Solid(b, "OVERLAY", 0, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 1)
    b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 0)
    b.line:SetHeight(2)
    b.SetOn = function(on)
        b.on = on
        local c = on and P.ivory or P.ash
        b.text:SetTextColor(c[1], c[2], c[3])
        b.line:SetShown(on)
    end
    b:SetScript("OnEnter", function() b.text:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3]) end)
    b:SetScript("OnLeave", function() b.SetOn(b.on) end)
    return b
end

-- A dungeon's page from here: back comes to Trends.
local function OpenDungeonPage(name, chart, run)
    S.tab, S.selected, S.from, S.detailRun = "dungeons", name, "trends", run
    S.detailChart = chart or (MS.Flavor.progressStats and "rate" or "dps")
    S.compareA, S.compareB = nil, nil
    S.trendDay = nil
    GameTooltip:Hide()
    UI.RefreshStats()
end

local function MakeRow(parent)
    local row = Btn(parent)
    row:SetSize(380, LIST_ROW)
    HoverRow(row)
    row:SetScript("OnClick", function(self)
        if not self.data then return end
        -- Its page, chart on XP an hour (your DPS elsewhere).
        OpenDungeonPage(self.data.dungeon)
    end)
    row.cells = K.Cells(row, COLS, 13)
    row:SetScript("OnEnter", function(self)
        local d = self.data
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(d.dungeon, P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:AddLine(MS.Plural(d.runs, "%d run", "%d runs", d.runs) .. (d.time and ("  ·  " .. Hours(d.time)) or ""),
            P.ash[1], P.ash[2], P.ash[3])
        if d.xp then
            GameTooltip:AddDoubleLine(L["XP"], Thousands(d.xp), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Gold"], MS.FormatGold(d.gold), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        end
        GameTooltip:AddLine(L["Click for everything about this dungeon."], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- The dungeon filter's list, under its button.
local function MenuRow(m)
    local r = Btn(m)
    r:SetSize(m:GetWidth() - 8, MENU_ROW)
    r.hov = Solid(r, "BACKGROUND", 1, P.bronze[1], P.bronze[2], P.bronze[3], 0.14)
    r.hov:SetAllPoints(); r.hov:Hide()
    r.mark = Solid(r, "ARTWORK", 0, P.bronze[1], P.bronze[2], P.bronze[3], 1)
    r.mark:SetPoint("TOPLEFT"); r.mark:SetPoint("BOTTOMLEFT"); r.mark:SetWidth(2)
    r.lbl = Text(r, "medium", 13, P.ivory, "LEFT")
    r.lbl:SetPoint("LEFT", 10, 0); r.lbl:SetWidth(m:GetWidth() - 80)
    r.cnt = Text(r, "medium", 12, P.ash, "RIGHT")
    r.cnt:SetPoint("RIGHT", -8, 0)
    r:SetScript("OnEnter", function(self) self.hov:Show() end)
    r:SetScript("OnLeave", function(self) if not self.on then self.hov:Hide() end end)
    r:SetScript("OnClick", function(self)
        S.trendDungeon = self.key
        m:Hide()
        UI.RefreshStats(true)
    end)
    return r
end

local function OpenDungeonMenu(t)
    local m = t.menu
    if m:IsShown() then m:Hide(); return end
    local entries = { { label = L["All dungeons"] } }
    for _, d in ipairs(MS:TrendDungeons()) do
        if #entries >= MENU_MAX then break end
        entries[#entries + 1] = { key = d.dungeon, label = d.dungeon, runs = d.runs }
    end
    m:SetHeight(#entries * MENU_ROW + 8)
    for i, en in ipairs(entries) do
        local r = m.rowAt(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", m, "TOPLEFT", 4, -4 - (i - 1) * MENU_ROW)
        r.key, r.on = en.key, en.key == S.trendDungeon
        r.hov:SetShown(r.on); r.mark:SetShown(r.on)
        r.lbl:SetText(en.label)
        r.cnt:SetText(en.runs and MS.Plural(en.runs, "%d run", "%d runs") or "")
    end
    m.rowsHideFrom(#entries + 1)
    m:Show()
end

-- A day's runs: a panel over the week's numbers, opened from the calendar.
local function MakeDayRow(parent)
    local r = Btn(parent)
    r:SetSize(DAY_W - 24, DAY_ROW)
    HoverRow(r)
    r.clock = Text(r, "medium", 12, P.ash, "LEFT")
    r.clock:SetPoint("LEFT", r, "LEFT", 2, 0); r.clock:SetWidth(64)
    r.name = Text(r, "medium", 13, P.ivory, "LEFT")
    r.name:SetPoint("LEFT", r, "LEFT", 70, 0); r.name:SetWidth(178)
    r.dur = Text(r, "medium", 13, P.ivory, "CENTER")
    r.dur:SetPoint("CENTER", r, "LEFT", 284, 0)
    r.val = Text(r, "medium", 13, P.ivory, "RIGHT")
    r.val:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r:SetScript("OnClick", function(self) if self.entry then OpenDungeonPage(self.entry.dungeon, "time", self.entry) end end)
    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.dungeon or "?", P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:AddLine(K.Result(e) .. CT(P.ash, "  ·  " .. K.Dur(e.dur or 0)))
        if e.prog then UI.AddProgressLines(e.prog, true) end
        if e.me and (e.me.dps or 0) > 0 then
            GameTooltip:AddDoubleLine(L["Your DPS"], Thousands(e.me.dps), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        end
        GameTooltip:AddLine(L["Click to see just this run."], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function BuildDayPanel(t)
    local p = CreateFrame("Frame", nil, t)
    p:SetFrameStrata("DIALOG"); p:EnableMouse(true)
    Box(p)
    p:SetWidth(DAY_W)
    p:SetPoint("TOPLEFT", t, "TOPLEFT", SUM_X - 14, -(GRID_TOP - 12))
    p.title = Text(p, "semibold", 15, P.ivory, "LEFT")
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -12)
    p.summary = Text(p, "medium", 12, P.ash, "LEFT")
    p.summary:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -34)
    p.summary:SetWidth(DAY_W - 28)
    local close = Btn(p)
    close:SetSize(22, 22); close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, -6)
    local x = Art(close, "Close", "OVERLAY")
    x:SetSize(11, 11); x:SetPoint("CENTER"); Tint(x, P.ash)
    close:SetScript("OnEnter", function() Tint(x, P.ivory) end)
    close:SetScript("OnLeave", function() Tint(x, P.ash) end)
    close:SetScript("OnClick", function() S.trendDay = nil; UI.RefreshStats(true) end)
    p.close = close
    p.rowAt, p.rowsHideFrom = Pool(function() return MakeDayRow(p) end)
    p.more = Text(p, "medium", 11, P.ash, "LEFT")
    p:Hide()
    return p
end

-- The Trends tab, a part at a time (BuildTrends, below). Activity: a
-- square a day.
local function BuildActivity(t)
    -- Activity: a square a day.
    t.actTitle = Heading(t, X0, 16, L["Activity"])
    local grid = CreateFrame("Frame", nil, t)
    grid:SetPoint("TOPLEFT", t, "TOPLEFT", X0, -GRID_TOP)
    grid:SetSize(GRID_W, 7 * (CELL + CELL_GAP) - CELL_GAP)
    t.grid = grid
    t.cellAt, t.cellsHideFrom = Pool(function() return MakeCell(grid) end)
    t.gridFrom = Text(t, "medium", 11, P.ash, "LEFT")
    t.gridFrom:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -6)
    t.gridTo = Text(t, "medium", 11, P.ash, "RIGHT")
    t.gridTo:SetPoint("TOPRIGHT", grid, "BOTTOMRIGHT", 0, -6)
    t.gridTo:SetText(L["Today"])
    t.sums = {}
    for i, label in ipairs({ L["This week"], L["Last week"], L["Streak"] }) do
        local y = GRID_TOP + (i - 1) * 38
        local lbl = Text(t, "medium", 12, P.ash, "LEFT")
        lbl:SetPoint("TOPLEFT", t, "TOPLEFT", SUM_X, -y); lbl:SetText(label)
        local val = Text(t, "semibold", 15, P.ivory, "LEFT")
        val:SetPoint("TOPLEFT", t, "TOPLEFT", SUM_X, -(y + 15))
        t.sums[i] = val
    end

end

-- The chart, its choices and which dungeon.
local function BuildTrendChart(t)
    -- The chart: what it shows (a row of choices), then which dungeon and
    -- how far back; a dot a run, and the trend through them.
    t.metricBtns = {}
    for i, m in ipairs(METRICS) do
        local b = Choice(t, L[m.label])
        if i == 1 then b:SetPoint("TOPLEFT", t, "TOPLEFT", X0, -(PERF_TOP - 3))
        else b:SetPoint("LEFT", t.metricBtns[i - 1], "RIGHT", 16, 0) end
        b.key = m.key
        b:SetScript("OnClick", function() S.trendMetric = m.key; UI.RefreshStats(true) end)
        t.metricBtns[i] = b
    end
    -- Under the choices: how far the trend has moved (left), the range (right).
    t.perfChange = Text(t, "semibold", 13, P.ivory, "LEFT")
    t.perfChange:SetPoint("TOPLEFT", t, "TOPLEFT", X0, -(PERF_TOP + 30))

    -- Which dungeon: above the choices, at their left.
    local dd = Btn(t)
    Box(dd, true)
    dd:SetSize(190, 22)
    dd:SetPoint("TOPLEFT", t, "TOPLEFT", X0, -(PERF_TOP - 30))
    dd.text = Text(dd, "medium", 13, P.ivory, "LEFT")
    dd.text:SetPoint("LEFT", dd, "LEFT", 10, 0); dd.text:SetWidth(154)
    local arrow = Art(dd, "Chevron", "OVERLAY")
    arrow:SetSize(10, 10); arrow:SetPoint("RIGHT", dd, "RIGHT", -8, 0); Tint(arrow, P.ash)
    dd:SetScript("OnClick", function() OpenDungeonMenu(t) end)
    t.dd = dd
    local menu = CreateFrame("Frame", nil, t)
    menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:EnableMouse(true)
    Box(menu)
    menu:SetWidth(280)
    menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -4)
    menu.rowAt, menu.rowsHideFrom = Pool(function() return MenuRow(menu) end)
    menu:Hide()
    t.menu = menu

    t.rangeBtns = {}
    for i = #RANGES, 1, -1 do      -- right to left: All time, 30 days, 7 days
        local r = RANGES[i]
        local b = Choice(t, r.days and MS.Plural(r.days, "%d day", "%d days", r.days) or L["All time"])
        if i == #RANGES then b:SetPoint("TOPRIGHT", t, "TOPLEFT", CHART_L + CHART_W, -(PERF_TOP + 27))
        else b:SetPoint("RIGHT", t.rangeBtns[#t.rangeBtns], "LEFT", -14, 0) end
        b.days = r.days
        b:SetScript("OnClick", function() S.trendRange = r.days; UI.RefreshStats(true) end)
        t.rangeBtns[#t.rangeBtns + 1] = b
    end

    local c = Chart(t, CHART_L, CHART_TOP, CHART_W, CHART_H)
    c.Tip = function(pt)
        local m = c.metric
        GameTooltip:AddDoubleLine(L[m.label], MetricText(m, pt.v), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Trend"], m.fmt == "whole" and _fmt("%.1f", pt.avg) or MetricText(m, pt.avg),
            P.ash[1], P.ash[2], P.ash[3], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        if pt == c.best then GameTooltip:AddLine(L["Your best run here"], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3]) end
        GameTooltip:AddLine(L["Click to see just this run."], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
    end
    c.Click = function(pt)                    -- that run, on its dungeon's page
        if pt.e.dungeon then OpenDungeonPage(pt.e.dungeon, "time", pt.e) end
    end
    t.chart = c
    t.day = BuildDayPanel(t)

end

-- A row per dungeon, sortable by any column.
local function BuildDungeonList(t)
    -- Right: a row per dungeon.
    t.listTitle = Heading(t, RIGHT_X, 16)
    t.listNote = Text(t, "regular", 12, P.ash, "LEFT")
    t.listNote:SetPoint("TOPLEFT", t, "TOPLEFT", RIGHT_X, -34)
    t.listNote:SetWidth(380); t.listNote:SetWordWrap(true)
    local band = Band(t, COLS, 8)            -- the right column's width only
    band:SetPoint("TOPLEFT", t, "TOPLEFT", RIGHT_X - 8, -60); band:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, -60)
    t.band = band
    -- Click a column's name to sort by it; again, the other way; a third
    -- time, back to the usual order.
    t.sortBtns = {}
    local hx = 8
    for _, col in ipairs(COLS) do
        local hb = Btn(band)
        hb:SetSize(col.w, COL_HDR_H)
        hb:SetPoint("LEFT", band, "LEFT", hx, 0)
        hx = hx + col.w
        local lbl = band.labels[col.key]
        hb.arrow = Art(hb, "Chevron", "OVERLAY")
        hb.arrow:SetSize(9, 9); hb.arrow:SetPoint("LEFT", lbl, "RIGHT", 3, 0); hb.arrow:Hide()
        Tint(hb.arrow, P.ivory)
        hb.Look = function()
            local on = S.trendSort and S.trendSort.key == col.key
            local col2 = on and P.ivory or P.ash
            lbl:SetTextColor(col2[1], col2[2], col2[3])
            hb.arrow:SetShown(on and true or false)
            if on then hb.arrow:SetRotation(S.trendSort.desc and 0 or math.pi) end
        end
        hb:SetScript("OnClick", function()
            local cur = S.trendSort
            if not cur or cur.key ~= col.key then S.trendSort = { key = col.key, desc = col.key ~= "dungeon", turns = 1 }
            elseif cur.turns == 1 then cur.desc = not cur.desc; cur.turns = 2
            else S.trendSort = nil end
            UI.RefreshStats(true)
        end)
        hb:SetScript("OnEnter", function(self)
            lbl:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3])
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Click to sort."], 1, 1, 1)
            GameTooltip:Show()
        end)
        hb:SetScript("OnLeave", function() hb.Look(); GameTooltip:Hide() end)
        t.sortBtns[#t.sortBtns + 1] = hb
    end
    t.rowAt, t.rowsHideFrom = Pool(function() return MakeRow(t) end)
    t.noList = Text(t, "regular", 14, P.ash, "CENTER")
    t.noList:SetPoint("TOP", t, "TOPLEFT", RIGHT_X + 190, -(60 + COL_HDR_H + 40))
    t.noList:SetWidth(340); t.noList:SetWordWrap(true)
end

local function BuildTrends(parent)
    local t = CreateFrame("Frame", nil, parent)
    t:SetAllPoints()

    BuildActivity(t)
    BuildTrendChart(t)
    BuildDungeonList(t)
    return t
end

-- ── Filling ────────────────────────────────────────────────────────────────
local function FillActivity(t, a)
    for i, cell in ipairs(a.cells) do
        local b = t.cellAt(i)
        b.cell = cell
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", t.grid, "TOPLEFT", (cell.col - 1) * (CELL + CELL_GAP), -(cell.row - 1) * (CELL + CELL_GAP))
        local col, alpha = CellColor(cell.runs, a.most)
        b.sq:SetColorTexture(col[1], col[2], col[3], cell.future and 0 or alpha)
        b:SetShown(not cell.future)
        b.ring:SetShown(S.trendDay ~= nil and date("%Y%m%d", S.trendDay) == date("%Y%m%d", cell.at))
    end
    t.cellsHideFrom(#a.cells + 1)
    t.gridFrom:SetText(Day(a.cells[1].at))
    local function Week(w)
        if w.runs == 0 then return CT(P.ash, L["No runs"]) end
        return Hours(w.time) .. CT(P.ash, "  ·  " .. MS.Plural(w.runs, "%d run", "%d runs", w.runs))
    end
    t.sums[1]:SetText(Week(a.thisWeek))
    t.sums[2]:SetText(Week(a.lastWeek))
    t.sums[3]:SetText(MS.Plural(a.streak, "%d day", "%d days", a.streak)
        .. CT(P.ash, "  " .. _fmt(L["(best %s)"], MS.Plural(a.bestStreak, "%d day", "%d days", a.bestStreak))))
end

local function FillPerf(t, ts)
    if S.trendMetric and not METRIC[S.trendMetric] then S.trendMetric = nil end
    local m = METRIC[S.trendMetric or (ts.perf.heals and "hps" or "dps")]
    for _, b in ipairs(t.metricBtns) do b.SetOn(b.key == m.key) end
    for _, b in ipairs(t.rangeBtns) do b.SetOn(b.days == S.trendRange) end
    t.dd.text:SetText(S.trendDungeon or L["All dungeons"])
    t.menu:Hide()
    local series = MS.TrendSeries(MS:TrendRuns(S.trendDungeon, S.trendRange), m.value, m.lower)
    local c = t.chart
    -- Down to the bottom of the page, leaving room for the dates under it.
    local th = t:GetHeight() or 0
    if th > CHART_TOP + 120 then
        c.h = _floor(th - CHART_TOP - 28)
        c:SetHeight(c.h)
    end
    c.metric, c.best = m, series.best
    DrawChart(c, series.points, MetricAxis(m))
    if #series.points >= 2 then
        for i, pt in ipairs(series.points) do
            if pt == series.best then Tint(c.pointAt(i).dot, P.bronzeHi) end
        end
    end
    t.perfChange:SetText(ChangeText(series.change, m.lower))
end

local function FillDay(t)
    local p = t.day
    local d = S.trendDay and MS:TrendDay(S.trendDay)
    if not d or #d.runs == 0 then S.trendDay = nil; p:Hide(); return end
    p.title:SetText(date("%A, ", d.at) .. Day(d.at))
    local parts = { MS.Plural(#d.runs, "%d run", "%d runs", #d.runs), Hours(d.time) }
    if MS.Flavor.progressStats then
        if d.xp > 0 then parts[#parts + 1] = _fmt(L["%s XP"], Short(d.xp)) end
        if d.gold > 0 then parts[#parts + 1] = CT(P.bronzeHi, MS.FormatGold(d.gold)) end
        if d.levels > 0 then parts[#parts + 1] = MS.Plural(d.levels, "+%d level", "+%d levels") end
    end
    p.summary:SetText(table.concat(parts, "  ·  "))
    local n = _min(#d.runs, DAY_MAX)
    for i = 1, n do
        local e = d.runs[i]
        local r = p.rowAt(i)
        r.entry = e
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -(58 + (i - 1) * DAY_ROW))
        r.clock:SetText(e.at and MS.ClockTime(e.at) or "")
        r.name:SetText(e.dungeon or "?")
        local col = e.cleared and P.ivory or P.ash
        r.name:SetTextColor(col[1], col[2], col[3])
        r.dur:SetText(K.Dur(e.dur or 0))
        if MS.Flavor.progressStats then
            local mobXP, questXP = UI.RunXP(e.prog)
            r.val:SetText(e.prog and _fmt(L["%s XP"], Short(mobXP + questXP)) or CT(P.ash2, "-"))
        else
            r.val:SetText(e.me and (e.me.dps or 0) > 0 and (Short(e.me.dps) .. " " .. L["DPS"]) or CT(P.ash2, "-"))
        end
    end
    p.rowsHideFrom(n + 1)
    local h = 58 + n * DAY_ROW + 10
    p.more:ClearAllPoints()
    p.more:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -(58 + n * DAY_ROW + 4))
    if #d.runs > n then
        p.more:SetText(_fmt(L["and %d more"], #d.runs - n))
        p.more:Show()
        h = h + 16
    else
        p.more:Hide()
    end
    p:SetHeight(h)
    p:Show()
end

local function FillList(t, ts)
    local rows
    if ts.farming then
        local f = ts.farming
        rows = f.rows
        t.listTitle:SetText(L["XP and gold an hour"])
        t.listNote:SetText(f.level and _fmt(L["From your own runs. Near your level (%d) first."], f.level)
            or L["From your own runs."])
        t.noList:SetText(L["Shows once you've finished a run here since XP and gold started being recorded."])
    else
        rows = ts.byDungeon
        t.listTitle:SetText(L["Your DPS by dungeon"])
        t.listNote:SetText(L["Your average and best in each dungeon."])
        t.noList:SetText(L["Your numbers show here after a couple of runs."])
    end
    -- The best near your level (or of all, with no level to go by) in bronze,
    -- whatever the order.
    local bestRow
    if ts.farming then
        local f = ts.farming
        for _, d in ipairs(rows) do
            if d.near or f.level == nil then
                local v = f.byGold and d.goldHour or d.xpHour
                if not bestRow or v > (f.byGold and bestRow.goldHour or bestRow.xpHour) then bestRow = d end
            end
        end
    end
    -- Sorted by a column, if one was clicked.
    local sort = S.trendSort
    if sort then
        local KEY = {
            dungeon = function(d) return d.dungeon end,
            levels = function(d) return d.lo or -1 end,
            xp = function(d) return d.xpHour end,
            gold = function(d) return d.goldHour end,
            runs = function(d) return d.runs end,
            avg = function(d) return d.avg end,
            best = function(d) return d.best end,
        }
        local key = KEY[sort.key]
        if key then
            local sorted = {}
            for i, d in ipairs(rows) do sorted[i] = d end
            table.sort(sorted, function(a, b)
                local ka, kb = key(a), key(b)
                if ka ~= kb then
                    if sort.desc then return ka > kb end
                    return ka < kb
                end
                return a.dungeon < b.dungeon
            end)
            rows = sorted
        end
    end
    for _, hb in ipairs(t.sortBtns) do hb.Look() end
    local n = _min(#rows, MAX_ROWS)
    for i = 1, n do
        local d = rows[i]
        local row = t.rowAt(i)
        row.data = d
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", t, "TOPLEFT", RIGHT_X, -(60 + COL_HDR_H + (i - 1) * LIST_ROW))
        local cl = row.cells
        cl.dungeon:SetText(d.dungeon)
        if ts.farming then
            local dim = not d.near and ts.farming.level ~= nil
            local col = dim and P.ash or P.ivory
            cl.dungeon:SetTextColor(col[1], col[2], col[3])
            cl.levels:SetText(d.lo and (d.lo == d.hi and tostring(d.lo) or (d.lo .. "–" .. d.hi)) or "-")
            cl.levels:SetTextColor(P.ash[1], P.ash[2], P.ash[3])
            local top = d == bestRow
            local xpCol = top and not ts.farming.byGold and P.bronzeHi or col
            local goldCol = top and ts.farming.byGold and P.bronzeHi or (dim and P.ash or P.bronzeHi)
            cl.xp:SetText(d.xpHour > 0 and Short(d.xpHour) or "-")
            cl.xp:SetTextColor(xpCol[1], xpCol[2], xpCol[3])
            cl.gold:SetText(GoldShort(d.goldHour))
            cl.gold:SetTextColor(goldCol[1], goldCol[2], goldCol[3])
        else
            cl.runs:SetText(tostring(d.runs))
            cl.avg:SetText(Thousands(d.avg))
            cl.best:SetText(Thousands(d.best))
        end
    end
    t.rowsHideFrom(n + 1)
    t.noList:SetShown(n == 0)
end

local function FillTrends(t, ts)
    FillActivity(t, ts.activity)
    FillPerf(t, ts)
    FillList(t, ts)
    FillDay(t)
end

K.BuildTrends, K.FillTrends = BuildTrends, FillTrends
-- For a dungeon's page (UI_StatsDungeon.lua), built after this file loads.
K.TrendChart, K.DrawTrendChart, K.TrendChange = Chart, DrawChart, ChangeText
K.Thousands, K.Short, K.GoldShort, K.Heading = Thousands, Short, GoldShort, Heading

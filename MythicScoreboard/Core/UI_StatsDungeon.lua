local _ceil, _floor, _max, _min = math.ceil, math.floor, math.max, math.min
local _fmt = string.format

local MS = _G["MythicScoreboard"]
local L = MS.L
local LK = MS.LK      -- a label kept in English, translated where it is shown
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local P, COL_HDR_H, FRAME_W = UI.P, UI.COL_HDR_H, UI.FRAME_W
local Text, Solid, Btn, Tint, Art = UI.Text, UI.Solid, UI.Btn, UI.Tint, UI.Art
local VGrad, MakeScrollFrame, CT, Abbrev = UI.VGrad, UI.MakeScrollFrame, UI.CT, UI.Abbrev
local FIGHT_BOT, FIGHT_TOP = UI.FIGHT_BOT, UI.FIGHT_TOP

-- Stats page, part 2: one dungeon (its numbers, a chart, every run, its
-- bosses, by level, where its XP and gold came from), and two of its runs
-- compared side by side. Built and filled
-- from UI_Stats.lua through UI.StatsKit; the page's state is K.S.

local K = UI.StatsKit                  -- shared by UI_Stats.lua
local BOSS_COL, Band, Cells, CharName = K.BOSS_COL, K.Band, K.Cells, K.CharName
local Day, Dur, HoverRow, LEFT_W, LIST_ROW = K.Day, K.Dur, K.HoverRow, K.LEFT_W, K.LIST_ROW
local MakeBossRow, Pct, Pool, RCOLS = K.MakeBossRow, K.Pct, K.Pool, K.RCOLS
local RIGHT_W, RIGHT_X, Result, S, TwoClick = K.RIGHT_W, K.RIGHT_X, K.Result, K.S, K.TwoClick
local X0 = K.X0

-- ── Detail: one dungeon ────────────────────────────────────────────────────
local function RunTooltip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(Day(e.at) .. (e.at and date("  %H:%M", e.at) or ""), P.ivory[1], P.ivory[2], P.ivory[3])
    GameTooltip:AddDoubleLine(L["Time"], Dur(e.dur), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Result"], Result(e), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
    if S.multiChar and MS:RunOwner(e) then
        GameTooltip:AddDoubleLine(L["Character"], CharName(MS:RunOwner(e)), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
    end
    if e.me and e.me.lvl then GameTooltip:AddDoubleLine(L["Your level"], e.me.lvl, P.ash[1], P.ash[2], P.ash[3], 1, 1, 1) end
    if e.me then GameTooltip:AddDoubleLine(L["Your DPS"], Abbrev(e.me.dps), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1) end
    GameTooltip:AddDoubleLine(L["Group deaths"], e.deaths or 0, P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
    if e.prog then UI.AddProgressLines(e.prog, true) end
    for _, b in ipairs(e.bosses or {}) do
        GameTooltip:AddDoubleLine(b.n, Dur(b.t), P.ash[1], P.ash[2], P.ash[3], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
    end
    GameTooltip:AddLine(S.detailRun == e and L["Click again for all runs."] or L["Click to see just this run."],
        P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
    GameTooltip:Show()
end

-- One run picked from the chart or the list: the page shows its numbers
-- (a second click, or the x by its date, goes back to all of them).
local function PickRun(e)
    S.detailRun = (S.detailRun ~= e) and e or nil
    GameTooltip:Hide()
    UI.RefreshStats(true)
end

local function MakeChartBar(parent)
    local b = Btn(parent)
    b:SetScript("OnClick", function(self) if self.entry then PickRun(self.entry) end end)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("BOTTOMLEFT"); b.fill:SetPoint("BOTTOMRIGHT")
    b.hi = Solid(b, "OVERLAY", 0, 1, 0.94, 0.86, 0.12); b.hi:SetAllPoints(); b.hi:Hide()
    b:SetScript("OnEnter", function(self) self.hi:Show(); RunTooltip(self, self.entry) end)
    b:SetScript("OnLeave", function(self) self.hi:Hide(); GameTooltip:Hide() end)
    return b
end

local function MakeRunRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LEFT_W, LIST_ROW)
    row:EnableMouse(true)
    HoverRow(row)
    row.cells = Cells(row, RCOLS, 14)
    if row.cells.bosses then row.cells.bosses:SetWidth(RCOLS[#RCOLS].w - 100) end
    row:SetScript("OnEnter", function(self) RunTooltip(self, self.entry) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.entry then PickRun(self.entry) end
    end)
    row.pick = Solid(row, "BACKGROUND", 0, P.bronze[1], P.bronze[2], P.bronze[3], 0.14)   -- the run picked
    row.pick:SetAllPoints(); row.pick:Hide()

    -- Remove from stats (two clicks).
    local del = Btn(row)
    del:SetSize(22, LIST_ROW)
    del:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    del:SetFrameLevel(row:GetFrameLevel() + 2)
    local icon = Art(del, L["Close"], "OVERLAY")
    icon:SetSize(11, 11); icon:SetPoint("CENTER"); Tint(icon, P.ash2)
    TwoClick(del, function(armed) Tint(icon, armed and P.bloodHi or P.ash2) end, function()
        GameTooltip:Hide()
        MS:RemoveArchivedRun(row.entry)
        UI.RefreshStats(true)
    end)
    del:SetScript("OnEnter", function(self)
        Tint(icon, P.bloodHi)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Remove from stats"], P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:AddLine(self.IsArmed() and L["Click again to remove this run."]
            or L["Leaves your run history untouched."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    del:SetScript("OnLeave", function(self)
        if not self.IsArmed() then Tint(icon, P.ash2) end
        GameTooltip:Hide()
    end)
    row.del = del

    -- Compare: pick this run, then another.
    local cmp = Btn(row)
    cmp:SetSize(62, LIST_ROW)
    cmp:SetPoint("RIGHT", del, "LEFT", -2, 0)
    cmp:SetFrameLevel(row:GetFrameLevel() + 2)
    cmp.text = Text(cmp, "medium", 12, P.ash2, "RIGHT")
    cmp.text:SetPoint("RIGHT", cmp, "RIGHT", -2, 0)
    cmp:SetScript("OnClick", function()
        GameTooltip:Hide()
        local e = row.entry
        if S.compareA == e then S.compareA = nil
        elseif S.compareA then S.compareB = e
        else S.compareA = e end
        UI.RefreshStats(true)
    end)
    cmp:SetScript("OnEnter", function(self)
        self.text:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if S.compareA == row.entry then
            GameTooltip:SetText(L["Picked for comparison"])
            GameTooltip:AddLine(L["Click again to cancel."], 0.8, 0.8, 0.8, true)
        elseif S.compareA then
            GameTooltip:SetText(L["Compare with the picked run"])
        else
            GameTooltip:SetText(L["Compare"])
            GameTooltip:AddLine(L["Pick this run, then another one, to see them side by side."], 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    cmp:SetScript("OnLeave", function(self) self.Look(); GameTooltip:Hide() end)
    cmp.Look = function()
        local picked = S.compareA ~= nil and S.compareA == row.entry
        cmp.text:SetText(picked and L["Picked"] or L["Compare"])
        local c = picked and P.bronzeHi or S.compareA and P.ivory or P.ash2
        cmp.text:SetTextColor(c[1], c[2], c[3])
    end
    row.cmp = cmp
    return row
end

-- The page: a band on top (back, the dungeon, a summary); left, the headline
-- numbers, a chart (run times, or XP an hour / your DPS run by run) and every
-- run; right, scrolling: the bosses, the dungeon by level (by difficulty
-- elsewhere) and, on WoW Forever, where its XP and gold came from. Opened from
-- the Dungeons tab or the Trends tab's list (back goes to whichever).
-- The rate chart and the number formats are the Trends tab's (K.TrendChart
-- and the rest, from UI_StatsTrends.lua, there by the time this is built).
local forever = MS.Flavor.progressStats
local TILE_TOP, TILE_H, TILES_A_ROW = COL_HDR_H + 12, 46, 4
local TILE_W = LEFT_W / TILES_A_ROW
local CHART_TOP = TILE_TOP + 2 * TILE_H + 12      -- the chart's heading
local DCHART_H = 104
local LIST_TOP = CHART_TOP + 26 + DCHART_H + 26
local SEC_GAP = 12
local CMP_ROW, CMP_ROWS, CMP_NAME_W, CMP_BAR_W = 17, 5, 200, 360   -- one run: compared with your other dungeons
local SEC_TOP = COL_HDR_H + 6                    -- the right column, just under the top band
local SPLIT_W = RIGHT_W - 14
-- "Where it came from", top to bottom: the XP and gold splits, the counts, reputation.
local SRC_XP, SRC_GOLD, SRC_COUNTS, SRC_REP = 26, 88, 152, 196
local REP_ROW, REP_GAP = 18, 20

local TLCOLS = {   -- WoW Forever: by your level
    { key = "group",   label = LK("Level"),     w = 54, left = true },
    { key = "runs",    label = LK("Runs"),      w = 56 },
    { key = "typical", label = LK("Typical"),   w = 70 },
    { key = "xp",      label = LK("XP/hour"),   w = 90 },
    { key = "gold",    label = LK("Gold/hour"), w = 104 },
}
local TKCOLS = {   -- elsewhere: by key level or difficulty
    { key = "group",   label = LK("Difficulty"), w = 114, left = true },
    { key = "runs",    label = LK("Runs"),       w = 56 },
    { key = "typical", label = LK("Typical"),    w = 70 },
    { key = "avg",     label = LK("Average"),    w = 67 },
    { key = "best",    label = LK("Best"),       w = 67 },
}
local GCOLS = forever and TLCOLS or TKCOLS

-- The chart's choices besides run time: a number per run, plotted with its
-- trend. lower: lower is better (the best run is the lowest).
local function Me(e) return e.me end
local METRICS = {
    { key = "dps",    label = LK("DPS"),          value = function(e) local m = Me(e); return m and (m.dps or 0) > 0 and m.dps or nil end },
    { key = "hps",    label = LK("HPS"),          value = function(e) local m = Me(e); return m and (m.hps or 0) > 0 and m.hps or nil end },
    { key = "taken",  label = LK("Damage taken"), value = function(e) local m = Me(e); return m and m.taken end, lower = true },
    { key = "deaths", label = LK("Deaths"),       value = function(e) return e.deaths or 0 end, lower = true, whole = true },
}
if forever then   -- XP an hour first (gold an hour once a dungeon gives no XP)
    table.insert(METRICS, 1, { key = "rate", label = LK("XP an hour") })
end
local METRIC = {}
for _, m in ipairs(METRICS) do METRIC[m.key] = m end

local function AddLine(label, value, col)
    col = col or P.ivory
    GameTooltip:AddDoubleLine(label, value, P.ash[1], P.ash[2], P.ash[3], col[1], col[2], col[3])
end

local function SecHeading(parent, text)
    local h = Text(parent, "medium", 13, P.ash, "LEFT")
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    h:SetText(text)
    return h
end

local function MakeTile(parent, i)
    local x = X0 + ((i - 1) % TILES_A_ROW) * TILE_W
    local y = TILE_TOP + _floor((i - 1) / TILES_A_ROW) * TILE_H
    local tile = {}
    tile.label = Text(parent, "medium", 12, P.ash, "LEFT")
    tile.label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    tile.label:SetWidth(TILE_W - 12)
    tile.value = Text(parent, "semibold", 18, P.ivory, "LEFT")
    tile.value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y + 16))
    tile.value:SetWidth(TILE_W - 12)
    return tile
end

local function MakeGroupRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(RIGHT_W, LIST_ROW)
    row:EnableMouse(true)
    HoverRow(row)
    row.cells = Cells(row, GCOLS, 13)
    row:SetScript("OnEnter", function(self)
        local g = self.data
        if not g then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(forever and (g.key and _fmt(L["Level %d"], g.key) or "?") or tostring(g.key),
            P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:AddLine(MS.Plural(g.runs, "%d run", "%d runs", g.runs) .. "  ·  " .. K.Hours(g.time), P.ash[1], P.ash[2], P.ash[3])
        if forever then
            AddLine(L["XP"], K.Thousands(g.xp))
            AddLine(L["Gold"], MS.FormatGold(g.gold), P.bronzeHi)
        else
            AddLine(L["Your DPS"], K.Thousands(g.avgDps))
            AddLine(L["Your best DPS"], K.Thousands(g.best), P.bronzeHi)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- A thin bar split two ways, with its two parts named underneath.
local function MakeSplit(parent, y)
    local s = {}
    s.title = Text(parent, "medium", 12, P.ash, "LEFT")
    s.title:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    s.total = Text(parent, "semibold", 13, P.ivory, "RIGHT")
    s.total:SetPoint("TOPRIGHT", parent, "TOPLEFT", SPLIT_W, -y)
    s.a = Solid(parent, "ARTWORK", 0, 1, 1, 1, 1)
    s.a:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y + 20)); s.a:SetHeight(8)
    s.b = Solid(parent, "ARTWORK", 0, 1, 1, 1, 1)
    s.b:SetPoint("TOPLEFT", s.a, "TOPRIGHT", 0, 0); s.b:SetHeight(8)
    s.legend = Text(parent, "medium", 11, P.ash, "LEFT")
    s.legend:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y + 34))
    s.legend:SetWidth(SPLIT_W)
    return s
end

local function FillSplit(s, title, total, a, b, colA, colB, nameA, nameB)
    s.title:SetText(title)
    s.total:SetText(total)
    local sum = a + b
    local wa = sum > 0 and _floor(SPLIT_W * a / sum + 0.5) or SPLIT_W
    s.a:SetColorTexture(colA[1], colA[2], colA[3], sum > 0 and 1 or 0.25)
    s.a:SetWidth(_max(1, wa))
    s.b:SetColorTexture(colB[1], colB[2], colB[3], 1)
    s.b:SetWidth(_max(1, SPLIT_W - wa))
    s.b:SetShown(sum > 0 and b > 0)
    local function Part(col, name, n)
        return UI.Swatch(col, 8, 8) .. " " .. name .. "  " .. CT(P.ivory, Pct(n, sum))
    end
    s.legend:SetText(sum > 0 and (Part(colA, nameA, a) .. "      " .. Part(colB, nameB, b)) or "")
end

-- A choice of chart above it: plain text, the one shown in ivory and underlined.
local function MakeChartChoice(parent, key, label)
    local b = Btn(parent)
    b.text = Text(b, "medium", 13, P.ash, "LEFT")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text:SetText(label)
    b:SetSize(_max(40, (b.text.GetStringWidth and b.text:GetStringWidth() or 80) + 4), 22)
    b.line = Solid(b, "OVERLAY", 0, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 1)
    b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 0)
    b.line:SetHeight(2)
    b.Look = function()
        local on = (S.detailChart or "time") == key
        local c = on and P.ivory or P.ash
        b.text:SetTextColor(c[1], c[2], c[3])
        b.line:SetShown(on)
    end
    b:SetScript("OnClick", function() S.detailChart = key; UI.RefreshStats(true) end)
    b:SetScript("OnEnter", function() b.text:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3]) end)
    b:SetScript("OnLeave", function() b.Look() end)
    return b
end

local function BuildDetail(parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetAllPoints()
    local band = Band(d)
    band:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, 0)

    local back = Btn(band)
    back:SetPoint("LEFT", band, "LEFT", X0 - 4, 0); back:SetSize(128, COL_HDR_H - 6)
    local arrow = Art(back, "Chevron", "OVERLAY")
    arrow:SetSize(12, 12); arrow:SetPoint("LEFT", back, "LEFT", 4, 0)
    arrow:SetRotation(-math.pi / 2); Tint(arrow, P.ash)
    local backTxt = Text(back, "medium", 13, P.ash, "LEFT")
    backTxt:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    back:SetScript("OnEnter", function() Tint(arrow, P.ivory); backTxt:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3]) end)
    back:SetScript("OnLeave", function() Tint(arrow, P.ash); backTxt:SetTextColor(P.ash[1], P.ash[2], P.ash[3]) end)
    back:SetScript("OnClick", function()
        if S.from == "trends" then S.tab = "trends" end
        S.selected, S.from, S.detailRun = nil, nil, nil
        S.compareA, S.compareB = nil, nil
        UI.RefreshStats()
    end)
    d.back, d.backTxt = back, backTxt

    d.title = Text(band, "semibold", 15, P.ivory, "LEFT")
    d.title:SetPoint("LEFT", back, "RIGHT", 14, 0)
    d.summary = Text(band, "medium", 13, P.ash, "RIGHT")
    d.summary:SetPoint("RIGHT", band, "LEFT", X0 + LEFT_W, 0)
    local runX = Btn(band)                    -- back to all runs, beside a picked run's date
    runX:SetSize(20, 20); runX:SetPoint("RIGHT", band, "LEFT", X0 + LEFT_W, 0)
    local xIcon = Art(runX, "Close", "OVERLAY")
    xIcon:SetSize(10, 10); xIcon:SetPoint("CENTER"); Tint(xIcon, P.ash)
    runX:SetScript("OnEnter", function(self)
        Tint(xIcon, P.ivory)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L["Back to all runs"], 1, 1, 1); GameTooltip:Show()
    end)
    runX:SetScript("OnLeave", function() Tint(xIcon, P.ash); GameTooltip:Hide() end)
    runX:SetScript("OnClick", function() S.detailRun = nil; GameTooltip:Hide(); UI.RefreshStats(true) end)
    runX:Hide()
    d.runX = runX

    -- Headline numbers: two rows of four.
    d.tiles = {}
    for i = 1, 2 * TILES_A_ROW do d.tiles[i] = MakeTile(d, i) end

    -- The chart: run times, or the rate run by run.
    d.choices = { MakeChartChoice(d, "time", L["Run time"]) }
    d.choices[1]:SetPoint("TOPLEFT", d, "TOPLEFT", X0, -(CHART_TOP - 3))
    for _, m in ipairs(METRICS) do
        local b = MakeChartChoice(d, m.key, L[m.label])
        b:SetPoint("LEFT", d.choices[#d.choices], "RIGHT", 18, 0)
        d.choices[#d.choices + 1] = b
        if m.key == "rate" then d.choiceRate = b end
    end
    d.chartChange = Text(d, "semibold", 13, P.ivory, "RIGHT")
    d.chartChange:SetPoint("TOPRIGHT", d, "TOPLEFT", X0 + LEFT_W, -CHART_TOP)

    -- Run times: one bar per run, oldest on the left.
    local chart = CreateFrame("Frame", nil, d)
    chart:SetPoint("TOPLEFT", d, "TOPLEFT", X0 + 52, -(CHART_TOP + 26))
    chart:SetSize(LEFT_W - 52, DCHART_H)
    local base = Solid(chart, "BORDER", 0, P.line[1], P.line[2], P.line[3], 1)
    base:SetPoint("BOTTOMLEFT"); base:SetPoint("BOTTOMRIGHT"); base:SetHeight(1)
    d.typLine = Solid(chart, "OVERLAY", 0, P.verd[1], P.verd[2], P.verd[3], 0.55)
    d.typLine:SetHeight(1)
    d.typLbl = Text(chart, "medium", 11, P.verd, "RIGHT")
    d.yTop = Text(chart, "medium", 11, P.ash, "RIGHT")
    d.yTop:SetPoint("RIGHT", chart, "TOPLEFT", -8, 0)
    d.yBot = Text(chart, "medium", 11, P.ash, "RIGHT")
    d.yBot:SetPoint("RIGHT", chart, "BOTTOMLEFT", -8, 0); d.yBot:SetText("0:00")
    d.xFirst = Text(chart, "medium", 11, P.ash, "CENTER")   -- placed under the first and last bars
    d.xLast = Text(chart, "medium", 11, P.ash, "CENTER")
    d.bestLbl = Text(chart, "semibold", 11, P.bronzeHi, "CENTER")
    d.chart = chart
    d.barAt, d.barsHideFrom = Pool(function() return MakeChartBar(chart) end)

    -- The rate: a point a run and its trend.
    local rateHolder = CreateFrame("Frame", nil, d)
    rateHolder:SetAllPoints()
    local rc = K.TrendChart(rateHolder, X0 + 52, CHART_TOP + 26, LEFT_W - 52, DCHART_H)
    rc.Tip = function(pt)
        local e, m = pt.e, d.metric
        if m.key == "rate" then
            local fmt = d.byGold and K.GoldShort or K.Thousands
            AddLine(d.byGold and L["Gold/hour"] or L["XP/hour"], fmt(pt.v))
            AddLine(L["Trend"], fmt(pt.avg), P.bronzeHi)
            if e.prog then
                local mobXP, questXP = UI.RunXP(e.prog)
                AddLine(L["XP"], K.Thousands(mobXP + questXP))
                AddLine(L["Gold"], MS.FormatGold((e.prog.g or 0) + (e.prog.qg or 0)), P.bronzeHi)
            end
        else
            local fmt = m.whole and tostring or K.Thousands
            AddLine(L[m.label], fmt(pt.v))
            AddLine(L["Trend"], m.whole and _fmt("%.1f", pt.avg) or K.Thousands(pt.avg), P.bronzeHi)
        end
        if pt == d.bestPoint then GameTooltip:AddLine(L["Your best run here"], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3]) end
        GameTooltip:AddLine(S.detailRun == e and L["Click again for all runs."] or L["Click to see just this run."],
            P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
    end
    rc.Click = function(pt) PickRun(pt.e) end
    -- Under two runs there's no line to draw: this dungeon among your others
    -- instead, a bar each (its average), this one in bronze.
    d.cmpNote = Text(rateHolder, "medium", 12, P.ash, "LEFT")   -- under the bars: what comes later
    d.cmpNote:SetWidth(LEFT_W - CMP_NAME_W - 10); d.cmpNote:SetWordWrap(false)
    d.cmpAt, d.cmpHideFrom = Pool(function()
        local r = CreateFrame("Frame", nil, rateHolder)
        r:SetSize(LEFT_W, CMP_ROW)
        r:EnableMouse(true)
        r.name = Text(r, "medium", 12, P.ash, "RIGHT")
        r.name:SetPoint("RIGHT", r, "LEFT", CMP_NAME_W, 0); r.name:SetWidth(CMP_NAME_W - 4)
        r.bar = Solid(r, "ARTWORK", 0, 1, 1, 1, 1)
        r.bar:SetPoint("LEFT", r, "LEFT", CMP_NAME_W + 10, 0); r.bar:SetHeight(CMP_ROW - 6)
        r.val = Text(r, "semibold", 12, P.ivory, "LEFT")
        r.val:SetPoint("LEFT", r.bar, "RIGHT", 6, 0)
        r:SetScript("OnEnter", function(self)
            if not self.data then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.data.dungeon, P.ivory[1], P.ivory[2], P.ivory[3])
            GameTooltip:AddLine(MS.Plural(self.data.runs, "%d run", "%d runs", self.data.runs), P.ash[1], P.ash[2], P.ash[3])
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end)
    d.rateHolder, d.rate = rateHolder, rc

    -- Every run, newest first.
    local lband = Band(d, RCOLS, X0)
    lband:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -LIST_TOP); lband:SetWidth(X0 + LEFT_W)
    d.sf = MakeScrollFrame(d)
    d.sf:SetPoint("TOPLEFT", d, "TOPLEFT", X0, -(LIST_TOP + COL_HDR_H))
    d.sf:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", X0, 8)
    d.sf:SetWidth(LEFT_W + 10)
    d.rowAt, d.rowsHideFrom = Pool(function() return MakeRunRow(d.sf.scrollContent) end)

    -- Right, scrolling: bosses, by level, where it came from.
    d.rsf = MakeScrollFrame(d)
    -- From 8px left of the column (its headers' bands reach there) to the
    -- frame's right edge, so the scroll bar sits clear of the content.
    d.rsf:SetPoint("TOPLEFT", d, "TOPLEFT", RIGHT_X - 8, -SEC_TOP)
    d.rsf:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, 8)
    local content = d.rsf.scrollContent

    local sb = CreateFrame("Frame", nil, content)
    sb:SetWidth(RIGHT_W)
    local bband = Band(sb)                   -- its column header says what it is
    bband:SetPoint("TOPLEFT", sb, "TOPLEFT", -8, 0); bband:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
    local typLbl = Text(bband, "medium", 13, P.ash, "CENTER")
    typLbl:SetPoint("CENTER", bband, "RIGHT", -BOSS_COL / 2, 0); typLbl:SetText(L["Typical"])
    local bestLbl = Text(bband, "medium", 13, P.ash, "CENTER")
    bestLbl:SetPoint("CENTER", bband, "RIGHT", -BOSS_COL * 1.5, 0); bestLbl:SetText(L["Best"])
    d.bossHdrA, d.bossHdrB = bestLbl, typLbl     -- Best / Typical; for one run, Killed / Fight
    local nameLbl = Text(bband, "medium", 13, P.ash, "LEFT")
    nameLbl:SetPoint("LEFT", bband, "LEFT", 8, 0); nameLbl:SetText(L["Boss"])
    d.bossAt, d.bossesHideFrom = Pool(function()
        local row = MakeBossRow(sb)
        row:SetHeight(LIST_ROW)
        return row
    end)
    d.noBosses = Text(sb, "regular", 13, P.ash2, "LEFT")
    d.noBosses:SetPoint("TOPLEFT", sb, "TOPLEFT", 2, -(COL_HDR_H + 8))
    d.noBosses:SetText(L["No bosses killed here yet."])
    d.secBoss = sb

    local sg = CreateFrame("Frame", nil, content)
    sg:SetWidth(RIGHT_W)
    local gband = Band(sg, GCOLS, 8)         -- "Level" / "Difficulty" heads it
    gband:SetPoint("TOPLEFT", sg, "TOPLEFT", -8, 0); gband:SetPoint("TOPRIGHT", sg, "TOPRIGHT", 0, 0)
    d.groupAt, d.groupsHideFrom = Pool(function() return MakeGroupRow(sg) end)
    d.secGroup = sg

    -- One run picked: your own numbers in it, a line each.
    local sy = CreateFrame("Frame", nil, content)
    sy:SetWidth(RIGHT_W)
    d.youAt, d.youHideFrom = Pool(function()
        local r = CreateFrame("Frame", nil, sy)
        r:SetSize(RIGHT_W, 22)
        r.lbl = Text(r, "medium", 13, P.ash, "LEFT"); r.lbl:SetPoint("LEFT", r, "LEFT", 2, 0)
        r.val = Text(r, "semibold", 13, P.ivory, "RIGHT"); r.val:SetPoint("RIGHT", r, "RIGHT", -8, 0)
        local line = Solid(r, "BORDER", 0, P.line[1], P.line[2], P.line[3], 1)
        line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
        return r
    end)
    d.secYou = sy

    if forever then
        local ss = CreateFrame("Frame", nil, content)
        ss:SetWidth(RIGHT_W)
        SecHeading(ss, L["Where it came from"])
        d.xpSplit = MakeSplit(ss, SRC_XP)
        d.goldSplit = MakeSplit(ss, SRC_GOLD)
        -- Mobs killed / quests / levels gained: three small numbers in a row.
        d.counts = {}
        for i = 1, 3 do
            local x = (i - 1) * SPLIT_W / 3
            local lbl = Text(ss, "medium", 11, P.ash, "LEFT")
            lbl:SetPoint("TOPLEFT", ss, "TOPLEFT", x, -SRC_COUNTS)
            local val = Text(ss, "semibold", 14, P.ivory, "LEFT")
            val:SetPoint("TOPLEFT", ss, "TOPLEFT", x, -(SRC_COUNTS + 14))
            d.counts[i] = { label = lbl, value = val }
        end
        -- Reputation: faction and amount, two to a line.
        d.repTitle = Text(ss, "medium", 11, P.ash, "LEFT")
        d.repTitle:SetPoint("TOPLEFT", ss, "TOPLEFT", 0, -SRC_REP)
        d.repTitle:SetText(L["Reputation"])
        local REP_W = (SPLIT_W - REP_GAP) / 2
        d.repAt, d.repsHideFrom = Pool(function(i)
            local r = CreateFrame("Frame", nil, ss)
            r:SetSize(REP_W, REP_ROW)
            r:SetPoint("TOPLEFT", ss, "TOPLEFT", ((i - 1) % 2) * (REP_W + REP_GAP),
                -(SRC_REP + 18 + _floor((i - 1) / 2) * REP_ROW))
            r.name = Text(r, "medium", 12, P.ivory, "LEFT")
            r.name:SetPoint("LEFT", r, "LEFT", 0, 0); r.name:SetWidth(REP_W - 48)
            r.amount = Text(r, "semibold", 12, P.verdHi, "RIGHT")
            r.amount:SetPoint("RIGHT", r, "RIGHT", 0, 0)
            return r
        end)
        d.secSource = ss
    end
    return d
end

local MAX_BARS = 40

local function Levels(lo, hi)
    if not lo then return nil end
    return lo == hi and tostring(lo) or (lo .. "–" .. hi)
end

local function FillBars(d, s)
    local runs = s.runs
    local first = _max(1, #runs - MAX_BARS + 1)
    local n = #runs - first + 1
    local top = 60
    for i = first, #runs do top = _max(top, runs[i].dur) end
    top = _floor(top * 1.1 / 60 + 0.999) * 60          -- headroom, whole minutes
    local cw, ch = d.chart:GetWidth(), DCHART_H
    local slot = n > 0 and cw / _max(n, 12) or cw
    local bw = _max(4, _min(22, slot - 6))
    local firstBar, lastBar
    for i = first, #runs do
        local e, k = runs[i], i - first + 1
        local b = d.barAt(k)
        b.entry = e
        local h = _max(2, e.dur / top * ch)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", d.chart, "BOTTOMLEFT", (k - 1) * slot + (slot - bw) / 2, 1)
        b.cx = (k - 1) * slot + slot / 2
        b:SetSize(bw, h)
        firstBar = firstBar or b
        lastBar = b
        if e.cleared and e.dur == s.best then
            VGrad(b.fill, P.bronze, P.bronzeHi)
        elseif e.cleared then
            VGrad(b.fill, FIGHT_BOT, FIGHT_TOP, 0.85, 0.85)
        else
            b.fill:SetColorTexture(P.ash2[1], P.ash2[2], P.ash2[3], 0.6)
        end
        b.fill:SetHeight(h)
        if e.cleared and e.dur == s.best then
            d.bestLbl:ClearAllPoints()
            d.bestLbl:SetPoint("BOTTOM", b, "TOP", 0, 3)
            d.bestLbl:SetText(L["Best"])
        end
    end
    d.barsHideFrom(n + 1)
    d.bestLbl:SetShown(s.best ~= nil and n > 0)
    d.yTop:SetText(Dur(top))
    d.xFirst:SetText(n > 0 and Day(runs[first].at) or "")
    d.xLast:SetText(n > 1 and Day(runs[#runs].at) or "")
    if firstBar then
        d.xFirst:ClearAllPoints(); d.xFirst:SetPoint("TOP", d.chart, "BOTTOMLEFT", firstBar.cx, -4)
        d.xLast:ClearAllPoints();  d.xLast:SetPoint("TOP", d.chart, "BOTTOMLEFT", lastBar.cx, -4)
    end
    if s.typical then
        local y = s.typical / top * ch
        d.typLine:ClearAllPoints()
        d.typLine:SetPoint("BOTTOMLEFT", d.chart, "BOTTOMLEFT", 0, y)
        d.typLine:SetPoint("BOTTOMRIGHT", d.chart, "BOTTOMRIGHT", 0, y)
        d.typLbl:ClearAllPoints()
        d.typLbl:SetPoint("BOTTOMRIGHT", d.typLine, "TOPRIGHT", 0, 2)
        d.typLbl:SetText(_fmt(L["Typical %s"], Dur(s.typical)))
    end
    d.typLine:SetShown(s.typical ~= nil)
    d.typLbl:SetShown(s.typical ~= nil)
end

local function FillDetail(d, s)
    local runs = s.runs
    -- A run picked (still one of this dungeon's): its numbers in place of all of them.
    local sel = S.detailRun
    if sel then
        local found = false
        for _, e in ipairs(runs) do if e == sel then found = true; break end end
        if not found then sel = nil; S.detailRun = nil end
    end
    local all = MS:TrendDungeon(s.name)          -- nil without XP and gold (DPS elsewhere) recorded
    local b = sel and MS.TrendBreakdown({ sel }, s.name) or all
    d.backTxt:SetText(S.from == "trends" and L["Trends"] or L["All dungeons"])
    d.title:SetText(s.name)

    -- Summary: runs, time, levels; or the comparison being picked.
    local time, deaths, lo, hi = 0, 0, nil, nil
    for _, e in ipairs(runs) do
        time, deaths = time + (e.dur or 0), deaths + (e.deaths or 0)
        local lv = e.me and e.me.lvl
        if lv then lo = lo and _min(lo, lv) or lv; hi = hi and _max(hi, lv) or lv end
    end
    d.runX:SetShown(sel ~= nil and not S.compareA)
    d.summary:ClearAllPoints()
    if d.runX:IsShown() then d.summary:SetPoint("RIGHT", d.runX, "LEFT", -4, 0)
    else d.summary:SetPoint("RIGHT", d.runX:GetParent(), "LEFT", X0 + LEFT_W, 0) end
    if S.compareA then
        d.summary:SetText(CT(P.bronzeHi, _fmt(L["Pick a second run to compare with %s"], CT(P.ivory, Day(S.compareA.at) .. "  " .. Dur(S.compareA.dur)))))
    elseif sel then
        d.summary:SetText(CT(P.ivory, date("%A, ", sel.at) .. Day(sel.at) .. "  " .. MS.ClockTime(sel.at)) .. "  ·  " .. Result(sel))
    else
        local parts = { MS.Plural(#runs, "%d run", "%d runs", #runs), K.Hours(time) }
        local lv = forever and Levels(lo, hi)
        if lv then parts[#parts + 1] = _fmt(L["Levels %s"], lv) end
        d.summary:SetText(table.concat(parts, "  ·  "))
    end

    -- Headline numbers.
    local dash = CT(P.ash2, "-")
    local best = s.best and CT(P.bronzeHi, Dur(s.best)) or dash
    local typical = s.typical and Dur(s.typical) or dash
    local deathsRun = _fmt("%.1f", #runs > 0 and deaths / #runs or 0)
    local tiles
    if forever then
        tiles = {
            { L["XP/hour"], b and b.xpHour > 0 and CT(P.bronzeHi, K.Thousands(b.xpHour)) or dash },
            { L["Gold/hour"], b and CT(P.bronzeHi, K.GoldShort(b.goldHour)) or dash },
            { L["XP a run"], b and b.xpRun > 0 and K.Thousands(b.xpRun) or dash },
            { L["Gold a run"], b and K.GoldShort(b.goldRun) or dash },
            { L["Best"], best },
            { L["Typical"], typical },
            { L["Cleared"], Pct(s.cleared, #runs) },
            { L["Deaths/run"], deathsRun },
        }
    else
        tiles = {
            { L["Your DPS"], b and CT(P.bronzeHi, K.Thousands(b.avgDps)) or dash },
            { L["Your best DPS"], b and K.Thousands(b.best) or dash },
            { L["Best"], best },
            { L["Typical"], typical },
            { L["Runs"], tostring(#runs) },
            { L["Time"], K.Hours(time) },
            { L["Cleared"], Pct(s.cleared, #runs) },
            { L["Deaths/run"], deathsRun },
        }
    end
    if sel then
        local me = sel.me or {}
        local time1 = sel.cleared and sel.dur == s.best and CT(P.bronzeHi, Dur(sel.dur)) or Dur(sel.dur or 0)
        if forever then
            tiles = {
                { L["XP/hour"], b and b.xpHour > 0 and CT(P.bronzeHi, K.Thousands(b.xpHour)) or dash },
                { L["Gold/hour"], b and CT(P.bronzeHi, K.GoldShort(b.goldHour)) or dash },
                { L["XP"], b and b.xp > 0 and K.Thousands(b.xp) or dash },
                { L["Gold"], b and K.GoldShort(b.gold) or dash },
                { L["Time"], time1 },
                { L["Result"], Result(sel) },
                { L["Level"], me.lvl and tostring(me.lvl) or dash },
                { L["Deaths"], tostring(sel.deaths or 0) },
            }
        else
            tiles = {
                { L["DPS"], (me.dps or 0) > 0 and CT(P.bronzeHi, K.Thousands(me.dps)) or dash },
                { L["HPS"], (me.hps or 0) > 0 and K.Thousands(me.hps) or dash },
                { L["Time"], time1 },
                { L["Result"], Result(sel) },
                { L["Damage taken"], me.taken and K.Short(me.taken) or dash },
                { L["Interrupts"], tostring(me.int or 0) },
                { L["Item level"], me.ilvl and tostring(me.ilvl) or dash },
                { L["Deaths"], tostring(sel.deaths or 0) },
            }
        end
    end
    for i, tile in ipairs(d.tiles) do
        tile.label:SetText(tiles[i][1])
        tile.value:SetText(tiles[i][2])
    end

    -- The chart.
    -- (A choice this game doesn't have, such as XP an hour outside Forever: DPS.)
    if S.detailChart ~= "time" and not METRIC[S.detailChart] then S.detailChart = "dps" end
    local m = METRIC[S.detailChart]
    for _, c in ipairs(d.choices) do c.Look() end
    local bAll = b
    b = all                                      -- the chart is every run, the picked one marked
    if d.choiceRate then d.choiceRate.text:SetText(b and b.byGold and L["Gold an hour"] or L["XP an hour"]) end
    d.chart:SetShown(not m)
    d.rateHolder:SetShown(m ~= nil)
    if m then
        local series
        if m.key == "rate" then
            series = { points = b and b.points or {}, change = b and b.change, best = b and b.bestPoint }
        else
            series = MS.TrendSeries(runs, m.value, m.lower)
        end
        d.metric, d.byGold, d.bestPoint = m, m.key == "rate" and b and b.byGold, series.best
        local label
        if m.key == "rate" and d.byGold then label = K.GoldShort
        elseif m.whole then label = function(v) return tostring(_floor(v + 0.5)) end end
        local pts = series.points
        K.DrawTrendChart(d.rate, pts, label)
        -- One run (or none) of this: how this dungeon sits among your others.
        local shown = 0
        if #pts < 2 then
            local tm = MS.TREND_METRICS
            local key = m.key == "rate" and (d.byGold and "gold" or "xp") or m.key
            local def
            for _, x in ipairs(tm) do if x.key == key then def = x end end
            local list = def and MS:TrendByDungeon(def.value, def.lower) or {}
            local mine
            for _, x in ipairs(list) do if x.dungeon == s.name then mine = x end end
            if mine and #list >= 2 then
                local rows = {}
                for i = 1, _min(#list, CMP_ROWS) do rows[i] = list[i] end
                local listed = false
                for _, x in ipairs(rows) do if x == mine then listed = true end end
                if not listed then rows[#rows] = mine end
                local top = 0
                for _, x in ipairs(rows) do top = _max(top, x.avg) end
                local fmt = def.fmt == "gold" and K.GoldShort or def.fmt == "whole" and function(v) return _fmt("%.1f", v) end
                    or K.Short
                for i, x in ipairs(rows) do
                    local r = d.cmpAt(i)
                    r.data = x
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", d.rateHolder, "TOPLEFT", X0, -(CHART_TOP + 26 + (i - 1) * CMP_ROW))
                    local me = x == mine
                    local col = me and P.bronzeHi or P.ash2
                    r.name:SetText(x.dungeon)
                    r.name:SetTextColor((me and P.ivory or P.ash)[1], (me and P.ivory or P.ash)[2], (me and P.ivory or P.ash)[3])
                    r.bar:SetColorTexture(col[1], col[2], col[3], me and 1 or 0.8)
                    r.bar:SetWidth(_max(2, top > 0 and x.avg / top * CMP_BAR_W or 2))
                    r.val:SetText(fmt(x.avg))
                    r.val:SetTextColor((me and P.bronzeHi or P.ash)[1], (me and P.bronzeHi or P.ash)[2], (me and P.bronzeHi or P.ash)[3])
                end
                shown = #rows
                d.rate.empty:Hide()
                d.cmpNote:ClearAllPoints()
                d.cmpNote:SetPoint("TOPLEFT", d.rateHolder, "TOPLEFT", X0 + CMP_NAME_W + 10,
                    -(CHART_TOP + 26 + shown * CMP_ROW + 6))
                d.cmpNote:SetText(L["Your run-by-run chart and trend show here once you've done a second run."])
            end
        end
        d.cmpHideFrom(shown + 1)
        d.cmpNote:SetShown(shown > 0)
        for i, pt in ipairs(pts) do
            if #pts >= 2 then
                local p = d.rate.pointAt(i)
                if pt == d.bestPoint then Tint(p.dot, P.bronzeHi) end
                p:SetAlpha((not sel or pt.e == sel) and 1 or 0.35)
            end
        end
        d.chartChange:SetText(shown > 0 and CT(P.ash, L["Compared with your other dungeons"])
            or K.TrendChange(series.change, m.lower))
    else
        FillBars(d, s)
        d.chartChange:SetText("")
    end
    b = bAll
    -- The picked run stands out; the rest fade.
    if not m then
        for i = 1, _min(#runs, MAX_BARS) do
            local bar = d.barAt(i)
            bar:SetAlpha((not sel or bar.entry == sel) and 1 or 0.35)
        end
    end

    -- Every run.
    local y, k = 0, 0
    for i = #runs, 1, -1 do
        local e = runs[i]
        k = k + 1
        local row = d.rowAt(k)
        row:SetPoint("TOPLEFT", d.sf.scrollContent, "TOPLEFT", 0, -y)
        if row.entry ~= e then row.del.Disarm() end
        row.entry = e
        row.del:SetShown(MS:IsOwnRun(e))       -- other characters' runs are changed on them
        row.cmp.Look()
        row.pick:SetShown(e == sel)
        local c = row.cells
        c.date:SetText(Day(e.at))
        -- A key: its level. Otherwise your character's level then (Forever).
        c.level:SetText(e.key and CT(P.bronzeHi, "+" .. e.key) or (e.me and e.me.lvl) or CT(P.ash2, "-"))
        c.time:SetText(e.cleared and e.dur == s.best and CT(P.bronzeHi, Dur(e.dur)) or Dur(e.dur))
        c.result:SetText(Result(e))
        c.deaths:SetText((e.deaths or 0) > 0 and CT(P.bloodHi, e.deaths) or CT(P.ash, "0"))
        if c.xp then
            local mobXP, questXP = UI.RunXP(e.prog)
            c.xp:SetText(e.prog and MS.FormatThousands(mobXP + questXP) or CT(P.ash2, "-"))
            c.gold:SetText(e.prog and CT(P.bronzeHi, K.GoldShort((e.prog.g or 0) + (e.prog.qg or 0))) or CT(P.ash2, "-"))
        else
            c.dps:SetText(e.me and Abbrev(e.me.dps) or CT(P.ash2, "-"))
        end
        if c.bosses then
            local names = {}
            for _, bo in ipairs(e.bosses or {}) do names[#names + 1] = bo.n end
            c.bosses:SetText(#names > 0 and CT(P.ash, table.concat(names, ", ")) or CT(P.ash2, L["None"]))
        end
        y = y + LIST_ROW
    end
    d.rowsHideFrom(k + 1)
    d.sf.scrollContent:SetHeight(_max(1, y))
    d.sf.UpdateRange()

    -- Right: the sections one under another.
    local content = d.rsf.scrollContent
    local top = 0
    local function Place(sec, h)
        sec:ClearAllPoints()
        sec:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -top)
        sec:SetHeight(h)
        sec:Show()
        top = top + h + SEC_GAP
    end
    local by = COL_HDR_H
    local nBoss
    if sel then
        -- This run's kills: when each died, and how long the fight took
        -- (bronze: its fastest fight yet).
        d.bossHdrA:SetText(L["Killed"]); d.bossHdrB:SetText(L["Fight"])
        local bestFight = {}
        for _, bo in ipairs(s.bosses) do bestFight[bo.name] = bo.best end
        local kills = sel.bosses or {}
        for i, kill in ipairs(kills) do
            local row = d.bossAt(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", d.secBoss, "TOPLEFT", 0, -by)
            row.data = nil
            for _, bo in ipairs(s.bosses) do if bo.name == kill.n then row.data = bo end end
            row.name:SetText(kill.n)
            row.best:SetText(kill.t and Dur(kill.t) or CT(P.ash2, "-"))
            local fast = kill.d and bestFight[kill.n] and kill.d <= bestFight[kill.n]
            row.typical:SetText(kill.d and (fast and CT(P.bronzeHi, Dur(kill.d)) or Dur(kill.d)) or CT(P.ash2, "-"))
            by = by + LIST_ROW
        end
        nBoss = #kills
    else
        d.bossHdrA:SetText(L["Best"]); d.bossHdrB:SetText(L["Typical"])
        for i, bo in ipairs(s.bosses) do
            local row = d.bossAt(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", d.secBoss, "TOPLEFT", 0, -by)
            row.data = bo
            row.name:SetText(bo.name)
            row.best:SetText(bo.best and CT(P.bronzeHi, Dur(bo.best)) or CT(P.ash2, "-"))
            row.typical:SetText(bo.typical and Dur(bo.typical) or CT(P.ash2, "-"))
            by = by + LIST_ROW
        end
        nBoss = #s.bosses
    end
    d.bossesHideFrom(nBoss + 1)
    d.noBosses:SetShown(nBoss == 0)
    Place(d.secBoss, nBoss > 0 and by or (by + 30))

    -- One run: your numbers in it, in place of the levels.
    d.secYou:SetShown(sel ~= nil)
    if sel then
        local me = sel.me or {}
        local lines = {}
        local function Add(label, v) if v then lines[#lines + 1] = { label, v } end end
        Add(L["DPS"], (me.dps or 0) > 0 and K.Thousands(me.dps) or nil)
        Add(L["HPS"], (me.hps or 0) > 0 and K.Thousands(me.hps) or nil)
        Add(L["Damage"], (me.dmg or 0) > 0 and K.Thousands(me.dmg) or nil)
        Add(L["Healing"], (me.heal or 0) > 0 and K.Thousands(me.heal) or nil)
        Add(L["Damage taken"], me.taken and K.Thousands(me.taken) or nil)
        Add(L["Avoidable damage"], (me.avoid or 0) > 0 and CT(P.avoid, K.Thousands(me.avoid)) or nil)
        Add(L["Interrupts"], me.int and tostring(me.int) or nil)
        Add(L["Item level"], me.ilvl and tostring(me.ilvl) or nil)
        for i, ln in ipairs(lines) do
            local r = d.youAt(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", d.secYou, "TOPLEFT", 0, -(i - 1) * 22)
            r.lbl:SetText(ln[1]); r.val:SetText(ln[2])
        end
        d.youHideFrom(#lines + 1)
        if #lines > 0 then Place(d.secYou, #lines * 22) else d.secYou:Hide() end
    end

    local groups = (not sel) and b and b.groups or {}
    d.secGroup:SetShown(#groups > 0)
    if #groups > 0 then
        local bestXP, bestGold, bestAvg = 0, 0, 0
        for _, g in ipairs(groups) do
            bestXP, bestGold, bestAvg = _max(bestXP, g.xpHour), _max(bestGold, g.goldHour), _max(bestAvg, g.avgDps)
        end
        local function Col(fs, v, most)
            local col = (#groups > 1 and v > 0 and v == most) and P.bronzeHi or P.ivory
            fs:SetTextColor(col[1], col[2], col[3])
        end
        local gy = COL_HDR_H
        for i, g in ipairs(groups) do
            local row = d.groupAt(i)
            row.data = g
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", d.secGroup, "TOPLEFT", 0, -gy)
            local cl = row.cells
            cl.group:SetText(g.key and tostring(g.key) or "-")
            cl.runs:SetText(tostring(g.runs))
            cl.typical:SetText(g.typical and Dur(g.typical) or CT(P.ash2, "-"))
            if forever then
                cl.xp:SetText(g.xpHour > 0 and K.Short(g.xpHour) or "-"); Col(cl.xp, g.xpHour, bestXP)
                cl.gold:SetText(K.GoldShort(g.goldHour)); Col(cl.gold, g.goldHour, bestGold)
            else
                cl.avg:SetText(K.Thousands(g.avgDps)); Col(cl.avg, g.avgDps, bestAvg)
                cl.best:SetText(K.Thousands(g.best))
            end
            gy = gy + LIST_ROW
        end
        Place(d.secGroup, gy)
    end
    d.groupsHideFrom(#groups + 1)

    if d.secSource then
        d.secSource:SetShown(b ~= nil)
        if b then
            FillSplit(d.xpSplit, L["XP"], K.Thousands(b.xp), b.mobXP, b.questXP, P.xpMob, P.xpQuest,
                L["From the dungeon"], L["From quests"])
            FillSplit(d.goldSplit, L["Gold"], CT(P.bronzeHi, MS.FormatGold(b.gold)), b.lootGold, b.questGold,
                P.bronze, P.xpQuest, L["Gold looted"], L["From quests"])
            local counts = {
                { L["Mobs killed"], K.Thousands(b.kills) },
                { L["Quests completed"], tostring(b.quests) },
                { L["Levels gained"], b.levels > 0 and ("+" .. b.levels) or "0" },
            }
            for i, c in ipairs(d.counts) do
                c.label:SetText(counts[i][1]); c.value:SetText(counts[i][2])
            end
            for i, r in ipairs(b.rep) do
                local row = d.repAt(i)
                row.name:SetText(r.faction)
                row.amount:SetText("+" .. K.Thousands(r.amount))
            end
            d.repsHideFrom(#b.rep + 1)
            d.repTitle:SetShown(#b.rep > 0)
            local h = #b.rep > 0 and (SRC_REP + 18 + _ceil(#b.rep / 2) * REP_ROW) or (SRC_COUNTS + 34)
            Place(d.secSource, h)
        end
    end
    content:SetHeight(_max(1, top - SEC_GAP))
    d.rsf.UpdateRange()
end

-- ── Compare ────────────────────────────────────────────────────────────────
-- Two runs of one dungeon. Top: each run as a bar on one time scale, with a
-- line joining each boss's kill in the earlier run to the same kill in the
-- later one. Below: boss by boss, the later run against the earlier one.
local CCOLS = {
    { key = "boss",  label = LK("Boss"),           w = 200, left = true },
    { key = "k1",    label = LK("Killed 1"),       w = 84 },
    { key = "k2",    label = LK("Killed 2"),       w = 84 },
    { key = "split", label = LK("Run 2 was"),      w = 112 },
    { key = "f1",    label = LK("Fight 1"),        w = 76 },
    { key = "f2",    label = LK("Fight 2"),        w = 76 },
    { key = "fd",    label = "",               w = 64 },
    { key = "t1",    label = LK("Trash 1"),        w = 76 },
    { key = "t2",    label = LK("Trash 2"),        w = 76 },
    { key = "td",    label = "",               w = 64 },
    { key = "m1",    label = LK("Your DPS 1"),     w = 92 },
    { key = "m2",    label = LK("Your DPS 2"),     w = 92 },
}
local LANE_X = X0 + 250                       -- where the bars start
local LANE_W = FRAME_W - 2 - LANE_X - X0 - 10
local LANE_H = 14
local RUN_COL = { P.ash, P.bronzeHi }          -- run 1 (earlier), run 2 (later)

local function Signed(d)
    if not d then return CT(P.ash2, "-") end
    if math.abs(d) < 1 then return CT(P.ash, "same") end
    return d < 0 and CT(P.verd, "-" .. Dur(-d)) or CT(P.bloodHi, "+" .. Dur(d))
end

local function Split(d)
    if not d then return CT(P.ash2, "-") end
    if math.abs(d) < 1 then return CT(P.ash, L["level"]) end
    return d < 0 and CT(P.verd, _fmt(L["%s ahead"], Dur(-d))) or CT(P.bloodHi, _fmt(L["%s behind"], Dur(d)))
end

local function OrDash(v, f) return v and (f and f(v) or v) or CT(P.ash2, "-") end

local function BuildCompare(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetAllPoints()
    local band = Band(c)
    band:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, 0)
    local back = Btn(band)
    back:SetPoint("LEFT", band, "LEFT", X0 - 4, 0); back:SetSize(220, COL_HDR_H - 6)
    local arrow = Art(back, "Chevron", "OVERLAY")
    arrow:SetSize(12, 12); arrow:SetPoint("LEFT", back, "LEFT", 4, 0)
    arrow:SetRotation(-math.pi / 2); Tint(arrow, P.ash)
    c.backTxt = Text(back, "medium", 13, P.ash, "LEFT")
    c.backTxt:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    back:SetScript("OnEnter", function() Tint(arrow, P.ivory); c.backTxt:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3]) end)
    back:SetScript("OnLeave", function() Tint(arrow, P.ash); c.backTxt:SetTextColor(P.ash[1], P.ash[2], P.ash[3]) end)
    back:SetScript("OnClick", function() S.compareA, S.compareB = nil, nil; UI.RefreshStats(true) end)
    c.title = Text(band, "semibold", 15, P.ivory, "LEFT")
    c.title:SetPoint("LEFT", band, "LEFT", LANE_X, 0)
    c.title:SetText(L["Run comparison"])

    -- Lanes
    c.lanes = {}
    for i = 1, 2 do
        local y = -(COL_HDR_H + 22 + (i - 1) * 62)
        local lane = { y = y }
        lane.num = Text(c, "title", 18, RUN_COL[i], "LEFT")
        lane.num:SetPoint("TOPLEFT", c, "TOPLEFT", X0, y + 2); lane.num:SetText(tostring(i))
        lane.head = Text(c, "semibold", 14, P.ivory, "LEFT")
        lane.head:SetPoint("TOPLEFT", c, "TOPLEFT", X0 + 22, y)
        lane.sub = Text(c, "medium", 12, P.ash, "LEFT")
        lane.sub:SetPoint("TOPLEFT", lane.head, "BOTTOMLEFT", 0, -3)
        local track = Solid(c, "BORDER", 0, 0.16, 0.14, 0.12, 1)
        track:SetPoint("TOPLEFT", c, "TOPLEFT", LANE_X, y - 8); track:SetSize(LANE_W, LANE_H)
        lane.track = track
        lane.ends = Solid(c, "OVERLAY", 1, P.ivory[1], P.ivory[2], P.ivory[3], 0.8)
        lane.ends:SetSize(2, LANE_H + 8)
        -- Each run's times on the side away from the lines joining the two:
        -- above the first bar, below the second. 0:00, each kill, the end.
        lane.above = (i == 1)
        lane.zero = Text(c, "medium", 11, P.ash, "LEFT")
        lane.zero:SetText("0:00")
        lane.endLbl = Text(c, "medium", 11, P.ash, "CENTER")
        lane.killAt, lane.killsHideFrom = Pool(function() return Text(c, "medium", 11, P.ash2, "CENTER") end)
        lane.blockAt, lane.blocksHideFrom = Pool(function()
            local t = c:CreateTexture(nil, "ARTWORK"); return t
        end)
        c.lanes[i] = lane
    end
    c.linkAt, c.linksHideFrom = Pool(function()
        return UI.ChartLine(c, 8, true)   -- long shallow lines: the softer-edged texture
    end)
    c.verdict = Text(c, "semibold", 14, P.ivory, "LEFT")
    c.verdict:SetPoint("TOPLEFT", c, "TOPLEFT", X0, -(COL_HDR_H + 22 + 62 + 52))

    -- Table
    local tableTop = COL_HDR_H + 22 + 62 + 80
    local tband = Band(c, CCOLS, X0)
    tband:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -tableTop); tband:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -tableTop)
    c.sf = MakeScrollFrame(c)
    c.sf:SetPoint("TOPLEFT", c, "TOPLEFT", X0, -(tableTop + COL_HDR_H))
    c.sf:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", X0, 8)
    c.sf:SetWidth(FRAME_W - 2 * X0)
    c.rowAt, c.rowsHideFrom = Pool(function()
        local row = CreateFrame("Frame", nil, c.sf.scrollContent)
        row:SetSize(FRAME_W - 2 * X0 - 10, LIST_ROW)
        HoverRow(row)
        row.cells = Cells(row, CCOLS, 14)
        return row
    end)
    return c
end

-- A lane's times: 0:00 at its start, its end time under (or over) the end
-- mark, and each kill's time at the end of its block. A kill time that
-- would run into another is left out (the start and end come first).
local function PlaceLaneTimes(lane, e, runEnd, At)
    local point = lane.above and "BOTTOM" or "TOP"
    local y = lane.above and (lane.y - 8 + 3) or (lane.y - 8 - LANE_H - 4)
    local taken = {}
    local function Fits(x1, x2)
        for _, r in ipairs(taken) do
            if x1 < r[2] + 6 and x2 > r[1] - 6 then return false end
        end
        return true
    end
    local function Put(fs, cx, text)
        fs:SetText(text)
        local half = fs:GetStringWidth() / 2
        cx = _max(LANE_X + half, _min(cx, LANE_X + LANE_W - half))   -- inside the lane
        fs:ClearAllPoints()
        fs:SetPoint(point, lane.zero:GetParent(), "TOPLEFT", cx, y)
        return cx - half, cx + half
    end
    local z1, z2 = Put(lane.zero, LANE_X, "0:00")
    taken[#taken + 1] = { z1, z2 }
    local e1, e2 = Put(lane.endLbl, At(runEnd), Dur(runEnd))
    taken[#taken + 1] = { e1, e2 }
    local n = 0
    for _, b in ipairs(e.bosses or {}) do
        if b.t then
            n = n + 1
            local fs = lane.killAt(n)
            local x1, x2 = Put(fs, At(b.t), Dur(_min(b.t, runEnd)))
            if Fits(x1, x2) then taken[#taken + 1] = { x1, x2 } else fs:Hide() end
        end
    end
    lane.killsHideFrom(n + 1)
end

local function FillCompare(c, cmp)
    local A, B = cmp.first, cmp.second
    c.backTxt:SetText(A.dungeon or L["Back"])
    local scale = _max(A.dur or 1, B.dur or 1, 1)
    local function LX(t) return LANE_X + (t or 0) / scale * LANE_W end
    for i, e in ipairs({ A, B }) do
        local lane = c.lanes[i]
        lane.head:SetText(Day(e.at) .. (e.at and date("  %H:%M", e.at) or "")
            .. (S.multiChar and MS:RunOwner(e) and ("   " .. CharName(MS:RunOwner(e))) or ""))
        lane.sub:SetText(table.concat({
            CT(P.ivory, Dur(e.dur)), Result(e),
            ((e.deaths or 0) > 0 and CT(P.bloodHi, MS.Plural(e.deaths, "%d death", "%d deaths")) or L["No deaths"]),
        }, "    "))
        -- A kill logged after the run ended (a key's last ENCOUNTER_END can
        -- come after its timer stopped) is drawn at the end, as on the
        -- scoreboard's timeline, so nothing runs past the run's own end.
        local runEnd = (e.dur or 0) > 0 and e.dur or scale
        local function At(t) return LX(_min(t or 0, runEnd)) end
        local k = 0
        for _, b in ipairs(e.bosses or {}) do
            k = k + 1
            local t = lane.blockAt(k)
            local x1 = At(b.d and (b.t - b.d) or b.t)
            local w = _max(2, At(b.t) - x1)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", c, "TOPLEFT", x1, lane.y - 8)
            t:SetSize(w, LANE_H)
            VGrad(t, FIGHT_BOT, FIGHT_TOP)
        end
        lane.blocksHideFrom(k + 1)
        lane.ends:ClearAllPoints()
        lane.ends:SetPoint("TOPLEFT", c, "TOPLEFT", LX(runEnd) - 1, lane.y - 4)
        PlaceLaneTimes(lane, e, runEnd, At)
    end
    -- Lines joining the same boss's kill in both runs.
    local n = 0
    local y1 = c.lanes[1].y - 8 - LANE_H
    local y2 = c.lanes[2].y - 8
    for _, r in ipairs(cmp.rows) do
        if r.a and r.b then
            n = n + 1
            local l = c.linkAt(n)
            local col = (r.split or 0) < -0.5 and P.verd or (r.split or 0) > 0.5 and P.bloodHi or P.ash
            UI.ChartLineColor(l, col, 0.85)
            l:SetStartPoint("TOPLEFT", c, LX(_min(r.a.t, A.dur or r.a.t)), y1)
            l:SetEndPoint("TOPLEFT", c, LX(_min(r.b.t, B.dur or r.b.t)), y2)
        end
    end
    c.linksHideFrom(n + 1)

    -- Verdict
    local T = cmp.total
    local d = T.diff
    local head = math.abs(d) < 1 and L["Both runs took the same time."]
        or (d < 0 and CT(P.verd, _fmt(L["Run 2 was %s faster."], Dur(-d))) or CT(P.bloodHi, _fmt(L["Run 2 was %s slower."], Dur(d))))
    local extra = {}
    if T.fightA and T.fightB and T.trashA and T.trashB and math.abs(d) >= 1 then
        local fd, td = T.fightB - T.fightA, T.trashB - T.trashA
        extra[#extra + 1] = _fmt(L["Boss fights %s, trash %s"], Signed(fd), Signed(td))
    end
    if T.dpsA and T.dpsB then extra[#extra + 1] = _fmt(L["Your DPS %s vs %s"], Abbrev(T.dpsA), Abbrev(T.dpsB)) end
    extra[#extra + 1] = _fmt(L["Deaths %s vs %s"], T.deathsA, T.deathsB)
    c.verdict:SetText(head .. "      " .. CT(P.ash, table.concat(extra, "      ")))

    -- Table
    local y, k = 0, 0
    local function Row()
        k = k + 1
        local row = c.rowAt(k)
        row:SetPoint("TOPLEFT", c.sf.scrollContent, "TOPLEFT", 0, -y)
        y = y + LIST_ROW
        return row.cells
    end
    for _, r in ipairs(cmp.rows) do
        local cl = Row()
        local ra, rb = r.a or {}, r.b or {}
        cl.boss:SetText(r.name or "?")
        cl.k1:SetText(OrDash(ra.t, Dur)); cl.k2:SetText(OrDash(rb.t, Dur))
        cl.split:SetText(Split(r.split))
        cl.f1:SetText(OrDash(ra.d, Dur)); cl.f2:SetText(OrDash(rb.d, Dur)); cl.fd:SetText(r.fight and Signed(r.fight) or "")
        cl.t1:SetText(OrDash(ra.trash, Dur)); cl.t2:SetText(OrDash(rb.trash, Dur)); cl.td:SetText(r.trashDiff and Signed(r.trashDiff) or "")
        cl.m1:SetText(OrDash(ra.m, Abbrev)); cl.m2:SetText(OrDash(rb.m, Abbrev))
    end
    -- After the last kill, then the whole run.
    local cl = Row()
    cl.boss:SetText(CT(P.ash, L["After the last boss"]))
    for _, key in ipairs({ "k1", "k2", "split", "f1", "f2", "fd", "m1", "m2" }) do cl[key]:SetText("") end
    cl.t1:SetText(Dur(T.endA)); cl.t2:SetText(Dur(T.endB)); cl.td:SetText(Signed(T.endB - T.endA))
    cl = Row()
    cl.boss:SetText(CT(P.ivory, L["Whole run"]))
    cl.k1:SetText(CT(P.ivory, Dur(T.a))); cl.k2:SetText(CT(P.ivory, Dur(T.b)))
    cl.split:SetText(Split(T.diff))
    cl.f1:SetText(OrDash(T.fightA, Dur)); cl.f2:SetText(OrDash(T.fightB, Dur))
    cl.fd:SetText(T.fightA and T.fightB and Signed(T.fightB - T.fightA) or "")
    cl.t1:SetText(T.trashA and Dur(T.trashA + T.endA) or CT(P.ash2, "-"))
    cl.t2:SetText(T.trashB and Dur(T.trashB + T.endB) or CT(P.ash2, "-"))
    cl.td:SetText(T.trashA and T.trashB and Signed((T.trashB + T.endB) - (T.trashA + T.endA)) or "")
    cl.m1:SetText(OrDash(T.dpsA, Abbrev)); cl.m2:SetText(OrDash(T.dpsB, Abbrev))
    c.rowsHideFrom(k + 1)
    c.sf.scrollContent:SetHeight(_max(1, y))
    c.sf.UpdateRange()
end

K.BuildDetail, K.FillDetail = BuildDetail, FillDetail
K.BuildCompare, K.FillCompare = BuildCompare, FillCompare

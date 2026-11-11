local _floor, _max, _min = math.floor, math.max, math.min
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

-- Stats page, part 2: one dungeon (a bar per run, the run list, each boss's
-- fight lengths), and two of its runs compared side by side. Built and filled
-- from UI_Stats.lua through UI.StatsKit; the page's state is K.S.

local K = UI.StatsKit                  -- shared by UI_Stats.lua
local BOSS_COL, Band, CHART_H, Cells, CharName = K.BOSS_COL, K.Band, K.CHART_H, K.Cells, K.CharName
local Day, Dur, HoverRow, LEFT_W, LIST_ROW = K.Day, K.Dur, K.HoverRow, K.LEFT_W, K.LIST_ROW
local MATE_ROW, MakeBossRow, Pct, Pool, RCOLS = K.MATE_ROW, K.MakeBossRow, K.Pct, K.Pool, K.RCOLS
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
    GameTooltip:Show()
end

local function MakeChartBar(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:EnableMouse(true)
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
    row.cells.bosses:SetWidth(RCOLS[#RCOLS].w - 100)
    row:SetScript("OnEnter", function(self) RunTooltip(self, self.entry) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

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

local function BuildDetail(parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetAllPoints()
    local band = Band(d)
    band:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, 0)
    local bossLbl = Text(band, "medium", 13, P.ash, "LEFT")
    bossLbl:SetPoint("LEFT", band, "LEFT", RIGHT_X, 0); bossLbl:SetText(L["Bosses"])
    local typLbl = Text(band, "medium", 13, P.ash, "CENTER")
    typLbl:SetPoint("CENTER", band, "LEFT", RIGHT_X + RIGHT_W - BOSS_COL / 2, 0); typLbl:SetText(L["Typical"])
    local bestLbl = Text(band, "medium", 13, P.ash, "CENTER")
    bestLbl:SetPoint("CENTER", band, "LEFT", RIGHT_X + RIGHT_W - BOSS_COL * 1.5, 0); bestLbl:SetText(L["Best"])

    local back = Btn(band)
    back:SetPoint("LEFT", band, "LEFT", X0 - 4, 0); back:SetSize(128, COL_HDR_H - 6)
    local arrow = Art(back, "Chevron", "OVERLAY")
    arrow:SetSize(12, 12); arrow:SetPoint("LEFT", back, "LEFT", 4, 0)
    arrow:SetRotation(-math.pi / 2); Tint(arrow, P.ash)
    local backTxt = Text(back, "medium", 13, P.ash, "LEFT")
    backTxt:SetPoint("LEFT", arrow, "RIGHT", 4, 0); backTxt:SetText(L["All dungeons"])
    back:SetScript("OnEnter", function() Tint(arrow, P.ivory); backTxt:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3]) end)
    back:SetScript("OnLeave", function() Tint(arrow, P.ash); backTxt:SetTextColor(P.ash[1], P.ash[2], P.ash[3]) end)
    back:SetScript("OnClick", function() S.selected = nil; S.compareA, S.compareB = nil, nil; UI.RefreshStats() end)
    d.back = back

    d.title = Text(band, "semibold", 15, P.ivory, "LEFT")
    d.title:SetPoint("LEFT", back, "RIGHT", 14, 0)
    d.summary = Text(band, "medium", 13, P.ash, "RIGHT")
    d.summary:SetPoint("RIGHT", band, "LEFT", X0 + LEFT_W, 0)

    -- Chart: one bar per run, oldest on the left.
    local chart = CreateFrame("Frame", nil, d)
    chart:SetPoint("TOPLEFT", d, "TOPLEFT", X0 + 40, -(COL_HDR_H + 22))
    chart:SetSize(LEFT_W - 40, CHART_H)
    local base = Solid(chart, "BORDER", 0, P.line[1], P.line[2], P.line[3], 1)
    base:SetPoint("BOTTOMLEFT"); base:SetPoint("BOTTOMRIGHT"); base:SetHeight(1)
    d.typLine = Solid(chart, "OVERLAY", 0, P.verd[1], P.verd[2], P.verd[3], 0.55)
    d.typLine:SetHeight(1)
    d.typLbl = Text(chart, "medium", 11, P.verd, "RIGHT")
    d.yTop = Text(d, "medium", 11, P.ash, "RIGHT")
    d.yTop:SetPoint("RIGHT", chart, "TOPLEFT", -6, 0)
    d.yBot = Text(d, "medium", 11, P.ash, "RIGHT")
    d.yBot:SetPoint("RIGHT", chart, "BOTTOMLEFT", -6, 0); d.yBot:SetText("0:00")
    d.xFirst = Text(d, "medium", 11, P.ash, "CENTER")   -- placed under the first and last bars
    d.xLast = Text(d, "medium", 11, P.ash, "CENTER")
    d.bestLbl = Text(chart, "semibold", 11, P.bronzeHi, "CENTER")
    d.chart = chart
    d.barAt, d.barsHideFrom = Pool(function() return MakeChartBar(chart) end)

    -- Run list, newest first.
    local listTop = COL_HDR_H + 22 + CHART_H + 26
    local lband = Band(d, RCOLS, X0)
    lband:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -listTop); lband:SetWidth(X0 + LEFT_W)
    d.sf = MakeScrollFrame(d)
    d.sf:SetPoint("TOPLEFT", d, "TOPLEFT", X0, -(listTop + COL_HDR_H))
    d.sf:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", X0, 8)
    d.sf:SetWidth(LEFT_W + 10)
    d.rowAt, d.rowsHideFrom = Pool(function() return MakeRunRow(d.sf.scrollContent) end)

    -- Bosses: fight lengths.
    d.bsf = MakeScrollFrame(d)
    d.bsf:SetPoint("TOPLEFT", d, "TOPLEFT", RIGHT_X, -COL_HDR_H)
    d.bsf:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", RIGHT_X, 8)
    d.bsf:SetWidth(RIGHT_W + 10)
    d.bossAt, d.bossesHideFrom = Pool(function() return MakeBossRow(d.bsf.scrollContent) end)
    d.noBosses = Text(d, "regular", 13, P.ash2, "LEFT")
    d.noBosses:SetPoint("TOPLEFT", d, "TOPLEFT", RIGHT_X + 2, -(COL_HDR_H + 10))
    d.noBosses:SetText(L["No bosses killed here yet."])
    return d
end

local MAX_BARS = 40

local function FillDetail(d, s, stats)
    d.title:SetText(s.name)
    if S.compareA then
        d.summary:SetText(CT(P.bronzeHi, _fmt(L["Pick a second run to compare with %s"], CT(P.ivory, Day(S.compareA.at) .. "  " .. Dur(S.compareA.dur)))))
    else
        d.summary:SetText(_fmt(L["Best %s      Typical %s      %s cleared"],
            CT(P.ivory, Dur(s.best)), CT(P.ivory, Dur(s.typical)), CT(P.ivory, Pct(s.cleared, #s.runs))))
    end

    -- Chart
    local runs = s.runs
    local first = _max(1, #runs - MAX_BARS + 1)
    local n = #runs - first + 1
    local top = 60
    for i = first, #runs do top = _max(top, runs[i].dur) end
    top = _floor(top * 1.1 / 60 + 0.999) * 60          -- headroom, whole minutes
    local cw, ch = d.chart:GetWidth(), CHART_H
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

    -- List
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
        else
            c.dps:SetText(e.me and Abbrev(e.me.dps) or CT(P.ash2, "-"))
        end
        local names = {}
        for _, b in ipairs(e.bosses or {}) do names[#names + 1] = b.n end
        c.bosses:SetText(#names > 0 and CT(P.ash, table.concat(names, ", ")) or CT(P.ash2, L["None"]))
        y = y + LIST_ROW
    end
    d.rowsHideFrom(k + 1)
    d.sf.scrollContent:SetHeight(_max(1, y))
    d.sf.UpdateRange()

    local by = 0
    for i, b in ipairs(s.bosses) do
        local row = d.bossAt(i)
        row:SetPoint("TOPLEFT", d.bsf.scrollContent, "TOPLEFT", 0, -by)
        row.data = b
        row.name:SetText(b.name)
        row.best:SetText(b.best and CT(P.bronzeHi, Dur(b.best)) or CT(P.ash2, "-"))
        row.typical:SetText(b.typical and Dur(b.typical) or CT(P.ash2, "-"))
        by = by + MATE_ROW
    end
    d.bossesHideFrom(#s.bosses + 1)
    d.bsf.scrollContent:SetHeight(_max(1, by))
    d.bsf.UpdateRange()
    d.noBosses:SetShown(#s.bosses == 0)
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

local _floor, _max, _min = math.floor, math.max, math.min
local _fmt = string.format

local MS = _G["MythicScoreboard"]
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local P, PAD_X, HDR_H, COL_HDR_H, FRAME_W = UI.P, UI.PAD_X, UI.HDR_H, UI.COL_HDR_H, UI.FRAME_W
local Text, Solid, Btn, Tint, Art, Box = UI.Text, UI.Solid, UI.Btn, UI.Tint, UI.Art, UI.Box
local VGrad, MakeScrollFrame, ClassHex, CT, DN, Abbrev = UI.VGrad, UI.MakeScrollFrame, UI.ClassHex, UI.CT, UI.DN, UI.Abbrev
local FIGHT_BOT, FIGHT_TOP = UI.FIGHT_BOT, UI.FIGHT_TOP

-- Stats page: your run history across every dungeon, from the archive
-- (Archive.lua). It takes the place of the table and timeline while open.
--
--   overview  dungeon table (left) + people you've played with (right)
--   detail    one dungeon: a bar per run, then the list of runs; each boss
--             with its fight lengths on the right
--   loot      every piece of gear that dropped for you, newest first
--   compare   two runs of one dungeon side by side (picked from the run list)
--
-- Tabs (Dungeons / Loot) and the character filter sit in the header.

-- ── Layout ─────────────────────────────────────────────────────────────────
local X0      = PAD_X - 2
local LEFT_W  = 700
local GAP     = 28
local RIGHT_X = X0 + LEFT_W + GAP
local RIGHT_W = FRAME_W - 2 - RIGHT_X - X0
local ROW     = 34
local MATE_ROW = 28
local CHART_H = 150
local LIST_ROW = 26

local DCOLS = {   -- overview: one row per dungeon
    { key = "name",    label = "Dungeon",      w = 180, left = true },
    { key = "runs",    label = "Runs",         w = 48 },
    { key = "cleared", label = "Cleared",      w = 62 },
    { key = "best",    label = "Best",         w = 60 },
    { key = "typical", label = "Typical",      w = 64 },
    { key = "recent",  label = "Recent runs",  w = 140, left = true },
    { key = "deaths",  label = "Deaths/run",   w = 70 },
    { key = "dps",     label = "Your DPS",     w = 76 },
}
-- Forever: what runs gave you, in place of your DPS.
if MS.Flavor.progressStats then
    for i, c in ipairs(DCOLS) do
        if c.key == "dps" then DCOLS[i] = { key = "xp", label = "XP a run", w = c.w } end
    end
end
local LCOLS = {   -- loot: one row per item
    { key = "item",    label = "Item",      w = 370, left = true },
    { key = "dungeon", label = "Dungeon",   w = 220, left = true },
    { key = "boss",    label = "Boss",      w = 210, left = true },
    { key = "date",    label = "Date",      w = 80,  left = true },
    { key = "char",    label = "Character", w = 130, left = true },
}
local LOOT_ROW = 30
local MAX_LOOT = 500
local RCOLS = {   -- detail: one row per run
    { key = "date",   label = "Date",     w = 92,  left = true },
    { key = "level",  label = "Level",    w = 56 },
    { key = "time",   label = "Time",     w = 70 },
    { key = "result", label = "Result",   w = 96,  left = true },
    { key = "deaths", label = "Deaths",   w = 64 },
    { key = "dps",    label = "Your DPS", w = 80 },
    { key = "bosses", label = "Bosses",   w = 242, left = true },
}
if MS.Flavor.progressStats then
    for i, c in ipairs(RCOLS) do
        if c.key == "dps" then RCOLS[i] = { key = "xp", label = "XP", w = c.w } end
    end
end

-- ── Formatting ─────────────────────────────────────────────────────────────
local function Dur(s) return MS:FormatLongTime(s) end
local function Hours(s)
    local m = _floor((s or 0) / 60 + 0.5)
    if m < 60 then return m .. "m" end
    return _floor(m / 60) .. "h " .. _fmt("%02dm", m % 60)
end
local function Day(at)
    if not at then return "-" end
    return date("%b ", at) .. tonumber(date("%d", at))
end
local function Result(e)
    local text, col = UI.ArchiveResult(e)
    return CT(col, text)
end
local function Pct(a, b) return b > 0 and _floor(a / b * 100 + 0.5) .. "%" or "-" end

-- ── State ──────────────────────────────────────────────────────────────────
local view, overview, detail, lootView, controls, compareView
local selected            -- dungeon name shown in detail, or nil for the overview
local compareA, compareB  -- runs picked for comparison (archive entries)
local tab = "dungeons"    -- or "loot"
local multiChar = false   -- more than one character has runs

-- A character's name in its class colour.
local function CharName(key)
    local c = MS:CharacterInfo(key)
    if not c then return CT(P.ash, "?") end
    return "|cff" .. ClassHex(c.class or "UNKNOWN") .. DN(c.name or "?") .. "|r"
end
UI.statsOpen = false

-- A header band like the scoreboard's column header, with labels per column.
local function Band(parent, cols, x)
    local band = CreateFrame("Frame", nil, parent)
    band:SetHeight(COL_HDR_H)
    local bg = Solid(band, "BACKGROUND", 0, 0, 0, 0, 0.25); bg:SetAllPoints()
    local lx = x or 0
    band.labels = {}
    for _, c in ipairs(cols or {}) do
        local lbl = Text(band, "medium", 13, P.ash, c.left and "LEFT" or "CENTER")
        lbl:SetWidth(c.w - 6)
        if c.left then lbl:SetPoint("LEFT", band, "LEFT", lx, 0)
        else lbl:SetPoint("CENTER", band, "LEFT", lx + c.w / 2, 0) end
        lbl:SetText(c.label)
        band.labels[c.key] = lbl
        lx = lx + c.w
    end
    return band
end

-- Places fontstrings for each column in a row; returns them by key.
local function Cells(row, cols, size)
    local out, x = {}, 0
    for _, c in ipairs(cols) do
        if c.key ~= "recent" then
            local fs = Text(row, c.key == "name" and "semibold" or "medium", size or 15, P.ivory, c.left and "LEFT" or "CENTER")
            fs:SetWidth(c.w - 8)
            if c.left then fs:SetPoint("LEFT", row, "LEFT", x, 0)
            else fs:SetPoint("CENTER", row, "LEFT", x + c.w / 2, 0) end
            out[c.key] = fs
        end
        c._x = x
        x = x + c.w
    end
    return out
end

local function HoverRow(row)
    local hov = Solid(row, "HIGHLIGHT", 0, 1, 0.94, 0.86, 0.04); hov:SetAllPoints()
    local line = Solid(row, "BORDER", 0, P.line[1], P.line[2], P.line[3], 1)
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
end

-- A small text or icon control that needs two clicks: the first arms it
-- (turns red, says what will happen), the second within 3s does it.
local function TwoClick(btn, setArmed, action)
    local armed, timer = false, nil
    local function Disarm()
        armed = false
        if timer then timer:Cancel(); timer = nil end
        setArmed(false)
    end
    btn:SetScript("OnClick", function()
        if armed then
            Disarm(); action()
        else
            armed = true; setArmed(true)
            timer = C_Timer.NewTimer(3, Disarm)
        end
    end)
    btn.Disarm = Disarm
    btn.IsArmed = function() return armed end
end

local function Pool(make)
    local items = {}
    return function(i)
        if not items[i] then items[i] = make(i) end
        items[i]:Show()
        return items[i]
    end, function(from)
        for i = from, #items do items[i]:Hide() end
    end
end

-- ── Overview ───────────────────────────────────────────────────────────────
local function RecentStrip(row)
    local bars = {}
    for i = 1, 12 do
        local b = Solid(row, "ARTWORK", 0, 1, 1, 1, 1)
        b:SetWidth(7)
        bars[i] = b
    end
    return bars
end

local function FillRecent(bars, d, x0)
    local lo, hi
    for _, e in ipairs(d.recent) do
        lo = (not lo or e.dur < lo) and e.dur or lo
        hi = (not hi or e.dur > hi) and e.dur or hi
    end
    for i, b in ipairs(bars) do
        local e = d.recent[i]
        if e then
            local h = (hi and hi > lo) and (5 + (e.dur - lo) / (hi - lo) * 17) or 12
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", b:GetParent(), "LEFT", x0 + (i - 1) * 11, -11)
            b:SetHeight(h)
            local c = (e.cleared and e.dur == d.best) and P.bronzeHi or (e.cleared and P.bronze or P.ash2)
            b:SetColorTexture(c[1], c[2], c[3], e.cleared and 0.95 or 0.7)
            b:Show()
        else
            b:Hide()
        end
    end
end

local function OpenDungeon(name) selected = name; compareA, compareB = nil, nil; UI.RefreshStats() end

local function MakeDungeonRow(parent)
    local row = Btn(parent)
    row:SetSize(LEFT_W, ROW)
    HoverRow(row)
    row.cells = Cells(row, DCOLS)
    local recentX
    for _, c in ipairs(DCOLS) do if c.key == "recent" then recentX = c._x end end
    row.bars, row.recentX = RecentStrip(row), recentX
    row:SetScript("OnClick", function(self) OpenDungeon(self.dungeon) end)
    row:SetScript("OnEnter", function(self)
        local d = self.data
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(d.name, P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:AddLine(_fmt("%d runs, %d cleared", d.runs, d.cleared), P.ash[1], P.ash[2], P.ash[3])
        GameTooltip:AddLine("Recent runs, oldest to newest. Shorter bars are faster; the brightest is your best clear.",
            P.ash[1], P.ash[2], P.ash[3], true)
        GameTooltip:AddLine("Click for every run in this dungeon.", P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function MakeMateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(RIGHT_W, MATE_ROW)
    row:EnableMouse(true)
    HoverRow(row)
    row.name = Text(row, "medium", 14, P.ivory, "LEFT")
    row.name:SetPoint("LEFT", row, "LEFT", 2, 0); row.name:SetWidth(RIGHT_W - 70)
    row.count = Text(row, "medium", 13, P.ash, "RIGHT")
    row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row:SetScript("OnEnter", function(self)
        local m = self.data
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(DN(m.name), P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:AddLine(_fmt("%d runs together, %d cleared", m.runs, m.cleared), P.ash[1], P.ash[2], P.ash[3])
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- Detail: one row per boss.
local BOSS_COL = 58
local function MakeBossRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(RIGHT_W, MATE_ROW)
    row:EnableMouse(true)
    HoverRow(row)
    row.name = Text(row, "medium", 14, P.ivory, "LEFT")
    row.name:SetPoint("LEFT", row, "LEFT", 2, 0); row.name:SetWidth(RIGHT_W - 2 * BOSS_COL - 8)
    row.typical = Text(row, "medium", 13, P.ivory, "CENTER")
    row.typical:SetPoint("CENTER", row, "RIGHT", -BOSS_COL / 2, 0)
    row.best = Text(row, "medium", 13, P.ivory, "CENTER")
    row.best:SetPoint("CENTER", row, "RIGHT", -BOSS_COL * 1.5, 0)
    row:SetScript("OnEnter", function(self)
        local b = self.data
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(b.name, P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:AddDoubleLine("Kills", b.kills, P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        if b.best then
            GameTooltip:AddDoubleLine("Fastest fight", Dur(b.best), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
            GameTooltip:AddDoubleLine("Typical fight", Dur(b.typical), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        end
        if b.bestDps then
            GameTooltip:AddDoubleLine("Your best DPS", Abbrev(b.bestDps), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        end
        if not b.best then
            GameTooltip:AddLine("Fight lengths are recorded from version 2.5 on.", P.ash[1], P.ash[2], P.ash[3], true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function BuildOverview(parent)
    local o = CreateFrame("Frame", nil, parent)
    o:SetAllPoints()
    local band = Band(o, DCOLS, X0)
    band:SetPoint("TOPLEFT", o, "TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", o, "TOPRIGHT", 0, 0)
    local mates = Text(band, "medium", 13, P.ash, "LEFT")
    mates:SetPoint("LEFT", band, "LEFT", RIGHT_X, 0); mates:SetText("Played with")

    -- Reset stats: empties the archive (history is kept).
    local reset = Btn(band)
    reset:SetSize(140, COL_HDR_H - 6)
    reset:SetPoint("RIGHT", band, "LEFT", RIGHT_X + RIGHT_W, 0)
    local resetTxt = Text(reset, "medium", 13, P.ash2, "RIGHT")
    resetTxt:SetPoint("RIGHT", reset, "RIGHT", 0, 0); resetTxt:SetText("Reset stats")
    local function ResetLook(armed)
        local c = armed and P.bloodHi or P.ash2
        resetTxt:SetText(armed and "Click again to reset" or "Reset stats")
        resetTxt:SetTextColor(c[1], c[2], c[3])
    end
    TwoClick(reset, ResetLook, function()
        MS:ResetArchive()
        UI.RefreshStats(true)
    end)
    reset:SetScript("OnEnter", function(self)
        if not self.IsArmed() then resetTxt:SetTextColor(P.bloodHi[1], P.bloodHi[2], P.bloodHi[3]) end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Reset stats", P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:AddLine(multiChar
            and "Removes every run of this character from your stats. Other characters keep theirs, and your run history in the dropdown is kept."
            or "Removes every run from your stats. Your run history in the dropdown is kept.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function(self)
        if not self.IsArmed() then resetTxt:SetTextColor(P.ash2[1], P.ash2[2], P.ash2[3]) end
        GameTooltip:Hide()
    end)
    o.reset = reset

    o.sf = MakeScrollFrame(o)
    o.sf:SetPoint("TOPLEFT", o, "TOPLEFT", X0, -COL_HDR_H)
    o.sf:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", X0, 8)
    o.sf:SetWidth(LEFT_W + 10)
    o.rowAt, o.rowsHideFrom = Pool(function() return MakeDungeonRow(o.sf.scrollContent) end)

    o.msf = MakeScrollFrame(o)
    o.msf:SetPoint("TOPLEFT", o, "TOPLEFT", RIGHT_X, -COL_HDR_H)
    o.msf:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", RIGHT_X, 8)
    o.msf:SetWidth(RIGHT_W + 10)
    o.mateAt, o.matesHideFrom = Pool(function() return MakeMateRow(o.msf.scrollContent) end)

    o.empty = Text(o, "regular", 15, P.ash, "CENTER")
    o.empty:SetPoint("CENTER", o, "LEFT", X0 + LEFT_W / 2, -20)
    o.empty:SetWidth(LEFT_W - 80); o.empty:SetWordWrap(true)
    o.empty:SetText("No finished runs yet. Every run you finish or leave from now on is added here.")
    o.noMates = Text(o, "regular", 14, P.ash, "LEFT")
    o.noMates:SetPoint("TOPLEFT", o, "TOPLEFT", RIGHT_X + 2, -COL_HDR_H - 10)
    o.noMates:SetText("Nobody yet.")
    return o
end

local function FillOverview(o, stats)
    local y = 0
    for i, d in ipairs(stats.dungeons) do
        local row = o.rowAt(i)
        row:SetPoint("TOPLEFT", o.sf.scrollContent, "TOPLEFT", 0, -y)
        row.dungeon, row.data = d.name, d
        local c = row.cells
        c.name:SetText(d.name)
        c.runs:SetText(d.runs)
        c.cleared:SetText(Pct(d.cleared, d.runs))
        c.best:SetText(d.best and Dur(d.best) or CT(P.ash2, "-"))
        c.typical:SetText(d.typical and Dur(d.typical) or CT(P.ash2, "-"))
        c.deaths:SetText(_fmt("%.1f", d.deathsPerRun))
        c.deaths:SetTextColor((d.deathsPerRun >= 1 and P.bloodHi or P.ivory)[1],
            (d.deathsPerRun >= 1 and P.bloodHi or P.ivory)[2], (d.deathsPerRun >= 1 and P.bloodHi or P.ivory)[3])
        if c.xp then
            c.xp:SetText(d.xpPerRun and Abbrev(d.xpPerRun) or CT(P.ash2, "-"))
        else
            c.dps:SetText(d.lastDps and (Abbrev(d.lastDps) .. (d.lastLvl and CT(P.ash, "  L" .. d.lastLvl) or "")) or CT(P.ash2, "-"))
        end
        FillRecent(row.bars, d, row.recentX)
        y = y + ROW
    end
    o.rowsHideFrom(#stats.dungeons + 1)
    o.sf.scrollContent:SetHeight(_max(1, y))
    o.sf.UpdateRange()
    o.empty:SetShown(#stats.dungeons == 0)

    local my = 0
    for i, m in ipairs(stats.mates) do
        local row = o.mateAt(i)
        row:SetPoint("TOPLEFT", o.msf.scrollContent, "TOPLEFT", 0, -my)
        row.data = m
        row.name:SetText("|cff" .. ClassHex(m.class or "UNKNOWN") .. DN(m.name) .. "|r")
        row.count:SetText(m.runs .. (m.runs == 1 and " run" or " runs"))
        my = my + MATE_ROW
    end
    o.matesHideFrom(#stats.mates + 1)
    o.msf.scrollContent:SetHeight(_max(1, my))
    o.msf.UpdateRange()
    o.noMates:SetShown(#stats.mates == 0)
end

-- ── Detail: one dungeon ────────────────────────────────────────────────────
local function RunTooltip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(Day(e.at) .. (e.at and date("  %H:%M", e.at) or ""), P.ivory[1], P.ivory[2], P.ivory[3])
    GameTooltip:AddDoubleLine("Time", Dur(e.dur), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
    GameTooltip:AddDoubleLine("Result", Result(e), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
    if multiChar and MS:RunOwner(e) then
        GameTooltip:AddDoubleLine("Character", CharName(MS:RunOwner(e)), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
    end
    if e.me and e.me.lvl then GameTooltip:AddDoubleLine("Your level", e.me.lvl, P.ash[1], P.ash[2], P.ash[3], 1, 1, 1) end
    if e.me then GameTooltip:AddDoubleLine("Your DPS", Abbrev(e.me.dps), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1) end
    GameTooltip:AddDoubleLine("Group deaths", e.deaths or 0, P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
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
    local icon = Art(del, "Close", "OVERLAY")
    icon:SetSize(11, 11); icon:SetPoint("CENTER"); Tint(icon, P.ash2)
    TwoClick(del, function(armed) Tint(icon, armed and P.bloodHi or P.ash2) end, function()
        GameTooltip:Hide()
        MS:RemoveArchivedRun(row.entry)
        UI.RefreshStats(true)
    end)
    del:SetScript("OnEnter", function(self)
        Tint(icon, P.bloodHi)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Remove from stats", P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:AddLine(self.IsArmed() and "Click again to remove this run."
            or "Leaves your run history untouched.", 0.8, 0.8, 0.8, true)
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
        if compareA == e then compareA = nil
        elseif compareA then compareB = e
        else compareA = e end
        UI.RefreshStats(true)
    end)
    cmp:SetScript("OnEnter", function(self)
        self.text:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if compareA == row.entry then
            GameTooltip:SetText("Picked for comparison")
            GameTooltip:AddLine("Click again to cancel.", 0.8, 0.8, 0.8, true)
        elseif compareA then
            GameTooltip:SetText("Compare with the picked run")
        else
            GameTooltip:SetText("Compare")
            GameTooltip:AddLine("Pick this run, then another one, to see them side by side.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    cmp:SetScript("OnLeave", function(self) self.Look(); GameTooltip:Hide() end)
    cmp.Look = function()
        local picked = compareA ~= nil and compareA == row.entry
        cmp.text:SetText(picked and "Picked" or compareA and "Compare" or "Compare")
        local c = picked and P.bronzeHi or compareA and P.ivory or P.ash2
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
    bossLbl:SetPoint("LEFT", band, "LEFT", RIGHT_X, 0); bossLbl:SetText("Bosses")
    local typLbl = Text(band, "medium", 13, P.ash, "CENTER")
    typLbl:SetPoint("CENTER", band, "LEFT", RIGHT_X + RIGHT_W - BOSS_COL / 2, 0); typLbl:SetText("Typical")
    local bestLbl = Text(band, "medium", 13, P.ash, "CENTER")
    bestLbl:SetPoint("CENTER", band, "LEFT", RIGHT_X + RIGHT_W - BOSS_COL * 1.5, 0); bestLbl:SetText("Best")

    local back = Btn(band)
    back:SetPoint("LEFT", band, "LEFT", X0 - 4, 0); back:SetSize(128, COL_HDR_H - 6)
    local arrow = Art(back, "Chevron", "OVERLAY")
    arrow:SetSize(12, 12); arrow:SetPoint("LEFT", back, "LEFT", 4, 0)
    arrow:SetRotation(-math.pi / 2); Tint(arrow, P.ash)
    local backTxt = Text(back, "medium", 13, P.ash, "LEFT")
    backTxt:SetPoint("LEFT", arrow, "RIGHT", 4, 0); backTxt:SetText("All dungeons")
    back:SetScript("OnEnter", function() Tint(arrow, P.ivory); backTxt:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3]) end)
    back:SetScript("OnLeave", function() Tint(arrow, P.ash); backTxt:SetTextColor(P.ash[1], P.ash[2], P.ash[3]) end)
    back:SetScript("OnClick", function() selected = nil; compareA, compareB = nil, nil; UI.RefreshStats() end)
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
    d.noBosses:SetText("No bosses killed here yet.")
    return d
end

local MAX_BARS = 40

local function FillDetail(d, s, stats)
    d.title:SetText(s.name)
    if compareA then
        d.summary:SetText(CT(P.bronzeHi, "Pick a second run to compare with ") .. CT(P.ivory, Day(compareA.at) .. "  " .. Dur(compareA.dur)))
    else
        d.summary:SetText(_fmt("Best %s      Typical %s      %s cleared",
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
            d.bestLbl:SetText("Best")
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
        d.typLbl:SetText("Typical " .. Dur(s.typical))
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
        c.level:SetText(e.me and e.me.lvl or CT(P.ash2, "-"))
        c.time:SetText(e.cleared and e.dur == s.best and CT(P.bronzeHi, Dur(e.dur)) or Dur(e.dur))
        c.result:SetText(Result(e))
        c.deaths:SetText((e.deaths or 0) > 0 and CT(P.bloodHi, e.deaths) or CT(P.ash, "0"))
        if c.xp then
            c.xp:SetText(e.prog and MS.FormatThousands(e.prog.xp) or CT(P.ash2, "-"))
        else
            c.dps:SetText(e.me and Abbrev(e.me.dps) or CT(P.ash2, "-"))
        end
        local names = {}
        for _, b in ipairs(e.bosses or {}) do names[#names + 1] = b.n end
        c.bosses:SetText(#names > 0 and CT(P.ash, table.concat(names, ", ")) or CT(P.ash2, "None"))
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
    { key = "boss",  label = "Boss",           w = 200, left = true },
    { key = "k1",    label = "Killed 1",       w = 84 },
    { key = "k2",    label = "Killed 2",       w = 84 },
    { key = "split", label = "Run 2 was",      w = 112 },
    { key = "f1",    label = "Fight 1",        w = 76 },
    { key = "f2",    label = "Fight 2",        w = 76 },
    { key = "fd",    label = "",               w = 64 },
    { key = "t1",    label = "Trash 1",        w = 76 },
    { key = "t2",    label = "Trash 2",        w = 76 },
    { key = "td",    label = "",               w = 64 },
    { key = "m1",    label = "Your DPS 1",     w = 92 },
    { key = "m2",    label = "Your DPS 2",     w = 92 },
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
    if math.abs(d) < 1 then return CT(P.ash, "level") end
    return d < 0 and CT(P.verd, Dur(-d) .. " ahead") or CT(P.bloodHi, Dur(d) .. " behind")
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
    back:SetScript("OnClick", function() compareA, compareB = nil, nil; UI.RefreshStats(true) end)
    c.title = Text(band, "semibold", 15, P.ivory, "LEFT")
    c.title:SetPoint("LEFT", band, "LEFT", LANE_X, 0)
    c.title:SetText("Run comparison")

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
        lane.blockAt, lane.blocksHideFrom = Pool(function()
            local t = c:CreateTexture(nil, "ARTWORK"); return t
        end)
        c.lanes[i] = lane
    end
    c.linkAt, c.linksHideFrom = Pool(function()
        local l = c:CreateLine(nil, "ARTWORK")
        l:SetThickness(1)
        return l
    end)
    c.axis0 = Text(c, "medium", 11, P.ash, "LEFT")
    c.axisEnd = Text(c, "medium", 11, P.ash, "RIGHT")
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

local function FillCompare(c, cmp)
    local A, B = cmp.first, cmp.second
    c.backTxt:SetText(A.dungeon or "Back")
    local scale = _max(A.dur or 1, B.dur or 1, 1)
    local function LX(t) return LANE_X + (t or 0) / scale * LANE_W end
    for i, e in ipairs({ A, B }) do
        local lane = c.lanes[i]
        lane.head:SetText(Day(e.at) .. (e.at and date("  %H:%M", e.at) or "")
            .. (multiChar and MS:RunOwner(e) and ("   " .. CharName(MS:RunOwner(e))) or ""))
        lane.sub:SetText(table.concat({
            CT(P.ivory, Dur(e.dur)), Result(e),
            ((e.deaths or 0) > 0 and CT(P.bloodHi, e.deaths .. (e.deaths == 1 and " death" or " deaths")) or "No deaths"),
        }, "    "))
        local k = 0
        for _, b in ipairs(e.bosses or {}) do
            k = k + 1
            local t = lane.blockAt(k)
            local x1 = LX(b.d and (b.t - b.d) or b.t)
            local w = _max(2, LX(b.t) - x1)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", c, "TOPLEFT", x1, lane.y - 8)
            t:SetSize(w, LANE_H)
            VGrad(t, FIGHT_BOT, FIGHT_TOP)
        end
        lane.blocksHideFrom(k + 1)
        lane.ends:ClearAllPoints()
        lane.ends:SetPoint("TOPLEFT", c, "TOPLEFT", LX(e.dur) - 1, lane.y - 4)
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
            l:SetColorTexture(col[1], col[2], col[3], 0.7)
            l:SetStartPoint("TOPLEFT", c, LX(r.a.t), y1)
            l:SetEndPoint("TOPLEFT", c, LX(r.b.t), y2)
        end
    end
    c.linksHideFrom(n + 1)
    c.axis0:ClearAllPoints(); c.axis0:SetPoint("TOPLEFT", c, "TOPLEFT", LANE_X, y2 - LANE_H - 4); c.axis0:SetText("0:00")
    c.axisEnd:ClearAllPoints(); c.axisEnd:SetPoint("TOPRIGHT", c, "TOPLEFT", LANE_X + LANE_W, y2 - LANE_H - 4)
    c.axisEnd:SetText(Dur(scale))

    -- Verdict
    local T = cmp.total
    local d = T.diff
    local head = math.abs(d) < 1 and "Both runs took the same time."
        or (d < 0 and CT(P.verd, "Run 2 was " .. Dur(-d) .. " faster.") or CT(P.bloodHi, "Run 2 was " .. Dur(d) .. " slower."))
    local extra = {}
    if T.fightA and T.fightB and T.trashA and T.trashB and math.abs(d) >= 1 then
        local fd, td = T.fightB - T.fightA, T.trashB - T.trashA
        extra[#extra + 1] = "Boss fights " .. Signed(fd) .. ", trash " .. Signed(td)
    end
    if T.dpsA and T.dpsB then extra[#extra + 1] = "Your DPS " .. Abbrev(T.dpsA) .. " vs " .. Abbrev(T.dpsB) end
    extra[#extra + 1] = "Deaths " .. T.deathsA .. " vs " .. T.deathsB
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
    cl.boss:SetText(CT(P.ash, "After the last boss"))
    for _, key in ipairs({ "k1", "k2", "split", "f1", "f2", "fd", "m1", "m2" }) do cl[key]:SetText("") end
    cl.t1:SetText(Dur(T.endA)); cl.t2:SetText(Dur(T.endB)); cl.td:SetText(Signed(T.endB - T.endA))
    cl = Row()
    cl.boss:SetText(CT(P.ivory, "Whole run"))
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

-- ── Loot ───────────────────────────────────────────────────────────────────
local function ItemID(item) return tonumber(tostring(item or ""):match("item:(%d+)")) end

local function ItemName(l)
    local fromLink = l.l and l.l:match("|h%[(.-)%]|h")
    if fromLink then return fromLink end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name = pcall(get, MS.LootItemString(l))
    if ok and name then return name end
    return nil
end

local function ItemIcon(l)
    local id = ItemID(MS.LootItemString(l))
    if not id then return nil end
    local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    local ok, icon = pcall(get, id)
    return ok and icon or nil
end

local function QualityColor(q)
    if not q then return P.ivory end
    return { UI.QualityColor(q) }
end

-- Item names can arrive a moment after they're asked for.
local waitingForItems = false
local itemFrame = CreateFrame("Frame")
itemFrame:SetScript("OnEvent", function()
    if not waitingForItems then return end
    waitingForItems = false
    C_Timer.After(0.3, function() if UI.statsOpen and tab == "loot" then UI.RefreshStats(true) end end)
end)
pcall(itemFrame.RegisterEvent, itemFrame, "GET_ITEM_INFO_RECEIVED")

local function MakeLootRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_W - 2 * X0 - 10, LOOT_ROW)
    row:EnableMouse(true)
    HoverRow(row)
    row.cells = Cells(row, LCOLS, 14)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22); row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.cells.item:ClearAllPoints()
    row.cells.item:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.cells.item:SetWidth(LCOLS[1].w - 40)
    row:SetScript("OnEnter", function(self)
        local l = self.data and self.data.item
        if not l then return end
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("BOTTOMLEFT", self.icon, "TOPRIGHT", 4, 2)
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, l.l or MS.LootItemString(l)) then
            GameTooltip:SetText(ItemName(l) or "Item")
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Shift-click links it in chat, as with any item.
    row:SetScript("OnMouseUp", function(self)
        local l = self.data and self.data.item
        if l and HandleModifiedItemClick then pcall(HandleModifiedItemClick, l.l or MS.LootItemString(l)) end
    end)
    return row
end

local function BuildLoot(parent)
    local lv = CreateFrame("Frame", nil, parent)
    lv:SetAllPoints()
    local band = Band(lv, LCOLS, X0)
    band:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", lv, "TOPRIGHT", 0, 0)
    lv.band = band
    lv.sf = MakeScrollFrame(lv)
    lv.sf:SetPoint("TOPLEFT", lv, "TOPLEFT", X0, -COL_HDR_H)
    lv.sf:SetPoint("BOTTOMLEFT", lv, "BOTTOMLEFT", X0, 8)
    lv.sf:SetWidth(FRAME_W - 2 * X0)
    lv.rowAt, lv.rowsHideFrom = Pool(function() return MakeLootRow(lv.sf.scrollContent) end)
    lv.empty = Text(lv, "regular", 15, P.ash, "CENTER")
    lv.empty:SetPoint("CENTER", lv, "CENTER", 0, -10)
    lv.empty:SetWidth(560); lv.empty:SetWordWrap(true)
    lv.empty:SetText("No loot yet. Gear that drops for you in a dungeon is listed here.")
    return lv
end

local function FillLoot(lv, items)
    lv.band.labels.char:SetShown(multiChar)
    local y, n = 0, _min(#items, MAX_LOOT)
    for i = 1, n do
        local it = items[i]
        local l, e = it.item, it.run
        local row = lv.rowAt(i)
        row:SetPoint("TOPLEFT", lv.sf.scrollContent, "TOPLEFT", 0, -y)
        row.data = it
        row.icon:SetTexture(ItemIcon(l) or 134400)            -- question mark until known
        local name = ItemName(l)
        if not name then waitingForItems = true end
        local qc = QualityColor(l.q)
        row.cells.item:SetText(name or "Loading...")
        row.cells.item:SetTextColor(qc[1], qc[2], qc[3])
        row.cells.dungeon:SetText(e.dungeon or "?")
        row.cells.boss:SetText(l.b and CT(P.ash, l.b) or CT(P.ash2, "Trash"))
        row.cells.date:SetText(CT(P.ash, Day(e.at)))
        row.cells.char:SetText(multiChar and CharName(MS:RunOwner(e)) or "")
        y = y + LOOT_ROW
    end
    lv.rowsHideFrom(n + 1)
    lv.sf.scrollContent:SetHeight(_max(1, y))
    lv.sf.UpdateRange()
    lv.empty:SetShown(n == 0)
end

-- ── Header controls: tabs and the character filter ─────────────────────────
-- Built once and refilled each time it opens: the game never frees a frame.
local charMenu            -- the menu while it's open
local menuFrame, menuRows = nil, {}
local function CloseCharMenu()
    charMenu = nil
    if menuFrame then menuFrame:Hide() end
end

local MENU_ROW = 26
local function MenuRow(i)
    local row = menuRows[i]
    if row then return row end
    row = Btn(menuFrame)
    row.hov = Solid(row, "BACKGROUND", 1, P.bronze[1], P.bronze[2], P.bronze[3], 0.14)
    row.hov:SetAllPoints()
    row.mark = Solid(row, "ARTWORK", 0, P.bronze[1], P.bronze[2], P.bronze[3], 1)
    row.mark:SetPoint("TOPLEFT"); row.mark:SetPoint("BOTTOMLEFT"); row.mark:SetWidth(2)
    row.lbl = Text(row, "medium", 13, P.ivory, "LEFT")
    row.lbl:SetPoint("LEFT", 10, 0)
    row.cnt = Text(row, "medium", 12, P.ash, "RIGHT")
    row.cnt:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnEnter", function(self) self.hov:Show() end)
    row:SetScript("OnLeave", function(self) if not self.on then self.hov:Hide() end end)
    row:SetScript("OnClick", function(self)
        MS:SetStatsChar(self.key)
        CloseCharMenu()
        selected = nil; compareA, compareB = nil, nil
        UI.RefreshStats(true)
    end)
    menuRows[i] = row
    return row
end

local function OpenCharMenu(anchor)
    if charMenu then CloseCharMenu(); return end
    if not menuFrame then
        menuFrame = CreateFrame("Frame", nil, UIParent)
        menuFrame:SetFrameStrata("TOOLTIP"); menuFrame:EnableMouse(true)
        Box(menuFrame)
        menuFrame:SetScript("OnHide", function() charMenu = nil end)
    end
    local m = menuFrame
    local entries = { { key = "all", label = "All characters" } }
    for _, c in ipairs(MS:StatsCharacters()) do
        entries[#entries + 1] = { key = c.key, label = CharName(c.key), runs = c.runs, me = c.me }
    end
    m:SetSize(anchor:GetWidth() + 40, #entries * MENU_ROW + 8)
    m:ClearAllPoints()
    m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    local current = MS:GetStatsChar()
    for i, en in ipairs(entries) do
        local row = MenuRow(i)
        row:SetSize(m:GetWidth() - 8, MENU_ROW)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", m, "TOPLEFT", 4, -4 - (i - 1) * MENU_ROW)
        row.key, row.on = en.key, en.key == current
        row.hov:SetShown(row.on); row.mark:SetShown(row.on)
        row.lbl:SetText(en.label .. (en.me and CT(P.ash2, "  (you)") or ""))
        row.cnt:SetText(en.runs and (en.runs .. (en.runs == 1 and " run" or " runs")) or "")
        row:Show()
    end
    for i = #entries + 1, #menuRows do menuRows[i]:Hide() end
    m:Show()
    charMenu = m
end

local function TabButton(parent, label, key)
    local b = Btn(parent)
    local t = Text(b, "semibold", 14, P.ash, "CENTER")
    t:SetPoint("CENTER", 0, 1)
    local line = Solid(b, "ARTWORK", 0, P.bronze[1], P.bronze[2], P.bronze[3], 1)
    line:SetPoint("BOTTOMLEFT", 2, 0); line:SetPoint("BOTTOMRIGHT", -2, 0); line:SetHeight(2)
    b.SetLabel = function(text)
        t:SetText(text)
        b:SetSize(t:GetStringWidth() + 16, 26)
    end
    b.Refresh = function()
        local on = tab == key
        line:SetShown(on)
        local c = on and P.ivory or P.ash
        t:SetTextColor(c[1], c[2], c[3])
    end
    b:SetScript("OnEnter", function() if tab ~= key then t:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3]) end end)
    b:SetScript("OnLeave", function() b.Refresh() end)
    b:SetScript("OnClick", function()
        if tab == key then return end
        tab = key; selected = nil; compareA, compareB = nil, nil
        CloseCharMenu()
        UI.RefreshStats(true)
    end)
    b.SetLabel(label)
    return b
end

local function BuildControls(sbFrame)
    local c = CreateFrame("Frame", nil, sbFrame)
    c:SetSize(10, 26)
    c:SetPoint("TOPRIGHT", sbFrame, "TOPRIGHT", -14, -52)
    c:SetFrameLevel(sbFrame:GetFrameLevel() + 20)

    local cb = Btn(c)
    cb:SetSize(190, 26)
    cb:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    Box(cb, true)
    local chev = Art(cb, "Chevron", "ARTWORK")
    chev:SetSize(12, 12); chev:SetPoint("RIGHT", -8, 0); Tint(chev, P.ash)
    cb.text = Text(cb, "medium", 13, P.ivory, "LEFT")
    cb.text:SetPoint("LEFT", 10, 0); cb.text:SetPoint("RIGHT", chev, "LEFT", -6, 0)
    cb:HookScript("OnEnter", function()
        Tint(chev, P.ivory)
        if charMenu then return end
        GameTooltip:SetOwner(cb, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Characters")
        GameTooltip:AddLine("Show stats for all your characters, or one of them.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    cb:HookScript("OnLeave", function() Tint(chev, P.ash); GameTooltip:Hide() end)
    cb:SetScript("OnClick", function() GameTooltip:Hide(); OpenCharMenu(cb) end)
    c.charBtn = cb

    c.lootTab = TabButton(c, "Loot", "loot")
    c.dunTab = TabButton(c, "Dungeons", "dungeons")
    c.dunTab:SetPoint("RIGHT", c.lootTab, "LEFT", -6, 0)
    c.Layout = function()
        c.lootTab:ClearAllPoints()
        if cb:IsShown() then c.lootTab:SetPoint("RIGHT", cb, "LEFT", -18, 0)
        else c.lootTab:SetPoint("RIGHT", c, "RIGHT", 0, 0) end
    end
    c:Hide()
    return c
end

-- ── Public ─────────────────────────────────────────────────────────────────
function UI.BuildStatsView(sbFrame)
    view = CreateFrame("Frame", nil, sbFrame)
    view:SetPoint("TOPLEFT", sbFrame, "TOPLEFT", 1, -(HDR_H + 1))
    view:SetPoint("BOTTOMRIGHT", sbFrame, "BOTTOMRIGHT", -1, 1)
    local top = Solid(view, "BORDER", 0, P.line[1], P.line[2], P.line[3], 1)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    overview = BuildOverview(view)
    detail = BuildDetail(view)
    lootView = BuildLoot(view)
    compareView = BuildCompare(view)
    controls = BuildControls(sbFrame)
    view:Hide()
    return view
end

-- What the page last drew. The live run's refresh (every meter poll) calls
-- this too, but the page only shows finished runs: redrawing anyway
-- re-anchors the row under the mouse, which closes its tooltip.
local drawnSig

function UI.RefreshStats(force)
    if not (view and UI.statsOpen and UI.frame) then return end
    local runs = MS:StatsRuns()
    local chars = MS:StatsCharacters()
    local who = MS:GetStatsChar()
    local sig = #runs .. "|" .. MS:StatsRevision() .. "|" .. tostring(selected) .. "|" .. tab .. "|" .. who .. "|" .. #chars
        .. "|" .. tostring(compareA) .. "|" .. tostring(compareB)
    if sig == drawnSig and not force then return end
    if overview and overview.reset then overview.reset.Disarm() end
    drawnSig = sig
    multiChar = #chars > 1
    local stats = MS:StatsOverview()

    -- Header controls
    controls:Show()
    controls.charBtn:SetShown(multiChar)
    controls.charBtn.text:SetText(who == "all" and "All characters" or CharName(who))
    local items = MS:LootHistory()
    controls.lootTab.SetLabel(#items > 0 and ("Loot  " .. CT(P.ash2, #items)) or "Loot")
    controls.dunTab.Refresh(); controls.lootTab.Refresh()
    controls.Layout()
    -- Only the character you're on can reset its own stats.
    overview.reset:SetShown(who == "all" or who == MS._charKey)
    local f = UI.frame
    f.DungeonName:SetText("Your stats")
    f.SetBadge(nil)
    f.PBLabel:Hide()
    if f.WholeRunBtn then f.WholeRunBtn:Hide() end
    if f.AbandonBtn then f.AbandonBtn:Hide() end
    f.LayoutAffixIcons(0)
    local parts = {
        CT(P.ivory, stats.runs) .. (stats.runs == 1 and " run" or " runs"),
        CT(P.ivory, stats.cleared) .. " cleared",
        CT(P.ivory, Hours(stats.time)) .. " in dungeons",
        CT(P.ivory, _fmt("%.1f", stats.deathsPerRun)) .. " deaths a run",
    }
    if MS.Flavor.progressStats and (stats.progRuns or 0) > 0 then
        parts[#parts + 1] = CT(P.ivory, MS.FormatThousands(stats.xp)) .. " XP"
        parts[#parts + 1] = CT(P.ivory, MS.FormatThousands(stats.kills)) .. " kills"
        parts[#parts + 1] = CT(P.ivory, stats.quests) .. " quests"
        parts[#parts + 1] = CT(P.bronzeHi, MS.FormatGold(stats.gold))
    end
    f.SublineRun = nil
    f.Subline:SetText(table.concat(parts, "      "))

    if selected then
        local s = MS:StatsForDungeon(selected)
        if #s.runs == 0 then selected = nil end
    end
    -- A picked run that's gone (removed, other filter) cancels the comparison.
    local function Listed(e)
        if not (e and selected) then return false end
        for _, x in ipairs(MS:StatsForDungeon(selected).runs) do if x == e then return true end end
        return false
    end
    if compareA and not Listed(compareA) then compareA, compareB = nil, nil end
    if compareB and not Listed(compareB) then compareB = nil end
    local onLoot = tab == "loot"
    local comparing = not onLoot and selected ~= nil and compareA ~= nil and compareB ~= nil
    overview:SetShown(not onLoot and not selected)
    detail:SetShown(not onLoot and selected ~= nil and not comparing)
    compareView:SetShown(comparing)
    lootView:SetShown(onLoot)
    if onLoot then FillLoot(lootView, items)
    elseif comparing then FillCompare(compareView, MS:CompareRuns(compareA, compareB))
    elseif selected then FillDetail(detail, MS:StatsForDungeon(selected), stats)
    else FillOverview(overview, stats) end
end

local function SetRunViewShown(shown)
    local f = UI.frame
    for _, part in ipairs({ f.ColHeader, f.overviewSF, f.timelineContainer }) do
        if part then part:SetShown(shown) end
    end
end

function UI.OpenStats()
    if not UI.frame then MS:BuildUI() end
    UI.statsOpen = true
    selected = nil
    drawnSig = nil
    if UI.frame.SettingsPopup then UI.frame.SettingsPopup:Hide() end
    SetRunViewShown(false)
    view:Show()
    if UI.frame.StatsBtn then UI.frame.StatsBtn.SetActive(true) end
    UI.frame:Show()
    UI.RefreshStats()
end

function UI.CloseStats()
    if not UI.statsOpen then return end
    UI.statsOpen = false
    view:Hide()
    controls:Hide()
    CloseCharMenu()
    SetRunViewShown(true)
    if UI.frame.StatsBtn then UI.frame.StatsBtn.SetActive(false) end
    MS:RefreshOverview()
end

function UI.ToggleStats()
    if UI.statsOpen then UI.CloseStats() else UI.OpenStats() end
end

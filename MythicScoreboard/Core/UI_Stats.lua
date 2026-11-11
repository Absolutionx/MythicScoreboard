local _floor, _max = math.floor, math.max
local _fmt = string.format

local MS = _G["MythicScoreboard"]
local L = MS.L
local LK = MS.LK      -- a label kept in English, translated where it is shown
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local P, PAD_X, HDR_H, COL_HDR_H, FRAME_W = UI.P, UI.PAD_X, UI.HDR_H, UI.COL_HDR_H, UI.FRAME_W
local Text, Solid, Btn, Tint, Art, Box = UI.Text, UI.Solid, UI.Btn, UI.Tint, UI.Art, UI.Box
local MakeScrollFrame, ClassHex, CT, DN, Abbrev = UI.MakeScrollFrame, UI.ClassHex, UI.CT, UI.DN, UI.Abbrev

-- Stats page: your run history across every dungeon, from the archive
-- (Archive.lua). It takes the place of the table and timeline while open.
--
--   overview  dungeon table (left) + people you've played with (right)
--   detail    one dungeon: a bar per run, then the list of runs; each boss
--             with its fight lengths on the right
--   loot      every piece of gear that dropped for you, newest first
--   compare   two runs of one dungeon side by side (picked from the run list)
--   keys      (Mythic+) rating key by key, timed rates by dungeon and level
--
-- Tabs (Dungeons / Keys / Loot) and the character filter sit in the header.

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
    -- (Widths add up to the band's; each header fits its column in every
    -- language with room to spare: locale_tests checks.)
    { key = "name",    label = LK("Dungeon"),        w = 174, left = true },  -- long names step down a size
    { key = "runs",    label = LK("Runs"),           w = 56 },
    { key = "cleared", label = LK("Cleared#column"), w = 64 },
    { key = "best",    label = LK("Best"),           w = 62 },   -- "1:24:33"
    { key = "typical", label = LK("Typical"),        w = 62 },
    { key = "recent",  label = LK("Recent runs"),    w = 130, left = true },  -- 12 bars, 11px apart: 128
    { key = "deaths",  label = LK("Deaths/run"),     w = 82 },
    { key = "dps",     label = LK("Your DPS"),       w = 70 },
}
-- Forever: what runs gave you, in place of your DPS.
if MS.Flavor.progressStats then
    for i, c in ipairs(DCOLS) do
        if c.key == "dps" then DCOLS[i] = { key = "xp", label = LK("XP a run"), w = c.w } end
    end
end
local LCOLS = {   -- loot: one row per item
    { key = "item",    label = LK("Item"),      w = 370, left = true },
    { key = "dungeon", label = LK("Dungeon"),   w = 220, left = true },
    { key = "boss",    label = LK("Boss"),      w = 210, left = true },
    { key = "date",    label = LK("Date"),      w = 80,  left = true },
    { key = "char",    label = LK("Character"), w = 130, left = true },
}
local LOOT_ROW = 30
local MAX_LOOT = 500
local RCOLS = {   -- detail: one row per run
    { key = "date",   label = LK("Date"),     w = 92,  left = true },
    { key = "level",  label = LK("Level"),    w = 56 },
    { key = "time",   label = LK("Time"),     w = 70 },
    { key = "result", label = LK("Result"),   w = 96,  left = true },
    { key = "deaths", label = LK("Deaths"),   w = 64 },
    { key = "dps",    label = LK("Your DPS"), w = 80 },
    { key = "bosses", label = LK("Bosses"),   w = 242, left = true },
}
if MS.Flavor.progressStats then
    for i, c in ipairs(RCOLS) do
        if c.key == "dps" then RCOLS[i] = { key = "xp", label = LK("XP"), w = c.w } end
    end
end

-- ── Formatting ─────────────────────────────────────────────────────────────
local function Dur(s) return MS:FormatLongTime(s) end
local function Hours(s)
    local m = _floor((s or 0) / 60 + 0.5)
    if m < 60 then return _fmt(L["%dm"], m) end
    return _fmt(L["%dh %02dm"], _floor(m / 60), m % 60)
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
local view, overview, detail, lootView, controls, compareView, keysView
-- (In one table, shared with UI_StatsDungeon.lua and UI_StatsLoot.lua.)
local S = {
    selected  = nil,         -- dungeon name shown in detail, or nil for the overview
    compareA  = nil,         -- runs picked for comparison (archive entries)
    compareB  = nil,
    tab       = "dungeons",  -- or "keys", "loot"
    multiChar = false,       -- more than one character has runs
}

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
        -- Each name in a frame the width of its column. (A label given a
        -- fixed width of its own didn't show in the game; the names fit
        -- their columns anyway: header_fit.py checks every language.)
        local cell = CreateFrame("Frame", nil, band)
        cell:SetSize(c.w, COL_HDR_H)
        cell:SetPoint("LEFT", band, "LEFT", lx, 0)
        local lbl = Text(cell, "medium", 13, P.ash, c.left and "LEFT" or "CENTER")
        if c.left then lbl:SetPoint("LEFT", cell, "LEFT", 0, 0)
        else lbl:SetPoint("CENTER", cell, "CENTER", 0, 0) end
        lbl:SetText(L[c.label])
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

local Pool = UI.Pool

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

local function OpenDungeon(name) S.selected = name; S.compareA, S.compareB = nil, nil; UI.RefreshStats() end

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
        GameTooltip:AddLine(MS.Plural(d.runs, "%d run", "%d runs") .. ", " .. _fmt(L["%d cleared"], d.cleared), P.ash[1], P.ash[2], P.ash[3])
        GameTooltip:AddLine(L["Recent runs, oldest to newest. Shorter bars are faster; the brightest is your best clear."],
            P.ash[1], P.ash[2], P.ash[3], true)
        GameTooltip:AddLine(L["Click for every run in this dungeon."], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
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
        GameTooltip:AddLine(MS.Plural(m.runs, "%d run together", "%d runs together") .. ", " .. _fmt(L["%d cleared"], m.cleared), P.ash[1], P.ash[2], P.ash[3])
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
        GameTooltip:AddDoubleLine(L["Kills"], b.kills, P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        if b.best then
            GameTooltip:AddDoubleLine(L["Fastest fight"], Dur(b.best), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Typical fight"], Dur(b.typical), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        end
        if b.bestDps then
            GameTooltip:AddDoubleLine(L["Your best DPS"], Abbrev(b.bestDps), P.ash[1], P.ash[2], P.ash[3], 1, 1, 1)
        end
        if not b.best then
            GameTooltip:AddLine(L["Fight lengths are recorded from version 2.5 on."], P.ash[1], P.ash[2], P.ash[3], true)
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
    mates:SetPoint("LEFT", band, "LEFT", RIGHT_X, 0); mates:SetText(L["Played with"])

    -- Reset stats: empties the archive (history is kept).
    local reset = Btn(band)
    reset:SetSize(140, COL_HDR_H - 6)
    reset:SetPoint("RIGHT", band, "LEFT", RIGHT_X + RIGHT_W, 0)
    local resetTxt = Text(reset, "medium", 13, P.ash2, "RIGHT")
    resetTxt:SetPoint("RIGHT", reset, "RIGHT", 0, 0); resetTxt:SetText(L["Reset stats"])
    local function ResetLook(armed)
        local c = armed and P.bloodHi or P.ash2
        resetTxt:SetText(armed and L["Click again to reset"] or L["Reset stats"])
        resetTxt:SetTextColor(c[1], c[2], c[3])
    end
    TwoClick(reset, ResetLook, function()
        MS:ResetArchive()
        UI.RefreshStats(true)
    end)
    reset:SetScript("OnEnter", function(self)
        if not self.IsArmed() then resetTxt:SetTextColor(P.bloodHi[1], P.bloodHi[2], P.bloodHi[3]) end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Reset stats"], P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:AddLine(S.multiChar
            and L["Removes every run of this character from your stats. Other characters keep theirs, and your run history in the dropdown is kept."]
            or L["Removes every run from your stats. Your run history in the dropdown is kept."], 0.8, 0.8, 0.8, true)
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
    o.empty:SetText(L["No finished runs yet. Every run you finish or leave from now on is added here."])
    o.noMates = Text(o, "regular", 14, P.ash, "LEFT")
    o.noMates:SetPoint("TOPLEFT", o, "TOPLEFT", RIGHT_X + 2, -COL_HDR_H - 10)
    o.noMates:SetText(L["Nobody yet."])
    return o
end

local function FillOverview(o, stats)
    local y = 0
    for i, d in ipairs(stats.dungeons) do
        local row = o.rowAt(i)
        row:SetPoint("TOPLEFT", o.sf.scrollContent, "TOPLEFT", 0, -y)
        row.dungeon, row.data = d.name, d
        local c = row.cells
        UI.FitText(c.name, d.name, "semibold", 15, 12)   -- long names step down a size
        c.runs:SetText(d.runs)
        c.cleared:SetText(Pct(d.cleared, d.runs))
        UI.FitText(c.best, d.best and Dur(d.best) or CT(P.ash2, "-"), "medium", 15, 12)
        UI.FitText(c.typical, d.typical and Dur(d.typical) or CT(P.ash2, "-"), "medium", 15, 12)
        c.deaths:SetText(_fmt("%.1f", d.deathsPerRun))
        c.deaths:SetTextColor((d.deathsPerRun >= 1 and P.bloodHi or P.ivory)[1],
            (d.deathsPerRun >= 1 and P.bloodHi or P.ivory)[2], (d.deathsPerRun >= 1 and P.bloodHi or P.ivory)[3])
        if c.xp then
            -- XP a run; under it, the split between the dungeon and quests.
            c.xp:SetText(d.xpPerRun and Abbrev(d.xpPerRun) or CT(P.ash2, "-"))
            local q = d.questXP or 0
            if not c.xpSplit then
                c.xpSplit = Text(row, "medium", 8, P.ivory, "CENTER")
                c.xpSplit:SetPoint("TOP", c.xp, "BOTTOM", 0, -1)
            end
            c.xpSplit:SetText((q > 0 and d.xp) and UI.XPSplit(d.xp - q, q, 44, 4) or "")
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
        UI.SetNameText(row.name, "|cff" .. ClassHex(m.class or "UNKNOWN") .. DN(m.name) .. "|r")
        row.count:SetText(MS.Plural(m.runs, "%d run", "%d runs"))
        my = my + MATE_ROW
    end
    o.matesHideFrom(#stats.mates + 1)
    o.msf.scrollContent:SetHeight(_max(1, my))
    o.msf.UpdateRange()
    o.noMates:SetShown(#stats.mates == 0)
end

-- ── Detail, compare and loot: UI_StatsDungeon.lua and UI_StatsLoot.lua ─────

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
        S.selected = nil; S.compareA, S.compareB = nil, nil
        UI.RefreshStats(true)
    end)
    menuRows[i] = row
    return row
end

local function OpenCharMenu(anchor)
    if charMenu then CloseCharMenu(); return end
    if not menuFrame then
        menuFrame = CreateFrame("Frame", nil, UIParent)
        menuFrame:SetFrameStrata("FULLSCREEN_DIALOG"); menuFrame:EnableMouse(true)
        Box(menuFrame)
        menuFrame:SetScript("OnHide", function() charMenu = nil end)
    end
    local m = menuFrame
    local entries = { { key = "all", label = L["All characters"] } }
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
        row.lbl:SetText(en.label .. (en.me and CT(P.ash2, "  " .. L["(you)"]) or ""))
        row.cnt:SetText(en.runs and MS.Plural(en.runs, "%d run", "%d runs") or "")
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
        local on = S.tab == key
        line:SetShown(on)
        local c = on and P.ivory or P.ash
        t:SetTextColor(c[1], c[2], c[3])
    end
    b:SetScript("OnEnter", function() if S.tab ~= key then t:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3]) end end)
    b:SetScript("OnLeave", function() b.Refresh() end)
    b:SetScript("OnClick", function()
        if S.tab == key then return end
        S.tab = key; S.selected = nil; S.compareA, S.compareB = nil, nil
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
        GameTooltip:SetText(L["Characters"])
        GameTooltip:AddLine(L["Show stats for all your characters, or one of them."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    cb:HookScript("OnLeave", function() Tint(chev, P.ash); GameTooltip:Hide() end)
    cb:SetScript("OnClick", function() GameTooltip:Hide(); OpenCharMenu(cb) end)
    c.charBtn = cb

    c.lootTab = TabButton(c, L["Loot"], "loot")
    c.dunTab = TabButton(c, L["Dungeons"], "dungeons")
    if MS.Flavor.mythicPlus then
        c.keysTab = TabButton(c, L["Keys"], "keys")
        c.keysTab:SetPoint("RIGHT", c.lootTab, "LEFT", -6, 0)
        c.dunTab:SetPoint("RIGHT", c.keysTab, "LEFT", -6, 0)
    else
        c.dunTab:SetPoint("RIGHT", c.lootTab, "LEFT", -6, 0)
    end
    c.Layout = function()
        c.lootTab:ClearAllPoints()
        if cb:IsShown() then c.lootTab:SetPoint("RIGHT", cb, "LEFT", -18, 0)
        else c.lootTab:SetPoint("RIGHT", c, "RIGHT", 0, 0) end
    end
    c:Hide()
    return c
end

-- What UI_StatsDungeon.lua and UI_StatsLoot.lua share with this file; they
-- add their Build and Fill functions to it.
local K = {
    S = S, X0 = X0, LEFT_W = LEFT_W, RIGHT_X = RIGHT_X, RIGHT_W = RIGHT_W,
    BOSS_COL = BOSS_COL, CHART_H = CHART_H, LIST_ROW = LIST_ROW, MATE_ROW = MATE_ROW,
    RCOLS = RCOLS, LCOLS = LCOLS, LOOT_ROW = LOOT_ROW, MAX_LOOT = MAX_LOOT,
    Band = Band, Cells = Cells, HoverRow = HoverRow, TwoClick = TwoClick, Pool = Pool,
    CharName = CharName, Day = Day, Dur = Dur, Pct = Pct, Result = Result, MakeBossRow = MakeBossRow,
}
UI.StatsKit = K

-- ── Public ─────────────────────────────────────────────────────────────────
function UI.BuildStatsView(sbFrame)
    view = CreateFrame("Frame", nil, sbFrame)
    view:SetPoint("TOPLEFT", sbFrame, "TOPLEFT", 1, -(HDR_H + 1))
    view:SetPoint("BOTTOMRIGHT", sbFrame, "BOTTOMRIGHT", -1, 1)
    local top = Solid(view, "BORDER", 0, P.line[1], P.line[2], P.line[3], 1)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    overview = BuildOverview(view)
    detail = K.BuildDetail(view)
    lootView = K.BuildLoot(view)
    compareView = K.BuildCompare(view)
    if K.BuildKeys and MS.Flavor.mythicPlus then keysView = K.BuildKeys(view) end
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
    local sig = #runs .. "|" .. MS:StatsRevision() .. "|" .. tostring(S.selected) .. "|" .. S.tab .. "|" .. who .. "|" .. #chars
        .. "|" .. tostring(S.compareA) .. "|" .. tostring(S.compareB)
    if sig == drawnSig and not force then return end
    if overview and overview.reset then overview.reset.Disarm() end
    drawnSig = sig
    S.multiChar = #chars > 1
    local stats = MS:StatsOverview()

    -- Header controls
    controls:Show()
    controls.charBtn:SetShown(S.multiChar)
    UI.SetNameText(controls.charBtn.text, who == "all" and L["All characters"] or CharName(who))
    local items = MS:LootHistory()
    controls.lootTab.SetLabel(#items > 0 and (L["Loot"] .. "  " .. CT(P.ash2, #items)) or L["Loot"])
    controls.dunTab.Refresh(); controls.lootTab.Refresh()
    if controls.keysTab then controls.keysTab.Refresh() end
    controls.Layout()
    -- Only the character you're on can reset its own stats.
    overview.reset:SetShown(who == "all" or who == MS:CharKey())
    local f = UI.frame
    f.DungeonName:SetText(L["Your stats"])
    f.SetBadge(nil)
    f.PBLabel:Hide()
    if f.WholeRunBtn then f.WholeRunBtn:Hide() end
    if f.AbandonBtn then f.AbandonBtn:Hide() end
    f.LayoutAffixIcons(0)
    local parts = {
        MS.Plural(stats.runs, "%d run", "%d runs", CT(P.ivory, stats.runs)),
        _fmt(L["%s cleared"], CT(P.ivory, stats.cleared)),
        _fmt(L["%s in dungeons"], CT(P.ivory, Hours(stats.time))),
        _fmt(L["%s deaths a run"], CT(P.ivory, _fmt("%.1f", stats.deathsPerRun))),
    }
    if MS.Flavor.progressStats and (stats.progRuns or 0) > 0 then
        parts[#parts + 1] = _fmt(L["%s XP"], CT(P.ivory, MS.FormatThousands(stats.xp)))
        parts[#parts + 1] = MS.Plural(stats.kills, "%d kill", "%d kills", CT(P.ivory, MS.FormatThousands(stats.kills)))
        parts[#parts + 1] = MS.Plural(stats.quests, "%d quest", "%d quests", CT(P.ivory, stats.quests))
        parts[#parts + 1] = CT(P.bronzeHi, MS.FormatGold(stats.gold))
    end
    local onKeys = S.tab == "keys" and keysView ~= nil
    local keyStats = onKeys and MS:KeyStats()
    if onKeys then
        -- The Keys tab: keys, how many timed, your rating now.
        parts = {
            MS.Plural(keyStats.keys, "%d key", "%d keys", CT(P.ivory, keyStats.keys)),
            _fmt(L["%s timed"], CT(P.ivory, Pct(keyStats.timed, keyStats.keys))),
        }
        local latest
        for _, list in pairs(keyStats.rating) do
            local last = list[#list]
            if last and (not latest or last.at > latest.at) then latest = last end
        end
        if latest and keyStats.ratingChars == 1 then
            parts[#parts + 1] = _fmt(L["Rating %s"], CT(P.ivory, tostring(_floor(latest.v + 0.5))))
        end
    end
    f.SublineRun = nil
    f.Subline:SetText(table.concat(parts, "      "))

    if S.selected then
        local s = MS:StatsForDungeon(S.selected)
        if #s.runs == 0 then S.selected = nil end
    end
    -- A picked run that's gone (removed, other filter) cancels the comparison.
    local function Listed(e)
        if not (e and S.selected) then return false end
        for _, x in ipairs(MS:StatsForDungeon(S.selected).runs) do if x == e then return true end end
        return false
    end
    if S.compareA and not Listed(S.compareA) then S.compareA, S.compareB = nil, nil end
    if S.compareB and not Listed(S.compareB) then S.compareB = nil end
    local onLoot = S.tab == "loot"
    local onTable = not onLoot and not onKeys
    local comparing = onTable and S.selected ~= nil and S.compareA ~= nil and S.compareB ~= nil
    overview:SetShown(onTable and not S.selected)
    detail:SetShown(onTable and S.selected ~= nil and not comparing)
    compareView:SetShown(comparing)
    lootView:SetShown(onLoot)
    if keysView then keysView:SetShown(onKeys) end
    if onLoot then K.FillLoot(lootView, items)
    elseif onKeys then K.FillKeys(keysView, keyStats)
    elseif comparing then K.FillCompare(compareView, MS:CompareRuns(S.compareA, S.compareB))
    elseif S.selected then K.FillDetail(detail, MS:StatsForDungeon(S.selected), stats)
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
    S.selected = nil
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

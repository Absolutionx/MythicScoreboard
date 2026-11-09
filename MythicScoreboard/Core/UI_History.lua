local _min    = math.min
local _ceil   = math.ceil
local _ins    = table.insert
local _rem    = table.remove

local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local Art, Box, Btn, ClassColor, DiffShort, P, RunResult = UI.Art, UI.Box, UI.Btn, UI.ClassColor, UI.DiffShort, UI.P, UI.RunResult
local Solid, Text, Tint = UI.Solid, UI.Text, UI.Tint

-- Run history dropdown under the header's history button.

-- History dropdown
-- ===========================================================================

-- Built once and reused: rows are filled in each time it opens.
local histDropdown = nil     -- the dropdown while it's open
local drop                   -- the dropdown frame (kept)
local dropRows = {}          -- run rows, made as needed and reused
local clearRow

local function CloseHistDropdown()
    if histDropdown then
        histDropdown = nil
        drop:Hide()
        if clearRow then clearRow.Disarm() end
    end
end

local function DoClearHistory()
    MS:ClearHistory()                       -- History.lua (a run in progress carries on)
    if UI.frame and UI.frame.RefreshHistBtn then UI.frame.RefreshHistBtn() end
    print("|cff00ccff[MythicScoreboard]|r " .. L["History cleared. Your stats still have these runs."])
end

local DROP_ROW_H = 28
local VISIBLE    = 12
local scroll     = 0         -- rows scrolled past at the top
local Fill            -- fills the dropdown (below)

local MAX_W  = 760          -- the dropdown never gets wider than this
local probe                -- measures dungeon names
local CHAR_W = 96           -- the character column, when other characters' runs are shown

local function MakeRow()
    local row = Btn(drop)
    local hov = Solid(row, "BACKGROUND", 1, P.bronze[1], P.bronze[2], P.bronze[3], 0.14)
    hov:SetAllPoints()
    local mark = Solid(row, "ARTWORK", 0, P.bronze[1], P.bronze[2], P.bronze[3], 1)
    mark:SetPoint("TOPLEFT"); mark:SetPoint("BOTTOMLEFT"); mark:SetWidth(2)
    row.hov, row.mark = hov, mark

    row.fIdx = Text(row, "medium", 12, P.ash2, "CENTER")
    row.fIdx:SetPoint("LEFT", 6, 0); row.fIdx:SetWidth(28)
    row.fRes = Text(row, "medium", 13, P.verd, "RIGHT")
    row.fRes:SetPoint("RIGHT", -30, 0); row.fRes:SetWidth(76)
    row.fTime = Text(row, "medium", 13, P.ash, "RIGHT")
    row.fTime:SetPoint("RIGHT", row.fRes, "LEFT", -8, 0); row.fTime:SetWidth(40)
    row.fChar = Text(row, "game", 12, P.ivory, "LEFT")
    row.fChar:SetPoint("RIGHT", row.fTime, "LEFT", -10, 0); row.fChar:SetWidth(CHAR_W)
    row.fLvl = Text(row, "semibold", 13, P.ash, "LEFT")
    row.fLvl:SetWidth(84)
    row.fName = Text(row, "game", 12, P.ivory, "LEFT")
    row.fName:SetPoint("LEFT", row.fLvl, "RIGHT", 4, 0)
    row.fLvl:SetPoint("LEFT", row.fIdx, "RIGHT", 4, 0)

    local delBtn = Btn(row)
    delBtn:SetSize(22, DROP_ROW_H)
    delBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    delBtn:SetFrameLevel(row:GetFrameLevel() + 2)
    local delIcon = Art(delBtn, "Close", "OVERLAY")
    delIcon:SetSize(12, 12); delIcon:SetPoint("CENTER")
    Tint(delIcon, P.ash2)
    row.delBtn = delBtn

    row:SetScript("OnEnter", function() hov:Show() end)
    row:SetScript("OnLeave", function() if not row.selected then hov:Hide() end end)
    delBtn:SetScript("OnEnter", function()
        hov:Show(); Tint(delIcon, P.bloodHi)
        GameTooltip:SetOwner(delBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Delete run"], P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:AddLine(L["Removes this run from history and from your stats."], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    delBtn:SetScript("OnLeave", function()
        Tint(delIcon, P.ash2); if not row.selected then hov:Hide() end
        GameTooltip:Hide()
    end)
    delBtn:SetScript("OnClick", function()
        GameTooltip:Hide()
        local runs = MythicScoreboardDB and MythicScoreboardDB.runs
        local run = row.run
        if runs then
            for i, r in ipairs(runs) do
                if r == run then
                    if MS.RemoveArchivedFor then MS:RemoveArchivedFor(run) end   -- and from stats
                    _rem(runs, i)
                    break
                end
            end
            if MS.displayRun == run then MS.displayRun = nil end
            if MS._lastCommittedRun == run then MS._lastCommittedRun = nil end   -- no late loot for it
        end
        if not runs or #runs == 0 then CloseHistDropdown() else Fill() end
        MS:RefreshOverview()
    end)
    row:SetScript("OnClick", function()
        MS.displayRun = (not row.live) and row.run or nil
        CloseHistDropdown()
        if UI.statsOpen then UI.CloseStats() end
        MS:RefreshOverview()
    end)
    return row
end

local function MakeClearRow()
    -- Clear-all row (two-click confirm)
    local armed, armTimer = false, nil
    local cr = Btn(drop)
    local sep = Solid(cr, "ARTWORK", 0, P.line[1], P.line[2], P.line[3], 1)
    sep:SetPoint("TOPLEFT"); sep:SetPoint("TOPRIGHT"); sep:SetHeight(1)
    local caHov = Solid(cr, "BACKGROUND", 1, P.blood[1], P.blood[2], P.blood[3], 0)
    caHov:SetAllPoints()
    local caTxt = Text(cr, "medium", 13, P.blood, "CENTER")
    caTxt:SetAllPoints(); caTxt:SetText(L["Clear all history"])
    function cr.Disarm()
        armed = false
        if armTimer then armTimer:Cancel(); armTimer = nil end
        caTxt:SetText(L["Clear all history"])
        caHov:SetColorTexture(P.blood[1], P.blood[2], P.blood[3], 0)
    end
    cr:SetScript("OnEnter", function()
        caHov:SetColorTexture(P.blood[1], P.blood[2], P.blood[3], armed and 0.35 or 0.15)
    end)
    cr:SetScript("OnLeave", function()
        if not armed then caHov:SetColorTexture(P.blood[1], P.blood[2], P.blood[3], 0) end
    end)
    cr:SetScript("OnClick", function()
        if armed then
            cr.Disarm(); CloseHistDropdown(); DoClearHistory()
        else
            armed = true
            caTxt:SetText(L["Click again: history only, stats are kept"])
            caHov:SetColorTexture(P.blood[1], P.blood[2], P.blood[3], 0.35)
            armTimer = C_Timer.NewTimer(3, cr.Disarm)
        end
    end)
    return cr
end

local function Colour(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- The live run (if any) sits on top as "Now", so you can get back to it
-- after looking at a saved run. It can't be deleted from here, and nor can
-- another character's run (only that character can).
local scopeRow

-- "All characters" / "This character", over the list when other characters
-- have runs.
local function MakeScopeRow()
    local sr = CreateFrame("Frame", nil, drop)
    local sep = Solid(sr, "ARTWORK", 0, P.line[1], P.line[2], P.line[3], 1)
    sep:SetPoint("BOTTOMLEFT"); sep:SetPoint("BOTTOMRIGHT"); sep:SetHeight(1)
    local function Tab(label, scope)
        local b = Btn(sr)
        b.txt = Text(b, "medium", 12, P.ash, "CENTER")
        b.txt:SetPoint("CENTER")
        b.txt:SetText(label)
        b:SetSize(b.txt:GetStringWidth() + 20, 22)
        b.line = Solid(b, "ARTWORK", 1, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 1)
        b.line:SetPoint("BOTTOMLEFT", 6, 0); b.line:SetPoint("BOTTOMRIGHT", -6, 0); b.line:SetHeight(2)
        b:SetScript("OnClick", function()
            MS:SetHistoryScope(scope)
            scroll = 0
            Fill()
        end)
        b.scope = scope
        return b
    end
    sr.all = Tab(L["All characters"], "all")
    sr.me  = Tab(L["This character"], "me")
    sr.all:SetPoint("LEFT", sr, "LEFT", 4, 0)
    sr.me:SetPoint("LEFT", sr.all, "RIGHT", 2, 0)
    function sr.Update()
        local cur = MS:GetHistoryScope()
        for _, b in ipairs({ sr.all, sr.me }) do
            local on = b.scope == cur
            local c = on and P.ivory or P.ash
            b.txt:SetTextColor(c[1], c[2], c[3])
            b.line:SetShown(on)
        end
    end
    return sr
end

function Fill()
    local others = #MS:OtherHistoryChars() > 0
    local showChars = others and MS:GetHistoryScope() == "all"
    local entries = {}
    if MS.currentRun then _ins(entries, { run = MS.currentRun, live = true }) end
    for i, e in ipairs(MS:HistoryEntries((not others) and "me" or nil)) do
        e.idx = i
        _ins(entries, e)
    end

    -- Twelve rows at a time; the mouse wheel scrolls through the rest.
    local visRows = _min(#entries, VISIBLE)
    scroll = math.max(0, math.min(scroll, #entries - visRows))
    -- The level column: as wide as a key and its pips if any key is listed.
    local lvlW = MS.Flavor.difficulties and 40 or 1
    for _, e in ipairs(entries) do
        if (e.run.keystoneLevel or 0) > 0 then lvlW = 84; break end
    end
    -- Wide enough for the longest dungeon name in the list, so none is cut
    -- short (up to MAX_W). Around the name: index and level on the left;
    -- character, time, result and delete on the right (see MakeRow).
    probe = probe or Text(drop, "game", 12, P.ivory, "LEFT")
    probe:Hide()
    local nameW = 0
    for _, e in ipairs(entries) do
        UI.SetNameText(probe, MS:RunTitle(e.run))
        nameW = math.max(nameW, probe:GetStringWidth())
    end
    local around = 8 + 42 + lvlW + (showChars and 268 or 162) + 6
    local dropW = math.max(drop.anchor:GetWidth() + 60, _min(MAX_W, around + _ceil(nameW * 1.08)))   -- (the game draws a little wider than it measures)
    local topH    = others and 28 or 0
    drop:SetSize(dropW, topH + visRows * DROP_ROW_H + DROP_ROW_H + 10)

    if others then
        scopeRow = scopeRow or MakeScopeRow()
        scopeRow:SetSize(dropW - 8, 26)
        scopeRow:ClearAllPoints()
        scopeRow:SetPoint("TOPLEFT", drop, "TOPLEFT", 4, -2)
        scopeRow.Update()
        scopeRow:Show()
    elseif scopeRow then
        scopeRow:Hide()
    end


    local yOff = -4 - topH
    for n = 1, visRows do
        local entry = entries[n + scroll]
        local run, idx = entry.run, entry.idx
        local row = dropRows[n] or MakeRow()
        dropRows[n] = row
        row:Show()
        row:SetSize(dropW - 8, DROP_ROW_H)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", drop, "TOPLEFT", 4, yOff)
        row.run, row.live = run, entry.live
        row.own = entry.live or entry.own

        local selected
        if entry.live then selected = not MS.displayRun
        else
            local newest = MythicScoreboardDB and MythicScoreboardDB.runs and MythicScoreboardDB.runs[1]
            selected = (MS.displayRun == run) or (not MS.displayRun and not MS.currentRun and run == newest)
        end
        row.selected = selected
        row.hov:SetShown(selected); row.mark:SetShown(selected)

        local isMPlus = (run.keystoneLevel or 0) > 0
        local result, rc = RunResult(run)
        Colour(row.fIdx, entry.live and P.bronzeHi or P.ash2)
        row.fIdx:SetText(entry.live and L["Now"] or idx)
        Colour(row.fRes, rc); row.fRes:SetText(result)
        row.fTime:SetText(MS:FormatTime(MS:GetRunDuration(run)))
        Colour(row.fLvl, isMPlus and P.bronzeHi or P.ash)
        -- Keys: level and pips. Elsewhere the difficulty, if this game has them.
        row.fLvl:SetWidth(lvlW)
        if isMPlus then
            local up = MS:RunUpgrades(run)
            row.fLvl:SetText("+" .. run.keystoneLevel .. (up and ("  " .. UI.Pips(up, 11)) or ""))
        else
            row.fLvl:SetText(MS.Flavor.difficulties and DiffShort(run) or "")
        end
        row.fName:SetText(MS:RunTitle(run))
        row.fName:ClearAllPoints()
        row.fName:SetPoint("LEFT", row.fLvl, "RIGHT", 4, 0)
        row.fChar:SetShown(showChars)
        if showChars then
            local who = entry.owner
            local name, class
            if who then name, class = who.name, who.class
            else name = MS:UnitPlayerName("player"); class = select(2, UnitClass("player")) end
            UI.SetNameText(row.fChar, MS.ShortName(name or "") or "")
            local cr, cg, cb = ClassColor(class)
            row.fChar:SetTextColor(cr, cg, cb)
            row.fName:SetPoint("RIGHT", row.fChar, "LEFT", -8, 0)
        else
            row.fName:SetPoint("RIGHT", row.fTime, "LEFT", -8, 0)
        end
        row.delBtn:SetShown(row.own and not entry.live)
        yOff = yOff - DROP_ROW_H
    end
    for n = visRows + 1, #dropRows do dropRows[n]:Hide() end

    clearRow = clearRow or MakeClearRow()
    clearRow.Disarm()
    clearRow:SetSize(dropW - 8, DROP_ROW_H)
    clearRow:ClearAllPoints()
    clearRow:SetPoint("TOPLEFT", drop, "TOPLEFT", 4, yOff - 2)
end

local function OpenHistDropdown(anchorBtn)
    if histDropdown then CloseHistDropdown(); return end
    if #MS:HistoryEntries() == 0 and #((MythicScoreboardDB and MythicScoreboardDB.runs) or {}) == 0
            and #MS:OtherHistoryChars() == 0 then
        print("|cff00ccff[MythicScoreboard]|r " .. L["No saved runs yet."])
        return
    end
    if not drop then
        drop = CreateFrame("Frame", nil, UIParent)
        drop:SetFrameStrata("FULLSCREEN_DIALOG")   -- over the window, under tooltips
        drop:EnableMouse(true)
        Box(drop)
        drop:SetScript("OnHide", function() if histDropdown then CloseHistDropdown() end end)
        drop:EnableMouseWheel(true)
        drop:SetScript("OnMouseWheel", function(_, delta)
            scroll = scroll - delta
            Fill()
        end)
    end
    drop.anchor = anchorBtn
    scroll = 0
    drop:ClearAllPoints()
    drop:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 0, -4)
    Fill()
    drop:Show()
    histDropdown = drop
end

function UI.IsHistOpen() return histDropdown ~= nil end

-- Published for the other UI files.
UI.CloseHistDropdown = CloseHistDropdown
UI.DoClearHistory = DoClearHistory
UI.OpenHistDropdown = OpenHistDropdown

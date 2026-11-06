local _min    = math.min
local _ins    = table.insert
local _rem    = table.remove

local MS = _G["MythicScoreboard"]
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local Art, Box, Btn, DiffShort, P, RunResult = UI.Art, UI.Box, UI.Btn, UI.DiffShort, UI.P, UI.RunResult
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
    if MythicScoreboardDB then MythicScoreboardDB.runs = {} end
    if not MS.inDungeon then MS:SetRunState("none") end
    MS.displayRun = nil
    MS:RefreshOverview()
    if UI.frame and UI.frame.RefreshHistBtn then UI.frame.RefreshHistBtn() end
    print("|cff00ccff[MythicScoreboard]|r History cleared.")
end

local DROP_ROW_H = 28
local Fill            -- fills the dropdown (below)

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
    row.fLvl = Text(row, "semibold", 13, P.ash, "RIGHT")
    row.fLvl:SetPoint("RIGHT", row.fTime, "LEFT", -8, 0); row.fLvl:SetWidth(58)
    row.fName = Text(row, "game", 12, P.ivory, "LEFT")
    row.fName:SetPoint("LEFT", row.fIdx, "RIGHT", 6, 0)
    row.fName:SetPoint("RIGHT", row.fLvl, "LEFT", -6, 0)

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
        GameTooltip:SetText("Delete run", P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:AddLine("Removes this run from history.", 0.8, 0.8, 0.8)
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
            if MS.currentRun == run then MS:SetRunState("none") end
            if MS.displayRun == run then MS.displayRun = nil end
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
    caTxt:SetAllPoints(); caTxt:SetText("Clear all history")
    function cr.Disarm()
        armed = false
        if armTimer then armTimer:Cancel(); armTimer = nil end
        caTxt:SetText("Clear all history")
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
            caTxt:SetText("Click again to delete every saved run")
            caHov:SetColorTexture(P.blood[1], P.blood[2], P.blood[3], 0.35)
            armTimer = C_Timer.NewTimer(3, cr.Disarm)
        end
    end)
    return cr
end

local function Colour(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- The live run (if any) sits on top as "Now", so you can get back to it
-- after looking at a saved run. It can't be deleted from here.
function Fill()
    local runs = (MythicScoreboardDB and MythicScoreboardDB.runs) or {}
    local entries = {}
    if MS.currentRun then _ins(entries, { run = MS.currentRun, live = true }) end
    for i, r in ipairs(runs) do _ins(entries, { run = r, idx = i }) end

    local visRows = _min(#entries, 12)
    local dropW   = drop.anchor:GetWidth() + 60
    drop:SetSize(dropW, visRows * DROP_ROW_H + DROP_ROW_H + 10)

    local yOff = -4
    for n = 1, visRows do
        local entry = entries[n]
        local run, idx = entry.run, entry.idx
        local row = dropRows[n] or MakeRow()
        dropRows[n] = row
        row:Show()
        row:SetSize(dropW - 8, DROP_ROW_H)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", drop, "TOPLEFT", 4, yOff)
        row.run, row.live = run, entry.live

        local selected
        if entry.live then selected = not MS.displayRun
        else selected = (MS.displayRun == run) or (not MS.displayRun and not MS.currentRun and idx == 1) end
        row.selected = selected
        row.hov:SetShown(selected); row.mark:SetShown(selected)

        local isMPlus = (run.keystoneLevel or 0) > 0
        local result, rc = RunResult(run)
        Colour(row.fIdx, entry.live and P.bronzeHi or P.ash2)
        row.fIdx:SetText(entry.live and "Now" or idx)
        Colour(row.fRes, rc); row.fRes:SetText(result)
        row.fTime:SetText(MS:FormatTime(MS:GetRunDuration(run)))
        Colour(row.fLvl, isMPlus and P.bronzeHi or P.ash)
        row.fLvl:SetText(isMPlus and ("+" .. run.keystoneLevel) or DiffShort(run))
        row.fName:SetText(run.dungeonName or "?")
        row.delBtn:SetShown(not entry.live)
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
    local runs = (MythicScoreboardDB and MythicScoreboardDB.runs) or {}
    if #runs == 0 then
        print("|cff00ccff[MythicScoreboard]|r No saved runs yet.")
        return
    end
    if not drop then
        drop = CreateFrame("Frame", nil, UIParent)
        drop:SetFrameStrata("TOOLTIP")
        drop:EnableMouse(true)
        Box(drop)
        drop:SetScript("OnHide", function() if histDropdown then CloseHistDropdown() end end)
    end
    drop.anchor = anchorBtn
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

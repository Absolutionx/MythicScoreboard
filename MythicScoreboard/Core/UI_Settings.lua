local _ins    = table.insert

local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local Art, Box, Btn, Outline, P, Solid = UI.Art, UI.Box, UI.Btn, UI.Outline, UI.P, UI.Solid
local Text, Tint = UI.Text, UI.Tint

-- Settings popup: built once by MS:BuildUI, anchored under the gear button.
function UI.BuildSettingsPopup(sbFrame, settBtn)
    local SETT_W, SROW = 236, 26

    local settPop = CreateFrame("Frame", nil, sbFrame)
    settPop:SetSize(SETT_W, 100)          -- height set once the rows are placed
    settPop:SetFrameStrata("FULLSCREEN_DIALOG")
    settPop:EnableMouse(true)
    settPop:SetPoint("TOPRIGHT", settBtn, "BOTTOMRIGHT", 0, -4)
    Box(settPop)
    settPop:Hide()

    local function MakeToggleRow(yOff, labelText, getFn, setFn, tip)
        local row = Btn(settPop)
        row:SetSize(SETT_W - 8, SROW)
        row:SetPoint("TOPLEFT", settPop, "TOPLEFT", 4, yOff)
        local hov = Solid(row, "BACKGROUND", 0, P.bronze[1], P.bronze[2], P.bronze[3], 0.10)
        hov:SetAllPoints(); hov:Hide()

        local box = CreateFrame("Frame", nil, row)
        box:SetSize(14, 14); box:SetPoint("LEFT", 8, 0)
        local boxFill = Solid(box, "BACKGROUND", 0, 0.05, 0.04, 0.035, 1)
        boxFill:SetAllPoints()
        local boxLine = Outline(box, P.ash2, 1, "BORDER")
        local mark = Art(box, "Check", "OVERLAY")
        mark:SetSize(14, 14); mark:SetPoint("CENTER", 0, 0); Tint(mark, P.bronzeHi)

        local lbl = Text(row, "regular", 14, P.ivory)
        lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
        lbl:SetText(labelText)

        local function Refresh()
            local on = getFn and getFn() or false
            mark:SetShown(on)
            boxLine:SetColor(on and P.bronze or P.ash2, 1)
            if on then
                boxFill:SetColorTexture(P.bronzeDk[1], P.bronzeDk[2], P.bronzeDk[3], 1)
            else
                boxFill:SetColorTexture(0.05, 0.04, 0.035, 1)
            end
            local c = on and P.ivory or P.ash
            lbl:SetTextColor(c[1], c[2], c[3])
        end
        row:SetScript("OnClick", function() setFn(not getFn()); Refresh() end)
        row:SetScript("OnEnter", function()
            hov:Show()
            if tip then
                GameTooltip:SetOwner(row, "ANCHOR_LEFT")
                GameTooltip:SetText(labelText)
                GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() hov:Hide(); GameTooltip:Hide() end)
        return { refresh = Refresh }
    end

    -- On/off settings, top to bottom (getters and setters: Settings.lua).
    local TOGGLES = {
        { L["Reset meter on zone-in"], "AutoResetMeter",
          L["Resets the Blizzard damage meter when you enter a tracked dungeon. Needed for accurate numbers."] },
        -- Enemy forces only exist in Mythic+.
        { L["Forces % on nameplates"], "MobForcesNameplate",
          L["Shows each mob's enemy forces % above its nameplate in Mythic+."], MS.Flavor.mythicPlus },
        { L["Forces % in tooltips"], "MobForcesTooltip",
          L["Adds enemy forces % to the unit tooltip in Mythic+."], MS.Flavor.mythicPlus },
        { L["Open after a run"], "AutoOpenOnComplete",
          L["Opens the scoreboard when you finish a dungeon."] },
        { L["Minimap button"], "MinimapButton",
          L["Left-click opens the scoreboard, right-click your stats. Drag it to move it around the minimap."] },
    }

    local yOff = -6
    local rows = {}
    for _, t in ipairs(TOGGLES) do
        local label, name, tip, shown = t[1], t[2], t[3], t[4]
        if shown ~= false then
            _ins(rows, MakeToggleRow(yOff, label,
                function() return MS["Get" .. name](MS) end,
                function(v) MS["Set" .. name](MS, v) end, tip))
            yOff = yOff - SROW
        end
    end

    -- History limit stepper
    local hl = CreateFrame("Frame", nil, settPop)
    hl:SetSize(SETT_W - 8, SROW); hl:SetPoint("TOPLEFT", settPop, "TOPLEFT", 4, yOff)
    local hlLbl = Text(hl, "regular", 14, P.ivory); hlLbl:SetPoint("LEFT", 8, 0); hlLbl:SetText(L["Runs to keep"])
    local function Step(txt)
        local b = Btn(hl)
        b:SetSize(20, 20); Box(b, true)
        local bars = {}
        local h = Solid(b, "ARTWORK", 0, P.ash[1], P.ash[2], P.ash[3], 1)
        h:SetSize(8, 2); h:SetPoint("CENTER"); bars[1] = h
        if txt == "+" then
            local v = Solid(b, "ARTWORK", 0, P.ash[1], P.ash[2], P.ash[3], 1)
            v:SetSize(2, 8); v:SetPoint("CENTER"); bars[2] = v
        end
        local function Col(c) for _, t in ipairs(bars) do t:SetColorTexture(c[1], c[2], c[3], 1) end end
        b:HookScript("OnEnter", function() Col(P.ivory) end)
        b:HookScript("OnLeave", function() Col(P.ash) end)
        return b
    end
    local hlPlus = Step("+"); hlPlus:SetPoint("RIGHT", -6, 0)
    local hlVal = Text(hl, "semibold", 14, P.ivory, "CENTER"); hlVal:SetWidth(26)
    hlVal:SetPoint("RIGHT", hlPlus, "LEFT", -4, 0)
    local hlMinus = Step("-"); hlMinus:SetPoint("RIGHT", hlVal, "LEFT", -4, 0)
    local function RefreshHL() hlVal:SetText(MS:GetHistoryLimit()) end
    hlMinus:SetScript("OnClick", function() MS:SetHistoryLimit(MS:GetHistoryLimit() - 1); RefreshHL() end)
    hlPlus:SetScript("OnClick", function() MS:SetHistoryLimit(MS:GetHistoryLimit() + 1); RefreshHL() end)
    _ins(rows, { refresh = RefreshHL })
    yOff = yOff - SROW

    -- Difficulty choices (Forever has one difficulty, so none to choose).
    if MS.Flavor.difficulties then
        local sep = Solid(settPop, "ARTWORK", 0, P.line[1], P.line[2], P.line[3], 1)
        sep:SetPoint("TOPLEFT", settPop, "TOPLEFT", 10, yOff - 7)
        sep:SetPoint("TOPRIGHT", settPop, "TOPRIGHT", -10, yOff - 7)
        sep:SetHeight(1)
        yOff = yOff - 14

        local diffHdr = Text(settPop, "medium", 13, P.bronzeHi)
        diffHdr:SetPoint("TOPLEFT", settPop, "TOPLEFT", 12, yOff - 4)
        diffHdr:SetText(L["Track these difficulties"])
        yOff = yOff - 22

        for _, grp in ipairs(MS.DIFF_GROUPS) do
            local key = grp.key
            _ins(rows, MakeToggleRow(yOff, L[grp.label],
                function() return MS:IsDifficultyGroupOn(key) end,
                function(v) MS:SetDifficultyGroupOn(key, v) end))
            yOff = yOff - SROW
        end
    end

    -- When a run counts as cleared (Forever: no Mythic+ completion event).
    if MS.CLEAR_RULES then
        local sep2 = Solid(settPop, "ARTWORK", 0, P.line[1], P.line[2], P.line[3], 1)
        sep2:SetPoint("TOPLEFT", settPop, "TOPLEFT", 10, yOff - 7)
        sep2:SetPoint("TOPRIGHT", settPop, "TOPRIGHT", -10, yOff - 7)
        sep2:SetHeight(1)
        yOff = yOff - 14
        local crHdr = Text(settPop, "medium", 13, P.bronzeHi)
        crHdr:SetPoint("TOPLEFT", settPop, "TOPLEFT", 12, yOff - 4)
        crHdr:SetText(L["Mark a run cleared when"])
        yOff = yOff - 22

        local TIPS = {
            final = L["The run is cleared when the dungeon's final boss dies. If other main bosses are still alive (some dungeons can be done in any order), it waits until they're dead too, or until you leave, so skipped bosses don't cost you the clear."],
            all   = L["The run is cleared once every boss except rare and optional ones is dead."],
            leave = L["Runs are never marked cleared or abandoned; each is saved as finished when you leave."],
        }
        for _, rule in ipairs(MS.CLEAR_RULES) do
            local key = rule.key
            local row = Btn(settPop)
            local rowH = rule.note and SROW + 12 or SROW
            row:SetSize(SETT_W - 8, rowH)
            row:SetPoint("TOPLEFT", settPop, "TOPLEFT", 4, yOff)
            local hov = Solid(row, "BACKGROUND", 0, P.bronze[1], P.bronze[2], P.bronze[3], 0.10)
            hov:SetAllPoints(); hov:Hide()
            local ring = Art(row, "Ring", "ARTWORK", 0)
            ring:SetSize(15, 15); ring:SetPoint("LEFT", 8, 0)
            local dot = Art(row, "Disc", "ARTWORK", 1)
            dot:SetSize(7, 7); dot:SetPoint("CENTER", ring); Tint(dot, P.bronzeHi)
            local lbl = Text(row, "regular", 14, P.ivory)
            lbl:SetPoint("LEFT", ring, "RIGHT", 8, 0)
            lbl:SetText(L[rule.label])
            local note
            if rule.note then
                -- Two lines: the name, and a short note under it.
                ring:ClearAllPoints(); ring:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -(SROW - 15) / 2)
                lbl:ClearAllPoints(); lbl:SetPoint("LEFT", ring, "RIGHT", 8, 0)
                note = Text(row, "regular", 11, P.ash)
                note:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
                note:SetText(L[rule.note])
            end
            local function Refresh()
                local on = MS:GetClearRule() == key
                dot:SetShown(on)
                Tint(ring, on and P.bronze or P.ash2)
                local c = on and P.ivory or P.ash
                lbl:SetTextColor(c[1], c[2], c[3])
            end
            row:SetScript("OnClick", function()
                MS:SetClearRule(key)
                settPop.Refresh()
            end)
            row:SetScript("OnEnter", function()
                hov:Show()
                GameTooltip:SetOwner(row, "ANCHOR_LEFT")
                GameTooltip:SetText(L[rule.label])
                GameTooltip:AddLine(TIPS[key], 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() hov:Hide(); GameTooltip:Hide() end)
            _ins(rows, { refresh = Refresh })
            yOff = yOff - rowH
        end
    end
    settPop:SetHeight(-yOff + 10)

    settPop.Refresh = function() for _, r in ipairs(rows) do r.refresh() end end
    settPop:SetScript("OnShow", function() settPop.Refresh() end)
    return settPop
end

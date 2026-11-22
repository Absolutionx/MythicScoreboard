local _ins    = table.insert

local MS = _G["MythicScoreboard"]
local L = MS.L
local LK = MS.LK      -- a label kept in English, translated where it is shown
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local Art, Box, Btn, Outline, P, Solid = UI.Art, UI.Box, UI.Btn, UI.Outline, UI.P, UI.Solid
local Text, Tint = UI.Text, UI.Tint

-- The check boxes and choices: a plain dark box with a light mark, no colour.
local BOX_FILL = { 0.035, 0.03, 0.026 }
local BOX_LINE = { 0.33, 0.30, 0.27 }
local BOX_LINE_HOVER = { 0.55, 0.51, 0.46 }
local MARK = { 0.90, 0.87, 0.80 }

-- Two columns of groups: the window, a run, history, and on WoW Forever
-- the directions and the blacklist.
local COL_W, SROW, GAP = 264, 26, 10      -- a column's width, a row's height, between groups
local SETT_W = COL_W                      -- (a row's width, in its column)

-- An on/off row with a check box.
local function MakeToggleRow(settPop, yOff, labelText, getFn, setFn, tip)
    local row = Btn(settPop)
    row:SetSize(SETT_W - 8, SROW)
    row:SetPoint("TOPLEFT", settPop, "TOPLEFT", (settPop.colX or 0) + 4, yOff)
    local hov = Solid(row, "BACKGROUND", 0, 1, 0.94, 0.86, 0.05)
    hov:SetAllPoints(); hov:Hide()

    local box = CreateFrame("Frame", nil, row)
    box:SetSize(14, 14); box:SetPoint("LEFT", 8, 0)
    local boxFill = Solid(box, "BACKGROUND", 0, BOX_FILL[1], BOX_FILL[2], BOX_FILL[3], 1)
    boxFill:SetAllPoints()
    local boxLine = Outline(box, BOX_LINE, 1, "BORDER")
    local mark = Art(box, "Check", "OVERLAY")
    mark:SetSize(12, 12); mark:SetPoint("CENTER", 0, 0); Tint(mark, MARK)

    local lbl = Text(row, "regular", 14, P.ivory)
    lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
    lbl:SetText(labelText)

    local function Refresh()
        local on = getFn and getFn() or false
        mark:SetShown(on)
        local c = on and P.ivory or P.ash
        lbl:SetTextColor(c[1], c[2], c[3])
    end
    row:SetScript("OnClick", function() setFn(not getFn()); Refresh() end)
    row:SetScript("OnEnter", function()
        hov:Show()
        boxLine:SetColor(BOX_LINE_HOVER, 1)
        if tip then
            GameTooltip:SetOwner(row, "ANCHOR_LEFT")
            GameTooltip:SetText(labelText)
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() hov:Hide(); boxLine:SetColor(BOX_LINE, 1); GameTooltip:Hide() end)
    return Refresh
end

-- An on/off setting: { label, name (Get/Set<name> in Settings.lua), tip,
-- shown (false leaves it out on this client) }.
local function T(label, name, tip, shown) return { kind = "toggle", label, name, tip, shown } end

-- The groups, column by column. (Each group's rows top to bottom.)
local GROUPS = {
    { col = 1, title = LK("Window"), rows = {
        T(LK("Lock the window"), "WindowLocked",
          LK("Stops the scoreboard being moved or resized, and hides its resize corner.")),
        { kind = "scale" },
        { kind = "resetScale" },
        T(LK("Open after a run"), "AutoOpenOnComplete", LK("Opens the scoreboard when you finish a dungeon.")),
        T(LK("Minimap button"), "MinimapButton",
          LK("Left-click opens the scoreboard, right-click your stats. Drag it to move it around the minimap.")),
    } },
    { col = 1, title = LK("During a run"), rows = {
        T(LK("In-run frame"), "CompactFrame",
          LK("A small frame with the clock, bosses and deaths while you're in a run. Right-click it to change its style; drag it to move it.")),
        { kind = "preview" },
        T(LK("Start the clock on the first pull"), "StartOnPull",
          LK("A dungeon's clock waits until you or your group get into combat, so waiting for the group doesn't count. Keystones keep the game's timer.")),
        T(LK("Warn about the instance limit"), "InstanceLimitWarn",
          LK("A warning when you're down to your last run of a dungeon this hour, and a chat line when it opens again."),
          MS.InstanceLimit ~= nil),           -- WoW Forever only (InstanceLimit.lua)
        { kind = "limitPreview" },
        T(LK("Reset meter on zone-in"), "AutoResetMeter",
          LK("Resets the Blizzard damage meter when you enter a tracked dungeon. Needed for accurate numbers.")),
        -- Enemy forces only exist in Mythic+.
        T(LK("Forces % on nameplates"), "MobForcesNameplate",
          LK("Shows each mob's enemy forces % above its nameplate in Mythic+."), MS.Flavor.mythicPlus),
        T(LK("Forces % in tooltips"), "MobForcesTooltip",
          LK("Adds enemy forces % to the unit tooltip in Mythic+."), MS.Flavor.mythicPlus),
    } },
    { col = 2, title = LK("Run history"), rows = { { kind = "limit" } } },
    -- Difficulty choices (Forever has one difficulty, so none to choose).
    { col = 2, title = LK("Track these difficulties"), rows = { { kind = "difficulties" } },
      shown = MS.Flavor.difficulties },
    -- When a run counts as cleared (Forever: no Mythic+ completion event).
    { col = 2, title = LK("Mark a run cleared when"), rows = { { kind = "clear" } }, shown = MS.CLEAR_RULES ~= nil },
    -- WoW Forever: the dungeon directions (UI_Navigate.lua) and the blacklist.
    { col = 2, title = LK("Directions"), shown = MS.Flavor.directions, rows = {
        T(LK("Take flights automatically"), "AutoTakeFlights",
          LK("When the directions say to fly, talking to the flight master skips to the flight map and takes that flight. Hold Shift to pick your own.")),
    } },
    { col = 2, title = LK("Blacklist"), shown = MS.Flavor.blacklist == true, rows = {
        T(LK("Warn about blacklisted players"), "BlacklistWarn",
          LK("A warning in chat and on screen when someone on your blacklist is in your group.")),
    } },
}

-- A + or - button for the "Runs to keep" stepper.
local function StepButton(hl, txt)
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

-- A label with - value +: "Runs to keep", "Window size". Returns its refresh.
local function StepperRow(settPop, yOff, label, valueText, step)
    local hl = CreateFrame("Frame", nil, settPop)
    hl:SetSize(SETT_W - 8, SROW); hl:SetPoint("TOPLEFT", settPop, "TOPLEFT", (settPop.colX or 0) + 4, yOff)
    local hlLbl = Text(hl, "regular", 14, P.ivory); hlLbl:SetPoint("LEFT", 8, 0); hlLbl:SetText(label)
    local hlPlus = StepButton(hl, "+"); hlPlus:SetPoint("RIGHT", -6, 0)
    local hlVal = Text(hl, "semibold", 14, P.ivory, "CENTER"); hlVal:SetWidth(40)
    hlVal:SetPoint("RIGHT", hlPlus, "LEFT", -4, 0)
    local hlMinus = StepButton(hl, "-"); hlMinus:SetPoint("RIGHT", hlVal, "LEFT", -4, 0)
    local function Refresh() hlVal:SetText(valueText()) end
    hlMinus:SetScript("OnClick", function() step(-1); Refresh() end)
    hlPlus:SetScript("OnClick", function() step(1); Refresh() end)
    return Refresh
end

local function HistoryLimitRow(settPop, yOff)
    return StepperRow(settPop, yOff, L["Runs to keep"], function() return MS:GetHistoryLimit() end,
        function(d) MS:SetHistoryLimit(MS:GetHistoryLimit() + d) end)
end

-- The window's size, 5% a click (from the nearest 5%).
local function ScaleRow(settPop, yOff)
    return StepperRow(settPop, yOff, L["Window size"],
        function() return math.floor(MS:GetWindowScale() * 100 + 0.5) .. "%" end,
        function(d)
            local s = math.floor(MS:GetWindowScale() * 20 + 0.5) / 20 + d * 0.05
            MS:SetWindowScale(s)
        end)
end

-- A button that shows the in-run frame with a sample run, to move and
-- resize it outside a run (and hides it again). Returns its refresh.
local function PreviewRow(settPop, yOff)
    local b = Btn(settPop)
    b:SetSize(COL_W - 24, 22)
    b:SetPoint("TOPLEFT", settPop, "TOPLEFT", (settPop.colX or 0) + 12, yOff - 2)
    Box(b, true)
    local t = Text(b, "medium", 13, P.ivory, "CENTER")
    t:SetAllPoints()
    local function Refresh()
        t:SetText(MS:IsCompactPreviewOn() and L["Hide the preview"] or L["Preview the in-run frame"])
    end
    b:SetScript("OnClick", function() MS:ToggleCompactPreview(); settPop.Refresh() end)
    b:HookScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Preview the in-run frame"])
        GameTooltip:AddLine(L["Shows the in-run frame with a sample run, so you can drag it where you want it and resize it from its corner."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", GameTooltip_Hide)
    return Refresh
end

-- Shows the instance limit (the in-run frame's row and the countdown) with
-- sample numbers, and hides it again. Returns its refresh.
local function LimitPreviewRow(settPop, yOff)
    local b = Btn(settPop)
    b:SetSize(COL_W - 24, 22)
    b:SetPoint("TOPLEFT", settPop, "TOPLEFT", (settPop.colX or 0) + 12, yOff - 2)
    Box(b, true)
    local t = Text(b, "medium", 13, P.ivory, "CENTER")
    t:SetAllPoints()
    local function Refresh()
        t:SetText(MS:IsInstanceLimitPreviewOn() and L["Hide the preview"] or L["Preview the instance limit"])
    end
    b:SetScript("OnClick", function() MS:ToggleInstanceLimitPreview(); settPop.Refresh() end)
    return Refresh
end

-- Puts the scoreboard back to its usual size.
local function ResetScaleRow(settPop, yOff)
    local b = Btn(settPop)
    b:SetSize(COL_W - 24, 22)
    b:SetPoint("TOPLEFT", settPop, "TOPLEFT", (settPop.colX or 0) + 12, yOff - 2)
    Box(b, true)
    local t = Text(b, "medium", 13, P.ivory, "CENTER")
    t:SetAllPoints(); t:SetText(L["Reset size"])
    b:SetScript("OnClick", function() MS:SetWindowScale(1); settPop.Refresh() end)
    settPop.ResetScaleBtn = b                   -- (for tests)
    return function() end      -- (nothing on it changes)
end

-- A group's heading, in its column; returns where its first row goes.
local function Heading(settPop, yOff, title)
    local hdr = Text(settPop, "medium", 12, P.bronzeHi)
    hdr:SetPoint("TOPLEFT", settPop, "TOPLEFT", (settPop.colX or 0) + 12, yOff - 6)
    hdr:SetText(title)
    local rule = Solid(settPop, "ARTWORK", 0, P.line[1], P.line[2], P.line[3], 1)
    rule:SetPoint("LEFT", hdr, "RIGHT", 8, 0)
    rule:SetPoint("RIGHT", settPop, "TOPLEFT", (settPop.colX or 0) + COL_W - 12, 0)
    rule:SetHeight(1)
    return yOff - 24
end

local CLEAR_TIPS = {
    final = LK("The run is cleared when the dungeon's final boss dies. If other main bosses are still alive (some dungeons can be done in any order), it waits until they're dead too, or until you leave, so skipped bosses don't cost you the clear."),
    all   = LK("The run is cleared once every boss except rare and optional ones is dead."),
    leave = LK("Runs are never marked cleared or abandoned; each is saved as finished when you leave."),
}

-- One "Mark a run cleared when" choice (a radio row). Returns its row
-- height and its refresh.
local function ClearRuleRow(settPop, yOff, rule)
    local key = rule.key
    local row = Btn(settPop)
    local rowH = rule.note and SROW + 12 or SROW
    row:SetSize(SETT_W - 8, rowH)
    row:SetPoint("TOPLEFT", settPop, "TOPLEFT", (settPop.colX or 0) + 4, yOff)
    local hov = Solid(row, "BACKGROUND", 0, 1, 0.94, 0.86, 0.05)
    hov:SetAllPoints(); hov:Hide()
    local ring = Art(row, "Ring", "ARTWORK", 0)
    ring:SetSize(15, 15); ring:SetPoint("LEFT", 8, 0)
    local dot = Art(row, "Disc", "ARTWORK", 1)
    dot:SetSize(7, 7); dot:SetPoint("CENTER", ring); Tint(dot, MARK)
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
        Tint(ring, on and BOX_LINE_HOVER or BOX_LINE)
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
        GameTooltip:AddLine(L[CLEAR_TIPS[key]], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() hov:Hide(); GameTooltip:Hide() end)
    return rowH, Refresh
end

-- Settings popup: built once by MS:BuildUI, anchored under the gear button.
function UI.BuildSettingsPopup(sbFrame, settBtn)
    local settPop = CreateFrame("Frame", nil, sbFrame)
    settPop:SetSize(COL_W * 2 + 1, 100)   -- height set once the rows are placed
    settPop:SetFrameStrata("FULLSCREEN_DIALOG")
    settPop:EnableMouse(true)
    settPop:SetPoint("TOPRIGHT", settBtn, "BOTTOMRIGHT", 0, -4)
    Box(settPop)
    settPop:Hide()

    local refreshers, ys = {}, { -8, -8 }
    for _, g in ipairs(GROUPS) do
        if g.shown ~= false then
            settPop.colX = (g.col - 1) * (COL_W + 1)
            local yOff = ys[g.col]
            if yOff < -8 then yOff = yOff - GAP end
            yOff = Heading(settPop, yOff, L[g.title])
            for _, r in ipairs(g.rows) do
                if r.kind == "toggle" and r[4] ~= false then
                    local name = r[2]
                    _ins(refreshers, MakeToggleRow(settPop, yOff, L[r[1]],
                        function() return MS["Get" .. name](MS) end,
                        function(v) MS["Set" .. name](MS, v) end, L[r[3]]))
                    yOff = yOff - SROW
                elseif r.kind == "preview" then
                    _ins(refreshers, PreviewRow(settPop, yOff)); yOff = yOff - SROW - 4
                elseif r.kind == "limitPreview" and MS.ToggleInstanceLimitPreview then
                    _ins(refreshers, LimitPreviewRow(settPop, yOff)); yOff = yOff - SROW - 4
                elseif r.kind == "resetScale" then
                    _ins(refreshers, ResetScaleRow(settPop, yOff)); yOff = yOff - SROW - 4
                elseif r.kind == "scale" then
                    _ins(refreshers, ScaleRow(settPop, yOff)); yOff = yOff - SROW
                elseif r.kind == "limit" then
                    _ins(refreshers, HistoryLimitRow(settPop, yOff)); yOff = yOff - SROW
                elseif r.kind == "difficulties" then
                    for _, grp in ipairs(MS.DIFF_GROUPS) do
                        local key = grp.key
                        _ins(refreshers, MakeToggleRow(settPop, yOff, L[grp.label],
                            function() return MS:IsDifficultyGroupOn(key) end,
                            function(v) MS:SetDifficultyGroupOn(key, v) end))
                        yOff = yOff - SROW
                    end
                elseif r.kind == "clear" then
                    for _, rule in ipairs(MS.CLEAR_RULES) do
                        local rowH, refresh = ClearRuleRow(settPop, yOff, rule)
                        _ins(refreshers, refresh)
                        yOff = yOff - rowH
                    end
                end
            end
            ys[g.col] = yOff
        end
    end
    settPop.colX = nil
    -- A line down the middle.
    local mid = Solid(settPop, "ARTWORK", 0, P.line[1], P.line[2], P.line[3], 0.8)
    mid:SetWidth(1)
    mid:SetPoint("TOP", settPop, "TOPLEFT", COL_W + 0.5, -10)
    mid:SetPoint("BOTTOM", settPop, "BOTTOMLEFT", COL_W + 0.5, 10)
    settPop:SetHeight(-math.min(ys[1], ys[2]) + 10)

    settPop.Refresh = function() for _, refresh in ipairs(refreshers) do refresh() end end
    settPop:SetScript("OnShow", function() settPop.Refresh() end)
    MS:OnSettingChanged("windowScale", function() if settPop:IsShown() then settPop.Refresh() end end)
    return settPop
end

local _ceil   = math.ceil

local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local Art, Box, Btn, BuildTimelineChrome = UI.Art, UI.Box, UI.Btn, UI.BuildTimelineChrome
local COLS, COL_HDR_H = UI.COLS, UI.COL_HDR_H
local CloseHistDropdown, ComputeColumnAnchors, DiffShort = UI.CloseHistDropdown, UI.ComputeColumnAnchors, UI.DiffShort
local FRAME_H, FRAME_W = UI.FRAME_H, UI.FRAME_W
local HDR_H, HGrad, MEDIA, MakeScrollFrame = UI.HDR_H, UI.HGrad, UI.MEDIA, UI.MakeScrollFrame
local OpenHistDropdown, Outline = UI.OpenHistDropdown, UI.Outline
local P, PAD_X, RunResult, SetFont, Solid, TL_H = UI.P, UI.PAD_X, UI.RunResult, UI.SetFont, UI.Solid, UI.TL_H
local Text, Tint, VGrad, colHdrLabels, sortState = UI.Text, UI.Tint, UI.VGrad, UI.colHdrLabels, UI.sortState

-- Main window: chrome, header buttons, layout and slash commands.

local sbFrame, overviewSF = nil, nil

-- ===========================================================================
-- Main frame
-- ===========================================================================

local function IconButton(parent, file, size, hoverCol)
    local b = Btn(parent)
    b:SetSize(size, size)
    Box(b, true)
    local ic = Art(b, file, "ARTWORK")
    ic:SetSize(16, 16); ic:SetPoint("CENTER")
    Tint(ic, P.ash)
    b:HookScript("OnEnter", function() Tint(ic, hoverCol or P.ivory) end)
    b:HookScript("OnLeave", function() Tint(ic, P.ash) end)
    b._icon = ic
    return b
end

-- The window's stone-and-bronze look, for any size of frame (the in-run
-- frame uses it too). washH: how far the warm light from the top reaches.
local function BuildChrome(f, washH)
    -- Border: black hairline outside a dark-bronze hairline.
    local outer = Solid(f, "BACKGROUND", -7, 0, 0, 0, 1); outer:SetAllPoints()
    local inner = Solid(f, "BACKGROUND", -6, P.bronzeDk[1], P.bronzeDk[2], P.bronzeDk[3], 1)
    inner:SetPoint("TOPLEFT", 1, -1); inner:SetPoint("BOTTOMRIGHT", -1, 1)

    -- Stone body with grain.
    local body = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    body:SetPoint("TOPLEFT", 2, -2); body:SetPoint("BOTTOMRIGHT", -2, 2)
    VGrad(body, P.stoneBot, P.stoneTop)
    f._body = body
    local grain = Art(f, "Grain", "BACKGROUND", -4, true)
    grain:SetPoint("TOPLEFT", 2, -2); grain:SetPoint("BOTTOMRIGHT", -2, 2)
    grain:SetBlendMode("ADD")
    grain:SetAlpha(0.5)

    -- Bronze top rule, bright in the middle and fading to the corners.
    local tl = f:CreateTexture(nil, "BORDER", nil, 5)
    tl:SetPoint("TOPLEFT", 2, -2); tl:SetPoint("BOTTOMRIGHT", f, "TOP", 0, -4)
    HGrad(tl, P.bronze, P.bronzeHi, 0, 1)
    local tr = f:CreateTexture(nil, "BORDER", nil, 5)
    tr:SetPoint("TOPRIGHT", -2, -2); tr:SetPoint("BOTTOMLEFT", f, "TOP", 0, -4)
    HGrad(tr, P.bronzeHi, P.bronze, 1, 0)
    -- A faint warm light falling from the top rule.
    local wash = f:CreateTexture(nil, "BACKGROUND", nil, -3)
    wash:SetPoint("TOPLEFT", 2, -4); wash:SetPoint("TOPRIGHT", -2, -4); wash:SetHeight(washH or 70)
    VGrad(wash, P.bronze, P.bronze, 0, 0.05)
end
UI.BuildChrome = BuildChrome

-- ── Size and lock ──────────────────────────────────────────────────────────
-- A window grows and shrinks as a whole (everything keeps its place), from
-- its top-left corner, which stays where it is. posKey: the setting its
-- place is kept in.
function UI.ScaleFrame(f, s, posKey)
    if not (f and s) then return end
    local left, top, old = f:GetLeft(), f:GetTop(), f:GetEffectiveScale()
    f:SetScale(s)
    if left and top and old then
        local new = f:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / new, top * old / new)
        local p, _, rp, x, y = f:GetPoint()
        if p and posKey then MS:SetSetting(posKey, { p, rp, math.floor(x + 0.5), math.floor(y + 0.5) }) end
    end
end

-- The corner to drag to resize a window. o: { get, set (the saved size),
-- min, max, posKey, setting (the size's setting key), shown (when the
-- corner shows), shownBy (settings that change that) }.
function UI.MakeResizeGrip(f, o)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    local art = grip:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    art:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    local lit = grip:CreateTexture(nil, "HIGHLIGHT")
    lit:SetAllPoints()
    lit:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    local dragging
    -- Done dragging: on letting go, or if the corner hides first (the window
    -- closed mid-drag), so it doesn't follow the cursor when it's next shown.
    local function StopDrag(self)
        if not dragging then return end
        dragging = false
        art:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        self:SetScript("OnUpdate", nil)
        o.set(f:GetScale())
    end
    grip:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" and o.shown() then o.set(1); return end      -- back to its usual size
        if button ~= "LeftButton" or not o.shown() then return end
        dragging = true
        art:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        self:SetScript("OnUpdate", function()
            -- The size that puts this corner under the cursor.
            local cx = GetCursorPosition()
            local left, eff = f:GetLeft(), f:GetEffectiveScale()
            local base = UIParent:GetEffectiveScale()
            if not (cx and left and eff and base and base > 0) then return end
            local want = (cx - left * eff) / f:GetWidth()
            local sc = math.max(o.min, math.min(o.max, want / base))
            if math.abs(sc - f:GetScale()) > 0.004 then UI.ScaleFrame(f, sc, o.posKey) end
        end)
    end)
    grip:SetScript("OnMouseUp", StopDrag)
    grip:SetScript("OnHide", StopDrag)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Drag to resize"])
        GameTooltip:AddLine(L["Right-click to reset the size."], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)
    function grip.Update() grip:SetShown(o.shown() and true or false) end
    grip.Update()
    for _, key in ipairs(o.shownBy or {}) do MS:OnSettingChanged(key, grip.Update) end
    MS:OnSettingChanged(o.setting, function(v)
        if not dragging and math.abs((tonumber(v) or 1) - f:GetScale()) > 0.004 then
            UI.ScaleFrame(f, o.get(), o.posKey)
        end
    end)
    return grip
end

function UI.BuildResizeGrip(f)
    f.ResizeGrip = UI.MakeResizeGrip(f, {
        get = function() return MS:GetWindowScale() end,
        set = function(v) MS:SetWindowScale(v) end,
        min = MS.WINDOW_SCALE_MIN, max = MS.WINDOW_SCALE_MAX,
        posKey = "windowPos", setting = "windowScale",
        shown = function() return not MS:GetWindowLocked() end, shownBy = { "windowLocked" },
    })
    return f.ResizeGrip
end

local function BuildWindow()
    sbFrame = CreateFrame("Frame", "MythicScoreboardFrame", UIParent)
    UI.frame = sbFrame
    sbFrame:SetSize(FRAME_W, FRAME_H)
    -- HIGH, as windows are; toplevel so a click brings it to the front. (In
    -- DIALOG, with another addon's DIALOG window in front, frame levels
    -- interleave and parts of this one showed through the other.)
    sbFrame:SetFrameStrata("HIGH")
    sbFrame:SetToplevel(true)
    sbFrame:SetMovable(true); sbFrame:EnableMouse(true)
    sbFrame:RegisterForDrag("LeftButton")
    sbFrame:SetScript("OnDragStart", function(self)
        if not MS:GetWindowLocked() then self:StartMoving() end
    end)
    sbFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Where it was put: kept for next time.
        local p, _, rp, x, y = self:GetPoint()
        if p then MS:SetSetting("windowPos", { p, rp, math.floor(x + 0.5), math.floor(y + 0.5) }) end
    end)
    sbFrame:SetScript("OnMouseDown", function()
        CloseHistDropdown()
        if sbFrame.SettingsPopup then sbFrame.SettingsPopup:Hide() end
    end)
    sbFrame:SetScript("OnShow", function()
        if sbFrame.SetBackdrop then sbFrame:SetBackdrop(nil) end
        MS:WatchItemInfo(true)
    end)
    sbFrame:SetScript("OnHide", function()
        MS:WatchItemInfo(false)
        CloseHistDropdown()
        if sbFrame.SettingsPopup then sbFrame.SettingsPopup:Hide() end
    end)
    sbFrame:SetClampedToScreen(true)             -- (never off the screen, whatever was saved)
    sbFrame:SetScale(MS:GetWindowScale())        -- (its size first: the place is in its own units)
    local pos = MS:GetSetting("windowPos")
    if type(pos) == "table" and pos[1] then
        sbFrame:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
    else
        sbFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    sbFrame:Hide()
    tinsert(UISpecialFrames, "MythicScoreboardFrame")
    UI.BuildResizeGrip(sbFrame)

    BuildChrome(sbFrame)
end

-- Title, difficulty badge, the line under it, and the personal-best label.
local function BuildHeader()
    -- ── Header ──────────────────────────────────────────────────────────
    local hdr = CreateFrame("Frame", nil, sbFrame)
    hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1)
    hdr:SetHeight(HDR_H)

    local title = Text(hdr, "title", 24, P.ivory)
    title:SetPoint("TOPLEFT", hdr, "TOPLEFT", PAD_X, -17)
    title:SetShadowOffset(0, -2); title:SetShadowColor(0, 0, 0, 1)
    sbFrame.DungeonName = title

    -- Difficulty badge: filled bronze for keystones, outlined otherwise.
    local badge = CreateFrame("Frame", nil, hdr)
    badge:SetHeight(20)
    badge:SetPoint("LEFT", title, "RIGHT", 12, 1)
    local badgeFill = badge:CreateTexture(nil, "BACKGROUND")
    badgeFill:SetAllPoints()
    local badgeLine = Outline(badge, P.bronze, 0.8, "BORDER")
    local badgeTxt = Text(badge, "semibold", 15, P.dark, "CENTER")
    badgeTxt:SetPoint("CENTER", 0, 0)
    sbFrame.SetBadge = function(text, filled)
        if not text then badge:Hide(); return end
        badge:Show()
        badgeTxt:SetText(text)
        if filled then
            VGrad(badgeFill, {0.66, 0.45, 0.23}, {0.93, 0.76, 0.52})
            badgeFill:Show(); badgeLine:SetShown(false)
            SetFont(badgeTxt, "semibold", 15)
            badgeTxt:SetTextColor(P.dark[1], P.dark[2], P.dark[3])
        else
            badgeFill:Hide(); badgeLine:SetShown(true)
            SetFont(badgeTxt, "medium", 13)
            badgeTxt:SetTextColor(P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        end
        badge:SetWidth(_ceil(badgeTxt:GetStringWidth()) + 16)
    end

    local subline = Text(hdr, "regular", 14, P.ash)
    subline:SetPoint("TOPLEFT", hdr, "TOPLEFT", PAD_X + 1, -55)
    sbFrame.Subline = subline

    -- Forever: hovering the line lists what the run did for you.
    if MS.Flavor.progressStats then
        local hov = CreateFrame("Frame", nil, hdr)
        hov:SetAllPoints(subline)
        hov:EnableMouse(true)
        hov:SetScript("OnEnter", function(owner)
            local run = sbFrame.SublineRun
            if not (run and run.progress) then return end
            GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT", 12, 12)
            GameTooltip:SetText(L["This run"], P.ivory[1], P.ivory[2], P.ivory[3])
            UI.AddProgressLines(run.progress)
            GameTooltip:Show()
        end)
        hov:SetScript("OnLeave", GameTooltip_Hide)
    end

    local pbLabel = Text(hdr, "medium", 13, P.bronzeHi, "RIGHT")
    pbLabel:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -16, -58)
    pbLabel:SetText(L["New personal best"])
    pbLabel:Hide()
    sbFrame.PBLabel = pbLabel
    return hdr, subline
end

-- Affix icons sit at the end of the subline.
local function BuildAffixIcons(hdr, subline)
    local AFFIX = 18
    local affixIcons = {}
    for i = 1, 4 do
        local fr = CreateFrame("Frame", nil, hdr)
        fr:SetSize(AFFIX, AFFIX)
        fr:Hide()
        fr:EnableMouse(true)
        local portrait = fr:CreateTexture(nil, "ARTWORK")
        portrait:SetSize(AFFIX - 2, AFFIX - 2)
        portrait:SetPoint("CENTER")
        local mask = fr:CreateMaskTexture()
        mask:SetTexture(MEDIA .. "CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(portrait)
        portrait:AddMaskTexture(mask)
        fr.Portrait = portrait
        local ring = Art(fr, "Ring", "OVERLAY")
        ring:SetAllPoints(); Tint(ring, P.bronze)
        fr.Border = ring
        if ScenarioChallengeModeAffixMixin then
            fr.SetUp = function(self2, affixID)
                ScenarioChallengeModeAffixMixin.SetUp(self2, affixID)
                self2.Border:SetTexture(MEDIA .. "Ring")   -- keep our ring over Blizzard's atlas
                Tint(self2.Border, P.bronze)
                self2.Border:SetAllPoints()
            end
            fr:SetScript("OnEnter", ScenarioChallengeModeAffixMixin.OnEnter)
        else
            fr.SetUp = function(self2, affixID)
                self2.affixID = affixID
                if C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
                    local _, _, fileID = C_ChallengeMode.GetAffixInfo(affixID)
                    if fileID then self2.Portrait:SetTexture(fileID) end
                end
            end
        end
        fr:SetScript("OnLeave", GameTooltip_Hide)
        affixIcons[i] = fr
    end
    sbFrame.AffixIcons = affixIcons
    sbFrame.LayoutAffixIcons = function(count)
        for i = 1, 4 do
            local fr = affixIcons[i]
            fr:ClearAllPoints()
            if i <= count then
                if i == 1 then fr:SetPoint("LEFT", subline, "RIGHT", 16, 0)
                else fr:SetPoint("LEFT", affixIcons[i - 1], "RIGHT", 5, 0) end
                fr:Show()
            else
                fr:Hide()
            end
        end
    end
end

-- Close and settings, at the top right.
local function BuildCloseAndSettings(hdr)
    local closeBtn = IconButton(hdr, "Close", 30, P.bloodHi)
    closeBtn:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -16, -17)
    closeBtn:SetScript("OnClick", function() CloseHistDropdown(); sbFrame:Hide() end)
    -- HookScript, not SetScript: IconButton's hover glow lives in these handlers.
    closeBtn:HookScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM"); GameTooltip:SetText(L["Close"]); GameTooltip:Show()
    end)
    closeBtn:HookScript("OnLeave", GameTooltip_Hide)
    sbFrame.CloseButton = closeBtn

    local settBtn = IconButton(hdr, "Gear", 30)
    settBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    settBtn:SetScript("OnClick", function()
        CloseHistDropdown()
        local pop = sbFrame.SettingsPopup
        if pop:IsShown() then pop:Hide() else pop:Show() end
        GameTooltip:Hide()
    end)
    settBtn:HookScript("OnEnter", function(b)
        if UI.IsHistOpen() or sbFrame.SettingsPopup:IsShown() then return end
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM"); GameTooltip:SetText(L["Settings"]); GameTooltip:Show()
    end)
    settBtn:HookScript("OnLeave", GameTooltip_Hide)
    sbFrame.SettingsBtn = settBtn

    -- WoW Forever: the blacklist (UI_Blacklist.lua).
    local left = settBtn
    if MS.ToggleBlacklist then
        local blBtn = IconButton(hdr, "Skull", 30, P.bloodHi)
        blBtn:SetPoint("RIGHT", settBtn, "LEFT", -8, 0)
        blBtn:SetScript("OnClick", function()
            CloseHistDropdown()
            if sbFrame.SettingsPopup then sbFrame.SettingsPopup:Hide() end
            GameTooltip:Hide()
            MS:ToggleBlacklist()
        end)
        blBtn:HookScript("OnEnter", function(b)
            GameTooltip:SetOwner(b, "ANCHOR_BOTTOM"); GameTooltip:SetText(L["Blacklist"])
            GameTooltip:AddLine(MS.Plural(#MS:BlacklistEntries(), "%d player", "%d players"), 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        blBtn:HookScript("OnLeave", GameTooltip_Hide)
        sbFrame.BlacklistBtn = blBtn
        left = blBtn
    end
    return settBtn, left
end

-- The run picker: which run the window shows (opens the history list).
local function BuildHistoryButton(hdr, settBtn)
    local histBtn = Btn(hdr)
    histBtn:SetSize(300, 30)
    histBtn:SetPoint("RIGHT", settBtn, "LEFT", -8, 0)
    Box(histBtn, true)

    local chev = Art(histBtn, "Chevron", "ARTWORK")
    chev:SetSize(14, 14); chev:SetPoint("RIGHT", -6, 0); Tint(chev, P.ash)
    -- Tight: the dungeon's name gets every pixel the rest doesn't need.
    local hbIndex = Text(histBtn, "medium", 12, P.ash2, "LEFT")
    hbIndex:SetPoint("LEFT", 10, 0)                        -- as wide as its text
    local hbResult = Text(histBtn, "medium", 13, P.verd, "RIGHT")
    hbResult:SetPoint("RIGHT", chev, "LEFT", -4, 0)
    local hbTime = Text(histBtn, "medium", 13, P.ash, "RIGHT")
    hbTime:SetPoint("RIGHT", hbResult, "LEFT", -6, 0)
    local hbLevel = Text(histBtn, "semibold", 13, P.bronzeHi, "RIGHT")
    hbLevel:SetPoint("RIGHT", hbTime, "LEFT", -6, 0)
    local hbDungeon = Text(histBtn, "game", 12, P.ivory, "LEFT")
    hbDungeon:SetPoint("LEFT", hbIndex, "RIGHT", 7, 0)
    hbDungeon:SetPoint("RIGHT", hbLevel, "LEFT", -6, 0)
    local hbEmpty = Text(histBtn, "medium", 13, P.ash, "LEFT")
    hbEmpty:SetPoint("LEFT", 12, 0)
    hbEmpty:SetText(L["No saved runs yet"])

    local function RefreshHistBtn()
        local runs = MythicScoreboardDB and MythicScoreboardDB.runs
        local r, idx = MS.displayRun, 1
        if r then
            idx = MS:HistoryIndexOf(r) or 1
        elseif MS.currentRun then
            r, idx = MS.currentRun, L["Now"]            -- the live run
        else
            r = runs and runs[1]
        end
        local has = r ~= nil
        hbEmpty:SetShown(not has)
        for _, fs in ipairs({ hbIndex, hbDungeon, hbLevel, hbTime, hbResult }) do fs:SetShown(has) end
        if not has then return end
        local isMPlus = (r.keystoneLevel or 0) > 0
        -- Cleared before each set: a text set while its font file is first
        -- loading can come out blank, and setting the same text again
        -- doesn't redraw it (the index is "1" nearly every time).
        for _, fs in ipairs({ hbIndex, hbDungeon, hbLevel, hbTime, hbResult }) do fs:SetText("") end
        hbIndex:SetText(idx)
        hbDungeon:SetText(MS:RunTitle(r))
        -- A dungeon's level range is already under the title ("Levels
        -- 26-33"): left out here, so the name has the room.
        local showLevel = isMPlus or not MS.Flavor.dungeonLevels
        hbLevel:SetText(showLevel and (isMPlus and ("+" .. r.keystoneLevel) or DiffShort(r)) or "")
        hbLevel:SetShown(showLevel)
        hbDungeon:SetPoint("RIGHT", showLevel and hbLevel or hbTime, "LEFT", -6, 0)
        local lc = isMPlus and P.bronzeHi or P.ash
        hbLevel:SetTextColor(lc[1], lc[2], lc[3])
        hbTime:SetText(MS:FormatTime(MS:GetRunDuration(r)))
        local res, rc = RunResult(r)
        hbResult:SetText(res); hbResult:SetTextColor(rc[1], rc[2], rc[3])
    end
    sbFrame.RefreshHistBtn = RefreshHistBtn
    RefreshHistBtn()

    histBtn:HookScript("OnEnter", function()
        Tint(chev, P.ivory)
        local n = #MS:HistoryEntries()
        local menuOpen = UI.IsHistOpen() or (sbFrame.SettingsPopup and sbFrame.SettingsPopup:IsShown())
        if n > 0 and not menuOpen then
            GameTooltip:SetOwner(histBtn, "ANCHOR_BOTTOM")
            GameTooltip:SetText(L["Run history"])
            GameTooltip:AddLine(MS.Plural(n, "Pick one of %d saved run to view.", "Pick one of %d saved runs to view."),
                0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    histBtn:HookScript("OnLeave", function() Tint(chev, P.ash); GameTooltip:Hide() end)
    histBtn:SetScript("OnClick", function()
        GameTooltip:Hide()
        if sbFrame.SettingsPopup then sbFrame.SettingsPopup:Hide() end
        OpenHistDropdown(histBtn)
    end)
    sbFrame.HistoryButton = histBtn
    return histBtn
end

-- The Stats button (UI_Stats.lua): three rising bars.
local function BuildStatsButton(hdr, histBtn)
    local statsBtn = Btn(hdr)
    statsBtn:SetSize(30, 30)
    statsBtn:SetPoint("RIGHT", histBtn, "LEFT", -8, 0)
    Box(statsBtn, true)
    local statBars = {}
    for i, h in ipairs({ 6, 10, 14 }) do
        local bar = Solid(statsBtn, "ARTWORK", 0, 1, 1, 1, 1)
        bar:SetSize(3, h)
        bar:SetPoint("BOTTOMLEFT", statsBtn, "CENTER", -7 + (i - 1) * 5, -7)
        statBars[i] = bar
    end
    local function TintBars(c) for _, bar in ipairs(statBars) do bar:SetColorTexture(c[1], c[2], c[3], 1) end end
    TintBars(P.ash)
    statsBtn.SetActive = function(on)
        statsBtn._active = on
        TintBars(on and P.bronzeHi or P.ash)
    end
    statsBtn:HookScript("OnEnter", function(b)
        if not b._active then TintBars(P.ivory) end
        if UI.IsHistOpen() or sbFrame.SettingsPopup:IsShown() then return end
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText(b._active and L["Back to the scoreboard"] or L["Your stats"])
        GameTooltip:Show()
    end)
    statsBtn:HookScript("OnLeave", function(b)
        TintBars(b._active and P.bronzeHi or P.ash)
        GameTooltip:Hide()
    end)
    statsBtn:SetScript("OnClick", function()
        GameTooltip:Hide()
        CloseHistDropdown()
        UI.ToggleStats()
    end)
    sbFrame.StatsBtn = statsBtn
end

-- The column headers: click to sort, again to reverse, a third time to reset.
local function BuildColumnHeader()
    local colHdr = CreateFrame("Frame", nil, sbFrame)
    colHdr:SetPoint("TOPLEFT",  sbFrame, "TOPLEFT",  2, -(HDR_H + 1))
    colHdr:SetPoint("TOPRIGHT", sbFrame, "TOPRIGHT", -2, -(HDR_H + 1))
    sbFrame.ColHeader = colHdr
    colHdr:SetHeight(COL_HDR_H)
    local chBg = Solid(colHdr, "BACKGROUND", 0, 0, 0, 0, 0.25); chBg:SetAllPoints()
    local chTop = Solid(colHdr, "BORDER", 0, P.line[1], P.line[2], P.line[3], 1)
    chTop:SetPoint("TOPLEFT"); chTop:SetPoint("TOPRIGHT"); chTop:SetHeight(1)
    local chBot = Solid(colHdr, "BORDER", 0, P.line[1], P.line[2], P.line[3], 1)
    chBot:SetPoint("BOTTOMLEFT"); chBot:SetPoint("BOTTOMRIGHT"); chBot:SetHeight(1)

    local function RefreshHeaderLabels()
        for _, c in ipairs(COLS) do
            local h = colHdrLabels[c.key]
            local active = (sortState.key == c.key)
            local col = (active or c.key == "dps") and P.ivory or P.ash
            h.label:SetTextColor(col[1], col[2], col[3])
            h.arrow:SetShown(active)
            if active then
                h.arrow:SetRotation(sortState.dir == 1 and 0 or math.pi)
            end
        end
    end

    -- A header cell for every column there can be; placed (and the ones not
    -- shown hidden) by LayoutHeader, again whenever the columns change.
    local cells = {}
    local function LayoutHeader()
        ComputeColumnAnchors()
        local shown = {}
        for _, col in ipairs(COLS) do shown[col.key] = col end
        for key, cell in pairs(cells) do
            local col = shown[key]
            cell:SetShown(col ~= nil)
            if col then
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", colHdr, "LEFT", col.x, 0)
                cell:SetSize(col.w, COL_HDR_H)
            end
        end
    end
    for _, col in ipairs(UI.ALL_COLS) do
        local cell = Btn(colHdr)
        cells[col.key] = cell
        local hov = Solid(cell, "HIGHLIGHT", 0, 1, 0.94, 0.86, 0.04); hov:SetAllPoints()

        local lbl = Text(cell, "medium", 13, P.ash, col.left and "LEFT" or "CENTER")
        lbl:SetText(L[col.label])
        local arrow = Art(cell, "Chevron", "OVERLAY")
        arrow:SetSize(12, 12); Tint(arrow, P.bronzeHi); arrow:Hide()
        if col.left then
            lbl:SetPoint("LEFT", cell, "LEFT", 0, 0)
            arrow:SetPoint("LEFT", lbl, "RIGHT", 3, 0)
        else
            lbl:SetPoint("CENTER", cell, "CENTER", 0, 0)
            arrow:SetPoint("RIGHT", lbl, "LEFT", -2, 0)
        end
        colHdrLabels[col.key] = { label = lbl, arrow = arrow }

        local key = col.key
        cell:SetScript("OnClick", function()
            if sortState.key == key then
                if sortState.dir == 1 then sortState.dir = -1
                else sortState.key = nil; sortState.dir = 1 end
            else
                sortState.key = key; sortState.dir = 1
            end
            RefreshHeaderLabels()
            MS:RefreshOverview()
        end)
    end
    LayoutHeader()
    UI.OnColumnsChanged(function()
        if sortState.key and not COLS._avoidable and sortState.key == "avoidable" then sortState.key = nil end
        LayoutHeader()
        RefreshHeaderLabels()
    end)
    RefreshHeaderLabels()
end

-- Player rows, the timeline under them, and the Stats page.
local function BuildBody()
    overviewSF = MakeScrollFrame(sbFrame)
    UI.overviewSF = overviewSF
    overviewSF:SetPoint("TOPLEFT",     sbFrame, "TOPLEFT",     1, -(HDR_H + COL_HDR_H + 1))
    overviewSF:SetPoint("BOTTOMRIGHT", sbFrame, "BOTTOMRIGHT", -1, TL_H + 1)
    sbFrame.overviewSF = overviewSF

    local tlc = CreateFrame("Frame", nil, sbFrame)
    tlc:SetPoint("BOTTOMLEFT",  sbFrame, "BOTTOMLEFT",  1, 1)
    tlc:SetPoint("BOTTOMRIGHT", sbFrame, "BOTTOMRIGHT", -1, 1)
    tlc:SetHeight(TL_H)
    BuildTimelineChrome(tlc)
    tlc:Hide()
    sbFrame.timelineContainer = tlc

    UI.BuildStatsView(sbFrame)
end

function MS:BuildUI()
    if sbFrame then return end
    BuildWindow()
    local hdr, subline = BuildHeader()
    BuildAffixIcons(hdr, subline)
    local settBtn, leftmost = BuildCloseAndSettings(hdr)
    local histBtn = BuildHistoryButton(hdr, leftmost)
    BuildStatsButton(hdr, histBtn)
    sbFrame.SettingsPopup = UI.BuildSettingsPopup(sbFrame, settBtn)   -- UI_Settings.lua
    BuildColumnHeader()
    BuildBody()
    MS:SetSBFrameVisibleCallback(function() return sbFrame and sbFrame:IsShown() end)
end



local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
local Art, Box, Btn, P, Solid, Text, Tint = UI.Art, UI.Box, UI.Btn, UI.P, UI.Solid, UI.Text, UI.Tint

-- The blacklist window: everyone on it, with their note and when they were
-- added. Click one to change the note; the cross removes them (click twice).
-- Opened from the settings, or /sb blacklist. The list itself: Blacklist.lua.

local W, H, ROW_H, PAD = 400, 440, 46, 14
local frame, rows = nil, {}

local function CloseButton(parent)
    local b = Btn(parent)
    b:SetSize(26, 26)
    Box(b, true)
    local ic = Art(b, "Close", "ARTWORK")
    ic:SetSize(14, 14); ic:SetPoint("CENTER"); Tint(ic, P.ash)
    b:HookScript("OnEnter", function() Tint(ic, P.bloodHi) end)
    b:HookScript("OnLeave", function() Tint(ic, P.ash) end)
    return b
end

local function TextButton(parent, label)
    local b = Btn(parent)
    Box(b, true)
    local t = Text(b, "medium", 13, P.ivory, "CENTER")
    t:SetAllPoints(); t:SetText(label)
    b:SetSize(t:GetStringWidth() + 28, 26)
    b._text = t
    return b
end

-- "November 14, 2026" (the game's month names, in your language).
local function Added(e)
    if not e.added then return "" end
    local ok, t = pcall(date, "*t", e.added)
    if not (ok and type(t) == "table") then return "" end
    local months = rawget(_G, "CALENDAR_FULLDATE_MONTH_NAMES")
    local month = type(months) == "table" and months[t.month]
    if type(month) ~= "string" then
        local okm, m = pcall(date, "%B", e.added)
        month = okm and m or tostring(t.month)
    end
    return string.format("%s %d, %d", month, t.day, t.year)
end
UI._BlacklistDate = Added

local function MakeRow(parent)
    local row = Btn(parent)
    row:SetHeight(ROW_H)
    local hov = Solid(row, "HIGHLIGHT", 0, 1, 0.94, 0.86, 0.04); hov:SetAllPoints()
    local sep = Solid(row, "ARTWORK", 0, P.line[1], P.line[2], P.line[3], 0.6)
    sep:SetPoint("BOTTOMLEFT"); sep:SetPoint("BOTTOMRIGHT"); sep:SetHeight(1)
    local bar = Solid(row, "BORDER", 0, 1, 0.13, 0.13, 0.9)
    bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT", 0, 1); bar:SetWidth(2)

    row._name = Text(row, "game", 14, { 1, 0.2, 0.2 })
    row._name:SetPoint("TOPLEFT", 12, -7)
    -- The date and the cross: down the middle of the row, on the right.
    row._date = Text(row, "regular", 12, P.ash, "RIGHT")
    row._date:SetWidth(120)
    row._date:SetPoint("RIGHT", -38, 0)
    row._name:SetPoint("RIGHT", row._date, "LEFT", -8, 0)
    row._note = Text(row, "regular", 13, P.ivory)
    row._note:SetPoint("TOPLEFT", 12, -26); row._note:SetPoint("RIGHT", row._date, "LEFT", -8, 0)

    -- Remove: the cross, then once more to be sure.
    local rm = Btn(row)
    rm:SetSize(24, 24); rm:SetPoint("RIGHT", -8, 0)
    local x = Art(rm, "Close", "ARTWORK"); x:SetSize(12, 12); x:SetPoint("CENTER"); Tint(x, P.ash2)
    -- Armed: a small red "Remove?" button where the date was (the date steps
    -- aside until it's clicked or three seconds pass).
    local sureLine = UI.Outline(rm, P.blood, 0.9, "BORDER"); sureLine:SetShown(false)
    local sure = Text(rm, "medium", 12, P.bloodHi, "CENTER")
    sure:SetPoint("CENTER", rm, "CENTER", 0, 0); sure:SetText(L["Remove?"]); sure:Hide()
    local armed, timer
    local function Disarm()
        armed = false
        if timer then timer:Cancel(); timer = nil end
        sure:Hide(); sureLine:SetShown(false); x:Show()
        rm:SetSize(24, 24)
        row._date:Show()
    end
    rm:SetScript("OnEnter", function()
        Tint(x, P.bloodHi)
        GameTooltip:SetOwner(rm, "ANCHOR_RIGHT"); GameTooltip:SetText(L["Remove from blacklist"]); GameTooltip:Show()
    end)
    rm:SetScript("OnLeave", function() Tint(x, P.ash2); GameTooltip:Hide() end)
    rm:SetScript("OnClick", function()
        if armed then
            Disarm()
            MS:RemoveBlacklistKey(row._key)
        else
            armed = true
            x:Hide(); row._date:Hide()
            rm:SetSize(math.ceil(sure:GetStringWidth()) + 16, 22)
            sure:Show(); sureLine:SetShown(true)
            timer = C_Timer.NewTimer(3, Disarm)
        end
    end)
    row.Disarm = Disarm

    row:SetScript("OnClick", function()
        local e = row._entry
        if e then MS:AskBlacklistNote(e.name, nil, e.class) end
    end)
    row:SetScript("OnEnter", function()
        local e = row._entry
        if not e then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.name, 1, 0.2, 0.2)
        if (e.note or "") ~= "" then GameTooltip:AddLine(e.note, 1, 1, 1, true) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to change the note."], 0.55, 0.55, 0.55)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

function UI.RefreshBlacklist()
    if not (frame and frame:IsShown()) then return end
    local entries = MS:BlacklistEntries()
    local content = frame.list.scrollContent
    for i, item in ipairs(entries) do
        local row = rows[i]
        if not row then
            row = MakeRow(content)
            rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", content, "RIGHT", -10, 0)
        row._key, row._entry = item.key, item.entry
        row.Disarm()
        UI.SetNameText(row._name, item.entry.name or "?")
        row._date:SetText(Added(item.entry))
        local note = item.entry.note or ""
        row._note:SetText(note ~= "" and note or ("|cff8c8273" .. L["No note"] .. "|r"))
        row:Show()
    end
    for i = #entries + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, #entries * ROW_H))
    frame.list.UpdateRange()
    frame.empty:SetShown(#entries == 0)
    frame.count:SetText(MS.Plural(#entries, "%d player", "%d players"))
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "MythicScoreboardBlacklistFrame", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    UI.BuildChrome(frame, 50)
    tinsert(UISpecialFrames, "MythicScoreboardBlacklistFrame")

    local title = Text(frame, "title", 18, P.bronzeHi)
    title:SetPoint("TOPLEFT", PAD + 2, -16)
    title:SetText(L["Blacklist"])
    frame.count = Text(frame, "regular", 12, P.ash)
    frame.count:SetPoint("LEFT", title, "RIGHT", 10, -1)

    local close = CloseButton(frame)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() frame:Hide() end)

    local top = -50
    local rule = Solid(frame, "ARTWORK", 0, P.line[1], P.line[2], P.line[3], 1)
    rule:SetPoint("TOPLEFT", PAD, top); rule:SetPoint("TOPRIGHT", -PAD, top); rule:SetHeight(1)

    local list = UI.MakeScrollFrame(frame)
    list:SetPoint("TOPLEFT", PAD, top - 1)
    list:SetPoint("BOTTOMRIGHT", -PAD, 50)
    list.scrollContent:SetWidth(W - 2 * PAD)
    frame.list = list

    frame.empty = Text(frame, "regular", 13, P.ash, "CENTER")
    frame.empty:SetWordWrap(true)
    frame.empty:SetPoint("TOPLEFT", list, "TOPLEFT", 20, -40)
    frame.empty:SetPoint("TOPRIGHT", list, "TOPRIGHT", -20, -40)
    frame.empty:SetText(L["No one yet. Right-click a player in your group, the group finder or the scoreboard and choose Add to blacklist."])

    local add = TextButton(frame, L["Add a player"])
    add:SetPoint("BOTTOMLEFT", PAD, 14)
    add:SetScript("OnClick", function() MS:AskBlacklistName() end)
    local hint = Text(frame, "regular", 11, P.ash, "RIGHT")
    hint:SetPoint("BOTTOMRIGHT", -PAD - 2, 20)
    hint:SetPoint("LEFT", add, "RIGHT", 10, 0)
    hint:SetText(L["Their names show in red in the group finder."])

    frame:SetScript("OnShow", UI.RefreshBlacklist)
    frame:Hide()
    return frame
end

function MS:ShowBlacklist()
    Build()
    if frame:IsShown() then frame:Raise() else frame:Show() end
    UI.RefreshBlacklist()
end

function MS:ToggleBlacklist()
    if frame and frame:IsShown() then frame:Hide() else MS:ShowBlacklist() end
end

MS:OnBlacklistChanged(function() UI.RefreshBlacklist() end)

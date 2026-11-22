local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
local P, Text = UI.P, UI.Text
local _fmt = string.format

-- ── Turned away: a countdown to the next slot ──────────────────────────────
-- From the moment the game turns you away at a dungeon's door (too many new
-- instances this hour; InstanceLimit.lua) until a slot frees: a small panel
-- near the top of the screen with the time left. Drag it where you want it
-- (kept: limitPanelPos); a click closes it until the next time you're
-- turned away.
--
-- The preview (/sb limit test, or the button in settings) shows it with a
-- sample countdown beside the in-run frame's preview, which has the limit's
-- row; turning either off turns both off.

local panel, ticker
local WIDTH, UNTIL_Y = 230, 56            -- the panel's width; where its last line starts
local closedFor                          -- the lock it was closed for
local preview                            -- while previewing: the sample's "next free" time

local function Hide()
    if ticker then ticker:Cancel(); ticker = nil end
    if panel then panel:Hide() end
end

local function Update()
    local info = MS:InstanceLimit()
    local nextFree = preview or (info.locked and info.nextFree)
    if not (nextFree and nextFree > time()) then Hide(); return end
    panel.clock:SetText(MS:FormatTime(nextFree - time()))
    -- (Counted each on its own: the dungeon you were turned away from.)
    local name = info.scope == "dungeon" and (info.dungeon or (preview and "Alcaz Prison"))
    panel.until_:SetText(name and _fmt(L["until you can enter %s again (%s)"], name, MS.ClockTime(nextFree))
        or _fmt(L["until you can enter another dungeon (%s)"], MS.ClockTime(nextFree)))
    -- (A long dungeon name wraps to a second line: the panel grows to fit.)
    local h = panel.until_.GetStringHeight and panel.until_:GetStringHeight()
    panel:SetHeight(UNTIL_Y + math.ceil(tonumber(h) or 13) + 12)
end

local function Build()
    if panel then return panel end
    panel = CreateFrame("Button", "MythicScoreboardInstanceLimit", UIParent)
    panel:SetSize(WIDTH, 84)
    local pos = MS:GetSetting("limitPanelPos")
    if type(pos) == "table" and pos[1] then
        panel:SetPoint(pos[1], UIParent, pos[2], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
    else
        panel:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving(); self._dragged = true end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if p then MS:SetSetting("limitPanelPos", { p, rp, math.floor(x + 0.5), math.floor(y + 0.5) }) end
    end)
    UI.Box(panel)
    local title = Text(panel, "semibold", 11, P.bloodHi, "LEFT")
    title:SetPoint("TOPLEFT", 12, -11); title:SetText(L["Instance limit reached"])
    panel.clock = Text(panel, "semibold", 24, P.ivory, "LEFT")
    panel.clock:SetPoint("TOPLEFT", 12, -26)
    panel.until_ = Text(panel, "regular", 11, P.ash, "LEFT")
    panel.until_:SetPoint("TOPLEFT", 12, -UNTIL_Y); panel.until_:SetWidth(WIDTH - 24)
    panel.until_:SetWordWrap(true)
    if panel.until_.SetMaxLines then panel.until_:SetMaxLines(2) end
    local close = Text(panel, "regular", 10, P.ash, "RIGHT")
    close:SetPoint("TOPRIGHT", -10, -11); close:SetText(L["Click to close."])
    -- (Long translations: the title gives way to "Click to close.")
    title:SetPoint("RIGHT", close, "LEFT", -8, 0)
    panel:SetScript("OnClick", function(self)
        if self._dragged then self._dragged = nil; return end   -- the end of a drag, not a click
        if preview then MS:ToggleInstanceLimitPreview(); return end
        closedFor = MS:InstanceLimit().nextFree
        Hide()
    end)
    panel:Hide()
    return panel
end

-- Shown while you're locked out (and haven't closed it for this lock).
local function Refresh()
    local info = MS:InstanceLimit()
    if not preview and (not info.locked or closedFor == info.nextFree) then Hide(); return end
    Build()
    if not panel:IsShown() then
        panel:Show()
        if ticker then ticker:Cancel() end
        if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, Update) end
    end
    Update()
end

-- ── The preview ────────────────────────────────────────────────────────────
function MS:PreviewInstanceLimitPanel(on)
    preview = on and (time() + 11 * 60 + 58) or nil
    local ok, err = pcall(Refresh)
    if not ok then MS:ReportError("Instance limit", err) end
end

function MS:IsInstanceLimitPreviewOn() return preview ~= nil end

-- Both together: the countdown, and the in-run frame's preview with the row.
-- On or off; returns whether it's on.
function MS:ToggleInstanceLimitPreview()
    local on = not preview
    if on ~= self:IsCompactPreviewOn() then self:ToggleCompactPreview() end
    self:PreviewInstanceLimitPanel(on)
    return on
end

MS:OnChanged(function(what)
    if what ~= "instanceLimit" then return end
    local ok, err = pcall(Refresh)
    if not ok then MS:ReportError("Instance limit", err) end
end)

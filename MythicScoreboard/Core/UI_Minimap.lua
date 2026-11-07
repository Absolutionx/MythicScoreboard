local _rad, _deg, _cos, _sin = math.rad, math.deg, math.cos, math.sin
local _atan2 = math.atan2 or math.atan

local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
local MEDIA = UI.MEDIA

-- Minimap button: left-click opens or closes the scoreboard, right-click the
-- Stats page, drag to move it around the minimap. Turned on and off in
-- settings ("Minimap button"); its place is remembered.

local ICON = "Interface\\AddOns\\MythicScoreboard\\Icons\\Icon"
local DEFAULT_ANGLE = 215
local btn

local function Place()
    local a = _rad(MS:GetMinimapAngle() or DEFAULT_ANGLE)
    local r = Minimap:GetWidth() / 2 + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", _cos(a) * r, _sin(a) * r)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not (mx and cx and scale and scale > 0) then return end
    MS:SetMinimapAngle(_deg(_atan2(cy / scale - my, cx / scale - mx)) % 360)
    Place()
end

local function ScoreboardShown()
    return UI.frame and UI.frame:IsShown()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L["Mythic Scoreboard"])
    local board, stats = ScoreboardShown() and not UI.statsOpen, ScoreboardShown() and UI.statsOpen
    GameTooltip:AddLine(board and L["Left-click: close the scoreboard"] or L["Left-click: open the scoreboard"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(stats and L["Right-click: close your stats"] or L["Right-click: open your stats"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Drag to move. Hide it in settings."], 0.55, 0.55, 0.55)
    GameTooltip:Show()
end

local function Build()
    if btn or not Minimap then return btn end
    btn = CreateFrame("Button", "MythicScoreboardMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(19, 19); icon:SetPoint("TOPLEFT", 6, -6)
    local mask = btn:CreateMaskTexture()
    mask:SetTexture(MEDIA .. "CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")

    btn:SetScript("OnClick", function(self, button)
        GameTooltip:Hide()
        if button == "RightButton" then
            if ScoreboardShown() and UI.statsOpen then UI.frame:Hide()
            else MS:ShowScoreboard(); UI.OpenStats() end
        else
            if ScoreboardShown() and not UI.statsOpen then UI.frame:Hide()
            else
                MS:ShowScoreboard()
                if UI.statsOpen then UI.CloseStats() end
            end
        end
        if self:IsMouseOver() then ShowTooltip(self) end
    end)
    btn:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", FollowCursor)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnEnter", ShowTooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    Place()
    return btn
end

function MS:UpdateMinimapButton()
    if self:GetMinimapButton() then
        if Build() then btn:Show(); Place() end
    elseif btn then
        btn:Hide()
    end
end

-- Turned on or off in settings (Settings.lua).
MS:OnSettingChanged("minimapButton", function() MS:UpdateMinimapButton() end)

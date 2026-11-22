local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
local Art, Box, Btn, P, Solid, Text, Tint = UI.Art, UI.Box, UI.Btn, UI.P, UI.Solid, UI.Text, UI.Tint

-- ── A search box on the world map (WoW Forever) ───────────────────────────
-- Type a dungeon or a zone: what fits drops down under the box (MS:MapSearch,
-- Core/MapSearch.lua). Pick one (Enter or a click) and the map opens there:
-- a zone's map, or a dungeon's zone with its entrance marker pulsing. The
-- arrow at the end of a row (or Shift-Enter) shows the way there straight
-- away. Up and Down (or Tab) move through the list; Escape clears it.
-- Alt-click anywhere on the map: the way to that spot (on the route's line
-- or a dot of it: the directions off).


local BOX_W, BOX_H, ROW_H, ROWS = 230, 24, 22, 8
local box, list, rows, results, sel = nil, nil, {}, {}, 1
local pulse

-- ── Showing what was picked ────────────────────────────────────────────────
local function Map() return rawget(_G, "WorldMapFrame") end

-- The entrance marker for a dungeon on the map now open, or nil.
local function PinFor(name)
    local map = Map()
    if not (map and map.EnumeratePinsByTemplate) then return nil end
    local ok, iter, state, first = pcall(map.EnumeratePinsByTemplate, map, "MythicScoreboardEntrancePinTemplate")
    if not ok or not iter then return nil end
    for pin in iter, state, first do
        for _, d in ipairs(pin.pin and pin.pin.dungeons or {}) do
            if d.name == name then return pin end
        end
    end
end

-- A ring that swells and fades three times over the marker.
local PULSE_TIME, PULSES = 0.9, 3
local function Pulse(pin)
    if not pulse then
        pulse = CreateFrame("Frame", nil, UIParent)
        pulse:SetSize(64, 64)
        pulse.ring = Art(pulse, "Ring", "OVERLAY")
        pulse.ring:SetAllPoints()
        pulse.ring:SetBlendMode("ADD")
        Tint(pulse.ring, P.bronzeHi)
        pulse:SetScript("OnUpdate", function(self, dt)
            self.t = self.t + dt
            local owner = self.owner
            if self.t >= PULSE_TIME * PULSES or not (owner and owner:IsVisible()) then
                self:Hide()
                local GT = rawget(_G, "GameTooltip")
                if GT and GT.GetOwner and GT:GetOwner() == owner then GT:Hide() end
                return
            end
            local f = (self.t % PULSE_TIME) / PULSE_TIME
            local s = 0.4 + f * 1.1
            self.ring:SetSize(64 * s, 64 * s)
            self.ring:ClearAllPoints(); self.ring:SetPoint("CENTER")
            self.ring:SetAlpha(1 - f)
        end)
    end
    pulse:SetParent(pin)
    pulse:ClearAllPoints(); pulse:SetPoint("CENTER", pin, "CENTER")
    pulse:SetFrameLevel(pin:GetFrameLevel() + 5)
    pulse.owner, pulse.t = pin, 0
    pulse:Show()
    -- Its tooltip too: the dungeon, its levels and "Click: the way there".
    if pin.OnMouseEnter then pcall(pin.OnMouseEnter, pin) end
end

local function HideList()
    if list then list:Hide() end
end

-- Turning the world map to another zone from here makes the game's own
-- markers set themselves up under this addon's name, and in combat one of
-- them does what only the game may do then (blocked, and blamed on us). So
-- in combat the map turns once the fight's over, if it's still open.
local pendingMap
local function ShowMap(hit, directions)
    local map = Map()
    if not (map and map.SetMapID) then return end
    if InCombatLockdown() then pendingMap = { hit = hit, directions = directions }; return end
    pendingMap = nil
    pcall(map.SetMapID, map, hit.map)
    if hit.kind == "dungeon" and not directions then
        -- The map adds its markers as it opens: look once they're there.
        C_Timer.After(0, function()
            local pin = PinFor(hit.name)
            if pin then Pulse(pin) end
        end)
    end
end
MS:On("PLAYER_REGEN_ENABLED", function()
    local p = pendingMap
    pendingMap = nil
    local map = Map()
    if p and map and map.IsShown and map:IsShown() then ShowMap(p.hit, p.directions) end
end)

local function Choose(hit, directions)
    if not hit then return end
    if directions then
        local dest
        if hit.kind == "dungeon" then
            dest = { name = hit.name, map = hit.map, x = hit.x, y = hit.y }
        else
            dest = MS:ZoneDestination(hit)
        end
        if dest and MS.NavigateTo then
            local ok, err = pcall(MS.NavigateTo, MS, dest)
            if not ok then MS:ReportError("Arrow", err) end
        end
    end
    box:ClearFocus()
    HideList()
    ShowMap(hit, directions)
end

-- ── The list under the box ─────────────────────────────────────────────────
local function Paint()
    for i, row in ipairs(rows) do
        local hit = results[i]
        if hit then
            row.hit = hit
            row.name:SetText(hit.name)
            if hit.kind == "dungeon" then
                row.kind:SetText(hit.lo and string.format(L["Levels %d-%d"], hit.lo, hit.hi) or "")
            else
                row.kind:SetText(L["Zone"])
            end
            row.bg:SetShown(i == sel)
            row:Show()
        else
            row.hit = nil
            row:Hide()
        end
    end
    local n = #results
    local text = box:GetText() or ""
    list.empty:SetShown(n == 0)
    local h = (n > 0 and n or 1) * ROW_H + 8 + list.hint:GetStringHeight() + 10
    list:SetHeight(h)
    list:SetShown(text ~= "")
end

local function Refresh()
    results = MS:MapSearch(box:GetText() or "", ROWS)
    sel = 1
    Paint()
end

local function Move(by)
    if #results == 0 then return end
    sel = ((sel - 1 + by) % #results) + 1
    Paint()
end

local function MakeRow(i)
    local r = Btn(list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * ROW_H)
    r.bg = Solid(r, "BACKGROUND", 3, P.bronze[1], P.bronze[2], P.bronze[3], 0.22)
    r.bg:SetAllPoints()
    r.bg:Hide()
    -- The way there: an arrow at the end of the row.
    local go = Btn(r)
    go:SetSize(20, 20); go:SetPoint("RIGHT", -4, 0)
    local ga = go:CreateTexture(nil, "ARTWORK")
    ga:SetTexture("Interface\\AddOns\\MythicScoreboard\\Media\\Arrow", nil, nil, "TRILINEAR")
    ga:SetSize(14, 14); ga:SetPoint("CENTER"); ga:SetRotation(-math.pi / 2)
    Tint(ga, P.ash)
    go:SetScript("OnEnter", function(self)
        sel = i; Paint(); Tint(ga, P.bronzeHi)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Directions"], 1, 0.82, 0)
        GameTooltip:Show()
    end)
    go:SetScript("OnLeave", function() Tint(ga, P.ash); GameTooltip:Hide() end)
    go:RegisterForClicks("LeftButtonUp")
    go:SetScript("OnClick", function() Choose(r.hit, true) end)
    r.kind = Text(r, "regular", 11, P.ash, "RIGHT")
    r.kind:SetPoint("RIGHT", go, "LEFT", -4, 0)
    r.name = Text(r, "medium", 12, P.ivory, "LEFT")
    r.name:SetPoint("LEFT", 8, 0)
    r.name:SetPoint("RIGHT", r.kind, "LEFT", -8, 0)
    r.name:SetWordWrap(false)
    r:SetScript("OnEnter", function() sel = i; Paint() end)
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnClick", function(self) Choose(self.hit, false) end)
    return r
end

-- ── The box ────────────────────────────────────────────────────────────────
local function Build()
    local map = Map()
    local canvas = map and (map.ScrollContainer or map)
    if not canvas or box then return end

    box = CreateFrame("EditBox", "MythicScoreboardMapSearch", map)
    box:SetSize(BOX_W, BOX_H)
    box:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -12, -12)
    box:SetFrameStrata(map:GetFrameStrata())
    box:SetFrameLevel(math.min(canvas:GetFrameLevel() + 600, 9000))
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    box:SetTextInsets(26, 24, 0, 0)
    UI.SetFont(box, "medium", 12)
    box:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3])
    Box(box)

    local glass = box:CreateTexture(nil, "ARTWORK")
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetSize(14, 14); glass:SetPoint("LEFT", 8, -1)
    glass:SetVertexColor(P.ash[1], P.ash[2], P.ash[3])

    local hint = Text(box, "regular", 12, P.ash, "LEFT")
    hint:SetPoint("LEFT", 26, 0); hint:SetPoint("RIGHT", -24, 0)
    hint:SetText(L["Search dungeons and zones"])
    hint:SetWordWrap(false)

    local clear = Btn(box)
    clear:SetSize(18, 18); clear:SetPoint("RIGHT", -4, 0)
    local x = Art(clear, "Close", "ARTWORK"); x:SetSize(10, 10); x:SetPoint("CENTER"); Tint(x, P.ash)
    clear:SetScript("OnEnter", function() Tint(x, P.ivory) end)
    clear:SetScript("OnLeave", function() Tint(x, P.ash) end)
    clear:SetScript("OnClick", function() box:SetText(""); box:ClearFocus() end)
    clear:Hide()

    list = CreateFrame("Frame", nil, box)
    list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
    list:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
    list:SetFrameLevel(box:GetFrameLevel() + 2)
    list:EnableMouse(true)
    local bg = Solid(list, "BACKGROUND", 0, P.stoneBot[1], P.stoneBot[2], P.stoneBot[3], 0.96)
    bg:SetAllPoints()
    UI.Outline(list, P.line, 1)
    for i = 1, ROWS do rows[i] = MakeRow(i) end
    list.empty = Text(list, "regular", 12, P.ash, "LEFT")
    list.empty:SetPoint("TOPLEFT", 12, -4); list.empty:SetHeight(ROW_H)
    list.empty:SetText(L["Nothing called that."])
    list.hint = Text(list, "regular", 11, P.ash2, "LEFT")
    list.hint:SetPoint("BOTTOMLEFT", 12, 7); list.hint:SetPoint("BOTTOMRIGHT", -12, 7)
    list.hint:SetWordWrap(true)
    list.hint:SetText(L["Enter or click: show it on the map. The arrow, or Shift-Enter: directions."]
        .. "\n" .. L["Alt-click anywhere on the map: directions to that spot. Alt-click the route to clear it."])
    list:Hide()

    local function Placeholder()
        local empty = (box:GetText() or "") == ""
        hint:SetShown(empty and not box:HasFocus())
        clear:SetShown(not empty)
    end
    box:SetScript("OnTextChanged", function() Placeholder(); Refresh() end)
    box:SetScript("OnEditFocusGained", function() Placeholder(); if (box:GetText() or "") ~= "" then Refresh() end end)
    box:SetScript("OnEditFocusLost", function()
        Placeholder()
        -- (A click on the list takes the focus first: hide it after the click.)
        C_Timer.After(0.2, function() if not box:HasFocus() then HideList() end end)
    end)
    box:SetScript("OnEnterPressed", function() Choose(results[sel], IsShiftKeyDown()) end)
    box:SetScript("OnEscapePressed", function()
        if (box:GetText() or "") ~= "" then box:SetText("") else box:ClearFocus() end
    end)
    box:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then Move(-1) elseif key == "DOWN" then Move(1) end
    end)
    box:SetScript("OnTabPressed", function() Move(IsShiftKeyDown() and -1 or 1) end)
    -- Closing the map leaves it empty for next time.
    map:HookScript("OnHide", function() box:SetText(""); box:ClearFocus(); HideList() end)
    Placeholder()
end

-- ── Alt-click on the map: directions to that spot ─────────────────────────
-- Where the button went down (a click on a continent opens the zone under
-- it as the button comes up, so the spot is taken first). Not a drag.
local downAt
local function HookAltClick()
    local map = Map()
    local canvas = map and map.ScrollContainer
    if not (canvas and canvas.HookScript and canvas.GetNormalizedCursorPosition) then return end
    canvas:HookScript("OnMouseDown", function(self, button)
        downAt = nil
        if button ~= "LeftButton" or not IsAltKeyDown() then return end
        local ok, x, y = pcall(self.GetNormalizedCursorPosition, self)
        local id = map.GetMapID and map:GetMapID()
        if ok and x and y and id and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            local cx, cy = GetCursorPosition()
            downAt = { map = id, x = x, y = y, cx = cx, cy = cy }
            local cv = map.GetCanvas and map:GetCanvas()          -- its size on screen, before a click opens a zone
            if cv then
                local scale = cv:GetEffectiveScale()
                downAt.w, downAt.h = cv:GetWidth() * scale, cv:GetHeight() * scale
            end
        end
    end)
    canvas:HookScript("OnMouseUp", function(_, button)
        local d = downAt
        downAt = nil
        if not d or button ~= "LeftButton" or not IsAltKeyDown() then return end
        local cx, cy = GetCursorPosition()
        if math.abs(cx - d.cx) > 10 or math.abs(cy - d.cy) > 10 then return end   -- dragged
        -- On the route's line or a dot: the directions off.
        if MS:NavigationTarget() and MS:OnRouteLine(d.map, d.x, d.y, d.w, d.h, 10) then
            MS:StopNavigation()
            return
        end
        local dest = MS:SpotDestination(d.map, d.x, d.y)
        if dest and MS.NavigateTo then
            local ok, err = pcall(MS.NavigateTo, MS, dest)
            if not ok then MS:ReportError("Arrow", err) end
        end
    end)
end

local function TryBuild()
    local first = not box
    local ok, err = pcall(Build)
    if not ok then MS:ReportError("Map search", err) end
    if first and box then
        ok, err = pcall(HookAltClick)
        if not ok then MS:ReportError("Map search", err) end
    end
end

MS:On("PLAYER_LOGIN", TryBuild)
MS:On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" then TryBuild() end
end)

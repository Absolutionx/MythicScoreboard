local MS = _G["MythicScoreboard"]
local L = MS.L

-- ── Dungeon entrances on the world map (WoW Forever) ──────────────────────
-- Forever's world map is the old one, with no dungeon entrances on it. A
-- marker for each (ForeverData.ENTRANCES), on its zone's map and on the
-- continent's; wings that share an entrance share a marker. Hover one for
-- the dungeon and its levels.

local _fmt, _ins = string.format, table.insert

local function Levels(name, levels)
    local def = MS.FOREVER_DUNGEONS and MS.FOREVER_DUNGEONS[name]
    local lv = levels or (def and def.levels)
    if lv then return lv[1], lv[2] end
end

-- Where a spot on a zone's map is on another map (the continent's), or nil.
local function OnMap(zone, x, y, mapID)
    if zone == mapID then return x, y end
    local C = rawget(_G, "C_Map")
    if not (C and C.GetMapRectOnMap) then return nil end
    local ok, minX, maxX, minY, maxY = pcall(C.GetMapRectOnMap, zone, mapID)
    if not (ok and minX and maxX and minY and maxY) or maxX <= minX or maxY <= minY then return nil end
    return minX + x * (maxX - minX), minY + y * (maxY - minY)
end

-- The markers for a map: { x, y, list of { name, lo, hi } }, one per spot.
function MS:EntrancePins(mapID)
    local pins, at = {}, {}
    for _, e in ipairs(MS.ForeverData and MS.ForeverData.ENTRANCES or {}) do
        local x, y = OnMap(e.map, e.x, e.y, mapID)
        if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            local spot = _fmt("%d:%.3f:%.3f", e.map, e.x, e.y)
            local pin = at[spot]
            if not pin then
                pin = { x = x, y = y, dungeons = {} }
                at[spot] = pin
                _ins(pins, pin)
            end
            local lo, hi = Levels(e[1], e.levels)
            _ins(pin.dungeons, { name = e[1], lo = lo, hi = hi, entrance = { map = e.map, x = e.x, y = e.y } })
            -- Wings that share it: the dungeon's own name ("Scarlet Monastery").
            local base = e[1]:match("^(.-):")
            if #pin.dungeons == 1 then pin.group = base
            elseif pin.group ~= base then pin.group = nil end
        end
    end
    return pins
end

-- The marker's tooltip lines: { left, right } per dungeon.
function MS:EntrancePinLines(pin)
    local out = {}
    for _, d in ipairs(pin.dungeons) do
        _ins(out, { d.name, d.lo and _fmt(L["Levels %d-%d"], d.lo, d.hi) or "" })
    end
    return out
end

-- ── On the map ─────────────────────────────────────────────────────────────
-- A data provider: the map asks for its markers each time it changes, and
-- sizes and places them as it does its own.
if MS.FLAVOR ~= "forever" then return end

local CreateFromMixins = rawget(_G, "CreateFromMixins")
local PinBase, ProviderBase = rawget(_G, "MapCanvasPinMixin"), rawget(_G, "MapCanvasDataProviderMixin")

-- Global: the XML template (Core/MapPins.xml) names it.
local PinMixin = CreateFromMixins and PinBase and CreateFromMixins(PinBase) or {}
rawset(_G, "MythicScoreboardEntrancePinMixin", PinMixin)

function PinMixin:OnLoad()
    if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.2) end
    if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_DUNGEON_ENTRANCE") end
    local icon = self.Icon
    local CT = rawget(_G, "C_Texture")
    if CT and CT.GetAtlasInfo and CT.GetAtlasInfo("Dungeon") then
        icon:SetAtlas("Dungeon")
    else
        icon:SetTexture("Interface\\Minimap\\Dungeon")
    end
end

function PinMixin:OnAcquired(pin)
    self.pin = pin
    self:SetPosition(pin.x, pin.y)
end

function PinMixin:OnMouseEnter()
    if not self.pin then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local lines = MS:EntrancePinLines(self.pin)
    for i, l in ipairs(lines) do
        if i == 1 then
            GameTooltip:SetText(l[1], 1, 0.82, 0)
            if l[2] ~= "" then GameTooltip:AddLine(l[2], 0.8, 0.8, 0.8) end
        else
            GameTooltip:AddDoubleLine(l[1], l[2], 1, 0.82, 0, 0.8, 0.8, 0.8)
        end
    end
    if MS.ToggleNavigation then
        GameTooltip:AddLine(L["Click: the way to the entrance (Shift-click the arrow to stop)"], 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

-- (The map calls it on a click: OnMouseUp is its own, for zooming out on right-click.)
function PinMixin:OnClick(button)
    if button == "LeftButton" and self.pin and MS.ToggleNavigation then
        local ok, err = pcall(MS.ToggleNavigation, MS, self.pin)
        if not ok then MS:ReportError("Arrow", err) end
    end
end

function PinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

local function AddProvider()
    if MS._entranceProvider then return end
    local map = rawget(_G, "WorldMapFrame")
    ProviderBase = ProviderBase or rawget(_G, "MapCanvasDataProviderMixin")
    if not (map and map.AddDataProvider and ProviderBase and CreateFromMixins) then return end
    local provider = CreateFromMixins(ProviderBase)
    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate("MythicScoreboardEntrancePinTemplate")
    end
    function provider:RefreshAllData()
        self:RemoveAllData()
        local mapID = self:GetMap():GetMapID()
        if not mapID then return end
        for _, pin in ipairs(MS:EntrancePins(mapID)) do
            self:GetMap():AcquirePin("MythicScoreboardEntrancePinTemplate", pin)
        end
    end
    map:AddDataProvider(provider)
    MS._entranceProvider = provider
end

-- After login, or once Blizzard's map loads if it loads later.
MS:On("PLAYER_LOGIN", function() pcall(AddProvider) end)
MS:On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" then pcall(AddProvider) end
end)

-- Turning the markers on or off redraws an open map.
function MS:RefreshEntrancePins()
    local p = MS._entranceProvider
    if p and p.GetMap and p:GetMap() then pcall(p.RefreshAllData, p) end
end

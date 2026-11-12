local MS = _G["MythicScoreboard"]
local UI = MS.UI

-- ── The way to a dungeon, on the world map (WoW Forever) ──────────────────
-- While the arrow shows the way (Core/UI_Navigate.lua), the world map draws
-- it: a line from you through each stop to the entrance (gold on foot, blue
-- in the air), a dot at each flight master and dock, and a bigger one at
-- the dungeon. On the continent's map, a zone's, or the world's.
--
-- The route is on its continent's map; MS:RouteOnMap works out where that is
-- on the map you're looking at. The drawing is one map pin the size of the
-- map, so it pans and zooms with it; its lines and dots stay the same size
-- on screen at any zoom.

local _ins, _max, _min = table.insert, math.max, math.min

-- ── Where the route is on a map ───────────────────────────────────────────
-- A spot on a continent's map, on another map (a zone on it, or the world
-- it's on): x, y, which may be off the map. Or nil.
local function Rect(inner, outer)
    local C = rawget(_G, "C_Map")
    if not (C and C.GetMapRectOnMap) then return nil end
    local ok, minX, maxX, minY, maxY = pcall(C.GetMapRectOnMap, inner, outer)
    if ok and minX and maxX and minY and maxY and maxX > minX and maxY > minY then
        return minX, maxX, minY, maxY
    end
end

local function ToMap(c, x, y, mapID)
    if c == mapID then return x, y end
    local minX, maxX, minY, maxY = Rect(mapID, c)              -- a zone on the continent
    if minX then return (x - minX) / (maxX - minX), (y - minY) / (maxY - minY) end
    minX, maxX, minY, maxY = Rect(c, mapID)                     -- the world the continent's on
    if minX then return minX + x * (maxX - minX), minY + y * (maxY - minY) end
end

-- The part of a line on the map (0 to 1 each way), or nil (Liang-Barsky).
local function Clip(x1, y1, x2, y2)
    local t0, t1 = 0, 1
    local dx, dy = x2 - x1, y2 - y1
    for _, pq in ipairs({ { -dx, x1 }, { dx, 1 - x1 }, { -dy, y1 }, { dy, 1 - y1 } }) do
        local p, q = pq[1], pq[2]
        if p == 0 then
            if q < 0 then return nil end
        else
            local r = q / p
            if p < 0 then t0 = _max(t0, r) else t1 = _min(t1, r) end
            if t0 > t1 then return nil end
        end
    end
    return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end

local function OnIt(x, y) return x >= 0 and x <= 1 and y >= 0 and y <= 1 end

-- The route on a map: lines { x1, y1, x2, y2, how } and dots { x, y, last }.
-- Or nil when there's no way being shown.
function MS:RouteOnMap(mapID)
    local legs = MS:NavigationTarget() and MS:NavigationSteps()
    if not (legs and legs[1] and mapID) then return nil end
    local lines, dots = {}, {}
    local c, x, y = MS:PlayerSpot()
    local prev = x and { c = c, x = x, y = y }
    for i, leg in ipairs(legs) do
        local to = leg.to
        local tx, ty = ToMap(to.c, to.x, to.y, mapID)
        -- A boat or zeppelin crosses to another continent: no line.
        if prev and prev.c == to.c and tx then
            local px, py = ToMap(prev.c, prev.x, prev.y, mapID)
            local x1, y1, x2, y2
            if px then x1, y1, x2, y2 = Clip(px, py, tx, ty) end
            if x1 then _ins(lines, { x1, y1, x2, y2, how = leg.how }) end
        end
        if tx and OnIt(tx, ty) then _ins(dots, { tx, ty, last = i == #legs }) end
        prev = to
    end
    return { lines = lines, dots = dots }
end

-- ── On the map ─────────────────────────────────────────────────────────────
if MS.FLAVOR ~= "forever" then return end

local CreateFromMixins = rawget(_G, "CreateFromMixins")
local PinBase = rawget(_G, "MapCanvasPinMixin")
local P = UI and UI.P
local GOLD = P and P.bronzeHi or { 0.91, 0.72, 0.47 }
local SKY = { 0.45, 0.78, 1 }
local DARK = { 0, 0, 0, 0.75 }
local DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"   -- a white circle
local WIDTH, EDGE, DOT_SIZE, END_SIZE = 3, 2, 9, 14               -- on screen
local FOLLOW = 0.1                                                -- seconds between redraws

-- Global: the XML template (Core/MapPins.xml) names it.
local RoutePin = CreateFromMixins and PinBase and CreateFromMixins(PinBase) or {}
rawset(_G, "MythicScoreboardRoutePinMixin", RoutePin)

-- Never in the way of the map's clicks, or its markers'.
local function NoMouse(self)
    self:EnableMouse(false)
    if self.SetMouseClickEnabled then self:SetMouseClickEnabled(false) end
    if self.SetMouseMotionEnabled then self:SetMouseMotionEnabled(false) end
end

function RoutePin:OnLoad()
    if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_MAP_HIGHLIGHT") end
    NoMouse(self)
    self.lines, self.dots = {}, {}
    -- While the map's open: the line from you follows you (on foot, mounted
    -- or in the air), a few times a second.
    local wait = 0
    self:SetScript("OnUpdate", function(pin, elapsed)
        wait = wait - (elapsed or 0)
        if wait > 0 then return end
        wait = FOLLOW
        local ok, err = pcall(pin.Follow, pin)
        if not ok then MS:ReportError("Route", err) end
    end)
end

-- Always its own size: the map's.
function RoutePin:ApplyCurrentScale()
    self:SetScale(1)
    if self.ApplyCurrentPosition then self:ApplyCurrentPosition() end
end

function RoutePin:OnAcquired(route)
    self.route = route
    NoMouse(self)
    self:SetPosition(0.5, 0.5)
    self:Draw()
end

function RoutePin:Follow()
    local map = self:GetMap()
    local route = map and MS:RouteOnMap(map:GetMapID())
    if route then
        self.route = route
        self:Draw()
    end
end

function RoutePin:OnCanvasScaleChanged()
    self:ApplyCurrentScale()
    self:Draw()
end
RoutePin.OnCanvasSizeChanged = RoutePin.OnCanvasScaleChanged

local function Line(self, i, layer)
    local l = self.lines[i]
    if not l then
        l = self:CreateLine(nil, "ARTWORK", nil, layer)
        self.lines[i] = l
    end
    l:Show()
    return l
end

local function Dot(self, i, layer)
    local d = self.dots[i]
    if not d then
        d = self:CreateTexture(nil, "OVERLAY", nil, layer)
        d:SetTexture(DOT)
        self.dots[i] = d
    end
    d:Show()
    return d
end

function RoutePin:Draw()
    local map, route = self:GetMap(), self.route
    if not (map and route) then return end
    local canvas = map:GetCanvas()
    local W, H = canvas:GetWidth(), canvas:GetHeight()
    if not (W and H and W > 0 and H > 0) then return end
    self:SetSize(W, H)
    -- One pixel on screen, in the map's own units.
    local px = 1 / ((map.GetCanvasScale and map:GetCanvasScale()) or 1)
    local nl, nd = 0, 0
    -- A dark edge under each line, then the line.
    for pass = 1, 2 do
        for _, s in ipairs(route.lines) do
            nl = nl + 1
            local l = Line(self, nl, pass == 1 and 1 or 2)
            l:SetStartPoint("TOPLEFT", self, s[1] * W, -s[2] * H)
            l:SetEndPoint("TOPLEFT", self, s[3] * W, -s[4] * H)
            if pass == 1 then
                l:SetThickness((WIDTH + 2 * EDGE) * px)
                l:SetColorTexture(DARK[1], DARK[2], DARK[3], DARK[4])
            else
                local col = s.how == "fly" and SKY or GOLD
                l:SetThickness(WIDTH * px)
                l:SetColorTexture(col[1], col[2], col[3], 1)
            end
        end
    end
    for _, d in ipairs(route.dots) do
        local size = (d.last and END_SIZE or DOT_SIZE) * px
        for pass = 1, 2 do
            nd = nd + 1
            local t = Dot(self, nd, pass == 1 and 1 or 2)
            local s = pass == 1 and size + 2 * EDGE * px or size
            t:SetSize(s, s)
            t:ClearAllPoints()
            t:SetPoint("CENTER", self, "TOPLEFT", d[1] * W, -d[2] * H)
            if pass == 1 then t:SetVertexColor(DARK[1], DARK[2], DARK[3], DARK[4])
            elseif d.last then t:SetVertexColor(1, 0.82, 0, 1)
            else t:SetVertexColor(1, 1, 1, 1) end
        end
    end
    for i = nl + 1, #self.lines do self.lines[i]:Hide() end
    for i = nd + 1, #self.dots do self.dots[i]:Hide() end
end

local function AddProvider()
    if MS._routeProvider then return end
    local map = rawget(_G, "WorldMapFrame")
    local ProviderBase = rawget(_G, "MapCanvasDataProviderMixin")
    if not (map and map.AddDataProvider and ProviderBase and CreateFromMixins) then return end
    local provider = CreateFromMixins(ProviderBase)
    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate("MythicScoreboardRoutePinTemplate")
    end
    function provider:RefreshAllData()
        self:RemoveAllData()
        local route = MS:RouteOnMap(self:GetMap():GetMapID())
        if route and (route.lines[1] or route.dots[1]) then
            self:GetMap():AcquirePin("MythicScoreboardRoutePinTemplate", route)
        end
    end
    map:AddDataProvider(provider)
    MS._routeProvider = provider
end

MS:On("PLAYER_LOGIN", function() pcall(AddProvider) end)
MS:On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" then pcall(AddProvider) end
end)

-- A new route (or none): drawn again if the map's open.
function MS:RefreshRouteMap()
    local p = MS._routeProvider
    local map = p and p.GetMap and p:GetMap()
    if map and map:IsShown() then
        local ok, err = pcall(p.RefreshAllData, p)
        if not ok then MS:ReportError("Route", err) end
    end
end

-- usage: lua5.1 map_data_tests.lua DIR TOC   (Forever: map search's zones and order, where a zone's
-- directions go, and the map's markers: entrances and the route, hooked into the map)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")

-- What the game's map has, as far as these need it (set before loading:
-- the files keep their own references).
CreateFromMixins = function(...)
    local t = {}
    for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end
    return t
end
MapCanvasPinMixin = { SetPosition = function(self, x, y) self._pos = { x, y } end }
MapCanvasDataProviderMixin = { GetMap = function(self) return self._map end }
local atlasKnown = true
C_Texture = { GetAtlasInfo = function(name) return atlasKnown and name == "Dungeon" and {} or nil end }
local ZONES = {
    [1414] = { { name = "Tanaris", mapID = 1446, mapType = 3 }, { name = "Thousand Needles", mapID = 1441, mapType = 3 },
               { name = "Orgrimmar", mapID = 1454, mapType = 3 }, { name = "Tanaris", mapID = 1446, mapType = 3 },
               { name = "Caverns of Time", mapID = 75, mapType = 4 } },
    [1415] = { { name = "Burning Steppes", mapID = 1428, mapType = 3 }, { name = "Searing Gorge", mapID = 1427, mapType = 3 } },
}
local mapsReady = false
C_Map.GetMapChildrenInfo = function(c) return mapsReady and ZONES[c] or nil end

M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if MS.FLAVOR ~= "forever" then io.stdout:write("retail: 0 passed, 0 failed (WoW Forever only)\n"); os.exit(0) end

-- A world map that keeps what's put on it.
local map = CreateFrame("Frame", "WorldMapFrame", UIParent)
map:SetFrameStrata("HIGH")
local providers, acquired, mapID = {}, {}, 1414
function map:AddDataProvider(p) p._map = map; providers[#providers + 1] = p end
function map:GetMapID() return mapID end
function map:AcquirePin(template, data) acquired[#acquired + 1] = { template = template, data = data } end
function map:RemoveAllPinsByTemplate(template)
    for i = #acquired, 1, -1 do if acquired[i].template == template then table.remove(acquired, i) end end
end
local function pins(template)
    local out = {}
    for _, a in ipairs(acquired) do if a.template == template then out[#out + 1] = a.data end end
    return out
end
WorldMapFrame = map
map:Show()

M.Fire("ADDON_LOADED", "MythicScoreboard")
M.Fire("PLAYER_LOGIN"); M.RunTimers(1)

-- ── The zones the search knows ─────────────────────────────────────────────
local z0 = MS:SearchableZones()
check("maps not loaded yet: no zones, and asked again later", #z0 == 0)
mapsReady = true
local zones = MS:SearchableZones()
local names = {}
for _, z in ipairs(zones) do names[#names + 1] = z.name end
check("zones from both continents", #zones == 5, table.concat(names, ", "))
local tanaris = 0
for _, z in ipairs(zones) do if z.name == "Tanaris" then tanaris = tanaris + 1 end end
check("a zone listed twice: once", tanaris == 1, tanaris)
local cot = false
for _, z in ipairs(zones) do if z.name == "Caverns of Time" then cot = true end end
check("not a zone (a cave's map): left out", not cot)
check("kept once found", MS:SearchableZones() == zones)

-- ── What a search finds, in what order ─────────────────────────────────────
local function found(q, limit)
    local out = {}
    for _, h in ipairs(MS:MapSearch(q, limit)) do out[#out + 1] = h.kind:sub(1, 1) .. ":" .. h.name end
    return out
end
local r = found("tan")
check("a zone by the start of its name", r[1] == "z:Tanaris", table.concat(r, ", "))
r = found("brd")
check("a dungeon by its short name, first", r[1] == "d:Blackrock Depths", table.concat(r, ", "))
r = found("burning")
check("a zone, with its map", r[1] == "z:Burning Steppes" and MS:MapSearch("burning")[1].map == 1428)
r = found("searing")
check("the dungeon in it doesn't match a zone's name", r[1] == "z:Searing Gorge", table.concat(r, ", "))
r = found("blackrock")
check("as good a fit: dungeons before zones, then by name",
    r[1] == "d:Blackrock Depths" and r[2] == "d:Lower Blackrock Spire", table.concat(r, ", "))
r = found("needles")
check("the start of a later word", r[1] == "z:Thousand Needles", table.concat(r, ", "))
r = found("e", 3)
check("no more than asked for", #r == 3, #r)
check("nothing typed: nothing", #MS:MapSearch("") == 0 and #MS:MapSearch("   ") == 0)
local h = MS:MapSearch("brd")[1]
check("a dungeon carries its levels", h.lo == 52 and h.hi == 60, tostring(h.lo) .. "-" .. tostring(h.hi))

-- ── Where directions to a zone go ──────────────────────────────────────────
local realOn, realFM, realZoneAt = MS.OnContinent, MS.FlightMasters, MS.ZoneAt
MS.OnContinent = function(_, m, x, y) return 1414, 0.6, 0.8 end
MS.ZoneAt = function(_, c, x, y) return (x > 0.5 and y > 0.7) and 1446 or 1441 end
MS.FlightMasters = function() return { { x = 0.62, y = 0.79 }, { x = 0.55, y = 0.9 }, { x = 0.4, y = 0.3 } } end
local d = MS:ZoneDestination({ name = "Tanaris", map = 1446 })
check("a zone: its flight master nearest the middle", d and d.map == 1414 and d.x == 0.62 and d.y == 0.79,
    d and (d.x .. "," .. d.y))
MS.FlightMasters = function() return { { x = 0.4, y = 0.3 } } end
d = MS:ZoneDestination({ name = "Tanaris", map = 1446 })
check("none in the zone: its middle", d and d.map == 1446 and d.x == 0.5 and d.y == 0.5)
MS.OnContinent = function() return nil end
check("not on a continent: nowhere", MS:ZoneDestination({ name = "?", map = 1 }) == nil)
MS.OnContinent, MS.FlightMasters, MS.ZoneAt = realOn, realFM, realZoneAt

-- ── Entrance markers: hooked into the map ──────────────────────────────────
local entranceProvider
for _, p in ipairs(providers) do if p == MS._entranceProvider then entranceProvider = p end end
check("entrance markers hooked into the map", entranceProvider ~= nil)
local withEntrances
for _, e in ipairs(MS.ForeverData.ENTRANCES) do withEntrances = withEntrances or e.map end
mapID = withEntrances
entranceProvider:RefreshAllData()
local here = 0
for _, e in ipairs(MS.ForeverData.ENTRANCES) do if e.map == withEntrances then here = here + 1 end end
check("one marker per entrance on the map", #pins("MythicScoreboardEntrancePinTemplate") >= 1
    and #pins("MythicScoreboardEntrancePinTemplate") <= here, #pins("MythicScoreboardEntrancePinTemplate") .. " of " .. here)
entranceProvider:RefreshAllData()
check("drawn again: not twice", #pins("MythicScoreboardEntrancePinTemplate") <= here)
mapID = nil
entranceProvider:RefreshAllData()
check("no map: no markers", #pins("MythicScoreboardEntrancePinTemplate") == 0)

-- The marker's icon: the game's dungeon icon, or the old texture without it.
local mix = rawget(_G, "MythicScoreboardEntrancePinMixin")
local function newPin()
    local f = CreateFrame("Button", nil, map)
    f.Icon = f:CreateTexture()
    local set = {}
    f.Icon.SetAtlas = function(_, a) set.atlas = a end
    f.Icon.SetTexture = function(_, t) set.texture = t end
    for k, v in pairs(mix) do if type(v) == "function" then f[k] = v end end
    return f, set
end
local p1, s1 = newPin(); p1:OnLoad()
check("icon: the dungeon atlas", s1.atlas == "Dungeon")
atlasKnown = false
local p2, s2 = newPin(); p2:OnLoad()
check("icon: the old texture when there's no atlas", s2.texture == "Interface\\Minimap\\Dungeon" and not s2.atlas)

-- ── The route: hooked into the map, drawn only with a route ────────────────
local routeProvider = MS._routeProvider
check("route hooked into the map", routeProvider ~= nil)
mapID = 1414
routeProvider:RefreshAllData()
check("no route: nothing drawn", #pins("MythicScoreboardRoutePinTemplate") == 0)
local realRoute = MS.RouteOnMap
MS.RouteOnMap = function() return { lines = { { 0.1, 0.1, 0.2, 0.2 } }, dots = {} } end
routeProvider:RefreshAllData()
check("a route: drawn once", #pins("MythicScoreboardRoutePinTemplate") == 1)
MS.RouteOnMap = function() return { lines = {}, dots = {} } end
routeProvider:RefreshAllData()
check("an empty route: nothing", #pins("MythicScoreboardRoutePinTemplate") == 0)
MS.RouteOnMap = realRoute

local function errorsPrinted() for _, p in ipairs(M.printed) do if p:find("rror") then return p end end end
check("no errors", not errorsPrinted(), errorsPrinted())
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR, passes, fails))
os.exit(fails == 0 and 0 or 1)

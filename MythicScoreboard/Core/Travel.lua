local MS = _G["MythicScoreboard"]

-- ── Getting to a dungeon (WoW Forever) ────────────────────────────────────
-- Where things are, and the quickest way from you to a dungeon's entrance:
-- on foot, by the flight paths you know, and by boat or zeppelin between
-- the continents. Core/UI_Navigate.lua shows it as steps and an arrow.
--
-- Everything is placed on its continent's map (x, y from 0 to 1) and
-- measured in yards (the continent's size, from the game). The route is the
-- quickest by estimated time: running, flying and sailing at rough speeds.
-- It's worked out again as you go, from wherever you are, so a step done
-- (or skipped) just leads to the next.

local _sqrt, _huge, _ins = math.sqrt, math.huge, table.insert

local CONTINENT = 2                          -- Enum.UIMapType.Continent
local RUN, FLY = 9, 30                       -- yards a second: mounted-ish, and a flight
local FLY_EXTRA = 20                         -- seconds: the flight master, take-off, landing
local SAIL = 200                             -- seconds for a boat or zeppelin, with the wait
local RIDE = { tram = 70 }                   -- shorter rides, with the wait
local FLY_PATH = 1.3                         -- a flight follows its paths, not a straight line
-- Running from one zone into another: zones are walled by hills, so the
-- way round is longer than the straight line, and slower.
local CROSS_FACTOR, CROSS_EXTRA = 1.3, 60

local function MapAPI() return rawget(_G, "C_Map") end

-- ── Maps ───────────────────────────────────────────────────────────────────
-- The continent a map is on, or nil. An island that's on no continent
-- (Zephras Isle, say) is a continent of its own: its own map.
function MS:ContinentOf(mapID)
    local C = MapAPI()
    if not (C and C.GetMapInfo) then return nil end
    local last
    for _ = 1, 8 do
        if not mapID or mapID == 0 then return last end
        local ok, info = pcall(C.GetMapInfo, mapID)
        if not (ok and info) then return last end
        if info.mapType == CONTINENT then return mapID end
        if info.mapType and info.mapType <= 1 then return last end   -- the world, or beyond
        last = mapID
        mapID = info.parentMapID
    end
    return last
end

function MS:MapName(mapID)
    local C = MapAPI()
    local ok, info = pcall(C and C.GetMapInfo or error, mapID)
    return ok and info and MS.Readable(info.name) or nil
end

-- A continent's width and height in yards.
local sizes = {}
function MS:ContinentSize(continent)
    local s = sizes[continent]
    if s then return s[1], s[2] end
    local C = MapAPI()
    local V = rawget(_G, "CreateVector2D")
    if not (C and C.GetWorldPosFromMapPos and V) then return nil end
    local ok1, _, a = pcall(C.GetWorldPosFromMapPos, continent, V(0, 0))
    local ok2, _, b = pcall(C.GetWorldPosFromMapPos, continent, V(1, 1))
    if not (ok1 and ok2 and a and b) then return nil end
    local ax, ay = a:GetXY()
    local bx, by = b:GetXY()
    -- World x runs north-south and y east-west: the map's width is the y span.
    local w, h = math.abs(ay - by), math.abs(ax - bx)
    if w <= 0 or h <= 0 then return nil end
    sizes[continent] = { w, h }
    return w, h
end

-- A spot on a zone's map, on its continent's: continent, x, y. Or nil.
local spots = {}
function MS:OnContinent(map, x, y)
    local key = map .. ":" .. x .. ":" .. y
    local hit = spots[key]
    if hit then return hit[1], hit[2], hit[3] end
    local continent = MS:ContinentOf(map)
    if not continent then return nil end
    local cx, cy = x, y
    if map ~= continent then
        local C = MapAPI()
        if not (C and C.GetMapRectOnMap) then return nil end
        local ok, minX, maxX, minY, maxY = pcall(C.GetMapRectOnMap, map, continent)
        if not (ok and minX and maxX and minY and maxY) or maxX <= minX or maxY <= minY then return nil end
        cx, cy = minX + x * (maxX - minX), minY + y * (maxY - minY)
    end
    spots[key] = { continent, cx, cy }
    return continent, cx, cy
end

-- Where you are: continent, x, y on its map. Or nil (indoors, say).
function MS:PlayerSpot()
    local C = MapAPI()
    if not (C and C.GetBestMapForUnit and C.GetPlayerMapPosition) then return nil end
    local ok, map = pcall(C.GetBestMapForUnit, "player")
    map = ok and MS.ReadableNumber(map)
    local continent = map and MS:ContinentOf(map)
    if not continent then return nil end
    local ok2, pos = pcall(C.GetPlayerMapPosition, continent, "player")
    if not (ok2 and pos and pos.GetXY) then return nil, continent end
    local x, y = pos:GetXY()
    x, y = MS.ReadableNumber(x), MS.ReadableNumber(y)
    if not (x and y) or (x == 0 and y == 0) then return nil, continent end
    return continent, x, y
end

-- Yards between two spots on one continent.
function MS:Yards(continent, x1, y1, x2, y2)
    local w, h = MS:ContinentSize(continent)
    if not w then return nil end
    local dx, dy = (x2 - x1) * w, (y2 - y1) * h
    return _sqrt(dx * dx + dy * dy)
end

-- Your side: "Horde" or "Alliance".
function MS:Side()
    local fn = rawget(_G, "UnitFactionGroup")
    return fn and MS.Readable(fn("player")) or nil
end

-- ── Flight paths you know ─────────────────────────────────────────────────
-- Opening a flight map, the game lists every flight master on the continent:
-- name, where it is, and whether you know it. Kept per character and
-- continent. Until then, the built-in list, taken as known: most players
-- have their side's flight paths, and the first flight map you open on a
-- continent corrects it (the route is worked out again straight away).
local function Learned()
    MythicScoreboardDB = MythicScoreboardDB or {}
    MythicScoreboardDB.flights = MythicScoreboardDB.flights or {}
    return MythicScoreboardDB.flights
end

function MS:LearnFlightMap()
    local T = rawget(_G, "C_TaxiMap")
    local C = MapAPI()
    if not (T and T.GetAllTaxiNodes and C and C.GetBestMapForUnit) then return end
    local ok, map = pcall(C.GetBestMapForUnit, "player")
    local continent = ok and MS:ContinentOf(MS.ReadableNumber(map))
    if not continent then return end
    local ok2, nodes = pcall(T.GetAllTaxiNodes, continent)
    if not (ok2 and type(nodes) == "table" and #nodes > 0) then return end
    local list = {}
    for _, n in ipairs(nodes) do
        local name = MS.Readable(n.name)
        local pos = n.position
        local x, y
        if pos and pos.GetXY then x, y = pos:GetXY() end
        x, y = MS.ReadableNumber(x), MS.ReadableNumber(y)
        -- Old nodes the game still lists ("zzOLD..."): not real flight masters.
        if name and name:find("^zz") then name = nil end
        if name and x and y then
            -- state: 0 here, 1 known (and reachable), 2 not known.
            local state = MS.ReadableNumber(n.state)
            _ins(list, { name = name:match("^([^,]+)") or name, x = x, y = y, known = state ~= 2 })
        end
    end
    if #list > 0 then Learned()[continent] = list end
end

if MS.FLAVOR == "forever" then
    MS:On("TAXIMAP_OPENED", function() MS:LearnFlightMap() end)
end

-- Flight masters on a continent for your side: { name, x, y, known }.
function MS:FlightMasters(continent)
    local learned = Learned()[continent]
    if learned then
        local out = {}
        for _, f in ipairs(learned) do
            if not (f.name or ""):find("^zz") then _ins(out, f) end
        end
        return out
    end
    local side = MS:Side()
    local out = {}
    for _, f in ipairs(MS.ForeverData.FLIGHT_MASTERS or {}) do
        if not f.side or f.side == side then
            local c, x, y = MS:OnContinent(f.map, f.x, f.y)
            if c == continent then _ins(out, { name = f[1], x = x, y = y, known = true, assumed = true }) end
        end
    end
    return out
end

-- The zone a spot on a continent's map is in (its map ID), or nil.
local zones = {}
function MS:ZoneAt(c, x, y)
    local key = string.format("%d:%.3f:%.3f", c, x, y)
    local z = zones[key]
    if z ~= nil then return z or nil end
    local C = MapAPI()
    local id
    if C and C.GetMapInfoAtPosition then
        local ok, info = pcall(C.GetMapInfoAtPosition, c, x, y)
        if ok and type(info) == "table" then id = MS.ReadableNumber(info.mapID) end
    end
    zones[key] = id or false
    return id
end

local function Zone(place)
    if place.zone == nil then place.zone = MS:ZoneAt(place.c, place.x, place.y) or false end
    return place.zone or nil
end

-- ── The route ──────────────────────────────────────────────────────────────
-- Places to go through: you, the entrance, flight masters, docks.
local function Places(from, to)
    local side = MS:Side()
    local P = {
        { kind = "start", c = from.c, x = from.x, y = from.y },
        { kind = "end",   c = to.c,   x = to.x,   y = to.y, name = to.name },
    }
    local continents = { [from.c] = true, [to.c] = true }
    for _, t in ipairs(MS.ForeverData.TRANSPORTS or {}) do
        if not t.side or t.side == side then
            local a, b = {}, {}
            for i, end_ in ipairs({ t[1], t[2] }) do
                local c, x, y = MS:OnContinent(end_.map, end_.x, end_.y)
                if c then
                    local dock = { kind = "dock", transport = t.kind, c = c, x = x, y = y, name = end_[1] }
                    if i == 1 then a = dock else b = dock end
                    continents[c] = true
                end
            end
            if a.c and b.c then
                a.other = b
                if not t.oneway then b.other = a end
                _ins(P, a); _ins(P, b)
            end
        end
    end
    for c in pairs(continents) do
        for _, f in ipairs(MS:FlightMasters(c)) do
            -- One you haven't learned yet: you can still fly from it (talking
            -- to it learns it), just not to it.
            _ins(P, { kind = "flight", c = c, x = f.x, y = f.y, name = f.name, known = f.known ~= false })
        end
    end
    return P
end

-- Seconds from one place to another, and how: "run", "fly", "sail". Or nil.
local function Leg(a, b)
    if a.kind == "dock" and a.other == b then return RIDE[a.transport] or SAIL, a.transport end
    if a.c ~= b.c then return nil end
    local yards = MS:Yards(a.c, a.x, a.y, b.x, b.y)
    if not yards then return nil end
    if a.kind == "flight" and b.kind == "flight" then
        if not b.known then return nil end
        return FLY_EXTRA + yards * FLY_PATH / FLY, "fly"
    end
    local secs = yards / RUN
    local za, zb = Zone(a), Zone(b)
    if za and zb and za ~= zb then secs = secs * CROSS_FACTOR + CROSS_EXTRA end
    return secs, "run"
end

-- The quickest way from one spot to another ({ c, x, y }), as legs:
-- { how = "run" | "fly" | "boat" | "zeppelin" | "tram", to = place }. Or nil.
function MS:PlanRoute(from, to)
    if not (from and to and from.c and to.c) then return nil end
    local P = Places(from, to)
    local dist, prev, how, done = {}, {}, {}, {}
    for i = 1, #P do dist[i] = _huge end
    dist[1] = 0
    for _ = 1, #P do
        local u, best = nil, _huge
        for i = 1, #P do
            if not done[i] and dist[i] < best then u, best = i, dist[i] end
        end
        if not u or u == 2 then break end
        done[u] = true
        for v = 1, #P do
            if not done[v] and v ~= u then
                local t, h = Leg(P[u], P[v])
                if t and dist[u] + t < dist[v] then
                    dist[v], prev[v], how[v] = dist[u] + t, u, h
                end
            end
        end
    end
    if dist[2] == _huge then return nil end
    local legs, i = {}, 2
    while prev[i] do
        _ins(legs, 1, { how = how[i], to = P[i], secs = dist[i] - dist[prev[i]] })
        i = prev[i]
    end
    -- Flights one after another: one flight (the game flies you through).
    local out = {}
    for _, l in ipairs(legs) do
        local last = out[#out]
        if last and last.how == "fly" and l.how == "fly" then last.to, last.secs = l.to, last.secs + l.secs
        else _ins(out, l) end
    end
    return out, dist[2]
end

-- ── Why this way ───────────────────────────────────────────────────────────
-- /sb routedebug: the route from here, each step's estimated time, and the
-- best ways in by each flight master you could land at instead.
function MS:RouteDebug(goal, name)
    local c, x, y = MS:PlayerSpot()
    if not (x and goal) then MS.Say("routedebug: no position or no target"); return end
    local from = { c = c, x = x, y = y }
    local function Line(legs, total)
        local t = {}
        for _, l in ipairs(legs or {}) do
            t[#t + 1] = string.format("%s %s (%ds)", l.how, l.to.name or l.to.kind, l.secs or 0)
        end
        return string.format("%ds: %s", total or 0, table.concat(t, ", "))
    end
    local legs, total = MS:PlanRoute(from, goal)
    MS.Say(string.format("routedebug to %s, zone here %s, there %s", name or "?",
        tostring(MS:ZoneAt(c, x, y)), tostring(MS:ZoneAt(goal.c, goal.x, goal.y))))
    MS.Say("  chosen " .. Line(legs, total))
    -- Each flight master on the way's continent, as the last stop.
    local alts = {}
    for _, f in ipairs(MS:FlightMasters(goal.c)) do
        if f.known then
            local spot = { c = goal.c, x = f.x, y = f.y }
            local a, ta = MS:PlanRoute(from, spot)
            local b, tb = MS:PlanRoute(spot, goal)
            if a and b then
                alts[#alts + 1] = { name = f.name, t = ta + tb, line = Line(a, ta) .. " | then " .. Line(b, tb) }
            end
        end
    end
    table.sort(alts, function(p, q) return p.t < q.t end)
    for i = 1, math.min(4, #alts) do
        MS.Say(string.format("  via %s: %ds  [%s]", alts[i].name, alts[i].t, alts[i].line))
    end
end

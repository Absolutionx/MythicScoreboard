local MS = _G["MythicScoreboard"]

-- ── Searching the world map for a dungeon or a zone (WoW Forever) ─────────
-- What the search box on the world map finds (Core/UI_MapSearch.lua): the
-- dungeons with an entrance on the map (ForeverData.ENTRANCES) and every
-- zone on the continents, as the game names them. Matched however it's
-- typed: the start of the name or of any word in it, anywhere in it, with
-- or without the apostrophes, or by its usual short name ("RFC", "BRD").

local _ins, _sort, _lower, _gsub = table.insert, table.sort, string.lower, string.gsub

-- The short names players use. Several dungeons can share one (DM, SM).
local SHORT = {
    ["Ragefire Chasm"] = { "rfc" },
    ["Wailing Caverns"] = { "wc" },
    ["The Deadmines"] = { "dm", "vc", "deadmines" },
    ["Shadowfang Keep"] = { "sfk" },
    ["Blackfathom Deeps"] = { "bfd" },
    ["The Stockade"] = { "stocks", "stockade" },
    ["Gnomeregan"] = { "gnomer" },
    ["Razorfen Kraul"] = { "rfk" },
    ["Razorfen Downs"] = { "rfd" },
    ["Scarlet Monastery: Graveyard"] = { "sm", "smgy", "gy" },
    ["Scarlet Monastery: Library"] = { "sm", "smlib", "lib" },
    ["Scarlet Monastery: Armory"] = { "sm", "smarm", "arm" },
    ["Scarlet Monastery: Cathedral"] = { "sm", "smcath", "cath" },
    ["Uldaman"] = { "ulda" },
    ["Zul'Farrak"] = { "zf" },
    ["Maraudon"] = { "mara" },
    ["Sunken Temple"] = { "st" },
    ["Blackrock Depths"] = { "brd" },
    ["Lower Blackrock Spire"] = { "lbrs" },
    ["Upper Blackrock Spire"] = { "ubrs" },
    ["Dire Maul: East"] = { "dm", "dme" },
    ["Dire Maul: West"] = { "dm", "dmw" },
    ["Dire Maul: North"] = { "dm", "dmn" },
    ["Scholomance"] = { "scholo" },
    ["Stratholme: Living"] = { "strat", "stratlive", "live" },
    ["Stratholme: Undead"] = { "strat", "stratud", "ud" },
}

-- Lower case, apostrophes and the like dropped: "Krol'dok" is "kroldok".
local function Flat(s)
    s = _lower(s or "")
    s = _gsub(s, "\226\128\153", "")                -- (a curly apostrophe)
    s = _gsub(s, "[%'%`%-%.%:%\"]", "")
    s = _gsub(s, "%s+", " ")
    return (s:match("^%s*(.-)%s*$"))
end

-- How well a name fits what's typed: lower is better, nil not at all.
local function Score(name, flatQuery, shorts)
    local n = Flat(name)
    local nn = _gsub(n, " ", "")
    local q = flatQuery
    local qq = _gsub(q, " ", "")
    for _, s in ipairs(shorts or {}) do
        if s == qq then return 0 end
    end
    if n == q or nn == qq then return 0 end
    if n:sub(1, #q) == q then return 1 end
    -- "the deadmines": "dead" fits the start of its second word.
    for word in n:gmatch("%S+") do
        if word:sub(1, #qq) == qq then return 2 end
    end
    if nn:find(qq, 1, true) then return 3 end
end

-- ── What can be found ──────────────────────────────────────────────────────
local UIMAP_ZONE = 3
local _zones

-- The continents to list zones from: the classic two, where the dungeons
-- are, and wherever you are.
local function Continents()
    local seen, out = {}, {}
    local function Add(c)
        if c and not seen[c] then seen[c] = true; _ins(out, c) end
    end
    Add(1414); Add(1415)
    for _, e in ipairs(MS.ForeverData and MS.ForeverData.ENTRANCES or {}) do
        Add(MS.ContinentOf and MS:ContinentOf(e.map))
    end
    local C = rawget(_G, "C_Map")
    if C and C.GetBestMapForUnit then
        local ok, map = pcall(C.GetBestMapForUnit, "player")
        map = ok and MS.ReadableNumber(map)
        if map then Add(MS.ContinentOf and MS:ContinentOf(map)) end
    end
    return out
end

-- Every zone on those continents: { name, map, continent }. Asked of the
-- game once it answers (it may not have the maps at login).
function MS:SearchableZones()
    if _zones then return _zones end
    local C = rawget(_G, "C_Map")
    if not (C and C.GetMapChildrenInfo) then return {} end
    local list, seen = {}, {}
    for _, c in ipairs(Continents()) do
        local ok, kids = pcall(C.GetMapChildrenInfo, c, UIMAP_ZONE, false)
        for _, info in ipairs(ok and type(kids) == "table" and kids or {}) do
            local name = MS.Readable(info.name)
            local id = MS.ReadableNumber(info.mapID)
            if id and type(name) == "string" and name ~= "" and not seen[id]
                    and (info.mapType == nil or info.mapType == UIMAP_ZONE) then
                seen[id] = true
                _ins(list, { name = name, map = id, continent = c })
            end
        end
    end
    if list[1] then _zones = list end
    return list
end

-- A dungeon's levels, lowest and highest: the entrance's own, or the
-- dungeon's (Data/ForeverDungeons.lua). (MapPins.lua shows them too.)
local function Levels(name, levels)
    local def = MS.FOREVER_DUNGEONS and MS.FOREVER_DUNGEONS[name]
    local lv = levels or (def and def.levels)
    if lv then return lv[1], lv[2] end
end
MS.DungeonLevels = Levels

-- What fits what's typed, best first: { kind = "dungeon" | "zone", name,
-- map, x, y (dungeons), lo, hi (their levels) }. At most `limit` (8).
function MS:MapSearch(query, limit)
    limit = limit or 8
    local q = Flat(query)
    if q == "" then return {} end
    local hits = {}
    for _, e in ipairs(MS.ForeverData and MS.ForeverData.ENTRANCES or {}) do
        local score = Score(e[1], q, SHORT[e[1]])
        if score then
            local lo, hi = Levels(e[1], e.levels)
            _ins(hits, { kind = "dungeon", name = e[1], map = e.map, x = e.x, y = e.y,
                lo = lo, hi = hi, score = score })
        end
    end
    for _, z in ipairs(MS:SearchableZones()) do
        local score = Score(z.name, q)
        if score then
            _ins(hits, { kind = "zone", name = z.name, map = z.map, continent = z.continent, score = score })
        end
    end
    _sort(hits, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        if a.kind ~= b.kind then return a.kind == "dungeon" end
        return a.name < b.name
    end)
    for i = #hits, limit + 1, -1 do hits[i] = nil end
    return hits
end

-- ── The way to a zone ──────────────────────────────────────────────────────
-- Where directions to a zone go: its flight master nearest the middle of
-- the zone (where a flight lands you), or the middle itself when it has
-- none for your side. { name, map, x, y }, or nil.
function MS:ZoneDestination(zone)
    local map = zone.map
    local c, mx, my = MS:OnContinent(map, 0.5, 0.5)
    if not c then return nil end
    local best, bestD
    for _, f in ipairs(MS.FlightMasters and MS:FlightMasters(c) or {}) do
        if f.x and f.y and MS:ZoneAt(c, f.x, f.y) == map then
            local d = (f.x - mx) ^ 2 + (f.y - my) ^ 2
            if not bestD or d < bestD then best, bestD = f, d end
        end
    end
    if best then
        return { name = zone.name, map = c, x = best.x, y = best.y }
    end
    return { name = zone.name, map = map, x = 0.5, y = 0.5 }
end

-- Directions to a spot clicked on a map: { name = "Tanaris 52, 71", map,
-- x, y }. On a continent's map, named by the zone it's in. Or nil (the
-- world's map, say: too far out to mean a spot).
function MS:SpotDestination(map, x, y)
    local c, cx, cy = MS:OnContinent(map, x, y)
    if not c then return nil end
    if c == map then                                   -- the continent: the zone it's in
        local zone = MS:ZoneAt(c, cx, cy)
        local C = rawget(_G, "C_Map")
        if zone and C and C.GetMapRectOnMap then
            local ok, minX, maxX, minY, maxY = pcall(C.GetMapRectOnMap, zone, c)
            if ok and minX and maxX > minX and maxY > minY then
                map, x, y = zone, (cx - minX) / (maxX - minX), (cy - minY) / (maxY - minY)
            end
        end
    end
    local name = MS:MapName(map) or "?"
    return { name = string.format("%s %d, %d", name, math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5)),
        map = map, x = x, y = y }
end

-- The step of the route drawn on a map at a spot (0 to 1 each way): within
-- `near` screen pixels of one of its dots (the end of that step) or its
-- line. step, "dot" | "line", or nil. A dot before a line; the nearest of
-- each. w, h: the map's size on screen, in pixels.
function MS:RouteStepAt(mapID, x, y, w, h, near)
    local route = MS.RouteOnMap and MS:RouteOnMap(mapID)
    if not (route and w and h and w > 0 and h > 0) then return nil end
    near = near or 8
    local px, py = x * w, y * h
    local best, bestD = nil, near * near
    for _, d in ipairs(route.dots) do
        local dx, dy = d[1] * w - px, d[2] * h - py
        local dd = dx * dx + dy * dy
        if dd <= bestD then best, bestD = d, dd end
    end
    if best then return best.step or 1, "dot" end
    bestD = near * near
    for _, l in ipairs(route.lines) do
        local ax, ay, bx, by = l[1] * w, l[2] * h, l[3] * w, l[4] * h
        local vx, vy = bx - ax, by - ay
        local len2 = vx * vx + vy * vy
        local t = len2 > 0 and ((px - ax) * vx + (py - ay) * vy) / len2 or 0
        t = t < 0 and 0 or (t > 1 and 1 or t)
        local dx, dy = ax + t * vx - px, ay + t * vy - py
        local dd = dx * dx + dy * dy
        if dd <= bestD then best, bestD = l, dd end
    end
    if best then return best.step or 1, "line" end
end

-- Is a spot on the route drawn there (its line or a dot)?
function MS:OnRouteLine(mapID, x, y, w, h, near)
    return MS:RouteStepAt(mapID, x, y, w, h, near) ~= nil
end

MS._MapSearchFlat = Flat                 -- for tests

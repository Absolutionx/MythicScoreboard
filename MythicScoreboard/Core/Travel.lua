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
local JUMP = 25                              -- seconds: a hearthstone or teleport's cast, and the loading screen
local WORTH = { hearth = 180, recall = 120, teleport = 60 }   -- seconds one has to save to be used
local HEARTHSTONE, ASTRAL_RECALL = 6948, 556 -- the item, and the shaman's spell (to the same place)
local FLY_PATH = 1.3                         -- a flight follows its paths, not a straight line
-- Running from one zone into another: zones are walled by hills, so the
-- way round is longer than the straight line, and slower.
local CROSS_FACTOR, CROSS_EXTRA = 1.3, 60

local function MapAPI() return rawget(_G, "C_Map") end

-- ── Maps ───────────────────────────────────────────────────────────────────
-- The continent a map is on, or nil. An island that's on no continent
-- (Zephras Isle, say) is a continent of its own: its own map.
local continentOf = {}                      -- map -> its continent, once found (a map never moves)
function MS:ContinentOf(mapID)
    if not mapID then return nil end
    local known = continentOf[mapID]
    if known then return known end
    local found = self:_ContinentOf(mapID)
    if found then continentOf[mapID] = found end      -- (not found: asked again, the game may not be ready)
    return found
end
function MS:_ContinentOf(mapID)
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
    if #list > 0 then
        Learned()[continent] = list
        -- Where they stand, for the account's other characters on this side
        -- (which ones each knows is still its own).
        local side = MS:Side()
        if side then
            local acc = MS.AccountDB(true)
            acc.flightSpots = acc.flightSpots or {}
            acc.flightSpots[side] = acc.flightSpots[side] or {}
            local kept = {}
            for _, f in ipairs(list) do _ins(kept, { name = f.name, x = f.x, y = f.y }) end
            acc.flightSpots[side][continent] = kept
        end
    end
end

if MS.FLAVOR == "forever" then
    MS:On("TAXIMAP_OPENED", function() MS:LearnFlightMap() end)
end

-- Where a flight from the open flight map goes: { kind = "flight", name,
-- c, x, y } for its slot (TakeTaxiNode's), or nil.
function MS:TaxiNodeSpot(slot)
    slot = MS.ReadableNumber(slot)
    if not slot then return nil end
    local T, C = rawget(_G, "C_TaxiMap"), MapAPI()
    local continent
    if C and C.GetBestMapForUnit then
        local ok, map = pcall(C.GetBestMapForUnit, "player")
        continent = ok and MS:ContinentOf(MS.ReadableNumber(map))
    end
    if not continent then return nil end
    local name
    if T and T.GetAllTaxiNodes then
        local ok, nodes = pcall(T.GetAllTaxiNodes, continent)
        for _, n in ipairs(ok and type(nodes) == "table" and nodes or {}) do
            if MS.ReadableNumber(n.slotIndex) == slot then
                name = MS.Readable(n.name)
                local x, y
                if n.position and n.position.GetXY then x, y = n.position:GetXY() end
                x, y = MS.ReadableNumber(x), MS.ReadableNumber(y)
                name = name and (name:match("^([^,]+)") or name)
                if name and x and y then return { kind = "flight", name = name, c = continent, x = x, y = y } end
            end
        end
    end
    -- By its name, from the flight masters known on this continent.
    local Name = rawget(_G, "TaxiNodeName")
    if not name and Name then
        local ok, n = pcall(Name, slot)
        name = ok and MS.Readable(n) or nil
    end
    name = name and (name:match("^([^,]+)") or name)
    for _, f in ipairs(name and MS:FlightMasters(continent) or {}) do
        if f.name == name then return { kind = "flight", name = name, c = continent, x = f.x, y = f.y } end
    end
end

-- Every flight master on a continent as the game lists them, for your side
-- (and both sides' shared ones): { name, x, y, known (assumed) }. Or nil
-- when the game won't say.
local FACTION = { Horde = 1, Alliance = 2 }
function MS:GameFlightMasters(continent, side)
    local T = rawget(_G, "C_TaxiMap")
    if not (T and T.GetTaxiNodesForMap and continent) then return nil end
    local ok, nodes = pcall(T.GetTaxiNodesForMap, continent)
    if not (ok and type(nodes) == "table" and nodes[1]) then return nil end
    local mine = FACTION[side or ""]
    local out = {}
    for _, n in ipairs(nodes) do
        local name = MS.Readable(n.name)
        local faction = MS.ReadableNumber(n.faction) or 0
        local x, y
        if n.position and n.position.GetXY then x, y = n.position:GetXY() end
        x, y = MS.ReadableNumber(x), MS.ReadableNumber(y)
        if name and x and y and not name:find("^zz") and (faction == 0 or not mine or faction == mine) then
            _ins(out, { name = name:match("^([^,]+)") or name, x = x, y = y, known = true, assumed = true })
        end
    end
    return out[1] and out or nil
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
    -- The game's own list (any time, anywhere): exact, and this side's only.
    local live = MS:GameFlightMasters(continent, side)
    if live then return live end
    -- Another character on this side opened this continent's flight map:
    -- where they really stand, taken as known.
    local acc = MS.AccountDB()
    local stood = acc and acc.flightSpots and side and acc.flightSpots[side] and acc.flightSpots[side][continent]
    if stood then
        for _, f in ipairs(stood) do
            _ins(out, { name = f.name, x = f.x, y = f.y, known = true, assumed = true })
        end
        return out
    end
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

-- ── Your own ways across: hearthstone, Astral Recall, a mage's teleports ──
-- Each only when it can be used right now: you have it, and it's off
-- cooldown (a teleport: castable too, so with its rune and the mana).
local function Ready(start, duration)
    start, duration = MS.ReadableNumber(start), MS.ReadableNumber(duration)
    if not (start and duration) then return true end
    return duration <= 1.5 or start + duration - GetTime() <= 0       -- (1.5: only the global cooldown)
end

local function ItemReady(item)
    local CItem, CCont = rawget(_G, "C_Item"), rawget(_G, "C_Container")
    local count = (CItem and CItem.GetItemCount) or rawget(_G, "GetItemCount")
    local okc, have = pcall(count or error, item)
    if not (okc and (MS.ReadableNumber(have) or 0) > 0) then return false end
    local cd = (CCont and CCont.GetItemCooldown) or rawget(_G, "GetItemCooldown")
    if not cd then return true end
    local ok, start, duration = pcall(cd, item)
    return not ok or Ready(start, duration)
end

local function SpellReady(spell)
    local known = rawget(_G, "IsPlayerSpell") or rawget(_G, "IsSpellKnown")
    local okk, has = pcall(known or error, spell)
    if not (okk and has == true) then return false end
    local CSpell = rawget(_G, "C_Spell")
    local usable = (CSpell and CSpell.IsSpellUsable) or rawget(_G, "IsUsableSpell")
    if usable then
        local oku, can = pcall(usable, spell)
        if oku and can == false then return false end
    end
    if CSpell and CSpell.GetSpellCooldown then
        local ok, info = pcall(CSpell.GetSpellCooldown, spell)
        if ok and type(info) == "table" then return Ready(info.startTime, info.duration) end
    end
    local cd = rawget(_G, "GetSpellCooldown")
    if not cd then return true end
    local ok, start, duration = pcall(cd, spell)
    return not ok or Ready(start, duration)
end

-- ── Where they land: learned from the game ─────────────────────────────
-- The first time you hearth (or Astral Recall, or teleport) somewhere, the
-- spot you arrive at is kept for the account; binding at an innkeeper keeps
-- where you stand until then. MythicScoreboardAccountDB.landings:
-- { inns = { [name] = { c, x, y } }, spells = { [spell] = { c, x, y } } }.
local HEARTH_SPELL = 8690                    -- (the hearthstone's own cast)
local function Landings()
    local acc = MS.AccountDB(true)
    acc.landings = acc.landings or {}
    acc.landings.inns = acc.landings.inns or {}
    acc.landings.spells = acc.landings.spells or {}
    return acc.landings
end

local function BindName()
    local Bind = rawget(_G, "GetBindLocation")
    return Bind and MS.Readable(Bind()) or nil
end

local function Keep(kind, key, c, x, y)
    if not (key and c and x and y) then return end
    Landings()[kind][key] = { c = c, x = x, y = y }
end

local TELEPORT_SPELLS = {}
for _, t in ipairs(MS.ForeverData.TELEPORTS or {}) do TELEPORT_SPELLS[t.spell] = true end

-- After the cast: watch for the arrival (a loading screen, or a jump on
-- the same continent), then keep where you are.
local watching
local ARRIVE_TRIES, FAR = 90, 150            -- once a second; yards that count as gone
local function Watch(kind, key, from)
    local token = {}
    watching = token
    local tries = 0
    local function Look()
        if watching ~= token then return end
        tries = tries + 1
        local c, x, y = MS:PlayerSpot()
        local moved = x and from and (c ~= from.c or (MS:Yards(c, x, y, from.x, from.y) or 0) > FAR)
        if x and (moved or not from) then
            watching = nil
            Keep(kind, key, c, x, y)
            return
        end
        if tries < ARRIVE_TRIES then C_Timer.After(1, Look) else watching = nil end
    end
    C_Timer.After(1, Look)
end

function MS:OnTravelSpell(spell)
    spell = MS.ReadableNumber(spell)
    if not spell then return end
    local c, x, y = MS:PlayerSpot()
    local from = x and { c = c, x = x, y = y }
    if spell == HEARTH_SPELL or spell == ASTRAL_RECALL then
        local name = BindName()
        if name then Watch("inns", name, from) end
    elseif TELEPORT_SPELLS[spell] then
        Watch("spells", spell, from)
    end
end

function MS:OnHearthBound()
    local c, x, y = MS:PlayerSpot()
    local name = BindName()
    -- (A spot from an actual arrival is the better one: kept if it's there.)
    if name and not Landings().inns[name] then Keep("inns", name, c, x, y) end
end

if MS.FLAVOR == "forever" then
    MS:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spell)
        if unit == "player" then MS:OnTravelSpell(spell) end
    end)
    MS:On("HEARTHSTONE_BOUND", function() MS:OnHearthBound() end)
end

-- Where your hearthstone is set, as a place: learned, or the inn of that
-- name in the shipped list. Or nil.
function MS:HearthPlace()
    local name = BindName()
    if not name then return nil end
    local acc = MS.AccountDB()
    local seen = acc and acc.landings and acc.landings.inns and acc.landings.inns[name]
    if seen then return { c = seen.c, x = seen.x, y = seen.y, name = name } end
    local side = MS:Side()
    for _, inn in ipairs(MS.ForeverData.INNS or {}) do
        local named = inn[1] == name
        for _, other in ipairs(inn.aka or {}) do named = named or other == name end
        if named and (not inn.side or inn.side == side) then
            local c, x, y = MS:OnContinent(inn.map, inn.x, inn.y)
            if c then return { c = c, x = x, y = y, name = name } end
        end
    end
end

-- The places you can be at in a moment, from anywhere: { kind = "jump",
-- how = "hearth" | "recall" | "teleport", c, x, y, name, and what takes you
-- there: item (the hearthstone) or spell }.
function MS:Jumps()
    local out = {}
    local hearth = MS:HearthPlace()
    if hearth then
        -- Astral Recall first: it's on the shorter cooldown.
        local how = SpellReady(ASTRAL_RECALL) and "recall" or (ItemReady(HEARTHSTONE) and "hearth") or nil
        if how then
            _ins(out, { kind = "jump", how = how, c = hearth.c, x = hearth.x, y = hearth.y, name = hearth.name,
                        item = how == "hearth" and HEARTHSTONE or nil, spell = how == "recall" and ASTRAL_RECALL or nil })
        end
    end
    local acc = MS.AccountDB()
    local landed = acc and acc.landings and acc.landings.spells or {}
    for _, t in ipairs(MS.ForeverData.TELEPORTS or {}) do
        local at = landed[t.spell]
        if at and SpellReady(t.spell) then
            _ins(out, { kind = "jump", how = "teleport", c = at.c, x = at.x, y = at.y, name = t[1], spell = t.spell })
        end
    end
    return out
end

-- ── The route ──────────────────────────────────────────────────────────────
-- Places to go through: you, the entrance, flight masters, docks, and where
-- your hearthstone or a teleport puts you.
local function Places(from, to, jumps)
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
    for _, j in ipairs(jumps and MS:Jumps() or {}) do
        _ins(P, j)
        continents[j.c] = true
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
    -- A hearthstone or teleport: from where you are now, and only from there.
    if b.kind == "jump" then
        if a.kind == "start" then return JUMP, b.how end
        return nil
    end
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
-- { how = "run" | "fly" | "boat" | "zeppelin" | "tram" | "airship" | "hearth" |
-- "recall" | "teleport", to = place }. Or nil.
local function Plan(from, to, jumps)
    local P = Places(from, to, jumps)
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

-- With your hearthstone or a teleport only when it saves real time: they
-- have cooldowns, and aren't worth spending on a minute.
function MS:PlanRoute(from, to, noJumps)
    if not (from and to and from.c and to.c) then return nil end
    local plain, plainSecs = Plan(from, to, false)
    if noJumps then return plain, plainSecs end
    local legs, secs = Plan(from, to, true)
    local jump = legs and legs[1] and WORTH[legs[1].how]
    if jump and plain and plainSecs - secs < jump then return plain, plainSecs end
    return legs, secs
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
            local b, tb = MS:PlanRoute(spot, goal, true)
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

-- ── /sb dumptravel ─────────────────────────────────────────────────────────
-- Everything the game has told the addon about getting around, saved for
-- the next /reload or logout (MythicScoreboardAccountDB.travelDump), to
-- build the shipped lists from: each continent's flight masters as the game
-- lists them, those learned from flight maps, and the landings.
function MS:DumpTravel()
    local acc = MS.AccountDB(true)
    local dump = { at = time(), side = MS:Side(), taxi = {}, flightSpots = acc.flightSpots, landings = acc.landings }
    local continents = {}
    for _, f in ipairs(MS.ForeverData.FLIGHT_MASTERS or {}) do
        local c = MS:ContinentOf(f.map)
        if c then continents[c] = true end
    end
    local c = MS:PlayerSpot()
    if c then continents[c] = true end
    local T = rawget(_G, "C_TaxiMap")
    local n = 0
    if T and T.GetTaxiNodesForMap then
        for id in pairs(continents) do
            local ok, nodes = pcall(T.GetTaxiNodesForMap, id)
            if ok and type(nodes) == "table" then
                local list = {}
                for _, node in ipairs(nodes) do
                    local x, y
                    if node.position and node.position.GetXY then x, y = node.position:GetXY() end
                    _ins(list, { name = MS.Readable(node.name), x = MS.ReadableNumber(x), y = MS.ReadableNumber(y),
                                 faction = MS.ReadableNumber(node.faction) })
                end
                dump.taxi[id] = list
                n = n + #list
            end
        end
    end
    acc.travelDump = dump
    local inns, spells = 0, 0
    for _ in pairs(acc.landings and acc.landings.inns or {}) do inns = inns + 1 end
    for _ in pairs(acc.landings and acc.landings.spells or {}) do spells = spells + 1 end
    local learned = 0
    for _, side in pairs(acc.flightSpots or {}) do
        for _, list in pairs(side) do learned = learned + #list end
    end
    MS.Say(string.format("dumptravel: %d flight masters from the game's list, %d from flight maps, "
        .. "%d inns, %d teleports. /reload to save.", n, learned, inns, spells))
end

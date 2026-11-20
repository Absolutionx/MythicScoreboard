-- usage: lua5.1 travel_tests.lua DIR TOC   (Forever: the way to a dungeon, step by step)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if not MS.PlanRoute then
    io.stdout:write("travel_tests: retail has no route planner, skipped\n")
    os.exit(0)
end
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4)

-- ── A small world ──────────────────────────────────────────────────────────
-- Two continents 10,000 yards across. Each zone covers its whole continent,
-- so a zone's spot is the continent's spot.
local KALIMDOR, EK = 1414, 1415
local function V(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
rawset(_G, "CreateVector2D", V)
local zoneOf = { [1411] = KALIMDOR, [1413] = KALIMDOR, [1420] = EK }
local playerMap, here, facing, side, onTaxi = 1413, { 0.12, 0.12 }, 0, "Horde", false
C_Map.GetMapInfo = function(id)
    if id == KALIMDOR then return { mapType = 2, name = "Kalimdor" } end
    if id == EK then return { mapType = 2, name = "Eastern Kingdoms" } end
    if zoneOf[id] then return { mapType = 3, parentMapID = zoneOf[id] } end
end
C_Map.GetMapRectOnMap = function(zone, map) if zoneOf[zone] == map then return 0, 1, 0, 1 end end
C_Map.GetWorldPosFromMapPos = function(_, pos) return 0, V(5000 - pos.y * 10000, 5000 - pos.x * 10000) end
C_Map.GetBestMapForUnit = function() return playerMap end
C_Map.GetPlayerMapPosition = function(map)
    if here and map == zoneOf[playerMap] then return V(here[1], here[2]) end
end
rawset(_G, "GetPlayerFacing", function() return facing end)
rawset(_G, "UnitFactionGroup", function() return side end)
rawset(_G, "UnitOnTaxi", function() return onTaxi end)

MS.ForeverData.FLIGHT_MASTERS = {
    { "Alpha", map = 1413, x = 0.1, y = 0.1, side = "Horde" },
    { "Beta",  map = 1413, x = 0.9, y = 0.9, side = "Horde" },
    { "Gamma", map = 1420, x = 0.5, y = 0.5, side = "Horde" },
}
MS.ForeverData.TRANSPORTS = {
    { kind = "zeppelin", side = "Horde",
      { "Kdock", map = 1411, x = 0.2, y = 0.2 }, { "Edock", map = 1420, x = 0.3, y = 0.3 } },
}
local function hows(legs)
    local t = {}
    for _, l in ipairs(legs or {}) do t[#t + 1] = l.how end
    return table.concat(t, ",")
end
local from = function() return { c = KALIMDOR, x = here[1], y = here[2] } end

-- No flight map opened here yet: your side's flight paths, taken as known.
local far = { c = KALIMDOR, x = 0.88, y = 0.9 }
local legs = MS:PlanRoute(from(), far)
check("before any flight map: flights assumed", hows(legs) == "run,fly,run", hows(legs))

-- Opening a flight map: every flight master there, and which you know.
rawset(_G, "C_TaxiMap", { GetAllTaxiNodes = function(map)
    if map ~= KALIMDOR then return {} end
    return { { name = "Alpha, Durotar", position = V(0.1, 0.1), state = 0 },
             { name = "Beta", position = V(0.9, 0.9), state = 1 },
             { name = "Delta", position = V(0.5, 0.9), state = 2 } }
end })
M.Fire("TAXIMAP_OPENED")
local learned = MythicScoreboardDB.flights and MythicScoreboardDB.flights[KALIMDOR]
check("taxi map: learned", learned and #learned == 3, learned and #learned)
check("taxi map: name without the zone", learned and learned[1].name == "Alpha")
check("taxi map: unknown kept unknown", learned and learned[3].known == false)

-- Now: run to Alpha, fly to Beta, run to the end; by Alpha, the run's done.
legs = MS:PlanRoute(from(), far)
check("known flights: run, fly, run", hows(legs) == "run,fly,run", hows(legs))
check("known flights: to Beta", legs and legs[2].to.name == "Beta")
here = { 0.1, 0.1004 }
local steps = MS._NavigationSteps(MS:PlanRoute(from(), far), from())
check("at the flight master: fly first", steps[1] and steps[1].how == "fly", steps[1] and steps[1].how)

-- A flight map that says you don't know Beta: run instead.
MythicScoreboardDB.flights[KALIMDOR][2].known = false
check("Beta not known: run", hows(MS:PlanRoute(from(), far)) == "run", hows(MS:PlanRoute(from(), far)))
MythicScoreboardDB.flights[KALIMDOR][2].known = true
-- Alpha not learned yet, right by you: run there (talking to it learns it), fly on.
MythicScoreboardDB.flights[KALIMDOR][1].known = false
legs = MS:PlanRoute(from(), far)
check("not learned, nearby: fly from it", hows(legs) == "run,fly,run" and legs[1].to.name == "Alpha", hows(legs))
MythicScoreboardDB.flights[KALIMDOR][1].known = true
-- Old nodes the game still lists ("zzOLD..."): left out.
table.insert(MythicScoreboardDB.flights[KALIMDOR], { name = "zzOLDGhost", x = 0.12, y = 0.121, known = true })
local ghost = false
for _, f in ipairs(MS:FlightMasters(KALIMDOR)) do if f.name:find("^zz") then ghost = true end end
check("zzOLD nodes left out", not ghost)
table.remove(MythicScoreboardDB.flights[KALIMDOR])

-- Near: just run.
legs = MS:PlanRoute(from(), { c = KALIMDOR, x = 0.15, y = 0.12 })
check("near: run", hows(legs) == "run", hows(legs))

-- Another continent: run to the dock, the zeppelin, run on.
here = { 0.25, 0.25 }
local over = { c = EK, x = 0.35, y = 0.35 }
legs = MS:PlanRoute(from(), over)
check("other continent: run, zeppelin, run", hows(legs) == "run,zeppelin,run", hows(legs))
side = "Alliance"
check("other continent, no zeppelin for the Alliance: no route", MS:PlanRoute(from(), over) == nil)
side = "Horde"
-- One way only: there, but not back.
local both = MS.ForeverData.TRANSPORTS
MS.ForeverData.TRANSPORTS = { { kind = "boat", oneway = true,
    { "Kdock", map = 1411, x = 0.2, y = 0.2 }, { "Edock", map = 1420, x = 0.3, y = 0.3 } } }
check("one-way boat: there", hows(MS:PlanRoute(from(), over)) == "run,boat,run")
check("one-way boat: not back", MS:PlanRoute({ c = EK, x = 0.35, y = 0.35 }, from()) == nil)
MS.ForeverData.TRANSPORTS = { { kind = "tram",
    { "Kdock", map = 1411, x = 0.2, y = 0.2 }, { "Edock", map = 1420, x = 0.3, y = 0.3 } } }
local tram = MS:PlanRoute(from(), over)
check("tram", hows(tram) == "run,tram,run", hows(tram))
-- An island on no continent (its parent's the world): a continent of its own.
local ISLE, WORLD = 2521, 947
local mapInfo = C_Map.GetMapInfo
C_Map.GetMapInfo = function(id)
    if id == ISLE then return { mapType = 3, parentMapID = WORLD, name = "Zephras Isle" } end
    if id == WORLD then return { mapType = 1, name = "Azeroth" } end
    return mapInfo(id)
end
check("island: its own continent", MS:ContinentOf(ISLE) == ISLE)
MS.ForeverData.TRANSPORTS = { { kind = "airship",
    { "Kdock", map = 1411, x = 0.2, y = 0.2 }, { "Valanaar", map = ISLE, x = 0.5, y = 0.8 } } }
local isle = MS:PlanRoute(from(), { c = ISLE, x = 0.4, y = 0.4 })
check("island: by airship", hows(isle) == "run,airship,run", hows(isle))
C_Map.GetMapInfo = mapInfo
MS.ForeverData.TRANSPORTS = both

-- The way to it: straight ahead when facing it; west of you: turn left.
local turn, yards = MS:TurnTo({ c = KALIMDOR, x = 0.5, y = 0.6 }, { x = 0.5, y = 0.5 })
check("turn: straight ahead", turn and math.abs(turn) < 1e-6, turn)
check("turn: 1,000 yards", yards and math.abs(yards - 1000) < 1e-3, yards)
facing = math.pi / 2
turn = MS:TurnTo({ c = KALIMDOR, x = 0.5, y = 0.6 }, { x = 0.5, y = 0.5 })
check("turn: facing west, turn right", turn and math.abs(turn + math.pi / 2) < 1e-6, turn)
facing = 0
turn = MS:TurnTo({ c = KALIMDOR, x = 0.6, y = 0.5 }, { x = 0.5, y = 0.5 })
check("turn: to the west, turn left", turn and math.abs(turn - math.pi / 2) < 1e-6, turn)

-- ── On screen ──────────────────────────────────────────────────────────────
here = { 0.1, 0.1004 }
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
local arrow = rawget(_G, "MythicScoreboardArrow")
check("arrow: shown", arrow and arrow._shown)
check("arrow: the step", arrow and arrow.lastStep == "Step 1 of 2: Fly to Beta", arrow and arrow.lastStep)
check("arrow: points the way the flight goes", arrow and arrow.arrow._shown)
onTaxi = true; MS:UpdateArrow()
check("in the air: where you land", arrow.lastStep:find("Step 1 of 2: Land at Beta", 1, true) == 1, arrow.lastStep)
check("in the air: what comes next", arrow.lastStep:find("Then: Run to Razorfen Kraul", 1, true) ~= nil, arrow.lastStep)
check("in the air: the arrow to where you land", arrow.arrow._shown)
-- A /reload in the air: the same dungeon, no route yet. The flight's kept.
check("in the air: the flight kept", MythicScoreboardDB.navFlying and MythicScoreboardDB.navFlying.name == "Beta")
here = { 0.5, 0.5 }
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
check("reload in the air: still landing at Beta", arrow.lastStep:find("Land at Beta", 1, true) ~= nil, arrow.lastStep)
check("reload in the air: the arrow", arrow.arrow._shown)
check("reload in the air: the yards", arrow.lastDist and arrow.lastDist:find("yards") ~= nil, arrow.lastDist)
check("reload in the air: on the map too", MS:NavigationSteps() and MS:NavigationSteps()[1].how == "fly")
-- Nothing kept (a flight of your own): the arrow to the dungeon.
MythicScoreboardDB.navFlying = nil
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
check("own flight: the arrow to the dungeon", arrow.arrow._shown and arrow.lastDist:find("yards") ~= nil, arrow.lastDist)
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
here = { 0.1, 0.1004 }; onTaxi = false; MS:UpdateArrow()
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
onTaxi = true; MS:UpdateArrow()
onTaxi = false
here = { 0.9, 0.9 }; M.now = M.now + 5; MS:UpdateArrow()
check("landed: the flight forgotten", MythicScoreboardDB.navFlying == nil)
check("landed: run on", arrow.lastStep == "Run to Razorfen Kraul", arrow.lastStep)
check("landed: the arrow", arrow.arrow._shown)
check("landed: the yards", arrow.lastDist and arrow.lastDist:find("yards") ~= nil, arrow.lastDist)
-- Running towards it: the time left, from how fast the yards go down.
here = { 0.88, 0.80 }; M.now = M.now + 1; MS:UpdateArrow()
here = { 0.88, 0.81 }; M.now = M.now + 1; MS:UpdateArrow()      -- 100 yards nearer in a second
check("time left: shown", arrow.lastDist:find("|cffffd14d%d+:%d%d|r") ~= nil, arrow.lastDist)
check("clock: m:ss", MS._NavClock(75) == "1:15" and MS._NavClock(3725) == "1:02:05")
here = { 0.88, 0.9 }; MS:UpdateArrow()
check("there: done", MS:NavigationTarget() == nil)

-- ── A flight of your own choosing ──────────────────────────────────────────
-- Taken from the flight map by hand (not the route's): where it lands is
-- kept, and the steps go on from there, on the arrow and the map.
local realNodes = C_TaxiMap.GetAllTaxiNodes
C_TaxiMap.GetAllTaxiNodes = function()
    return { { name = "Alpha", slotIndex = 1, position = V(0.1, 0.1), state = 0 },
             { name = "Delta, The Barrens", slotIndex = 3, position = V(0.5, 0.9), state = 1 } }
end
here, onTaxi = { 0.1, 0.1 }, false
MS:StopNavigation()
TakeTaxiNode(3)                                          -- (directions not shown yet)
check("own flight: kept as it's taken", MythicScoreboardDB.navFlying and MythicScoreboardDB.navFlying.name == "Delta")
onTaxi = true; here = { 0.3, 0.5 }
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
check("own flight: land at Delta", arrow.lastStep:find("Land at Delta", 1, true) ~= nil, arrow.lastStep)
check("own flight: then on from there", arrow.lastStep:find("Then: ", 1, true) ~= nil, arrow.lastStep)
local steps = MS:NavigationSteps()
check("own flight: the steps from where it lands", steps and steps[1].how == "fly" and steps[1].to.name == "Delta" and #steps >= 2,
    steps and hows(steps))
check("own flight: the arrow to Delta", arrow.arrow._shown and arrow.lastDist:find("yards") ~= nil)
local drawn = MS:RouteOnMap(KALIMDOR)
check("own flight: drawn on the map", drawn and #drawn.lines >= 2, drawn and #drawn.lines)
-- Directions stopped and started again in the air: still known.
MS:StopNavigation()
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
check("own flight: kept over stopping", arrow.lastStep:find("Land at Delta", 1, true) ~= nil, arrow.lastStep)
-- Landed: forgotten, and the steps from where you are.
onTaxi = false; here = { 0.5, 0.9 }
M.Fire("PLAYER_CONTROL_GAINED")
check("own flight: landed, forgotten", MythicScoreboardDB.navFlying == nil)
M.now = M.now + 5; MS:UpdateArrow()
check("own flight: landed, on foot", arrow.lastStep and not arrow.lastStep:find("Land at", 1, true), arrow.lastStep)
C_TaxiMap.GetAllTaxiNodes = realNodes
MS:StopNavigation()

-- Between looks at where you are, a frame only turns the arrow: it follows
-- the way you face straight away, and nothing else is worked out.
here = { 0.5, 0.6 }
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.5, y = 0.5 })     -- due north, 1,000 yards
facing = 0; MS:UpdateArrow()
check("frame: straight ahead", math.abs(arrow.arrow._rotation) < 1e-6, arrow.arrow._rotation)
local spots, realSpot = 0, MS.PlayerSpot
MS.PlayerSpot = function(...) spots = spots + 1; return realSpot(...) end
arrow:Fire("OnUpdate", 0.2)                              -- (a look: where you are, the text)
spots = 0
facing = math.pi / 2
arrow:Fire("OnUpdate", 0.01)
check("frame: the turn follows at once", math.abs(arrow.arrow._rotation + math.pi / 2) < 1e-6, arrow.arrow._rotation)
check("frame: where you are isn't read again", spots == 0, spots)
for _ = 1, 20 do arrow:Fire("OnUpdate", 0.01) end
check("ten looks a second", spots >= 1 and spots <= 3, spots)
MS.PlayerSpot = realSpot
facing = 0
MS:StopNavigation()

-- A click on the arrow doesn't stop it; a Shift-click does.
here = { 0.12, 0.12 }
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
arrow:Fire("OnClick", "LeftButton")
check("arrow: a click keeps it", MS:NavigationTarget() ~= nil)
M.shift = true; arrow:Fire("OnClick", "LeftButton"); M.shift = nil
check("arrow: a Shift-click stops it", MS:NavigationTarget() == nil)

-- Clicking a marker: the way there; again: stop.
here = { 0.12, 0.12 }
local pin = { dungeons = { { name = "Razorfen Kraul", entrance = { map = 1413, x = 0.88, y = 0.9 } } } }
MS:ToggleNavigation(pin)
check("click: on", MS:NavigationTarget() ~= nil)
MS:ToggleNavigation(pin)
check("click again: off", MS:NavigationTarget() == nil and not arrow._shown)

-- At a flight master with "Fly to Beta" next: opening the map takes it.
MythicScoreboardDB.flights = nil
C_TaxiMap.GetAllTaxiNodes = function(map)
    if map ~= KALIMDOR then return {} end
    return { { name = "Alpha", position = V(0.1, 0.1), state = 0, slotIndex = 1 },
             { name = "Beta, The Barrens", position = V(0.9, 0.9), state = 1, slotIndex = 2 } }
end
here = { 0.1, 0.1004 }
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
M.tookTaxi = nil; M.Fire("TAXIMAP_OPENED")
check("auto flight: off by default", M.tookTaxi == nil)
MS:SetAutoTakeFlights(true)
M.tookTaxi = nil; M.Fire("TAXIMAP_OPENED")
check("auto flight: took Beta", M.tookTaxi == 2, M.tookTaxi)
M.tookTaxi = nil; M.shift = true; M.Fire("TAXIMAP_OPENED"); M.shift = nil
check("auto flight: not with Shift", M.tookTaxi == nil)
MS:SetAutoTakeFlights(false)
M.tookTaxi = nil; M.Fire("TAXIMAP_OPENED")
check("auto flight: not when off", M.tookTaxi == nil)

-- Talking to the flight master: straight past the chat to the flight map.
local picked
rawset(_G, "C_GossipInfo", {
    GetOptions = function()
        return { { name = "Train me.", icon = 132058, gossipOptionID = 11 },
                 { name = "I need a ride.", icon = 132057, gossipOptionID = 12 } }
    end,
    SelectOption = function(id) picked = id end,
})
picked = nil; M.Fire("GOSSIP_SHOW")
check("chat: left alone when the setting's off", picked == nil)
MS:SetAutoTakeFlights(true)
picked = nil; M.Fire("GOSSIP_SHOW")
check("chat: the flight choice", picked == 12, picked)
picked = nil; M.shift = true; M.Fire("GOSSIP_SHOW"); M.shift = nil
check("chat: not with Shift", picked == nil)
-- Still on the way to the flight master (its spot a little off): the same.
here = { 0.1, 0.103 }
picked = nil; M.Fire("GOSSIP_SHOW")
check("chat: on the way to it", picked == 12, picked)
here = { 0.1, 0.1004 }
C_GossipInfo.GetOptions = function() return { { name = "Hello.", icon = 132053, gossipOptionID = 13 } } end
picked = nil; M.Fire("GOSSIP_SHOW")
check("chat: no flight choice, nothing", picked == nil)
MS:StopNavigation()
C_GossipInfo.GetOptions = function() return { { name = "I need a ride.", type = "taxi", gossipOptionID = 14 } } end
picked = nil; M.Fire("GOSSIP_SHOW")
check("chat: no way being shown, nothing", picked == nil)
MS:SetAutoTakeFlights(false)

-- The way on the world map: you, the flight master, where you land, the dungeon.
here = { 0.12, 0.12 }
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
local route = MS:RouteOnMap(KALIMDOR)
check("map: three lines", route and #route.lines == 3, route and #route.lines)
check("map: on foot, then flying, then on foot",
    route and route.lines[1].how == "run" and route.lines[2].how == "fly" and route.lines[3].how == "run")
check("map: from you", route and math.abs(route.lines[1][1] - 0.12) < 1e-6)
check("map: a dot at each stop", route and #route.dots == 3)
check("map: the last is the dungeon", route and route.dots[3].last and not route.dots[1].last)
check("map: the zone's map too", MS:RouteOnMap(1413) and #MS:RouteOnMap(1413).lines == 3)
route = MS:RouteOnMap(EK)
check("map: nothing on another continent", route and #route.lines == 0 and #route.dots == 0)
-- Drawn: a dark edge and the line for each, and two circles for each dot.
local Pin = rawget(_G, "MythicScoreboardRoutePinMixin")
local canvas = CreateFrame("Frame"); canvas:SetSize(1000, 700)
local fakeMap = { GetCanvas = function() return canvas end, GetCanvasScale = function() return 2 end,
                  GetMapID = function() return KALIMDOR end }
local pinFrame = CreateFrame("Frame")
for k, v in pairs(Pin) do pinFrame[k] = v end
pinFrame.GetMap = function() return fakeMap end
pinFrame.SetPosition = function() end
local okDraw, errDraw = pcall(function()
    pinFrame:OnLoad()
    pinFrame:OnAcquired(MS:RouteOnMap(KALIMDOR))
    pinFrame:OnCanvasScaleChanged()
end)
check("map: drawn", okDraw, errDraw)
check("map: lines and edges", #pinFrame.lines == 6, #pinFrame.lines)
check("map: dots and edges", #pinFrame.dots == 6, #pinFrame.dots)
-- Moving (in the air, say): the line from you follows, with no new route.
onTaxi = true; here = { 0.5, 0.5 }
pinFrame:Fire("OnUpdate", 1)
check("map: follows you", math.abs(pinFrame.route.lines[1][1] - 0.5) < 1e-6, pinFrame.route.lines[1][1])
onTaxi = false
MS:StopNavigation()
check("map: nothing once stopped", MS:RouteOnMap(KALIMDOR) == nil)

-- In combat: nothing the game blocks. The map's markers skip it; the arrow
-- lets right-click through once the fight's over.
check("arrow: right-click goes through", arrow._passThrough and arrow._passThrough[1] == "RightButton")
local Entrance = rawget(_G, "MythicScoreboardEntrancePinMixin")
local inFight = true
InCombatLockdown = function() return inFight end
local marker = CreateFrame("Frame")
Entrance.SetPassThroughButtons(marker, "RightButton")
check("combat: marker pass-through skipped", (M.blocked or 0) == 0 and marker._passThrough == nil, M.blocked)
inFight = false
Entrance.SetPassThroughButtons(marker, "RightButton")
check("out of combat: marker pass-through set", marker._passThrough and marker._passThrough[1] == "RightButton")
InCombatLockdown = function() return false end

-- ── Your hearthstone, Astral Recall, a mage's teleports ───────────────────
-- (Alpha at 0.1,0.1 and Beta at 0.9,0.9 on Kalimdor; Gamma on the other side.)
local bind, bags, spells, cooldown = nil, {}, {}, {}
rawset(_G, "GetBindLocation", function() return bind end)
rawset(_G, "GetItemCount", function(id) return bags[id] or 0 end)
rawset(_G, "GetItemCooldown", function(id) local c = cooldown[id]; return c and GetTime() or 0, c or 0 end)
rawset(_G, "IsPlayerSpell", function(id) return spells[id] == true end)
rawset(_G, "GetSpellCooldown", function(id) local c = cooldown[id]; return c and GetTime() or 0, c or 0 end)
MS.ForeverData.INNS = {
    { "Farside Inn", map = 1413, x = 0.85, y = 0.88, side = "Horde" },
    { "Nearby Inn",  map = 1413, x = 0.14, y = 0.12, side = "Horde" },
    { "Their Inn",   map = 1413, x = 0.85, y = 0.88, side = "Alliance" },
}
MS.ForeverData.TELEPORTS = { { "Gamma City", spell = 3567 } }
-- No flights here, so the other way is a long run.
MS.ForeverData.FLIGHT_MASTERS = {}
MythicScoreboardDB.flights, MythicScoreboardAccountDB.flightSpots = nil, nil
here = { 0.12, 0.12 }
local goal = { c = KALIMDOR, x = 0.88, y = 0.9 }
check("no hearthstone set: run", hows(MS:PlanRoute(from(), goal)) == "run", hows(MS:PlanRoute(from(), goal)))
bind, bags[6948] = "Farside Inn", 1
legs = MS:PlanRoute(from(), goal)
check("hearthstone near the entrance: used", hows(legs) == "hearth,run", hows(legs))
check("hearthstone: to the inn", legs[1].to.name == "Farside Inn" and math.abs(legs[1].to.x - 0.85) < 1e-6)
check("without it when asked", hows(MS:PlanRoute(from(), goal, true)) == "run")
cooldown[6948] = 3600
check("on cooldown: not used", hows(MS:PlanRoute(from(), goal)) == "run")
cooldown[6948] = nil; bags[6948] = 0
check("no hearthstone in your bags: not used", hows(MS:PlanRoute(from(), goal)) == "run")
spells[556] = true
check("Astral Recall instead", hows(MS:PlanRoute(from(), goal)) == "recall,run", hows(MS:PlanRoute(from(), goal)))
bags[6948] = 1
check("both ready: Astral Recall (shorter cooldown)", hows(MS:PlanRoute(from(), goal)) == "recall,run")
cooldown[556] = 900
check("Astral Recall on cooldown: the hearthstone", hows(MS:PlanRoute(from(), goal)) == "hearth,run")
cooldown[556] = 1.5
check("only the global cooldown: still ready", hows(MS:PlanRoute(from(), goal)) == "recall,run")
-- Shown: the step's icon to click in place of the arrow, set to cast it.
bags[6948], spells[556], cooldown[556] = 1, nil, nil
MS:NavigateTo({ name = "Far Dungeon", map = 1413, x = 0.88, y = 0.9 })
local jb = rawget(_G, "MythicScoreboardJump")
check("hearth step: the button", jb and jb:IsShown() and MS:NavigationJump() ~= nil)
check("hearth step: uses the hearthstone", jb and jb:GetAttribute("type") == "item" and jb:GetAttribute("item") == "item:6948",
    jb and tostring(jb:GetAttribute("type")))
check("hearth step: no arrow", arrow.arrow and not arrow.arrow:IsShown())
spells[556] = true; M.now = M.now + 5; MS:UpdateArrow()
check("Astral Recall step: casts it", jb:GetAttribute("type") == "spell" and jb:GetAttribute("spell") == 556,
    tostring(jb:GetAttribute("type")))
-- In a fight: left as it is (the game won't allow a change), set right after.
local fighting = true
InCombatLockdown = function() return fighting end
local blockedBefore = M.blocked or 0
MS:StopNavigation()
check("combat: nothing blocked", (M.blocked or 0) == blockedBefore, M.blocked)
check("combat: the button stays for now", jb:IsShown())
fighting = false
M.Fire("PLAYER_REGEN_ENABLED")
check("after the fight: hidden", not jb:IsShown())
InCombatLockdown = function() return false end
-- A step on foot: the arrow again, no button.
MS:NavigateTo({ name = "Far Dungeon", map = 1413, x = 0.88, y = 0.9 })
bags[6948], spells[556] = 0, nil
M.now = M.now + 5; MS:UpdateArrow()
check("on foot: no button", not jb:IsShown() and arrow.arrow:IsShown())
MS:StopNavigation()
bags[6948] = 1
cooldown[556], spells[556] = nil, nil
bind = "Their Inn"
check("the other side's inn: not yours", hows(MS:PlanRoute(from(), goal)) == "run")
MS.ForeverData.INNS[1].aka = { "Farside" }
bind = "Farside"
check("an inn by its other name: used", hows(MS:PlanRoute(from(), goal)) == "hearth,run", hows(MS:PlanRoute(from(), goal)))
MS.ForeverData.INNS[1].aka = nil
bind = "Somewhere Unknown"
check("an inn not in the list: not used", hows(MS:PlanRoute(from(), goal)) == "run")
-- Set close to where you are: nothing saved, so not spent.
bind = "Nearby Inn"
check("hearthstone that saves nothing: not used", hows(MS:PlanRoute(from(), goal)) == "run")
bind = "Farside Inn"
check("saving under three minutes: kept", hows(MS:PlanRoute(from(), { c = KALIMDOR, x = 0.2, y = 0.2 })) == "run")
-- A teleport: across the sea with no boat.
MS.ForeverData.TRANSPORTS = {}
local over = { c = EK, x = 0.5, y = 0.5 }
check("no way across", MS:PlanRoute(from(), over) == nil)
spells[3567] = true
check("a teleport never cast: where it lands not known yet", MS:PlanRoute(from(), over) == nil)
-- Cast once: where you arrive is kept.
local home = here
local function arrive(map, spot)
    M.RunTimers(1)                               -- (still casting, still here)
    playerMap, here = map, spot
    M.RunTimers(1)
end
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 3567)
arrive(1420, { 0.5, 0.52 })
local spot = MythicScoreboardAccountDB.landings.spells[3567]
check("teleport: landing kept", spot and spot.c == EK and math.abs(spot.y - 0.52) < 1e-6)
playerMap, here = 1413, home
legs = MS:PlanRoute(from(), over)
check("a teleport you know: used", hows(legs) == "teleport,run", hows(legs))
rawset(_G, "IsUsableSpell", function() return false end)   -- (no rune)
check("a teleport you can't cast: not used", MS:PlanRoute(from(), over) == nil)
rawset(_G, "IsUsableSpell", nil)
-- On the arrow and the map: a step to read, no arrow to follow, no line.
MS:NavigateTo({ name = "Over There", map = 1420, x = 0.5, y = 0.5 })
local text = arrow.lastStep
check("step text names the teleport", text and text:find("Gamma City", 1, true), text)
local drawn = MS:RouteOnMap(EK)
check("map: no line for the teleport", drawn and #drawn.lines == 1, drawn and #drawn.lines)
MS:StopNavigation()
bind, bags, spells = nil, {}, {}

-- ── Learned from the game: inns, flight masters, for the whole account ──
MythicScoreboardAccountDB.landings = nil
MS.ForeverData.INNS = {}
playerMap, here = 1413, { 0.12, 0.12 }
bind, bags[6948] = "Farside Inn", 1
check("an inn never landed at: not used", hows(MS:PlanRoute(from(), goal)) == "run")
-- Someone else's spell: nothing.
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-2", 8690)
M.RunTimers(3)
check("someone else hearthing: nothing kept", next(MythicScoreboardAccountDB.landings and MythicScoreboardAccountDB.landings.inns or {}) == nil)
-- The hearthstone, cast and landed.
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 8690)
arrive(1413, { 0.85, 0.88 })
local inn = MythicScoreboardAccountDB.landings.inns["Farside Inn"]
check("hearthed: the inn kept", inn and inn.c == KALIMDOR and math.abs(inn.x - 0.85) < 1e-6)
playerMap, here = 1413, { 0.12, 0.12 }
check("hearthed once: used from then on", hows(MS:PlanRoute(from(), goal)) == "hearth,run", hows(MS:PlanRoute(from(), goal)))
-- A cast that never goes anywhere (interrupted after all): nothing kept.
bind = "Stayed Inn"
M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 8690)
M.RunTimers(95)
check("never left: nothing kept", MythicScoreboardAccountDB.landings.inns["Stayed Inn"] == nil)
-- Binding at an innkeeper: where you stand, until a landing says better.
here = { 0.3, 0.3 }
M.Fire("HEARTHSTONE_BOUND")
check("bound: the spot kept", MythicScoreboardAccountDB.landings.inns["Stayed Inn"] ~= nil)
bind = "Farside Inn"; here = { 0.2, 0.2 }
M.Fire("HEARTHSTONE_BOUND")
check("bound again: a real landing kept", math.abs(MythicScoreboardAccountDB.landings.inns["Farside Inn"].x - 0.85) < 1e-6)
bind, bags = nil, {}

-- Flight maps: an alt that never opened one uses where yours stand.
local realNodes = C_TaxiMap.GetAllTaxiNodes
C_TaxiMap.GetAllTaxiNodes = function()
    return { { name = "Delta, Somewhere", position = V(0.4, 0.4), state = 1 },
             { name = "Epsilon", position = V(0.6, 0.6), state = 2 } }
end
playerMap = 1413
M.Fire("TAXIMAP_OPENED")
C_TaxiMap.GetAllTaxiNodes = realNodes
local acc = MythicScoreboardAccountDB
check("flight map: spots kept for the account", acc.flightSpots and acc.flightSpots.Horde and #acc.flightSpots.Horde[KALIMDOR] == 2)
MythicScoreboardDB.flights = nil                 -- (the alt)
local fm = MS:FlightMasters(KALIMDOR)
check("alt: your flight masters' spots", #fm == 2 and fm[1].name == "Delta" and fm[2].known == true, #fm)
side = "Alliance"
check("other side: not yours", #MS:FlightMasters(KALIMDOR) == 0, #MS:FlightMasters(KALIMDOR))
side = "Horde"

-- /sb dumptravel: what the game lists, saved.
C_TaxiMap.GetTaxiNodesForMap = function(id)
    if id == KALIMDOR then return { { name = "Alpha", position = V(0.1, 0.1), faction = 1 } } end
    return {}
end
MS.ForeverData.FLIGHT_MASTERS = { { "Alpha", map = 1413, x = 0.1, y = 0.1, side = "Horde" } }
MS:DumpTravel()
local dump = acc.travelDump
check("dump: the game's list", dump and dump.taxi[KALIMDOR] and dump.taxi[KALIMDOR][1].name == "Alpha" and dump.taxi[KALIMDOR][1].faction == 1)
check("dump: landings and spots", dump and dump.landings == acc.landings and dump.flightSpots == acc.flightSpots)
check("dump: said so", M.printed[#M.printed]:find("dumptravel: 1 flight", 1, true), M.printed[#M.printed])

-- ── The game's own flight list: used live ──────────────────────────────────
MythicScoreboardDB.flights, MythicScoreboardAccountDB.flightSpots = nil, nil
C_TaxiMap.GetTaxiNodesForMap = function(id)
    if id ~= KALIMDOR then return {} end
    return { { name = "Crossroads, The Barrens", position = V(0.53, 0.54), faction = 1 },
             { name = "Astranaar, Ashenvale", position = V(0.47, 0.40), faction = 2 },
             { name = "Ratchet, The Barrens", position = V(0.56, 0.55), faction = 0 },
             { name = "zzOLDPowderfuse Port, Riverglades", position = V(0.56, 0.55), faction = 0 } }
end
local live = MS:FlightMasters(KALIMDOR)
local names = {}
for _, f in ipairs(live) do names[#names + 1] = f.name end
table.sort(names)
check("game's list: your side and both sides', no old ones", table.concat(names, ",") == "Crossroads,Ratchet", table.concat(names, ","))
check("game's list: exact spots", math.abs(live[1].x - 0.53) < 1e-6 or math.abs(live[2].x - 0.53) < 1e-6)
side = "Alliance"
names = {}
for _, f in ipairs(MS:FlightMasters(KALIMDOR)) do names[#names + 1] = f.name end
table.sort(names)
check("game's list: the Alliance's", table.concat(names, ",") == "Astranaar,Ratchet", table.concat(names, ","))
side = "Horde"
-- Your own flight map still comes first (it knows which ones you have).
C_TaxiMap.GetAllTaxiNodes = function()
    return { { name = "Crossroads", position = V(0.53, 0.54), state = 1 } }
end
M.Fire("TAXIMAP_OPENED")
check("your flight map first", #MS:FlightMasters(KALIMDOR) == 1)
C_TaxiMap.GetTaxiNodesForMap = nil

for _, p in ipairs(M.printed) do if p:find("error") then check("no errors", false, p) end end
io.stdout:write(("travel_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

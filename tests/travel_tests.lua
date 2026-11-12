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
check("in the air", arrow.lastStep == "Flying to Beta", arrow.lastStep)
check("in the air: the arrow to where you land", arrow.arrow._shown)
-- A /reload in the air: the same dungeon, no route yet. The flight's kept.
check("in the air: the flight kept", MythicScoreboardDB.navFlying and MythicScoreboardDB.navFlying.name == "Beta")
here = { 0.5, 0.5 }
MS:NavigateTo({ name = "Razorfen Kraul", map = 1413, x = 0.88, y = 0.9 })
check("reload in the air: still flying to Beta", arrow.lastStep == "Flying to Beta", arrow.lastStep)
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

for _, p in ipairs(M.printed) do if p:find("error") then check("no errors", false, p) end end
io.stdout:write(("travel_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

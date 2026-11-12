-- usage: lua5.1 route_audit_tests.lua DIR TOC   (Forever: real routes, real flight paths)
-- Kalimdor's flight masters where the game says they are (a level 40 Horde
-- character's flight map), and the routes players actually take.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if not MS.PlanRoute then
    io.stdout:write("route_audit_tests: retail has no route planner, skipped\n")
    os.exit(0)
end
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4)

local KALIMDOR, BARRENS, DUSTWALLOW, ORGRIMMAR, NEEDLES = 1414, 1413, 1445, 1454, 1441
local W, H = 36800, 24533                                  -- Kalimdor, in yards
local function V(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
rawset(_G, "CreateVector2D", V)
-- The Barrens on Kalimdor (from its flight masters' two positions).
local B = { 0.3927, 0.3927 + 0.275, 0.4564, 0.4564 + 0.275 }
C_Map.GetMapInfo = function(id)
    if id == KALIMDOR then return { mapType = 2, name = "Kalimdor" } end
    if id == BARRENS or id == DUSTWALLOW or id == ORGRIMMAR or id == NEEDLES then return { mapType = 3, parentMapID = KALIMDOR } end
end
C_Map.GetMapRectOnMap = function(zone, map)
    if zone == BARRENS and map == KALIMDOR then return B[1], B[2], B[3], B[4] end
end
C_Map.GetWorldPosFromMapPos = function(_, pos) return 0, V(H / 2 - pos.y * H, W / 2 - pos.x * W) end
-- Dustwallow: east of the Barrens' south; Thousand Needles: south of the
-- Barrens; Orgrimmar: around its flight master.
C_Map.GetMapInfoAtPosition = function(_, x, y)
    if y > B[4] and x < 0.537 then return { mapID = NEEDLES } end
    if x >= 0.537 and y >= 0.60 and y <= 0.76 then return { mapID = DUSTWALLOW } end
    if math.abs(x - 0.581) < 0.02 and math.abs(y - 0.4534) < 0.02 then return { mapID = ORGRIMMAR } end
    return { mapID = BARRENS }
end
local spot = { 0, 0 }
C_Map.GetBestMapForUnit = function() return BARRENS end
C_Map.GetPlayerMapPosition = function() return V(spot[1], spot[2]) end
rawset(_G, "UnitFactionGroup", function() return "Horde" end)

local function N(name, x, y) return { name = name, x = x, y = y, known = true } end
MythicScoreboardDB.flights = { [KALIMDOR] = {
    N("Thunder Bluff", 0.4630, 0.5705), N("Orgrimmar", 0.5810, 0.4534), N("Crossroads", 0.5343, 0.5397),
    N("Sun Rock Retreat", 0.4355, 0.4823), N("Freewind Post", 0.5294, 0.7422), N("Shadowprey Village", 0.3751, 0.5938),
    N("Gadgetzan", 0.5665, 0.8091), N("Camp Mojache", 0.4584, 0.7019), N("Brackenwall Village", 0.5410, 0.6500),
    N("Zoram'gar Outpost", 0.4367, 0.3842), N("Splintertree Post", 0.5324, 0.4279), N("Camp Taurajo", 0.5149, 0.6188),
    N("Ratchet", 0.5663, 0.5582),
} }

local function Dungeon(name)
    for _, e in ipairs(MS.ForeverData.ENTRANCES) do
        if e[1] == name then
            local c, x, y = MS:OnContinent(e.map, e.x, e.y)
            return { c = c, x = x, y = y, name = name }
        end
    end
end
local function LastFlight(from, to)
    local legs = MS:PlanRoute({ c = KALIMDOR, x = from[1], y = from[2] }, to)
    local last
    for _, l in ipairs(legs or {}) do if l.how == "fly" then last = l.to.name end end
    return last, legs
end
local function Show(legs)
    local t = {}
    for _, l in ipairs(legs or {}) do t[#t + 1] = l.how .. " " .. (l.to.name or l.to.kind) end
    return table.concat(t, ", ")
end

local ORG, XROADS = { 0.5810, 0.4535 }, { 0.5343, 0.5398 }
for _, d in ipairs({ "Razorfen Kraul", "Razorfen Downs" }) do
    local goal = Dungeon(d)
    for where, from in pairs({ Orgrimmar = ORG, Crossroads = XROADS }) do
        local last, legs = LastFlight(from, goal)
        check(d .. " from " .. where .. ": fly to Camp Taurajo", last == "Camp Taurajo", Show(legs))
    end
end
-- Wailing Caverns from the Crossroads: just run, it's next door.
local _, legs = LastFlight(XROADS, Dungeon("Wailing Caverns"))
check("Wailing Caverns from the Crossroads: run", Show(legs):match("^run [^,]*$") ~= nil, Show(legs))

-- Eastern Kingdoms: in Swamp of Sorrows by Stonard, not learned yet. Going
-- north: run to Stonard (talking to it learns it) and fly, not the long run
-- to Grom'gol.
local EK = 1415
local mapInfo = C_Map.GetMapInfo
C_Map.GetMapInfo = function(id)
    if id == EK then return { mapType = 2, name = "Eastern Kingdoms" } end
    return mapInfo(id)
end
MythicScoreboardDB.flights[EK] = {
    N("The Sepulcher", 0.4109, 0.2978), N("Undercity", 0.4469, 0.2513), N("Tarren Mill", 0.4790, 0.3182),
    N("Hammerfall", 0.5539, 0.3572), N("Booty Bay", 0.4401, 0.9337), N("Grom'gol", 0.4504, 0.8472),
    N("Kargath", 0.5165, 0.6009),
    { name = "Stonard", x = 0.5477, y = 0.7638, known = false },
    { name = "Flame Crest", x = 0.5167, y = 0.6380, known = false },
}
legs = MS:PlanRoute({ c = EK, x = 0.557, y = 0.756 }, { c = EK, x = 0.447, y = 0.24, name = "north" })
check("by Stonard, not learned: start there", legs and legs[1].to.name == "Stonard" and legs[2].how == "fly", Show(legs))
C_Map.GetMapInfo = mapInfo

io.stdout:write(("route_audit_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

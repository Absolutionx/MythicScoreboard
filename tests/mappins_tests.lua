-- usage: lua5.1 mappins_tests.lua DIR TOC   (Forever: dungeon entrances on the world map)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if not MS.EntrancePins then
    io.stdout:write("mappins_tests: retail has its own entrances, skipped\n")
    os.exit(0)
end

-- Every entrance: a known dungeon (or levels of its own), a map, a spot on it.
for _, e in ipairs(MS.ForeverData.ENTRANCES) do
    local def = MS.FOREVER_DUNGEONS[e[1]]
    check("entrance " .. e[1] .. ": known", def ~= nil or e.levels ~= nil)
    check("entrance " .. e[1] .. ": on a map", type(e.map) == "number" and e.x > 0 and e.x < 1 and e.y > 0 and e.y < 1)
end

-- Tirisfal: one marker for the four Scarlet Monastery wings, and Ruins of Lordaeron.
local pins = MS:EntrancePins(1420)
check("Tirisfal: two markers", #pins == 2, #pins)
local sm
for _, p in ipairs(pins) do if #p.dungeons == 4 then sm = p end end
check("Tirisfal: the four wings share one", sm ~= nil)
local lines = sm and MS:EntrancePinLines(sm) or {}
check("SM tooltip: a line per wing", #lines == 4, #lines)
check("SM tooltip: levels", lines[1] and lines[1][2]:find("^Levels %d+%-%d+$") ~= nil, lines[1] and lines[1][2])
check("A new dungeon's own levels", MS:EntrancePinLines(MS:EntrancePins(1447)[1])[1][2] == "Levels 55-60")
check("No markers on a map without dungeons", #MS:EntrancePins(1411) == 0)

-- The continent: zones placed by where they sit on it.
C_Map.GetMapRectOnMap = function(zone, map)
    if map == 1415 and zone == 1420 then return 0.4, 0.6, 0.1, 0.3 end
end
pins = MS:EntrancePins(1415)
check("Eastern Kingdoms: Tirisfal's markers", #pins == 2, #pins)
check("Eastern Kingdoms: placed in Tirisfal", pins[1] and math.abs(pins[1].x - (0.4 + 0.826 * 0.2)) < 1e-6
    or pins[2] and math.abs(pins[2].x - (0.4 + 0.826 * 0.2)) < 1e-6)
C_Map.GetMapRectOnMap = nil

for _, p in ipairs(M.printed) do if p:find("error") then check("no errors", false, p) end end
io.stdout:write(("mappins_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

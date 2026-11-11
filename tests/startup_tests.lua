-- usage: lua5.1 startup_tests.lua DIR TOC
-- Loading the addon in unusual moments: in combat, and with a handler that
-- errors. Its own file, because loading happens once per process.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end

-- 1. /reload in the middle of a pull, with a run in progress saved.
local inCombat = true
InCombatLockdown = function() return inCombat end
MythicScoreboardDB = { runs = {}, activeRun = { _active = true, dungeonName = "Ragefire Chasm",
    keystoneLevel = 0, players = {}, bosses = {}, _wallClockStart = time() - 300, _savedAt = time() } }
M.instance = { "Ragefire Chasm", "party", 1 }
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
M.Fire("ADDON_LOADED", "MythicScoreboard")
check("loaded in combat: the saved run is picked up", MS.currentRun ~= nil)
inCombat = false
M.Fire("PLAYER_REGEN_ENABLED"); M.RunTimers(4)
M.Fire("PLAYER_LEAVING_WORLD")
check("loaded in combat: the run is still saved after a loading screen",
    MythicScoreboardDB.activeRun ~= nil)

-- 2. A handler that errors is reported, and the next event still works.
local real = MS.BossKill
MS.BossKill = function() error("boom") end
local ok, err = pcall(M.Fire, "ENCOUNTER_END", 1, "Taragaman", 1, 5, 1)
check("an erroring handler doesn't throw into the game", ok, err)
local said = false
for _, line in ipairs(M.printed) do if line:find("ENCOUNTER_END") and line:find("boom") then said = true end end
check("an erroring handler is reported in chat", said)
MS.BossKill = real
local before = #(MS.currentRun and MS.currentRun.bosses or {})
pcall(M.Fire, "ENCOUNTER_START", 2, "Bazzalan")
M.Fire("ENCOUNTER_END", 2, "Bazzalan", 1, 5, 1)
check("the next event is handled as usual", MS.currentRun and #MS.currentRun.bosses > before)

io.stdout:write(string.format("startup_tests: %d passed, %d failed\n", passes, fails))
os.exit(fails == 0 and 0 or 1)

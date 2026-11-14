-- usage: lua5.1 startonpull_tests.lua DIR TOC   ("Start the clock on the first pull")
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.startOnPull = true                       -- the setting's default, as players get it
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function zone(inst, levels)
    M.instance = inst
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.RunTimers(levels or 8)
end
local RFC, WORLD = { "Ragefire Chasm", "party", 1 }, { "Orgrimmar", "none", 0 }
local inCombat = {}
UnitAffectingCombat = function(unit) return inCombat[unit] or false end
local function reset()
    M.timers = {}
    MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
    MS.currentRun, MS.inDungeon, MS._abandonedIn = nil, false, nil
    M.dead = {}; M.groupSize = 5
    M.instance = WORLD
    inCombat = {}
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
end
local function clock() return MS:GetRunDuration(MS.currentRun) end

-- On by default.
reset()
check("on by default", MS:GetStartOnPull() == true)

-- In the door, waiting for the group: the clock stays at 0.
zone(RFC)
check("run starts", MS:RunState() == "active")
M.Advance(120)
check("waiting: 0:00", clock() == 0, clock())

-- The pull: the clock starts from it.
M.Fire("PLAYER_REGEN_DISABLED")
check("pulled: no longer waiting", not MS.currentRun._waitingForPull)
M.Advance(30)
check("pulled: counts from the pull", math.abs(clock() - 30) < 1, clock())

-- Someone else pulls (you're behind): the clock starts too.
reset(); zone(RFC); M.Advance(60)
inCombat.party2 = true
M.Fire("UNIT_FLAGS", "party2")
M.Advance(10)
check("a group member's pull starts it", math.abs(clock() - 10) < 1, clock())

-- Someone still out in the world fighting their way here: not them.
-- (Forever's dungeons have no map; out in the world, everyone has a zone's.)
local bestMap = C_Map.GetBestMapForUnit
local mapInfo = C_Map.GetMapInfo
reset(); zone(RFC)
C_Map.GetBestMapForUnit = function(u) if u == "party3" then return 1454 end end
inCombat.party3 = true
M.Fire("UNIT_FLAGS", "party3")
M.Advance(10)
check("someone outside: not them", clock() == 0, clock())
check("someone outside: still waiting", MS.currentRun._waitingForPull)
-- Near you (in range, or close enough to be drawn): with you, whatever the
-- maps say. Farther: only on the same map (another wing of the same place
-- isn't).
C_Map.GetBestMapForUnit = function(u) return ({ player = 900, party1 = 901, party2 = 900, party3 = 1454 })[u] end
local near = {}
rawset(_G, "UnitInRange", function(u) return near[u] == "range" end)
rawset(_G, "UnitIsVisible", function(u) return near[u] ~= nil end)
check("far, same map: with you", MS:InDungeonWithMe("party2"))
check("far, another wing or floor: not", not MS:InDungeonWithMe("party1"))
check("far, a zone outside: not", not MS:InDungeonWithMe("party3"))
near.party1 = "range"
check("in range (the lit party frame): with you", MS:InDungeonWithMe("party1"))
near.party1 = "seen"
check("close enough to be drawn: with you", MS:InDungeonWithMe("party1"))
reset(); zone(RFC)
near.party1 = "range"
inCombat.party1 = true
M.Fire("UNIT_FLAGS", "party1")
M.Advance(10)
check("a nearby member's pull starts it", math.abs(clock() - 10) < 1, clock())
rawset(_G, "UnitInRange", nil); rawset(_G, "UnitIsVisible", nil)
C_Map.GetBestMapForUnit, C_Map.GetMapInfo = bestMap, mapInfo
inCombat = {}

-- Nameplates and other units don't.
reset(); zone(RFC)
inCombat.nameplate3 = true
M.Fire("UNIT_FLAGS", "nameplate3")
M.Advance(10)
check("not a nameplate", clock() == 0, clock())

-- A boss fight starts it.
reset(); zone(RFC); M.Advance(20)
M.Fire("ENCOUNTER_START", 1, "Oggleflint", 1, 5)
M.Advance(5)
check("a boss pull starts it", math.abs(clock() - 5) < 1, clock())

-- Already fighting at the door: straight away.
reset()
inCombat.player = true
zone(RFC)
check("in combat at the door: started", not MS.currentRun._waitingForPull)
inCombat.player = nil

-- Left before anyone pulled: nothing saved, nothing paused.
reset(); zone(RFC); M.Advance(30)
zone(WORLD)
check("left unpulled: no run", MS:RunState() == "none", MS:RunState())
check("left unpulled: not in history", #MythicScoreboardDB.runs == 0, #MythicScoreboardDB.runs)
zone(RFC)
check("back in: a new run waits", MS:RunState() == "active" and MS.currentRun._waitingForPull)

-- Abandoned before a pull: not saved.
check("abandon unpulled", MS:AbandonRun() == true and #MythicScoreboardDB.runs == 0, #MythicScoreboardDB.runs)

-- A /reload while waiting: still waiting.
reset(); zone(RFC); M.Advance(30)
MS:FlushSave()
local saved = MythicScoreboardDB.activeRun
check("saved while waiting: waits", saved and saved._waitingForPull)
MS.currentRun = nil; MS:SetRunState("none")
MythicScoreboardDB.activeRun = saved
MS:RestoreCurrentRun()
check("restored: still 0:00", MS.currentRun and clock() == 0, MS.currentRun and clock())

-- The saved run doesn't keep the flag.
M.Fire("PLAYER_REGEN_DISABLED"); M.Advance(40)
MS:AbandonRun()
check("history: no waiting flag", MythicScoreboardDB.runs[1] and MythicScoreboardDB.runs[1]._waitingForPull == nil)
check("history: the time from the pull", MythicScoreboardDB.runs[1] and math.abs(MythicScoreboardDB.runs[1].duration - 40) < 1,
    MythicScoreboardDB.runs[1] and MythicScoreboardDB.runs[1].duration)

-- Off: the clock starts at the door, as before.
reset(); MS:SetStartOnPull(false); zone(RFC); M.Advance(50)
check("off: from the door", math.abs(clock() - 50) < 2, clock())

io.stdout:write(("startonpull_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

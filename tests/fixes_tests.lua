-- usage: lua5.1 fixes_tests.lua DIR TOC
-- The 2.7 review fixes: clear detection from the journal, death recaps,
-- hidden GUIDs, one death clock, history clearing, personal bests, settings.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
-- Loot needs to tell gear from other items.
C_Item.GetItemInfoInstant = function(link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    if id then return id, "Armor", "Plate", "INVTYPE_CHEST", 135274, 4, 4 end
end
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local forever = MS.FLAVOR == "forever"
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function S(v) return { __secret = true, v = v } end
local clock = 1800000000
time = function() return clock end
local function wait(s) M.now = M.now + s; clock = clock + s end
local WORLD = { "Orgrimmar", "none", 0 }
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local function reset()
    M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
    MS.currentRun, MS.inDungeon, MS.displayRun = nil, false, nil
    M.dead = {}; M.instance = WORLD; M.printed = {}
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
end
local function kill(name, fight)
    M.Fire("ENCOUNTER_START", 1, name); wait(fight or 30)
    M.Fire("ENCOUNTER_END", 1, name, 1, 5, 1); M.RunTimers(4)
end
local me = forever and "Jay-Breezy" or "Jay"

-- 1. Retail: a dungeon Seasons.lua doesn't list is cleared from the journal's
--    boss list for the instance the player is in (2.6 asked with the key's
--    map ID, nil outside Mythic+, and never cleared these).
if not forever then
    local selected = false
    local saved = { EJ_GetInstanceForMap, EJ_GetEncounterInfoByIndex, EJ_SelectInstance }
    EJ_GetInstanceForMap = function(map) return map == 1 and 777 or 0 end
    EJ_GetEncounterInfoByIndex = function(i, inst)
        if inst == 777 and i <= 3 then return "Boss " .. i, "", 100 + i, 0, 0, 0, 2000 + i end
    end
    EJ_SelectInstance = function() selected = true end
    reset(); zone({ "The Stonevault", "party", 2 })
    check("journal: run started", MS.currentRun ~= nil)
    selected = false                       -- (the portrait scan on zone-in may select it)
    kill("Boss 1"); kill("Boss 2")
    check("journal: not cleared at 2 of 3", MS.currentRun and not MS.currentRun.completed)
    kill("Boss 3")
    check("journal: cleared at 3 of 3", MS.currentRun and MS.currentRun.completed == true)
    check("journal: selection left alone", not selected)
    zone(WORLD)
    check("journal: saved as cleared", MythicScoreboardDB.runs[1] and MythicScoreboardDB.runs[1].completed == true)
    EJ_GetInstanceForMap, EJ_GetEncounterInfoByIndex, EJ_SelectInstance = saved[1], saved[2], saved[3]

    -- Settings: retail has no clear rule to choose.
    check("retail: no clear rule", MS:GetClearRule() == nil)
end

-- 2. Death recaps: each death gets its own hits, copied when it happens.
reset(); zone({ "Ragefire Chasm", "party", 1 })
local recaps = {
    [11] = { { spellName = "Fireball", caster = "Taragaman", amount = 900, overkill = 0 },
             { spellName = "Uppercut", caster = "Taragaman", amount = 1200, overkill = 300 } },
    [12] = { { spellName = "Shadow Bolt", caster = "Jergosh", amount = 800, overkill = 50 } },
}
DeathRecap_GetEvents = function(id) return recaps[id] end
local function meterDeaths(n, recapID)
    M.meter = { [0] = { duration = 100, combatSources = {} }, [2] = { combatSources = {} },
                [5] = { combatSources = {} }, [6] = { combatSources = {} }, [7] = { combatSources = {} },
                [8] = { combatSources = {} },
                [9] = { combatSources = { { name = me, sourceGUID = "Player-1-AAA", totalAmount = n,
                                            isLocalPlayer = true, deathRecapID = recapID } } } }
end
local p = MS:PlayerByName(me)
wait(60); M.dead.player = true; M.Tick()           -- death poll sees it
meterDeaths(1, 11); MS:SnapshotFromDamageMeter()
M.dead.player = nil; M.Tick()
wait(120); M.dead.player = true; M.Tick()
meterDeaths(2, 12); MS:SnapshotFromDamageMeter()
check("recap: two deaths", p.deaths == 2, p.deaths)
local d1, d2 = p.deathEvents[1], p.deathEvents[2]
check("recap: first death keeps its own killing blow", d1.events and MS.KillingBlow(d1.events).spellName == "Uppercut")
check("recap: second death its own", d2.events and MS.KillingBlow(d2.events).spellName == "Shadow Bolt")
local saved = MS:SerializeRun(MS.currentRun)
local sp = saved.players[MS.ShortName(me)]
check("recap: no recap ID saved", sp.deathRecapID == nil and sp._lastRecapID == nil)
check("recap: hits saved", sp.deathEvents[1].events and #sp.deathEvents[1].events == 2)
DeathRecap_GetEvents = function() return nil end

-- 3. Hidden values: the meter's isLocalPlayer and an INSPECT_READY GUID.
meterDeaths(2, 13)
M.meter[9].combatSources[1].isLocalPlayer = S(true)
local ok = pcall(MS.SnapshotFromDamageMeter, MS)
check("hidden isLocalPlayer: no error", ok)
MS:PopulateAll(); M.RunTimers(2)
ok = pcall(function() M.Fire("INSPECT_READY", S("Player-1-BBB")) end)
check("hidden inspect GUID: no error", ok)

-- 4. One clock: a death polled while the world timer says something else
--    is timed like everything else in the run.
local gw = GetWorldElapsedTime
GetWorldElapsedTime = function() return 0, 5 end
M.dead.party1 = true; M.Tick()
local a = MS:PlayerByName("Akasha")
local dt = a.deathEvents[#a.deathEvents].time
check("death clock: run time, not the world timer", math.abs(dt - MS:GetRunDuration()) < 0.01, dt)
GetWorldElapsedTime = gw

-- 5. Clearing history while a run is paused keeps the run.
zone(WORLD)
check("paused", MS:RunState() == "paused", MS:RunState())
MS:ClearHistory()
check("clear history: paused run kept", MS:RunState() == "paused" and MS.currentRun ~= nil)
check("clear history: history empty", #MythicScoreboardDB.runs == 0)
MS:ClosePausedRun()

-- 6. Settings: a lower history limit drops the oldest runs at once.
MythicScoreboardDB.runs = { {}, {}, {}, {}, {} }
MS:SetHistoryLimit(3)
check("history limit trims", #MythicScoreboardDB.runs == 3, #MythicScoreboardDB.runs)
check("history limit clamped", (function() MS:SetHistoryLimit(99); return MS:GetHistoryLimit() end)() == 30)

-- 7. Personal bests come from the archive.
reset()
local function key(dur)
    local run = MS.NewRunData()
    run.dungeonName, run.keystoneLevel, run.completed, run.inTime = "Skyreach", 10, true, true
    run.duration, run._wallClockStart = dur, clock
    run.players[MS.ShortName(me)] = MS.NewPlayerStats(MS.ShortName(me), "SHAMAN", "Player-1-AAA")
    MS:SetRunState("finishing", run)
    clock = clock + 3600
    MS:CommitRun({})
    return MythicScoreboardDB.runs[1]
end
local first = key(1500)
check("pb: first clear announced", M.printed[#M.printed]:find("First recorded clear") ~= nil, M.printed[#M.printed])
check("pb: first is best", MS:IsPersonalBest(first))
local slower = key(1600)
check("pb: slower is not", not MS:IsPersonalBest(slower))
local faster = key(1400)
check("pb: faster announced", M.printed[#M.printed]:find("New personal best") ~= nil, M.printed[#M.printed])
check("pb: faster is best", MS:IsPersonalBest(faster) and not MS:IsPersonalBest(first))

-- 8. Run status: one answer everywhere.
check("status: abandoned", MS:RunStatus({ completed = false }) == "abandoned")
check("status: finished", MS:RunStatus({ finishedOnLeave = true }) == "finished")
check("status: timed key", MS:RunStatus({ completed = true, inTime = true, keystoneLevel = 5 }) == "inTime")
check("status: archive cleared", MS:ArchiveStatus({ cleared = true }) == "cleared")

-- 9. Retail key: CHALLENGE_MODE_COMPLETED has no values; the result and
--    the time lost to deaths come from the game.
if not forever then
    reset()
    local map = 2526
    C_ChallengeMode = {
        GetActiveChallengeMapID = function() return map end,
        GetActiveKeystoneInfo = function() return 10, { 9, 10 }, true end,
        GetMapInfo = function() return { name = "Skyreach" } end,
        GetMapUIInfo = function() return "Skyreach", map, 1680 end,
        GetChallengeCompletionInfo = function() return { time = 1500250, onTime = true, level = 10 } end,
        GetDeathCount = function() return 2, 30 end,
        GetDungeonScoreRarityColor = function(score) return score >= 2500 and { r = 1, g = 0.5, b = 0 } or { r = 0, g = 0.7, b = 1 } end,
        GetSpecificDungeonOverallScoreRarityColor = function() return { r = 1, g = 0.5, b = 0 } end,
    }
    zone({ "Skyreach", "party", 8 })
    M.Fire("CHALLENGE_MODE_START", map); M.RunTimers(3)
    local run = MS.currentRun
    check("key: time limit from the map", run and run.keystoneTimeLimit == 1680, run and run.keystoneTimeLimit)
    M.Fire("CHALLENGE_MODE_COMPLETED"); M.RunTimers(6)
    local saved = MythicScoreboardDB.runs[1]
    check("key: saved", saved and saved.keystoneLevel == 10)
    check("key: official time", saved and math.abs(saved.duration - 1500.25) < 0.01, saved and saved.duration)
    check("key: in time", saved and saved.inTime == true)
    check("key: time lost from the game", saved and saved.deathPenaltySeconds == 30, saved and saved.deathPenaltySeconds)

    -- Loot from the chest, after the run was saved, reaches the Stats page.
    local item = "|cnIQ4:|Hitem:12345::::::::80:::::|h[Chest Thing]|h|r"
    MS:RecordLoot(me, item, "chat")
    local a = MS:ArchiveRuns()
    local e = a[#a]
    check("late loot: in history", saved.players[MS.ShortName(me)].loot and #saved.players[MS.ShortName(me)].loot == 1)
    check("late loot: in stats", e and e.loot and #e.loot == 1, e and e.loot and #e.loot)

    -- Rating colours use the overall-rating scale.
    local r, g = MS.UI.ScoreColor(1800)
    check("rating colour: overall scale", r == 0 and g == 0.7, tostring(r) .. "," .. tostring(g))
    C_ChallengeMode = nil
end

-- 10. Two players with one name (retail, another realm) stay two rows.
if not forever then
    reset()
    local saved1 = M.roster.party1
    M.roster.party1 = { name = "Jay", guid = "Player-2-ZZZ", class = "MAGE", level = 80 }
    MS:InvalidateGroupUnits()
    zone({ "Ragefire Chasm", "party", 1 })
    local n, keys = 0, {}
    for k in pairs(MS.currentRun.players) do n = n + 1; keys[#keys + 1] = k end
    check("same name: five rows", n == 5, table.concat(keys, ","))
    local me1, other = MS:PlayerForUnit("player"), MS:PlayerForUnit("party1")
    check("same name: kept apart", me1 and other and me1 ~= other and other.class == "MAGE",
        tostring(other and other.name))
    M.meter = { [0] = { duration = 100, combatSources = {
                    { name = "Jay", sourceGUID = "Player-1-AAA", totalAmount = 1000, isLocalPlayer = true, amountPerSecond = 0 },
                    { name = "Jay", sourceGUID = "Player-2-ZZZ", totalAmount = 3000, isLocalPlayer = false, amountPerSecond = 0 } } },
                [2] = { combatSources = {} }, [5] = { combatSources = {} }, [6] = { combatSources = {} },
                [7] = { combatSources = {} }, [8] = { combatSources = {} }, [9] = { combatSources = {} } }
    MS:SnapshotFromDamageMeter()
    check("same name: own numbers", me1.damageDone == 1000 and other.damageDone == 3000,
        me1.damageDone .. "/" .. other.damageDone)
    M.roster.party1 = saved1
    MS:InvalidateGroupUnits()
end

-- 11. "Reset meter on zone-in" off: what the meter held before doesn't count.
reset()
MythicScoreboardDB.settings.autoResetMeter = false
local function meterAt(dmg, dur, deaths)
    M.meter = { [0] = { duration = dur, combatSources = {
                    { name = me, sourceGUID = "Player-1-AAA", totalAmount = dmg, isLocalPlayer = true, amountPerSecond = dmg / dur } } },
                [2] = { combatSources = {} }, [5] = { combatSources = {} }, [6] = { combatSources = {} },
                [7] = { combatSources = {} }, [8] = { combatSources = {} },
                [9] = { combatSources = { { name = me, sourceGUID = "Player-1-AAA", totalAmount = deaths, isLocalPlayer = true } } } }
end
meterAt(50000, 600, 2)                 -- open-world numbers from before
local resets = M.meterResets or 0
zone({ "Ragefire Chasm", "party", 1 })
check("no reset: meter left alone", (M.meterResets or 0) == resets)
MS:SnapshotFromDamageMeter()
local mine = MS:PlayerForUnit("player")
check("no reset: starts at zero", mine.damageDone == 0 and mine.deaths == 0, mine.damageDone .. "/" .. mine.deaths)
meterAt(62000, 700, 3)
MS:SnapshotFromDamageMeter()
check("no reset: counts only the run", mine.damageDone == 12000, mine.damageDone)
check("no reset: rate over the run's time", math.abs(mine.dps - 120) < 0.01, mine.dps)
check("no reset: one death in the run", mine.deaths == 1, mine.deaths)
MythicScoreboardDB.settings.autoResetMeter = true

-- 12. The meter starting over mid-run doesn't hide deaths.
reset()
M.meter = {}                           -- (the mock's reset doesn't empty it)
zone({ "Ragefire Chasm", "party", 1 })
meterAt(1000, 300, 2); MS:SnapshotFromDamageMeter()
mine = MS:PlayerForUnit("player")
check("restart: two deaths", mine.deaths == 2, mine.deaths)
wait(30)
meterAt(200, 20, 1); MS:SnapshotFromDamageMeter()        -- the meter started over
check("restart: third death counted", mine.deaths == 3, mine.deaths)
check("restart: damage carried", mine.damageDone == 1200, mine.damageDone)

-- 13. Forever.
if forever then
    local SM = { "Scarlet Monastery", "party", 1 }
    -- Wings: the run is named after the wing its bosses belong to.
    reset()
    local uiMap = 302
    local gm = C_Map.GetBestMapForUnit
    C_Map.GetBestMapForUnit = function() return uiMap end
    zone(SM)
    wait(60); kill("Houndmaster Loksey")
    check("wing: named after its bosses", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Library",
        MS:RunTitle(MS.currentRun))
    check("wing: level range known", select(1, MS:ForeverLevelRange(MS.currentRun)) == 33)
    -- Leave, then walk into another wing: a new run, not the Library one.
    zone(WORLD)
    check("wing: paused on leaving", MS:RunState() == "paused", MS:RunState())
    uiMap = 304
    zone(SM)
    check("wing: other wing starts a new run", MS:RunState() == "active" and #MS.currentRun.bosses == 0
        and MythicScoreboardDB.runs[1] and MS:RunTitle(MythicScoreboardDB.runs[1]) == "Scarlet Monastery: Library")
    -- Back in the same wing after a pause: the run carries on.
    zone(WORLD); zone(SM)
    check("wing: same wing resumes", MS:RunState() == "active" and #MythicScoreboardDB.runs == 1, #MythicScoreboardDB.runs)
    C_Map.GetBestMapForUnit = gm

    -- Blackrock Spire: one instance, two halves with their own names.
    reset()
    local BRS = { "Blackrock Spire", "party", 1 }
    zone(BRS)
    zone(WORLD)
    check("brs: leaving before a kill pauses", MS:RunState() == "paused", MS:RunState())
    zone(BRS)
    wait(60); kill("Highlord Omokk")
    check("brs: lower spire named", MS:RunTitle(MS.currentRun) == "Lower Blackrock Spire", MS:RunTitle(MS.currentRun))
    check("brs: lower spire levels", select(1, MS:ForeverLevelRange(MS.currentRun)) == 55)

    -- Leaving rule: a corpse run doesn't end the run.
    reset(); MythicScoreboardDB.settings.clearRule = "leave"
    zone({ "Ragefire Chasm", "party", 1 })
    wait(60); kill("Oggleflint")
    M.dead.player = true
    zone(WORLD)
    check("leave rule: ghost outside pauses", MS:RunState() == "paused", MS:RunState())
    M.dead.player = nil
    zone({ "Ragefire Chasm", "party", 1 })
    check("leave rule: back in, same run", MS:RunState() == "active" and #MS.currentRun.bosses == 1)
    zone(WORLD)
    check("leave rule: alive and leaving finishes it", MS:RunState() == "none"
        and MythicScoreboardDB.runs[1].finishedOnLeave == true)

    -- Still fighting after the final boss: cleared all the same.
    reset(); MythicScoreboardDB.settings.clearRule = "final"
    zone({ "Ragefire Chasm", "party", 1 })
    local icl = InCombatLockdown
    InCombatLockdown = function() return true end
    for _, b in ipairs({ "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" }) do wait(60); kill(b) end
    check("in combat: cleared at the final kill", MS.currentRun.completed == true)
    InCombatLockdown = icl
end

-- 14. Logging out inside a dungeon: the time away doesn't count.
reset()
zone({ "Ragefire Chasm", "party", 1 })
wait(300)
MS:FlushSave()
local db = MythicScoreboardDB
MS.currentRun, MS.inDungeon = nil, false
M.timers = {}
wait(8 * 3600)                                       -- logged out for the night
MythicScoreboardDB = db
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(8)
local t = MS:GetRunDuration()
check("logout: offline time not counted", MS.currentRun and t >= 299 and t <= 305, t)
-- A /reload's few seconds still count.
MS:FlushSave(); MS.currentRun, MS.inDungeon = nil, false; M.timers = {}
wait(10)
MythicScoreboardDB = db
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(8)
t = MS:GetRunDuration()
check("reload: its seconds count", MS.currentRun and t >= 309 and t <= 316, t)

-- 15. Logged out inside, logged back in elsewhere: the run isn't lost.
reset()
zone({ "Ragefire Chasm", "party", 1 })
wait(400)
MS:FlushSave()
db = MythicScoreboardDB
MS.currentRun, MS.inDungeon = nil, false; M.timers = {}
wait(3 * 3600)
M.instance = WORLD
MythicScoreboardDB = db
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(2)
check("elsewhere: comes back paused", MS:RunState() == "paused", MS:RunState())
local pt = MS:GetRunDuration()
check("elsewhere: paused at the logout", pt >= 399 and pt <= 405, pt)
wait(31 * 60); M.Tick(); M.RunTimers(4)
check("elsewhere: closes and is saved", MS:RunState() == "none" and #MythicScoreboardDB.runs == 1, MS:RunState())

-- 16. Retail: a key started while a normal run is paused saves that run.
if not forever then
    reset()
    zone({ "Ragefire Chasm", "party", 1 })
    wait(200); kill("Oggleflint")
    zone(WORLD)
    check("key over paused: paused", MS:RunState() == "paused")
    local map = 2526
    C_ChallengeMode = {
        GetActiveChallengeMapID = function() return map end,
        GetActiveKeystoneInfo = function() return 5, {}, false end,
        GetMapInfo = function() return { name = "Skyreach" } end,
    }
    zone({ "Skyreach", "party", 8 })
    M.Fire("CHALLENGE_MODE_START", map); M.RunTimers(3)
    check("key over paused: key running", MS:RunState() == "active" and MS.currentRun.keystoneLevel == 5)
    check("key over paused: paused run saved", MythicScoreboardDB.runs[1] and MythicScoreboardDB.runs[1].dungeonName == "Ragefire Chasm",
        MythicScoreboardDB.runs[1] and MythicScoreboardDB.runs[1].dungeonName)
    C_ChallengeMode = nil
end

io.stdout:write(("fixes_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

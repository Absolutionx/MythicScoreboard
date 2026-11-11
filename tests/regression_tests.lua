-- usage: lua5.1 regression_tests.lua DIR TOC
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
    check("key: saved on the result's clock", saved and saved.resultClock == true)

    -- Loot from the chest, after the run was saved, reaches the Stats page.
    local item = "|cnIQ4:|Hitem:12345::::::::80:::::|h[Chest Thing]|h|r"
    MS:RecordLoot(me, item, "chat")
    local a = MS:ArchiveRuns()
    local e = a[#a]
    check("late loot: in history", saved.players[MS.ShortName(me)].loot and #saved.players[MS.ShortName(me)].loot == 1)
    check("late loot: in stats", e and e.loot and #e.loot == 1, e and e.loot and #e.loot)
    local myLoot = saved.players[MS.ShortName(me)].loot
    -- The same drop from a groupmate's copy of the addon: its item string
    -- differs (level and spec fields are the looker's), still the same drop.
    wait(2); MS:RecordLoot(me, "item:12345::::::::70:250::::", "comm")
    check("loot: same drop from the addon message not doubled", #myLoot == 1, #myLoot)
    -- Something else, still inside: counted.
    wait(20); MS:RecordLoot(me, "|cnIQ4:|Hitem:22222::::::::80:::::|h[Ring]|h|r", "chat")
    check("late loot: still inside, counted", #myLoot == 2, #myLoot)
    -- Out in the world (the Great Vault): not the run's.
    zone(WORLD); wait(30)
    MS:RecordLoot(me, "|cnIQ4:|Hitem:33333::::::::80:::::|h[Vault Gloves]|h|r", "chat")
    check("late loot: after leaving, not the run's", #myLoot == 2, #myLoot)

    -- /sb removeloot [item]: off the run and the Stats page.
    local print_ = print
    local said = {}
    print = function(s) said[#said + 1] = s end
    SlashCmdList["MYTHICSCOREBOARD"]("removeloot |cnIQ4:|Hitem:22222::::::::80:::::|h[Ring]|h|r")
    print = print_
    check("removeloot: off the run", #myLoot == 1 and myLoot[1].link:find("12345"), #myLoot)
    local a2 = MS:ArchiveRuns()
    local e2 = a2[#a2]
    local inStats = false
    for _, l in ipairs(e2.loot or {}) do if (l.l or l.i or ""):find("22222") then inStats = true end end
    check("removeloot: off the Stats page", not inStats)
    check("removeloot: says so", said[1] and said[1]:find("1") ~= nil, said[1])
    said = {}
    print = function(s) said[#said + 1] = s end
    SlashCmdList["MYTHICSCOREBOARD"]("removeloot")
    print = print_
    check("removeloot: no item, says how", said[1] and said[1]:find("Shift") ~= nil, said[1])

    -- Rating colours use the overall-rating scale.
    local r, g = MS.UI.ScoreColor(1800)
    check("rating colour: overall scale", r == 0 and g == 0.7, tostring(r) .. "," .. tostring(g))
    C_ChallengeMode = nil
end

-- A finished key on its result's clock: the game's timer jumped 15 s at each
-- death, the key's time leaves that out.
do
    local function Run()
        return { dungeonName = "Windrunner Spire", keystoneLevel = 15, completed = true, inTime = true,
            duration = 1774, deathPenaltySeconds = 30, _wallClockStart = 5000,
            bosses = { { name = "Emberdawn", pullTime = 300, killTime = 400 },
                       { name = "Restless Heart", pullTime = 1700, killTime = 1810 } },
            players = { A = { name = "A", deaths = 2, deathEvents = { { time = 350 }, { time = 1000 } },
                              interruptEvents = { 100, 1200 }, loot = { { t = 1812 } } } } }
    end
    local r = Run()
    MS.ToResultClock(r)
    local b1, b2 = r.bosses[1], r.bosses[2]
    check("result clock: before any death, unchanged", b1.pullTime == 300)
    check("result clock: after one death, 15 s less", b1.killTime == 385, b1.killTime)
    check("result clock: after two, 30 s less", b2.pullTime == 1670 and b2.killTime == 1774, b2.killTime)
    check("result clock: deaths too", r.players.A.deathEvents[1].time == 335 and r.players.A.deathEvents[2].time == 970)
    check("result clock: interrupts", r.players.A.interruptEvents[1] == 100 and r.players.A.interruptEvents[2] == 1170)
    check("result clock: nothing past the key's end", r.players.A.loot[1].t == 1774)
    MS.ToResultClock(r)
    check("result clock: once only", r.bosses[2].pullTime == 1670)

    -- Keys saved before: put on it once, the Stats page copy too.
    MythicScoreboardDB = { dataVersion = 5, runs = { Run() } }
    MS:RunMigrations()
    check("result clock: saved keys corrected", MythicScoreboardDB.runs[1].bosses[2].killTime == 1774)
    local arch = { v = 6, runs = { { at = 5000, dungeon = "Windrunner Spire", key = 15, dur = 1774,
        bosses = { { n = "Emberdawn", t = 400, d = 100, m = 1000 }, { n = "Restless Heart", t = 1810, d = 110 } } } } }
    MS:MigrateArchive(arch)
    local xb = arch.runs[1].bosses
    check("result clock: Stats page kill times", xb[1].t == 385 and xb[2].t == 1774, xb[2].t)
    check("result clock: fight length and DPS", xb[1].d == 85 and xb[1].m == math.floor(1000 * 100 / 85 + 0.5), xb[1].m)
end

-- Loot saved twice by 2.9.0 (a groupmate's addon copy) is cleaned up once.
do
    local item = function(fields) return { link = "|cnIQ4:|Hitem:" .. fields .. "|h[X]|h|r", t = 0 } end
    local a1, a2, a3 = item("500::::::::80:65::::"), item("500::::::::70:250::::"), item("501::::::::80:65::::")
    a2.t, a3.t = 3, 4
    local later = item("500::::::::80:65::::"); later.t = 900      -- a second real drop, much later
    MythicScoreboardDB = { dataVersion = 4, runs = { { dungeonName = "Skyreach", duration = 1000, bosses = {},
        players = { Xin = { name = "Xin", loot = { a1, a2, a3, later } } } } } }
    MS:RunMigrations()
    local L2 = MythicScoreboardDB.runs[1].players.Xin.loot
    check("dedupe: the doubled drop once", #L2 == 3, #L2)
    check("dedupe: other items and later drops kept", L2[2] == a3 and L2[3] == later)
    local arch = { v = 5, runs = { { at = 1, dungeon = "Skyreach", dur = 1000,
        loot = { { l = a1.link, t = 0 }, { l = a2.link, t = 2 } } } } }
    MS:MigrateArchive(arch)
    check("dedupe: Stats page copy too", #arch.runs[1].loot == 1 and arch.v == MS.ARCHIVE_VERSION)
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
    -- The Library's map was remembered: walking in there again, the wing
    -- is known before any boss.
    MS:AbandonRun(); zone(WORLD)
    uiMap = 302; zone(SM)
    check("wing: known from its map on the way in", #MS.currentRun.bosses == 0
        and MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Library", MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    -- A map the game names after its wing: known the first time.
    local gi = C_Map.GetMapInfo
    C_Map.GetMapInfo = function(id) return id == 305 and { name = "Cathedral" } or nil end
    uiMap = 305; zone(SM)
    check("wing: known from the map's name", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Cathedral",
        MS:RunTitle(MS.currentRun))
    -- Each wing's own map, known first time (a fresh account).
    MS:AbandonRun(); zone(WORLD)
    local learnedMaps = MythicScoreboardAccountDB.wingMaps
    MythicScoreboardAccountDB.wingMaps = {}
    for map, wing in pairs({ [302] = "Graveyard", [303] = "Library", [304] = "Armory" }) do
        uiMap = map; zone(SM)
        check("wing: map " .. map .. " is the " .. wing, MS:RunTitle(MS.currentRun) == "Scarlet Monastery: " .. wing,
            MS:RunTitle(MS.currentRun))
        MS:AbandonRun(); zone(WORLD)
    end
    MythicScoreboardAccountDB.wingMaps = learnedMaps
    -- No map at all (WoW Forever has no dungeon maps): the part of the
    -- dungeon you're in says which wing.
    uiMap = nil
    M.subzone = "Huntsman's Cloister"; zone(SM)
    check("wing: from the subzone", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Library", MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    M.subzone = ""; zone(SM)
    check("wing: no subzone yet, not known", MS.currentRun.wingName == nil, MS.currentRun.wingName)
    M.subzone = "Chapel Gardens"; M.Fire("ZONE_CHANGED_INDOORS"); M.RunTimers(5)
    check("wing: known on walking in", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Cathedral", MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    -- A part of a wing the table doesn't name (another language): learned
    -- from the boss fought there.
    M.subzone = "Salle des Chasseurs"; zone(SM)
    wait(30); kill("Houndmaster Loksey")
    check("wing: unnamed part learned", MythicScoreboardAccountDB.wingZones["Salle des Chasseurs"] == "Scarlet Monastery: Library")
    MS:AbandonRun(); zone(WORLD)
    zone(SM)
    check("wing: learned part known next time", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Library", MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    M.subzone = nil
    -- No map and no room name inside (WoW Forever): the door you walked in
    -- by. Two doors are known; another is learned from its bosses.
    local px, py = 0, 0
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px, py end } end
    local function walkIn(x, y)
        M.instance = WORLD; uiMap, px, py = 1420, x, y
        M.Fire("ZONE_CHANGED_NEW_AREA"); M.Tick()       -- standing at the door
        uiMap = nil; zone(SM)
    end
    walkIn(0.8536, 0.3240)
    check("wing: the Library door", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Library", MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    walkIn(0.8481, 0.3035)
    check("wing: the Graveyard door", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Graveyard", MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    walkIn(0.8620, 0.3150)
    check("wing: an unknown door, not guessed", MS.currentRun.wingName == nil, MS.currentRun.wingName)
    wait(30); kill("Herod")
    check("wing: its boss says", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Armory", MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    walkIn(0.8622, 0.3152)
    check("wing: the learned door, next time", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Armory", MS:RunTitle(MS.currentRun))
    -- A door near a known one is a guess: the room you walk into corrects it.
    MS:AbandonRun(); zone(WORLD)
    walkIn(0.8536, 0.3240)
    M.subzone = "Chapel Gardens"; M.Fire("ZONE_CHANGED_INDOORS"); M.RunTimers(5)
    check("wing: the room overrules the door", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Cathedral", MS:RunTitle(MS.currentRun))
    M.subzone = nil; M.Fire("ZONE_CHANGED_INDOORS"); M.RunTimers(5)
    check("wing: and stays", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Cathedral", MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    walkIn(0.8622, 0.3152)
    -- Out, then in by another door: a new run, not the Armory one.
    zone(WORLD)
    walkIn(0.8536, 0.3240)
    check("wing: another door, another run", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Library"
        and #MS.currentRun.bosses == 0, MS:RunTitle(MS.currentRun))
    -- The first wing-only trash killed says which wing: by name (the XP or
    -- "dies" line) or by NPC ID (UNIT_DIED); shared trash doesn't vote.
    rawset(_G, "UNITDIESOTHER", "%s dies.")
    MS:AbandonRun(); zone(WORLD)
    walkIn(0.8536, 0.3240)                                   -- the Library door...
    M.Fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Scarlet Myrmidon dies.")
    check("wing: shared trash, no change", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Library", MS:RunTitle(MS.currentRun))
    M.Fire("CHAT_MSG_COMBAT_HOSTILE_DEATH", "Scarlet Wizard dies.")
    check("wing: Cathedral trash overrules the door", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Cathedral",
        MS:RunTitle(MS.currentRun))
    M.subzone = "Huntsman's Cloister"; M.Fire("ZONE_CHANGED_INDOORS"); M.RunTimers(5)
    check("wing: trash outranks a room", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Cathedral", MS:RunTitle(MS.currentRun))
    M.subzone = nil
    MS:AbandonRun(); zone(WORLD)
    walkIn(0.8700, 0.3400)
    M.Fire("UNIT_DIED", "Creature-0-1-189-1-4283-0000AAAA")
    check("wing: by NPC ID", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Graveyard", MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    walkIn(0.8700, 0.3400)
    check("wing: the door learned from trash", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Graveyard", MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    MythicScoreboardAccountDB.wingDoors = {}
    -- Out, then in by a door nobody knows yet: still not the paused run.
    zone(WORLD)
    walkIn(0.8700, 0.3400)
    check("wing: an unknown door, a new run", MS.currentRun.wingName == nil and #MS.currentRun.bosses == 0,
        MS:RunTitle(MS.currentRun))
    MS:AbandonRun(); zone(WORLD)
    C_Map.GetPlayerMapPosition = nil
    wait(300)                                          -- that walk-in is long past
    -- The map not known yet on the way in (the loading screen): asked again
    -- once you're there.
    MS:AbandonRun(); zone(WORLD)
    uiMap = nil; zone(SM)
    check("wing: not known while the map isn't", MS.currentRun.wingName == nil, MS.currentRun.wingName)
    uiMap = 305; M.Fire("ZONE_CHANGED_INDOORS"); M.RunTimers(5)
    check("wing: known once the map is", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Cathedral",
        MS:RunTitle(MS.currentRun))
    -- A wrong guess gives way to the bosses.
    wait(30); kill("Houndmaster Loksey")
    check("wing: bosses overrule the map", MS:RunTitle(MS.currentRun) == "Scarlet Monastery: Library",
        MS:RunTitle(MS.currentRun))
    check("wing: a map with two wings isn't trusted", MythicScoreboardAccountDB.wingMaps[305] == "Scarlet Monastery: Library"
        or MythicScoreboardAccountDB.wingMaps[305] == false)
    -- Looking at a saved run changes nothing saved: not the run, not the maps.
    local function Dump(t, seen)
        if type(t) ~= "table" then return tostring(t) end
        seen = seen or {}
        if seen[t] then return "<loop>" end
        seen[t] = true
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        local out = {}
        for _, k in ipairs(keys) do
            local v = t[k]; if v == nil then v = t[tonumber(k)] end
            out[#out + 1] = k .. "=" .. Dump(v, seen)
        end
        return "{" .. table.concat(out, ",") .. "}"
    end
    local saved = MythicScoreboardDB.runs[1]
    saved.uiMapID = 999
    local before, mapsBefore = Dump(saved), Dump(MythicScoreboardAccountDB.wingMaps)
    MS:ForeverDungeon(saved); MS:ForeverDefsFor(saved); MS:ForeverCanDetectClear(saved)
    MS:ForeverBossProgress(saved); MS:RunTitle(saved)
    check("wing: viewing a saved run leaves it as saved", Dump(saved) == before)
    check("wing: viewing a saved run learns no maps", Dump(MythicScoreboardAccountDB.wingMaps) == mapsBefore)
    C_Map.GetMapInfo = gi
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

io.stdout:write(("regression_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

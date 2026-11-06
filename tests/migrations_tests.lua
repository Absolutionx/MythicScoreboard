-- usage: lua5.1 migrations_tests.lua DIR TOC   (saved data brought up to date, in order, once)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local ME                                      -- the local player's name as stored
local function run(at, dur, completed, boss)
    ME = ME or MS:UnitPlayerName("player")
    return { dungeonName = "Ragefire Chasm", _wallClockStart = at, startTime = 50, endTime = 50 + dur, completed = completed,
             keystoneLevel = 0, deathPenaltySeconds = 0,
             players = { [ME] = { name = ME, class = "MAGE", damageDone = 10, deaths = 0, deathEvents = {},
                                 interrupts = 1, interruptEvents = { { time = 12.3456, spell = "Unknown" } }, loot = {} } },
             bosses = { { name = boss, pullTime = 10, killTime = 60.123456 } } }
end
local function login(db)
    MythicScoreboardDB, MythicScoreboardAccountDB = db, nil
    M.instance = { "Orgrimmar", "none", 0 }
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    return MythicScoreboardDB
end

-- 1. Nothing done yet (before 2.5): every step runs.
local db = login({ runs = { run(5000 + 900 + 60, 600, true, "Bazzalan"), run(5000, 900, false, "Oggleflint") } })
check("split run joined", #db.runs == 1, #db.runs)
check("interrupts made plain", type(db.runs[1].players[ME].interruptEvents[1]) == "number")
check("at the latest version", db.dataVersion == MS.DATA_VERSION, db.dataVersion)
check("length kept as run.duration", db.runs[1].duration == 900 + 60 + 600, db.runs[1].duration)
check("game-clock times dropped", db.runs[1].startTime == nil and db.runs[1].endTime == nil)

-- 1b. A run whose saved clock was off falls back to its last kill.
local bad = run(9000, 0, true, "Oggleflint"); bad.endTime = 99999
db = login({ runs = { bad } })
check("bad clock: last kill + 30s", db.runs[1].duration == 90.12, db.runs[1].duration)

-- 2. Already repaired and compacted under the old flags: the join isn't
-- repeated (these two runs are an abandoned run and a fresh one, both new).
db = login({ historyRepair = 1, compact = 1, runs = { run(5000 + 900 + 60, 600, true, "Bazzalan"), run(5000, 900, false, "Oggleflint") } })
check("old flags respected: no second join", #db.runs == 2, #db.runs)
check("old flags removed", db.historyRepair == nil and db.compact == nil and db.dataVersion == MS.DATA_VERSION)

-- 3. Only the join done: compaction still runs.
db = login({ historyRepair = 1, runs = { run(5000, 900, true, "Oggleflint") } })
check("compaction runs after the join", type(db.runs[1].players[ME].interruptEvents[1]) == "number"
    and db.runs[1].bosses[1].killTime == 60.12, db.runs[1].bosses[1].killTime)

-- 4. A version-1 archive goes through every archive step.
local hist = run(7000, 900, true, "Oggleflint")
hist.players[ME].loot = { { item = "item:1", link = "|cff1eff00|Hitem:1|h[Thing]|h|r", quality = 2, t = 65 } }
hist.bosses[1].stats = { [ME] = { dmg = 500 } }
db = login({ runs = { hist }, archive = { v = 1, seeded = true, runs = {
    { at = 7000, dungeon = "Ragefire Chasm", dur = 900, cleared = true, bosses = { { n = "Oggleflint", t = 60 } }, group = {} },
    { at = 1000, dungeon = "Ragefire Chasm", dur = 900, bosses = {}, group = {} },
    { at = 1000 + 900 + 60, dungeon = "Ragefire Chasm", dur = 300, cleared = true, bosses = {}, group = {} },
} } })
local a = MS._ArchiveStore()
check("archive moved account-wide", db.archive == nil and a.v == MS.ARCHIVE_VERSION, a.v)
check("v1: split entries joined and sorted", #a.runs == 2 and a.runs[1].at == 1000 and a.runs[1].merged == 2, #a.runs)
local e = a.runs[2]
check("v3: fight length filled", e.bosses[1].d == 50, e.bosses[1].d)
check("v4: loot filled", e.loot and #e.loot == 1)
check("v5: loot keeps its link only", e.loot[1].l and e.loot[1].i == nil)

-- 5. A run saved now: its length, nothing live.
local live = run(9500, 0, false, "Oggleflint")
live.duration, live._carry, live._seq, live.activeBoss = 300, { x = 1 }, 7, live.bosses[1]
live.bosses[1]._session, live.players[ME]._lastDeathTime = 4, 12
local saved = MS:SerializeRun(live)
check("saved run keeps duration", saved.duration == 300)
check("saved run drops live state", saved._carry == nil and saved._seq == nil and saved.activeBoss == nil
    and saved.startTime == nil and saved.bosses[1]._session == nil and saved.players[ME]._lastDeathTime == nil)
local kept = MS:SerializeRun(live, true)
check("run in progress keeps it", kept._carry and kept.bosses[1]._session == 4 and kept.startTime ~= nil)

-- 6. Running again changes nothing.
local before = #a.runs
MS:RunMigrations()
check("second run does nothing", #MS._ArchiveStore().runs == before and MythicScoreboardDB.dataVersion == MS.DATA_VERSION)

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

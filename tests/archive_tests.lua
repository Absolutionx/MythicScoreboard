-- usage: lua5.1 archive_tests.lua DIR TOC
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local WORLD = { "Orgrimmar", "none", 0 }
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD"); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local clock = 1800000000
time = function() return clock end
local function reset()
    M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil; MS.currentRun, MS.inDungeon = nil, false
    M.instance = WORLD; M.Fire("ADDON_LOADED", "MythicScoreboard")
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
    MythicScoreboardDB.settings.historyLimit = 3
end
-- Plays one run: bosses killed (and wiped), my dps, cleared or not, then leaves.
local function playRun(dungeon, secs, opts)
    opts = opts or {}
    clock = clock + 3600
    zone({ dungeon, "party", 1 })
    local run = MS.currentRun
    for i, b in ipairs(opts.bosses or {}) do
        _ins = table.insert
        table.insert(run.bosses, { name = b, pullTime = i * 60, killTime = i * 60 + 30 })
    end
    for _ = 1, (opts.wipes or 0) do table.insert(run.bosses, { name = "Wiper", pullTime = 5 }) end
    local me = MS:PlayerForUnit("player")
    me.dps, me.level, me.deaths = opts.dps or 100, opts.lvl or 15, opts.myDeaths or 0
    MS:PlayerByName("Akasha").deaths = opts.akashaDeaths or 0
    run.completed = opts.cleared or false
    M.now = M.now + secs; run.startTime = M.now - secs
    zone(WORLD)
    if MS.currentRun and MS.currentRun._suspended then MS:ClosePausedRun() end
end

-- 1. Runs in history before the archive existed are seeded once, oldest first.
reset()
playRun("Ragefire Chasm", 900, { cleared = true, bosses = { "Oggleflint" } })
playRun("The Deadmines", 1500, { cleared = false })
local a = MS._ArchiveStore()
check("archive created", a and #a.runs == 2, a and #a.runs)
MythicScoreboardAccountDB.chars[MS._charKey].archive = nil   -- pretend it never existed
local seeded = MS:ArchiveRuns()
check("seeded from history", #seeded == 2, #seeded)
check("seeded oldest first", seeded[1].dungeon == "Ragefire Chasm" and seeded[2].dungeon == "The Deadmines")
MS:ArchiveRuns()
check("seeding happens once", #MS:ArchiveRuns() == 2)

-- 2. Every finished run is archived exactly once, even past the history limit.
reset()
for i = 1, 6 do playRun("Ragefire Chasm", 800 + i * 10, { cleared = i % 2 == 0, bosses = { "Oggleflint", "Bazzalan" }, dps = 100 + i }) end
check("history capped at 3", #MythicScoreboardDB.runs == 3, #MythicScoreboardDB.runs)
check("archive keeps all 6", #MS:ArchiveRuns() == 6, #MS:ArchiveRuns())

-- 3. The summary: my numbers, the group, bosses, wipes, deaths.
reset()
playRun("Ragefire Chasm", 1000, { cleared = true, bosses = { "Oggleflint", "Jergosh" }, wipes = 2, dps = 321, lvl = 17, myDeaths = 1, akashaDeaths = 2 })
local e = MS:ArchiveRuns()[1]
check("duration", e.dur == 1000, e.dur)
check("cleared flag", e.cleared == true)
check("my dps and level", e.me and e.me.dps == 321 and e.me.lvl == M.roster.player.level, e.me and (e.me.dps .. " L" .. tostring(e.me.lvl)))
check("group excludes me", #e.group == 4, #e.group)
check("bosses in order", #e.bosses == 2 and e.bosses[1].n == "Oggleflint" and e.bosses[1].t == 90)
check("wipes counted", e.wipes == 2, e.wipes)
check("group deaths", e.deaths == 3, e.deaths)
check("start date kept", e.at == clock, e.at)

-- 4. Overview numbers.
reset()
playRun("Ragefire Chasm", 900, { cleared = true })
playRun("Ragefire Chasm", 700, { cleared = true })
playRun("Ragefire Chasm", 1200, { cleared = false, akashaDeaths = 3 })
playRun("Ragefire Chasm", 800, { cleared = true })
playRun("The Deadmines", 1500, { cleared = true })
local o = MS:StatsOverview()
check("total runs", o.runs == 5 and o.cleared == 4, o.runs .. "/" .. o.cleared)
local rfc = o.dungeons[2].name == "Ragefire Chasm" and o.dungeons[2] or o.dungeons[1]
check("most recent dungeon first", o.dungeons[1].name == "The Deadmines")
check("best clear", rfc.best == 700, rfc.best)
check("typical clear is the median of clears", rfc.typical == 800, rfc.typical)
check("abandoned run not in clear times", #rfc.clearTimes == 3)
check("deaths per run", math.abs(rfc.deathsPerRun - 0.75) < 0.001, rfc.deathsPerRun)
check("recent strip", #rfc.recent == 4)
check("played with", #o.mates == 4 and o.mates[1].runs == 5, #o.mates)
local d = MS:StatsForDungeon("Ragefire Chasm")
check("dungeon detail", #d.runs == 4 and d.best == 700 and math.abs(d.clearRate - 0.75) < 0.001)

-- 5. Empty archive is fine.
reset()
local empty = MS:StatsOverview()
check("empty overview", empty.runs == 0 and #empty.dungeons == 0)

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

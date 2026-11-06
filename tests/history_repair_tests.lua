-- usage: lua5.1 history_repair_tests.lua DIR TOC
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function player(name, dmg, deathAt, lootT)
    return { name = name, class = "MAGE", damageDone = dmg, healingDone = 0, damageTaken = 100, avoidableDamageTaken = 0,
             interrupts = 1, dispels = 0, deaths = deathAt and 1 or 0, dps = 0, hps = 0,
             deathEvents = deathAt and { { time = deathAt } } or {}, interruptEvents = { { time = 30 } },
             loot = lootT and { { item = "item:1", t = lootT } } or {}, level = 15, itemLevel = 9 }
end
local function run(name, at, dur, completed, players, bosses, key)
    return { dungeonName = name, _wallClockStart = at, startTime = 50, endTime = 50 + dur, completed = completed,
             keystoneLevel = key or 0, players = players, bosses = bosses or {}, deathPenaltySeconds = 0 }
end
local function login(runs)
    MythicScoreboardDB = { runs = runs }
    M.instance = { "Orgrimmar", "none", 0 }
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    return MythicScoreboardDB.runs
end

-- 1. A split run is joined, with times shifted and numbers combined.
local A = run("Ragefire Chasm", 10000, 2000, false,
    { Jay = player("Jay", 1000, 500), Akasha = player("Akasha", 400) },
    { { name = "Oggleflint", pullTime = 100, killTime = 150 } })
local B = run("Ragefire Chasm", 10000 + 2000 + 600, 900, true,
    { Jay = player("Jay", 800, 200, 300), Skip = player("Skip", 50) },
    { { name = "Bazzalan", pullTime = 700, killTime = 760 } })
local runs = login({ B, A })
check("joined into one", #runs == 1, #runs)
local m = runs[1]
local offset = 2600
check("length spans both halves", MS:GetRunDuration(m) == offset + 900, MS:GetRunDuration(m))
check("result from the later half", m.completed == true)
check("bosses in order", #m.bosses == 2 and m.bosses[2].killTime == 760 + offset, m.bosses[2] and m.bosses[2].killTime)
check("first half untouched", m.bosses[1].killTime == 150)
local jay = m.players.Jay
check("damage added", jay.damageDone == 1800, jay.damageDone)
check("dps over time inside", math.abs(jay.dps - 1800 / 2900) < 0.001, jay.dps)
check("deaths added", jay.deaths == 2 and #jay.deathEvents == 2, jay.deaths)
check("death time shifted", jay.deathEvents[2].time == 200 + offset, jay.deathEvents[2].time)
check("loot time shifted", jay.loot[1].t == 300 + offset, jay.loot[1] and jay.loot[1].t)
check("interrupts kept", #jay.interruptEvents == 2 and jay.interrupts == 2)
check("player only in first half marked left", m.players.Akasha.left == true)
check("player only in second half kept", m.players.Skip and not m.players.Skip.left)
check("original halves not modified", B.bosses[1].killTime == 760 and B.players.Jay.deathEvents[1].time == 200)

-- 2. Runs that must stay apart.
local function pair(aCompleted, gap, key, otherName)
    local a = run("Ragefire Chasm", 20000, 1000, aCompleted, { Jay = player("Jay", 1) }, {}, key)
    local b = run(otherName or "Ragefire Chasm", 20000 + 1000 + gap, 500, true, { Jay = player("Jay", 1) }, {}, key)
    return #login({ b, a })
end
check("gap over 30 minutes", pair(false, 31 * 60) == 2)
check("first half cleared", pair(true, 60) == 2)
check("Mythic+ keys", pair(false, 60, 12) == 2)
check("different dungeons", pair(false, 60, nil, "The Deadmines") == 2)
check("within 30 minutes joins", pair(false, 29 * 60) == 1)

-- 3. Only once per character.
local r = login({ B, A })
check("first login joins", #r == 1)
table.insert(MythicScoreboardDB.runs, run("Ragefire Chasm", 1, 100, false, {}, {}))
M.Fire("ADDON_LOADED", "MythicScoreboard")
check("later logins don't", #MythicScoreboardDB.runs == 2)

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

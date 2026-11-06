-- usage: lua5.1 fight_tests.lua DIR TOC
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function S(v) return { __secret = true, v = v } end
local WORLD = { "Orgrimmar", "none", 0 }
local me = MS.FLAVOR == "forever" and "Jay-Breezy" or "Jay"
local function src(name, guid, amt, isLocal, cls)
    return { name = name, sourceGUID = guid, totalAmount = amt, isLocalPlayer = isLocal, classFilename = cls, amountPerSecond = 0 }
end
-- Overall totals: Jay (self) and Akasha.
local function overall(jay, aka, extra)
    extra = extra or {}
    M.meter = {
        [0] = { duration = 100, combatSources = { src("Jay-Breezy", "Player-1-AAA", jay, true, "SHAMAN"),
                                                  src("Akasha", "Player-1-BBB", aka, false, "MAGE") } },
        [2] = { duration = 100, combatSources = { src("Akasha", "Player-1-BBB", extra.heal or 0, false, "MAGE") } },
        [5] = { combatSources = {} }, [6] = { combatSources = {} },
        [7] = { combatSources = { src("Jay-Breezy", "Player-1-AAA", extra.taken or 0, true, "SHAMAN") } },
        [8] = { combatSources = {} }, [9] = { combatSources = {} },
    }
end
local function session(id, name, jay, aka, secret)
    local function v(x) return secret and S(x) or x end
    return { sessionID = id, name = name, data = {
        [0] = { combatSources = { src("Jay-Breezy", "Player-1-AAA", v(jay), true, "SHAMAN"),
                                  src("Akasha", "Player-1-BBB", v(aka), false, "MAGE") } },
        [2] = { combatSources = { src("Akasha", "Player-1-BBB", v(500), false, "MAGE") } },
        [5] = { combatSources = { src("Jay-Breezy", "Player-1-AAA", v(2), true, "SHAMAN") } },
    } }
end
local function fresh()
    M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil; MS.currentRun, MS.inDungeon, MS.displayRun = nil, false, nil
    M.sessions, M.meter = {}, {}
    M.instance = WORLD
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
    M.instance = { "Ragefire Chasm", "party", 1 }
    MS:StartRun("Ragefire Chasm", 0, 1, "Normal")
    M.RunTimers(2)
    return MS.currentRun
end
local function fight(name, secs, success)
    M.Fire("ENCOUNTER_START", 100, name)
    M.now = M.now + secs
    M.Fire("ENCOUNTER_END", 100, name, 1, 5, success == nil and 1 or success)
end
local function B(run, i) return run.bosses[i] end
local AK

-- 1. The fight's own session gives its numbers.
local run = fresh()
AK = MS:PlayerByGUID("Player-1-BBB").name
overall(1000, 2000); MS:SnapshotFromDamageMeter()
M.sessions = { session(3, "Trash", 1, 1) }
M.Fire("ENCOUNTER_START", 100, "Oggleflint"); M.now = M.now + 60
M.sessions[2] = session(7, "Oggleflint", 3000, 1200)
M.Fire("ENCOUNTER_END", 100, "Oggleflint", 1, 5, 1)
overall(5000, 4000); MS:SnapshotFromDamageMeter()
local st = B(run, 1).stats
check("fight recorded", st ~= nil)
check("own damage from session", st and st[MS.ShortName(me)] and st[MS.ShortName(me)].dmg == 3000, st and st[MS.ShortName(me)] and st[MS.ShortName(me)].dmg)
check("other player's damage", st and st[AK] and st[AK].dmg == 1200)
check("healing and interrupts", st and st[AK].heal == 500 and st[MS.ShortName(me)].int == 2)
check("not approximate", not B(run, 1).statsApprox)
check("working fields cleared", B(run, 1)._session == nil and B(run, 1)._before == nil)

-- 2. Hidden at first (a key), readable later.
run = fresh()
M.Fire("ENCOUNTER_START", 100, "Oggleflint"); M.now = M.now + 60
M.sessions = { session(9, "Oggleflint", 800, 900, true) }
M.Fire("ENCOUNTER_END", 100, "Oggleflint", 1, 5, 1)
fight("Bazzalan", 50)          -- next boss pulled before anything was readable
MS:CaptureFightStats(run)
check("hidden: nothing stored", B(run, 1).stats == nil)
M.sessions[1] = session(9, "Oggleflint", 800, 900)
MS:CaptureFightStats(run)
check("readable later: stored", B(run, 1).stats and B(run, 1).stats[AK].dmg == 900)

-- 2b. Session list hidden at the kill: found by name afterwards.
run = fresh()
M.sessions = { { sessionID = S(30), name = S("Oggleflint"), data = {} } }
fight("Oggleflint", 30, 0)                                   -- a wipe
fight("Oggleflint", 40)                                      -- then the kill
fight("Bazzalan", 50)
check("hidden ids: none noted", B(run, 1)._session == nil and B(run, 2)._session == nil)
M.sessions = { session(1, "Oggleflint", 5, 5), session(30, "Oggleflint", 10, 11),
               session(31, "Oggleflint", 20, 21), session(32, "Bazzalan", 40, 41) }
MS:CaptureFightStats(run)
check("wipe matched by name", B(run, 1).stats and B(run, 1).stats[AK].dmg == 11, B(run, 1).stats and B(run, 1).stats[AK].dmg)
check("kill matched by name", B(run, 2).stats and B(run, 2).stats[AK].dmg == 21)
check("last boss matched", B(run, 3).stats and B(run, 3).stats[AK].dmg == 41)

-- 3. No per-fight sessions: the difference between readings.
run = fresh()
local saved = C_DamageMeter.GetAvailableCombatSessions
C_DamageMeter.GetAvailableCombatSessions = nil
overall(1000, 2000, { taken = 50 }); MS:SnapshotFromDamageMeter()
fight("Oggleflint", 40)
overall(1600, 2300, { taken = 450 }); MS:SnapshotFromDamageMeter()
st = B(run, 1).stats
check("difference used", st and st[MS.ShortName(me)].dmg == 600 and st[AK].dmg == 300, st and st[MS.ShortName(me)] and st[MS.ShortName(me)].dmg)
check("difference taken", st and st[MS.ShortName(me)].taken == 400)
check("marked approximate", B(run, 1).statsApprox == true)
-- ...but not once the next boss has been pulled.
fight("Jergosh", 30)
M.Fire("ENCOUNTER_START", 100, "Bazzalan")
overall(9000, 9000); MS:SnapshotFromDamageMeter()
check("no difference after next pull", B(run, 2).stats == nil and B(run, 2)._before == nil)
C_DamageMeter.GetAvailableCombatSessions = saved

-- 4. Two bosses in one combat: the session isn't given to both.
run = fresh()
M.sessions = { session(4, "Combat", 100, 100) }
fight("Oggleflint", 20); fight("Jergosh", 20)
check("shared session only once", B(run, 1)._session == 4 and B(run, 2)._session == nil, tostring(B(run, 2)._session))

-- 5. A session that's gone: give up after a while, keep the run going.
run = fresh()
M.sessions = { session(12, "Oggleflint", 1, 1) }
fight("Oggleflint", 20)
M.sessions = {}
for _ = 1, 25 do MS:CaptureFightStats(run) end
check("gave up on a lost session", B(run, 1)._session == nil)

-- 6. The table for one fight.
run = fresh()
overall(1000, 2000); MS:SnapshotFromDamageMeter()
M.sessions = { session(20, "Oggleflint", 6000, 3000) }
local jay = MS:PlayerByName(me)
M.now = M.now + 100
local pull = MS:GetRunDuration(run)
M.Fire("ENCOUNTER_START", 100, "Oggleflint"); M.now = M.now + 60
MS:RecordDeathEvent(jay)
M.Fire("ENCOUNTER_END", 100, "Oggleflint", 1, 5, 1)
overall(9000, 9000); MS:SnapshotFromDamageMeter()
M.now = M.now + 5
MS:RecordDeathEvent(MS:PlayerByGUID("Player-1-BBB"))      -- after the fight
MS:SaveCurrentRun(); MS:FlushSave()
MS:ShowScoreboard(); M.RunTimers(2)
local f = MythicScoreboardFrame
local function boardRows()
    local out = {}
    for _, w in ipairs(M.allFrames) do
        if w._shown and w._player and w._parent == UI.overviewSF.scrollContent then out[#out + 1] = w end
    end
    return out
end
local function cell(row, key) return row._statFs[key].main:GetText() end
local function rowFor(name)
    for _, r in ipairs(boardRows()) do if r._player.name == MS.ShortName(name) then return r end end
end
check("whole run first", cell(rowFor(me), "deaths") == "1" and cell(rowFor(AK), "deaths") == "1")

-- Click the boss on the timeline.
local segBtn
for _, w in ipairs(M.allFrames) do
    if w._shown and w._kind == "Button" and w._scripts.OnClick and w._parent
            and w._parent._parent == f.timelineContainer then segBtn = segBtn or w end
end
check("boss on timeline is clickable", segBtn ~= nil)
if segBtn then segBtn:Fire("OnClick"); M.RunTimers(2) end
check("fight shown", UI.focus and UI.focus.boss == B(run, 1))
check("header names the fight", f.Subline:GetText():find("Oggleflint") and f.Subline:GetText():find("Fight"), f.Subline:GetText())
check("whole run button shown", f.WholeRunBtn and f.WholeRunBtn:IsShown())
local jr, ar = rowFor(me), rowFor(AK)
check("fight deaths only", jr and ar and cell(jr, "deaths") == "1" and cell(ar, "deaths") == "0",
    jr and ar and (cell(jr, "deaths") .. "/" .. cell(ar, "deaths")))
check("fight dps from session", jr and jr._statFs.dps.main:GetText() == "100", jr and jr._statFs.dps.main:GetText())
local function full(cell) return (cell.main:GetText() .. (cell.tail:GetText() or "")):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
check("fight damage column", jr and full(jr._statFs.damage) == "6.0K", jr and full(jr._statFs.damage))
check("fight healing column", ar and full(ar._statFs.healing) == "500", ar and full(ar._statFs.healing))
check("players without fight numbers hidden", #boardRows() == 2, #boardRows())
jr:Fire("OnEnter"); jr:Fire("OnLeave")
local errs
for _, p in ipairs(M.printed) do if p:find("error") then errs = p end end
check("no errors", not errs, errs)
check("run itself untouched", jay.deaths == 1 and jay.damageDone == 9000, jay.damageDone)

-- Back to the whole run.
f.WholeRunBtn:Fire("OnClick"); M.RunTimers(2)
check("whole run again", UI.focus == nil and cell(rowFor(AK), "deaths") == "1")
check("button hidden", not f.WholeRunBtn:IsShown())
-- Clicking the same boss twice toggles.
UI.FocusBoss(run, B(run, 1)); M.RunTimers(2)
UI.FocusBoss(run, B(run, 1)); M.RunTimers(2)
check("second click goes back", UI.focus == nil)
-- Showing another run drops the fight.
UI.FocusBoss(run, B(run, 1)); M.RunTimers(2)
MS.displayRun = { dungeonName = "The Deadmines", players = {}, bosses = {}, duration = 99, completed = true }
MS:RefreshOverview(); M.RunTimers(2)
check("other run drops the fight", UI.focus == nil and not f.WholeRunBtn:IsShown())
MS.displayRun = nil

-- 7. Archive: fight lengths, your DPS, and the Stats bosses list.
local e = MS:SummarizeRun(run)
check("archive fight length", e.bosses[1].d == 60, e.bosses[1].d)
check("archive your fight dps", e.bosses[1].m == 100, e.bosses[1].m)

MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
M.Fire("ADDON_LOADED", "MythicScoreboard")
local function arun(at, bosses)
    return { at = at, dungeon = "Ragefire Chasm", dur = 900, cleared = true, deaths = 0, bosses = bosses, group = {} }
end
MS:ArchiveRuns()
local a = MS._ArchiveStore()
a.runs = {
    arun(1, { { n = "Oggleflint", t = 100, d = 50, m = 90 }, { n = "Bazzalan", t = 800, d = 70 } }),
    arun(2, { { n = "Oggleflint", t = 90, d = 40, m = 120 }, { n = "Bazzalan", t = 700, d = 90 } }),
    arun(3, { { n = "Oggleflint", t = 95, d = 60 }, { n = "Jergosh", t = 400 }, { n = "Bazzalan", t = 750, d = 80 } }),
}
local s = MS:StatsForDungeon("Ragefire Chasm")
check("boss order", s.bosses[1].name == "Oggleflint" and s.bosses[2].name == "Jergosh" and s.bosses[3].name == "Bazzalan",
    s.bosses[1].name .. "," .. s.bosses[2].name .. "," .. s.bosses[3].name)
check("boss best/typical", s.bosses[1].best == 40 and s.bosses[1].typical == 50 and s.bosses[1].kills == 3)
check("boss best dps", s.bosses[1].bestDps == 120)
check("boss without lengths", s.bosses[2].best == nil and s.bosses[2].kills == 1)

-- On the Stats page.
MS:ShowScoreboard(); M.RunTimers(2)
UI.OpenStats(); M.RunTimers(2)
for _, w in ipairs(M.allFrames) do if w.dungeon == "Ragefire Chasm" and w._shown then w:Fire("OnClick") end end
M.RunTimers(2)
local bossRows = {}
for _, w in ipairs(M.allFrames) do
    if w._shown and w.data and w.best and w.typical then bossRows[#bossRows + 1] = w end
end
check("bosses panel rows", #bossRows == 3, #bossRows)
local og
for _, r in ipairs(bossRows) do if r.data.name == "Oggleflint" then og = r end end
check("bosses panel text", og and og.best:GetText():find("0:40") and og.typical:GetText() == "0:50",
    og and (og.best:GetText() .. " " .. og.typical:GetText()))
for _, r in ipairs(bossRows) do r:Fire("OnEnter"); r:Fire("OnLeave") end
errs = nil
for _, p in ipairs(M.printed) do if p:find("error") then errs = p end end
check("no stats errors", not errs, errs)

-- 8. Old archive filled in from history once.
MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
M.Fire("ADDON_LOADED", "MythicScoreboard")
MythicScoreboardDB.runs = { { dungeonName = "Ragefire Chasm", _wallClockStart = 500, duration = 900, completed = true,
    players = {}, bosses = { { name = "Oggleflint", pullTime = 100, killTime = 145 } } } }
MythicScoreboardDB.archive = { v = 2, seeded = true, runs = { arun(500, { { n = "Oggleflint", t = 145 } }) } }
MS:RunMigrations()
local arc = MS._ArchiveStore()
check("old per-character archive moved account-wide", MythicScoreboardDB.archive == nil and arc.runs[1].at == 500)
check("backfilled fight length", arc.runs[1].bosses[1].d == 45, arc.runs[1].bosses[1].d)
arc.runs[1].bosses[1].d = nil
MS:RunMigrations()
check("backfill runs once", arc.runs[1].bosses[1].d == nil)

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

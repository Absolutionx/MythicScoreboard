-- usage: lua5.1 openfight_tests.lua DIR TOC   (boss fights the game never ends; deaths after the final boss)
-- From a Blackfathom Deeps run on Forever: Lorgus Jett's fight started and
-- never ended, so it stayed "in combat", took the deaths after the last
-- boss, and kept the run from being cleared at Aku'mai.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if not MS.Flavor.progressStats then
    io.stdout:write("openfight_tests: Forever only, skipped\n"); os.exit(0)
end
local clock = 1800000000
time = function() return clock end
local function wait(s) M.now = M.now + s; clock = clock + s end
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local WORLD, BFD = { "Ashenvale", "none", 0 }, { "Blackfathom Deeps", "party", 1, 48 }
local inCombat = false
UnitAffectingCombat = function() return inCombat end
local function kill(name, len)
    inCombat = true; M.Fire("PLAYER_REGEN_DISABLED")
    M.Fire("ENCOUNTER_START", 1, name); wait(len or 30); M.Fire("ENCOUNTER_END", 1, name, 1, 5, 1)
    inCombat = false; M.Fire("PLAYER_REGEN_ENABLED"); M.RunTimers(4)
end
-- A fight the game starts and never ends.
local function noEnd(name, xpLine)
    inCombat = true; M.Fire("PLAYER_REGEN_DISABLED")
    M.Fire("ENCOUNTER_START", 2913, name); wait(25)
    if xpLine then M.Fire("CHAT_MSG_COMBAT_XP_GAIN", name .. " dies, you gain 300 experience.") end
    wait(2); inCombat = false; M.Fire("PLAYER_REGEN_ENABLED")
end
local function Boss(run, name)
    for _, b in ipairs(run.bosses) do if b.name == name then return b end end
end
local function fresh()
    if MS.currentRun then MS:AbandonRun() end
    M.timers = {}; M.dead = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    zone(WORLD); zone(BFD)
    return MS.currentRun
end

-- ── It reset: closed when combat has been over a few seconds ───────────────
local run = fresh()
check("run", run ~= nil)
kill("Ghamoo-ra"); wait(200); kill("Lady Sarevess"); wait(300); kill("Geilhast"); wait(400)
noEnd("Lorgus Jett")
local lj = Boss(run, "Lorgus Jett")
check("reset: still open at once", lj and not lj.wipeTime and not lj.killTime)
M.Advance(3)
check("reset: still open 3s later (the group may still be fighting)", not lj.wipeTime)
inCombat = true; M.Advance(4)
check("reset: kept open while anyone's in combat", not lj.wipeTime)
inCombat = false; M.Advance(7)
check("reset: closed", lj.wipeTime ~= nil and lj.reset == true and not lj.killTime, tostring(lj.wipeTime))
check("reset: ended when combat did", lj.wipeTime and math.abs(lj.wipeTime - (lj.pullTime + 27)) < 1, lj.wipeTime and (lj.wipeTime - lj.pullTime))
check("reset: no fight open", run.activeBoss == nil)
check("reset: result", MS.FightResult(lj) == "reset" and MS.FightLost(lj) and MS.FightTag(lj):find("reset") ~= nil)

-- Deaths later aren't Lorgus Jett's, and Aku'mai clears it (he doesn't always spawn).
wait(500); kill("Old Serra'kis"); wait(400); kill("Twilight Lord Kelris"); wait(300); kill("Aku'mai", 70)
M.RunTimers(4)
check("cleared at Aku'mai", run.completed == true, tostring(run.completed))
local me = run.players and select(2, next(run.players))
local deathsBefore = 0
for _, p in pairs(run.players) do deathsBefore = deathsBefore + (p.deaths or 0) end
wait(300); M.dead.player = true; M.Tick(); wait(5); M.dead.player = nil; M.Tick()
local deathsAfter = 0
for _, p in pairs(run.players) do deathsAfter = deathsAfter + (p.deaths or 0) end
check("a death after the clear isn't the run's", deathsAfter == deathsBefore, deathsBefore .. " -> " .. deathsAfter)
zone(WORLD)

-- ── It died, the experience line says so: a kill ───────────────────────────
run = fresh()
kill("Ghamoo-ra"); wait(200)
noEnd("Lorgus Jett", true)
lj = Boss(run, "Lorgus Jett")
wait(8); M.RunTimers(8)
check("xp: killed", lj.killTime ~= nil and not lj.wipeTime, tostring(lj.killTime))
check("xp: result", MS.FightResult(lj) == "kill" and not MS.FightLost(lj) and MS.FightTag(lj) == "")
check("xp: at the death", lj.killTime and math.abs(lj.killTime - (lj.pullTime + 25)) < 1)

-- ── Its ENCOUNTER_END comes late after all: no harm ─────────────────────────
M.Fire("ENCOUNTER_END", 2913, "Lorgus Jett", 1, 5, 1); M.RunTimers(4)
check("late end: still one kill", lj.killTime ~= nil and #run.bosses == 2, #run.bosses)
zone(WORLD)

-- ── The next boss pulled before combat ever dropped ────────────────────────
run = fresh()
inCombat = true
M.Fire("ENCOUNTER_START", 2913, "Lorgus Jett"); wait(20)
M.Fire("ENCOUNTER_START", 2, "Old Serra'kis"); wait(20); M.Fire("ENCOUNTER_END", 2, "Old Serra'kis", 1, 5, 1)
inCombat = false; M.RunTimers(4)
lj = Boss(run, "Lorgus Jett")
check("next pull: closed", lj.wipeTime ~= nil and lj.reset)
check("next pull: the other boss killed", Boss(run, "Old Serra'kis").killTime ~= nil)

-- ── Dead while the group fights on: left open ──────────────────────────────
wait(60); inCombat = true
M.Fire("ENCOUNTER_START", 3, "Twilight Lord Kelris"); wait(10)
M.dead.player = true; inCombat = false; M.Fire("PLAYER_REGEN_ENABLED")
wait(12); M.RunTimers(8)
local tk = Boss(run, "Twilight Lord Kelris")
check("dead: fight kept open", MS.FightResult(tk) == "open" and MS.FightEnd(tk) == nil)
M.dead.player = nil
M.Fire("ENCOUNTER_END", 3, "Twilight Lord Kelris", 1, 5, 1); M.RunTimers(4)
check("dead: then killed", tk.killTime ~= nil)

-- ── Final boss down, a required boss left, deaths, then leaving mid-fight ──
-- (Gelihast left: cleared on leaving, at Aku'mai; the deaths after don't
-- count, and the fight still open when leaving is closed.)
run = fresh()
kill("Ghamoo-ra"); wait(100); kill("Lady Sarevess"); wait(100)
kill("Old Serra'kis"); wait(100); kill("Twilight Lord Kelris"); wait(100); kill("Aku'mai", 60)
M.RunTimers(4)
check("waiting for Gelihast", not run.completed and run.finalDown)
local before = 0
for _, p in pairs(run.players) do before = before + (p.deaths or 0) end
wait(200); M.dead.player = true; M.Tick(); wait(5); M.dead.player = nil; M.Tick()
local mid = 0
for _, p in pairs(run.players) do mid = mid + (p.deaths or 0) end
check("the death recorded while waiting", mid == before + 1, before .. " " .. mid)
inCombat = true; M.Fire("PLAYER_REGEN_DISABLED"); M.Fire("ENCOUNTER_START", 5, "Gelihast"); wait(10)
zone(WORLD)
local saved = MythicScoreboardDB.runs[1]
local gh; for _, b in ipairs(saved.bosses) do if b.name == "Gelihast" then gh = b end end
check("leave: open fight closed", gh and gh.wipeTime ~= nil and gh.reset, gh and tostring(gh.wipeTime))
local total = 0
for _, p in pairs(saved.players) do total = total + (p.deaths or 0); for _, de in ipairs(p.deathEvents or {}) do
    check("no death after the clear", de.time <= saved.clearedAt + 2, de.time) end end
check("cleared on leaving", saved.completed and saved.clearedAt ~= nil)
check("deaths after Aku'mai dropped", total == before, total)

-- ── Boss names, compared one way ───────────────────────────────────────────
check("names: key", MS.BossKey("Ner\226\128\153zhul") == "ner'zhul")
check("names: case", MS.SameBossName("Lorgus Jett", "lorgus jett"))
check("names: punctuation", MS.SameBossName("Lorgus-Jett", "Lorgus Jett"))
check("names: curly apostrophe", MS.SameBossName("Aku\226\128\153mai", "Aku'mai"))
check("names: different bosses", not MS.SameBossName("Gelihast", "Ghamoo-ra"))

io.stdout:write(("openfight_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

-- usage: lua5.1 emptyrun_tests.lua DIR TOC
-- Runs nothing happened in aren't saved; saving a run survives an error; and
-- (Forever) gold and XP aren't read before the game has them.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.startOnPull, M.dropEmptyRuns = true, true          -- as players get it
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local RFC, WORLD = { "Ragefire Chasm", "party", 1 }, { "Orgrimmar", "none", 0 }
local function zone(inst)
    M.instance = inst
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.RunTimers(8)
end
local skew = 0
time = function() return os.time() + skew end
local function reset()
    skew = 0
    M.timers = {}
    MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
    MS.currentRun, MS.inDungeon, MS._abandonedIn = nil, false, nil
    M.dead = {}; M.groupSize = 5
    M.instance = WORLD
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
end
local function saved() return #MythicScoreboardDB.runs end
-- Logged out inside, back in (inside or outside): the run in progress again.
local function relog(inst)
    MS:FlushSave()
    local active = MythicScoreboardDB.activeRun
    MS.currentRun = nil; MS:SetRunState("none")
    MythicScoreboardDB.activeRun = active
    M.instance = inst
    M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(3)
end

-- ── Runs nothing happened in ───────────────────────────────────────────────
-- The clock at the door (first-pull clock off): in and out, the pause runs out.
reset(); MS:SetStartOnPull(false); zone(RFC); M.Advance(20); zone(WORLD)
check("in and out: paused", MS:RunState() == "paused", MS:RunState())
skew = 31 * 60; M.Advance(60)
check("in and out: not saved", MS:RunState() == "none" and saved() == 0, saved())

-- Abandoned with nothing done.
reset(); MS:SetStartOnPull(false); zone(RFC); M.Advance(20)
MS:AbandonRun()
check("abandoned, nothing done: not saved", saved() == 0, saved())

-- Waiting for its pull, logged out inside, back in outside.
reset(); zone(RFC); M.Advance(60); relog(WORLD)
skew = 31 * 60; M.Advance(60)
check("waiting run, back outside: not saved", MS:RunState() == "none" and saved() == 0, saved())

-- "Leaving the dungeon" ends runs: one never pulled still isn't a run.
if MS.CLEAR_RULES then
    reset(); MS:SetClearRule("leave"); zone(RFC); M.Advance(300); zone(WORLD)
    check("leave rule, never pulled: not saved", saved() == 0, saved())
end

-- Something happened: saved as before.
reset(); zone(RFC)
M.Fire("PLAYER_REGEN_DISABLED"); M.Advance(30)
M.Fire("ENCOUNTER_START", 1, "Oggleflint", 1, 5); M.Advance(20)
M.Fire("ENCOUNTER_END", 1, "Oggleflint", 1, 5, 0)
MS:AbandonRun()
check("a boss fought: saved", saved() == 1, saved())

reset(); MS:SetStartOnPull(false); zone(RFC); M.Advance(20)
for _, p in pairs(MS.currentRun.players) do p.deaths = 1; break end
MS:AbandonRun()
check("a death: saved", saved() == 1, saved())

-- A key is always saved.
check("a key is never empty", MS:IsEmptyRun({ keystoneLevel = 12, players = {}, bosses = {} }) == false)
check("a cleared run is never empty", MS:IsEmptyRun({ completed = true, players = {}, bosses = {} }) == false)

-- ── Saving survives an error ───────────────────────────────────────────────
local function fought()
    reset(); zone(RFC)
    M.Fire("PLAYER_REGEN_DISABLED"); M.Advance(30)
    M.Fire("ENCOUNTER_START", 1, "Oggleflint", 1, 5); M.Advance(20)
    M.Fire("ENCOUNTER_END", 1, "Oggleflint", 1, 5, 0)
end
-- Beside the save (the meter, the Stats summary, the best-time line): still saved.
for _, part in ipairs({ "SnapshotFromDamageMeter", "PopulateAll", "ArchiveRun", "_AnnouncePB", "BestKeyTime" }) do
    fought()
    local real = MS[part]
    MS[part] = function() error("broken " .. part) end
    local ok = pcall(MS.AbandonRun, MS)
    MS[part] = real
    check(part .. " fails: no error out", ok)
    check(part .. " fails: the run is still saved", saved() == 1, saved())
    check(part .. " fails: no run left hanging", MS.currentRun == nil and MS:RunState() == "none")
end
-- The save itself: the run is kept, and saved at the next login.
fought()
local real = MS.SerializeRun
MS.SerializeRun = function() error("broken save") end
local ok = pcall(MS.AbandonRun, MS)
MS.SerializeRun = real
check("the save fails: no error out", ok)
check("the save fails: kept for another try", saved() == 0 and type(MythicScoreboardDB.unsavedRun) == "table")
check("the save fails: no run left hanging", MS.currentRun == nil)
local kept = MythicScoreboardDB.unsavedRun
M.Fire("ADDON_LOADED", "MythicScoreboard")
check("next login: saved", saved() == 1 and MythicScoreboardDB.unsavedRun == nil, saved())
check("next login: the same run", MythicScoreboardDB.runs[1] and MythicScoreboardDB.runs[1]._wallClockStart == kept._wallClockStart)
-- Still broken at the next login: dropped, not tried for ever.
fought()
MS.SerializeRun = function() error("broken save") end
pcall(MS.AbandonRun, MS)
pcall(M.Fire, "ADDON_LOADED", "MythicScoreboard")
MS.SerializeRun = real
check("still failing: one more try only", MythicScoreboardDB.unsavedRun == nil)

-- ── Gold and XP: nothing read while the game is loading (Forever) ─────────
if MS.Flavor.progressStats then
    reset(); MS:SetStartOnPull(false)
    M.money, M.xp, M.xpMax, M.level = 550000, 30000, 60000, 41
    zone(RFC); M.Advance(10)
    M.money = 550000 + 40; M.Fire("PLAYER_MONEY")
    check("looting counts", MS.currentRun.progress.gold == 40, MS.currentRun.progress.gold)
    -- A /reload inside: the run is picked up while the game still says 0.
    MS:FlushSave()
    local active = MythicScoreboardDB.activeRun
    MS.currentRun = nil; MS:SetRunState("none")
    MythicScoreboardDB.activeRun = active
    M.money, M.xp = 0, 0
    M.instance = RFC
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    M.Fire("PLAYER_MONEY"); M.Fire("PLAYER_XP_UPDATE"); M.RunTimers(2)      -- (events while loading)
    M.money, M.xp = 550040, 30000
    M.Fire("PLAYER_ENTERING_WORLD", false, true); M.RunTimers(8)
    M.money = 550040 + 12; M.Fire("PLAYER_MONEY")
    M.xp = 30000 + 150; M.Fire("PLAYER_XP_UPDATE"); M.RunTimers(2)
    local p = MS.currentRun and MS.currentRun.progress
    check("after a /reload: only the 12 copper more", p and p.gold == 52, p and p.gold)
    check("after a /reload: only the 150 XP", p and p.xp == 150, p and p.xp)
end

for _, line in ipairs(M.printed or {}) do
    if line:find("error") and not line:find("broken") then check("no other errors", false, line) end
end
io.stdout:write(("emptyrun_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

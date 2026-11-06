-- usage: lua5.1 lifecycle_tests.lua DIR TOC
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local retail = MS.FLAVOR ~= "forever"
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
local RFC, DM, WORLD = { "Ragefire Chasm", "party", 1 }, { "The Deadmines", "party", 1 }, { "Orgrimmar", "none", 0 }
local function history() return #MythicScoreboardDB.runs end
local function reset()
    M.timers = {}
    MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
    MS.currentRun, MS.inDungeon = nil, false
    M.dead = {}; M.groupSize = 5
    M.instance = WORLD
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
    MythicScoreboardDB.settings.clearRule = "final"
end

-- 1. Enter a tracked dungeon: a run starts.
reset(); zone(RFC)
check("starts in dungeon", MS:RunState() == "active" and MS.currentRun.dungeonName == "Ragefire Chasm", MS:RunState())
local run1 = MS.currentRun

-- 2. A loading screen inside the dungeon (e.g. reload): same run continues.
zone(RFC)
check("reload keeps run", MS.currentRun == run1 and MS:RunState() == "active")

-- 3. One odd reading during a zone change does not end the run.
M.instance = WORLD
M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(1)     -- first check sees "outside"
M.instance = RFC; M.RunTimers(8)                    -- then it settles back inside
check("single odd reading ignored", MS.currentRun == run1 and MS:RunState() == "active", MS:RunState())

-- 4. Release while dead: paused; walking back in resumes the same run.
M.dead.player = true; zone(WORLD)
check("release pauses", MS:RunState() == "paused" and MS.currentRun == run1, MS:RunState())
check("paused not in history", history() == 0, history())
M.dead.player = nil; zone(RFC)
check("return resumes", MS:RunState() == "active" and MS.currentRun == run1, MS:RunState())

-- 5. Paused, then a different dungeon: old run closes, new one starts.
M.dead.player = true; zone(WORLD); M.dead.player = nil
zone(DM)
check("other dungeon closes paused run", history() == 1 and MythicScoreboardDB.runs[1].dungeonName == "Ragefire Chasm", history())
check("other dungeon starts new run", MS:RunState() == "active" and MS.currentRun.dungeonName == "The Deadmines")

-- 6. Leaving alive (repair, vendor) pauses too; coming back resumes.
local dmRun = MS.currentRun
zone(WORLD)
check("leave alive pauses", MS:RunState() == "paused" and history() == 1, MS:RunState() .. " " .. history())
zone(DM)
check("leave alive then return resumes", MS:RunState() == "active" and MS.currentRun == dmRun)

-- 6b. A cleared run ends as soon as you leave.
MS.currentRun.completed = true
zone(WORLD)
check("cleared run ends on leave", MS:RunState() == "none" and history() == 2, history())
check("saved as cleared", MythicScoreboardDB.runs[1].completed == true)

-- 7. Paused too long: closed.
reset(); zone(RFC); M.dead.player = true; zone(WORLD); M.dead.player = nil
local realTime = time
time = function() return realTime() + 14 * 60 end
M.Tick()
check("paused run survives 14 minutes", MS:RunState() == "paused")
time = function() return realTime() + 31 * 60 end
M.Tick()
time = realTime
check("paused run times out", MS:RunState() == "none" and history() == 1, MS:RunState())

-- 8. Paused and the group disbands: closed.
reset(); zone(RFC); M.dead.player = true; zone(WORLD); M.dead.player = nil
M.groupSize = 0; M.Fire("GROUP_ROSTER_UPDATE"); M.RunTimers(3)
check("group disband closes paused run", MS:RunState() == "none" and history() == 1, MS:RunState())

-- 8b. The instance is reset while paused: the run closes.
reset(); zone(RFC); zone(WORLD)
M.Fire("CHAT_MSG_SYSTEM", "Some Other Place has been reset."); M.RunTimers(2)
check("other reset ignored", MS:RunState() == "paused")
M.Fire("CHAT_MSG_SYSTEM", "Ragefire Chasm has been reset."); M.RunTimers(2)
check("reset closes paused run", MS:RunState() == "none" and history() == 1, MS:RunState())

-- 9. "Leaving the dungeon" clear rule (Forever only): finished, not abandoned.
if not retail then
    reset(); MythicScoreboardDB.settings.clearRule = "leave"
    zone(RFC); zone(WORLD)
    check("leave rule marks finished", history() == 1 and MythicScoreboardDB.runs[1].finishedOnLeave == true)
end

-- 10. Untracked difficulty: no run (retail only; Forever tracks every dungeon).
if retail then
    reset()
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = false end
    zone(RFC)
    check("untracked difficulty ignored", MS:RunState() == "none")
end

-- 11. Mythic+ (retail): key run keeps going in the open world, even dead;
--     ends if you enter another dungeon with no key active.
if retail then
    reset()
    local activeMap = 2526
    C_ChallengeMode = {
        GetActiveChallengeMapID = function() return activeMap end,
        GetActiveKeystoneInfo = function() return 12, {}, 1800 end,
        GetMapInfo = function() return { name = "Ragefire Chasm" } end,
    }
    zone({ "Ragefire Chasm", "party", 8 })
    M.Fire("CHALLENGE_MODE_START", activeMap); M.RunTimers(3)
    check("key starts run", MS:RunState() == "active" and MS.currentRun.keystoneLevel == 12, MS:RunState())
    local key = MS.currentRun
    M.dead.player = true; zone(WORLD); M.dead.player = nil
    check("key not paused when dead outside", MS:RunState() == "active" and MS.currentRun == key, MS:RunState())
    zone({ "Ragefire Chasm", "party", 8 })
    check("key run continues back inside", MS.currentRun == key)
    activeMap = nil
    MythicScoreboardDB.settings.trackedDifficulties.normal = false
    zone({ "The Deadmines", "party", 1 })
    check("untracked dungeon without key ends key run", history() >= 1 and MythicScoreboardDB.runs[1].keystoneLevel == 12, history())
    C_ChallengeMode = nil
end

-- 12. /reload mid-run: the saved run comes back and keeps going.
reset(); zone(RFC)
MS.currentRun.players[next(MS.currentRun.players)].damageDone = 4242
MS._saveDirty = true; MS:FlushSave()
MS.currentRun, MS.inDungeon = nil, false              -- what a reload wipes
M.Fire("ADDON_LOADED", "MythicScoreboard"); zone(RFC)
local restored = 0
for _, p in pairs(MS.currentRun and MS.currentRun.players or {}) do if p.damageDone == 4242 then restored = 1 end end
check("reload inside restores run", MS:RunState() == "active" and restored == 1, MS:RunState())

-- 13. /reload while paused outside: still paused, resumes on return.
M.dead.player = true; zone(WORLD); M.dead.player = nil
MS._saveDirty = true; MS:FlushSave()
MS.currentRun, MS.inDungeon = nil, false
M.Fire("ADDON_LOADED", "MythicScoreboard"); zone(WORLD)
check("reload while paused stays paused", MS:RunState() == "paused", MS:RunState())
zone(RFC)
check("resume after reload", MS:RunState() == "active" and history() == 0, MS:RunState() .. " " .. history())

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

-- usage: lua5.1 savedsize_tests.lua DIR TOC   (history in both files; leftovers cleared at logout)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local WORLD, RFC = { "Orgrimmar", "none", 0 }, { "Ragefire Chasm", "party", 1 }
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local clock = 1800000000
time = function() return clock end
local function wait(s) M.now = M.now + s; clock = clock + s end
local function login()
    M.timers = {}; MS.currentRun, MS.inDungeon, MS.displayRun = nil, false, nil
    M.instance = WORLD
    M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(2)
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
end
local function playRun()
    clock = clock + 86400
    zone(RFC); wait(60)
    M.Fire("ENCOUNTER_START", 1, "Oggleflint"); wait(30); M.Fire("ENCOUNTER_END", 1, "Oggleflint", 1, 5, 1); M.RunTimers(4)
    MS.currentRun.completed = true
    wait(200); zone(WORLD)
    if MS.currentRun and MS.currentRun._suspended then MS:ClosePausedRun() end
end
-- What the game does at logout and the next login: each saved variable
-- written to its own file and read back (so nothing is shared between them).
local function copy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local t = {}; seen[v] = t
    for k, x in pairs(v) do t[copy(k, seen)] = copy(x, seen) end
    return t
end
local function relog()
    M.Fire("PLAYER_LOGOUT")
    local db, acc = copy(MythicScoreboardDB), copy(MythicScoreboardAccountDB)
    MythicScoreboardDB, MythicScoreboardAccountDB = db, acc
    login()
end

-- ── 1. History is kept in both files ───────────────────────────────────────
MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
login()
playRun(); playRun()
local key = MS:CharKey()
check("two runs in history", #MythicScoreboardDB.runs == 2, #MythicScoreboardDB.runs)
M.Fire("PLAYER_LOGOUT")
check("kept in the character's file", type(MythicScoreboardDB.runs) == "table" and #MythicScoreboardDB.runs == 2
    and MythicScoreboardDB.runsAt == nil)
check("and in the account file", #MythicScoreboardAccountDB.chars[key].history == 2)
relog()
check("back after a relog", #MythicScoreboardDB.runs == 2, #MythicScoreboardDB.runs)
check("account file lost: the character keeps its own", (function()
    M.Fire("PLAYER_LOGOUT")
    local db = copy(MythicScoreboardDB)
    MythicScoreboardDB, MythicScoreboardAccountDB = db, nil
    login()
    return #MythicScoreboardDB.runs == 2
end)(), #MythicScoreboardDB.runs)

-- ── 5. Leftovers ───────────────────────────────────────────────────────────
local acc2 = MythicScoreboardAccountDB
acc2.mapExport = { 1, 2, 3 }
acc2.travelDump = { taxi = {} }                       -- from before dumps were dated
M.Fire("PLAYER_LOGOUT")
check("old map export cleared", acc2.mapExport == nil)
check("undated travel dump cleared", acc2.travelDump == nil)
acc2.travelDump = { at = clock - 3600, taxi = {} }
M.Fire("PLAYER_LOGOUT")
check("fresh dump kept to be sent in", acc2.travelDump ~= nil)
acc2.travelDump.at = clock - 2 * 86400
M.Fire("PLAYER_LOGOUT")
check("day-old dump cleared", acc2.travelDump == nil)
local function errorsPrinted()
    for _, p in ipairs(M.printed) do if p:find("rror") then return p end end
end
check("no errors at all", not errorsPrinted(), errorsPrinted())

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

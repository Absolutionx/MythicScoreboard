-- usage: lua5.1 lootedge_tests.lua DIR TOC   (removing loot: odd cases)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function errorsPrinted()
    for _, p in ipairs(M.printed) do if p:find("rror") then return p end end
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
local LINK = "|cnIQ4:|Hitem:12345::::::::20:::::|h[Fiery Greatsword]|h|r"
local function playRun(cleared, withLoot)
    clock = clock + 86400
    zone(RFC)
    wait(60)
    M.Fire("ENCOUNTER_START", 1, "Oggleflint"); wait(30); M.Fire("ENCOUNTER_END", 1, "Oggleflint", 1, 5, 1); M.RunTimers(4)
    if withLoot then
        wait(20)
        local me = MS:PlayerForUnit("player")
        me.loot = { { item = "item:12345::::::::20:::::", link = LINK, quality = 4, t = MS:GetRunDuration() } }
    end
    MS.currentRun.completed = cleared
    wait(200); zone(WORLD)
    if MS.currentRun and MS.currentRun._suspended then MS:ClosePausedRun() end
end



MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
login()
playRun(true, true)
local e; for _, x in ipairs(MS:ArchiveRuns()) do if x.loot then e = x end end
-- two copies of the same item in one run (two of a kind dropped)
e.loot[2] = { l = e.loot[1].l, q = e.loot[1].q, t = (e.loot[1].t or 0) + 5, b = e.loot[1].b }
MS:BumpStats()
check("two of a kind listed", #MS:LootHistory() == 2, #MS:LootHistory())
local second = e.loot[2]
check("removing one copy", MS:RemoveArchivedLoot(e, second) and #e.loot == 1 and e.loot[1] ~= second)
check("removing it again: nothing", not MS:RemoveArchivedLoot(e, second))
check("junk in: nothing", not MS:RemoveArchivedLoot(nil, nil) and not MS:RemoveArchivedLoot({}, {}))
MS:RemoveArchivedLoot(e, e.loot[1])
check("last item gone: no empty list left", e.loot == nil)
check("clear with nothing: zero", MS:ClearLootHistory() == 0)
local shown
StaticPopupDialogs = {}; StaticPopup_Show = function() shown = true end
UI.AskClearLoot()
check("clear with nothing: no dialog", not shown)
-- the run removed from stats while its item's x is armed
playRun(true, true)
local e2; for _, x in ipairs(MS:ArchiveRuns()) do if x.loot then e2 = x end end
local item = e2.loot[1]
MS:RemoveArchivedRun(e2)
check("run gone: its item can't be removed (no error)", pcall(MS.RemoveArchivedLoot, MS, e2, item))
check("loot list follows the run", #MS:LootHistory() == 0, #MS:LootHistory())
local function errorsPrinted() for _, p in ipairs(M.printed) do if p:find("rror") then return p end end end
check("no errors", not errorsPrinted(), errorsPrinted())
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

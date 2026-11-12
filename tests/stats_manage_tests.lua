-- usage: lua5.1 stats_manage_tests.lua DIR TOC
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
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
end
local function playRun(dungeon, secs, cleared, gapBefore)
    clock = clock + (gapBefore or 86400)
    zone({ dungeon, "party", 1 })
    local run = MS.currentRun
    run.completed = cleared
    M.now = M.now + secs; run.startTime = M.now - secs
    clock = clock + secs
    zone(WORLD)
    if MS.currentRun and MS.currentRun._suspended then MS:ClosePausedRun() end
end

-- 1. Split runs in old history are joined when seeding.
reset()
local function oldRun(at, dur, cleared, boss)
    return { dungeonName = "Ragefire Chasm", _wallClockStart = at, startTime = 100, endTime = 100 + dur,
             completed = cleared, bosses = { { name = boss, pullTime = 10, killTime = 60 } }, players = {} }
end
MythicScoreboardDB.runs = { oldRun(5000 + 2400 + 300, 900, true, "Bazzalan"), oldRun(5000, 2400, false, "Oggleflint") }
MythicScoreboardAccountDB.chars[MS:CharKey()].archive = nil
local runs = MS:ArchiveRuns()
check("old split runs joined", #runs == 1 and runs[1].cleared and #runs[1].bosses == 2, #runs)
check("joined time spans both", runs[1].dur == 2400 + 300 + 900, runs[1].dur)
check("second boss time shifted", runs[1].bosses[2].t == 60 + 2700, runs[1].bosses[2].t)

-- 2. New runs (after the fix) are never joined, even if they look split.
reset()
MS:ArchiveRuns()
playRun("Ragefire Chasm", 600, false)
playRun("Ragefire Chasm", 500, true, 120)          -- 2 minutes later: a real new attempt
check("new runs stay separate", #MS:ArchiveRuns() == 2, #MS:ArchiveRuns())

-- 3. Deleting a run from history removes it from stats too.
reset()
playRun("Ragefire Chasm", 700, true)
playRun("The Deadmines", 900, true)
check("two archived", #MS:ArchiveRuns() == 2)
MS:ShowScoreboard(); M.RunTimers(2)
local f = MythicScoreboardFrame
f.HistoryButton:Fire("OnClick")
local del
for _, w in ipairs(M.allFrames) do
    if w._shown and w._kind == "Button" and w._parent and w._parent._parent and w._parent._parent._parent == UIParent
            and w._scripts.OnClick and w._scripts.OnEnter and not w._children[2] then del = del or w end
end
check("history delete button found", del ~= nil)
if del then
    del:Fire("OnClick")
    check("history delete: one click only asks", #MythicScoreboardDB.runs == 2, #MythicScoreboardDB.runs)
    M.RunTimers(4)
    del:Fire("OnClick")
    check("history delete: the ask runs out", #MythicScoreboardDB.runs == 2, #MythicScoreboardDB.runs)
    del:Fire("OnClick")
    M.RunTimers(2)
end
check("history delete also removes from stats", #MS:ArchiveRuns() == 1 and #MythicScoreboardDB.runs == 1,
    #MS:ArchiveRuns() .. "/" .. #MythicScoreboardDB.runs)

-- 4. Remove a run from the Stats page (two clicks), history untouched.
reset()
playRun("Ragefire Chasm", 700, true)
playRun("Ragefire Chasm", 400, true)
playRun("Ragefire Chasm", 800, true)
MS:ShowScoreboard(); M.RunTimers(2)
UI.OpenStats(); M.RunTimers(2)
for _, w in ipairs(M.allFrames) do if w.dungeon == "Ragefire Chasm" and w._shown then w:Fire("OnClick") end end
M.RunTimers(2)
local fastRow
for _, w in ipairs(M.allFrames) do if w.entry and w.del and w._shown and w.entry.dur == 400 then fastRow = w end end
check("run row with remove button", fastRow ~= nil)
fastRow.del:Fire("OnClick")
check("first click only arms", #MS:ArchiveRuns() == 3)
fastRow.del:Fire("OnClick"); M.RunTimers(2)
check("second click removes", #MS:ArchiveRuns() == 2)
check("history untouched", #MythicScoreboardDB.runs == 3)
check("best recalculated", MS:StatsForDungeon("Ragefire Chasm").best == 700, MS:StatsForDungeon("Ragefire Chasm").best)
local shownRows = 0
for _, w in ipairs(M.allFrames) do if w.entry and w.del and w._shown then shownRows = shownRows + 1 end end
check("list redrawn", shownRows == 2, shownRows)

-- 5. Reset stats (two clicks); history kept and not re-imported.
local back
for _, w in ipairs(M.allFrames) do
    if w._kind == "Button" and w._shown and w._children then
        for _, c in ipairs(w._children) do if c._kind == "FontString" and c._text == "All dungeons" then back = w end end
    end
end
back:Fire("OnClick"); M.RunTimers(2)
local resetBtn
for _, w in ipairs(M.allFrames) do
    if w._kind == "Button" and w._shown and w._children then
        for _, c in ipairs(w._children) do if c._kind == "FontString" and c._text == "Reset stats" then resetBtn = w end end
    end
end
check("reset button found", resetBtn ~= nil)
resetBtn:Fire("OnEnter"); resetBtn:Fire("OnLeave")
resetBtn:Fire("OnClick")
check("reset armed, nothing removed", #MS:ArchiveRuns() == 2)
resetBtn:Fire("OnClick"); M.RunTimers(2)
check("stats reset", #MS:ArchiveRuns() == 0)
check("history kept", #MythicScoreboardDB.runs == 3)
check("summary shows zero", f.Subline:GetText():find("0") ~= nil, f.Subline:GetText())
playRun("Ragefire Chasm", 650, true)
check("new runs recorded after reset", #MS:ArchiveRuns() == 1, #MS:ArchiveRuns())

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

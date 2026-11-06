-- usage: lua5.1 clear_tests.lua DIR TOC   (Forever: final-boss rule, reloads, pause end)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local forever = MS.FLAVOR == "forever"
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local RUINS, WORLD = { "Ruins of Lordaeron", "party", 1 }, { "Orgrimmar", "none", 0 }
local clock = 1800000000
time = function() return clock end
local function wait(s) M.now = M.now + s; clock = clock + s end
local function reset()
    M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil; MS.currentRun, MS.inDungeon, MS.displayRun = nil, false, nil
    M.dead = {}; M.instance = WORLD
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
    MythicScoreboardDB.settings.clearRule = "final"
end
local function kill(name, fight)
    M.Fire("ENCOUNTER_START", 1, name); wait(fight or 30)
    M.Fire("ENCOUNTER_END", 1, name, 1, 5, 1); M.RunTimers(4)
end
local function reload()
    MS:FlushSave()
    local db = MythicScoreboardDB
    MS.currentRun, MS.inDungeon = nil, false
    M.timers = {}
    MythicScoreboardDB = db
    M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(8)
end

if forever then
    -- 1. Ruins of Lordaeron in the order it was actually played.
    reset(); zone(RUINS)
    for _, b in ipairs({ "Witherfang", "The Butcher", "Viktor the Vile" }) do wait(200); kill(b) end
    check("final boss third: not cleared yet", not MS.currentRun.completed and MS.currentRun.finalDown)
    wait(100); kill("The Abandoned")
    -- 2. A reload in between keeps everything.
    reload()
    local run = MS.currentRun
    check("reload restores run", run and run.dungeonName == "Ruins of Lordaeron" and #run.bosses == 4)
    check("reload keeps finalDown", run and run.finalDown == true)
    check("reload keeps boss order", run and run.bosses[3].name == "Viktor the Vile")
    wait(200); kill("Bjork"); wait(300); kill("Rath'mael")
    check("cleared after the last required boss", MS.currentRun.completed == true)
    local clearedAt = MS.currentRun.clearedAt
    check("cleared at the last kill", clearedAt and math.abs(clearedAt - MS.currentRun.bosses[6].killTime) < 0.01, clearedAt)
    wait(840)                                        -- looting and chatting for 14 minutes
    check("clock stopped at the clear", math.abs(MS:GetRunDuration() - clearedAt) < 0.01, MS:GetRunDuration())
    zone(WORLD)
    check("leaving a cleared run finishes it", MS:RunState() == "none" and #MythicScoreboardDB.runs == 1, MS:RunState())
    local saved = MythicScoreboardDB.runs[1]
    check("saved as cleared", saved.completed == true)
    check("saved time is the clear", math.abs(MS:GetRunDuration(saved) - clearedAt) < 0.01, MS:GetRunDuration(saved))

    -- 3. Cleared, then reload, then leave: still cleared (the bug).
    reset(); zone(RUINS)
    for _, b in ipairs({ "Witherfang", "The Butcher", "The Abandoned", "Bjork", "Rath'mael", "Viktor the Vile" }) do wait(100); kill(b) end
    check("final boss last: cleared at once", MS.currentRun.completed == true)
    reload()
    check("reload keeps cleared", MS.currentRun and MS.currentRun.completed == true)
    zone(WORLD)
    check("cleared run not paused after reload", MS:RunState() == "none" and MythicScoreboardDB.runs[1].completed == true, MS:RunState())

    -- 4. Final boss down, optional ones skipped, leave: cleared.
    reset(); zone(RUINS)
    wait(100); kill("Witherfang"); wait(100); kill("Viktor the Vile")
    local lastKill = MS.currentRun.bosses[2].killTime
    wait(300)
    zone(WORLD)
    check("final down + leave = cleared", MS:RunState() == "none" and MythicScoreboardDB.runs[1].completed == true, MS:RunState())
    check("its time ends at the last kill", math.abs(MS:GetRunDuration(MythicScoreboardDB.runs[1]) - lastKill) < 0.01)

    -- 5. Final boss alive: leaving pauses; closing later is abandoned, timed to the pause.
    reset(); zone(RUINS)
    wait(100); kill("Witherfang"); wait(200)
    local pausedAt = MS:GetRunDuration()
    zone(WORLD)
    check("unfinished leave pauses", MS:RunState() == "paused")
    wait(600)
    MS:ClosePausedRun()
    local r = MythicScoreboardDB.runs[1]
    check("closed paused run abandoned", r and r.completed == false)
    check("closed paused run ends at the pause", r and math.abs(MS:GetRunDuration(r) - pausedAt) < 1, r and MS:GetRunDuration(r))
end

-- 6. Short fights get their length under the bar.
reset()
MythicScoreboardDB.runs = { { dungeonName = "Ragefire Chasm", _wallClockStart = 1, duration = 3900, completed = true,
    players = {}, bosses = {
        { name = "Oggleflint", pullTime = 300, killTime = 330 },
        { name = "Taragaman the Hungerer", pullTime = 340, killTime = 365 },   -- right after: no room
        { name = "Bazzalan", pullTime = 2000, killTime = 2600 },               -- long: inside
    } } }
MS:ShowScoreboard(); M.RunTimers(3)
local labels = {}
for _, w in ipairs(M.allFrames) do
    if w._kind == "FontString" and w._shown and w._text and w._text:match("^%d+:%d%d$") and w._parent == MythicScoreboardFrame.timelineContainer._children[1] then
        labels[w._text] = (labels[w._text] or 0) + 1
    end
end
local function any(t) for _, w in ipairs(M.allFrames) do if w._kind == "FontString" and w._shown and w._text == t then return true end end end
check("short fight labelled", any("0:30"))
check("crowded label skipped", not any("0:25"))
check("long fight labelled", any("10:00"))

-- 7. A saved run that wasn't cleared is drawn still: the timeline must not
-- keep rebuilding itself (that swallowed clicks on the boss medallions).
reset()
MythicScoreboardDB.runs = { { dungeonName = "Ragefire Chasm", _wallClockStart = 1, duration = 1500, completed = false,
    players = {}, bosses = {
        { name = "Oggleflint", pullTime = 300, killTime = 330 },
        { name = "Bazzalan", pullTime = 1000, killTime = 1040 },
    } } }
MS:ShowScoreboard(); M.RunTimers(3)
local f = MythicScoreboardFrame
local function medallions()
    local out = {}
    for _, w in ipairs(M.allFrames) do
        if w._shown and w._kind == "Button" and w._scripts.OnClick and w._parent and w._parent._parent == f.timelineContainer
                and w:GetWidth() >= 30 then out[#out + 1] = w end
    end
    return out
end
local before = medallions()
check("abandoned: medallions drawn", #before == 2, #before)
local function frameUpdates(n)
    for _ = 1, n do
        M.now = M.now + 0.05
        for _, w in ipairs(M.allFrames) do
            local u = w._scripts and w._scripts.OnUpdate
            if u and w._shown then u(w, 0.05) end
        end
    end
end
frameUpdates(40)
local after = medallions()
check("abandoned: timeline not rebuilt every frame", after[1] == before[1] and after[2] == before[2])
check("abandoned: no live tag", not (f.timelineContainer._children[1]._liveTag and f.timelineContainer._children[1]._liveTag._shown))
after[1]:Fire("OnClick"); frameUpdates(5)
check("abandoned: medallion click shows the fight", UI.focus and UI.focus.boss.name == "Oggleflint")
UI.FocusBoss(nil, nil)

-- A live run still grows and draws live.
if forever then
    reset(); zone(RUINS)
    wait(60); kill("Witherfang")
    MS:ShowScoreboard(); M.RunTimers(3)
    local m1 = medallions()[1]
    frameUpdates(20)
    check("live: medallion stable", medallions()[1] == m1)
    m1:Fire("OnClick"); M.RunTimers(2)
    check("live: click works", UI.focus and UI.focus.boss.name == "Witherfang")
    UI.FocusBoss(nil, nil)
    -- Paused: the clock stands still.
    wait(30); zone(WORLD)
    local d1 = MS:GetRunDuration()
    wait(300)
    check("paused clock stands still", MS:GetRunDuration() == d1, MS:GetRunDuration() - d1)
end

-- 8. Abandoning by hand.
do
    local RFC = { "Ragefire Chasm", "party", 1 }
    reset(); zone(RFC)
    wait(60); kill("Oggleflint"); wait(30)
    MS:ShowScoreboard(); M.RunTimers(2)
    local f = MythicScoreboardFrame
    local ab = f.AbandonBtn
    check("abandon button on a live run", ab and ab:IsShown())
    ab:Fire("OnEnter"); ab:Fire("OnLeave")
    ab:Fire("OnClick")
    check("first click only arms", MS:RunState() == "active")
    ab:Fire("OnClick"); M.RunTimers(2)
    local h = MythicScoreboardDB.runs[1]
    check("abandoned and saved", MS:RunState() == "none" and h and h.completed == false and h.abandoned == true)
    check("button gone after", not ab:IsShown())
    zone(RFC)
    check("no new run while still inside", MS:RunState() == "none", MS:RunState())
    zone(WORLD); zone(RFC)
    check("new run after leaving and coming back", MS:RunState() == "active")

    -- Not for a cleared run.
    MS.currentRun.completed = true
    MS:RefreshOverview(); M.RunTimers(2)
    check("no button on a cleared run", not ab:IsShown())
    check("cleared run can't be abandoned", MS:AbandonRun() == false)
    MS.currentRun.completed = false

    -- Paused: abandoned, timed to the pause.
    wait(100); zone(WORLD)
    check("paused", MS:RunState() == "paused")
    local pausedAt = MS:GetRunDuration()
    MS:RefreshOverview(); M.RunTimers(2)
    check("button on a paused run", ab:IsShown())
    wait(500)
    SlashCmdList["MYTHICSCOREBOARD"]("abandon"); M.RunTimers(2)
    check("slash command abandons", MS:RunState() == "none" and MythicScoreboardDB.runs[1].completed == false)
    check("paused run ends at the pause", math.abs(MS:GetRunDuration(MythicScoreboardDB.runs[1]) - pausedAt) < 1)
    SlashCmdList["MYTHICSCOREBOARD"]("abandon")
    check("nothing to abandon says so", M.printed[#M.printed]:find("No run in progress") ~= nil)
    check("archive says abandoned", not MS:ArchiveRuns()[#MS:ArchiveRuns()].cleared)
end
if forever then
    -- Final boss down: abandoning still abandons (not "cleared on leave").
    reset(); zone(RUINS)
    wait(60); kill("Viktor the Vile")
    check("final down", MS.currentRun.finalDown)
    MS:AbandonRun()
    check("final-down run abandoned, not cleared", MythicScoreboardDB.runs[1].completed == false)
end

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

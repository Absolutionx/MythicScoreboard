-- usage: lua5.1 runstats_tests.lua DIR TOC   (Forever: experience, kills, quests, gold, reputation)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if not MS.Flavor.progressStats then
    io.stdout:write("runstats_tests: retail has no run stats, skipped\n")
    check("retail: nothing recorded", true)
    os.exit(0)
end
local clock = 1800000000
time = function() return clock end
local function wait(s) M.now = M.now + s; clock = clock + s end
local WORLD, RFC = { "Orgrimmar", "none", 0 }, { "Ragefire Chasm", "party", 1 }
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local function xp(v, lvl) M.xp = v; if lvl then M.level = lvl; M.Fire("PLAYER_LEVEL_UP", lvl) end; M.Fire("PLAYER_XP_UPDATE", "player"); M.RunTimers(2) end
local function money(v) M.money = v; M.Fire("PLAYER_MONEY"); M.RunTimers(1) end

M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
M.xp, M.xpMax, M.level, M.money = 4000, 5000, 14, 10000
M.quests = { { title = "Searching for the Lost Satchel", id = 101, done = false },
             { title = "Hidden Enemies", id = 102, done = true } }       -- already done: not this run's
M.Fire("ADDON_LOADED", "MythicScoreboard")
zone(RFC)
local run = MS.currentRun
check("run started", run ~= nil)

-- Experience, across a level-up.
xp(4600)
xp(300, 15)                          -- 400 to finish level 14, then 300 into 15
local pr = run.progress
check("xp: counted across the level", pr and pr.xp == 1300, pr and pr.xp)
check("xp: one level", pr and pr.levels == 1, pr and pr.levels)

-- Kills, from the experience lines (only kills that gave XP).
for _, line in ipairs({ "Ragefire Trogg dies, you gain 45 experience.",
                        "Ragefire Shaman dies, you gain 52 experience. (+5 group bonus)",
                        "Earthborer dies, you gain 40 experience. (20 exp Rested bonus)",
                        "You gain 120 experience." }) do           -- a quest or exploration: not a kill
    M.Fire("CHAT_MSG_COMBAT_XP_GAIN", line)
end
check("kills: three", pr.kills == 3, pr.kills)

-- Reputation.
M.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your Orgrimmar reputation has increased by 25.")
M.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your Orgrimmar reputation has increased by 10.")
check("rep: by faction", pr.rep and pr.rep.Orgrimmar == 35, pr.rep and pr.rep.Orgrimmar)

-- Quests: one finished in here (the game reports the objective's progress),
-- one already done before.
M.Fire("QUEST_WATCH_UPDATE", 1)                     -- log index 1 (classic)
M.quests[1].done = true
M.Fire("QUEST_LOG_UPDATE"); M.Fire("QUEST_LOG_UPDATE"); M.RunTimers(2)
check("quests: the one finished here", #pr.quests == 1 and pr.quests[1] == "Searching for the Lost Satchel",
    #pr.quests)

-- The log filling in after the loading screen (or a header being expanded):
-- quests already done when they first show up aren't this run's.
M.quests[#M.quests + 1] = { title = "Ziz Fizziks", id = 201, done = true }
M.quests[#M.quests + 1] = { title = "Harpy Lieutenants", id = 202, done = true }
M.Fire("QUEST_LOG_UPDATE"); M.RunTimers(2)
check("quests: already done when first seen don't count", #pr.quests == 1, #pr.quests)
-- Quests long done that read as not done while the log loads, then done
-- (City of Dalaran: ten of them counted at zone-in): no progress, no count.
for i, t in ipairs({ "Wrongly Blamed, Justly Corrected", "Kill Grundig Darkcloud", "Regthar Deathgate" }) do
    M.quests[#M.quests + 1] = { title = t, id = 300 + i, done = false }
end
M.Fire("QUEST_LOG_UPDATE"); M.RunTimers(2)
for i = #M.quests - 2, #M.quests do M.quests[i].done = true end
M.Fire("QUEST_LOG_UPDATE"); M.RunTimers(2)
check("quests: done ones that loaded as not done don't count", #pr.quests == 1, #pr.quests)
-- One that shows up incomplete, makes progress here, and completes does.
M.quests[#M.quests + 1] = { title = "Deathstalkers in Shadowfang", id = 203, done = false }
M.Fire("QUEST_LOG_UPDATE"); M.RunTimers(2)
M.Fire("QUEST_WATCH_UPDATE", 203)                   -- quest ID (newer clients)
M.quests[#M.quests].done = true
M.Fire("QUEST_LOG_UPDATE"); M.RunTimers(2)
check("quests: progress here, then complete", #pr.quests == 2 and pr.quests[2] == "Deathstalkers in Shadowfang", #pr.quests)
-- One completed right after an objective line ("Arcane Mote: 1/1").
M.quests[#M.quests + 1] = { title = "Heart of Disruption", id = 204, done = false }
M.Fire("QUEST_LOG_UPDATE"); M.RunTimers(2)
M.Fire("UI_INFO_MESSAGE", 288, "Arcane Mote: 1/1")
M.quests[#M.quests].done = true
M.Fire("QUEST_LOG_UPDATE"); M.RunTimers(2)
check("quests: right after an objective line", #pr.quests == 3 and pr.quests[3] == "Heart of Disruption", #pr.quests)

-- Gold.
money(10850); money(12000)
check("gold: looted", pr.gold == 2000, pr.gold)

-- Header line.
MS:ShowScoreboard(); M.RunTimers(2)
local sub = MythicScoreboardFrame.Subline:GetText() or ""
check("header: xp", sub:find("1,300") ~= nil, sub)
check("header: kills", sub:find("3|r kills") ~= nil or sub:find("3 kills") ~= nil, sub)
check("header: gold", sub:find("20s") ~= nil, sub)

-- Outside (paused): nothing counts; back in, it carries on from there.
zone(WORLD)
check("paused", MS:RunState() == "paused", MS:RunState())
xp(900); money(50000)
M.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 30 experience.")
zone(RFC)
check("back in", MS:RunState() == "active")
xp(1000)
check("outside not counted: xp", pr.xp == 1400, pr.xp)
check("outside not counted: kills", pr.kills == 3, pr.kills)
check("outside not counted: gold", pr.gold == 2000, pr.gold)

-- Saved into the archive for the Stats page.
for _, b in ipairs({ "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" }) do
    M.Fire("ENCOUNTER_START", 1, b); wait(30); M.Fire("ENCOUNTER_END", 1, b, 1, 5, 1); M.RunTimers(4)
end
zone(WORLD)
local runs = MS:ArchiveRuns()
local e = runs[#runs]
check("archive: progress kept", e and e.prog and e.prog.xp == 1400 and e.prog.k == 3 and e.prog.q == 3
    and e.prog.g == 2000 and e.prog.lv == 1 and e.prog.rep.Orgrimmar == 35)
local st = MS:StatsOverview()
check("stats: totals", st.xp == 1400 and st.kills == 3 and st.quests == 3 and st.gold == 2000, st.xp)
check("stats: per dungeon", st.dungeons[1] and st.dungeons[1].xpPerRun == 1400)

-- Formatting.
check("gold format", MS.FormatGold(123456) == "12g 34s" and MS.FormatGold(250) == "2s 50c" and MS.FormatGold(7) == "7c")
check("thousands", MS.FormatThousands(1234567) == "1,234,567" and MS.FormatThousands(999) == "999")

-- Quest XP: counted with the run as soon as the quest is done in here (no
-- need to hand it in), in its own colour; handed in inside, it isn't counted
-- twice.
do
    local sel = 0
    GetQuestLogSelection = function() return sel end
    SelectQuestLogEntry = function(i) sel = i end
    GetQuestLogRewardXP = function() local q = M.quests[sel]; return q and q.xp or 0 end
    GetQuestLogRewardMoney = function() local q = M.quests[sel]; return q and q.money or 0 end
    zone(WORLD); MS:AbandonRun(); M.RunTimers(2)
    zone(RFC)
    local r2 = MS.currentRun
    local p2 = r2.progress
    M.xp = 100; xp(100)
    M.quests[#M.quests + 1] = { title = "Rig Wars", id = 501, done = false, xp = 8200, money = 12000 }
    M.quests[#M.quests + 1] = { title = "Sparklematic", id = 502, done = false, xp = 3100 }
    M.Fire("QUEST_LOG_UPDATE"); M.RunTimers(2)
    sel = 2
    for _, id in ipairs({ 501, 502 }) do M.Fire("QUEST_WATCH_UPDATE", id) end
    M.quests[#M.quests - 1].done, M.quests[#M.quests].done = true, true
    M.Fire("QUEST_LOG_UPDATE"); M.RunTimers(2)
    check("quest xp: counted when done, not handed in", p2.qx == 11300 and p2.qg == 12000, tostring(p2.qx) .. " " .. tostring(p2.qg))
    check("quest xp: the log's selection put back", sel == 2, sel)
    check("quest xp: per quest", p2.questRewards and p2.questRewards[1].x == 8200 and p2.questRewards[2].x == 3100)
    xp(1100)                                            -- the dungeon: 1,000
    MS:ShowScoreboard(); M.RunTimers(2)
    local sub2 = MythicScoreboardFrame.Subline:GetText() or ""
    check("quest xp: header total", sub2:find("12,300") ~= nil, sub2)
    check("quest xp: header split bar", sub2:find("WHITE8X8") ~= nil, sub2)
    -- Rig Wars handed in here: the bar moves by its reward, which stays on the quest side.
    M.xp = 1100 + 8000; M.Fire("QUEST_TURNED_IN", 501, 8000, 12000); xp(9100)
    money(M.money + 12000)
    M.Fire("QUEST_TURNED_IN", 501, 8000, 12000)         -- the same hand-in reported again: once
    check("quest xp: handed in here, not counted twice", p2.xp == 1000 and p2.qx == 11100,
        tostring(p2.xp) .. " " .. tostring(p2.qx))
    check("quest gold: handed in here, not counted twice", p2.gold == 0 and p2.qg == 12000, tostring(p2.gold))
    for _, b in ipairs({ "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" }) do
        M.Fire("ENCOUNTER_START", 1, b); wait(30); M.Fire("ENCOUNTER_END", 1, b, 1, 5, 1); M.RunTimers(4)
    end
    zone(WORLD)
    local all = MS:ArchiveRuns()
    local e2 = all[#all]
    check("quest xp: archived apart", e2.prog and e2.prog.xp == 1000 and e2.prog.qx == 11100 and e2.prog.qg == 12000)
    local st2 = MS:StatsOverview()
    local rfc
    for _, d in ipairs(st2.dungeons) do if d.name == e2.dungeon then rfc = d end end
    check("quest xp: in the stats", rfc and rfc.questXP == 11100, rfc and rfc.questXP)
end

io.stdout:write(("runstats_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

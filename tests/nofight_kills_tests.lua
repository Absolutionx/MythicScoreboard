-- usage: lua5.1 nofight_kills_tests.lua DIR TOC   (Forever: boss kills with no boss fight, Krol'dok Stronghold)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local function wait(s) M.now = M.now + s; M.RunTimers(1) end
local function killed(name)
    for _, b in ipairs(MS.currentRun.bosses) do if b.killTime and b.name == name then return b end end
end
local function kills(name)
    local n = 0
    for _, b in ipairs(MS.currentRun.bosses) do if b.killTime and MS.SameBossName(b.name, name) then n = n + 1 end end
    return n
end
local function xpline(name) M.Fire("CHAT_MSG_COMBAT_XP_GAIN", name .. " dies, you gain 1450 experience."); M.RunTimers(1) end

M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
M.xp, M.xpMax, M.level = 4000, 50000, 42
M.Fire("ADDON_LOADED", "MythicScoreboard")
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
zone({ "Krol'dok Stronghold", "party", 1 })
check("run started", MS.currentRun ~= nil)

if MS.FLAVOR ~= "forever" then
    -- Retail: unchanged. A kill the game ends without starting stays unrecorded.
    wait(30)
    M.Fire("ENCOUNTER_END", 3453, "War Handler Ashka", 1, 5, 1); M.RunTimers(2)
    check("retail: an end without a start adds nothing", #MS.currentRun.bosses == 0, #MS.currentRun.bosses)
    io.stdout:write(("retail: %d passed, %d failed\n"):format(passes, fails))
    os.exit(fails == 0 and 0 or 1)
end

-- 1. A boss with both events: as ever.
wait(60)
M.Fire("ENCOUNTER_START", 3450, "Slavecrusher Grox"); wait(40)
M.Fire("ENCOUNTER_END", 3450, "Slavecrusher Grox", 1, 5, 1); M.RunTimers(2)
check("Grox: killed as ever", killed("Slavecrusher Grox") and killed("Slavecrusher Grox").pullTime < killed("Slavecrusher Grox").killTime)
xpline("Slavecrusher Grox")
check("Grox: its XP line doesn't add a second", kills("Slavecrusher Grox") == 1, kills("Slavecrusher Grox"))

-- 2. The game ends a fight it never started.
wait(300)
M.Fire("ENCOUNTER_END", 3453, "War Handler Ashka", 1, 5, 1); M.RunTimers(2)
local ashka = killed("War Handler Ashka")
check("Ashka: an end without a start is a kill", ashka ~= nil)
check("Ashka: its length unknown (no split)", ashka and ashka.pullTime == ashka.killTime)
check("Ashka: encounter noted", ashka and ashka.dungeonEncounterId == 3453)
M.Fire("ENCOUNTER_END", 3453, "War Handler Ashka", 1, 5, 1); M.RunTimers(2)
check("Ashka: the end twice is one kill", kills("War Handler Ashka") == 1, kills("War Handler Ashka"))
M.Fire("ENCOUNTER_END", 3453, "War Handler Ashka", 1, 5, 0); M.RunTimers(2)
check("Ashka: a wipe after doesn't undo it", killed("War Handler Ashka") ~= nil)

-- 3. No boss events at all: the XP line.
wait(200)
xpline("Krol'dok Brute")
check("trash: no boss", #MS.currentRun.bosses == 2, #MS.currentRun.bosses)
xpline("Bossman Toof")
check("Toof: the XP line is his kill", killed("Bossman Toof") ~= nil and killed("Bossman Toof").seen == "xp")
xpline("Bossman Toof")
check("Toof: once", kills("Bossman Toof") == 1, kills("Bossman Toof"))

-- 4. Another name for a boss ("Zarmok"): one kill, under either name.
xpline("Zarmok")
check("Zarmok: by his short name", killed("Zarmok") ~= nil and MS:ForeverSameBoss(MS.currentRun, "Zarmok", "Twilight Commander Zarmok"))
M.Fire("ENCOUNTER_END", 3452, "Twilight Commander Zarmok", 1, 5, 1); M.RunTimers(2)
local nZ = 0
for _, b in ipairs(MS.currentRun.bosses) do if b.killTime and (b.name == "Zarmok" or b.name == "Twilight Commander Zarmok") then nZ = nZ + 1 end end
check("Zarmok: the game's event after it is the same kill", nZ == 1, nZ)

-- 5. Gray to you, no XP, no event: the corpse on your target.
wait(120)
M.roster.target = { name = "Nar'gurk", guid = "Creature-0-1-2548-0-258964-0000ABCD", npc = true, hostile = true }
M.dead.target = nil
M.Fire("PLAYER_TARGET_CHANGED"); M.RunTimers(1)
check("alive on target: not a kill", not killed("Nar'gurk"))
M.dead.target = true
M.Fire("PLAYER_TARGET_CHANGED"); M.RunTimers(1)
check("Nar'gurk: the corpse is his kill", killed("Nar'gurk") ~= nil and killed("Nar'gurk").seen == "corpse")
-- A dead trash mob on a nameplate: nothing.
M.roster.nameplate3 = { name = "Krol'dok Brute", guid = "Creature-0-1-2548-0-258687-0000ABCE", npc = true, hostile = true }
M.dead.nameplate3 = true
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3"); M.RunTimers(1)
check("dead trash: no boss", kills("Krol'dok Brute") == 0)

-- 6. The final boss, named only by his NPC ID: the run is cleared.
check("not cleared yet", not MS.currentRun.completed)
wait(100)
M.roster.nameplate4 = { name = "", guid = "Creature-0-1-2548-0-258968-0000ABCF", npc = true, hostile = true }
M.dead.nameplate4 = true
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4"); M.RunTimers(5)
check("Mugg: his corpse by NPC ID", killed("Overlord Mugg") ~= nil)
check("cleared once the final boss is down", MS.currentRun.completed == true)
local done, total = MS:ForeverBossProgress(MS.currentRun)
check("6 of 6", done == 6 and total == 6, tostring(done) .. "/" .. tostring(total))

-- 7. Outside a dungeon: nothing.
zone({ "Badlands", "none", 0 })
local before = MS.currentRun and #MS.currentRun.bosses
xpline("Bossman Toof")
check("outside: nothing", not MS.currentRun or #MS.currentRun.bosses == before)

local function errorsPrinted() for _, p in ipairs(M.printed) do if p:find("rror") then return p end end end
check("no errors", not errorsPrinted(), errorsPrinted())
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR, passes, fails))
os.exit(fails == 0 and 0 or 1)

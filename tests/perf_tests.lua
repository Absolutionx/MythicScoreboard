-- usage: lua5.1 perf_tests.lua DIR TOC   (nothing piles up; no needless work)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local clock = 1800000000
time = function() return clock end
local function wait(s) M.now = M.now + s; clock = clock + s end
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local WORLD, RFC = { "Orgrimmar", "none", 0 }, { "Ragefire Chasm", "party", 1 }
M.instance = WORLD
dofile("fixtures/wc.lua")
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4)
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
local function objects() return #M.allFrames end

check("window not built at login", rawget(_G, "MythicScoreboardFrame") == nil and #M.allFrames < 120, #M.allFrames)
-- 0. Saved data made smaller on load, once, with nothing lost.
do
    local r = MythicScoreboardDB.runs[1]
    local jay = r.players["Jay-Breezy"]
    check("interrupts became plain times", type(jay.interruptEvents[1]) == "number" and #jay.interruptEvents == jay.interrupts,
        type(jay.interruptEvents[1]))
    local l = jay.loot[1]
    check("loot keeps its link only", l.link and not l.item and MS.LootItemString(l):find("^item:%d+"))
    check("times kept to two places", (tostring(r.bosses[1].killTime):match("%.(%d+)") or ""):len() <= 2, r.bosses[1].killTime)
    local arc = MS:ArchiveRuns()
    local al
    for _, e in ipairs(arc) do if e.loot then al = e.loot[1] end end
    check("archived loot keeps its link only", al and al.l and not al.i and MS.LootItemString(al))
    check("archive stored once (account-wide)", MythicScoreboardDB.archive == nil and #arc == 3)
    check("data versions up to date", MythicScoreboardDB.dataVersion == MS.DATA_VERSION and MS._ArchiveStore().v == MS.ARCHIVE_VERSION
        and MythicScoreboardDB.compact == nil and MythicScoreboardDB.historyRepair == nil)
end
local function shownText(pat)
    for _, w in ipairs(M.allFrames) do
        if w._shown and w._kind == "FontString" and w._text and w._text:find(pat) then return w end
    end
end

-- Meter readings, counted.
local reads = 0
local getType = C_DamageMeter.GetCombatSessionFromType
C_DamageMeter.GetCombatSessionFromType = function(...) reads = reads + 1; return getType(...) end
local function meter(d)
    local src = { { sourceGUID = UnitGUID("player"), name = UnitName("player"), isLocalPlayer = true,
                    totalAmount = d * 900, amountPerSecond = 900, classFilename = "SHAMAN" } }
    for _, t in ipairs({ 0, 2, 7, 8 }) do M.meter[t] = { duration = d, combatSources = src } end
    M.meter[5] = { duration = d, combatSources = { { sourceGUID = UnitGUID("player"), isLocalPlayer = true, totalAmount = 3 } } }
    M.meter[6] = { duration = d, combatSources = {} }; M.meter[9] = { duration = d, combatSources = {} }
end
local copies = 0
local ser = MS.SerializeRun
MS.SerializeRun = function(...) copies = copies + 1; return ser(...) end

-- 1. A live run with the window closed: nothing drawn, nothing copied.
check("nothing ticks out in the world", #M.tickers == 0, #M.tickers)
local before = objects()
zone(RFC)
check("meter and death polls run in a dungeon", #M.tickers == 2, #M.tickers)
for i, b in ipairs({ "Oggleflint", "Taragaman the Hungerer" }) do
    for _ = 1, 30 do wait(2); meter(M.now); M.Tick(); M.RunTimers(1) end
    M.Fire("ENCOUNTER_START", 1, b); for _ = 1, 10 do wait(2); meter(M.now); M.Tick(); M.RunTimers(1) end
    M.Fire("ENCOUNTER_END", 1, b, 1, 5, 1); M.RunTimers(4)
    MS:RecordDeathEvent(MS.currentRun.players[next(MS.currentRun.players)])
end
check("closed window: nothing drawn during a run", objects() - before < 20, objects() - before)
check("no copies of the run during play", copies == 0, copies)

-- 2. Meter: one read per stat type per update.
reads = 0
wait(2); meter(M.now); M.Tick(); M.RunTimers(1)
check("seven meter reads per update", reads == 7, reads)

-- 3. Open: the rows follow the live numbers.
MS:ShowScoreboard(); M.RunTimers(2)
reads = 0
wait(2); meter(M.now); M.Tick(); M.RunTimers(2)
check("still seven reads with the window open", reads == 7, reads)
local dmg1 = MS.currentRun.players[next(MS.currentRun.players)].damageDone
local function cellText()
    for _, r in ipairs(UI.overviewRows) do
        if r._statFs and r._player and (r._player.damageDone or 0) > 0 then
            return r._statFs.damage.main:GetText() .. r._statFs.damage.tail:GetText()
        end
    end
end
local t1 = cellText()
wait(60); meter(M.now); M.Tick(); M.RunTimers(2)
check("rows update on the poll", cellText() ~= t1, tostring(t1) .. " -> " .. tostring(cellText()))

-- 4. Leaving the world saves the run.
M.Fire("PLAYER_LEAVING_WORLD")
check("run saved at logout/reload", MythicScoreboardDB.activeRun and MythicScoreboardDB.activeRun._active == true)
check("one copy for it", copies == 1, copies)

-- 5. Timeline redraws reuse their pieces.
zone(WORLD)
check("only the pause timer ticks while paused", #M.tickers == 1, #M.tickers)
MS:ClosePausedRun()
check("nothing ticks after the run", #M.tickers == 0, #M.tickers)
MS:ShowScoreboard(); M.RunTimers(2)
local runs = MythicScoreboardDB.runs
for i = 1, 6 do MS.displayRun = runs[(i % #runs) + 1]; MS:RefreshOverview(); M.RunTimers(2) end
before = objects()
for i = 1, 50 do
    MS.displayRun = runs[(i % #runs) + 1]; MS:RefreshOverview(); M.RunTimers(2)
    local r = MS.displayRun
    if r.bosses and r.bosses[1] then UI.FocusBoss(r, r.bosses[i % #r.bosses + 1]); M.RunTimers(2) end
end
UI.FocusBoss(nil, nil); M.RunTimers(2)
check("50 timeline redraws add nothing", objects() - before < 10, objects() - before)
check("medallions still clickable", UI._medLayout and #UI._medLayout > 0)

-- 6. History dropdown opened and closed 20 times.
local hb = MythicScoreboardFrame.HistoryButton
hb:Fire("OnClick"); hb:Fire("OnClick")
before = objects()
for _ = 1, 20 do hb:Fire("OnClick"); hb:Fire("OnClick") end
check("history dropdown reused", objects() - before <= 0, objects() - before)
hb:Fire("OnClick")
check("history dropdown shows the runs", shownText("^Wailing Caverns$") ~= nil)
UI.CloseHistDropdown()

-- 7. Nameplates: no labels outside a key; one per plate inside.
local plates = {}
for i = 1, 5 do plates[i] = M.New("Frame") end
C_NamePlate.GetNamePlateForUnit = function(u) local n = tonumber(u:match("%d+")); return plates[(n - 1) % 5 + 1] end
UnitCanAttack = function() return true end
C_ScenarioInfo.GetUnitCriteriaProgressValues = function() return 3, 0.4, "0.40" end
local function churn()
    for i = 1, 200 do
        local u = "nameplate" .. ((i % 12) + 1)
        M.roster[u] = { name = "Mob", guid = "Creature-0-1", npc = true }
        M.Fire("NAME_PLATE_UNIT_ADDED", u); M.Fire("NAME_PLATE_UNIT_REMOVED", u)
    end
end
before = objects()
churn()
check("no nameplate labels outside a key", objects() - before == 0, objects() - before)
zone({ "Altar of Fangs", "party", 8 })
before = objects()
churn(); churn()
check("at most one label per plate in a key", objects() - before <= 5, objects() - before)
M.roster["nameplate1"] = { name = "Mob", guid = "Creature-0-1", npc = true }
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check("label shows the forces", plates[1].MythicScoreboardForces ~= nil)
zone(WORLD)

for _, p in ipairs(M.printed) do if p:lower():find("error") then check("no errors", false, p) end end
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

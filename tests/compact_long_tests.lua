-- usage: lua5.1 compact_long_tests.lua DIR TOC   (Forever: the in-run frame with many bosses; the limit line)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if MS.FLAVOR ~= "forever" then io.stdout:write("retail: 0 passed, 0 failed (WoW Forever only)\n"); os.exit(0) end
local function frame() return rawget(_G, "MythicScoreboardCompact") end
local function texts()
    local f, out = frame(), {}
    for _, w in ipairs(M.allFrames) do
        if w._shown and w._kind == "FontString" and w._parent == f and w._text and w._text ~= "" then out[#out + 1] = w end
    end
    return out
end
local function shown(pat) for _, w in ipairs(texts()) do if w._text:find(pat) then return w._text end end end
local function bossRows()
    local def = MS.FOREVER_DUNGEONS["Blackrock Depths"]
    local n = 0
    for _, w in ipairs(texts()) do
        local t = w._text
        if t:find("^%d+ killed$") or t:find("^%+%d+ more") then n = n + 1
        else for _, b in ipairs(def.bosses) do if t == b.name then n = n + 1 end end end
    end
    return n
end
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local function wait(s) M.now = M.now + s; M.RunTimers(1) end
local clock = 1800000000
time = function() return clock end
M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
M.level = 58
M.Fire("ADDON_LOADED", "MythicScoreboard")
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
zone({ "Blackrock Depths", "party", 1 })
MS:RefreshCompact(); M.RunTimers(2)
check("frame shown", frame() and frame()._shown)
check("no more than 8 boss lines", bossRows() <= 8, bossRows())
check("the final boss listed", shown("^Emperor Dagran Thaurissan$"))
check("the rest as '+N more'", shown("^%+%d+ more$"))
check("the first boss listed", shown("^High Interrogator Gerstahn$"))

-- Kill the first six: the earlier ones fold into one line.
local order = { "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Ring of Law", "Pyromancer Loregrain", "Fineous Darkvire" }
for _, name in ipairs(order) do
    wait(60); clock = clock + 60
    M.Fire("ENCOUNTER_START", nil, name); wait(20)
    M.Fire("ENCOUNTER_END", nil, name, 1, 5, 1); M.RunTimers(2)
end
MS:RefreshCompact(); M.RunTimers(2)
check("after six kills: still 8 lines at most", bossRows() <= 8, bossRows())
check("earlier kills folded", shown("^4 killed$"), shown("killed$"))
check("latest kill shown", shown("^Fineous Darkvire$") and shown("^Pyromancer Loregrain$"))
check("an early kill folded away", not shown("^Lord Roccor$"))
check("final still there", shown("^Emperor Dagran Thaurissan$"))

-- The fight you're in: "fighting" on the right, the name left at its size.
M.Fire("ENCOUNTER_START", nil, "Warder Stilgiss"); M.RunTimers(1)
MS:RefreshCompact(); M.RunTimers(1)
check("fighting: the name alone", shown("^Warder Stilgiss$"))
check("fighting: said on its own", shown("fighting"))
-- With the boss's frame up: its health in place of "fighting", and a bar.
local ue, uh, um = UnitExists, rawget(_G, "UnitHealth"), rawget(_G, "UnitHealthMax")
UnitExists = function(u) return u == "boss1" or ue(u) end
rawset(_G, "UnitHealth", function() return 600 end)
rawset(_G, "UnitHealthMax", function() return 1000 end)
MS:RefreshCompact(); M.RunTimers(1)
check("fighting: the boss's health", shown("^60%%$"), shown("%%"))
rawset(_G, "UnitHealth", function() return 250 end)
local bar
for _, fr in ipairs(M.allFrames) do if fr.pct and fr.SetStatusBarColor then bar = fr end end
bar:Fire("OnUpdate", 0.25)
check("fighting: health follows the fight", shown("^25%%$"), shown("%%"))
-- No boss frame: the boss as your target, by name.
local un = UnitName
UnitExists = function(u) return u == "target" or ue(u) end
UnitName = function(u) if u == "target" then return "Warder Stilgiss" end return un(u) end
rawset(_G, "UnitHealth", function() return 410 end)
bar:Fire("OnUpdate", 0.25)
check("fighting: the boss as your target", shown("^41%%$"), shown("%%"))
UnitName = function(u) if u == "target" then return "Some Trash Mob" end return un(u) end
bar:Fire("OnUpdate", 0.25)
check("fighting: not a target that isn't the boss", not shown("^41%%$"))
-- The name hidden in a fight: the boss found by which creature it is.
local ug = UnitGUID
local secretName = { __secret = true }
UnitName = function(u) if u == "target" then return secretName end return un(u) end
UnitGUID = function(u) if u == "target" then return "Creature-0-1-2-3-9999-0001" end return ug(u) end
local bossNpc = MS.BossNpcID
MS.BossNpcID = function(_, name) if name == "Warder Stilgiss" then return 9999 end return bossNpc(MS, name) end
rawset(_G, "UnitHealth", function() return 330 end)
bar:Fire("OnUpdate", 0.25)
check("fighting: a hidden name, found by creature", shown("^33%%$"), shown("%%"))
UnitGUID = function(u) if u == "target" then return "Creature-0-1-2-3-1234-0001" end return ug(u) end
bar:Fire("OnUpdate", 0.25)
check("fighting: another creature isn't the boss", not shown("^33%%$"))
-- In instances the game hides who a unit is (name and creature): then the
-- boss is the elite in the fight with the highest level.
UnitGUID = function(u) if u == "target" or u == "nameplate3" then return secretName end return ug(u) end
UnitName = function(u) if u == "target" or u == "nameplate3" then return secretName end return un(u) end
local lv = { target = 15, nameplate3 = 16 }
local keepG = {}
for _, k in ipairs({ "UnitCanAttack", "UnitClassification", "UnitAffectingCombat", "UnitEffectiveLevel", "C_NamePlate" }) do keepG[k] = rawget(_G, k) end
rawset(_G, "UnitCanAttack", function() return true end)
rawset(_G, "UnitClassification", function() return "elite" end)
rawset(_G, "UnitAffectingCombat", function() return true end)
rawset(_G, "UnitEffectiveLevel", function(u) return lv[u] end)
rawset(_G, "C_NamePlate", { GetNamePlates = function() return { { namePlateUnitToken = "nameplate3" } } end })
UnitExists = function(u) return u == "target" or u == "nameplate3" or ue(u) end
check("hidden: the highest elite is the boss (a trash mob targeted)", MS.UI._BossUnit("Warder Stilgiss") == "nameplate3",
    MS.UI._BossUnit("Warder Stilgiss"))
lv.target = 16; lv.nameplate3 = 14
check("hidden: the boss targeted", MS.UI._BossUnit("Warder Stilgiss") == "target")
lv.nameplate3 = -1
check("hidden: a skull outranks", MS.UI._BossUnit("Warder Stilgiss") == "nameplate3")
for k, v in pairs(keepG) do rawset(_G, k, v) end
MS.BossNpcID, UnitGUID = bossNpc, ug
UnitExists = ue; UnitName = un; rawset(_G, "UnitHealth", uh); rawset(_G, "UnitHealthMax", um)
M.Fire("ENCOUNTER_END", nil, "Warder Stilgiss", 1, 5, 1); M.RunTimers(2)
MS:RefreshCompact(); M.RunTimers(1)
check("fighting gone after the kill", not shown("fighting"))
order[#order + 1] = "Warder Stilgiss"

-- Hovering a folded line names what it stands for.
local tip = {}
GameTooltip.SetText = function(_, t) tip = { t } end
GameTooltip.AddDoubleLine = function(_, l, r) tip[#tip + 1] = l .. "|" .. r end
GameTooltip.AddLine = function(_, l) tip[#tip + 1] = l end
local function hover(kind)
    for _, w in ipairs(M.allFrames) do
        if w._shown and w.row and w.row[kind] and w._scripts and w._scripts.OnEnter then w:Fire("OnEnter"); return true end
    end
end
check("the killed line can be hovered", hover("folded"))
check("its tooltip: the folded kills, first one first", tip[2] and tip[2]:find("^High Interrogator Gerstahn|%d") and #tip == 6,
    table.concat(tip, " / "))
check("its tooltip: Lord Roccor's kill time", (table.concat(tip, "\n")):find("Lord Roccor|%d+:%d%d"))
check("the more line can be hovered", hover("more"))
check("its tooltip: the bosses to come, in order", tip[1] == "+8 more" and #tip == 9 and tip[2] == "Golem Lord Argelmach",
    table.concat(tip, " / "))

-- The limit's line: short enough not to be cut.
local line = shown("^Next frees at")
check("limit line short", line and not line:find("Blackrock Depths"), line)

-- Redrawn once a second, not on every tick, when nothing else changes.
do
    local real, n = MS.RefreshCompact, 0
    MS.RefreshCompact = function(...) n = n + 1; return real(...) end
    local fr = frame()
    M.now = math.floor(M.now) + 0.1
    for _ = 1, 4 do fr:Fire("OnUpdate", 0.25) end            -- the same second
    check("ticks within a second: one redraw", n == 1, n)
    M.now = M.now + 1
    fr:Fire("OnUpdate", 0.25)
    check("the next second: redrawn", n == 2, n)
    MS.RefreshCompact = real
end

-- The clock shows every second, once: a run that started part way through
-- a second, the game at 60 frames a second (it skipped one now and then).
do
    local run, fr = MS.currentRun, frame()
    local real, shownSecs = MS.RefreshCompact, {}
    MS.RefreshCompact = function(...)
        shownSecs[#shownSecs + 1] = math.floor(MS:GetRunDuration(run))
        return real(...)
    end
    for _, start in ipairs({ 0.02, 0.13, 0.24, 0.5, 0.97 }) do
        for k in pairs(shownSecs) do shownSecs[k] = nil end
        run.startTime = math.floor(M.now) - 100 + start
        for _ = 1, 60 * 20 do M.now = M.now + 1 / 60; fr:Fire("OnUpdate", 1 / 60) end
        local skipped, twice = 0, 0
        for i = 2, #shownSecs do
            local d = shownSecs[i] - shownSecs[i - 1]
            if d > 1 then skipped = skipped + 1 elseif d == 0 then twice = twice + 1 end
        end
        check("started at ." .. start .. ": no second skipped", skipped == 0, skipped)
        check("started at ." .. start .. ": each second once", twice == 0 and #shownSecs >= 19, twice .. " " .. #shownSecs)
    end
    MS.RefreshCompact = real
end

-- The demo, in a dungeon you name.
zone({ "Orgrimmar", "none", 0 })
if MS.currentRun and MS.currentRun._suspended then MS:ClosePausedRun() end
SlashCmdList.MYTHICSCOREBOARD("compact demo Blackrock Depths"); M.RunTimers(2)
local d = MS._CompactDemo()
check("demo in Blackrock Depths", d and d.dungeonName == "Blackrock Depths", d and d.dungeonName)
-- The demo's boss fight shows made-up health, as a real one would.
local fought
for _ = 1, 600 do
    M.now = M.now + 1; MS:RefreshCompact(); M.RunTimers(1)
    if d.activeBoss and not d.activeBoss.killTime then fought = d.activeBoss; break end
end
check("demo fight: the boss's health", fought and fought.demoHealth and shown("^" .. fought.demoHealth .. "%%$"),
    fought and fought.demoHealth)
SlashCmdList.MYTHICSCOREBOARD("compact demo"); M.RunTimers(2)
check("demo again: hidden", MS._CompactDemo() == nil)
SlashCmdList.MYTHICSCOREBOARD("compact demo depths"); M.RunTimers(2)
check("part of the name will do", MS._CompactDemo() and MS._CompactDemo().dungeonName == "Blackrock Depths")
SlashCmdList.MYTHICSCOREBOARD("compact demo"); M.RunTimers(2)
SlashCmdList.MYTHICSCOREBOARD("compact demo nowhere at all"); M.RunTimers(2)
check("unknown name: said so, no demo", MS._CompactDemo() == nil and M.printed[#M.printed]:find("nowhere at all"), M.printed[#M.printed])

-- Garbage and redraws: in game the addon showed 56 MB, from about 30 KB of
-- garbage a redraw, and a redraw for every change (a pull's kills, XP, loot).
do
    zone({ "Blackrock Depths", "party", 1 })
    MS:RefreshCompact(); M.RunTimers(2)
    local fr = frame()
    check("back in BRD: shown", fr._shown and MS.inDungeon)
    collectgarbage("collect"); collectgarbage("stop")
    local a = collectgarbage("count")
    for _ = 1, 50 do M.now = M.now + 1; MS:RefreshCompact() end
    local per = (collectgarbage("count") - a) / 50
    collectgarbage("restart")
    check("a redraw: little garbage (the mock's own included)", per < 15, string.format("%.1f KB", per))
    -- A burst of changes: one redraw, at the frame's next check.
    local real, n = MS.RefreshCompact, 0
    MS.RefreshCompact = function(...) n = n + 1; return real(...) end
    for _ = 1, 20 do MS:Changed("run") end
    check("20 changes: none drawn at once", n == 0, n)
    fr:Fire("OnUpdate", 0.06)
    check("20 changes: drawn once", n == 1, n)
    fr:Fire("OnUpdate", 0.06)
    check("nothing new: not again", n == 1, n)
    MS.RefreshCompact = real
    -- The boss list kept between fights still changes as a fight starts and ends.
    local boss = "High Interrogator Gerstahn"
    wait(30); M.Fire("ENCOUNTER_START", nil, boss); M.RunTimers(1)
    fr:Fire("OnUpdate", 0.06)
    check("pulled: fighting", shown("fighting"))
    M.Fire("ENCOUNTER_END", nil, boss, 1, 5, 1); M.RunTimers(2)
    M.now = M.now + 1; fr:Fire("OnUpdate", 0.06)
    check("killed: within a second, no longer fighting", not shown("fighting"))
end

local function errorsPrinted() for _, p in ipairs(M.printed) do if p:find("rror") then return p end end end
check("no errors", not errorsPrinted(), errorsPrinted())
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR, passes, fails))
os.exit(fails == 0 and 0 or 1)

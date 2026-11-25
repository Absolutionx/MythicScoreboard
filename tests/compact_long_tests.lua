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
SlashCmdList.MYTHICSCOREBOARD("compact demo"); M.RunTimers(2)
check("demo again: hidden", MS._CompactDemo() == nil)
SlashCmdList.MYTHICSCOREBOARD("compact demo depths"); M.RunTimers(2)
check("part of the name will do", MS._CompactDemo() and MS._CompactDemo().dungeonName == "Blackrock Depths")
SlashCmdList.MYTHICSCOREBOARD("compact demo"); M.RunTimers(2)
SlashCmdList.MYTHICSCOREBOARD("compact demo nowhere at all"); M.RunTimers(2)
check("unknown name: said so, no demo", MS._CompactDemo() == nil and M.printed[#M.printed]:find("nowhere at all"), M.printed[#M.printed])

local function errorsPrinted() for _, p in ipairs(M.printed) do if p:find("rror") then return p end end end
check("no errors", not errorsPrinted(), errorsPrinted())
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR, passes, fails))
os.exit(fails == 0 and 0 or 1)

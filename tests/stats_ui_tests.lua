-- usage: lua5.1 stats_ui_tests.lua DIR TOC
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
M.Fire("ADDON_LOADED", "MythicScoreboard")
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
local function playRun(dungeon, secs, cleared)
    clock = clock + 86400
    zone({ dungeon, "party", 1 })
    local run = MS.currentRun
    table.insert(run.bosses, { name = "Oggleflint", pullTime = 60, killTime = 90 })
    MS:PlayerForUnit("player").dps = 200
    run.completed = cleared
    M.now = M.now + secs; run.startTime = M.now - secs
    zone(WORLD)
    if MS.currentRun and MS.currentRun._suspended then MS:ClosePausedRun() end
end
for i, s in ipairs({ 900, 760, 1300, 820, 700 }) do playRun("Ragefire Chasm", s, i ~= 3) end
playRun("The Deadmines", 1500, true)
playRun("Wailing Caverns", 1700, false)

if not MythicScoreboardFrame then MS:BuildUI() end   -- built on first open
local f = MythicScoreboardFrame
-- Errors inside the addon's own refresh are printed, not raised: collect them.
local function errorsPrinted()
    for _, p in ipairs(M.printed) do if p:find("error") then return p end end
end
local function shownChildren(parent, kind)
    local n = 0
    for _, w in ipairs(parent._children or {}) do if w._shown and (not kind or w._kind == kind) then n = n + 1 end end
    return n
end

-- Open from the header button.
MS:ShowScoreboard(); M.RunTimers(2)
f.StatsBtn:Fire("OnClick"); M.RunTimers(2)
check("stats open", UI.statsOpen == true)
check("title", f.DungeonName:GetText() == "Your stats", f.DungeonName:GetText())
check("summary line", f.Subline:GetText():find("7") and f.Subline:GetText():find("runs")
    and f.Subline:GetText():find("5") and f.Subline:GetText():find("cleared"), f.Subline:GetText())
check("table hidden", not f.ColHeader:IsShown() and not f.overviewSF:IsShown() and not f.timelineContainer:IsShown())
check("no refresh errors", not errorsPrinted(), errorsPrinted())

-- A live refresh must not overwrite the Stats header.
MS:RefreshOverview(); M.RunTimers(2)
check("refresh keeps stats header", f.DungeonName:GetText() == "Your stats")

-- Overview rows: one per dungeon, most recent first.
local stats = MS:StatsOverview()
check("three dungeons", #stats.dungeons == 3, #stats.dungeons)
check("most recent first", stats.dungeons[1].name == "Wailing Caverns")
local rfc
for _, d in ipairs(stats.dungeons) do if d.name == "Ragefire Chasm" then rfc = d end end
check("rfc best/typical", rfc.best == 700 and rfc.typical == 790, (rfc.best or "nil") .. " " .. tostring(rfc.typical))

-- Find the dungeon rows the page drew (Buttons with .dungeon set).
local rows = {}
for _, w in ipairs(M.allFrames) do if w.dungeon and w._shown then rows[#rows + 1] = w end end
check("rows drawn", #rows == 3, #rows)
local rfcRow
for _, r in ipairs(rows) do if r.dungeon == "Ragefire Chasm" then rfcRow = r end end
check("row text", rfcRow and rfcRow.cells.best:GetText() == "11:40" and rfcRow.cells.cleared:GetText() == "80%",
    rfcRow and (rfcRow.cells.best:GetText() .. " " .. rfcRow.cells.cleared:GetText()))
local shownBars = 0
for _, b in ipairs(rfcRow.bars) do if b._shown then shownBars = shownBars + 1 end end
check("recent bars", shownBars == 5, shownBars)

-- Open the dungeon.
rfcRow:Fire("OnEnter"); rfcRow:Fire("OnLeave")
rfcRow:Fire("OnClick"); M.RunTimers(2)
local runRows, chartBars = 0, 0
for _, w in ipairs(M.allFrames) do
    if w.entry and w._shown then
        if w.cells then runRows = runRows + 1 else chartBars = chartBars + 1 end
    end
end
check("detail run list", runRows == 5, runRows)
check("detail chart bars", chartBars == 5, chartBars)
check("no detail errors", not errorsPrinted(), errorsPrinted())
for _, w in ipairs(M.allFrames) do
    if w.entry and w._shown then w:Fire("OnEnter"); w:Fire("OnLeave") end
end
check("no tooltip errors", not errorsPrinted(), errorsPrinted())

-- Back to the overview.
local back
for _, w in ipairs(M.allFrames) do
    if w._kind == "Button" and w._scripts.OnClick and w._shown and w._children then
        for _, c in ipairs(w._children) do if c._kind == "FontString" and c._text == "All dungeons" then back = w end end
    end
end
check("back button found", back ~= nil)
if back then back:Fire("OnClick"); M.RunTimers(2) end
local stillDetail = 0
for _, w in ipairs(M.allFrames) do if w.entry and w._shown and w.cells then stillDetail = stillDetail + 1 end end

-- Picking a run from history closes Stats.
UI.OpenStats(); M.RunTimers(2)
f.HistoryButton:Fire("OnClick")
local histRow
for _, w in ipairs(M.allFrames) do
    if w._shown and w._kind == "Button" and w._scripts.OnClick and w ~= f.HistoryButton and w._parent and w._parent._kind == "Frame"
            and w._parent ~= f and w._parent._parent == UIParent then histRow = histRow or w end
end
if histRow then histRow:Fire("OnClick"); M.RunTimers(2) end
check("history row found", histRow ~= nil); check("history pick closes stats", UI.statsOpen == false)

-- Toggle back and close via the button.
UI.OpenStats(); M.RunTimers(2)
f.StatsBtn:Fire("OnClick"); M.RunTimers(2)
check("button closes stats", UI.statsOpen == false and f.ColHeader:IsShown() and f.overviewSF:IsShown())
check("title restored", f.DungeonName:GetText() ~= "Your stats", f.DungeonName:GetText())

-- Slash command opens it.
SlashCmdList["MYTHICSCOREBOARD"]("stats"); M.RunTimers(2)
check("/sb stats", UI.statsOpen == true)
check("no errors at all", not errorsPrinted(), errorsPrinted())

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

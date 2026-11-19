-- usage: lua5.1 trends_tests.lua DIR TOC
-- The Stats page's Trends tab (Core/Trends.lua, Core/UI_StatsTrends.lua):
-- the activity calendar, this week against last and the streak; your DPS run
-- by run and its trend; XP and gold an hour by dungeon (WoW Forever) or your
-- DPS by dungeon (elsewhere); and the tab drawing it.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
local NOW = os.time({ year = 2026, month = 11, day = 18, hour = 17, min = 0, sec = 0 })   -- a Wednesday
time = function(t) if t then return os.time(t) end return NOW end
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4)
local forever = MS.Flavor.progressStats

-- Runs made up for the test, the Stats page's runs in place of the archive's.
local function At(daysAgo, hour) return os.time({ year = 2026, month = 11, day = 18 - daysAgo, hour = hour or 20 }) end
local runs = {}
local function Run(daysAgo, dungeon, dur, dps, extra)
    local e = { at = At(daysAgo), dungeon = dungeon, dur = dur, cleared = true, deaths = 0,
                me = { dps = dps, hps = 5, lvl = 30, ilvl = 20, role = "DAMAGER" } }
    for k, v in pairs(extra or {}) do e[k] = v end
    runs[#runs + 1] = e
    return e
end
-- Today, yesterday and the day before: a three-day streak. Last week, a five-day one.
Run(0, "Gnomeregan", 1800, 100)
Run(0, "Gnomeregan", 1500, 110, { at = At(0, 21) })
Run(1, "Razorfen Kraul", 1200, 120)
Run(2, "Razorfen Kraul", 1300, 130)
for d = 4, 8 do Run(d, "Wailing Caverns", 2400, 60 + d) end   -- Tuesday to Saturday last week
Run(60, "Ragefire Chasm", 1000, 20)
table.sort(runs, function(a, b) return a.at < b.at end)
local rev = 1000
function MS:StatsRuns() return runs end
function MS:StatsRevision() return rev end

-- ── Activity ───────────────────────────────────────────────────────────────
local ts = MS:TrendStats()
local a = ts.activity
check("a square a day for 26 weeks", #a.cells == 26 * 7, #a.cells)
local todayCell, future
for _, c in ipairs(a.cells) do
    if os.date("%Y%m%d", c.at) == "20261118" then todayCell = c end
    if c.future then future = (future or 0) + 1 end
end
check("today's square: two runs", todayCell and todayCell.runs == 2 and todayCell.time == 3300, todayCell and todayCell.runs)
check("the days after today aren't counted", future == 3, future)        -- Thursday, Friday, Saturday
check("the busiest day sets the scale", a.most == 2, a.most)
check("this week: since Sunday", a.thisWeek.runs == 4 and a.thisWeek.time == 5800, a.thisWeek.runs .. " " .. a.thisWeek.time)
check("last week", a.lastWeek.runs == 5, a.lastWeek.runs)
check("the streak: today and the two days before", a.streak == 3, a.streak)
check("the best streak", a.bestStreak == 5, a.bestStreak)

-- No run yet today: yesterday's streak still counts.
local today = table.remove(runs); local today2 = table.remove(runs)
rev = rev + 1
check("no run yet today: the streak goes on", MS:TrendStats().activity.streak == 2, MS:TrendStats().activity.streak)
runs[#runs + 1] = today2; runs[#runs + 1] = today
rev = rev + 1

-- ── Performance ────────────────────────────────────────────────────────────
local perf = MS:TrendStats().perf
check("a point a run with numbers", #perf.points == #runs, #perf.points)
check("in time order", perf.points[1].v == 20 and perf.points[#perf.points].v == 110)
check("DPS when you mostly deal damage", not perf.heals)
check("the trend: the average of the last five", math.abs(perf.points[#perf.points].avg - (64 + 130 + 120 + 100 + 110) / 5) < 0.01,
    perf.points[#perf.points].avg)
check("the trend went up", perf.change and perf.change > 0, perf.change)
for _, e in ipairs(runs) do e.me.role = "HEALER" end
rev = rev + 1
check("HPS when you mostly heal", MS:TrendStats().perf.heals and MS:TrendStats().perf.points[1].v == 5)
for _, e in ipairs(runs) do e.me.role = "DAMAGER" end
rev = rev + 1

-- ── Farming (WoW Forever) / DPS by dungeon ─────────────────────────────────
if forever then
    -- 55 minutes of Gnomeregan for 60,000 XP and 2g; half an hour of Kraul for 60,000 XP.
    runs[#runs].prog = { xp = 30000, qx = 0, g = 10000, qg = 0 }
    runs[#runs - 1].prog = { xp = 25000, qx = 5000, g = 8000, qg = 2000 }
    runs[#runs].me.lvl, runs[#runs - 1].me.lvl = 31, 30
    runs[#runs - 2].prog = { xp = 30000, g = 1000 }; runs[#runs - 2].dur = 900
    runs[#runs - 3].prog = { xp = 30000, g = 1000 }; runs[#runs - 3].dur = 900
    -- Far below your level: Ragefire, very quick.
    runs[1].prog = { xp = 50000, g = 0 }; runs[1].me.lvl = 15; runs[1].dur = 600
    local level = 30
    UnitLevel = function() return level end
    rev = rev + 1
    local f = MS:TrendStats().farming
    check("farming: your level", f.level == 30, f.level)
    local gn
    for _, d in ipairs(f.rows) do if d.dungeon == "Gnomeregan" then gn = d end end
    check("farming: XP an hour, quests included", gn and math.abs(gn.xpHour - 60000 / 3300 * 3600) < 1, gn and gn.xpHour)
    check("farming: gold an hour, quests included", gn and math.abs(gn.goldHour - 20000 / 3300 * 3600) < 1, gn and gn.goldHour)
    check("farming: the levels it was run at", gn and gn.lo == 30 and gn.hi == 31)
    check("farming: near your level first", f.rows[#f.rows].dungeon == "Ragefire Chasm" and not f.rows[#f.rows].near,
        f.rows[#f.rows].dungeon)
    check("farming: best XP an hour on top", f.rows[1].dungeon == "Razorfen Kraul", f.rows[1].dungeon)
    -- At the top level, nothing gives XP: by gold.
    for _, e in ipairs(runs) do if e.prog then e.prog.xp, e.prog.qx = 0, 0 end end
    rev = rev + 1
    f = MS:TrendStats().farming
    check("farming: no XP to be had, by gold", f.byGold and f.rows[1].dungeon == "Gnomeregan", f.rows[1].dungeon)
else
    local rows = MS:TrendStats().byDungeon
    check("by dungeon: one row each", #rows == 4, #rows)
    check("by dungeon: best average first", rows[1].dungeon == "Razorfen Kraul" and rows[1].avg == 125, rows[1].dungeon)
end

-- ── The tab ────────────────────────────────────────────────────────────────
local UI = MS.UI
UI.OpenStats()
UI.StatsKit.S.tab = "trends"
UI.RefreshStats(true)
local function Shown(text)
    for _, w in ipairs(M.allFrames) do
        if w._kind == "FontString" and w._shown and w._text == text then return w end
    end
end
check("tab: the calendar's heading", Shown("Activity"))
check("tab: the chart's choices", Shown("DPS") and Shown("Run time") and Shown("All dungeons") and Shown("All time"))
check("tab: this week", Shown("This week"))
check("tab: the list's heading", Shown(forever and "XP and gold an hour" or "Your DPS by dungeon"))
check("tab: a row per dungeon", Shown("Gnomeregan") and Shown("Razorfen Kraul"))

-- ── The chart's choices, the list's order, a day's runs ───────────────────
local TS = UI.StatsKit.S
local function Find(test)
    for _, w in ipairs(M.allFrames) do if w._scripts.OnClick and test(w) then return w end end
end
local function Choose(label)
    local b = Find(function(w) return w.SetOn and w.text and w.text._text == label end)
    check("chart: the " .. label .. " button", b)
    if b then local ok, err = pcall(b.Fire, b, "OnClick"); check("chart: " .. label .. " draws", ok, err) end
end
for _, label in ipairs({ "HPS", "Run time", "Damage taken", "Deaths", "DPS" }) do Choose(label) end
if forever then Choose("XP an hour"); Choose("Gold an hour") end
check("chart: the last choice sticks", TS.trendMetric == (forever and "gold" or "dps"), TS.trendMetric)
Choose("7 days")
check("chart: the last 7 days", TS.trendRange == 7)
check("chart: 7 days' runs", #MS:TrendRuns(nil, 7) == 8, #MS:TrendRuns(nil, 7))
Choose("All time")
check("chart: all time", TS.trendRange == nil)
local dd = Find(function(w) return w.text and w.text._text == "All dungeons" and not w.SetOn end)
check("chart: the dungeon filter", dd)
if dd then dd:Fire("OnClick") end
local pick = Find(function(w) return w.key == "Gnomeregan" and w.lbl end)
check("filter: Gnomeregan in its list", pick)
if pick then pick:Fire("OnClick") end
check("filter: one dungeon", TS.trendDungeon == "Gnomeregan", TS.trendDungeon)
check("filter: its runs", #MS:TrendRuns("Gnomeregan") == 2)
check("filter: the list most run first", MS:TrendDungeons()[1].dungeon == "Wailing Caverns")
TS.trendDungeon, TS.trendMetric = nil, nil
UI.RefreshStats(true)

-- The list's headers: sort, the other way, back to the usual.
local hdr = Find(function(w) return w.arrow and w.Look end)
check("list: a header to sort by", hdr)
if hdr then
    hdr:Fire("OnClick"); check("list: sorted", TS.trendSort and TS.trendSort.turns == 1)
    local first = TS.trendSort and TS.trendSort.desc
    hdr:Fire("OnClick"); check("list: the other way", TS.trendSort and TS.trendSort.desc ~= first)
    hdr:Fire("OnClick"); check("list: the usual order", TS.trendSort == nil)
end
TS.trendSort = { key = "dungeon", desc = false, turns = 1 }
local ok2, err2 = pcall(UI.RefreshStats, true)
check("list: sorted by name draws", ok2, err2)
TS.trendSort = nil

-- A day's runs: click its square; again to close.
local cell = Find(function(w) return w.ring and w.cell and w.cell.runs == 2 end)
check("calendar: today's square", cell)
if cell then cell:Fire("OnClick") end
check("calendar: the day opens", TS.trendDay ~= nil)
local dayRow = Find(function(w) return w.entry and w.clock and w._shown end)
check("day: a row a run", dayRow and dayRow.entry.dungeon == "Gnomeregan")
local d = MS:TrendDay(NOW)
check("day: its runs and time", #d.runs == 2 and d.time == 3300, #d.runs)
if cell then cell:Fire("OnClick") end
check("calendar: again closes it", TS.trendDay == nil)
local empty = Find(function(w) return w.ring and w.cell and w.cell.runs == 0 end)
if empty then empty:Fire("OnClick") end
check("calendar: a day without runs doesn't open", TS.trendDay == nil)

-- ── A dungeon's breakdown ──────────────────────────────────────────────────
local gA, gB = runs[#runs - 1], runs[#runs]          -- the two Gnomeregan runs (30 and 25 minutes)
gA.me.lvl, gB.me.lvl = 30, 31
gA.prog = { xp = 20000, qx = 10000, g = 5000, qg = 5000, k = 40, q = 2, rep = { ["Gnomeregan Exiles"] = 100 } }
gB.prog = { xp = 30000, g = 10000, k = 60, q = 0 }
gA.deaths = 2
rev = rev + 1
local b = MS:TrendDungeon("Gnomeregan")
check("breakdown: its runs", b and b.runs == 2 and b.allRuns == 2, b and b.runs)
check("breakdown: typical and fastest clear", b.typical == 1650 and b.fastest == 1500, tostring(b.typical) .. " " .. tostring(b.fastest))
check("breakdown: deaths a run", b.deathsRun == 1, b.deathsRun)
check("breakdown: the latest run first", b.recent[1] == gB and b.recent[2] == gA)
check("breakdown: a point a run", #b.points == 2)
check("breakdown: unknown dungeon", MS:TrendDungeon("Nowhere") == nil)
if forever then
    check("breakdown: XP, from the dungeon and quests", b.xp == 60000 and b.mobXP == 50000 and b.questXP == 10000, b.xp)
    check("breakdown: gold, looted and quests", b.gold == 20000 and b.lootGold == 15000 and b.questGold == 5000, b.gold)
    check("breakdown: XP an hour", math.abs(b.xpHour - 60000 / 3300 * 3600) < 1, b.xpHour)
    check("breakdown: mobs a run", b.killsRun == 50, b.killsRun)
    check("breakdown: reputation", b.rep[1] and b.rep[1].faction == "Gnomeregan Exiles" and b.rep[1].amount == 100)
    check("breakdown: by level, highest first", #b.groups == 2 and b.groups[1].key == 31 and b.groups[2].key == 30)
    check("breakdown: a level's XP an hour", math.abs(b.groups[1].xpHour - 30000 / 1500 * 3600) < 1, b.groups[1].xpHour)
    check("breakdown: the best run", b.bestPoint and b.bestPoint.e == gB)
else
    check("breakdown: your DPS", b.avgDps == 105 and b.best == 110, b.avgDps)
    check("breakdown: one difficulty", #b.groups == 1, #b.groups)
    check("breakdown: the best run", b.bestPoint and b.bestPoint.e == gB)
end

-- Clicking a dungeon in the list opens its page (the Dungeons tab's, one
-- page for both), on the rate chart; Back returns to Trends.
local S = UI.StatsKit.S
local function Button(test)
    for _, w in ipairs(M.allFrames) do
        if w._scripts.OnClick and test(w) then return w end
    end
end
local function Labelled(text)
    return Button(function(w)
        for _, k in ipairs(M.allFrames) do
            if k._parent == w and k._kind == "FontString" and k._text == text and w._shown then return true end
        end
    end)
end
UI.RefreshStats(true)
local row = Button(function(w) return w.data and w.data.dungeon == "Gnomeregan" end)
check("tab: a dungeon's row can be clicked", row)
if row then row:Fire("OnClick") end
check("the click opens the dungeon's page", S.tab == "dungeons" and S.selected == "Gnomeregan" and S.from == "trends",
    S.tab .. " " .. tostring(S.selected))
check("page: on the rate chart (DPS elsewhere)", S.detailChart == (forever and "rate" or "dps"), S.detailChart)
check("page: the headline numbers", Shown(forever and "XP/hour" or "Your best DPS") and Shown("Deaths/run"))
check("page: the bosses", Shown("Boss"))
check("page: by level or difficulty, no heading", Shown(forever and "Level" or "Difficulty"))
if forever then check("page: where it came from", Shown("Where it came from")) end
-- Every other chart: DPS, HPS, damage taken, deaths.
for _, label in ipairs({ "DPS", "HPS", "Damage taken", "Deaths" }) do
    local btn = Button(function(w) return w.Look and w.text and w.text._text == label end)
    check("page: the " .. label .. " chart's button", btn)
    if btn then
        local ok, err = pcall(btn.Fire, btn, "OnClick")
        check("page: the " .. label .. " chart draws", ok, err)
    end
end
check("page: on the deaths chart", S.detailChart == "deaths", S.detailChart)
-- The series behind them: lower is better for deaths.
local ser = MS.TrendSeries(MS:StatsForDungeon("Gnomeregan").runs, function(e) return e.deaths or 0 end, true)
check("series: a point a run, the fewest deaths best", #ser.points == 2 and ser.best.v == 0, ser.best and ser.best.v)
local ser2 = MS.TrendSeries(MS:StatsForDungeon("Gnomeregan").runs, function(e) return e.me and e.me.dps end)
check("series: the highest DPS best", ser2.best.v == 110, ser2.best and ser2.best.v)
local timeBtn = Labelled("Run time")
check("page: the run time chart's button", timeBtn)
if timeBtn then timeBtn:Fire("OnClick") end
check("page: run times", S.detailChart == "time")
-- One run picked: from the run time chart's bar, then back to all of them.
S.detailChart = "time"
UI.RefreshStats(true)
local bar = Button(function(w) return w.entry == gB and w.fill end)
check("page: a bar for the run", bar)
if bar then bar:Fire("OnClick") end
check("page: the bar picks its run", S.detailRun == gB)
check("picked run: its own numbers", Shown("Result") and Shown("Killed") and Shown("Fight"))
if forever then check("picked run: its XP", Shown("30,000") or Shown("30000")) end
if bar then bar:Fire("OnClick") end
check("page: the same bar again, all runs", S.detailRun == nil)
check("all runs: Best and Typical again", Shown("Best") and Shown("Typical"))
-- A point on the rate chart picks its run too.
S.detailChart = "dps"
UI.RefreshStats(true)
local dot = Button(function(w) return w.pt and w.pt.e == gA and w._shown end)
check("page: a point for the run", dot)
if dot then dot:Fire("OnClick") end
check("page: the point picks its run", S.detailRun == gA)
local ok3, err3 = pcall(UI.RefreshStats, true)
check("picked run on the DPS chart draws", ok3, err3)
S.detailRun = nil

-- A dungeon with one run: its bar among your other dungeons, not an empty chart.
local list = MS:TrendByDungeon(function(e) return e.me and e.me.dps end)
check("by dungeon: best average first", list[1].avg >= list[#list].avg and #list >= 3, #list)
S.tab, S.selected, S.from, S.detailChart = "dungeons", "Ragefire Chasm", nil, "dps"
local ok4, err4 = pcall(UI.RefreshStats, true)
check("one run: the page draws", ok4, err4)
local function ShownHas(text)
    for _, w in ipairs(M.allFrames) do
        if w._kind == "FontString" and w._shown and type(w._text) == "string" and w._text:find(text, 1, true) then return w end
    end
end
check("one run: compared with your other dungeons", ShownHas("Compared with your other dungeons"))
S.detailChart = "deaths"
UI.RefreshStats(true)
check("one run: deaths compared too", ShownHas("Compared with your other dungeons"))
S.selected = nil

-- Back from a page opened on Trends goes to Trends.
S.tab, S.selected, S.from = "dungeons", "Gnomeregan", "trends"
UI.RefreshStats(true)
local backBtn
for _, w in ipairs(M.allFrames) do
    if w._scripts.OnClick and not w.Refresh then
        for _, k in ipairs(M.allFrames) do
            if k._parent == w and k._text == "Trends" and w._shown then backBtn = w end
        end
    end
end
check("page: a back button", backBtn)
if backBtn then backBtn:Fire("OnClick") end
check("back: the Trends tab again", S.tab == "trends" and S.selected == nil and S.from == nil, S.tab)
-- Opened from the Dungeons tab, back stays there.
S.tab, S.selected, S.from = "dungeons", "Gnomeregan", nil
UI.RefreshStats(true)
check("page from Dungeons: back says All dungeons", Shown("All dungeons"))
S.selected = nil
UI.StatsKit.S.tab = "trends"
UI.RefreshStats(true)

-- No runs at all: nothing breaks, the empty notes show.
runs = {}
rev = rev + 1
local ok, err = pcall(UI.RefreshStats, true)
check("no runs: no error", ok, err)
check("no runs: the chart says so", Shown("Your numbers show here after a couple of runs."))
UI.CloseStats()

io.stdout:write(("trends_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

local MS = _G["MythicScoreboard"]
local _floor, _max, _min = math.floor, math.max, math.min
local _sort = table.sort

-- ── The Trends tab's numbers (UI_StatsTrends.lua) ──────────────────────────
-- Worked out from the runs the Stats page shows (MS:StatsRuns: your
-- character, or all of them), and kept until those runs change or the day does.
--
--   activity  a cell a day for the last WEEKS weeks (runs, time), this week
--             and last (runs, time), the current and longest streak of days
--             with a run, and the weekday you play most
--   perf      your numbers run by run (the last PERF_RUNS): DPS, or HPS when
--             you mostly heal, with an average of the last few for the trend
--   farming   (WoW Forever) per dungeon: XP and gold an hour, from the runs
--             that recorded them; the ones near your level first
--   byDungeon (elsewhere) per dungeon: runs, your average and best DPS
--
-- MS:TrendDungeon(name): one dungeon from that list, broken down (the
-- dungeon's page, UI_StatsDungeon.lua).

local WEEKS = 26
local PERF_RUNS = 60
local AVERAGE_OF = 5                   -- runs in the trend line's average
local NEAR_LEVEL = 3                   -- levels either side that count as "your level"
MS.TRENDS_WEEKS = WEEKS

-- Midnight of a day, in your own time.
local function DayStart(t)
    local d = date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
end
-- A day's key (20261118), the same whatever the clock change.
local function DayKey(t) return tonumber(date("%Y%m%d", t)) end

-- The day before, by the calendar (a day isn't always 24 hours).
local function DayBefore(t) return DayStart(DayStart(t) - 12 * 3600) end
local function DayAfter(t) return DayStart(DayStart(t) + 36 * 3600) end

-- ── Activity ───────────────────────────────────────────────────────────────
local function Activity(runs, now)
    local byDay, weekday = {}, { 0, 0, 0, 0, 0, 0, 0 }
    for _, e in ipairs(runs) do
        if e.at then
            local k = DayKey(e.at)
            local d = byDay[k]
            if not d then d = { runs = 0, time = 0 }; byDay[k] = d end
            d.runs = d.runs + 1
            d.time = d.time + (e.dur or 0)
            local w = tonumber(date("%w", e.at)) + 1   -- 1 = Sunday
            weekday[w] = weekday[w] + 1
        end
    end
    -- The grid: weeks as columns, Sunday at the top; this week the last column.
    local today = DayStart(now)
    local todayW = tonumber(date("%w", today))
    local start = today
    for _ = 1, (WEEKS - 1) * 7 + todayW do start = DayBefore(start) end
    local cells, most = {}, 0
    local t = start
    for i = 1, WEEKS * 7 do
        local future = t > today
        local d = (not future) and byDay[DayKey(t)] or nil
        cells[i] = { at = t, runs = d and d.runs or 0, time = d and d.time or 0, future = future,
                     col = _floor((i - 1) / 7) + 1, row = (i - 1) % 7 + 1 }
        most = _max(most, cells[i].runs)
        t = DayAfter(t)
    end
    -- This week (from Sunday) and last.
    local weekStart = today
    for _ = 1, todayW do weekStart = DayBefore(weekStart) end
    local lastStart = weekStart
    for _ = 1, 7 do lastStart = DayBefore(lastStart) end
    local this, last = { runs = 0, time = 0 }, { runs = 0, time = 0 }
    for _, e in ipairs(runs) do
        if e.at and e.at >= weekStart then
            this.runs = this.runs + 1; this.time = this.time + (e.dur or 0)
        elseif e.at and e.at >= lastStart then
            last.runs = last.runs + 1; last.time = last.time + (e.dur or 0)
        end
    end
    -- Streaks: days in a row with a run. Today without one yet doesn't end it.
    local streak = 0
    local d = today
    if not byDay[DayKey(d)] then d = DayBefore(d) end
    while byDay[DayKey(d)] do streak = streak + 1; d = DayBefore(d) end
    local keys = {}
    for k in pairs(byDay) do keys[#keys + 1] = k end
    _sort(keys)
    local best, run, prev = 0, 0, nil
    for _, k in ipairs(keys) do
        local y, m, dd = _floor(k / 10000), _floor(k / 100) % 100, k % 100
        local at = time({ year = y, month = m, day = dd, hour = 12 })
        if prev and DayKey(DayBefore(at)) == prev then run = run + 1 else run = 1 end
        best = _max(best, run)
        prev = k
    end
    local topDay, topN = nil, 0
    for w = 1, 7 do if weekday[w] > topN then topDay, topN = w, weekday[w] end end
    return { cells = cells, most = most, thisWeek = this, lastWeek = last,
             streak = streak, bestStreak = best, topWeekday = topDay }
end

-- ── Performance ────────────────────────────────────────────────────────────
-- The trend through points {v}: each point's avg, the average of the last few
-- runs up to it. Gives how far it has moved, the first full average to the
-- latest (nil until there are enough runs to say).
local function Trendline(pts)
    for i, pt in ipairs(pts) do
        local sum, n = 0, 0
        for j = _max(1, i - AVERAGE_OF + 1), i do sum = sum + pts[j].v; n = n + 1 end
        pt.avg = sum / n
    end
    local base, last = pts[AVERAGE_OF], pts[#pts]
    if #pts >= 2 * AVERAGE_OF and base.avg > 0 then return last.avg / base.avg - 1 end
end

local function Performance(runs)
    local list = {}
    for _, e in ipairs(runs) do
        if e.me and ((e.me.dps or 0) > 0 or (e.me.hps or 0) > 0) then list[#list + 1] = e end
    end
    local from = _max(1, #list - PERF_RUNS + 1)
    local healer = 0
    for i = from, #list do if list[i].me.role == "HEALER" then healer = healer + 1 end end
    local heals = healer * 2 > (#list - from + 1)
    local pts = {}
    for i = from, #list do
        local e = list[i]
        local v = heals and (e.me.hps or 0) or (e.me.dps or 0)
        pts[#pts + 1] = { e = e, v = v, lvl = e.me.lvl, ilvl = e.me.ilvl }
    end
    return { points = pts, heals = heals, change = Trendline(pts) }
end

-- ── Farming (WoW Forever) ──────────────────────────────────────────────────
local function Farming(runs, level)
    local by = {}
    for _, e in ipairs(runs) do
        local pr = e.prog
        if pr and e.dungeon and (e.dur or 0) >= 60 then
            local d = by[e.dungeon]
            if not d then d = { dungeon = e.dungeon, runs = 0, time = 0, xp = 0, gold = 0 }; by[e.dungeon] = d end
            d.runs = d.runs + 1
            d.time = d.time + e.dur
            d.xp = d.xp + _max(0, pr.xp or 0) + _max(0, pr.qx or 0)
            d.gold = d.gold + _max(0, pr.g or 0) + _max(0, pr.qg or 0)
            local lv = e.me and e.me.lvl
            if lv then
                d.lo = d.lo and _min(d.lo, lv) or lv
                d.hi = d.hi and _max(d.hi, lv) or lv
            end
        end
    end
    local rows, anyXP = {}, false
    for _, d in pairs(by) do
        d.xpHour = d.xp / d.time * 3600
        d.goldHour = d.gold / d.time * 3600
        d.near = level ~= nil and d.lo ~= nil and level >= d.lo - NEAR_LEVEL and level <= d.hi + NEAR_LEVEL
        if d.xp > 0 then anyXP = true end
        rows[#rows + 1] = d
    end
    -- Near your level first; then by XP an hour (by gold once there's no XP to be had).
    local byGold = not anyXP
    _sort(rows, function(a, b)
        if a.near ~= b.near then return a.near end
        local ka, kb = byGold and a.goldHour or a.xpHour, byGold and b.goldHour or b.xpHour
        if ka ~= kb then return ka > kb end
        return a.dungeon < b.dungeon
    end)
    return { rows = rows, byGold = byGold, level = level }
end

-- ── Your DPS by dungeon (elsewhere) ────────────────────────────────────────
local function ByDungeon(runs)
    local by = {}
    for _, e in ipairs(runs) do
        local v = e.me and (e.me.dps or 0)
        if e.dungeon and v and v > 0 then
            local d = by[e.dungeon]
            if not d then d = { dungeon = e.dungeon, runs = 0, sum = 0, best = 0 }; by[e.dungeon] = d end
            d.runs = d.runs + 1; d.sum = d.sum + v; d.best = _max(d.best, v)
        end
    end
    local rows = {}
    for _, d in pairs(by) do d.avg = d.sum / d.runs; rows[#rows + 1] = d end
    _sort(rows, function(a, b) if a.avg ~= b.avg then return a.avg > b.avg end return a.dungeon < b.dungeon end)
    return rows
end

-- ── Any number, run by run ─────────────────────────────────────────────────
-- A chart's points from runs (oldest first): value(e) gives a run's number, or
-- nil to leave it out. The latest PERF_RUNS, each with its trend average; the
-- best point (lowest when lower is better), and how far the trend moved.
function MS.TrendSeries(runs, value, lowerIsBetter)
    local pts = {}
    for _, e in ipairs(runs) do
        local v = value(e)
        if v then pts[#pts + 1] = { e = e, v = v, lvl = e.me and e.me.lvl, ilvl = e.me and e.me.ilvl } end
    end
    while #pts > PERF_RUNS do table.remove(pts, 1) end
    local best
    for _, pt in ipairs(pts) do
        if not best or (lowerIsBetter and pt.v < best.v) or (not lowerIsBetter and pt.v > best.v) then best = pt end
    end
    return { points = pts, change = Trendline(pts), best = best }
end

-- What the Trends tab's chart can show: a number per run (nil leaves the run
-- out). lower: lower is better. fmt: how it's written ("gold" copper,
-- "minutes", "whole"; otherwise a plain number). forever: WoW Forever only.
local LK = MS.LK                       -- labels, translated where they are shown
local function Prog(e) return e.prog and (e.dur or 0) >= 60 and e.prog end
MS.TREND_METRICS = {
    { key = "dps", label = LK("DPS"), value = function(e) return e.me and (e.me.dps or 0) > 0 and e.me.dps or nil end },
    { key = "hps", label = LK("HPS"), value = function(e) return e.me and (e.me.hps or 0) > 0 and e.me.hps or nil end },
    { key = "xp", label = LK("XP an hour"), forever = true, value = function(e)
        local p = Prog(e)
        return p and (_max(0, p.xp or 0) + _max(0, p.qx or 0)) / e.dur * 3600 or nil
    end },
    { key = "gold", label = LK("Gold an hour"), forever = true, fmt = "gold", value = function(e)
        local p = Prog(e)
        return p and (_max(0, p.g or 0) + _max(0, p.qg or 0)) / e.dur * 3600 or nil
    end },
    { key = "time", label = LK("Run time"), lower = true, fmt = "minutes", value = function(e)
        return e.cleared and e.dur and e.dur / 60 or nil   -- cleared runs only: a quit isn't a time
    end },
    { key = "taken", label = LK("Damage taken"), lower = true, value = function(e) return e.me and e.me.taken or nil end },
    { key = "deaths", label = LK("Deaths"), lower = true, fmt = "whole", value = function(e) return e.deaths or 0 end },
}

-- The runs the chart is drawn from: one dungeon (nil: all) in the last days
-- (nil: all time).
function MS:TrendRuns(dungeon, days)
    local from = days and (time() - days * 86400)
    local out = {}
    for _, e in ipairs(self:StatsRuns()) do
        if (not dungeon or e.dungeon == dungeon) and (not from or (e.at or 0) >= from) then out[#out + 1] = e end
    end
    return out
end

-- Each dungeon's average of a number (value(e), nil leaves a run out), best
-- first (lowest first when lower is better): { {dungeon, avg, runs} }.
function MS:TrendByDungeon(value, lowerIsBetter)
    local by, list = {}, {}
    for _, e in ipairs(self:StatsRuns()) do
        local v = e.dungeon and value(e)
        if v then
            local d = by[e.dungeon]
            if not d then d = { dungeon = e.dungeon, sum = 0, runs = 0 }; by[e.dungeon] = d; list[#list + 1] = d end
            d.sum, d.runs = d.sum + v, d.runs + 1
        end
    end
    for _, d in ipairs(list) do d.avg = d.sum / d.runs end
    _sort(list, function(a, b)
        if a.avg ~= b.avg then if lowerIsBetter then return a.avg < b.avg end return a.avg > b.avg end
        return a.dungeon < b.dungeon
    end)
    return list
end

-- The dungeons with runs, the most run first: { {dungeon, runs} }.
function MS:TrendDungeons()
    local by, list = {}, {}
    for _, e in ipairs(self:StatsRuns()) do
        if e.dungeon then
            if not by[e.dungeon] then by[e.dungeon] = { dungeon = e.dungeon, runs = 0 }; list[#list + 1] = by[e.dungeon] end
            by[e.dungeon].runs = by[e.dungeon].runs + 1
        end
    end
    _sort(list, function(a, b) if a.runs ~= b.runs then return a.runs > b.runs end return a.dungeon < b.dungeon end)
    return list
end

-- One day of the calendar: its runs (in the order played) and what they added up to.
function MS:TrendDay(at)
    local k = DayKey(at)
    local d = { at = DayStart(at), runs = {}, time = 0, xp = 0, gold = 0, levels = 0, deaths = 0 }
    for _, e in ipairs(self:StatsRuns()) do
        if e.at and DayKey(e.at) == k then
            d.runs[#d.runs + 1] = e
            d.time = d.time + (e.dur or 0)
            d.deaths = d.deaths + (e.deaths or 0)
            local p = e.prog
            if p then
                d.xp = d.xp + _max(0, p.xp or 0) + _max(0, p.qx or 0)
                d.gold = d.gold + _max(0, p.g or 0) + _max(0, p.qg or 0)
                d.levels = d.levels + (p.lv or 0)
            end
        end
    end
    return d
end

-- ── One dungeon, broken down ───────────────────────────────────────────────
-- What the breakdown shows: totals and per-run/per-hour figures, a group per
-- level (Forever) or difficulty (elsewhere), a point per run for the chart
-- (XP an hour, or gold once there's no XP; elsewhere your DPS), and the
-- latest runs. Nil when no run of it has the numbers.
local Median = MS._Median
local RECENT_RUNS = 5

local function Per(n, d) return d > 0 and n / d or 0 end

local function Breakdown(runs, name, forever)
    local b = { dungeon = name, allRuns = 0, runs = 0, time = 0, deaths = 0, cleared = 0,
                mobXP = 0, questXP = 0, lootGold = 0, questGold = 0, kills = 0, quests = 0, levels = 0,
                dpsSum = 0, best = 0 }
    local list, clears, groups, reps = {}, {}, {}, {}
    for _, e in ipairs(runs) do
        if e.dungeon == name then
            b.allRuns = b.allRuns + 1
            local pr, me = e.prog, e.me
            local counts
            if forever then counts = pr and (e.dur or 0) >= 60
            else counts = me and (me.dps or 0) > 0 end
            if counts then
                list[#list + 1] = e
                b.runs = b.runs + 1
                b.time = b.time + (e.dur or 0)
                b.deaths = b.deaths + (e.deaths or 0)
                if e.cleared then b.cleared = b.cleared + 1; clears[#clears + 1] = e.dur end
                -- The group: your level then (Forever), or the key or difficulty.
                local gk, gsort
                if forever then
                    gk = me and me.lvl
                    gsort = gk or -1
                else
                    gk = e.key and ("+" .. e.key) or e.diff or "-"
                    gsort = e.key or -1
                end
                local g = groups[gk or "-"]
                if not g then
                    g = { key = gk, sort = gsort, runs = 0, time = 0, xp = 0, gold = 0, dpsSum = 0, best = 0, clears = {} }
                    groups[gk or "-"] = g
                end
                g.runs = g.runs + 1
                g.time = g.time + (e.dur or 0)
                if e.cleared then g.clears[#g.clears + 1] = e.dur end
                if forever then
                    local xp = _max(0, pr.xp or 0) + _max(0, pr.qx or 0)
                    local gold = _max(0, pr.g or 0) + _max(0, pr.qg or 0)
                    b.mobXP = b.mobXP + _max(0, pr.xp or 0)
                    b.questXP = b.questXP + _max(0, pr.qx or 0)
                    b.lootGold = b.lootGold + _max(0, pr.g or 0)
                    b.questGold = b.questGold + _max(0, pr.qg or 0)
                    b.kills = b.kills + (pr.k or 0)
                    b.quests = b.quests + (pr.q or 0)
                    b.levels = b.levels + (pr.lv or 0)
                    for f, n in pairs(pr.rep or {}) do reps[f] = (reps[f] or 0) + n end
                    g.xp, g.gold = g.xp + xp, g.gold + gold
                else
                    b.dpsSum = b.dpsSum + me.dps
                    b.best = _max(b.best, me.dps)
                    g.dpsSum = g.dpsSum + me.dps
                    g.best = _max(g.best, me.dps)
                end
            end
        end
    end
    if b.runs == 0 then return nil end

    b.xp, b.gold = b.mobXP + b.questXP, b.lootGold + b.questGold
    b.xpHour, b.goldHour = Per(b.xp, b.time) * 3600, Per(b.gold, b.time) * 3600
    b.xpRun, b.goldRun = b.xp / b.runs, b.gold / b.runs
    b.killsRun, b.deathsRun = b.kills / b.runs, b.deaths / b.runs
    b.avgDps = b.dpsSum / b.runs
    b.typical = Median(clears)
    for _, d in ipairs(clears) do b.fastest = b.fastest and _min(b.fastest, d) or d end
    b.byGold = forever and b.xp == 0
    b.rep = {}
    for f, n in pairs(reps) do b.rep[#b.rep + 1] = { faction = f, amount = n } end
    _sort(b.rep, function(x, y) if x.amount ~= y.amount then return x.amount > y.amount end return x.faction < y.faction end)

    b.groups = {}
    for _, g in pairs(groups) do
        g.xpHour, g.goldHour = Per(g.xp, g.time) * 3600, Per(g.gold, g.time) * 3600
        g.avgDps = g.dpsSum / g.runs
        g.typical = Median(g.clears)
        g.clears = nil
        b.groups[#b.groups + 1] = g
    end
    _sort(b.groups, function(x, y)
        if x.sort ~= y.sort then return x.sort > y.sort end
        return tostring(x.key) < tostring(y.key)
    end)

    -- The chart: a point a run, oldest first.
    local pts, bestPt = {}, nil
    for i = _max(1, #list - PERF_RUNS + 1), #list do
        local e = list[i]
        local v
        if forever then
            local pr = e.prog
            v = b.byGold and (_max(0, pr.g or 0) + _max(0, pr.qg or 0)) or (_max(0, pr.xp or 0) + _max(0, pr.qx or 0))
            v = Per(v, e.dur) * 3600
        else
            v = e.me.dps
        end
        local pt = { e = e, v = v, lvl = e.me and e.me.lvl, ilvl = e.me and e.me.ilvl }
        pts[#pts + 1] = pt
        if not bestPt or v > bestPt.v then bestPt = pt end
    end
    b.points, b.change, b.bestPoint = pts, Trendline(pts), bestPt

    b.recent = {}
    for i = #list, _max(1, #list - RECENT_RUNS + 1), -1 do b.recent[#b.recent + 1] = list[i] end
    return b
end

-- ── All of it ──────────────────────────────────────────────────────────────
local cache, cacheKey
local function Key(self, now, level)
    return #self:StatsRuns() .. "|" .. self:StatsRevision() .. "|" .. self:GetStatsChar() .. "|" .. DayKey(now) .. "|" .. tostring(level)
end

local function PlayerLevel()
    local level = UnitLevel and UnitLevel("player")
    if MS.IsSecret(level) then return nil end
    return level
end

-- The same for any runs of one dungeon: the dungeon page's numbers for a
-- single run it's showing.
function MS.TrendBreakdown(runs, name) return Breakdown(runs, name, MS.Flavor.progressStats) end

local dunCache, dunKey
function MS:TrendDungeon(name)
    if not name then return nil end
    local key = Key(self, time(), nil) .. "|" .. name
    if dunKey ~= key then
        dunCache, dunKey = Breakdown(self:StatsRuns(), name, MS.Flavor.progressStats), key
    end
    return dunCache
end

function MS:TrendStats()
    local runs = self:StatsRuns()
    local now = time()
    local level = PlayerLevel()
    local key = Key(self, now, level)
    if cache and cacheKey == key then return cache end
    cache = {
        activity = Activity(runs, now),
        perf = Performance(runs),
        farming = MS.Flavor.progressStats and Farming(runs, level) or nil,
        byDungeon = (not MS.Flavor.progressStats) and ByDungeon(runs) or nil,
    }
    cacheKey = key
    return cache
end

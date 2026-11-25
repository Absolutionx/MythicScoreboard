-- usage: lua5.1 long_run_tests.lua DIR TOC   (a three-hour run's timeline stays readable)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
M.instance = { "Orgrimmar", "none", 0 }
M.Fire("ADDON_LOADED", "MythicScoreboard")
local UI = MS.UI
local FRAME_W = UI.FRAME_W

local function T(m, s) return m * 60 + s end
local function kill(name, at, fight) return { name = name, pullTime = at - fight, killTime = at } end
local function wipe(name, at, fight) return { name = name, pullTime = at - fight, wipeTime = at } end

-- Blackrock Depths over almost three hours (the screenshot): 19 bosses, wipes,
-- bosses close together near the end.
local bosses = {
    kill("High Interrogator Gerstahn", T(12, 11), 26),
    kill("Lord Roccor", T(20, 40), 37),
    kill("Ring of Law", T(26, 1), 27),
    kill("Houndmaster Grebmar", T(27, 30), 25),
    kill("Lord Incendius", T(29, 32), 30),
    kill("Pyromancer Loregrain", T(50, 22), 31),
    kill("Warder Stilgiss", T(59, 22), 29),
    wipe("Fineous Darkvire", T(70, 10), 28),
    kill("Fineous Darkvire", T(76, 40), 34),
    kill("Bael'Gar", T(80, 2), 40),
    kill("General Angerforge", T(98, 9), 55),
    wipe("Golem Lord Argelmach", T(110, 30), 28),
    kill("Golem Lord Argelmach", T(115, 58), 14),
    kill("Hurley Blackbreath", T(121, 43), 50),
    kill("Phalanx", T(124, 10), 25),
    kill("Plugger Spazzring", T(128, 2), 30),
    kill("Ribbly Screwspigot", T(133, 40), 20),
    kill("Ambassador Flamelash", T(141, 55), 50),
    kill("The Seven", T(148, 31), 90),
    kill("Magmus", T(160, 12), 45),
    kill("Princess Moira Bronzebeard", T(165, 5), 30),
}
local DUR = T(170, 42)
local players = { { name = "Jay Breezy", class = "MAGE", deathEvents = {} } }
for i = 1, 29 do
    local p = players[1]
    p.deathEvents[#p.deathEvents + 1] = { time = (i * 347) % DUR, by = "Mob" }
end

MythicScoreboardDB.runs = { { dungeonName = "Blackrock Depths", _wallClockStart = 1, duration = DUR,
    completed = true, clearedAt = DUR, players = players, bosses = bosses } }
MS.displayRun = nil; UI._medPlanLRU = nil
MS:ShowScoreboard(); MS:RefreshOverview(); M.RunTimers(5)

local container = MythicScoreboardFrame.timelineContainer
local function inTimeline(w)
    while w do if w == container then return true end; w = w._parent end
end

-- ── Medallions: inside the window ──────────────────────────────────────────
local outside, n = 0, 0
for _, e in ipairs(UI._medLayout or {}) do
    n = n + 1
    if e.cx - 17 < 0 or e.cx + 17 > FRAME_W then
        outside = outside + 1; io.write("  outside: ", e.name, " at ", math.floor(e.cx), "\n")
    end
end
check("medallions laid out", n >= 15, n)
check("no medallion past the window's edges", outside == 0, outside)

-- Crowded long runs (bosses bunched at the start and end, as in BRD), made
-- up the same way each time: no medallion leaves the window either.
local seed = 7
local function rnd(k) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % k end
local escaped = 0
for runN = 1, 24 do
    local list, t = {}, 0
    local count = 18 + rnd(10)
    for i = 1, count do
        local bunched = i <= 4 or i > count - 7
        t = t + (bunched and (20 + rnd(90)) or (200 + rnd(900)))
        list[#list + 1] = (rnd(6) == 0) and wipe("Boss " .. i, t, 20 + rnd(40)) or kill("Boss " .. i, t, 15 + rnd(60))
    end
    local dur = t + 30 + rnd(300)
    MythicScoreboardDB.runs = { { dungeonName = "Blackrock Depths", _wallClockStart = runN + 1, duration = dur,
        completed = true, clearedAt = dur, players = {}, bosses = list } }
    MS.displayRun = nil; UI._medPlanLRU = nil
    MS:RefreshOverview(); M.RunTimers(5)
    for _, e in ipairs(UI._medLayout or {}) do
        if e.cx - 17 < 0 or e.cx + 17 > FRAME_W then
            escaped = escaped + 1; io.write("  run ", runN, " outside: ", e.name, " at ", math.floor(e.cx), "\n")
        end
    end
end
check("crowded long runs: no medallion past the edges", escaped == 0, escaped)
MythicScoreboardDB.runs = { { dungeonName = "Blackrock Depths", _wallClockStart = 1, duration = DUR,
    completed = true, clearedAt = DUR, players = players, bosses = bosses } }
MS.displayRun = nil; UI._medPlanLRU = nil
MS:RefreshOverview(); M.RunTimers(5)

-- ── The minute labels: apart ───────────────────────────────────────────────
local function labelsAt(y, pat)
    local xs = {}
    for _, w in ipairs(M.allFrames) do
        if w._kind == "FontString" and w._shown and w._text and w._text:find(pat) and w._at
                and w._at[5] == y and inTimeline(w) then
            xs[#xs + 1] = { x = w._at[4], t = w._text }
        end
    end
    table.sort(xs, function(a, b) return a.x < b.x end)
    return xs
end
local ticks = labelsAt(8, "^%d+:%d%d$")
local tight = 0
for i = 2, #ticks do
    if ticks[i].point ~= "BOTTOMLEFT" and ticks[i].x - ticks[i - 1].x < 50 then
        tight = tight + 1; io.write("  close: ", ticks[i - 1].t, " / ", ticks[i].t, "\n")
    end
end
check("minute labels shown", #ticks >= 8, #ticks)
check("minute labels don't run into each other", tight == 0, tight)
check("a step for three hours: 10 minutes or more", UI._TickStep(DUR, FRAME_W - 46) >= 600, UI._TickStep(DUR, FRAME_W - 46))
check("short runs keep their steps", UI._TickStep(150, 1100) == 30 and UI._TickStep(400, 1100) == 60
    and UI._TickStep(800, 1100) == 120 and UI._TickStep(40 * 60, 1100) == 300)

io.stdout:write("long_run_tests: ", passes, " passed, ", fails, " failed\n")
os.exit(fails == 0 and 0 or 1)

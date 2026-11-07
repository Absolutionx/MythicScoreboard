-- usage: lua5.1 layout_tests.lua DIR TOC   (medallion placement on its own, no drawing)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local R = UI.TL.MED_R
local n = 0
local function place(spots)        -- spots: { {mx, lblW}, ... }, first = last kill
    n = n + 1
    local info, order = {}, {}
    for i, s in ipairs(spots) do
        info[i] = { mx = s[1], lblW = s[2] or 120, compW = math.min(s[2] or 120, UI.TL.COMPACT_W) }
        order[i] = i
    end
    UI._medPlanLRU = nil
    return UI.PlaceMedallions(info, order, "run" .. n), info
end
local function rulesHold(plan, count)
    for i = 1, count do
        for j = i + 1, count do
            local a, b = plan[i], plan[j]
            if a.row == b.row and math.min(a.x2, b.x2 + 10) - math.max(a.x1, b.x1 - 10) > 0 then
                return false, ("%d and %d touch on row %d"):format(i, j, a.row)
            end
            -- a top-row stem never hides behind a bottom-row medallion
            local top, bot = (a.row == 1 and a or b), (a.row == 1 and b or a)
            if a.row ~= b.row and math.abs(top.cx - bot.cx) < R + 4 then
                return false, ("%d's stem hides behind %d"):format(i, j)
            end
        end
    end
    return true
end

-- 1. One boss: its own spot, full label, straight stem.
local p = place({ { 300 } })
check("single: full label at its fight", not p[1].mode.bare and not p[1].mode.compact and p[1].cx == 300 and p[1].shift == 0)

-- 2. Two bosses far apart: both full, neither moved.
p = place({ { 800 }, { 200 } })
check("apart: both full and in place", p[1].cx == 800 and p[2].cx == 200 and not p[1].mode.compact and not p[2].mode.compact)

-- 3. Two bosses close together: the rules hold, both keep a name.
p = place({ { 230 }, { 200 } })
local ok, why = rulesHold(p, 2)
check("close: rules hold", ok, why)
check("close: both named", not p[1].mode.bare and not p[2].mode.bare)

-- 4. A tight run (six fights 70px apart): the rules hold, and the last
-- kill keeps its full label.
local spots = {}
for i = 6, 1, -1 do spots[#spots + 1] = { 150 + i * 70, 110 } end
p = place(spots)
local ok, why = rulesHold(p, 6)
check("tight: rules hold", ok, why)
check("tight: last kill keeps its full label", not p[1].mode.bare and not p[1].mode.compact)

-- 4b. Far too crowded for any clean layout (eight fights in 400px): every
-- boss still gets a spot. (This used to crash, hiding the whole timeline.)
spots = {}
for i = 8, 1, -1 do spots[#spots + 1] = { 150 + i * 50, 110 } end
local okCall, plan = pcall(place, spots)
local all = okCall and plan ~= nil
for i = 1, 8 do all = all and plan[i] ~= nil end
check("very crowded: no crash, every boss placed", all, plan)

-- 5. Long labels near the right edge stay on screen.
p = place({ { UI.FRAME_W - 40, 160 } })
check("right edge: on screen", p[1].x2 <= UI.FRAME_W - 6 and p[1].x1 >= 4, p[1].x1 .. ".." .. p[1].x2)

-- 6. The same layout twice comes from the cache.
local info = { { mx = 300, lblW = 100, compW = 88 } }
UI._medPlanLRU = nil
local a1 = UI.PlaceMedallions(info, { 1 }, "same")
local a2 = UI.PlaceMedallions(info, { 1 }, "same")
check("cached", a1 == a2)

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

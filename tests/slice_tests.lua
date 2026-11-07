-- usage: lua5.1 slice_tests.lua DIR TOC
-- A crowded timeline's thorough medallion search runs a few milliseconds a
-- frame: the quick layout first, the better one when it's done.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
local ms = 0
debugprofilestop = function() ms = ms + 0.05; return ms end     -- time moves as work is done
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function Cost(plan, order) local c = 0; for _, bi in ipairs(order) do c = c + plan[bi].cost end; return c end

-- Twelve bosses packed together: the quick search can't name them all.
local info, order = {}, {}
local x = 120
for i = 1, 12 do
    x = x + ((i % 3 == 0) and 140 or 45)
    info[i] = { mx = x, lblW = 150, compW = 80 }
    order[#order + 1] = i
end
local rebuilt = 0
UI.RebuildTimeline = function() rebuilt = rebuilt + 1 end
M.timers = {}
local first = UI.PlaceMedallions(info, order, "crowded")
local entry = UI._medPlanLRU[1]
check("quick layout straight away", first ~= nil and entry.pending == true, entry.pending)
local frames = 0
while entry.pending and frames < 500 do frames = frames + 1; M.RunTimers(1) end
check("thorough search finishes over a few frames", not entry.pending and frames > 1, frames)
check("redrawn once when it's better", (entry.plan ~= first and rebuilt == 1) or (entry.plan == first and rebuilt == 0), rebuilt)
check("never worse than the quick layout", Cost(entry.plan, order) <= Cost(first, order))
check("asked again: the finished plan", UI.PlaceMedallions(info, order, "crowded") == entry.plan)

-- The same answer as working it all out at once.
ms = 0
debugprofilestop = nil
UI._medPlanLRU = nil
local f2 = loadfile(arg[1] .. "/Core/UI_TimelineLayout.lua")   -- (a copy with no clock: one go)
local saved = UI.PlaceMedallions
f2()
local whole = UI.PlaceMedallions(info, order, "crowded2")
UI.PlaceMedallions = saved
check("same as one go", math.abs(Cost(whole, order) - Cost(entry.plan, order)) < 0.001,
    Cost(whole, order) .. " vs " .. Cost(entry.plan, order))

io.stdout:write(("slice_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

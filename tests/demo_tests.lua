-- usage: lua5.1 demo_tests.lua DIR TOC
-- /sb demo: a sample run to look at. Retail: a Mythic+ key. WoW Forever: one
-- of its own dungeons near your level, with its bosses, a group of its
-- classes and what the run gave you; never a retail dungeon.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.Fire("PLAYER_LOGIN")
local forever = MS.Flavor.progressStats
UnitLevel = function() return 44 end
local ok, err = pcall(SlashCmdList["MYTHICSCOREBOARD"], "demo")
check("/sb demo runs", ok, err)
local r = MS.displayRun
check("a sample run", r and r._demo)
local n = 0
for _ in pairs(r and r.players or {}) do n = n + 1 end
check("five players", n == 5, n)
if forever then
    local key = r.wingName or r.dungeonName
    local d = MS.ForeverData.DUNGEONS[key]
    check("a WoW Forever dungeon", d ~= nil, key)
    check("near your level", d and 44 >= d.levels[1] - 3 and 44 <= d.levels[2] + 3, key)
    check("not a key", (r.keystoneLevel or 0) == 0 and not r.ratingAfter, r.keystoneLevel)
    check("its own bosses", #r.bosses > 0 and r.bosses[1].name ~= "Avanoxx", r.bosses[1] and r.bosses[1].name)
    check("what it gave you", r.progress and r.progress.xp > 0 and r.progress.kills > 0)
    for _, p in pairs(r.players) do
        check("no retail classes (" .. p.name .. ")", p.class ~= "DEMONHUNTER" and p.class ~= "EVOKER" and p.class ~= "MONK", p.class)
        check("a level (" .. p.name .. ")", (p.level or 0) > 0)
    end
    -- Many times over: always a Forever dungeon with bosses.
    local bad
    for _ = 1, 50 do
        local s = MS.UI.ForeverDemoRun()
        if not MS.ForeverData.DUNGEONS[s.wingName or s.dungeonName] or #s.bosses == 0 then bad = s.dungeonName end
    end
    check("always a WoW Forever dungeon", bad == nil, bad)
    local okDraw, errDraw = pcall(MS.RefreshOverview, MS); M.RunTimers(2)
    check("the scoreboard draws it", okDraw, errDraw)
else
    check("retail: a key", r.keystoneLevel == 15 and r.dungeonName == "Ara-Kara, City of Echoes")
end
io.stdout:write(("demo_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

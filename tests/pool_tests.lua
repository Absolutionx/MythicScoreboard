-- usage: lua5.1 pool_tests.lua DIR TOC
-- Timeline pieces are reused between redraws. A label one run hid (compact
-- or bare) must show again when another run reuses it.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
time = function() return 1800000000 end
M.instance = { "Orgrimmar", "none", 0 }
dofile("fixtures/wc.lua")
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4)

-- A crowded run, so some labels go compact or bare.
local function Crowded()
    local run = MS.NewRunData()
    run.dungeonName, run.duration, run.completed, run._wallClockStart = "Shadowfang Keep", 3020, true, 1799990000
    local kills = { { "Rethilgore", 445, 484 }, { "Razorclaw the Butcher", 996, 1014 }, { "Baron Silverlaine", 1212, 1232 },
                    { "Commander Springvale", 1499, 1549 }, { "Odo the Blindwatcher", 1732, 1782 },
                    { "Fenrus the Devourer", 2468, 2495 }, { "Wolf Master Nandos", 2789, 2826 },
                    { "Archmage Arugal", 2942, 3020 } }
    for _, k in ipairs(kills) do run.bosses[#run.bosses + 1] = { name = k[1], pullTime = k[2], killTime = k[3] } end
    run.players.Jay = MS.NewPlayerStats("Jay", "SHAMAN", "Player-1-AAA")
    return run
end
table.insert(MythicScoreboardDB.runs, 1, Crowded())
-- Eight bosses inside two minutes of a long run: labels have to give way.
local packed = Crowded()
packed.dungeonName, packed._wallClockStart = "Blackrock Depths", 1799980000
for i, b in ipairs(packed.bosses) do b.pullTime = 1500 + i * 14; b.killTime = b.pullTime + 8 end
table.insert(MythicScoreboardDB.runs, 1, packed)

local function Visible(f)
    while f do
        if not f._shown then return false end
        f = f._parent
    end
    return true
end
local function Labels()
    local shown = {}
    for _, f in ipairs(M.allFrames) do
        if f.GetText and f._shown ~= nil and Visible(f) then
            local t = f:GetText()
            if t and t ~= "" then shown[t] = true end
        end
    end
    return shown
end

MS:ShowScoreboard(); M.RunTimers(4)
local runs = MythicScoreboardDB.runs
local orders = { { 1, 2, 3, 4, 5 }, { 5, 4, 3, 2, 1 }, { 1, 2, 1, 3, 1, 4, 1, 5 } }
local steps, hidden = 0, 0
for _, ord in ipairs(orders) do
    for _, i in ipairs(ord) do
        if runs[i] then
            MS.displayRun = runs[i]; MS:_DoRefreshOverview(); M.RunTimers(1)
            local shown = Labels()
            for _, e in ipairs(MS.UI._medLayout or {}) do
                if e.bare or e.compact then hidden = hidden + 1 end
                if not e.bare then
                    steps = steps + 1
                    check("name shown: " .. e.name .. " (" .. MS:RunTitle(runs[i]) .. ")", shown[e.name])
                    if not e.compact then
                        check("time shown: " .. e.name .. " (" .. MS:RunTitle(runs[i]) .. ")", shown[e.sub])
                    end
                end
            end
        end
    end
end
check("labels were checked", steps > 20, steps)
check("some labels went compact or bare (else this proves nothing)", hidden > 0, hidden)
io.stdout:write(("pool_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

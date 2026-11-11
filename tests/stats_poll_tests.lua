-- usage: lua5.1 stats_poll_tests.lua DIR TOC
-- During a live run the meter poll refreshes the window every 2s. With the
-- Stats page open that must not touch its rows (it re-anchors the row under
-- the mouse, which closes its tooltip).
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD"); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
M.Fire("ADDON_LOADED", "MythicScoreboard")
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
zone({ "Ragefire Chasm", "party", 1 }); MS.currentRun.completed = true; M.now = M.now + 600; zone({ "Orgrimmar", "none", 0 })
zone({ "The Deadmines", "party", 1 })                      -- live run in progress

MS:ShowScoreboard(); M.RunTimers(2)
UI.OpenStats(); M.RunTimers(2)
-- Count re-anchoring and text changes on the drawn stats rows from here on.
local touched = 0
for _, w in ipairs(M.allFrames) do
    if w.dungeon then
        local sp, ca = w.SetPoint, w.ClearAllPoints
        w.SetPoint = function(...) touched = touched + 1; return sp(...) end
        w.ClearAllPoints = function(...) touched = touched + 1; return ca(...) end
        for _, fs in pairs(w.cells) do
            local st = fs.SetText
            fs.SetText = function(...) touched = touched + 1; return st(...) end
        end
    end
end
for _ = 1, 5 do M.Tick(); M.RunTimers(2) end              -- ten seconds of meter polls
check("live polls leave stats rows alone", touched == 0, touched .. " changes")

-- A run finishing while it's open does update it.
local before = #MS:StatsOverview().dungeons
MS.currentRun.completed = true; M.now = M.now + 600; zone({ "Orgrimmar", "none", 0 }); M.RunTimers(2)
local drawn = 0
for _, w in ipairs(M.allFrames) do if w.dungeon and w._shown then drawn = drawn + 1 end end
check("finished run appears", drawn == before + 1, drawn)
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

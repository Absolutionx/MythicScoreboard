-- usage: lua5.1 history_tests.lua DIR TOC
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local WORLD = { "Orgrimmar", "none", 0 }
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD"); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
M.Fire("ADDON_LOADED", "MythicScoreboard")
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end

-- Two saved runs, then a live one.
for _, d in ipairs({ "Ragefire Chasm", "The Deadmines" }) do
    zone({ d, "party", 1 }); MS.currentRun.completed = true; M.now = M.now + 600; zone(WORLD)
end
zone({ "Ruins of Lordaeron", "party", 1 })
if not MythicScoreboardFrame then MS:BuildUI() end   -- built on first open
local f = MythicScoreboardFrame
MS:ShowScoreboard(); M.RunTimers(2)
check("live run shown", f.DungeonName:GetText() == "Ruins of Lordaeron", f.DungeonName:GetText())

-- History rows: the live one first ("Now"), then saved runs.
local function dropRows()
    local rows = {}
    for _, w in ipairs(M.allFrames) do
        if w._shown and w._kind == "Button" and w._parent and w._parent._parent == UIParent
                and w._parent ~= f and w._scripts.OnClick and w._children then
            for _, c in ipairs(w._children) do
                if c._kind == "FontString" and c._text ~= "" and c._text ~= "Clear all history" then
                    rows[#rows + 1] = w; break
                end
            end
        end
    end
    return rows
end
local function rowText(row)
    local t = {}
    for _, c in ipairs(row._children) do if c._kind == "FontString" then t[#t + 1] = c._text end end
    return table.concat(t, "|")
end
f.HistoryButton:Fire("OnClick")
local rows = dropRows()
check("dropdown rows", #rows == 3, #rows)
check("live run on top as Now", rows[1] and rowText(rows[1]):find("Now") and rowText(rows[1]):find("Ruins"), rows[1] and rowText(rows[1]))

-- Pick the second saved run (Ragefire Chasm) while the live run continues.
local rfcRow
for _, r in ipairs(rows) do if rowText(r):find("Ragefire") then rfcRow = r end end
rfcRow:Fire("OnClick"); M.RunTimers(2)
check("saved run shown during live run", f.DungeonName:GetText() == "Ragefire Chasm", f.DungeonName:GetText())
M.Tick(); M.RunTimers(2)              -- a live meter poll must not switch it back
check("stays on saved run after a poll", f.DungeonName:GetText() == "Ragefire Chasm", f.DungeonName:GetText())
check("run is still live underneath", MS.inDungeon and MS.currentRun.dungeonName == "Ruins of Lordaeron")

-- Back to the live run via "Now".
f.HistoryButton:Fire("OnClick")
rows = dropRows()
rows[1]:Fire("OnClick"); M.RunTimers(2)
check("Now returns to live run", f.DungeonName:GetText() == "Ruins of Lordaeron" and MS.displayRun == nil, f.DungeonName:GetText())

-- Live row can't be deleted; saved rows can.
f.HistoryButton:Fire("OnClick")
rows = dropRows()
local liveDel, savedDel
for _, c in ipairs(rows[1]._children) do if c._kind == "Button" then liveDel = c end end
for _, c in ipairs(rows[2]._children) do if c._kind == "Button" then savedDel = c end end
check("no delete on live row", liveDel and not liveDel._shown)
check("delete on saved row", savedDel and savedDel._shown)

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

-- usage: lua5.1 avoidable_column_tests.lua DIR TOC
-- The scoreboard's Avoidable column. WoW Forever: left out (its width goes
-- to Loot) until the first avoidable damage is seen, then back at once,
-- header and rows laid out again, with no /reload, and from then on.
-- Elsewhere: always there.
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
M.Fire("PLAYER_LOGIN")
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
local forever = MS.Flavor.progressStats

local function Col(key)
    for _, c in ipairs(UI.COLS) do if c.key == key then return c end end
end
local function HeaderShown(label)
    for _, w in ipairs(M.allFrames) do
        if w._kind == "FontString" and w._text == label and w._parent and w._parent._parent == MythicScoreboardFrame.ColHeader then
            return w._parent._shown
        end
    end
end

zone({ "The Deadmines", "party", 1 })
if not MythicScoreboardFrame then MS:BuildUI() end
local function src(n, g, a) return { name = n, sourceGUID = g, totalAmount = a, classFilename = "MAGE", amountPerSecond = 0 } end
M.meter = { [0] = { duration = 50, combatSources = { src("Akasha", "Player-1-BBB", 500), src("Girthy", "Player-1-CCC", 400) } } }
MS:ShowScoreboard(); M.RunTimers(2); M.Tick(); M.RunTimers(2)
local row = UI.overviewRows[1]

if not forever then
    check("retail: the column's there", Col("avoidable") ~= nil)
    check("retail: its header shows", HeaderShown("Avoidable") == true)
    check("retail: three loot icons", row._lootSlots == 3, row._lootSlots)
else
    -- Nothing avoidable yet: no column, a wider Loot with five icons.
    local width = 0
    for _, c in ipairs(UI.COLS) do width = width + c.w end
    check("forever: no Avoidable column", Col("avoidable") == nil)
    check("forever: its header hidden", HeaderShown("Avoidable") == false, tostring(HeaderShown("Avoidable")))
    check("forever: Loot takes its width", Col("loot").w == 192, Col("loot").w)
    check("forever: five loot icons", row._lootSlots == 5, row._lootSlots)
    check("forever: its cells hidden", not row._statFs.avoidable.main._shown)

    -- The first avoidable damage: the column comes back, now.
    M.meter[8] = { combatSources = { src("Akasha", "Player-1-BBB", 300) } }
    M.Tick(); M.RunTimers(2)
    check("seen: the column's back", Col("avoidable") ~= nil)
    check("seen: kept for later sessions", MS:GetSetting("avoidableSeen") == true)
    check("seen: its header shows", HeaderShown("Avoidable") == true)
    check("seen: Loot back to its own width", Col("loot").w == 108, Col("loot").w)
    local width2 = 0
    for _, c in ipairs(UI.COLS) do width2 = width2 + c.w end
    check("seen: the same overall width", width2 == width, width2 .. " vs " .. width)
    local akasha
    for _, r in ipairs(UI.overviewRows) do
        if r._nameFs and r._nameFs:GetText() == MS.DisplayName(MS:PlayerByName("Akasha").name) then akasha = r end
    end
    check("seen: Akasha's row", akasha ~= nil)
    if akasha then
        check("seen: rows laid out again (three loot icons)", akasha._lootSlots == 3, akasha._lootSlots)
        check("seen: the cell shows", akasha._statFs.avoidable.main._shown)
        check("seen: her avoidable damage", akasha._statFs.avoidable.main._text == "300", akasha._statFs.avoidable.main._text)
    end
    -- The numbers after it moved right along with it.
    check("seen: Damage after Avoidable", Col("damage").x > Col("avoidable").x)

    -- The next session: back from the start.
    UI.SetAvoidableColumn(false)
    check("(a fresh load: hidden)", Col("avoidable") == nil)
    M.Fire("PLAYER_LOGIN")
    check("next session: there from the start", Col("avoidable") ~= nil)
end

io.stdout:write(("avoidable_column_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

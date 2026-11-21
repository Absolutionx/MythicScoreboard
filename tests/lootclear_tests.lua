-- usage: lua5.1 lootclear_tests.lua DIR TOC   (removing items from the Stats loot list)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function errorsPrinted()
    for _, p in ipairs(M.printed) do if p:find("rror") then return p end end
end
local WORLD, RFC = { "Orgrimmar", "none", 0 }, { "Ragefire Chasm", "party", 1 }
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local clock = 1800000000
time = function() return clock end
local function wait(s) M.now = M.now + s; clock = clock + s end
local function login()
    M.timers = {}; MS.currentRun, MS.inDungeon, MS.displayRun = nil, false, nil
    M.instance = WORLD
    M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(2)
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
end
local LINK = "|cnIQ4:|Hitem:12345::::::::20:::::|h[Fiery Greatsword]|h|r"
local function playRun(cleared, withLoot)
    clock = clock + 86400
    zone(RFC)
    wait(60)
    M.Fire("ENCOUNTER_START", 1, "Oggleflint"); wait(30); M.Fire("ENCOUNTER_END", 1, "Oggleflint", 1, 5, 1); M.RunTimers(4)
    if withLoot then
        wait(20)
        local me = MS:PlayerForUnit("player")
        me.loot = { { item = "item:12345::::::::20:::::", link = LINK, quality = 4, t = MS:GetRunDuration() } }
    end
    MS.currentRun.completed = cleared
    wait(200); zone(WORLD)
    if MS.currentRun and MS.currentRun._suspended then MS:ClosePausedRun() end
end


local function findButton(text)
    for _, w in ipairs(M.allFrames) do
        if w._kind == "Button" and w._children then
            for _, c in ipairs(w._children) do if c._kind == "FontString" and c._text == text then return w end end
        end
    end
end
local function lootRows()
    local out = {}
    for _, w in ipairs(M.allFrames) do if w.del and w.data and w.data.item and w._shown then out[#out + 1] = w end end
    return out
end

MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
login()
playRun(true, true); playRun(true, true); playRun(true, true)
check("three items", #MS:LootHistory() == 3, #MS:LootHistory())

-- ── 1. One item, two clicks ────────────────────────────────────────────────
MS:ShowScoreboard(); M.RunTimers(2)
UI.OpenStats(); M.RunTimers(2)
local lootTab = findButton("Loot  " .. "3") or findButton("Loot")
for _, w in ipairs(M.allFrames) do
    if w._kind == "Button" and w._children then
        for _, c in ipairs(w._children) do if c._kind == "FontString" and (c._text or ""):find("^Loot") then lootTab = w end end
    end
end
check("loot tab", lootTab ~= nil)
lootTab:Fire("OnClick"); M.RunTimers(2)
local rows = lootRows()
check("rows with remove buttons", #rows == 3, #rows)
local row = rows[1]
check("remove shown for own items", row.del._shown)
row.del:Fire("OnEnter"); row.del:Fire("OnLeave")
row.del:Fire("OnClick")
check("first click only arms", #MS:LootHistory() == 3)
check("armed: row marked red with its message", row.armBg._shown and row.armTxt._shown and row.armTxt._text == "Click again to remove")
M.now = M.now + 4; M.RunTimers(4)
check("disarms after 3s", not row.armBg._shown and not row.armTxt._shown and not row.del.IsArmed())
row.del:Fire("OnClick")
row.del:Fire("OnClick"); M.RunTimers(2)
check("second click removes", #MS:LootHistory() == 2, #MS:LootHistory())
check("runs kept", #MS:ArchiveRuns() == 3 and #MythicScoreboardDB.runs == 3)
check("history's own loot column kept", MythicScoreboardDB.runs[1].players and next(MythicScoreboardDB.runs[1].players) ~= nil)
check("list redrawn", #lootRows() == 2, #lootRows())

-- ── 2. Clear all, after a yes ──────────────────────────────────────────────
local shown
StaticPopupDialogs = {}
StaticPopup_Show = function(name, text) shown = { name = name, text = text } end
local clear = findButton("Clear loot")
check("clear button", clear ~= nil and clear._shown)
clear:Fire("OnEnter"); clear:Fire("OnLeave")
clear:Fire("OnClick")
check("asks first", shown and shown.text:find("2 items") and shown.text:find("kept"), shown and shown.text)
check("nothing cleared yet", #MS:LootHistory() == 2)
StaticPopupDialogs[shown.name].OnAccept(); M.RunTimers(2)
check("cleared", #MS:LootHistory() == 0, #MS:LootHistory())
check("runs still kept", #MS:ArchiveRuns() == 3)
check("clear button hidden when empty", not clear._shown)
check("empty text", #lootRows() == 0)

-- ── 3. One item left: its own wording ──────────────────────────────────────
playRun(true, true); M.RunTimers(2)
UI.RefreshStats(true)
shown = nil; clear:Fire("OnClick")
check("one item wording", shown and shown.text:find("one item"), shown and shown.text)

-- ── 4. Another character's items can't be removed here ─────────────────────
local e; for _, x in ipairs(MS:ArchiveRuns()) do if x.loot then e = x end end
local realOwn = MS.IsOwnRun
MS.IsOwnRun = function() return false end
check("not removed when not yours", not MS:RemoveArchivedLoot(e, e.loot[1]) and #e.loot == 1)
UI.RefreshStats(true)
local hidden = true
for _, w in ipairs(lootRows()) do if w.del._shown then hidden = false end end
check("no x on others' items", hidden)
MS.IsOwnRun = realOwn

local function errorsPrinted()
    for _, p in ipairs(M.printed) do if p:find("rror") then return p end end
end
check("no errors at all", not errorsPrinted(), errorsPrinted())
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

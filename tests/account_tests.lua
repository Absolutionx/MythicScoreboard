-- usage: lua5.1 account_tests.lua DIR TOC   (all characters, loot history, minimap button)
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

-- ── 1. This character's runs are kept account-wide ─────────────────────────
MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
login()
playRun(true, true)
playRun(false)
local me = MS:CharKey()
check("character key", me and me:find("@"), me)
local acc = MythicScoreboardAccountDB
check("account store made", acc and acc.chars and acc.chars[me])
check("archive kept account-wide, once", acc.chars[me].archive.runs == MS:ArchiveRuns() and MythicScoreboardDB.archive == nil and acc.chars[me].runs == nil)
check("class saved", acc.chars[me].class ~= nil)

-- ── 2. Loot is archived with its boss ──────────────────────────────────────
local e = MS:ArchiveRuns()[1]
check("loot archived", e.loot and #e.loot == 1, e.loot and #e.loot)
check("loot boss", e.loot and e.loot[1].b == "Oggleflint", e.loot and e.loot[1].b)
check("loot link kept", e.loot and e.loot[1].l == LINK)
check("loot history", #MS:LootHistory() == 1)

-- ── 3. Another character's runs ────────────────────────────────────────────
local other = "Akasha@Elsewhere"
acc.chars[other] = { name = "Akasha", class = "MAGE", runs = {
    { at = clock - 500000, dungeon = "Ragefire Chasm", dur = 700, cleared = true, deaths = 0, bosses = {}, group = {},
      me = { dps = 300 }, loot = { { i = "item:999", q = 3, t = 300, b = "Bazzalan" } } },
    { at = clock - 400000, dungeon = "The Deadmines", dur = 1500, cleared = true, deaths = 2, bosses = {}, group = {} },
} }
MS:SetStatsChar("all")
check("all characters: runs", #MS:StatsRuns() == 4, #MS:StatsRuns())
check("all characters: oldest first", MS:StatsRuns()[1].at < MS:StatsRuns()[4].at)
check("all characters: loot", #MS:LootHistory() == 2)
check("owner known", MS:RunOwner(acc.chars[other].runs[1]) == other)
check("other's run isn't ours", not MS:IsOwnRun(acc.chars[other].runs[1]) and MS:IsOwnRun(MS:ArchiveRuns()[1]))
check("all characters: dungeon has both", #MS:StatsForDungeon("Ragefire Chasm").runs == 3, #MS:StatsForDungeon("Ragefire Chasm").runs)
MS:SetStatsChar(other)
check("one character", #MS:StatsRuns() == 2 and MS:StatsOverview().runs == 2)
MS:SetStatsChar(me)
check("this character", #MS:StatsRuns() == 2 and MS:StatsRuns()[1].dungeon == "Ragefire Chasm")
MS:SetStatsChar("Gone@Nowhere")
check("unknown character falls back to all", MS:GetStatsChar() == "all")
local chars = MS:StatsCharacters()
check("characters listed, you first", #chars == 2 and chars[1].me and chars[2].key == other)

-- ── 4. The Stats page ──────────────────────────────────────────────────────
MS:SetStatsChar("all")
MS:ShowScoreboard(); M.RunTimers(2)
UI.OpenStats(); M.RunTimers(2)
local f = MythicScoreboardFrame
local function find(text)
    for _, w in ipairs(M.allFrames) do
        if w._shown and w._kind == "Button" and w._children then
            for _, c in ipairs(w._children) do
                if c._kind == "FontString" and c._text and c._text:find(text, 1, true) then return w, c end
            end
        end
    end
end
local charBtn = find("All characters")
check("character filter shown", charBtn ~= nil)
check("summary counts all", f.Subline:GetText():find("4") ~= nil, f.Subline:GetText())
charBtn:Fire("OnEnter"); charBtn:Fire("OnLeave")
charBtn:Fire("OnClick")
local akRow = find("Akasha")
check("menu lists the other character", akRow ~= nil)
akRow:Fire("OnClick"); M.RunTimers(2)
check("filter applied", MS:GetStatsChar() == other and f.Subline:GetText():find("2") ~= nil, f.Subline:GetText())
local resetBtn = find("Reset stats")
check("no reset for another character", resetBtn == nil)
-- Detail rows: no remove button on another character's runs.
for _, w in ipairs(M.allFrames) do if w.dungeon == "Ragefire Chasm" and w._shown then w:Fire("OnClick") end end
M.RunTimers(2)
local delShown = 0
for _, w in ipairs(M.allFrames) do if w.entry and w.del and w._shown and w.del._shown then delShown = delShown + 1 end end
check("no remove on other's runs", delShown == 0, delShown)
for _, w in ipairs(M.allFrames) do if w.entry and w._shown then w:Fire("OnEnter"); w:Fire("OnLeave") end end
-- Back to all, then the Loot tab.
charBtn:Fire("OnClick"); find("All characters"):Fire("OnClick")
for _, w in ipairs(M.allFrames) do if w._shown and w._kind == "Button" and w._children then
    for _, c in ipairs(w._children) do if c._text == "All characters" and w ~= charBtn then w:Fire("OnClick") end end
end end
M.RunTimers(2)
check("back to all", MS:GetStatsChar() == "all")
local controls
for _, w in ipairs(M.allFrames) do if w.charBtn and w.lootTab then controls = w end end
local lootTab = controls.lootTab
local lootLbl
for _, c in ipairs(lootTab._children) do if c._kind == "FontString" then lootLbl = c end end
check("loot tab with count", lootLbl and lootLbl._text:find("2") ~= nil, lootLbl and lootLbl._text)
lootTab:Fire("OnClick"); M.RunTimers(2)
local lootRows = {}
for _, w in ipairs(M.allFrames) do if w._shown and w.data and w.data.item and w.icon then lootRows[#lootRows + 1] = w end end
check("loot rows", #lootRows == 2, #lootRows)
local fiery
for _, r in ipairs(lootRows) do if r.cells.item:GetText() == "Fiery Greatsword" then fiery = r end end
check("item name from link", fiery ~= nil)
check("loot boss shown", fiery and fiery.cells.boss:GetText():find("Oggleflint"))
check("loot character shown", fiery and fiery.cells.char:GetText() ~= "")
local loading
for _, r in ipairs(lootRows) do if r.cells.item:GetText() == "Loading..." then loading = r end end
check("unknown item waits for its name", loading ~= nil)
local linked
HandleModifiedItemClick = function(l) linked = l end
fiery:Fire("OnEnter"); fiery:Fire("OnLeave"); fiery:Fire("OnMouseUp", "LeftButton")
check("click hands the link to the game", linked == LINK)
local dunTab = controls.dunTab
dunTab:Fire("OnClick"); M.RunTimers(2)
check("dungeons tab back", f.overviewSF and true)
check("no stats errors", not errorsPrinted(), errorsPrinted())
UI.CloseStats()

-- Only one character: no filter.
acc.chars[other] = nil
UI.OpenStats(); M.RunTimers(2)
check("single character: no filter", not controls.charBtn:IsShown())
UI.CloseStats()

-- ── 5. Reset only touches this character ───────────────────────────────────
acc.chars[other] = { name = "Akasha", class = "MAGE", runs = { { at = 1, dungeon = "X", dur = 5, bosses = {}, group = {} } } }
MS:ResetArchive()
MS:SetStatsChar("all")
check("reset keeps other characters", #MS:StatsRuns() == 1 and #acc.chars[other].runs == 1)

-- ── 6. Old archive gets its loot from history once ─────────────────────────
local arc = MS._ArchiveStore()
arc.v = 3                                   -- an archive from before loot was kept
arc.runs = { MS:SummarizeRun(MythicScoreboardDB.runs[#MythicScoreboardDB.runs]) }
arc.runs[1].loot = nil
MS:MigrateArchive(arc)
check("loot backfilled", arc.runs[1].loot and #arc.runs[1].loot == 1)

-- ── 7. Minimap button ──────────────────────────────────────────────────────
local mb = MythicScoreboardMinimapButton
check("minimap button on by default", mb and mb:IsShown())
f:Hide()
mb:Fire("OnClick", "LeftButton")
check("left-click opens the scoreboard", f:IsShown() and not UI.statsOpen)
mb:Fire("OnClick", "LeftButton")
check("left-click again closes it", not f:IsShown())
mb:Fire("OnClick", "RightButton")
check("right-click opens stats", f:IsShown() and UI.statsOpen)
mb:Fire("OnClick", "LeftButton")
check("left-click from stats shows the scoreboard", f:IsShown() and not UI.statsOpen)
mb:Fire("OnEnter"); mb:Fire("OnLeave")
M.cursor = { 0, 100 }
mb:Fire("OnDragStart"); mb._scripts.OnUpdate(mb); mb:Fire("OnDragStop")
check("drag moves it", math.abs((MythicScoreboardDB.settings.minimapAngle or 0) - 90) < 0.01, MythicScoreboardDB.settings.minimapAngle)
-- The setting.
MS:SetMinimapButton(false)
check("turned off", not mb:IsShown() and MythicScoreboardDB.settings.minimapButton == false)
MS:SetMinimapButton(true)
check("turned on", mb:IsShown())
-- The settings row flips it.
f.SettingsBtn:Fire("OnClick")
local row = find("Minimap button")
check("settings row found", row ~= nil)
if row then row:Fire("OnClick") end
check("settings row turns it off", not mb:IsShown())
if row then row:Fire("OnClick") end
check("settings row turns it on", mb:IsShown())
check("no errors at all", not errorsPrinted(), errorsPrinted())

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

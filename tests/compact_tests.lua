-- usage: lua5.1 compact_tests.lua DIR TOC
-- The in-run frame (UI_Compact.lua): the demo, its styles, clicks, position.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
GetSpecialization = function() return 1 end              -- (the retail demo asks for your spec)
GetSpecializationInfo = function() return 262 end
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
MS._demoFixed = true                    -- the scripted dungeon (a random one is tested at the end)
local retail = MS.FLAVOR ~= "forever"
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
M.instance = { "Orgrimmar", "none", 0 }
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4)
local function frame() return rawget(_G, "MythicScoreboardCompact") end
local function shown(pat)
    local f = frame()
    for _, w in ipairs(M.allFrames) do
        if w._shown and w._kind == "FontString" and w._parent == f and (w._text or ""):find(pat) then return w._text end
    end
end
local function slash(s) SlashCmdList.MYTHICSCOREBOARD(s); M.RunTimers(2) end

-- Detailed unless the player picked another; the first test builds' saved
-- "compact" (never picked) gives way to it.
check("detailed by default", MS:GetCompactStyle() == "detailed", MS:GetCompactStyle())
MythicScoreboardDB.settings.compactStyle = "compact"
MS:InitSettings(MythicScoreboardDB)
check("an unpicked old default gives way", MS:GetCompactStyle() == "detailed", MS:GetCompactStyle())
MS:SetCompactStyle("minimal"); MS:InitSettings(MythicScoreboardDB)
check("a picked style stays", MS:GetCompactStyle() == "minimal", MS:GetCompactStyle())
MS:SetCompactStyle("detailed")

-- Out of a run: nothing.
check("not shown outside a run", frame() == nil or not frame()._shown)

-- The demo plays out (20 times real time) and starts over.
local function at(gameSeconds)                 -- jump the demo to that point of its run
    M.now = M.now + gameSeconds / 20
    MS:RefreshCompact()
end
slash("compact demo")
check("demo shows the frame", frame() and frame()._shown)
check("demo starts at 0:00", shown("^0:00$") ~= nil)
if retail then
    slash("compact detailed")
    check("start: no forces yet", shown("^0%.00%%$") ~= nil, shown("%%"))
end
at(1000)
check("demo clock moves", shown("^16:40$") ~= nil)
if retail then
    slash("compact compact")
    check("compact: the next upgrade in reach", shown("%+3 in 1:20") ~= nil, shown("in"))
    check("compact: bosses 2/3", shown("^2/3$") ~= nil)
    check("compact: pace against your best", shown("ahead") ~= nil, shown("ahead"))
    slash("compact detailed")
    check("detailed: time left", shown("13:20 left") ~= nil, shown("left"))
    check("detailed: forces to two decimals", shown("^64%.28%%$") ~= nil, shown("%%"))
    check("detailed: last pull", shown("Last pull") ~= nil and shown("12%.40") ~= nil)
    check("detailed: a boss being fought", shown("fighting") ~= nil)
    check("detailed: deaths and their cost", shown("^3  %-0:45$") ~= nil, shown("^3"))
    at(460)                                     -- 24:20: the key is done
    check("finish: all forces", shown("^100%.00%%$") ~= nil, shown("%%"))
    check("finish: the clock stops at the key's time", shown("^24:00$") ~= nil)
    check("finish: four deaths", shown("^4  %-1:00$") ~= nil, shown("^4"))
    at(100)                                     -- past the end: it starts over
    check("starts over", shown("^0:40$") ~= nil, shown("^%d+:%d%d$"))
else
    check("Forever: the wing", shown("Scarlet Monastery: Library") ~= nil)
    check("Forever: level range", shown("Levels") ~= nil)
    check("Forever: the boss down", shown("Houndmaster Loksey") ~= nil)
    check("Forever: experience, with the quest", shown("15,132") ~= nil, shown("1%d,"))
    at(480)                                     -- 24:40: both bosses down
    check("Forever: the clock stops at the last boss", shown("^24:20$") ~= nil)
    local tall = frame()._h
    slash("compact compact")
    check("Forever compact: shorter than detailed", frame()._h < tall, frame()._h .. " vs " .. tall)
    check("Forever compact: bosses as a count", shown("^2/2$") ~= nil)
    check("Forever compact: no boss list", shown("Houndmaster Loksey") == nil)
    slash("compact detailed")
end
slash("compact minimal")
local line = shown(":")
check("minimal: one line", line ~= nil and frame()._h == 28, frame()._h)

-- Right-click cycles the style; off hides (except the demo, shown compact).
MS:SetCompactStyle("compact")
frame():Fire("OnClick", "RightButton")
check("right-click: next style", MS:GetCompactStyle() == "detailed", MS:GetCompactStyle())
slash("compact demo")
check("demo off: hidden outside a run", not frame()._shown)

-- Dragging remembers where.
frame():SetPoint("CENTER", UIParent, "CENTER", 120, -40)
frame():Fire("OnDragStop")
local pos = MS:GetSetting("compactPos")
check("position remembered", type(pos) == "table" and pos[1] == "CENTER" and pos[3] == 120, pos and pos[3])

-- A real run shows it; leaving hides it; the setting turns it off.
M.instance = retail and { "Skyreach", "party", 1 } or { "Ragefire Chasm", "party", 1 }
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8)
check("shown during a real run", MS.currentRun ~= nil and frame()._shown)
MS:SetCompactFrame(false)
check("setting off: hidden", not frame()._shown and MS:GetCompactStyle() == "off")
MS:SetCompactFrame(true)
check("setting on: back with its style", frame()._shown and MS:GetCompactStyle() == "detailed", MS:GetCompactStyle())
-- Odd or missing run data: every style draws without an error, and so do
-- the mouse handlers.
local run = MS.currentRun
local odd = {
    function(r) r.bosses = { { name = nil }, { name = "X", killTime = 30 }, {} }; r.activeBoss = r.bosses[1] end,
    function(r) r.keystoneLevel, r.keystoneTimeLimit = 12, nil end,
    function(r) r.keystoneLevel, r.keystoneTimeLimit, r.currentPct, r.lastPull = 12, 1800, 140, 160 end,
    function(r) r.keystoneLevel, r.keystoneTimeLimit, r.forcesTotal, r.forcesCount = 12, "1800", 308, nil end,
    function(r) r.players = { Odd = { deaths = 2, deathEvents = { {} } } }; r.deathPenaltySeconds = 30 end,
    function(r) r.affixes = { 9, { id = 10 }, {}, "x" }; r.progress = { kills = 3 } end,
    function(r) r.keystoneLevel, r.dungeonName, r.wingName = 0, nil, nil end,
}
for i, mangle in ipairs(odd) do
    mangle(run)
    for _, style in ipairs({ "compact", "detailed", "minimal" }) do
        MS:SetCompactStyle(style)
        MS:RefreshCompact()
        for _, w in ipairs(M.allFrames) do
            if w._shown and (w == frame() or w._parent == frame()) and w.Fire then
                w:Fire("OnEnter"); w:Fire("OnLeave")
            end
        end
        check("odd data " .. i .. " (" .. style .. ") shown", frame()._shown)
    end
end
frame():Fire("OnClick", "RightButton")
MS:SetCompactStyle("detailed")
-- A random dungeon each loop: a Forever dungeon from the table; a key from
-- the season's maps, with its bosses from the journal.
MS._demoFixed = nil
local function demoRun() return MS._CompactDemo() end
if demoRun() then slash("compact demo") end
MS:SetCompactStyle("detailed")
if retail then
    C_ChallengeMode = {
        GetMapTable = function() return { 501, 502 } end,
        GetMapUIInfo = function(id) return id == 501 and "Altar of Fangs" or "Murder Row", id, id == 501 and 1800 or 2040 end,
    }
    EJ_GetNumTiers = function() return 1 end
    EJ_SelectTier = function() end
    EJ_GetCurrentTier = function() return 1 end
    EJ_GetInstanceByIndex = function(i) if i == 1 then return 9001, "Altar of Fangs" elseif i == 2 then return 9002, "Murder Row" end end
    EJ_GetEncounterInfoByIndex = function(e, id)
        local list = id == 9001 and { "Fang One", "Fang Two", "Fang Three" } or { "Row A", "Row B", "Row C", "Row D" }
        return list[e]
    end
end
local seen = {}
for _ = 1, 12 do
    slash("compact demo")
    local title = MS:RunTitle(demoRun())
    seen[title] = true
    if retail then
        check("random key: a season dungeon", title == "Altar of Fangs" or title == "Murder Row", title)
        check("random key: its bosses", shown("^Fang One") ~= nil or shown("^Row A") ~= nil)
    else
        check("random Forever: a known dungeon", MS.FOREVER_DUNGEONS[title] ~= nil, title)
    end
    at(5000)                                     -- past the end: the next loop
    check("random: still shown after a loop", frame()._shown)
    slash("compact demo")
end
local n = 0
for _ in pairs(seen) do n = n + 1 end
check("random: more than one dungeon", n > 1, n)

for _, p in ipairs(M.printed) do if p:find("error") then check("no errors", false, p) end end

io.stdout:write(("compact_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

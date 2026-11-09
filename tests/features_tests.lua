-- usage: lua5.1 features_tests.lua DIR TOC
-- 2.9: key upgrades (+1/+2/+3), your rating change, specializations, the
-- timeline's upgrade thresholds, and every character's runs in history.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
-- Specializations (retail): set before loading, the addon checks for them then.
local SPECS = { [65] = { "Holy", "HEALER", "PALADIN" }, [62] = { "Arcane", "DAMAGER", "MAGE" }, [264] = { "Restoration", "HEALER", "SHAMAN" } }
GetSpecializationInfoByID = function(id)
    local s = SPECS[id]; if s then return id, s[1], "", 0, s[2], s[3] end
end
GetSpecialization = function() return 3 end
GetSpecializationInfo = function(i) if i == 3 then return 264 end end
LOCALIZED_CLASS_NAMES_MALE = { PALADIN = "Paladin", MAGE = "Mage", SHAMAN = "Shaman" }
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local forever = MS.FLAVOR == "forever"
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local clock = 1800000000
time = function() return clock end
local function wait(s) M.now = M.now + s; clock = clock + s end
local WORLD = { "Orgrimmar", "none", 0 }
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local function reset(keepAccount)
    M.timers = {}; MythicScoreboardDB = nil
    if not keepAccount then MythicScoreboardAccountDB = nil end
    MS.currentRun, MS.inDungeon, MS.displayRun = nil, false, nil
    M.dead = {}; M.instance = WORLD; M.printed = {}
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
end

-- ── Upgrade levels ─────────────────────────────────────────────────────────
check("+3 at 60%", MS.KeyUpgrades(1080, 1800, true) == 3)
check("+2 just over 60%", MS.KeyUpgrades(1081, 1800, true) == 2)
check("+2 at 80%", MS.KeyUpgrades(1440, 1800, true) == 2)
check("+1 just over 80%", MS.KeyUpgrades(1441, 1800, true) == 1)
check("+1 at the timer", MS.KeyUpgrades(1800, 1800, true) == 1)
check("0 over time", MS.KeyUpgrades(1900, 1800, false) == 0)
check("no limit: 0", MS.KeyUpgrades(1000, nil, true) == 0)
check("not a key: none", MS:RunUpgrades({ completed = true, inTime = true, duration = 10 }) == nil)
check("game's count wins", MS:RunUpgrades({ completed = true, keystoneLevel = 5, keyUpgrades = 2,
    duration = 100, keystoneTimeLimit = 1000, inTime = true }) == 2)
local pips = MS.UI.Pips(2, 12)
local _, full = pips:gsub("PipFull", ""); local _, empty = pips:gsub("PipEmpty", "")
check("pips: two filled, one hollow", full == 2 and empty == 1, pips)
_, empty = MS.UI.Pips(0):gsub("PipEmpty", "")
check("pips: over time all hollow", empty == 3)

-- ── A key: upgrades and your rating from the game ──────────────────────────
if not forever then
    reset()
    local map = 2526
    C_ChallengeMode = {
        GetActiveChallengeMapID = function() return map end,
        GetActiveKeystoneInfo = function() return 15, {}, true end,
        GetMapInfo = function() return { name = "Skyreach" } end,
        GetMapUIInfo = function() return "Skyreach", map, 1800 end,
        GetChallengeCompletionInfo = function()
            return { time = 1300000, onTime = true, level = 15, keystoneUpgradeLevels = 2,
                     oldOverallDungeonScore = 2827, newOverallDungeonScore = 2845 }
        end,
        GetDeathCount = function() return 0, 0 end,
        GetDungeonScoreRarityColor = function() return { r = 1, g = 0.5, b = 0 } end,
        GetSpecificDungeonOverallScoreRarityColor = function() return { r = 1, g = 0.5, b = 0 } end,
    }
    zone({ "Skyreach", "party", 8 })
    M.Fire("CHALLENGE_MODE_START", map); M.RunTimers(3)
    MS:PopulateRolesAndScores(); MS:PopulateAll()
    local run = MS.currentRun
    local me = run and MS:PlayerByName("Jay", run)
    check("own spec read directly", me and me.specID == 264, me and me.specID)
    check("spec label", MS.SpecLabel(264, "SHAMAN") == "Restoration Shaman", MS.SpecLabel(264, "SHAMAN"))
    wait(1300)
    M.Fire("CHALLENGE_MODE_COMPLETED"); M.RunTimers(6)
    local saved = MythicScoreboardDB.runs[1]
    check("key saved", saved and saved.keystoneLevel == 15)
    check("upgrades from the game", saved and saved.keyUpgrades == 2 and MS:RunUpgrades(saved) == 2, saved and saved.keyUpgrades)
    check("rating before/after", saved and saved.ratingBefore == 2827 and saved.ratingAfter == 2845)
    local sp = saved and saved.players[MS.ShortName("Jay")]
    check("your row: new rating and gain", sp and sp.mythicScore == 2845 and sp.ratingGain == 18,
        sp and (tostring(sp.mythicScore) .. " " .. tostring(sp.ratingGain)))
    check("spec saved with the run", sp and sp.specID == 264)

    -- The header shows the pips and the rating; the timeline its thresholds.
    MS:ShowScoreboard(); M.RunTimers(3)
    local sub = MS.UI.frame.Subline:GetText() or ""
    check("header: pips", sub:find("PipFull") ~= nil, sub)
    check("header: rating gain", sub:find("+18", 1, true) ~= nil, sub)
    local labels = {}
    for _, f in ipairs(M.allFrames) do
        if f._kind == "FontString" and f._shown ~= false then
            local t = f.GetText and f:GetText()
            if t == "+1" or t == "+2" or t == "+3" then labels[t] = (labels[t] or 0) + 1 end
        end
    end
    check("timeline: +1, +2 and +3 marked", labels["+1"] and labels["+2"] and labels["+3"],
        tostring(labels["+1"]) .. tostring(labels["+2"]) .. tostring(labels["+3"]))
    C_ChallengeMode = nil
end

-- ── Other players' specs come from the inspect ─────────────────────────────
if not forever then
    reset()
    zone({ "Skyreach", "party", 1 })
    local run = MS.currentRun
    MS.specCache["Akasha"] = 62
    MS:PopulateAll()
    local p = run and MS:PlayerByName("Akasha", run)
    check("cached spec applied", p and p.specID == 62, p and p.specID)
    check("label for a mage", MS.SpecLabel(62, "MAGE") == "Arcane Mage")
    MS:AbandonRun()
end

-- ── Every character's history ──────────────────────────────────────────────
reset()
MythicScoreboardDB.runs = {
    { dungeonName = "Mine B", _wallClockStart = 2000, duration = 100, players = {}, bosses = {} },
    { dungeonName = "Mine A", _wallClockStart = 1000, duration = 100, players = {}, bosses = {} },
}
MS:MirrorHistory()
local key = MS._charKey
check("mirrored account-wide", key and MythicScoreboardAccountDB.chars[key].history == MythicScoreboardDB.runs)
MythicScoreboardAccountDB.chars["Alt@Realm"] = { name = "Alt", class = "MAGE", history = {
    { dungeonName = "Alt run", _wallClockStart = 1500, duration = 100, players = {}, bosses = {} },
} }
local e = MS:HistoryEntries()
check("all: three runs", #e == 3, #e)
check("all: newest first, interleaved", e[1].run.dungeonName == "Mine B" and e[2].run.dungeonName == "Alt run"
    and e[3].run.dungeonName == "Mine A", e[2] and e[2].run.dungeonName)
check("all: owner known", e[2].owner and e[2].owner.name == "Alt" and e[1].own)
check("other character's run isn't ours", MS:HistoryOwner(e[2].run) ~= nil and not MS:IsOwnHistoryRun(e[2].run))
check("index in the list", MS:HistoryIndexOf(e[2].run) == 2)
MS:SetHistoryScope("me")
check("this character only", #MS:HistoryEntries() == 2)
MS:SetHistoryScope("all")
check("scope saved account-wide", MythicScoreboardAccountDB.historyScope == nil and MS:GetHistoryScope() == "all")
-- The dropdown lists them all, with names; another character's run has no delete.
MS:ShowScoreboard(); M.RunTimers(3)
MS.UI.OpenHistDropdown(MS.UI.frame.HistoryButton)
local shownAlt
for _, f in ipairs(M.allFrames) do
    if f._kind == "FontString" and f._shown ~= false and f.GetText and f:GetText() == "Alt" then shownAlt = true end
end
check("dropdown: character names", shownAlt)
MS.UI.CloseHistDropdown()
-- Viewing another character's run.
MS.displayRun = e[2].run
MS:RefreshOverview(); M.RunTimers(2)
check("viewing another character's run", MS.displayRun == e[2].run)
-- Clearing history keeps the mirror in step.
MS:ClearHistory()
check("cleared: mirror follows", MythicScoreboardAccountDB.chars[key].history == MythicScoreboardDB.runs and #MythicScoreboardDB.runs == 0)
check("cleared: other characters kept", #MS:HistoryEntries() == 1)

-- ── /sb demo: a sample key, shown and never saved ─────────────────────────
reset()
local before = #MythicScoreboardDB.runs
for _, up in ipairs({ 0, 1, 2, 3 }) do
    SlashCmdList["MYTHICSCOREBOARD"]("demo " .. up); M.RunTimers(2)
    local d = MS.displayRun
    check("demo " .. up .. ": shown", d and d._demo and MS:RunUpgrades(d) == up, d and MS:RunUpgrades(d))
    local n = 0
    for _ in pairs(d and d.players or {}) do n = n + 1 end
    check("demo " .. up .. ": five players", n == 5, n)
    local sub = MS.UI.frame.Subline:GetText() or ""
    local _, filled = sub:gsub("PipFull", "")
    check("demo " .. up .. ": diamonds", filled == up, sub)
end
check("demo: not saved", #MythicScoreboardDB.runs == before and #MS:ArchiveRuns() == 0)
check("demo: not a personal best", not MS:IsPersonalBest(MS.displayRun))

-- ── Abandoned inside: a new run without leaving ────────────────────────────
reset()
zone({ "Ragefire Chasm", "party", 1 })
local first = MS.currentRun
check("fresh: a run started", first ~= nil)
check("fresh: not offered while a run is going", not MS:CanStartFresh())
MS:AbandonRun()
check("fresh: abandoned, nothing new yet", MS.currentRun == nil and MS:CanStartFresh())
zone({ "Ragefire Chasm", "party", 1 })
check("fresh: still none after a location check", MS.currentRun == nil)
MS:ShowScoreboard(); M.RunTimers(2)
check("fresh: button shown", MS.UI.frame.FreshRunBtn and MS.UI.frame.FreshRunBtn._shown ~= false)
MS.UI.frame.FreshRunBtn._scripts.OnClick(MS.UI.frame.FreshRunBtn); M.RunTimers(3)
local second = MS.currentRun
check("fresh: a new run here", second and second ~= first and second.dungeonName == first.dungeonName)
check("fresh: no longer offered", not MS:CanStartFresh())
check("fresh: button hidden", MS.UI.frame.FreshRunBtn._shown == false)
check("fresh: the abandoned one saved", MythicScoreboardDB.runs[1] and MythicScoreboardDB.runs[1].abandoned)
zone(WORLD); M.RunTimers(4)
MS:AbandonRun()
check("fresh: not offered outside", not MS:CanStartFresh())

-- ── Stats page: the Keys tab ───────────────────────────────────────────────
if not forever then
    reset()
    local function Key(at, lvl, dur, inTime, r0, r1, up)
        local r = MS.NewRunData()
        r.dungeonName, r.keystoneLevel, r.keystoneTimeLimit = (lvl % 2 == 0) and "Skyreach" or "Pit of Saron", lvl, 1800
        r.completed, r.inTime, r.duration, r._wallClockStart = true, inTime, dur, at
        r.keyUpgrades, r.ratingBefore, r.ratingAfter = up, r0, r1
        r.players = {}
        local p = MS.NewPlayerStats(MS.ShortName("Jay"), "SHAMAN", "Player-1")
        p.mythicScore = r0
        r.players[p.name] = p
        return r
    end
    MS:ArchiveRun(Key(1000, 10, 1000, true, 2500, 2530, 3))
    MS:ArchiveRun(Key(2000, 12, 1500, true, 2530, 2550, nil))      -- no count from the game: worked out (+1)
    MS:ArchiveRun(Key(3000, 12, 2000, false, 2550, 2550, 0))
    MS:ArchiveRun(Key(4000, 13, 1300, true, 2550, nil, nil))       -- older: only the rating going in
    local ks = MS:KeyStats()
    check("keys: counted", ks.keys == 4 and ks.timed == 3, ks.keys .. " " .. ks.timed)
    local sky
    for _, d in ipairs(ks.dungeons) do if d.name == "Skyreach" then sky = d end end
    check("keys: per dungeon", sky and sky.keys == 3 and sky.timed == 2 and sky.bestTimed == 12 and sky.highest == 12)
    check("keys: average upgrade (3 + 1 + 0)", sky and sky.upN == 3 and sky.upSum == 4, sky and (sky.upSum .. "/" .. sky.upN))
    check("keys: levels, highest first", ks.levels[1].level == 13 and ks.levels[2].level == 12
        and ks.levels[2].keys == 2 and ks.levels[2].timed == 1)
    local pts = select(2, next(ks.rating))
    check("keys: rating points", pts and #pts == 4 and pts[1].v == 2530 and pts[4].v == 2550 and not pts[4].after)
    -- The tab itself.
    MS:ShowScoreboard(); MS.UI.OpenStats(); M.RunTimers(2)
    local tab = MS.UI.StatsKit.S
    tab.tab = "keys"; MS.UI.RefreshStats(true)
    local sub = MS.UI.frame.Subline:GetText() or ""
    check("keys tab: summary", sub:find("4") and sub:find("75%%") and sub:find("2550"), sub)
    local diamonds = 0
    for _, f in ipairs(M.allFrames) do
        if f._kind == "Button" and f.pt and f._shown ~= false then diamonds = diamonds + 1 end
    end
    check("keys tab: a diamond per key", diamonds == 4, diamonds)
    MS.UI.CloseStats()
    -- Older archived keys get their details from history, once.
    reset()
    local old = Key(5000, 14, 1000, true, 2600, 2621, 3)
    MythicScoreboardDB.runs = { old }
    local acc = MythicScoreboardAccountDB
    MS:ArchiveRuns()
    local key = MS._charKey
    local arch = acc.chars[key].archive
    arch.keysV = nil
    for _, e in ipairs(arch.runs) do e.up, e.r0, e.r1, e.lim = nil, nil, nil, nil end
    MS:ArchiveRuns()
    local e = arch.runs[#arch.runs]
    check("backfill: from history", e and e.up == 3 and e.r1 == 2621 and e.r0 == 2600 and e.lim == 1800,
        e and (tostring(e.up) .. " " .. tostring(e.r1)))
end

io.stdout:write(("features_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

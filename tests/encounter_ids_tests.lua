-- usage: lua5.1 encounter_ids_tests.lua DIR TOC   (Forever: bosses known by encounter ID; fights of several bosses)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if MS.FLAVOR ~= "forever" then io.stdout:write("retail: 0 passed, 0 failed (WoW Forever only)\n"); os.exit(0) end
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local function wait(s) M.now = M.now + s; M.RunTimers(1) end
local function fight(id, name, kill)
    M.Fire("ENCOUNTER_START", id, name); wait(20)
    M.Fire("ENCOUNTER_END", id, name, 1, 5, kill == false and 0 or 1); M.RunTimers(2)
end
local function killed(name)
    for _, b in ipairs(MS.currentRun.bosses) do if b.killTime and b.name == name then return b end end
end
local function enter(dungeon)
    if MS.currentRun then zone({ "Orgrimmar", "none", 0 }); if MS.currentRun and MS.currentRun._suspended then MS:ClosePausedRun() end end
    MythicScoreboardDB.activeRun = nil
    zone({ dungeon, "party", 1 })
end
M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
M.level = 58
M.Fire("ADDON_LOADED", "MythicScoreboard")
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end

-- ── Every encounter names a boss of its dungeon ────────────────────────────
local bad = {}
for id, e in pairs(MS.ForeverData.ENCOUNTERS) do
    local def = MS.FOREVER_DUNGEONS[e[1]]
    local ok = false
    for _, b in ipairs(def and def.bosses or {}) do if b.name == e[2] then ok = true end end
    for _, a in ipairs(e.also or {}) do
        local found = false
        for _, b in ipairs(def and def.bosses or {}) do if b.name == a then found = true end end
        ok = ok and found
    end
    if not ok then bad[#bad + 1] = id end
end
check("every encounter ID names a boss of its dungeon", #bad == 0, table.concat(bad, ","))

-- ── Another language: the kill counts by its ID ────────────────────────────
enter("Krol'dok Stronghold")
fight(3449, "Nar'gurk der Schlächter")
check("ID: recorded under the list's name", killed("Nar'gurk") ~= nil)
-- one of its own other names is kept
fight(3452, "Zarmok")
check("ID: the game's own other name kept", killed("Zarmok") ~= nil)
local n = MS:ForeverBossProgress(MS.currentRun)
check("both count", n == 2, n)
-- an ID we don't know: the game's name, as before
fight(99999, "Someone New")
check("unknown ID: the game's name", killed("Someone New") ~= nil)

-- ── Ring of Law: one fight, whichever challenger ──────────────────────────
enter("Blackrock Depths")
local _, total = MS:ForeverBossProgress(MS.currentRun)
fight(nil, "Grizzle")
local done = MS:ForeverBossProgress(MS.currentRun)
check("Ring of Law: one challenger is the fight", done == 1, done)
check("Ring of Law: one boss, not six (" .. tostring(total) .. " required)", total and total <= 21, total)
fight(230, "Ring of Law")
check("Ring of Law: its own event too, still one", MS:ForeverBossProgress(MS.currentRun) == 1)
check("Moira: not needed", (function()
    local def = MS:ForeverDungeon(MS.currentRun)
    for _, b in ipairs(def.bosses) do if b.name == "Princess Moira Bronzebeard" then return b.rare == true end end
end)())

-- ── Fights that end two bosses ─────────────────────────────────────────────
enter("Upper Blackrock Spire")
fight(3063, "Warchief Rend Blackhand")
check("Rend's fight: Rend", killed("Warchief Rend Blackhand") ~= nil)
check("Rend's fight: Gyth too", killed("Gyth") ~= nil)
check("Gyth once", (function() local c = 0 for _, b in ipairs(MS.currentRun.bosses) do if b.name == "Gyth" then c = c + 1 end end return c end)() == 1)

enter("Sunken Temple")
fight(490, "Morphaz & Hazzas")
check("Morphaz & Hazzas: both", killed("Morphaz & Hazzas") ~= nil and killed("Hazzas") ~= nil)
check("Morphaz & Hazzas counts as Morphaz", MS:ForeverSameBoss(MS.currentRun, "Morphaz", "Morphaz & Hazzas"))
fight(3587, "Weaver"); fight(3588, "Dreamscythe")
check("Forever's own Weaver and Dreamscythe", killed("Weaver") ~= nil and killed("Dreamscythe") ~= nil)

local function errorsPrinted() for _, p in ipairs(M.printed) do if p:find("rror") then return p end end end
check("no errors", not errorsPrinted(), errorsPrinted())
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR, passes, fails))
os.exit(fails == 0 and 0 or 1)

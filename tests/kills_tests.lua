-- usage: lua5.1 kills_tests.lua DIR TOC   (Forever: mob kills seen on enemies, with or without XP)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if not MS.Flavor.progressStats then
    io.stdout:write("kills_tests: retail has no run stats, skipped\n")
    os.exit(0)
end
local RFC = { "Ragefire Chasm", "party", 1 }
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local function mob(unit, name, id, extra)
    local r = { name = name, guid = "Creature-0-1-389-0-" .. id .. "-0000ABCD", npc = true, hostile = true }
    for k, v in pairs(extra or {}) do r[k] = v end
    M.roster[unit] = r
    M.dead[unit] = nil
end
local function die(unit, event, arg)
    M.dead[unit] = true
    M.Fire(event or "UNIT_HEALTH", arg or unit); M.RunTimers(1)
end
local function xpline(name) M.Fire("CHAT_MSG_COMBAT_XP_GAIN", name .. " dies, you gain 45 experience."); M.RunTimers(1) end

M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
M.xp, M.xpMax, M.level, M.money = 4000, 5000, 14, 10000
M.Fire("ADDON_LOADED", "MythicScoreboard")
zone(RFC)
local run = MS.currentRun
check("run started", run ~= nil)
local function kills() return run.progress and run.progress.kills or 0 end

-- A grey mob (no XP line): seen alive on its nameplate, then dead.
mob("nameplate1", "Ragefire Trogg", 11318)
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check("alive: not a kill", kills() == 0, kills())
die("nameplate1")
check("grey mob: counted", kills() == 1, kills())
M.Fire("UNIT_HEALTH", "nameplate1"); M.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check("same mob: once", kills() == 1, kills())

-- A mob giving XP: the line and the nameplate are one kill, either order.
mob("nameplate2", "Ragefire Shaman", 11319)
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
die("nameplate2"); M.now = M.now + 1
xpline("Ragefire Shaman")
check("plate then XP line: once", kills() == 2, kills())
mob("nameplate3", "Searing Blade Cultist", 11322)
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
xpline("Searing Blade Cultist"); M.now = M.now + 1
die("nameplate3")
check("XP line then plate: once", kills() == 3, kills())

-- Only the XP line (nameplates off): still a kill.
xpline("Earthborer")
check("XP line alone: counted", kills() == 4, kills())
-- Long after, the same name dying on a plate is a new kill.
M.now = M.now + 30
mob("nameplate4", "Earthborer", 11320)
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4"); die("nameplate4")
check("same name later: counted", kills() == 5, kills())

-- A corpse never seen alive, a mob someone else tapped, a friendly NPC.
mob("nameplate5", "Ragefire Trogg", 11318)
M.dead.nameplate5 = true
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
check("corpse: not counted", kills() == 5, kills())
mob("nameplate6", "Ragefire Trogg", 11318, { tapDenied = true })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate6"); die("nameplate6")
check("tapped by others: not counted", kills() == 5, kills())
mob("nameplate7", "Oggleflint's Pet", 11400, { hostile = false })
M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate7"); die("nameplate7")
check("friendly: not counted", kills() == 5, kills())

-- A party member's target, caught after the fight.
mob("party1target", "Molten Elemental", 11321)
M.Fire("UNIT_TARGET", "party1")
M.dead.party1target = true
M.Fire("PLAYER_REGEN_ENABLED"); M.RunTimers(1)
check("party target, after the fight: counted", kills() == 6, kills())

-- A boss dying on its nameplate tells the fight it's over.
local noted
local orig = MS.NoteMobDied
MS.NoteMobDied = function(_, name) noted = name end
mob("target", "Oggleflint", 11517)
M.Fire("PLAYER_TARGET_CHANGED"); die("target", "PLAYER_TARGET_CHANGED", nil)
MS.NoteMobDied = orig
check("boss death noted", noted == "Oggleflint", noted)
check("boss: counted", kills() == 7, kills())

-- Forever hides mob GUIDs and names in instances: a mob is its nameplate,
-- and its XP line is matched to whichever nameless kill came with it.
M.now = M.now + 30
local function hidden(unit) M.roster[unit] = { npc = true, hostile = true }; M.dead[unit] = nil end
local base = kills()
hidden("nameplate8"); M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate8"); die("nameplate8")
check("hidden grey mob: counted", kills() == base + 1, kills())
M.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate8")
check("hidden: once", kills() == base + 1, kills())
hidden("nameplate8"); M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate8")     -- the plate, on a new mob
M.now = M.now + 30
die("nameplate8"); xpline("Ragefire Shaman")
check("hidden, then XP line: once", kills() == base + 2, kills())
M.now = M.now + 30
hidden("nameplate9"); M.Fire("NAME_PLATE_UNIT_ADDED", "nameplate9")
xpline("Ragefire Shaman"); die("nameplate9")
check("XP line, then hidden: once", kills() == base + 3, kills())

for _, p in ipairs(M.printed) do if p:find("error") then check("no errors", false, p) end end
io.stdout:write(("kills_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

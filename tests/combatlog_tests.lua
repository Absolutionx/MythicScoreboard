-- usage: lua5.1 combatlog_tests.lua DIR TOC   (combat logging: the reminder, auto, the upload reminder)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4)
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.RunTimers(2) end
local function said(pat) for _, p in ipairs(M.printed) do if p:find(pat) then return p end end end
local function shown(name) local f = rawget(_G, name); return f and f._shown end
local forever = MS.FLAVOR == "forever"

-- Off until turned on.
check("default: off", MS:GetCombatLog() == "off", MS:GetCombatLog())
zone({ "Onyxia's Lair", "raid", 9 })
check("default: nothing in a raid", not shown("MythicScoreboardLogReminder") and M.logging == false)
zone({ "Dustwallow Marsh", "none", 0 })
check("default: raids only", MS:GetCombatLogWhere() == "raids")

-- Remind: going into a raid with logging off.
MS:SetCombatLog("remind")
zone({ "Onyxia's Lair", "raid", 9 })
check("remind: the popup in a raid", shown("MythicScoreboardLogReminder"))
check("remind: logging still off", M.logging == false)
local d = rawget(_G, "MythicScoreboardLogReminder")
d.start:GetScript("OnClick")(d.start)
check("start logging: on", M.logging == true and said("Combat logging on"))
check("start logging: Advanced Combat Logging on", M.cvars.advancedCombatLogging == "1" and said("Advanced Combat Logging turned on"))
check("start logging: popup gone", not shown("MythicScoreboardLogReminder"))
-- Out again: logging the addon started stops; the upload reminder.
zone({ "Dustwallow Marsh", "none", 0 })
check("out: logging off", M.logging == false and said("Combat logging off"))
check("out: no upload popup (the log site's app uploads)", rawget(_G, "MythicScoreboardLogUpload") == nil)

-- Not again in the same raid after "Not now"; dungeons left alone (raids only).
zone({ "Onyxia's Lair", "raid", 9 })
d.later:GetScript("OnClick")(d.later)
M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(1)
check("not now: not asked again in the same raid", not shown("MythicScoreboardLogReminder"))
zone({ "Ragefire Chasm", "party", 1 })
check("raids only: a dungeon isn't asked about", not shown("MythicScoreboardLogReminder"))
MS:SetCombatLogWhere("all")
zone({ "Dustwallow Marsh", "none", 0 }); zone({ "Ragefire Chasm", "party", 1 })
check("raids and dungeons: a dungeon is asked about", shown("MythicScoreboardLogReminder"))
zone({ "Dustwallow Marsh", "none", 0 })
check("out: the reminder goes", not shown("MythicScoreboardLogReminder"))

-- Dungeons only: raids left alone; a dungeon you log brings the upload reminder too.
MS:SetCombatLogWhere("dungeons")
zone({ "Onyxia's Lair", "raid", 9 })
check("dungeons only: a raid isn't asked about", not shown("MythicScoreboardLogReminder"))
zone({ "Dustwallow Marsh", "none", 0 }); zone({ "Ragefire Chasm", "party", 1 })
check("dungeons only: a dungeon is", shown("MythicScoreboardLogReminder"))
d.start:GetScript("OnClick")(d.start)
zone({ "Dustwallow Marsh", "none", 0 })
check("a dungeon: logging stops on the way out", M.logging == false)

-- Automatically: on the way in, off on the way out.
MS:SetCombatLog("auto"); MS:SetCombatLogWhere("raids")
zone({ "Onyxia's Lair", "raid", 9 })
check("auto: on in a raid", M.logging == true and not shown("MythicScoreboardLogReminder"))
zone({ "Dustwallow Marsh", "none", 0 })
check("auto: off when out", M.logging == false)
-- Logging you started yourself is yours: not stopped.
M.logging = true
zone({ "Onyxia's Lair", "raid", 9 }); zone({ "Dustwallow Marsh", "none", 0 })
check("auto: your own logging left on", M.logging == true)
M.logging = false

-- Off: nothing at all.
MS:SetCombatLog("off")
zone({ "Onyxia's Lair", "raid", 9 })
check("off: no popup, no logging", not shown("MythicScoreboardLogReminder") and M.logging == false)
zone({ "Dustwallow Marsh", "none", 0 })

io.stdout:write((forever and "forever" or "retail") .. ": " .. passes .. " passed, " .. fails .. " failed\n")
os.exit(fails == 0 and 0 or 1)

-- usage: lua5.1 loot_chat_tests.lua DIR TOC   (loot read from chat lines: yours, others', other word orders)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
-- The game's own English formats (the mock gives every one the same text).
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_ITEM_PUSHED = "%s receives item: %s."
LOOT_ITEM_PUSHED_MULTIPLE = "%s receives item: %sx%d."
LOOT_ITEM_BONUS_ROLL = "%s receives bonus loot: %s."
LOOT_ITEM_BONUS_ROLL_MULTIPLE = "%s receives bonus loot: %sx%d."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
LOOT_ITEM_BONUS_ROLL_SELF = "You receive bonus loot: %s."
LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE = "You receive bonus loot: %sx%d."
-- (Set before loading: the addon keeps its own reference to it.)
-- Gear: armour (class 4) you can wear; anything else isn't kept.
local GEAR = { [12345] = true, [22222] = true, [33333] = true, [44444] = true, [55555] = true }
GetItemInfoInstant = function(link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    if not id then return nil end
    if GEAR[id] then return id, nil, nil, "INVTYPE_CHEST", nil, 4 end
    return id, nil, nil, "", nil, 15
end
C_Item.GetItemInfoInstant = GetItemInfoInstant
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function link(id, name, q) return ("|cnIQ%d:|Hitem:%d::::::::20:::::|h[%s]|h|r"):format(q or 3, id, name) end

local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
local function loot(who)
    local p = MS.currentRun and MS:PlayerByName(who, MS.currentRun)
    return p and p.loot or {}
end
local function say(text) M.Fire("CHAT_MSG_LOOT", text); M.RunTimers(1); M.now = M.now + 20 end

M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
M.Fire("ADDON_LOADED", "MythicScoreboard")
M.Fire("PLAYER_LOGIN"); M.RunTimers(1)
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
M.groupSize = 3
zone(MS.FLAVOR == "forever" and { "Ragefire Chasm", "party", 1 } or { "Ragefire Chasm", "party", 2 })
check("run started", MS.currentRun ~= nil)

-- ── What a line says ───────────────────────────────────────────────────────
local who, item = MS:_ParseLootMessage("You receive loot: " .. link(12345, "Robe") .. ".")
check("yours: you", who == MS:UnitPlayerName("player"), who)
check("yours: the item", item and item:find("item:12345"), item)
who, item = MS:_ParseLootMessage("Akasha receives loot: " .. link(22222, "Boots") .. ".")
check("someone else's: who", who == "Akasha", who)
check("someone else's: the item", item and item:find("item:22222"), item)
who, item = MS:_ParseLootMessage("Akasha receives loot: " .. link(22222, "Boots") .. "x2.")
check("several at once: who and item", who == "Akasha" and item and item:find("item:22222"), tostring(who) .. " " .. tostring(item))
who = MS:_ParseLootMessage("You receive bonus loot: " .. link(33333, "Helm") .. ".")
check("bonus loot", who == MS:UnitPlayerName("player"), who)
who = MS:_ParseLootMessage("Akasha has selected Need for: " .. link(22222, "Boots"))
check("a roll isn't loot", who == nil, who)
check("not text: nothing", MS:_ParseLootMessage(nil) == nil and MS:_ParseLootMessage(5) == nil)

-- ── Into the run ───────────────────────────────────────────────────────────
say("You receive loot: " .. link(12345, "Robe") .. ".")
check("your piece recorded", #loot(MS:UnitPlayerName("player")) == 1, #loot(MS:UnitPlayerName("player")))
check("recorded as from chat", loot(MS:UnitPlayerName("player"))[1] and loot(MS:UnitPlayerName("player"))[1].src == "chat")
say("Akasha receives loot: " .. link(22222, "Boots") .. ".")
check("theirs recorded", #loot("Akasha") == 1, #loot("Akasha"))
say("Akasha receives loot: " .. link(77777, "Linen Cloth", 1) .. ".")
check("not gear: not kept", #loot("Akasha") == 1, #loot("Akasha"))
say("Akasha receives loot: " .. link(55555, "Grey Belt", 0) .. ".")
check("poor quality: not kept", #loot("Akasha") == 1, #loot("Akasha"))
say("Stranger receives loot: " .. link(44444, "Cloak") .. ".")
check("someone not in the run: nothing", MS:PlayerByName("Stranger", MS.currentRun) == nil)
-- The same drop twice at once (from chat and the game): once.
M.Fire("CHAT_MSG_LOOT", "Akasha receives item: " .. link(33333, "Helm") .. "."); M.RunTimers(1)
M.Fire("CHAT_MSG_LOOT", "Akasha receives loot: " .. link(33333, "Helm") .. "."); M.RunTimers(1)
check("the same drop twice: once", #loot("Akasha") == 2, #loot("Akasha"))

-- ── Another word order (a client whose format puts the item first) ────────
LOOT_ITEM = "%2$s goes to %1$s."
M.Fire("PLAYER_LOGIN"); M.RunTimers(1)
who, item = MS:_ParseLootMessage(link(44444, "Cloak") .. " goes to Girthy.")
check("item first: still who, then what", who == "Girthy" and item and item:find("item:44444"), tostring(who) .. " / " .. tostring(item))

-- ── Another language ───────────────────────────────────────────────────────
LOOT_ITEM = "%s erhält Beute: %s."
LOOT_ITEM_SELF = "Ihr erhaltet Beute: %s."
M.Fire("PLAYER_LOGIN"); M.RunTimers(1)
who = MS:_ParseLootMessage("Akasha erhält Beute: " .. link(22222, "Stiefel") .. ".")
check("German: someone else's", who == "Akasha", who)
who = MS:_ParseLootMessage("Ihr erhaltet Beute: " .. link(12345, "Robe") .. ".")
check("German: yours", who == MS:UnitPlayerName("player"), who)

-- ── No run: chat isn't read ────────────────────────────────────────────────
zone({ "Orgrimmar", "none", 0 })
if MS.currentRun and MS.currentRun._suspended then MS:ClosePausedRun() end
M.now = M.now + 600
local before = #loot("Akasha")
M.Fire("CHAT_MSG_LOOT", "Akasha erhält Beute: " .. link(44444, "Cloak") .. "."); M.RunTimers(1)
check("no run: nothing recorded", MS.currentRun == nil and #loot("Akasha") == before)

local function errorsPrinted() for _, p in ipairs(M.printed) do if p:find("rror") then return p end end end
check("no errors", not errorsPrinted(), errorsPrinted())
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR, passes, fails))
os.exit(fails == 0 and 0 or 1)

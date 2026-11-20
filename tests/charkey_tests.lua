-- usage: lua5.1 charkey_tests.lua DIR TOC
-- Your character's account-wide key is name@realm. WoW Forever can give an
-- empty realm early in a login: that made a second you ("Name@") in the
-- Stats page's character list. Now no key until the realm's known, and the
-- "Name@" left by an earlier version is folded into the real one.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
local realm = ""                                   -- not known yet
GetRealmName = function() return realm end
M.LoadTOC(arg[1], arg[2])
GetRealmName = function() return realm end
-- WoW Forever: UnitFullName's second half is your surname, not a realm.
UnitFullName = function() return "Jay", "Breezy" end
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end

-- What an earlier version left: the real you (20 runs) and "Name@" (17 of
-- the same runs, and one only it had).
local me = MS:UnitPlayerName("player")
local _, cls = UnitClass("player")
local function Run(at, dungeon) return { at = at, dungeon = dungeon, dur = 900, cleared = true } end
local full, blank = {}, {}
for i = 1, 20 do full[i] = Run(1000 + i * 100, "Ragefire Chasm") end
for i = 4, 20 do blank[#blank + 1] = Run(1000 + i * 100, "Ragefire Chasm") end
blank[#blank + 1] = Run(9999, "Wailing Caverns")
MythicScoreboardAccountDB = { chars = {
    [me .. "@Forever"] = { name = me, realm = "Forever", class = cls, archive = { v = MS.ARCHIVE_VERSION, runs = full, seeded = true } },
    [me .. "@"] = { name = me, realm = "", class = cls, archive = { v = MS.ARCHIVE_VERSION, runs = blank, seeded = true } },
    ["Alt@Forever"] = { name = "Alt", realm = "Forever", class = "MAGE", archive = { v = MS.ARCHIVE_VERSION, runs = { Run(500, "The Stockade") } } },
} }
-- WoW Forever (two-part names), 2.17.1 for a moment: the surname taken for the realm.
local forever = MS.Flavor.twoPartNames
if forever then
    MythicScoreboardAccountDB.chars[me .. "@Breezy"] = { name = me, realm = "Breezy", class = cls,
        archive = { v = MS.ARCHIVE_VERSION, runs = { Run(8888, "Gnomeregan") } } }
end

-- Logged in, and the game won't say the realm (all session): the key you
-- were saved under before, and "Name@" folded into it.
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(2)
MS:SyncAccountStats()
check("no realm: the key you were saved under", MS:CharKey() == me .. "@Forever", MS:CharKey())
check("the second you is gone", MythicScoreboardAccountDB.chars[me .. "@"] == nil)
check("the surname one too", MythicScoreboardAccountDB.chars[me .. "@Breezy"] == nil)
local runs = MythicScoreboardAccountDB.chars[me .. "@Forever"].archive.runs
check("their runs joined, each once", #runs == (forever and 22 or 21), #runs)
check("oldest first", runs[1].at < runs[#runs].at)
local kept = {}
for _, e in ipairs(runs) do kept[e.dungeon] = true end
check("the runs only they had, kept", kept["Wailing Caverns"] and (not forever or kept["Gnomeregan"]))
local list = MS:StatsCharacters()
local mine, you = 0, false
for _, c in ipairs(list) do if c.name == me then mine = mine + 1; you = c.me end end
check("you once in the list", mine == 1, mine)
check("marked as you", you)
check("other characters untouched", MythicScoreboardAccountDB.chars["Alt@Forever"] ~= nil and #list == 2, #list)

-- The realm known: the same key.
realm = "Forever"
check("realm known: the same key", MS._CharKeyNow() == me .. "@Forever", MS._CharKeyNow())

io.stdout:write(("charkey_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

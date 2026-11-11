-- usage: lua5.1 util_tests.lua DIR TOC
-- Core/Util.lua: format strings as patterns, readable values.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local F, Match = MS.FormatPattern, MS.MatchFormat

local fp = F("%s receives loot: %s.")
local who, item = Match("Jay receives loot: [Sword].", fp)
check("two strings, in order", who == "Jay" and item == "[Sword]", tostring(who) .. "/" .. tostring(item))
check("the whole line only", Match("Jay receives loot: [Sword]. Extra", fp) == nil)

fp = F("%2$s erhält Beute: %1$s.")
local a1, a2 = Match("[Schwert] erhält Beute: Jay.", F("%2$s erhält Beute: %1$s."))
check("swapped arguments come back in argument order", a1 == "Jay" and a2 == "[Schwert]", tostring(a1) .. "/" .. tostring(a2))

fp = F("Your %s reputation has increased by %d.", "start")
local fac, amt = Match("Your Ironforge reputation has increased by 25. (+5 bonus)", fp)
check("start: a string and a number", fac == "Ironforge" and amt == "25", tostring(fac) .. "/" .. tostring(amt))

local f2, a3 = Match("Reputation with Cenarion increased by 12.5 (bonus).",
    F("Reputation with %s increased by %.1f (bonus).", "start"))
check("a decimal value", f2 == "Cenarion" and a3 == "12.5", tostring(f2) .. "/" .. tostring(a3))

fp = F("%s dies, you gain %d experience. (+%d exp Rested bonus)", "prefix")
check("prefix: up to the first number", Match("Kobold Miner dies, you gain 45 experience.", fp) == "Kobold Miner")

check("magic characters are literal", Match("100% (done) [ok]", F("%d%% (done) [ok]")) == "100")
check("a dungeon reset line", Match("The Deadmines has been reset.", F("%s has been reset.")) == "The Deadmines")
check("not a string", F(nil) == nil and Match(nil, F("%s")) == nil)

check("ReadableNumber", MS.ReadableNumber("12") == 12 and MS.ReadableNumber(nil) == nil)
check("Readable", MS.Readable("") == nil and MS.Readable("x") == "x" and MS.Readable(5) == nil)
check("Round", MS.Round(2.5) == 3 and MS.Round("x") == 0)

io.stdout:write(("util_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

-- usage: lua5.1 portraits_builtin_tests.lua DIR TOC
-- WoW Forever: the built-in boss list (Data/ForeverBossNpcs.lua) draws a
-- boss's portrait before anyone on the account has met it, by its name or by
-- any of its dungeon's aka names; a model learned in play wins over it.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if MS.FLAVOR ~= "forever" then
    io.stdout:write("portraits_builtin_tests: 0 passed, 0 failed (retail: the journal)\n")
    os.exit(0)
end
M.Fire("ADDON_LOADED", "MythicScoreboard")

-- Every entry: a name, an npc ID and a model.
local n, bad = 0, {}
for name, ids in pairs(MS.ForeverData.BOSSES) do
    n = n + 1
    if type(name) ~= "string" or type(ids.npc) ~= "number" or type(ids.display) ~= "number" then bad[#bad + 1] = tostring(name) end
end
check("the list: every boss has an npc and a model", #bad == 0, table.concat(bad, ", "))
check("the list: not empty", n > 250, n)

-- Every boss of every dungeon is in the list, but the two not known yet.
local missing = {}
for _, d in pairs(MS.ForeverData.DUNGEONS) do
    for _, b in ipairs(d.bosses or {}) do
        local name = type(b) == "table" and (b.name or b[1]) or b
        local aka = type(b) == "table" and b.aka or nil
        if not MS:ShippedBossDisplay(name, aka) then missing[#missing + 1] = name end
    end
end
table.sort(missing)
check("every dungeon boss has a model, but the two unknown",
    table.concat(missing, ", ") == "Lordaeron Captain, Magmatus", table.concat(missing, ", "))

-- Drawn straight away, before anyone's met it.
local dm = MS.ForeverData.BOSSES["Deathless Marrow"]
local kind, id = MS:BossPortrait({ name = "Deathless Marrow" })
check("built in: drawn before it's met", kind == "display" and id == dm.display, tostring(kind) .. " " .. tostring(id))
check("built in: its creature known", MS:BossNpcID("Deathless Marrow") == dm.npc)

-- By an aka name: the game calls the fight "Deathless Guardians".
check("by an aka name", MS:ShippedBossDisplay("Deathless Guardians", { "Deathless Marrow" }) == dm.display)
check("an unknown name: nothing", MS:ShippedBossDisplay("Nobody At All") == nil)
check("a name with quotes", MS:ShippedBossDisplay('"Pyromancer" Braxton') ~= nil)

-- A model learned in play wins over the built-in one.
MythicScoreboardPortraitsDB.display["deathless marrow"] = 4242
MythicScoreboardPortraitsDB.display[MS.BossKey and MS.BossKey("Deathless Marrow") or "deathlessmarrow"] = 4242
local _, learned = MS:BossPortrait({ name = "Deathless Marrow" })
check("learned in play wins", learned == 4242, learned)

io.stdout:write(("portraits_builtin_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

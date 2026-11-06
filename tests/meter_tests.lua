-- usage: lua5.1 meter_tests.lua DIR TOC
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, " ", tostring(detail or ""), "\n") end
end
local function S(v) return { __secret = true, v = v } end
local function src(name, guid, amt, isLocal, cls) return { name = name, sourceGUID = guid, totalAmount = amt, isLocalPlayer = isLocal, classFilename = cls, amountPerSecond = 0 } end
local function fresh()
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    MS.currentRun = nil; MS.inDungeon = false; M.meter = {}
    M.instance = { "Ragefire Chasm", "party", 1 }
    MS:StartRun("Ragefire Chasm", 0, 1, "Normal")
    M.RunTimers(2)
    return MS.currentRun
end
local function meter(list, dur, extra)
    M.meter = { [0] = { duration = dur or 100, combatSources = list }, [2] = { duration = dur or 100, combatSources = {} },
                [5] = { combatSources = {} }, [6] = { combatSources = {} }, [7] = extra or { combatSources = {} },
                [8] = { combatSources = {} }, [9] = { combatSources = {} } }
end
local function P(n) return MS:PlayerByName(n) end
local me = MS.FLAVOR == "forever" and "Jay-Breezy" or "Jay"

-- 1. First source's name hidden: everyone still gets numbers (2.4.1 skipped the whole read).
local run = fresh()
meter({ src(S("Akasha"), "Player-1-BBB", 2000, false, "MAGE"), src("Jay-Breezy", "Player-1-AAA", 1000, true, "SHAMAN") })
MS:SnapshotFromDamageMeter()
check("hidden first name: Akasha read", P("Akasha").damageDone == 2000, P("Akasha").damageDone)
check("hidden first name: self read", P(me).damageDone == 1000, P(me).damageDone)

-- 2. Hidden name and hidden GUID together: skipped, nothing stored, no error.
run = fresh()
meter({ src(S("Akasha"), S("Player-1-BBB"), 2000, false, "MAGE") })
MS:SnapshotFromDamageMeter()
check("fully hidden source skipped", P("Akasha").damageDone == 0)

-- 3. Numbers hidden: snapshot does nothing at all.
run = fresh()
meter({ src("Akasha", "Player-1-BBB", S(2000), false, "MAGE") })
MS:SnapshotFromDamageMeter()
check("hidden totals skipped", P("Akasha").damageDone == 0)
check("IsMeterHidden true", MS:IsMeterHidden() == true)

-- 4. Two-part names in every form match the same player.
run = fresh()
for _, form in ipairs({ "Jay-Breezy", "Jay Breezy", "Jay-Breezy-Forever" }) do
    meter({ src(form, nil, 777, false, "SHAMAN") })
    MS:SnapshotFromDamageMeter()
    if MS.FLAVOR == "forever" then check("name form " .. form, P("Jay Breezy").damageDone == 777, P("Jay Breezy").damageDone) end
end

-- 5. Unmatched player is never credited to the hunter; their pet is.
run = fresh()
meter({}, 100, { duration = 100, combatSources = {
    src("Stranger", "Player-9-ZZZ", 5000, false, "ROGUE"),
    src("Wolf", "Pet-0-1-99", 300, false, nil),
    src("Some Mob", "Creature-0-1-1-1-1-777", 999, false, nil),
} })
MS:SnapshotFromDamageMeter()
check("pet credited to Hizazi", P("Hizazi").damageTaken == 300, P("Hizazi").damageTaken)
check("stranger not credited", P("Hizazi").damageTaken < 5000)
-- Pet share must not pile up over polls.
MS:SnapshotFromDamageMeter(); MS:SnapshotFromDamageMeter()
check("pet share stable over polls", P("Hizazi").damageTaken == 300, P("Hizazi").damageTaken)

-- 6. Pet owner from tooltip text when the pet isn't a visible unit.
run = fresh()
M.roster.party4pet = nil; MS._petGUIDToOwner = {}; MS._petNameToOwner = {}
C_TooltipInfo.GetHyperlink = function(l) if l == "unit:Pet-0-1-55" then return { lines = { {}, { leftText = "Akasha's Pet" } } } end end
meter({}, 100, { duration = 100, combatSources = { src("Imp", "Pet-0-1-55", 40, false, nil) } })
MS:SnapshotFromDamageMeter()
check("tooltip owner", P("Akasha").damageTaken == 40, P("Akasha").damageTaken)
C_TooltipInfo.GetHyperlink = function() return nil end
M.roster.party4pet = { name = "Wolf", guid = "Pet-0-1-99", npc = true }

-- 7. Meter restarts mid-run (any time, not only after a release): totals carry.
run = fresh()
meter({ src("Akasha", "Player-1-BBB", 2000, false, "MAGE") }, 100); MS:SnapshotFromDamageMeter()
meter({ src("Akasha", "Player-1-BBB", 2500, false, "MAGE") }, 130); MS:SnapshotFromDamageMeter()
check("no carry while growing", P("Akasha").damageDone == 2500, P("Akasha").damageDone)
meter({ src("Akasha", "Player-1-BBB", 100, false, "MAGE") }, 10); MS:SnapshotFromDamageMeter()
check("carry after restart", P("Akasha").damageDone == 2600, P("Akasha").damageDone)
meter({ src("Akasha", "Player-1-BBB", 400, false, "MAGE") }, 40); MS:SnapshotFromDamageMeter()
check("carry keeps adding", P("Akasha").damageDone == 2900, P("Akasha").damageDone)
check("dps over whole run", math.abs(P("Akasha").dps - 2900 / 170) < 0.01, P("Akasha").dps)

-- 8. Player lookups agree.
run = fresh()
check("unit lookup", MS:PlayerForUnit("party1") == P("Akasha"))
check("guid lookup", MS:PlayerByGUID("Player-1-BBB") == P("Akasha"))
check("self by unit", MS:PlayerForUnit("player") == P(me))

-- 9. Forever: full names from UnitName's surname, shown with a space.
if MS.FLAVOR == "forever" then
    run = fresh()
    local keys = {}
    for k in pairs(run.players) do keys[#keys + 1] = k end
    table.sort(keys)
    check("stored with surnames", table.concat(keys, ",") == "Akasha-Dawnfire,Girthy-Stone,Hizazi-Bow,Jay-Breezy,Skip", table.concat(keys, ","))
    check("shown with a space", MS.DisplayName(MS:PlayerForUnit("player").name) == "Jay Breezy")
    check("first name alone finds player", MS:PlayerByName("Jay") == MS:PlayerByName("Jay Breezy"))
    check("surname not taken for a realm", MS.ShortName("Jay-Breezy") == "Jay-Breezy")
    -- Two players called Jay: a bare "Jay" must not guess.
    run.players["Jay-Other"] = MS.NewPlayerStats("Jay-Other", "MAGE", "Player-1-FFF")
    check("ambiguous first name not guessed", MS:PlayerByName("Jay") == nil)
    -- Meter gives only first names, no GUIDs: still matched.
    run.players["Jay-Other"] = nil
    meter({ src("Akasha", nil, 321, false, "MAGE") })
    MS:SnapshotFromDamageMeter()
    check("meter first name only", MS:PlayerByName("Akasha Dawnfire").damageDone == 321, MS:PlayerByName("Akasha Dawnfire").damageDone)
end

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

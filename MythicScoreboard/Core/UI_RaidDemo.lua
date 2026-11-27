local MS = _G["MythicScoreboard"]
local UI = MS.UI
local _fmt = string.format

-- ── Sample raids ───────────────────────────────────────────────────────────
-- The raid views (UI_Raid.lua, the scoreboard; UI_RaidFrame.lua, the in-run
-- frame) shown with made-up raids until real raids are tracked: /sb raid 10,
-- 20 or 40. One sample per size, from WoW Forever's launch raids. The bosses
-- of Barrow Deeps and Hyjal Summit aren't known yet: "Boss 1", "Boss 2"...
--
-- A sample: { key, name, size, bosses = total, killed, time (seconds),
-- wipes, pulls = { {s, e = its start and end in seconds, kill, boss} }, players =
-- { {name, class, role, deaths, taken, damage, healing, kicks, dispels} },
-- loot = { {icon, name, q (quality), ilvl, who, from (boss number) or boss} },
-- frame = what the in-run frame shows (UI_RaidFrame.lua) }. The items are
-- made up too.

local function I(icon, name, q, ilvl, who, from)
    return { icon = icon, name = name, q = q, ilvl = ilvl, who = who,
             from = type(from) == "number" and from or nil, boss = type(from) == "string" and from or nil }
end

local function P(name, class, role, deaths, taken, damage, healing, kicks, dispels)
    return { name = name, class = class, role = role, deaths = deaths, taken = taken, damage = damage,
             healing = healing, kicks = kicks, dispels = dispels }
end

-- The bosses, from the game client's own data (/sb raid dump, client
-- 1.60.1): the raids' "Conqueror of" achievements name each boss, with its
-- NPC ID (kill-creature criteria) and, for some, its encounter ID (the one
-- ENCOUNTER_START and ENCOUNTER_END report). Barrow Deeps has all eight
-- encounter IDs; Hyjal Summit six of thirteen (the others are likely
-- 3341, 3343, 3344, 3346 and 3349-3351, but which is whose isn't known).
-- Order: the achievement's for Barrow Deeps (Sonya Darkhallow last); for
-- Hyjal Summit, the wiki's (Nythus the Dreambound last).
UI.RAID_ENCOUNTERS = {
    barrow = {
        { name = "Chillhowl",                npc = 259867, encounter = 3491 },
        { name = "Elder Tangleclaw",         npc = 259904, encounter = 3486 },
        { name = "Khalith the Dreadspinner", npc = 259902, encounter = 3489 },
        { name = "Well of Sorrow",           npc = 259866, encounter = 3483 },
        { name = "Amethrax",                 npc = 259907, encounter = 3484 },
        { name = "Del'lynar Songwood",       npc = 259911, encounter = 3487 },
        { name = "Ravus and Darlissa",       npc = 259905, encounter = 3485 },
        { name = "Sonya Darkhallow",         npc = 259912, encounter = 3490 },
    },
    hyjal = {
        { name = "Bandalar",              npc = 249790 },
        { name = "Time-Lost Battalion",                 encounter = 3339 },
        { name = "Old Gloomlurker",       npc = 250070 },
        { name = "Kathris the Haunted",   npc = 250077 },
        { name = "Elder Minderel",        npc = 253861, encounter = 3342 },
        { name = "Council of Thorns",     npc = 250082, encounter = 3347 },
        { name = "The Wild King",         npc = 250079 },
        { name = "Ancient of Decay",      npc = 250076 },
        { name = "Sylvestris Dusksong",   npc = 257638, encounter = 3340 },
        { name = "Gharalis the Abyssal",  npc = 250075, encounter = 3345 },
        { name = "Anara Chillwind",       npc = 249787 },
        { name = "Tracker Stillwind",     npc = 250074 },
        { name = "Nythus the Dreambound", npc = 250078, encounter = 3348 },
    },
    onyxia = {
        { name = "Onyxia", npc = 10184 },   -- instance ID 249; model 8570
    },
}
local function Names(list) local t = {} for i, e in ipairs(list) do t[i] = e.name end return t end
-- Onyxia's model is known (the classic one), so her portrait is drawn
-- straight away; the new raids' bosses are learned from the game.
if MS.ForeverData and MS.ForeverData.BOSSES and not MS.ForeverData.BOSSES["Onyxia"] then
    MS.ForeverData.BOSSES["Onyxia"] = { npc = 10184, display = 8570 }
end
local BARROW_BOSSES = Names(UI.RAID_ENCOUNTERS.barrow)
local HYJAL_BOSSES = Names(UI.RAID_ENCOUNTERS.hyjal)
UI.RAID_BOSSES = { barrow = BARROW_BOSSES, hyjal = HYJAL_BOSSES }

local BARROW = {
    key = "barrow", name = "Barrow Deeps", size = 10, bosses = 8, killed = 4, time = 58 * 60 + 12, wipes = 2,
    bossNames = BARROW_BOSSES,
    pulls = {
        { s = 242, e = 372, kill = true, boss = 1 }, { s = 650, e = 810, kill = false },
        { s = 1000, e = 1180, kill = true, boss = 2 }, { s = 1715, e = 1865, kill = true, boss = 3 },
        { s = 2465, e = 2650, kill = false }, { s = 2927, e = 3140, kill = true, boss = 4 },
    },
    players = {
        P("Kaelthor Oakshield", "ROGUE", "DAMAGER", 3, 128e3, 342e3, 0, 7, 0),
        P("Ysmera Tallgrass", "MAGE", "DAMAGER", 1, 96e3, 318e3, 0, 4, 2),
        P("Brannick Pinecrest", "WARRIOR", "DAMAGER", 0, 141e3, 301e3, 0, 6, 0),
        P("Vexalia Elmstead", "WARLOCK", "DAMAGER", 2, 88e3, 287e3, 0, 0, 0),
        P("Torvald Nightbloom", "HUNTER", "DAMAGER", 1, 74e3, 266e3, 0, 3, 0),
        P("Dunmore Kettlewick", "WARRIOR", "TANK", 1, 612e3, 198e3, 0, 9, 0),
        P("Saelith Juniper", "DRUID", "DAMAGER", 0, 81e3, 187e3, 22e3, 2, 6),
        P("Orrin Oldbridge", "PRIEST", "HEALER", 0, 46e3, 38e3, 612e3, 0, 19),
        P("Meliora Brightwater", "PALADIN", "HEALER", 1, 59e3, 41e3, 548e3, 0, 12),
        P("Thandrel Frostwhisper", "SHAMAN", "HEALER", 0, 51e3, 32e3, 441e3, 0, 5),
    },
    loot = {
        I("INV_Helmet_03", "Warden's Hood", 4, 66, "Dunmore Kettlewick", 1),
        I("INV_Jewelry_Ring_03", "Band of the Barrow", 3, 63, "Meliora Brightwater", 1),
        I("INV_Sword_04", "Jailer's Edge", 4, 66, "Kaelthor Oakshield", 2),
        I("INV_Misc_Cape_06", "Shroud of the Deep", 3, 63, "Brannick Pinecrest", 3),
        I("INV_Chest_Chain_05", "Wardenmail Hauberk", 4, 66, "Torvald Nightbloom", 4),
        I("INV_Staff_08", "Staff of Binding", 4, 66, "Orrin Oldbridge", 4),
    },
    -- In-run: a fight in progress.
    frame = { mode = "fight", clock = 41 * 60 + 20, killedNow = 3, wipes = 1,
              fightBoss = 4, fightPull = 2, fightTime = 161, health = 63, lastWipeAt = 41,
              alive = 7, deaths = 5, gold = "14g 32s", resetDays = 4,
              pullDeaths = { { "Vexalia Elmstead", "1:12" }, { "Torvald Nightbloom", "2:05" }, { "Kaelthor Oakshield", "2:48" } },
              list = { { boss = 1, t = "6:12" }, { boss = 2, t = "19:40" }, { boss = 3, t = "31:05" },
                       { boss = 4, fighting = true }, { boss = 5 }, { boss = 6 }, { boss = 7 }, { boss = 8 } } },
}

local HYJAL = {
    key = "hyjal", name = "Hyjal Summit", size = 20, bosses = 13, killed = 5, time = 74 * 60 + 2, wipes = 3,
    bossNames = HYJAL_BOSSES,
    pulls = {
        { s = 435, e = 570, kill = true, boss = 1 }, { s = 920, e = 1090, kill = true, boss = 2 },
        { s = 1340, e = 1480, kill = false }, { s = 1715, e = 1905, kill = true, boss = 3 },
        { s = 2000, e = 2110, kill = false }, { s = 2190, e = 2280, kill = false },
        { s = 2330, e = 2490, kill = true, boss = 7 }, { s = 3245, e = 3490, kill = true, boss = 8 },
    },
    players = {
        P("Dunmore Kettlewick", "WARRIOR", "TANK", 1, 1.42e6, 412e3, 0, 14, 0),
        P("Halvard Moonbrook", "DRUID", "TANK", 0, 1.18e6, 356e3, 41e3, 4, 3),
        P("Orrin Oldbridge", "PRIEST", "HEALER", 0, 96e3, 52e3, 1.31e6, 0, 31),
        P("Meliora Brightwater", "PALADIN", "HEALER", 1, 118e3, 61e3, 1.22e6, 0, 24),
        P("Thandrel Frostwhisper", "SHAMAN", "HEALER", 0, 104e3, 48e3, 1.04e6, 2, 9),
        P("Liora Fairwind", "PRIEST", "HEALER", 2, 131e3, 44e3, 0.97e6, 0, 27),
        P("Brisa Willowmere", "DRUID", "HEALER", 0, 88e3, 39e3, 0.91e6, 0, 14),
        P("Kaelthor Oakshield", "ROGUE", "DAMAGER", 2, 214e3, 1.02e6, 0, 11, 0),
        P("Ysmera Tallgrass", "MAGE", "DAMAGER", 1, 162e3, 0.98e6, 0, 6, 4),
        P("Brannick Pinecrest", "WARRIOR", "DAMAGER", 0, 241e3, 0.95e6, 0, 9, 0),
        P("Vexalia Elmstead", "WARLOCK", "DAMAGER", 3, 187e3, 0.93e6, 0, 0, 0),
        P("Corvan Vinewood", "MAGE", "DAMAGER", 1, 149e3, 0.91e6, 0, 5, 3),
        P("Torvald Nightbloom", "HUNTER", "DAMAGER", 1, 132e3, 0.88e6, 0, 0, 0),
        P("Sefira Redfern", "ROGUE", "DAMAGER", 0, 176e3, 0.86e6, 0, 8, 0),
        P("Grimwald Emberfall", "WARLOCK", "DAMAGER", 2, 158e3, 0.84e6, 0, 0, 0),
        P("Elandra Blackthorn", "HUNTER", "DAMAGER", 0, 121e3, 0.81e6, 0, 0, 0),
        P("Fenrick Ivyreach", "WARRIOR", "DAMAGER", 1, 228e3, 0.79e6, 0, 7, 0),
        P("Aubrel Ashvale", "MAGE", "DAMAGER", 0, 141e3, 0.77e6, 0, 3, 2),
        P("Saelith Juniper", "DRUID", "DAMAGER", 0, 139e3, 0.72e6, 22e3, 2, 5),
        P("Mordane Ironbark", "SHAMAN", "DAMAGER", 1, 166e3, 0.69e6, 31e3, 6, 1),
    },
    loot = {
        I("INV_Shield_05", "Bulwark of the World Tree", 4, 71, "Dunmore Kettlewick", 1),
        I("INV_Gauntlets_04", "Grips of the Ancients", 4, 71, "Kaelthor Oakshield", 1),
        I("INV_Jewelry_Ring_15", "Nordrassil Signet", 4, 71, "Orrin Oldbridge", 2),
        I("INV_Boots_05", "Treads of the Summit", 4, 71, "Brannick Pinecrest", 2),
        I("INV_Wand_07", "Wand of Waning Light", 4, 71, "Liora Fairwind", 3),
        I("INV_Bracer_07", "Bindings of the Watch", 4, 71, "Halvard Moonbrook", 7),
        I("INV_Belt_03", "Girdle of the Root", 4, 71, "Ysmera Tallgrass", 7),
        I("INV_Helmet_08", "Crown of the Grove", 4, 71, "Meliora Brightwater", 8),
        I("INV_Misc_Cape_08", "Cloak of Falling Leaves", 4, 71, "Corvan Vinewood", 8),
    },
    -- In-run: between pulls. Kills so far: 1, 2, 3, 7 and 8 (the order is a
    -- guess; the raid lets groups choose their route).
    frame = { mode = "rest", clock = 62 * 60 + 45, killedNow = 5, wipes = 2, alive = 20,
              lastKill = { boss = 8, t = "58:10", pull = 3 }, deaths = 17, gold = "41g 08s", resetDays = 4,
              list = { { folded = 3, list = { { boss = 1, t = "9:30" }, { boss = 2, t = "18:10" }, { boss = 3, t = "31:45" } } },
                       { boss = 7, t = "41:30" }, { boss = 8, t = "58:10" },
                       { boss = 4 }, { boss = 5 }, { boss = 6 },
                       { more = 4, list = { { boss = 9 }, { boss = 10 }, { boss = 11 }, { boss = 12 } } },
                       { boss = 13 } } },
}

-- Onyxia's Lair: 40 players, one boss, three phases.
local ONYXIA_NAMES = { "Kaelthor Oakshield", "Ysmera Tallgrass", "Brannick Pinecrest", "Vexalia Elmstead", "Corvan Vinewood", "Torvald Nightbloom", "Sefira Redfern", "Grimwald Emberfall", "Elandra Blackthorn",
    "Fenrick Ivyreach", "Aubrel Ashvale", "Mordane Ironbark", "Saelith Juniper", "Rhyst Copperpot", "Quillon Stonemantle", "Davena Coldmere", "Osric Westbrook", "Tamsin Stormrook", "Harrow Thornfield", "Iselde Kindleby",
    "Jorund Wildmane", "Pellam Dawnhollow", "Wrenna Longbarrow", "Caddoc Goldleaf", "Nimue Quickwater", "Ulric Underbough", "Berrin Hollowmere", "Calla Northwood", "Edric Ravenhill", "Fiora Proudfoot",
    "Gideon Yarrow", "Hesper Duskwood", "Ivo Silverbrook", "Juno Greycloak", "Kestrel Valebright", "Lorne Mistvale", "Maeve Ambergale", "Nolan Ashford", "Odette Hightower", "Piran Larkspur" }
local ONYXIA_CLASSES = { "ROGUE", "MAGE", "WARRIOR", "WARLOCK", "MAGE", "HUNTER", "ROGUE", "WARLOCK", "HUNTER", "WARRIOR",
    "MAGE", "SHAMAN", "DRUID", "ROGUE", "MAGE", "WARLOCK", "WARRIOR", "HUNTER", "ROGUE", "MAGE",
    "WARRIOR", "HUNTER", "WARLOCK", "WARRIOR", "DRUID", "WARRIOR", "ROGUE", "DRUID", "PALADIN", "SHAMAN",
    "WARRIOR", "PRIEST", "PALADIN", "PRIEST", "DRUID", "PRIEST", "PALADIN", "SHAMAN", "PRIEST", "PRIEST" }
local ONYXIA_DEATHS = { 2, 1, 0, 3, 1, 1, 0, 2, 0, 1, 0, 1, 0, 2, 1, 0, 1, 0, 0, 1,
                        0, 2, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 2, 0, 0, 1 }
local function OnyxiaPlayers()
    local list = {}
    for i, name in ipairs(ONYXIA_NAMES) do
        local tank = (i == 21 or i == 24 or i == 26)
        local healer = i >= 29 and i ~= 31
        local damage = i <= 30 and (2.9e6 - (i - 1) * 72e3 - ((i - 1) % 3) * 9e3) or (420e3 - (i - 31) * 30e3)
        list[i] = P(name, ONYXIA_CLASSES[i], tank and "TANK" or healer and "HEALER" or "DAMAGER", ONYXIA_DEATHS[i],
            tank and (1.1e6 - i * 9e3) or (60e3 + (i * 7919) % 90e3), damage,
            healer and (1.6e6 - (i - 29) * 85e3) or 0, (i * 5) % 7, healer and (6 + i % 9) or 0)
    end
    return list
end

local ONYXIA = {
    key = "onyxia", name = "Onyxia's Lair", size = 40, bosses = 1, killed = 1, time = 38 * 60 + 4, wipes = 2,
    pulls = {
        { s = 240, e = 510, kill = false, pull = 1, phase = 2 }, { s = 840, e = 1330, kill = false, pull = 2, phase = 3 },
        { s = 1800, e = 2270, kill = true, pull = 3, name = "Onyxia" },
    },
    players = OnyxiaPlayers(),
    loot = {
        I("INV_Misc_Head_Dragon_01", "Head of Onyxia", 4, 60, "Dunmore Kettlewick", "Onyxia"),
        I("INV_Sword_39", "Brood Mother's Fang", 4, 74, "Kaelthor Oakshield", "Onyxia"),
        I("INV_Helmet_10", "Dragonscale Crown", 4, 74, "Brannick Pinecrest", "Onyxia"),
        I("INV_Jewelry_Necklace_07", "Pendant of the Black Flight", 4, 74, "Hesper Duskwood", "Onyxia"),
        I("INV_Shoulder_25", "Mantle of the Lair", 4, 74, "Ysmera Tallgrass", "Onyxia"),
        I("INV_Chest_Plate06", "Whelpscale Breastplate", 4, 74, "Ulric Underbough", "Onyxia"),
        I("INV_Misc_Monsterscales_15", "Onyxia Scale", 4, 60, "Fenrick Ivyreach", "Onyxia"),
        I("INV_Gauntlets_10", "Handguards of Deep Flame", 4, 74, "Juno Greycloak", "Onyxia"),
        I("INV_Misc_Bag_10_Black", "Onyxia Hide Bag", 4, 60, "Vexalia Elmstead", "Onyxia"),
    },
    -- In-run: the third pull, in phase 2 (the phase changes at 65% and 40%,
    -- as in the original; Forever's version may differ).
    frame = { mode = "phases", clock = 31 * 60 + 28, pull = 3, wipes = 2, phase = 2, fightTime = 382,
              health = 52, nextPhaseAt = 40, alive = 36, pullDeaths = 4, deaths = 31, resetDays = 4,
              phases = { 125, 257 },
              tries = { { pull = 1, phase = 2, at = 58 }, { pull = 2, phase = 3, at = 21 }, { pull = 3, fighting = true } } },
}

-- What each player's numbers are made of, for the tooltips: damage and
-- healing by spell, dispels by type, and their deaths. Spell names and
-- splits are a plausible sample per class (and role), nothing measured.
local DAMAGE_SPELLS = {
    WARRIOR = { { "Bloodthirst", 0.31 }, { "Heroic Strike", 0.27 }, { "Auto Attack", 0.24 }, { "Whirlwind", 0.18 } },
    WARRIOR_TANK = { { "Shield Slam", 0.34 }, { "Revenge", 0.26 }, { "Heroic Strike", 0.22 }, { "Auto Attack", 0.18 } },
    ROGUE = { { "Sinister Strike", 0.38 }, { "Auto Attack", 0.32 }, { "Eviscerate", 0.22 }, { "Rupture", 0.08 } },
    MAGE = { { "Frostbolt", 0.62 }, { "Arcane Missiles", 0.18 }, { "Fire Blast", 0.12 }, { "Cone of Cold", 0.08 } },
    WARLOCK = { { "Shadow Bolt", 0.58 }, { "Corruption", 0.17 }, { "Curse of Agony", 0.14 }, { "Immolate", 0.11 } },
    HUNTER = { { "Auto Shot", 0.41 }, { "Multi-Shot", 0.22 }, { "Arcane Shot", 0.19 }, { "Serpent Sting", 0.18 } },
    DRUID = { { "Shred", 0.36 }, { "Auto Attack", 0.30 }, { "Ferocious Bite", 0.22 }, { "Rip", 0.12 } },
    DRUID_TANK = { { "Maul", 0.41 }, { "Swipe", 0.33 }, { "Auto Attack", 0.26 } },
    SHAMAN = { { "Lightning Bolt", 0.48 }, { "Chain Lightning", 0.24 }, { "Stormstrike", 0.16 }, { "Flame Shock", 0.12 } },
    PRIEST = { { "Smite", 0.50 }, { "Holy Fire", 0.30 }, { "Shadow Word: Pain", 0.20 } },
    PALADIN = { { "Seal of Righteousness", 0.45 }, { "Auto Attack", 0.35 }, { "Consecration", 0.20 } },
}
local HEAL_SPELLS = {
    PRIEST = { { "Greater Heal", 0.44 }, { "Prayer of Healing", 0.27 }, { "Renew", 0.18 }, { "Power Word: Shield", 0.11 } },
    PALADIN = { { "Flash of Light", 0.52 }, { "Holy Light", 0.38 }, { "Holy Shock", 0.10 } },
    SHAMAN = { { "Chain Heal", 0.55 }, { "Healing Wave", 0.25 }, { "Lesser Healing Wave", 0.20 } },
    DRUID = { { "Rejuvenation", 0.34 }, { "Regrowth", 0.28 }, { "Healing Touch", 0.26 }, { "Swiftmend", 0.12 } },
}
local DISPEL_TYPES = {
    PRIEST = { { "Magic", 0.75 }, { "Disease", 0.25 } }, PALADIN = { { "Magic", 0.6 }, { "Poison", 0.2 }, { "Disease", 0.2 } },
    SHAMAN = { { "Poison", 0.6 }, { "Disease", 0.4 } }, DRUID = { { "Curse", 0.6 }, { "Poison", 0.4 } },
    MAGE = { { "Curse", 1 } },
}
local KILLERS = { "Melee", "Shadow Cleave", "Fireball Volley", "Crushing Blow", "Flame Wave" }
local ONYXIA_KILLERS = { "Flame Breath", "Tail Sweep", "Deep Breath", "Fireball", "Onyxian Whelp" }

local function Split(total, list)
    local out, left = {}, total
    for i, e in ipairs(list) do
        local n = i == #list and left or math.floor(total * e[2] + 0.5)
        left = left - n
        out[i] = { name = e[1], amount = n }
    end
    return out
end

local function Breakdown(r)
    local killers = r.size == 40 and ONYXIA_KILLERS or KILLERS
    for i, p in ipairs(r.players) do
        local dmg = p.role == "TANK" and DAMAGE_SPELLS[p.class .. "_TANK"] or DAMAGE_SPELLS[p.class]
        p.spells = (p.damage or 0) > 0 and dmg and Split(p.damage, dmg) or {}
        p.heals = (p.healing or 0) > 0 and HEAL_SPELLS[p.class] and Split(p.healing, HEAL_SPELLS[p.class]) or {}
        p.dispelTypes = (p.dispels or 0) > 0 and Split(p.dispels, DISPEL_TYPES[p.class] or { { "Magic", 1 } }) or {}
        p.deathLog = {}
        for d = 1, p.deaths or 0 do
            local at = math.floor(r.time * ((i * 0.137 + d * 0.29) % 0.9 + 0.05))
            p.deathLog[d] = { t = at, by = killers[(i + d) % #killers + 1] }
        end
        table.sort(p.deathLog, function(a, b) return a.t < b.t end)
    end
end
Breakdown(BARROW); Breakdown(HYJAL); Breakdown(ONYXIA)

-- Bosses by name wherever the samples say "boss = n".
local function NameBosses(r)
    local N = r.bossNames
    if not N then return end
    for _, p in ipairs(r.pulls) do if p.boss then p.name = p.name or N[p.boss] end end
    for _, e in ipairs(r.loot or {}) do if e.from then e.boss, e.from = N[e.from], nil end end
end
NameBosses(BARROW); NameBosses(HYJAL)

-- Each pull's place along the run, and a kill's time.
local function Clock(sec) return _fmt("%d:%02d", math.floor(sec / 60), sec % 60) end
for _, r in ipairs({ BARROW, HYJAL, ONYXIA }) do
    for _, p in ipairs(r.pulls) do
        p.at = p.e / r.time
        if p.kill then p.t = Clock(p.e) end
    end
end

local BY_SIZE = { [10] = BARROW, [20] = HYJAL, [40] = ONYXIA }
-- The saved raids, newest first (the samples, until raids are tracked).
function UI.RaidHistory() return { BARROW, HYJAL, ONYXIA } end
local BY_KEY = { barrow = BARROW, hyjal = HYJAL, onyxia = ONYXIA }

-- The sample for "10", "20", "40" or a raid's name (or the start of it).
function UI.RaidDemo(arg)
    arg = (arg or ""):lower()
    local n = tonumber(arg)
    if n then return BY_SIZE[n] end
    if arg == "" then return nil end
    for key, r in pairs(BY_KEY) do
        if key:find(arg, 1, true) == 1 or r.name:lower():find(arg, 1, true) == 1 then return r end
    end
end

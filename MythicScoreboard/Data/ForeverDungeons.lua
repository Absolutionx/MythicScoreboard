-- WoW Forever dungeons: names, level ranges and bosses. Data only; the
-- rules that use it are in Core/Forever.lua. Loaded only by
-- MythicScoreboard_Forever.toc.

local MS = _G["MythicScoreboard"]
local D = {}
MS.ForeverData = D

-- ── Dungeon data ────────────────────────────────────────────────────────
-- levels   : recommended level range
-- final    : the boss whose death means the dungeon is done
-- instance : the instance's own name, when it holds several wings and the
--            key isn't "<instance>: <wing>" (Blackrock Spire's two halves)
-- bosses : in rough kill order. A plain string is a regular boss. A table can
--          mark  rare = true    (rare spawn, never required)
--                summon = true  (summoned / optional event, never required)
--                aka = {...}    (other names the game may use for it)
-- Dungeons with an empty boss list are announced but not yet documented.

D.DUNGEONS = {
    ["Ragefire Chasm"] = { levels = {13, 18}, final = "Bazzalan", bosses = {
        "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan",
    }},
    ["Hall of Thanes"] = { levels = {13, 20}, final = "Durgen Dirgehammer", bosses = {
        "Faldrim Anvilmar", { "Magmatus", aka = { "Infurnus" } }, "Plunder", "Durgen Dirgehammer",
    }},
    ["Ruins of Lordaeron"] = { levels = {15, 22}, final = "Viktor the Vile", bosses = {
        { "The Baron", aka = { "The Butcher" } }, "Witherfang", "The Abandoned", "Bjork",
        "Rath'mael", "Viktor the Vile", { "Lordaeron Captain", rare = true },
    }},
    ["Wailing Caverns"] = { levels = {15, 24}, final = "Mutanus the Devourer", bosses = {
        "Lord Cobrahn", "Lady Anacondra", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis",
        "Verdan the Everliving", "Mutanus the Devourer", { "Deviate Faerie Dragon", rare = true },
    }},
    ["The Deadmines"] = { levels = {17, 26}, final = "Edwin VanCleef", bosses = {
        "Rhahk'Zor", { "Miner Johnson", rare = true }, "Sneed's Shredder", "Sneed", "Gilnid",
        "Mr. Smite", "Captain Greenskin", "Edwin VanCleef", "Cookie",
    }},
    ["Shadowfang Keep"] = { levels = {20, 30}, final = "Archmage Arugal", bosses = {
        "Rethilgore", { "Fel Steed / Shadow Charger", aka = { "Fel Steed", "Shadow Charger" } },
        "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher",
        { "Deathsworn Captain", rare = true }, "Arugal's Voidwalker", "Fenrus the Devourer",
        "Wolf Master Nandos", "Archmage Arugal",
    }},
    ["Blackfathom Deeps"] = { levels = {24, 32}, final = "Aku'mai", bosses = {
        "Ghamoo-ra", "Lady Sarevess", { "Gelihast", aka = { "Geilhast" } },
        { "Lorgus Jett", rare = true },                -- doesn't always spawn
        "Old Serra'kis", "Twilight Lord Kelris", "Aku'mai",
    }},
    ["The Stockade"] = { levels = {24, 32}, final = "Bazil Thredd", bosses = {
        "Targorr the Dread", "Kam Deepfury", "Hamhock", "Dextren Ward", "Bazil Thredd",
        { "Bruegal Ironknuckle", rare = true },
    }},
    ["Excavation Site: Wetlands"] = { levels = {26, 33}, final = "Relic Guardian", bosses = {
        "Saltspine", "Shadetooth", "Relic Guardian",
    }},
    ["City of Dalaran"] = { levels = {28, 33}, final = "Shade of the Archmage", bosses = {
        "Atrexis the Grave Knight", "Arcane Anomaly", "Fel Ancient", "Unstable Sentinel",
        "Mana Devourer", { "Arcanic Enigma", aka = { "Mana Elemental" } },
        { "Lyn the Ignored", summon = true }, "Shade of the Archmage",
    }},
    ["Gnomeregan"] = { levels = {29, 38}, final = "Mekgineer Thermaplugg", bosses = {
        "Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60",
        { "Dark Iron Ambassador", rare = true }, "Mekgineer Thermaplugg",
    }},
    ["Razorfen Kraul"] = { levels = {29, 38}, final = "Charlga Razorflank", bosses = {
        "Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk",
        "Agathelos the Raging", { "Blind Hunter", rare = true }, { "Earthcaller Halmgar", rare = true },
        "Charlga Razorflank",
    }},
    ["Scarlet Monastery: Graveyard"] = { levels = {30, 38}, final = "Bloodmage Thalnos", bosses = {
        "Interrogator Vishas", { "Azshir the Sleepless", rare = true }, { "Fallen Champion", rare = true },
        { "Ironspine", rare = true }, "Bloodmage Thalnos",
    }},
    ["Scarlet Monastery: Library"] = { levels = {33, 41}, final = "Arcanist Doan", bosses = {
        "Houndmaster Loksey", "Arcanist Doan",
    }},
    ["Scarlet Monastery: Armory"] = { levels = {34, 42}, final = "Herod", bosses = {
        { "Herod", aka = { "Herod, the Scarlet Champion" } },
    }},
    ["Scarlet Monastery: Cathedral"] = { levels = {36, 45}, final = "High Inquisitor Whitemane", bosses = {
        { "High Inquisitor Fairbanks", aka = { "Fairbanks" } },
        { "Scarlet Commander Mograine", aka = { "Mograine" } },
        { "High Inquisitor Whitemane", aka = { "Whitemane" } },
    }},
    ["Razorfen Downs"] = { levels = {37, 46}, final = "Amnennar the Coldbringer", bosses = {
        "Tuten'kash", "Mordresh Fire Eye", "Glutton", { "Ragglesnout", rare = true },
        { "Plaguemaw the Rotting", rare = true, aka = { "Plaguemaw" } },
        { "Amnennar the Coldbringer", aka = { "Amnennar" } },
    }},
    ["Uldaman"] = { levels = {38, 48}, final = "Archaedas", bosses = {
        "Revelosh", { "The Lost Dwarves", aka = { "Baelog", "Eric \"The Swift\"", "Olaf" } },
        "Ironaya", "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas",
    }},
    ["Zul'Farrak"] = { levels = {43, 50}, final = "Chief Ukorz Sandscalp", bosses = {
        "Antu'sul", "Witch Doctor Zum'rah", "Shadowpriest Sezz'ziz", { "Gahz'rilla", summon = true },
        { "Zerillis", rare = true }, { "Sandarr Dunereaver", rare = true }, { "Dustwraith", rare = true },
        "Ruuzlu", "Chief Ukorz Sandscalp",
    }},
    ["Maraudon"] = { levels = {45, 52}, final = "Princess Theradras", bosses = {
        "Noxxion", "Razorlash", "Lord Vyletongue", { "Meshlok the Harvester", rare = true },
        "Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras",
    }},
    ["Sunken Temple"] = { levels = {49, 56}, final = "Shade of Eranikus", bosses = {
        "Atal'alarion", "Dreamscythe", "Weaver", "Avatar of Hakkar", "Jammal'an the Prophet",
        "Ogom the Wretched", "Morphaz", "Hazzas", "Shade of Eranikus",
    }},
    ["Blackrock Depths"] = { levels = {52, 60}, final = "Emperor Dagran Thaurissan", bosses = {
        "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Gorosh the Dervish",
        "Grizzle", "Eviscerator", "Ok'thor the Breaker", "Anub'shiah", "Hedrum the Creeper",
        "Pyromancer Loregrain", "Fineous Darkvire", "Warder Stilgiss", "Lord Incendius", "Bael'Gar",
        "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx",
        "Ribbly Screwspigot", "Plugger Spazzring", "Ambassador Flamelash",
        { "Panzor the Invincible", rare = true },
        { "The Seven", aka = { "Doom'rel", "Hate'rel", "Anger'rel", "Vile'rel", "Gloom'rel", "Seeth'rel", "Dope'rel" } },
        "Magmus", "Princess Moira Bronzebeard", "Emperor Dagran Thaurissan",
    }},
    ["Lower Blackrock Spire"] = { instance = "Blackrock Spire", levels = {55, 60}, final = "Overlord Wyrmthalak", bosses = {
        { "Spirestone Butcher", rare = true }, { "Spirestone Battle Lord", rare = true },
        { "Spirestone Lord Magus", rare = true }, "Highlord Omokk", "Shadow Hunter Vosh'gajin",
        "War Master Voone", "Mother Smolderweb", { "Crystal Fang", rare = true }, "Urok Doomhowl",
        { "Bannok Grimaxe", rare = true }, "Quartermaster Zigris", "Halycon", "Gizrul the Slavener",
        { "Ghok Bashguud", rare = true }, "Overlord Wyrmthalak",
    }},
    ["Upper Blackrock Spire"] = { instance = "Blackrock Spire", levels = {55, 60}, final = "General Drakkisath", bosses = {
        "Pyroguard Emberseer", "Solakar Flamewreath", { "Jed Runewatcher", rare = true },
        "Goraluk Anvilcrack", "Gyth", "Warchief Rend Blackhand", "The Beast",
        { "Lord Valthalak", summon = true }, "General Drakkisath",
    }},
    ["Dire Maul: East"] = { levels = {55, 60}, final = "Alzzin the Wildshaper", bosses = {
        "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper",
    }},
    ["Dire Maul: West"] = { levels = {57, 60}, final = "Prince Tortheldrin", bosses = {
        "Tendris Warpwood", "Illyanna Ravenoak", { "Tsu'zee", rare = true }, "Magister Kalendris",
        "Immol'thar", "Lord Hel'nurath", "Prince Tortheldrin",
    }},
    ["Dire Maul: North"] = { levels = {57, 60}, final = "King Gordok", bosses = {
        "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush",
        "Cho'Rush the Observer", "King Gordok",
    }},
    ["Scholomance"] = { levels = {58, 60}, final = "Darkmaster Gandling", bosses = {
        { "Kirtonos the Herald", summon = true }, "Jandice Barov", "Rattlegore", "Marduk Blackpool",
        "Vectus", "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov",
        "Lorekeeper Polkelt", "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov",
        "Darkmaster Gandling",
    }},
    ["Stratholme: Living"] = { levels = {58, 60}, final = "Balnazzar", bosses = {
        { "Skul", rare = true }, { "Hearthsinger Forresten", rare = true }, "The Unforgiven",
        "Timmy the Cruel", "Postmaster Malown", "Cannon Master Willey", "Archivist Galford", "Balnazzar",
    }},
    ["Stratholme: Undead"] = { levels = {58, 60}, final = "Baron Rivendare", bosses = {
        { "Stonespine", rare = true }, "Magistrate Barthilas", "Nerub'enkan", "Baroness Anastari",
        "Maleki the Pallid", "Ramstein the Gorger", "Baron Rivendare",
    }},
    -- Announced, bosses not documented yet: runs are saved as "Finished".
    -- (ForeverDungeonJournal 1.7.2: bosses in its order, the last one final.)
    ["Krol'dok Stronghold"] = { levels = {40, 45}, final = "Overlord Mugg", bosses = {
        "Slavecrusher Grox", "Twilight Commander Zarmok", "War Handler Ashka", "Nar'gurk",
        "Bossman Toof", "Overlord Mugg",
    }},
    ["The Drowned City"] = { levels = {35, 40}, final = "Min'loth the Serpent", bosses = {
        "Zul'Alai", "Var'Taka", "Captain Dreadrise", "Deathless Marrow",
        { "Gill", rare = true }, "Min'loth the Serpent",
    }},
    ["Alcaz Prison"]        = { levels = {48, 53}, bosses = {} },
    ["Blackmaw Hold"]       = { levels = {55, 60}, bosses = {} },
    ["Shaper's Terrace"]    = { levels = {58, 60}, bosses = {} },
}

-- Other names the game may give an instance than the key above.
D.INSTANCE_ALIASES = {
    ["Deadmines"]                 = "The Deadmines",
    ["Stormwind Stockade"]        = "The Stockade",
    ["The Stockades"]             = "The Stockade",
    ["The Temple of Atal'Hakkar"] = "Sunken Temple",
    ["Temple of Atal'Hakkar"]     = "Sunken Temple",
}
-- The classic dungeons by instance ID (GetInstanceInfo), for clients in other
-- languages, where the dungeon's name isn't the English one in DUNGEONS.
-- Dungeons with wings map to the instance; the wing is found by its bosses.
-- Wings by the map the game says you're on (C_Map.GetBestMapForUnit): the
-- four Scarlet Monastery wings share one instance, but each is its own map.
-- The game names all four just "Scarlet Monastery", so the name can't say.
-- (warcraft.wiki.gg/wiki/UiMapID; a map the bosses show to be another wing
-- is learned and wins over this.)
D.WING_MAPS = {
    [302] = "Scarlet Monastery: Graveyard", [303] = "Scarlet Monastery: Library",
    [304] = "Scarlet Monastery: Armory",    [305] = "Scarlet Monastery: Cathedral",
}

-- Wings by the part of the dungeon you're in (GetSubZoneText), for when
-- the game has no map for it (WoW Forever: no dungeon maps). English names;
-- in any language, a part of a wing is learned from the bosses fought there.
D.WING_ZONES = {
    ["Chamber of Atonement"] = "Scarlet Monastery: Graveyard",
    ["Forlorn Cloister"]     = "Scarlet Monastery: Graveyard",
    ["Honor's Tomb"]         = "Scarlet Monastery: Graveyard",
    ["Huntsman's Cloister"]  = "Scarlet Monastery: Library",
    ["Gallery of Treasures"] = "Scarlet Monastery: Library",
    ["Athenaeum"]            = "Scarlet Monastery: Library",
    ["Training Grounds"]     = "Scarlet Monastery: Armory",
    ["Footman's Armory"]     = "Scarlet Monastery: Armory",
    ["Crusader's Armory"]    = "Scarlet Monastery: Armory",
    ["Hall of Champions"]    = "Scarlet Monastery: Armory",
    ["Chapel Gardens"]       = "Scarlet Monastery: Cathedral",
    ["Crusader's Chapel"]    = "Scarlet Monastery: Cathedral",
}

-- Wings by the door you walked in through: where you last stood outside,
-- on the zone's map (x, y from 0 to 1). The four Scarlet Monastery doors are
-- side by side in Tirisfal Glades (map 1420). These two were measured in
-- game on the Forever client (as in the Forever Dungeon Journal addon); the
-- others, and any door in another language's client, are learned from the
-- bosses fought inside.
D.WING_DOORS = {
    { map = 1420, x = 0.8535, y = 0.3239, wing = "Scarlet Monastery: Library" },
    { map = 1420, x = 0.8480, y = 0.3037, wing = "Scarlet Monastery: Graveyard" },
}

-- Wings by the trash you kill: mobs found in only one wing (by NPC ID, or
-- by English name). Mobs shared by two wings (Scarlet Myrmidon, Defender,
-- Chaplain and Monk; Scarshield trash) are left out, so they never choose.
-- Classic NPC IDs, as collected by the Forever Dungeon Journal addon.
D.WING_TRASH = {
    ["Scarlet Monastery: Graveyard"] = { [4283] = "Scarlet Sentry", [4293] = "Scarlet Scryer",
        [4306] = "Scarlet Torturer", [4308] = "Unfettered Spirit", [6426] = "Anguished Dead",
        [6427] = "Haunting Phantasm" },
    ["Scarlet Monastery: Library"] = { [4287] = "Scarlet Gallant", [4288] = "Scarlet Beastmaster",
        [4291] = "Scarlet Diviner", [4296] = "Scarlet Adept", [4304] = "Scarlet Tracking Hound" },
    ["Scarlet Monastery: Armory"] = { [4286] = "Scarlet Soldier", [4289] = "Scarlet Evoker",
        [4290] = "Scarlet Guardsman", [4292] = "Scarlet Protector", [4297] = "Scarlet Conjuror" },
    ["Scarlet Monastery: Cathedral"] = { [4294] = "Scarlet Sorcerer", [4300] = "Scarlet Wizard",
        [4301] = "Scarlet Centurion", [4302] = "Scarlet Champion", [4303] = "Scarlet Abbot" },
    ["Dire Maul: East"] = { [13022] = "Whip Lasher", [13276] = "Wildspawn Imp",
        [11461] = "Warpwood Guardian", [11462] = "Warpwood Treant", [11464] = "Warpwood Tangler",
        [11465] = "Warpwood Stomper", [13021] = "Warpwood Crusher", [13196] = "Phase Lasher",
        [13197] = "Fel Lash", [11451] = "Wildspawn Satyr", [11452] = "Wildspawn Rogue",
        [11453] = "Wildspawn Trickster", [11454] = "Wildspawn Betrayer", [11455] = "Wildspawn Felsworn",
        [11456] = "Wildspawn Shadowstalker", [11457] = "Wildspawn Hellcaller" },
    ["Dire Maul: West"] = { [11458] = "Petrified Treant", [11459] = "Ironbark Protector",
        [11469] = "Eldreth Seether", [11470] = "Eldreth Sorcerer", [11471] = "Eldreth Apparition",
        [11472] = "Eldreth Spirit", [11473] = "Eldreth Spectre", [11475] = "Eldreth Phantasm",
        [11480] = "Arcane Aberration", [11483] = "Mana Remnant", [11484] = "Residual Monstrosity" },
    ["Dire Maul: North"] = { [11441] = "Gordok Brute", [11444] = "Gordok Mage-Lord",
        [11445] = "Gordok Captain", [11448] = "Gordok Warlock", [11450] = "Gordok Reaver",
        [13036] = "Gordok Mastiff" },
    ["Upper Blackrock Spire"] = { [9096] = "Rage Talon Dragonspawn", [9818] = "Blackhand Summoner",
        [9819] = "Blackhand Veteran" },
    ["Lower Blackrock Spire"] = { [9197] = "Spirestone Battle Mage", [9198] = "Spirestone Mystic",
        [9199] = "Spirestone Enforcer", [9200] = "Spirestone Reaver", [9201] = "Spirestone Ogre Magus",
        [9239] = "Smolderthorn Mystic", [9240] = "Smolderthorn Shadow Priest",
        [9241] = "Smolderthorn Headhunter", [9259] = "Firebrand Grunt", [9261] = "Firebrand Darkweaver",
        [9264] = "Firebrand Pyromancer" },
}

-- Dungeon entrances, for the world map's markers (Core/MapPins.lua): the
-- zone's map ID and the spot on it (x, y from 0 to 1). The positions are the
-- Forever Dungeon Journal addon's (gathered for the Forever client); wings
-- that share an entrance share a marker. levels: for dungeons not in
-- DUNGEONS above.
D.ENTRANCES = {
    { "Ragefire Chasm",               map = 1454, x = 0.526, y = 0.490 },
    { "Wailing Caverns",              map = 1413, x = 0.460, y = 0.364 },
    { "The Deadmines",                map = 1436, x = 0.425, y = 0.717 },
    { "Shadowfang Keep",              map = 1421, x = 0.448, y = 0.678 },
    { "Blackfathom Deeps",            map = 1440, x = 0.145, y = 0.142 },
    { "The Stockade",                 map = 1453, x = 0.524, y = 0.700 },
    { "Gnomeregan",                   map = 1426, x = 0.243, y = 0.398 },
    { "Razorfen Kraul",               map = 1413, x = 0.429, y = 0.902 },
    { "Razorfen Downs",               map = 1413, x = 0.500, y = 0.920 },
    { "Scarlet Monastery: Graveyard", map = 1420, x = 0.826, y = 0.338 },
    { "Scarlet Monastery: Library",   map = 1420, x = 0.826, y = 0.338 },
    { "Scarlet Monastery: Armory",    map = 1420, x = 0.826, y = 0.338 },
    { "Scarlet Monastery: Cathedral", map = 1420, x = 0.826, y = 0.338 },
    { "Ruins of Lordaeron",           map = 1420, x = 0.634, y = 0.674 },
    { "Uldaman",                      map = 1418, x = 0.443, y = 0.120 },
    { "Zul'Farrak",                   map = 1446, x = 0.387, y = 0.200 },
    { "Maraudon",                     map = 1443, x = 0.291, y = 0.625 },
    { "Sunken Temple",                map = 1435, x = 0.695, y = 0.535 },
    { "Blackrock Depths",             map = 1427, x = 0.348, y = 0.840 },
    { "Lower Blackrock Spire",        map = 1427, x = 0.348, y = 0.840 },
    { "Upper Blackrock Spire",        map = 1427, x = 0.348, y = 0.840 },
    { "Dire Maul: East",              map = 1444, x = 0.590, y = 0.450 },
    { "Dire Maul: West",              map = 1444, x = 0.590, y = 0.450 },
    { "Dire Maul: North",             map = 1444, x = 0.590, y = 0.450 },
    { "Scholomance",                  map = 1422, x = 0.697, y = 0.732 },
    { "Stratholme: Living",           map = 1423, x = 0.300, y = 0.150 },
    { "Stratholme: Undead",           map = 1423, x = 0.440, y = 0.190 },
    { "Hall of Thanes",               map = 1455, x = 0.435, y = 0.520 },
    { "Excavation Site: Wetlands",    map = 1437, x = 0.477, y = 0.562 },
    { "The Drowned City",             map = 1434, x = 0.214, y = 0.279 },
    { "City of Dalaran",              map = 1416, x = 0.085, y = 0.593 },
    { "Krol'dok Stronghold",          map = 2548, x = 0.375, y = 0.373 },
    { "Alcaz Prison",                 map = 1445, x = 0.753, y = 0.141, levels = { 48, 53 } },
    { "Blackmaw Hold",                map = 1447, x = 0.386, y = 0.332, levels = { 55, 60 } },
    { "Shaper's Terrace",             map = 1449, x = 0.481, y = 0.061, levels = { 58, 60 } },
}

D.INSTANCE_IDS = {
    [389] = "Ragefire Chasm",    [43]  = "Wailing Caverns",  [36]  = "The Deadmines",
    [33]  = "Shadowfang Keep",   [48]  = "Blackfathom Deeps", [34]  = "The Stockade",
    [90]  = "Gnomeregan",        [47]  = "Razorfen Kraul",   [189] = "Scarlet Monastery",
    [129] = "Razorfen Downs",    [70]  = "Uldaman",          [209] = "Zul'Farrak",
    [349] = "Maraudon",          [109] = "Sunken Temple",    [230] = "Blackrock Depths",
    [229] = "Blackrock Spire",   [429] = "Dire Maul",        [329] = "Stratholme",
    [289] = "Scholomance",
}

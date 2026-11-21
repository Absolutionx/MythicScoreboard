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
--          mark  rare = true    (rare spawn or optional boss, never required)
--                summon = true  (summoned / optional event, never required)
--                aka = {...}    (other names the game may use for it)
-- Dungeons with an empty boss list are announced but not yet documented.
--
-- Sources: the classic dungeons from the game as it was; WoW Forever's own
-- dungeons from the public guides on warcrafttavern.com (Nov 2026), checked
-- against method.gg, lfcarry.com and allthings.how where they differ, with
-- the level ranges from Wowhead's Forever dungeon overview. Other names the
-- game used in our own runs are kept as aka.

D.DUNGEONS = {
    ["Ragefire Chasm"] = { levels = {13, 18}, final = "Bazzalan", bosses = {
        "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan",
    }},
    ["Hall of Thanes"] = { levels = {13, 20}, final = "Durgen Dirgehammer", bosses = {
        "Faldrim Anvilmar", { "Magmatus", aka = { "Infurnus" } }, "Plunder", { "Durgen Dirgehammer", aka = { "Dirgen Dirgehammer" } },
    }},
    -- (Viktor the Vile: an optional gauntlet. The Butcher: what the game
    -- called The Baron in our own runs.)
    ["Ruins of Lordaeron"] = { levels = {15, 22}, final = "Rath'mael", bosses = {
        "Witherfang", { "The Baron", aka = { "The Butcher" } }, { "Viktor the Vile", summon = true },
        "The Abandoned", "Bjork", "Rath'mael", { "Lordaeron Captain", rare = true },
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
        "Rethilgore", { "Fel Steed / Shadow Charger", rare = true, aka = { "Fel Steed", "Shadow Charger" } },
        "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher",
        { "Deathsworn Captain", rare = true }, "Arugal's Voidwalker", "Fenrus the Devourer",
        "Wolf Master Nandos", "Archmage Arugal",
    }},
    ["Blackfathom Deeps"] = { levels = {24, 32}, final = "Aku'mai", bosses = {
        "Ghamoo-ra", "Lady Sarevess", { "Gelihast", aka = { "Geilhast" } },
        { "Lorgus Jett", rare = true },                -- doesn't always spawn
        { "Baron Aquanis", summon = true }, "Old Serra'kis", "Twilight Lord Kelris", "Aku'mai",
    }},
    ["The Stockade"] = { levels = {24, 32}, final = "Bazil Thredd", bosses = {
        "Targorr the Dread", "Kam Deepfury", "Hamhock", "Dextren Ward", "Bazil Thredd",
        { "Bruegal Ironknuckle", rare = true },
    }},
    ["Excavation Site: Wetlands"] = { levels = {26, 33}, final = "Relic Guardian", bosses = {
        "Saltspine", "Shadetooth", { "Highland Horror", rare = true }, "Relic Guardian",
    }},
    ["City of Dalaran"] = { levels = {28, 33}, final = "Shade of the Archmage", bosses = {
        "Atrexis the Grave Knight", { "Lyn the Ignored", summon = true }, "Mana Devourer",
        "Arcane Anomaly", "Fel Ancient", { "Arcanic Enigma", aka = { "Mana Elemental" } },
        { "Mana Wraith", rare = true },
        { "Unstable Sentinel", aka = { "Unstable Sentry" } }, "Shade of the Archmage",
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
        "Ironaya", { "Obsidian Sentinel", rare = true }, "Ancient Stone Keeper", "Galgann Firehammer",
        "Grimlok", "Archaedas",
    }},
    ["Zul'Farrak"] = { levels = {43, 50}, final = "Chief Ukorz Sandscalp", bosses = {
        { "Theka the Martyr", rare = true }, "Antu'sul", "Witch Doctor Zum'rah",
        { "Nekrum Gutchewer", rare = true }, "Shadowpriest Sezz'ziz",
        { "Sergeant Bly", rare = true }, { "Hydromancer Velratha", rare = true },
        { "Gahz'rilla", summon = true },
        { "Zerillis", rare = true }, { "Sandarr Dunereaver", rare = true }, { "Dustwraith", rare = true },
        "Ruuzlu", "Chief Ukorz Sandscalp",
    }},
    ["Maraudon"] = { levels = {45, 52}, final = "Princess Theradras", bosses = {
        "Noxxion", "Razorlash", "Lord Vyletongue", { "Meshlok the Harvester", rare = true },
        "Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras",
    }},
    ["Sunken Temple"] = { levels = {49, 56}, final = "Shade of Eranikus", bosses = {
        { "Gasher", rare = true }, { "Loro", rare = true }, { "Zolo", rare = true },
        { "Hukku", rare = true }, { "Mijan", rare = true }, { "Zul'Lor", rare = true },
        "Atal'alarion", { "Dreamscythe", aka = { "Dreamscythe & Weaver",
        "Traumsense", "Fauche-rêve", "Guadañasueños", "Darquimeros", "Жнец Снов", "드림사이드", "德姆塞卡尔", "德姆塞卡爾" } }, "Weaver", "Avatar of Hakkar", "Jammal'an the Prophet",
        "Ogom the Wretched", { "Morphaz", aka = { "Morphaz & Hazzas", "Морфаз", "몰파즈", "摩弗拉斯" } }, "Hazzas", "Shade of Eranikus",
    }},
    ["Blackrock Depths"] = { levels = {52, 60}, final = "Emperor Dagran Thaurissan", bosses = {
        "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar",
        -- (The Ring of Law: one fight, against whichever of the six shows up.)
        { "Ring of Law", aka = { "Gorosh the Dervish", "Grizzle", "Eviscerator", "Ok'thor the Breaker",
                                 "Anub'shiah", "Hedrum the Creeper" } },
        "Pyromancer Loregrain", "Fineous Darkvire", "Warder Stilgiss", "Lord Incendius", "Bael'Gar",
        "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx",
        "Ribbly Screwspigot", "Plugger Spazzring", { "Theldren", summon = true }, "Ambassador Flamelash",
        { "Panzor the Invincible", rare = true },
        { "The Seven", aka = { "Doom'rel", "Hate'rel", "Anger'rel", "Vile'rel", "Gloom'rel", "Seeth'rel",
                               "Dope'rel" } },
        -- (Moira: often spared, killing the Emperor without her.)
        "Magmus", { "Princess Moira Bronzebeard", rare = true }, "Emperor Dagran Thaurissan",
    }},
    ["Lower Blackrock Spire"] = { instance = "Blackrock Spire", levels = {55, 60}, final = "Overlord Wyrmthalak", bosses = {
        { "Spirestone Butcher", rare = true }, { "Spirestone Battle Lord", rare = true },
        { "Spirestone Lord Magus", rare = true }, "Highlord Omokk", "Shadow Hunter Vosh'gajin",
        "War Master Voone", "Mother Smolderweb", { "Crystal Fang", rare = true }, "Urok Doomhowl",
        { "Bannok Grimaxe", rare = true }, "Quartermaster Zigris", "Halycon", "Gizrul the Slavener",
        { "Mor Grayhoof", summon = true }, { "Burning Felguard", rare = true },
        { "Ghok Bashguud", rare = true }, "Overlord Wyrmthalak",
    }},
    ["Upper Blackrock Spire"] = { instance = "Blackrock Spire", levels = {55, 60}, final = "General Drakkisath", bosses = {
        "Pyroguard Emberseer", "Solakar Flamewreath", { "Jed Runewatcher", rare = true },
        "Goraluk Anvilcrack", "Gyth", "Warchief Rend Blackhand", "The Beast",
        { "Lord Valthalak", summon = true }, "General Drakkisath",
    }},
    ["Dire Maul: East"] = { levels = {55, 60}, final = "Alzzin the Wildshaper", bosses = {
        { "Pusillin", rare = true }, "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", { "Isalien", summon = true }, "Alzzin the Wildshaper",
    }},
    ["Dire Maul: West"] = { levels = {57, 60}, final = "Prince Tortheldrin", bosses = {
        "Tendris Warpwood", "Illyanna Ravenoak", { "Tsu'zee", rare = true }, "Magister Kalendris",
        "Immol'thar", { "Lord Hel'nurath", summon = true }, "Prince Tortheldrin",
    }},
    ["Dire Maul: North"] = { levels = {57, 60}, final = "King Gordok", bosses = {
        "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush",
        "Cho'Rush the Observer", "King Gordok",
    }},
    ["Scholomance"] = { levels = {58, 60}, final = "Darkmaster Gandling", bosses = {
        { "Kirtonos the Herald", summon = true, aka = { "Kirtonos" } }, "Jandice Barov", "Rattlegore", "Marduk Blackpool",
        "Vectus", { "Ras Frostwhisper", aka = { "Ras Frostwhisperer" } }, "Instructor Malicia", "Doctor Theolen Krastinov",
        "Lorekeeper Polkelt", "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov",
        { "Death Knight Darkreaver", summon = true, aka = { "Darkreaver" } }, { "Kormok", summon = true },
        "Darkmaster Gandling",
    }},
    ["Stratholme: Living"] = { levels = {58, 60}, final = "Balnazzar", bosses = {
        { "Skul", rare = true }, { "Hearthsinger Forresten", rare = true }, "The Unforgiven",
        "Timmy the Cruel", { "Malor the Zealous", rare = true }, { "Postmaster Malown", summon = true },
        { "Ezra Grimm", rare = true, aka = { "Fras Siabi" } }, "Cannon Master Willey", "Archivist Galford",
        { "Jarien and Sothos", summon = true, aka = { "Jarien", "Sothos" } }, "Balnazzar",
    }},
    ["Stratholme: Undead"] = { levels = {58, 60}, final = "Baron Rivendare", bosses = {
        { "Stonespine", rare = true }, "Magistrate Barthilas", "Nerub'enkan", "Baroness Anastari",
        "Maleki the Pallid", "Ramstein the Gorger", "Baron Rivendare",
    }},
    -- WoW Forever's own dungeons (sources above).
    ["Krol'dok Stronghold"] = { levels = {40, 45}, final = "Overlord Mugg", bosses = {
        "Slavecrusher Grox", { "Twilight Commander Zarmok", aka = { "Zarmok" } },
        { "War Handler Ashka", aka = { "Handler Ashka" } }, "Nar'gurk", { "Bossman Toof", aka = { "Boss Kof" } },
        { "Kroog", rare = true }, { "Overlord Mugg", aka = { "Overseer Mugg" } },
    }},
    ["The Drowned City"] = { levels = {35, 40}, final = "Min'loth the Serpent", bosses = {
        "Zul'Alai", { "Var'Taka", aka = { "Zin'aka" } }, { "Primeval Elemental", summon = true }, "Captain Dreadrise",
        { "Deathless Marrow", aka = { "Deathless Guardians" } },
        { "Umbra", rare = true }, { "Gill", rare = true },
        { "\"Pyromancer\" Braxton", rare = true, aka = { "Pyromancer Braxton", "\"Пиромант\" Бракстон" } },
        { "Min'loth the Serpent", aka = { "Min'loth" } },
    }},
    -- (Zarla Ober becomes Blazeroar partway through the fight.)
    ["Alcaz Prison"] = { levels = {48, 53}, final = "Blazeroar", bosses = {
        { "Overseer Wrex", aka = { "Wrex" } }, { "The Questioner", aka = { "Questioner" } },
        { "Tidemistress Ca'zass", aka = { "Ca'zass" } }, { "Katerina the Cleaner", aka = { "Katerina" } },
        { "Blazeroar", aka = { "Zarla Ober" } },
    }},
    ["Blackmaw Hold"] = { levels = {55, 60}, final = "Varrox Bleakhoof", bosses = {
        "Withermaw", { "Bonesnout the Unbroken", aka = { "Bonesnout" } },
        { "Impaan the Imprisoner", aka = { "Impaan" } }, "Unbound Spirit",
        { "Elder Shaman Bloodmane", aka = { "Bloodmane" } },
        { "Blackmaw Behemoth", aka = { "Clawbert" } },
        { "Moontouched Wanderer", rare = true }, { "Gortek the Apprentice", rare = true, aka = { "Gortek" } },
        { "Tunnelweb Matriarch", rare = true }, { "Sabella No-Eyes", rare = true, aka = { "Sabella" } },
        { "Varrox Bleakhoof", aka = { "Varrox" } },
    }},
    -- (The four crystal bosses open the way to Nanaya; Vitrix can be skipped
    -- once its crystals are in, and the roaming dinosaurs are optional.)
    ["Shaper's Terrace"] = { levels = {58, 60}, final = "Nanaya", bosses = {
        "Cinder", "Snowtalon", { "Vitrix", summon = true }, "Bolt",
        { "Titanosaur", rare = true }, { "Direhorn Matriarch", rare = true },
        { "Thunderhoof", rare = true }, { "Venomridge", rare = true },
        { "Izha'Rel and Tor'Rel", rare = true, aka = { "Izha'Rel", "Tor'Rel" } },
        "Nanaya",
    }},
}

-- Other names the game may give an instance than the key above.
D.INSTANCE_ALIASES = {
    ["Deadmines"]                 = "The Deadmines",
    ["Stormwind Stockade"]        = "The Stockade",
    ["The Stockades"]             = "The Stockade",
    ["The Temple of Atal'Hakkar"] = "Sunken Temple",
    ["Temple of Atal'Hakkar"]     = "Sunken Temple",
}
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

-- Wings by the door you walked in through: learned from the bosses fought
-- inside (Core/Forever.lua), nothing built in.
D.WING_DOORS = {}

-- Wings by the trash you kill: mobs found in only one wing, by English name.
-- Mobs shared by two wings (Scarlet Myrmidon, Defender, Chaplain and Monk;
-- Scarshield trash) are left out, so they never choose. (By name only: WoW
-- Forever hides the mobs' GUIDs inside dungeons.)
D.WING_TRASH = {
    ["Scarlet Monastery: Graveyard"] = { "Scarlet Scryer", "Scarlet Torturer", "Unfettered Spirit",
        "Anguished Dead", "Haunting Phantasm" },
    ["Scarlet Monastery: Library"] = { "Scarlet Gallant", "Scarlet Beastmaster", "Scarlet Diviner",
        "Scarlet Adept", "Scarlet Tracking Hound" },
    ["Scarlet Monastery: Armory"] = { "Scarlet Soldier", "Scarlet Evoker", "Scarlet Guardsman",
        "Scarlet Protector", "Scarlet Conjuror" },
    ["Scarlet Monastery: Cathedral"] = { "Scarlet Sorcerer", "Scarlet Wizard", "Scarlet Centurion",
        "Scarlet Champion", "Scarlet Abbot" },
    ["Dire Maul: East"] = { "Whip Lasher", "Phase Lasher", "Fel Lash", "Wildspawn Imp",
        "Warpwood Guardian", "Warpwood Treant", "Warpwood Tangler", "Warpwood Stomper",
        "Warpwood Crusher", "Wildspawn Satyr", "Wildspawn Rogue", "Wildspawn Trickster",
        "Wildspawn Betrayer", "Wildspawn Felsworn", "Wildspawn Shadowstalker", "Wildspawn Hellcaller" },
    ["Dire Maul: West"] = { "Petrified Treant", "Ironbark Protector", "Eldreth Seether",
        "Eldreth Sorcerer", "Eldreth Apparition", "Eldreth Spirit", "Eldreth Spectre",
        "Eldreth Phantasm", "Arcane Aberration", "Mana Remnant", "Residual Monstrosity" },
    ["Dire Maul: North"] = { "Gordok Brute", "Gordok Mage-Lord", "Gordok Captain", "Gordok Warlock",
        "Gordok Reaver", "Gordok Mastiff" },
    ["Upper Blackrock Spire"] = { "Rage Talon Dragonspawn", "Blackhand Summoner", "Blackhand Veteran" },
    ["Lower Blackrock Spire"] = { "Spirestone Battle Mage", "Spirestone Mystic", "Spirestone Enforcer",
        "Spirestone Reaver", "Spirestone Ogre Magus", "Smolderthorn Mystic",
        "Smolderthorn Shadow Priest", "Smolderthorn Headhunter" },
}

-- Dungeon entrances, for the world map's markers (Core/MapPins.lua): the
-- zone's map ID and the spot on it (x, y from 0 to 1). The classic ones from
-- Wowhead's Forever dungeon overview, WoW Forever's own from the
-- warcrafttavern.com guides (Nov 2026); wings that share an entrance share a
-- marker. levels: for dungeons not in DUNGEONS above.
D.ENTRANCES = {
    { "Ragefire Chasm",               map = 1454, x = 0.520, y = 0.490 },
    { "Wailing Caverns",              map = 1413, x = 0.455, y = 0.355 },
    { "The Deadmines",                map = 1436, x = 0.424, y = 0.704 },
    { "Shadowfang Keep",              map = 1421, x = 0.426, y = 0.666 },
    { "Blackfathom Deeps",            map = 1440, x = 0.134, y = 0.128 },
    { "The Stockade",                 map = 1453, x = 0.410, y = 0.570 },
    { "Gnomeregan",                   map = 1426, x = 0.305, y = 0.363 },
    { "Razorfen Kraul",               map = 1413, x = 0.426, y = 0.885 },
    { "Razorfen Downs",               map = 1413, x = 0.500, y = 0.920 },
    { "Scarlet Monastery: Graveyard", map = 1420, x = 0.835, y = 0.320 },
    { "Scarlet Monastery: Library",   map = 1420, x = 0.835, y = 0.320 },
    { "Scarlet Monastery: Armory",    map = 1420, x = 0.835, y = 0.320 },
    { "Scarlet Monastery: Cathedral", map = 1420, x = 0.835, y = 0.320 },
    { "Ruins of Lordaeron",           map = 1420, x = 0.620, y = 0.670 },
    { "Uldaman",                      map = 1418, x = 0.426, y = 0.108 },
    { "Zul'Farrak",                   map = 1446, x = 0.395, y = 0.213 },
    { "Maraudon",                     map = 1443, x = 0.295, y = 0.578 },
    { "Sunken Temple",                map = 1435, x = 0.696, y = 0.532 },
    { "Blackrock Depths",             map = 1427, x = 0.352, y = 0.842 },
    { "Lower Blackrock Spire",        map = 1427, x = 0.352, y = 0.842 },
    { "Upper Blackrock Spire",        map = 1427, x = 0.352, y = 0.842 },
    { "Dire Maul: East",              map = 1444, x = 0.589, y = 0.415 },
    { "Dire Maul: West",              map = 1444, x = 0.589, y = 0.415 },
    { "Dire Maul: North",             map = 1444, x = 0.589, y = 0.415 },
    { "Scholomance",                  map = 1422, x = 0.698, y = 0.760 },
    { "Stratholme: Living",           map = 1423, x = 0.309, y = 0.152 },
    { "Stratholme: Undead",           map = 1423, x = 0.483, y = 0.218 },
    { "Hall of Thanes",               map = 1455, x = 0.435, y = 0.520 },
    { "Excavation Site: Wetlands",    map = 1437, x = 0.481, y = 0.565 },
    { "The Drowned City",             map = 1434, x = 0.214, y = 0.279 },
    { "City of Dalaran",              map = 1421, x = 0.693, y = 0.456 },
    { "Krol'dok Stronghold",          map = 2548, x = 0.375, y = 0.375 },
    { "Alcaz Prison",                 map = 1445, x = 0.750, y = 0.150, levels = { 48, 53 } },
    { "Blackmaw Hold",                map = 1447, x = 0.387, y = 0.334, levels = { 55, 60 } },
    { "Shaper's Terrace",             map = 1449, x = 0.481, y = 0.061, levels = { 58, 60 } },
}

-- The classic dungeons by instance ID (GetInstanceInfo), for clients in other
-- languages, where the dungeon's name isn't the English one in DUNGEONS.
-- Dungeons with wings map to the instance; the wing is found by its bosses.
D.INSTANCE_IDS = {
    [389] = "Ragefire Chasm",    [43]  = "Wailing Caverns",  [36]  = "The Deadmines",
    [33]  = "Shadowfang Keep",   [48]  = "Blackfathom Deeps", [34]  = "The Stockade",
    [90]  = "Gnomeregan",        [47]  = "Razorfen Kraul",   [189] = "Scarlet Monastery",
    [129] = "Razorfen Downs",    [70]  = "Uldaman",          [209] = "Zul'Farrak",
    [349] = "Maraudon",          [109] = "Sunken Temple",    [230] = "Blackrock Depths",
    [229] = "Blackrock Spire",   [429] = "Dire Maul",        [329] = "Stratholme",
    [289] = "Scholomance",
}

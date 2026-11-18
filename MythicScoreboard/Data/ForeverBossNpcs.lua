-- WoW Forever dungeon bosses: which creature each one is (npc) and what it
-- looks like (display), so the timeline can draw its portrait before anyone
-- on this account has met it (Core/Portraits.lua). A boss met in play is
-- kept in MythicScoreboardPortraitsDB and wins over this list.
--
-- Names match Data/ForeverDungeons.lua (a boss's aka names find it too).
-- Classic creature IDs are the same as in Classic Era; /sb bosses check asks
-- the game to name each npc ID. Magmatus and the Lordaeron Captain have no
-- known IDs yet. Loaded only by MythicScoreboard_Forever.toc.

local MS = _G["MythicScoreboard"]

MS.ForeverData.BOSSES = {
    -- Excavation Site: Wetlands
    ["Saltspine"]       = { npc = 260322, display = 144209 },
    ["Shadetooth"]      = { npc = 260325, display = 144210 },
    ["Relic Guardian"]  = { npc = 260326, display = 144224 },
    ["Highland Horror"] = { npc = 260808, display = 9010 },

    -- City of Dalaran
    ["Atrexis the Grave Knight"] = { npc = 247126, display = 145787 },
    ["Arcane Anomaly"]           = { npc = 245999, display = 129891 },
    ["Unstable Sentinel"]        = { npc = 246017, display = 129954 },
    ["Fel Ancient"]              = { npc = 246003, display = 129894 },
    ["Mana Devourer"]            = { npc = 246008, display = 129895 },
    ["Arcanic Enigma"]           = { npc = 246016, display = 129900 },
    ["Shade of the Archmage"]    = { npc = 246020, display = 130061 },
    ["Lyn the Ignored"]          = { npc = 247032, display = 130235 },
    ["Mana Wraith"]              = { npc = 246931, display = 130220 },

    -- Shaper's Terrace
    ["Titanosaur"]         = { npc = 253201, display = 142989 },
    ["Venomridge"]         = { npc = 261813, display = 144511 },
    ["Thunderhoof"]        = { npc = 261812, display = 144514 },
    ["Direhorn Matriarch"] = { npc = 262127, display = 144515 },
    ["Cinder"]             = { npc = 261974, display = 143035 },
    ["Bolt"]               = { npc = 262081, display = 143063 },
    ["Snowtalon"]          = { npc = 262297, display = 143122 },
    ["Vitrix"]             = { npc = 272561, display = 147098 },
    ["Izha'Rel"]           = { npc = 253218, display = 143040 },
    ["Tor'Rel"]            = { npc = 261811, display = 143039 },
    ["Nanaya"]             = { npc = 261809, display = 143832 },

    -- Blackmaw Hold
    ["Withermaw"]              = { npc = 247195, display = 140708 },
    ["Impaan the Imprisoner"]  = { npc = 247206, display = 130432 },
    ["Bonesnout the Unbroken"] = { npc = 247198, display = 130427 },
    ["Varrox Bleakhoof"]       = { npc = 247234, display = 130447 },
    ["Elder Shaman Bloodmane"] = { npc = 247209, display = 130440 },
    ["Blackmaw Behemoth"]      = { npc = 247207, display = 130436 },
    ["Unbound Spirit"]         = { npc = 247231, display = 131644 },
    ["Moontouched Wanderer"]   = { npc = 269104, display = 12235 },
    ["Gortek the Apprentice"]  = { npc = 269111, display = 145808 },
    ["Tunnelweb Matriarch"]    = { npc = 250034, display = 2424 },

    -- Alcaz Prison
    ["Overseer Wrex"]        = { npc = 255391, display = 7914 },
    ["Tidemistress Ca'zass"] = { npc = 255997, display = 4973 },
    ["Katerina the Cleaner"] = { npc = 257016, display = 2317 },
    ["The Questioner"]       = { npc = 256236, display = 140092 },
    ["Blazeroar"]            = { npc = 255702, display = 6374 },

    -- Krol'dok Stronghold
    ["Slavecrusher Grox"]         = { npc = 258966, display = 141217 },
    ["Twilight Commander Zarmok"] = { npc = 258972, display = 141219 },
    ["War Handler Ashka"]         = { npc = 259281, display = 141443 },
    ["Nar'gurk"]                  = { npc = 258964, display = 141215 },
    ["Bossman Toof"]              = { npc = 264773, display = 14424 },
    ["Overlord Mugg"]             = { npc = 258968, display = 141218 },
    ["Kroog"]                     = { npc = 262716, display = 17273 },

    -- Gnomeregan
    ["Grubbis"]               = { npc = 7361, display = 144378 },
    ["Viscous Fallout"]       = { npc = 7079, display = 5497 },
    ["Electrocutioner 6000"]  = { npc = 6235, display = 6915 },
    ["Crowd Pummeler 9-60"]   = { npc = 6229, display = 6774 },
    ["Mekgineer Thermaplugg"] = { npc = 7800, display = 6980 },
    ["Dark Iron Ambassador"]  = { npc = 6228, display = 6669 },

    -- Razorfen Kraul
    ["Roogug"]               = { npc = 6168, display = 6110 },
    ["Aggem Thorncurse"]     = { npc = 4424, display = 6097 },
    ["Death Speaker Jargba"] = { npc = 4428, display = 4644 },
    ["Overlord Ramtusk"]     = { npc = 4420, display = 4652 },
    ["Agathelos the Raging"] = { npc = 4422, display = 2450 },
    ["Charlga Razorflank"]   = { npc = 4421, display = 4642 },
    ["Blind Hunter"]         = { npc = 4425, display = 4735 },
    ["Earthcaller Halmgar"]  = { npc = 4842, display = 6102 },

    -- Scarlet Monastery: Graveyard
    ["Interrogator Vishas"]  = { npc = 3983, display = 2044 },
    ["Azshir the Sleepless"] = { npc = 6490, display = 5534 },
    ["Fallen Champion"]      = { npc = 6488, display = 5230 },
    ["Ironspine"]            = { npc = 6489, display = 5231 },
    ["Bloodmage Thalnos"]    = { npc = 4543, display = 11396 },

    -- Scarlet Monastery: Library
    ["Houndmaster Loksey"] = { npc = 3974, display = 2040 },
    ["Arcanist Doan"]      = { npc = 6487, display = 5266 },

    -- Scarlet Monastery: Armory
    ["Herod"] = { npc = 3975, display = 2041 },

    -- Scarlet Monastery: Cathedral
    ["High Inquisitor Fairbanks"]  = { npc = 4542, display = 2605 },
    ["Scarlet Commander Mograine"] = { npc = 3976, display = 2042 },
    ["High Inquisitor Whitemane"]  = { npc = 3977, display = 2043 },

    -- Uldaman
    ["Revelosh"]             = { npc = 6910, display = 5945 },
    ["The Lost Dwarves"]     = { npc = 6906, display = 5710 },
    ["Ironaya"]              = { npc = 7228, display = 6089 },
    ["Obsidian Sentinel"]    = { npc = 7023, display = 5285 },
    ["Ancient Stone Keeper"] = { npc = 7206, display = 10798 },
    ["Galgann Firehammer"]   = { npc = 7291, display = 6059 },
    ["Grimlok"]              = { npc = 4854, display = 11165 },
    ["Archaedas"]            = { npc = 2748, display = 5988 },

    -- Zul'Farrak
    ["Theka the Martyr"]      = { npc = 7272,  display = 6696 },
    ["Antu'sul"]              = { npc = 8127,  display = 7353 },
    ["Witch Doctor Zum'rah"]  = { npc = 7271,  display = 6434 },
    ["Nekrum Gutchewer"]      = { npc = 7796,  display = 6690 },
    ["Shadowpriest Sezz'ziz"] = { npc = 7275,  display = 6441 },
    ["Sergeant Bly"]          = { npc = 7604,  display = 6433 },
    ["Hydromancer Velratha"]  = { npc = 7795,  display = 6685 },
    ["Gahz'rilla"]            = { npc = 7273,  display = 7271 },
    ["Zerillis"]              = { npc = 10082, display = 9293 },
    ["Sandarr Dunereaver"]    = { npc = 10080, display = 9291 },
    ["Dustwraith"]            = { npc = 10081, display = 9292 },
    ["Ruuzlu"]                = { npc = 7797,  display = 6687 },
    ["Chief Ukorz Sandscalp"] = { npc = 7267,  display = 6439 },

    -- Sunken Temple
    ["Gasher"]                = { npc = 5713, display = 6698 },
    ["Loro"]                  = { npc = 5714, display = 6700 },
    ["Zolo"]                  = { npc = 5712, display = 6699 },
    ["Hukku"]                 = { npc = 5715, display = 6702 },
    ["Mijan"]                 = { npc = 5717, display = 6707 },
    ["Zul'Lor"]               = { npc = 5716, display = 6701 },
    ["Atal'alarion"]          = { npc = 8580, display = 7873 },
    ["Dreamscythe"]           = { npc = 5721, display = 7553 },
    ["Weaver"]                = { npc = 5720, display = 6375 },
    ["Avatar of Hakkar"]      = { npc = 8443, display = 8053 },
    ["Jammal'an the Prophet"] = { npc = 5710, display = 6708 },
    ["Ogom the Wretched"]     = { npc = 5711, display = 6709 },
    ["Morphaz"]               = { npc = 5719, display = 7975 },
    ["Hazzas"]                = { npc = 5722, display = 9584 },
    ["Shade of Eranikus"]     = { npc = 5709, display = 7806 },

    -- Scholomance
    ["Kirtonos the Herald"]      = { npc = 10506, display = 143673 },
    ["Jandice Barov"]            = { npc = 10503, display = 11073 },
    ["Rattlegore"]               = { npc = 11622, display = 12073 },
    ["Marduk Blackpool"]         = { npc = 10433, display = 10248 },
    ["Vectus"]                   = { npc = 10432, display = 2606 },
    ["Ras Frostwhisper"]         = { npc = 10508, display = 7919 },
    ["Instructor Malicia"]       = { npc = 10505, display = 11069 },
    ["Doctor Theolen Krastinov"] = { npc = 11261, display = 10901 },
    ["Lorekeeper Polkelt"]       = { npc = 10901, display = 11492 },
    ["The Ravenian"]             = { npc = 10507, display = 10433 },
    ["Lord Alexei Barov"]        = { npc = 10504, display = 11072 },
    ["Lady Illucia Barov"]       = { npc = 10502, display = 11835 },
    ["Darkmaster Gandling"]      = { npc = 1853,  display = 11070 },
    ["Death Knight Darkreaver"]  = { npc = 14516, display = 14591 },
    ["Kormok"]                   = { npc = 16118, display = 16020 },

    -- Maraudon
    ["Noxxion"]               = { npc = 13282, display = 11172 },
    ["Razorlash"]             = { npc = 12258, display = 12389 },
    ["Lord Vyletongue"]       = { npc = 12236, display = 12334 },
    ["Meshlok the Harvester"] = { npc = 12237, display = 9014 },
    ["Celebras the Cursed"]   = { npc = 12225, display = 12350 },
    ["Landslide"]             = { npc = 12203, display = 12293 },
    ["Tinkerer Gizlock"]      = { npc = 13601, display = 7125 },
    ["Rotgrip"]               = { npc = 13596, display = 13589 },
    ["Princess Theradras"]    = { npc = 12201, display = 12292 },

    -- Dire Maul: East
    ["Pusillin"]              = { npc = 14354, display = 7552 },
    ["Zevrim Thornhoof"]      = { npc = 11490, display = 11335 },
    ["Hydrospawn"]            = { npc = 13280, display = 5489 },
    ["Lethtendris"]           = { npc = 14327, display = 14378 },
    ["Alzzin the Wildshaper"] = { npc = 11492, display = 14416 },

    -- Dire Maul: West
    ["Tendris Warpwood"]   = { npc = 11489, display = 14383 },
    ["Illyanna Ravenoak"]  = { npc = 11488, display = 11270 },
    ["Tsu'zee"]            = { npc = 11467, display = 11250 },
    ["Magister Kalendris"] = { npc = 11487, display = 14384 },
    ["Immol'thar"]         = { npc = 11496, display = 14173 },
    ["Lord Hel'nurath"]    = { npc = 14506, display = 14556 },
    ["Prince Tortheldrin"] = { npc = 11486, display = 11256 },

    -- Dire Maul: North
    ["Guard Mol'dar"]         = { npc = 14326, display = 11561 },
    ["Stomper Kreeg"]         = { npc = 14322, display = 11545 },
    ["Guard Fengus"]          = { npc = 14321, display = 11561 },
    ["Guard Slip'kik"]        = { npc = 14323, display = 11561 },
    ["Captain Kromcrush"]     = { npc = 14325, display = 11564 },
    ["Cho'Rush the Observer"] = { npc = 14324, display = 11537 },
    ["King Gordok"]           = { npc = 11501, display = 11583 },

    -- Stratholme: Living
    ["Skul"]                   = { npc = 10393, display = 2606 },
    ["Hearthsinger Forresten"] = { npc = 10558, display = 10482 },
    ["The Unforgiven"]         = { npc = 10516, display = 10771 },
    ["Timmy the Cruel"]        = { npc = 10808, display = 571 },
    ["Malor the Zealous"]      = { npc = 11032, display = 10458 },
    ["Postmaster Malown"]      = { npc = 11143, display = 10669 },
    ["Ezra Grimm"]             = { npc = 11058, display = 10475 },
    ["Cannon Master Willey"]   = { npc = 10997, display = 10674 },
    ["Archivist Galford"]      = { npc = 10811, display = 10544 },
    ["Balnazzar"]              = { npc = 10813, display = 10691 },

    -- Stratholme: Undead
    ["Stonespine"]           = { npc = 10809, display = 7856 },
    ["Magistrate Barthilas"] = { npc = 10435, display = 10433 },
    ["Nerub'enkan"]          = { npc = 10437, display = 9793 },
    ["Baroness Anastari"]    = { npc = 10436, display = 10698 },
    ["Maleki the Pallid"]    = { npc = 10438, display = 10546 },
    ["Ramstein the Gorger"]  = { npc = 10439, display = 12818 },
    ["Baron Rivendare"]      = { npc = 10440, display = 10729 },

    -- Blackrock Depths
    ["High Interrogator Gerstahn"] = { npc = 9018,  display = 8761 },
    ["Lord Roccor"]                = { npc = 9025,  display = 5781 },
    ["Houndmaster Grebmar"]        = { npc = 9319,  display = 9212 },
    ["Gorosh the Dervish"]         = { npc = 9027,  display = 8760 },
    ["Grizzle"]                    = { npc = 9028,  display = 7873 },
    ["Eviscerator"]                = { npc = 9029,  display = 523 },
    ["Ok'thor the Breaker"]        = { npc = 9030,  display = 11538 },
    ["Anub'shiah"]                 = { npc = 9031,  display = 3004 },
    ["Hedrum the Creeper"]         = { npc = 9032,  display = 8271 },
    ["Pyromancer Loregrain"]       = { npc = 9024,  display = 8762 },
    ["Fineous Darkvire"]           = { npc = 9056,  display = 8704 },
    ["Warder Stilgiss"]            = { npc = 9041,  display = 9089 },
    ["Lord Incendius"]             = { npc = 9017,  display = 1204 },
    ["Bael'Gar"]                   = { npc = 9016,  display = 12162 },
    ["General Angerforge"]         = { npc = 9033,  display = 8756 },
    ["Golem Lord Argelmach"]       = { npc = 8983,  display = 8759 },
    ["Hurley Blackbreath"]         = { npc = 9537,  display = 8658 },
    ["Phalanx"]                    = { npc = 9502,  display = 8177 },
    ["Ribbly Screwspigot"]         = { npc = 9543,  display = 8667 },
    ["Theldren"]                   = { npc = 16059, display = 15981 },
    ["Plugger Spazzring"]          = { npc = 9499,  display = 8652 },
    ["Ambassador Flamelash"]       = { npc = 9156,  display = 8329 },
    ["Panzor the Invincible"]      = { npc = 8923,  display = 8270 },
    ["The Seven"]                  = { npc = 9039,  display = 8687 },
    ["Magmus"]                     = { npc = 9938,  display = 12162 },
    ["Princess Moira Bronzebeard"] = { npc = 8929,  display = 8705 },
    ["Emperor Dagran Thaurissan"]  = { npc = 9019,  display = 8807 },

    -- Upper Blackrock Spire
    ["Pyroguard Emberseer"]     = { npc = 9816,  display = 2172 },
    ["Solakar Flamewreath"]     = { npc = 10264, display = 9581 },
    ["Jed Runewatcher"]         = { npc = 10509, display = 9686 },
    ["Goraluk Anvilcrack"]      = { npc = 10899, display = 10222 },
    ["Gyth"]                    = { npc = 10339, display = 9806 },
    ["Warchief Rend Blackhand"] = { npc = 10429, display = 9778 },
    ["The Beast"]               = { npc = 10430, display = 10193 },
    ["Lord Valthalak"]          = { npc = 16042, display = 14308 },
    ["General Drakkisath"]      = { npc = 10363, display = 10115 },

    -- Lower Blackrock Spire
    ["Spirestone Butcher"]       = { npc = 9219,  display = 11574 },
    ["Spirestone Battle Lord"]   = { npc = 9218,  display = 11576 },
    ["Spirestone Lord Magus"]    = { npc = 9217,  display = 11578 },
    ["Highlord Omokk"]           = { npc = 9196,  display = 11565 },
    ["Shadow Hunter Vosh'gajin"] = { npc = 9236,  display = 9732 },
    ["War Master Voone"]         = { npc = 9237,  display = 9733 },
    ["Mother Smolderweb"]        = { npc = 10596, display = 9929 },
    ["Crystal Fang"]             = { npc = 10376, display = 9755 },
    ["Urok Doomhowl"]            = { npc = 10584, display = 11583 },
    ["Bannok Grimaxe"]           = { npc = 9596,  display = 9668 },
    ["Quartermaster Zigris"]     = { npc = 9736,  display = 9738 },
    ["Halycon"]                  = { npc = 10220, display = 9567 },
    ["Gizrul the Slavener"]      = { npc = 10268, display = 9564 },
    ["Ghok Bashguud"]            = { npc = 9718,  display = 11809 },
    ["Overlord Wyrmthalak"]      = { npc = 9568,  display = 8711 },

    -- Razorfen Downs
    ["Tuten'kash"]               = { npc = 7355, display = 7845 },
    ["Mordresh Fire Eye"]        = { npc = 7357, display = 8055 },
    ["Glutton"]                  = { npc = 8567, display = 7864 },
    ["Ragglesnout"]              = { npc = 7354, display = 11382 },
    ["Plaguemaw the Rotting"]    = { npc = 7356, display = 6124 },
    ["Amnennar the Coldbringer"] = { npc = 7358, display = 7971 },

    -- Hall of Thanes
    ["Faldrim Anvilmar"]   = { npc = 261306, display = 142826 },
    ["Plunder"]            = { npc = 261311, display = 142840 },
    ["Durgen Dirgehammer"] = { npc = 261319, display = 142837 },

    -- Ruins of Lordaeron
    ["The Baron"]       = { npc = 250660, display = 144188 },
    ["Witherfang"]      = { npc = 250483, display = 144189 },
    ["The Abandoned"]   = { npc = 250631, display = 138667 },
    ["Bjork"]           = { npc = 256097, display = 144170 },
    ["Rath'mael"]       = { npc = 250657, display = 144175 },
    ["Viktor the Vile"] = { npc = 256035, display = 139455 },

    -- Ragefire Chasm
    ["Oggleflint"]             = { npc = 11517, display = 11611 },
    ["Taragaman the Hungerer"] = { npc = 11520, display = 7970 },
    ["Jergosh the Invoker"]    = { npc = 11518, display = 11429 },
    ["Bazzalan"]               = { npc = 11519, display = 2007 },

    -- The Deadmines
    ["Rhahk'Zor"]         = { npc = 644,  display = 14403 },
    ["Miner Johnson"]     = { npc = 3586, display = 556 },
    ["Sneed's Shredder"]  = { npc = 642,  display = 1269 },
    ["Sneed"]             = { npc = 643,  display = 7125 },
    ["Gilnid"]            = { npc = 1763, display = 7124 },
    ["Mr. Smite"]         = { npc = 646,  display = 2026 },
    ["Captain Greenskin"] = { npc = 647,  display = 7113 },
    ["Edwin VanCleef"]    = { npc = 639,  display = 2029 },
    ["Cookie"]            = { npc = 645,  display = 1305 },

    -- Wailing Caverns
    ["Lord Cobrahn"]          = { npc = 3669, display = 4213 },
    ["Lady Anacondra"]        = { npc = 3671, display = 4313 },
    ["Kresh"]                 = { npc = 3653, display = 5126 },
    ["Lord Pythas"]           = { npc = 3670, display = 4214 },
    ["Skum"]                  = { npc = 3674, display = 4203 },
    ["Lord Serpentis"]        = { npc = 3673, display = 4215 },
    ["Verdan the Everliving"] = { npc = 5775, display = 4256 },
    ["Mutanus the Devourer"]  = { npc = 3654, display = 4088 },
    ["Deviate Faerie Dragon"] = { npc = 5912, display = 1267 },

    -- Shadowfang Keep
    ["Rethilgore"]                 = { npc = 3914, display = 524 },
    ["Fel Steed / Shadow Charger"] = { npc = 3864, display = 1951 },
    ["Razorclaw the Butcher"]      = { npc = 3886, display = 524 },
    ["Baron Silverlaine"]          = { npc = 3887, display = 3222 },
    ["Commander Springvale"]       = { npc = 4278, display = 3223 },
    ["Odo the Blindwatcher"]       = { npc = 4279, display = 522 },
    ["Deathsworn Captain"]         = { npc = 3872, display = 3224 },
    ["Arugal's Voidwalker"]        = { npc = 4627, display = 1131 },
    ["Fenrus the Devourer"]        = { npc = 4274, display = 2352 },
    ["Wolf Master Nandos"]         = { npc = 3927, display = 11179 },
    ["Archmage Arugal"]            = { npc = 4275, display = 2353 },

    -- The Stockade
    ["Targorr the Dread"]   = { npc = 1696, display = 517 },
    ["Kam Deepfury"]        = { npc = 1666, display = 825 },
    ["Hamhock"]             = { npc = 1717, display = 3250 },
    ["Dextren Ward"]        = { npc = 1663, display = 2149 },
    ["Bazil Thredd"]        = { npc = 1716, display = 1621 },
    ["Bruegal Ironknuckle"] = { npc = 1720, display = 2142 },

    -- Blackfathom Deeps
    ["Ghamoo-ra"]            = { npc = 4887,  display = 5027 },
    ["Lady Sarevess"]        = { npc = 4831,  display = 4979 },
    ["Gelihast"]             = { npc = 6243,  display = 1773 },
    ["Lorgus Jett"]          = { npc = 12902, display = 12822 },
    ["Baron Aquanis"]        = { npc = 12876, display = 110 },
    ["Old Serra'kis"]        = { npc = 4830,  display = 1816 },
    ["Twilight Lord Kelris"] = { npc = 4832,  display = 4939 },
    ["Aku'mai"]              = { npc = 4829,  display = 2837 },

    -- The Drowned City
    ["Zul'Alai"]               = { npc = 258905, display = 144475 },
    ["Var'Taka"]               = { npc = 258924, display = 144487 },
    ["Captain Dreadrise"]      = { npc = 260042, display = 142144 },
    ["Deathless Marrow"]       = { npc = 270885, display = 142245 },
    ["Primeval Elemental"]     = { npc = 270887, display = 129945 },
    ["Gill"]                   = { npc = 264177, display = 144023 },
    ["Umbra"]                  = { npc = 264172, display = 144022 },
    ["\"Pyromancer\" Braxton"] = { npc = 260468, display = 142457 },
    ["Min'loth the Serpent"]   = { npc = 260274, display = 142322 },
}

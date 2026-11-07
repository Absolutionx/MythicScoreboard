-- Boss portrait display IDs for WoW Forever dungeons.
-- Loaded only by MythicScoreboard_Forever.toc.
--
-- Data from ForeverDungeonJournal by Exehn (Data/Dungeons.lua npcIDs and
-- Data/Bosses.lua STATIC_DISPLAY_IDS; v1.6.6, checked against v1.7.2), so medallions have portraits
-- without that addon installed. The game draws each portrait from its own
-- model files; nothing here is artwork.
--
-- [dungeon][boss name or alias] = creature display ID.
-- Magmatus has no model entry yet and uses a game icon instead.

local MS = _G["MythicScoreboard"]

MS.FOREVER_BOSS_ICONS = {
    ["Hall of Thanes"] = {
        ["Magmatus"] = "Interface\\Icons\\Spell_Fire_Elemental_Totem",
        ["Infurnus"] = "Interface\\Icons\\Spell_Fire_Elemental_Totem",
    },
}

MS.FOREVER_BOSS_DISPLAY = {
    ["Hall of Thanes"] = {
        ["Faldrim Anvilmar"] = 142826,              -- npc 261306
        ["Plunder"] = 142840,                       -- npc 261311
        ["Durgen Dirgehammer"] = 142837,            -- npc 261319
    },
    ["Ragefire Chasm"] = {
        ["Oggleflint"] = 11611,                     -- npc 11517
        ["Taragaman the Hungerer"] = 7970,          -- npc 11520
        ["Jergosh the Invoker"] = 11429,            -- npc 11518
        ["Bazzalan"] = 2007,                        -- npc 11519
    },
    ["Ruins of Lordaeron"] = {
        ["The Baron"] = 144188,                     -- npc 250660
        ["The Butcher"] = 144188,                   -- alias of The Baron
        ["Witherfang"] = 144189,                    -- npc 250483
        ["The Abandoned"] = 138667,                 -- npc 250631
        ["Bjork"] = 144170,                         -- npc 256097
        ["Rath'mael"] = 144175,                     -- npc 250657
        ["Rath’mael"] = 144175,                     -- alias of Rath'mael
        ["Viktor the Vile"] = 139455,               -- npc 256035
    },
    ["Wailing Caverns"] = {
        ["Lord Cobrahn"] = 4213,                    -- npc 3669
        ["Lady Anacondra"] = 4313,                  -- npc 3671
        ["Kresh"] = 5126,                           -- npc 3653
        ["Lord Pythas"] = 4214,                     -- npc 3670
        ["Skum"] = 4203,                            -- npc 3674
        ["Lord Serpentis"] = 4215,                  -- npc 3673
        ["Verdan the Everliving"] = 4256,           -- npc 5775
        ["Mutanus the Devourer"] = 4088,            -- npc 3654
        ["Deviate Faerie Dragon"] = 1267,           -- npc 5912
    },
    ["The Deadmines"] = {
        ["Rhahk'Zor"] = 14403,                      -- npc 644
        ["Miner Johnson"] = 556,                    -- npc 3586
        ["Sneed's Shredder"] = 1269,                -- npc 642
        ["Sneed"] = 7125,                           -- npc 643
        ["Gilnid"] = 7124,                          -- npc 1763
        ["Mr. Smite"] = 2026,                       -- npc 646
        ["Captain Greenskin"] = 7113,               -- npc 647
        ["Edwin VanCleef"] = 2029,                  -- npc 639
        ["Cookie"] = 1305,                          -- npc 645
    },
    ["Shadowfang Keep"] = {
        ["Rethilgore"] = 524,                       -- npc 3914
        ["Fel Steed / Shadow Charger"] = 1951,      -- npc 3864
        ["Fel Steed"] = 1951,                       -- alias of Fel Steed / Shadow Charger
        ["Shadow Charger"] = 1951,                  -- alias of Fel Steed / Shadow Charger
        ["Razorclaw the Butcher"] = 524,            -- npc 3886
        ["Baron Silverlaine"] = 3222,               -- npc 3887
        ["Commander Springvale"] = 3223,            -- npc 4278
        ["Odo the Blindwatcher"] = 522,             -- npc 4279
        ["Deathsworn Captain"] = 3224,              -- npc 3872
        ["Arugal's Voidwalker"] = 1131,             -- npc 4627
        ["Arugal’s Voidwalker"] = 1131,             -- alias of Arugal's Voidwalker
        ["Fenrus the Devourer"] = 2352,             -- npc 4274
        ["Wolf Master Nandos"] = 11179,             -- npc 3927
        ["Archmage Arugal"] = 2353,                 -- npc 4275
    },
    ["Blackfathom Deeps"] = {
        ["Ghamoo-ra"] = 5027,                       -- npc 4887
        ["Lady Sarevess"] = 4979,                   -- npc 4831
        ["Gelihast"] = 1773,                        -- npc 6243
        ["Geilhast"] = 1773,                        -- alias of Gelihast
        ["Lorgus Jett"] = 12822,                    -- npc 12902
        ["Old Serra'kis"] = 1816,                   -- npc 4830
        ["Old Serra’kis"] = 1816,                   -- alias of Old Serra'kis
        ["Twilight Lord Kelris"] = 4939,            -- npc 4832
        ["Aku'mai"] = 2837,                         -- npc 4829
        ["Aku’mai"] = 2837,                         -- alias of Aku'mai
    },
    ["The Stockade"] = {
        ["Targorr the Dread"] = 517,                -- npc 1696
        ["Kam Deepfury"] = 825,                     -- npc 1666
        ["Hamhock"] = 3250,                         -- npc 1717
        ["Dextren Ward"] = 2149,                    -- npc 1663
        ["Bazil Thredd"] = 1621,                    -- npc 1716
        ["Bruegal Ironknuckle"] = 2142,             -- npc 1720
    },
    ["Excavation Site: Wetlands"] = {
        ["Saltspine"] = 144209,                     -- npc 260322
        ["Shadetooth"] = 144210,                    -- npc 260325
        ["Relic Guardian"] = 144224,                -- npc 260326
    },
    ["City of Dalaran"] = {
        ["Atrexis the Grave Knight"] = 145787,      -- npc 247126
        ["Arcane Anomaly"] = 129891,                -- npc 245999
        ["Fel Ancient"] = 129894,                   -- npc 246003
        ["Unstable Sentinel"] = 129954,             -- npc 246017
        ["Mana Devourer"] = 129895,                 -- npc 246008
        ["Arcanic Enigma"] = 129900,                -- npc 246016
        ["Mana Elemental"] = 129900,                -- alias of Arcanic Enigma
        ["Lyn the Ignored"] = 130235,               -- npc 247032
        ["Shade of the Archmage"] = 130061,         -- npc 246020
    },
    ["Gnomeregan"] = {
        ["Grubbis"] = 144378,                       -- npc 7361
        ["Viscous Fallout"] = 5497,                 -- npc 7079
        ["Electrocutioner 6000"] = 6915,            -- npc 6235
        ["Crowd Pummeler 9-60"] = 6774,             -- npc 6229
        ["Mekgineer Thermaplugg"] = 6980,           -- npc 7800
        ["Dark Iron Ambassador"] = 6669,            -- npc 6228
    },
    ["Razorfen Kraul"] = {
        ["Roogug"] = 6110,                          -- npc 6168
        ["Aggem Thorncurse"] = 6097,                -- npc 4424
        ["Death Speaker Jargba"] = 4644,            -- npc 4428
        ["Overlord Ramtusk"] = 4652,                -- npc 4420
        ["Agathelos the Raging"] = 2450,            -- npc 4422
        ["Charlga Razorflank"] = 4642,              -- npc 4421
        ["Blind Hunter"] = 4735,                    -- npc 4425
        ["Earthcaller Halmgar"] = 6102,             -- npc 4842
    },
    ["Scarlet Monastery: Graveyard"] = {
        ["Interrogator Vishas"] = 2044,             -- npc 3983
        ["Azshir the Sleepless"] = 5534,            -- npc 6490
        ["Fallen Champion"] = 5230,                 -- npc 6488
        ["Ironspine"] = 5231,                       -- npc 6489
        ["Bloodmage Thalnos"] = 11396,              -- npc 4543
    },
    ["Scarlet Monastery: Library"] = {
        ["Houndmaster Loksey"] = 2040,              -- npc 3974
        ["Arcanist Doan"] = 5266,                   -- npc 6487
    },
    ["Scarlet Monastery: Armory"] = {
        ["Herod"] = 2041,                           -- npc 3975
        ["Herod, the Scarlet Champion"] = 2041,     -- alias of Herod
    },
    ["Scarlet Monastery: Cathedral"] = {
        ["High Inquisitor Fairbanks"] = 2605,       -- npc 4542
        ["Fairbanks"] = 2605,                       -- alias of High Inquisitor Fairbanks
        ["Scarlet Commander Mograine"] = 2042,      -- npc 3976
        ["Mograine"] = 2042,                        -- alias of Scarlet Commander Mograine
        ["High Inquisitor Whitemane"] = 2043,       -- npc 3977
        ["Whitemane"] = 2043,                       -- alias of High Inquisitor Whitemane
    },
    ["Razorfen Downs"] = {
        ["Tuten'kash"] = 7845,                      -- npc 7355
        ["Mordresh Fire Eye"] = 8055,               -- npc 7357
        ["Glutton"] = 7864,                         -- npc 8567
        ["Ragglesnout"] = 11382,                    -- npc 7354
        ["Plaguemaw the Rotting"] = 6124,           -- npc 7356
        ["Plaguemaw"] = 6124,                       -- alias of Plaguemaw the Rotting
        ["Amnennar the Coldbringer"] = 7971,        -- npc 7358
        ["Amnennar"] = 7971,                        -- alias of Amnennar the Coldbringer
    },
    ["Uldaman"] = {
        ["Revelosh"] = 5945,                        -- npc 6910
        ["The Lost Dwarves"] = 5710,                -- npc 6906
        ["Baelog"] = 5710,                          -- alias of The Lost Dwarves
        ["Eric \"The Swift\""] = 5710,              -- alias of The Lost Dwarves
        ["Olaf"] = 5710,                            -- alias of The Lost Dwarves
        ["Ironaya"] = 6089,                         -- npc 7228
        ["Ancient Stone Keeper"] = 10798,           -- npc 7206
        ["Galgann Firehammer"] = 6059,              -- npc 7291
        ["Grimlok"] = 11165,                        -- npc 4854
        ["Archaedas"] = 5988,                       -- npc 2748
    },
    ["Zul'Farrak"] = {
        ["Antu'sul"] = 7353,                        -- npc 8127
        ["Witch Doctor Zum'rah"] = 6434,            -- npc 7271
        ["Shadowpriest Sezz'ziz"] = 6441,           -- npc 7275
        ["Gahz'rilla"] = 7271,                      -- npc 7273
        ["Zerillis"] = 9293,                        -- npc 10082
        ["Sandarr Dunereaver"] = 9291,              -- npc 10080
        ["Dustwraith"] = 9292,                      -- npc 10081
        ["Ruuzlu"] = 6687,                          -- npc 7797
        ["Chief Ukorz Sandscalp"] = 6439,           -- npc 7267
    },
    ["Maraudon"] = {
        ["Noxxion"] = 11172,                        -- npc 13282
        ["Razorlash"] = 12389,                      -- npc 12258
        ["Lord Vyletongue"] = 12334,                -- npc 12236
        ["Meshlok the Harvester"] = 9014,           -- npc 12237
        ["Celebras the Cursed"] = 12350,            -- npc 12225
        ["Landslide"] = 12293,                      -- npc 12203
        ["Tinkerer Gizlock"] = 7125,                -- npc 13601
        ["Rotgrip"] = 13589,                        -- npc 13596
        ["Princess Theradras"] = 12292,             -- npc 12201
    },
    ["Sunken Temple"] = {
        ["Atal'alarion"] = 7873,                    -- npc 8580
        ["Dreamscythe"] = 7553,                     -- npc 5721
        ["Weaver"] = 6375,                          -- npc 5720
        ["Avatar of Hakkar"] = 8053,                -- npc 8443
        ["Jammal'an the Prophet"] = 6708,           -- npc 5710
        ["Ogom the Wretched"] = 6709,               -- npc 5711
        ["Morphaz"] = 7975,                         -- npc 5719
        ["Hazzas"] = 9584,                          -- npc 5722
        ["Shade of Eranikus"] = 7806,               -- npc 5709
    },
    ["Blackrock Depths"] = {
        ["High Interrogator Gerstahn"] = 8761,      -- npc 9018
        ["Lord Roccor"] = 5781,                     -- npc 9025
        ["Houndmaster Grebmar"] = 9212,             -- npc 9319
        ["Gorosh the Dervish"] = 8760,              -- npc 9027
        ["Grizzle"] = 7873,                         -- npc 9028
        ["Eviscerator"] = 523,                      -- npc 9029
        ["Ok'thor the Breaker"] = 11538,            -- npc 9030
        ["Anub'shiah"] = 3004,                      -- npc 9031
        ["Hedrum the Creeper"] = 8271,              -- npc 9032
        ["Pyromancer Loregrain"] = 8762,            -- npc 9024
        ["Fineous Darkvire"] = 8704,                -- npc 9056
        ["Warder Stilgiss"] = 9089,                 -- npc 9041
        ["Lord Incendius"] = 1204,                  -- npc 9017
        ["Bael'Gar"] = 12162,                       -- npc 9016
        ["General Angerforge"] = 8756,              -- npc 9033
        ["Golem Lord Argelmach"] = 8759,            -- npc 8983
        ["Hurley Blackbreath"] = 8658,              -- npc 9537
        ["Phalanx"] = 8177,                         -- npc 9502
        ["Ribbly Screwspigot"] = 8667,              -- npc 9543
        ["Plugger Spazzring"] = 8652,               -- npc 9499
        ["Ambassador Flamelash"] = 8329,            -- npc 9156
        ["Panzor the Invincible"] = 8270,           -- npc 8923
        ["The Seven"] = 8687,                       -- npc 9039
        ["Doom'rel"] = 8687,                        -- alias of The Seven
        ["Hate'rel"] = 8687,                        -- alias of The Seven
        ["Anger'rel"] = 8687,                       -- alias of The Seven
        ["Vile'rel"] = 8687,                        -- alias of The Seven
        ["Gloom'rel"] = 8687,                       -- alias of The Seven
        ["Seeth'rel"] = 8687,                       -- alias of The Seven
        ["Dope'rel"] = 8687,                        -- alias of The Seven
        ["Magmus"] = 12162,                         -- npc 9938
        ["Princess Moira Bronzebeard"] = 8705,      -- npc 8929
        ["Emperor Dagran Thaurissan"] = 8807,       -- npc 9019
    },
    ["Dire Maul: East"] = {
        ["Zevrim Thornhoof"] = 11335,               -- npc 11490
        ["Hydrospawn"] = 5489,                      -- npc 13280
        ["Lethtendris"] = 14378,                    -- npc 14327
        ["Alzzin the Wildshaper"] = 14416,          -- npc 11492
    },
    ["Lower Blackrock Spire"] = {
        ["Spirestone Butcher"] = 11574,             -- npc 9219
        ["Spirestone Battle Lord"] = 11576,         -- npc 9218
        ["Spirestone Lord Magus"] = 11578,          -- npc 9217
        ["Highlord Omokk"] = 11565,                 -- npc 9196
        ["Shadow Hunter Vosh'gajin"] = 9732,        -- npc 9236
        ["War Master Voone"] = 9733,                -- npc 9237
        ["Mother Smolderweb"] = 9929,               -- npc 10596
        ["Crystal Fang"] = 9755,                    -- npc 10376
        ["Urok Doomhowl"] = 11583,                  -- npc 10584
        ["Bannok Grimaxe"] = 9668,                  -- npc 9596
        ["Quartermaster Zigris"] = 9738,            -- npc 9736
        ["Halycon"] = 9567,                         -- npc 10220
        ["Gizrul the Slavener"] = 9564,             -- npc 10268
        ["Ghok Bashguud"] = 11809,                  -- npc 9718
        ["Overlord Wyrmthalak"] = 8711,             -- npc 9568
    },
    ["Upper Blackrock Spire"] = {
        ["Pyroguard Emberseer"] = 2172,             -- npc 9816
        ["Solakar Flamewreath"] = 9581,             -- npc 10264
        ["Jed Runewatcher"] = 9686,                 -- npc 10509
        ["Goraluk Anvilcrack"] = 10222,             -- npc 10899
        ["Gyth"] = 9806,                            -- npc 10339
        ["Warchief Rend Blackhand"] = 9778,         -- npc 10429
        ["The Beast"] = 10193,                      -- npc 10430
        ["Lord Valthalak"] = 14308,                 -- npc 16042
        ["General Drakkisath"] = 10115,             -- npc 10363
    },
    ["Dire Maul: North"] = {
        ["Guard Mol'dar"] = 11561,                  -- npc 14326
        ["Stomper Kreeg"] = 11545,                  -- npc 14322
        ["Guard Fengus"] = 11561,                   -- npc 14321
        ["Guard Slip'kik"] = 11561,                 -- npc 14323
        ["Captain Kromcrush"] = 11564,              -- npc 14325
        ["Cho'Rush the Observer"] = 11537,          -- npc 14324
        ["King Gordok"] = 11583,                    -- npc 11501
    },
    ["Dire Maul: West"] = {
        ["Tendris Warpwood"] = 14383,               -- npc 11489
        ["Illyanna Ravenoak"] = 11270,              -- npc 11488
        ["Tsu'zee"] = 11250,                        -- npc 11467
        ["Magister Kalendris"] = 14384,             -- npc 11487
        ["Immol'thar"] = 14173,                     -- npc 11496
        ["Lord Hel'nurath"] = 14556,                -- npc 14506
        ["Prince Tortheldrin"] = 11256,             -- npc 11486
    },
    ["Scholomance"] = {
        ["Kirtonos the Herald"] = 143673,           -- npc 10506
        ["Jandice Barov"] = 11073,                  -- npc 10503
        ["Rattlegore"] = 12073,                     -- npc 11622
        ["Marduk Blackpool"] = 10248,               -- npc 10433
        ["Vectus"] = 2606,                          -- npc 10432
        ["Ras Frostwhisper"] = 7919,                -- npc 10508
        ["Instructor Malicia"] = 11069,             -- npc 10505
        ["Doctor Theolen Krastinov"] = 10901,       -- npc 11261
        ["Lorekeeper Polkelt"] = 11492,             -- npc 10901
        ["The Ravenian"] = 10433,                   -- npc 10507
        ["Lord Alexei Barov"] = 11072,              -- npc 10504
        ["Lady Illucia Barov"] = 11835,             -- npc 10502
        ["Darkmaster Gandling"] = 11070,            -- npc 1853
    },
    ["Stratholme: Living"] = {
        ["Skul"] = 2606,                            -- npc 10393
        ["Hearthsinger Forresten"] = 10482,         -- npc 10558
        ["The Unforgiven"] = 10771,                 -- npc 10516
        ["Timmy the Cruel"] = 571,                  -- npc 10808
        ["Postmaster Malown"] = 10669,              -- npc 11143
        ["Cannon Master Willey"] = 10674,           -- npc 10997
        ["Archivist Galford"] = 10544,              -- npc 10811
        ["Balnazzar"] = 10691,                      -- npc 10813
    },
    ["Stratholme: Undead"] = {
        ["Stonespine"] = 7856,                      -- npc 10809
        ["Magistrate Barthilas"] = 10433,           -- npc 10435
        ["Nerub'enkan"] = 9793,                     -- npc 10437
        ["Baroness Anastari"] = 10698,              -- npc 10436
        ["Maleki the Pallid"] = 10546,              -- npc 10438
        ["Ramstein the Gorger"] = 12818,            -- npc 10439
        ["Baron Rivendare"] = 10729,                -- npc 10440
    },
}

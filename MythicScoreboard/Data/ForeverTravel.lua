local MS = _G["MythicScoreboard"]

-- ── Getting around (WoW Forever): the route planner's map ─────────────────
-- Flight masters and the boats and zeppelins between the continents, each on
-- its zone's map (x, y from 0 to 1), for Core/Travel.lua.
--
-- Flight masters: classic's positions, close, not exact; the game corrects
-- them: open any flight map and the addon learns every flight master on that
-- continent, where it really stands and which ones you know (Travel.lua,
-- TAXIMAP_OPENED). Boats, zeppelins and the tram: where you board.
--
-- Inns and teleports: where you land is learned from the game the first
-- time you hearth or teleport there (Travel.lua), for every character on
-- the account. Until then, INNS: each innkeeper's spot (/sb dumptravel
-- collects the learned ones, to add to it).
--
-- side: "Horde", "Alliance", or nil for both.

local D = MS.ForeverData or {}
MS.ForeverData = D

D.FLIGHT_MASTERS = {
    -- Kalimdor, Horde
    { "Orgrimmar",              map = 1454, x = 0.451, y = 0.639, side = "Horde" },
    { "Crossroads",             map = 1413, x = 0.515, y = 0.303, side = "Horde" },
    { "Camp Taurajo",           map = 1413, x = 0.444, y = 0.591, side = "Horde" },
    { "Thunder Bluff",          map = 1456, x = 0.470, y = 0.498, side = "Horde" },
    { "Sun Rock Retreat",       map = 1442, x = 0.451, y = 0.598, side = "Horde" },
    { "Splintertree Post",      map = 1440, x = 0.732, y = 0.616, side = "Horde" },
    { "Zoram'gar Outpost",      map = 1440, x = 0.122, y = 0.338, side = "Horde" },
    { "Shadowprey Village",     map = 1443, x = 0.216, y = 0.741, side = "Horde" },
    { "Freewind Post",          map = 1441, x = 0.451, y = 0.491, side = "Horde" },
    { "Brackenwall Village",    map = 1445, x = 0.356, y = 0.319, side = "Horde" },
    { "Camp Mojache",           map = 1444, x = 0.754, y = 0.443, side = "Horde" },
    { "Valormok",               map = 1447, x = 0.220, y = 0.496, side = "Horde" },
    { "Bloodvenom Post",        map = 1448, x = 0.344, y = 0.539, side = "Horde" },
    { "Moonglade",              map = 1450, x = 0.321, y = 0.666, side = "Horde" },
    -- Kalimdor, Alliance
    { "Rut'theran Village",     map = 1438, x = 0.584, y = 0.940, side = "Alliance" },
    { "Auberdine",              map = 1439, x = 0.363, y = 0.456, side = "Alliance" },
    { "Astranaar",              map = 1440, x = 0.344, y = 0.480, side = "Alliance" },
    { "Stonetalon Peak",        map = 1442, x = 0.364, y = 0.072, side = "Alliance" },
    { "Nijel's Point",          map = 1443, x = 0.647, y = 0.105, side = "Alliance" },
    { "Thalanaar",              map = 1444, x = 0.895, y = 0.459, side = "Alliance" },
    { "Feathermoon Stronghold", map = 1444, x = 0.302, y = 0.432, side = "Alliance" },
    { "Theramore",              map = 1445, x = 0.675, y = 0.513, side = "Alliance" },
    { "Talonbranch Glade",      map = 1448, x = 0.625, y = 0.242, side = "Alliance" },
    { "Talrendis Point",        map = 1447, x = 0.119, y = 0.776, side = "Alliance" },
    { "Moonglade",              map = 1450, x = 0.481, y = 0.673, side = "Alliance" },
    -- Kalimdor, both: one flight master for everyone, or one for each side
    { "Ratchet",                map = 1413, x = 0.631, y = 0.372 },
    { "Marshal's Refuge",       map = 1449, x = 0.452, y = 0.058 },
    { "Gadgetzan",              map = 1446, x = 0.516, y = 0.255, side = "Horde" },
    { "Gadgetzan",              map = 1446, x = 0.510, y = 0.293, side = "Alliance" },
    { "Everlook",               map = 1452, x = 0.605, y = 0.363, side = "Horde" },
    { "Everlook",               map = 1452, x = 0.623, y = 0.366, side = "Alliance" },
    { "Cenarion Hold",          map = 1451, x = 0.488, y = 0.367, side = "Horde" },
    { "Cenarion Hold",          map = 1451, x = 0.507, y = 0.346, side = "Alliance" },
    -- Mount Hyjal (WoW Forever)
    { "Summit of Eternity",     map = 2482, x = 0.686, y = 0.441 },
    { "Tainted Foothills",      map = 2482, x = 0.551, y = 0.825 },
    -- Eastern Kingdoms, Horde
    { "Undercity",              map = 1458, x = 0.633, y = 0.485, side = "Horde" },
    { "The Sepulcher",          map = 1421, x = 0.456, y = 0.426, side = "Horde" },
    { "Tarren Mill",            map = 1424, x = 0.601, y = 0.186, side = "Horde" },
    { "Hammerfall",             map = 1417, x = 0.730, y = 0.326, side = "Horde" },
    { "Revantusk Village",      map = 1425, x = 0.817, y = 0.818, side = "Horde" },
    { "Kargath",                map = 1418, x = 0.040, y = 0.448, side = "Horde" },
    { "Flame Crest",            map = 1428, x = 0.656, y = 0.242, side = "Horde" },
    { "Stonard",                map = 1435, x = 0.461, y = 0.548, side = "Horde" },
    { "Grom'gol Base Camp",     map = 1434, x = 0.325, y = 0.294, side = "Horde" },
    -- Eastern Kingdoms, Alliance
    { "Stormwind",              map = 1453, x = 0.663, y = 0.621, side = "Alliance" },
    { "Ironforge",              map = 1455, x = 0.555, y = 0.477, side = "Alliance" },
    { "Sentinel Hill",          map = 1436, x = 0.566, y = 0.526, side = "Alliance" },
    { "Lakeshire",              map = 1433, x = 0.306, y = 0.594, side = "Alliance" },
    { "Darkshire",              map = 1431, x = 0.775, y = 0.443, side = "Alliance" },
    { "Thelsamar",              map = 1432, x = 0.339, y = 0.509, side = "Alliance" },
    { "Menethil Harbor",        map = 1437, x = 0.095, y = 0.597, side = "Alliance" },
    { "Southshore",             map = 1424, x = 0.493, y = 0.523, side = "Alliance" },
    { "Refuge Pointe",          map = 1417, x = 0.458, y = 0.461, side = "Alliance" },
    { "Aerie Peak",             map = 1425, x = 0.111, y = 0.462, side = "Alliance" },
    { "Chillwind Camp",         map = 1422, x = 0.429, y = 0.851, side = "Alliance" },
    { "Morgan's Vigil",         map = 1428, x = 0.843, y = 0.683, side = "Alliance" },
    { "Nethergarde Keep",       map = 1419, x = 0.655, y = 0.243, side = "Alliance" },
    -- Eastern Kingdoms, one for each side
    { "Booty Bay",              map = 1434, x = 0.268, y = 0.770, side = "Horde" },
    { "Booty Bay",              map = 1434, x = 0.274, y = 0.778, side = "Alliance" },
    { "Thorium Point",          map = 1427, x = 0.348, y = 0.306, side = "Horde" },
    { "Thorium Point",          map = 1427, x = 0.378, y = 0.306, side = "Alliance" },
    { "Light's Hope Chapel",    map = 1423, x = 0.802, y = 0.570, side = "Horde" },
    { "Light's Hope Chapel",    map = 1423, x = 0.816, y = 0.592, side = "Alliance" },
    -- The Riverglades and Dun Morogh's coast (WoW Forever)
    { "Rog'mar",                map = 2548, x = 0.596, y = 0.451, side = "Horde" },
    { "Farholde Keep",          map = 2548, x = 0.606, y = 0.814, side = "Alliance" },
    { "Powderfuse Port",        map = 2548, x = 0.790, y = 0.523 },
    { "Tidegear Coast",         map = 1426, x = 0.190, y = 0.152 },
}

-- Inns, by the name the game gives your hearthstone's place (the town, not
-- the innkeeper): { name, map, x, y, side, aka = other names it may give }.
-- The innkeeper's spot; a landing learned in game replaces it. English
-- names: in other languages only learned landings are used.
D.INNS = {
    -- Kalimdor
    { "Orgrimmar",              map = 1454, x = 0.541, y = 0.685, side = "Horde" },          -- Gryshka
    { "Razor Hill",             map = 1411, x = 0.516, y = 0.417, side = "Horde" },          -- Grosk
    { "Crossroads",             map = 1413, x = 0.520, y = 0.299, side = "Horde", aka = { "The Crossroads" } },  -- Boorand Plainswind
    { "Camp Taurajo",           map = 1413, x = 0.455, y = 0.590, side = "Horde" },          -- Byula
    { "Ratchet",                map = 1413, x = 0.620, y = 0.394 },                          -- Wiley
    { "Bloodhoof Village",      map = 1412, x = 0.459, y = 0.642, side = "Horde" },          -- Kauth
    { "Thunder Bluff",          map = 1456, x = 0.458, y = 0.647, side = "Horde" },          -- Pala
    { "Freewind Post",          map = 1441, x = 0.461, y = 0.515, side = "Horde" },          -- Abeqwa
    { "Shadowprey Village",     map = 1443, x = 0.242, y = 0.683, side = "Horde" },          -- Sikewa
    { "Dolanaar",               map = 1438, x = 0.557, y = 0.598, side = "Alliance" },       -- Keldamyr
    { "Darnassus",              map = 1457, x = 0.674, y = 0.156, side = "Alliance" },       -- Saelienne
    { "Theramore Isle",         map = 1445, x = 0.666, y = 0.452, side = "Alliance", aka = { "Theramore" } },  -- Janene
    { "Feathermoon Stronghold", map = 1444, x = 0.310, y = 0.435, side = "Alliance", aka = { "Feathermoon" } },  -- Shyria
    { "Gadgetzan",              map = 1446, x = 0.525, y = 0.279 },                          -- Fizzgrimble
    { "Everlook",               map = 1452, x = 0.614, y = 0.388 },                          -- Vizzie
    { "Cenarion Hold",          map = 1451, x = 0.519, y = 0.392 },                          -- Calandrath
    { "Camp Mojache",           map = 1444, x = 0.748, y = 0.452, side = "Horde" },          -- Greul
    { "Splintertree Post",      map = 1440, x = 0.740, y = 0.621, side = "Horde" },          -- Kaylisk
    { "Sun Rock Retreat",       map = 1442, x = 0.474, y = 0.620, side = "Horde" },          -- Jayka
    { "Brackenwall Village",    map = 1445, x = 0.365, y = 0.322, side = "Horde" },          -- "Little" Logok
    { "Astranaar",              map = 1440, x = 0.360, y = 0.495, side = "Alliance" },       -- Kimlya
    { "Auberdine",              map = 1439, x = 0.370, y = 0.444, side = "Alliance" },       -- Shaussiy
    { "Nijel's Point",          map = 1443, x = 0.663, y = 0.066, side = "Alliance" },       -- Lyshaerya
    { "Summit of Eternity",     map = 2482, x = 0.708, y = 0.514 },                          -- Sebelia (WoW Forever)
    -- Eastern Kingdoms
    { "Undercity",              map = 1458, x = 0.677, y = 0.379, side = "Horde" },          -- Norman
    { "Brill",                  map = 1420, x = 0.617, y = 0.521, side = "Horde" },          -- Renee
    { "Tarren Mill",            map = 1424, x = 0.628, y = 0.190, side = "Horde" },          -- Shay
    { "Hammerfall",             map = 1417, x = 0.738, y = 0.325, side = "Horde" },          -- Adegwa
    { "Revantusk Village",      map = 1425, x = 0.781, y = 0.814, side = "Horde" },          -- Lard
    { "Grom'gol Base Camp",     map = 1434, x = 0.315, y = 0.298, side = "Horde", aka = { "Grom'gol" } },  -- Thulbek
    { "Stormwind City",         map = 1453, x = 0.606, y = 0.750, side = "Alliance", aka = { "Stormwind" } },  -- Allison
    { "Goldshire",              map = 1429, x = 0.438, y = 0.658, side = "Alliance" },       -- Farley
    { "Ironforge",              map = 1455, x = 0.181, y = 0.515, side = "Alliance" },       -- Firebrew
    { "Kharanos",               map = 1426, x = 0.474, y = 0.525, side = "Alliance" },       -- Belm
    { "Menethil Harbor",        map = 1437, x = 0.108, y = 0.608, side = "Alliance" },       -- Helbrek
    { "Southshore",             map = 1424, x = 0.512, y = 0.590, side = "Alliance" },       -- Anderson
    { "Aerie Peak",             map = 1425, x = 0.138, y = 0.432, side = "Alliance" },       -- Thulfram
    { "The Sepulcher",          map = 1421, x = 0.434, y = 0.414, side = "Horde", aka = { "Sepulcher" } },  -- Bates
    { "Kargath",                map = 1418, x = 0.030, y = 0.460, side = "Horde" },          -- Shul'kar
    { "Stonard",                map = 1435, x = 0.452, y = 0.567, side = "Horde" },          -- Karakul
    { "Booty Bay",              map = 1434, x = 0.270, y = 0.773 },                          -- Skindle
    { "Lakeshire",              map = 1433, x = 0.268, y = 0.450, side = "Alliance" },       -- Brianna
    { "Darkshire",              map = 1431, x = 0.742, y = 0.471, side = "Alliance" },       -- Trelayne
    { "Sentinel Hill",          map = 1436, x = 0.529, y = 0.537, side = "Alliance" },       -- Heather
    { "Thelsamar",              map = 1432, x = 0.355, y = 0.484, side = "Alliance" },       -- Hearthstove
    -- The Riverglades (WoW Forever): the hub, not the inn's own spot
    { "Rog'mar",                map = 2548, x = 0.596, y = 0.451, side = "Horde" },          -- Toka
    { "Powderfuse Port",        map = 2548, x = 0.790, y = 0.523 },                          -- Zizplink
}

-- A mage's teleports. Where each lands: learned the first time it's cast.
D.TELEPORTS = {
    { spell = 3567, "Orgrimmar" },
    { spell = 3563, "Undercity" },
    { spell = 3566, "Thunder Bluff" },
    { spell = 3561, "Stormwind" },
    { spell = 3562, "Ironforge" },
    { spell = 3565, "Darnassus" },
}

-- Boats, zeppelins and the tram: two docks, one each end, where you stand
-- to board (WoW Forever's own routes and positions). kind: "boat",
-- "zeppelin", "airship" or "tram". oneway: it only goes from the first to the second.
D.TRANSPORTS = {
    -- Horde zeppelins (the towers outside Orgrimmar and Undercity, and Grom'gol)
    { kind = "zeppelin", side = "Horde",
      { "Orgrimmar",          map = 1411, x = 0.5082, y = 0.1381 },
      { "Undercity",          map = 1420, x = 0.6070, y = 0.5876 } },
    { kind = "zeppelin", side = "Horde",
      { "Orgrimmar",          map = 1411, x = 0.5057, y = 0.1266 },
      { "Grom'gol Base Camp", map = 1434, x = 0.3135, y = 0.3012 } },
    { kind = "zeppelin", side = "Horde",
      { "Undercity",          map = 1420, x = 0.6188, y = 0.5910 },
      { "Grom'gol Base Camp", map = 1434, x = 0.3153, y = 0.2915 } },
    -- Both sides
    { kind = "boat",
      { "Booty Bay",          map = 1434, x = 0.2592, y = 0.7315 },
      { "Ratchet",            map = 1413, x = 0.6366, y = 0.3865 } },
    { kind = "boat",
      { "Powderfuse Port",    map = 2548, x = 0.8030, y = 0.5440 },
      { "Steamwheedle Port",  map = 1446, x = 0.6834, y = 0.2298 } },
    -- The airships to Zephras Isle
    { kind = "airship", side = "Horde",
      { "Valanaar",           map = 2521, x = 0.5794, y = 0.8072 },
      { "Mulgore",            map = 1412, x = 0.3429, y = 0.2573 } },
    { kind = "airship", side = "Alliance",
      { "Valanaar",           map = 2521, x = 0.6582, y = 0.8342 },
      { "Dalaran",            map = 1416, x = 0.1252, y = 0.5196 } },
    -- Alliance
    { kind = "boat", side = "Alliance",
      { "Stormwind",          map = 1453, x = 0.2260, y = 0.5613 },
      { "Auberdine",          map = 1439, x = 0.3076, y = 0.4100 } },
    { kind = "boat", side = "Alliance",
      { "Rut'theran Village", map = 1438, x = 0.5486, y = 0.9679 },
      { "Auberdine",          map = 1439, x = 0.3319, y = 0.4013 } },
    { kind = "boat", side = "Alliance",
      { "Menethil Harbor",    map = 1437, x = 0.0508, y = 0.6340 },
      { "Theramore",          map = 1445, x = 0.7154, y = 0.5634 } },
    -- The loop: Auberdine to Menethil to Southshore and back to Auberdine.
    { kind = "boat", side = "Alliance", oneway = true,
      { "Auberdine",          map = 1439, x = 0.3239, y = 0.4380 },
      { "Menethil Harbor",    map = 1437, x = 0.0465, y = 0.5716 } },
    { kind = "boat", side = "Alliance", oneway = true,
      { "Menethil Harbor",    map = 1437, x = 0.0465, y = 0.5719 },
      { "Southshore",         map = 1424, x = 0.5060, y = 0.6971 } },
    { kind = "boat", side = "Alliance", oneway = true,
      { "Southshore",         map = 1424, x = 0.5060, y = 0.6971 },
      { "Auberdine",          map = 1439, x = 0.3239, y = 0.4380 } },
    { kind = "tram", side = "Alliance",
      { "Stormwind",          map = 1453, x = 0.6036, y = 0.1247 },
      { "Ironforge",          map = 1455, x = 0.7290, y = 0.5027 } },
}

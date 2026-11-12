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
    -- Kalimdor, both (one flight master for each side, side by side)
    { "Ratchet",                map = 1413, x = 0.631, y = 0.372 },
    { "Gadgetzan",              map = 1446, x = 0.516, y = 0.254 },
    { "Everlook",               map = 1452, x = 0.605, y = 0.363 },
    { "Marshal's Refuge",       map = 1449, x = 0.452, y = 0.058 },
    { "Cenarion Hold",          map = 1451, x = 0.487, y = 0.367 },
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
    -- Eastern Kingdoms, both
    { "Booty Bay",              map = 1434, x = 0.269, y = 0.771 },
    { "Thorium Point",          map = 1427, x = 0.349, y = 0.307 },
    { "Light's Hope Chapel",    map = 1423, x = 0.802, y = 0.570 },
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

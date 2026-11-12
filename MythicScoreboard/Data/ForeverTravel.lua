local MS = _G["MythicScoreboard"]

-- ── Getting around (WoW Forever): the route planner's map ─────────────────
-- Flight masters and the boats and zeppelins between the continents, each on
-- its zone's map (x, y from 0 to 1), for Core/Travel.lua.
--
-- Classic's positions, from memory of the old world: close, not exact. The
-- flight masters are corrected by the game itself: open any flight map and
-- the addon learns every flight master on that continent, where it really
-- stands and which ones you know (Travel.lua, TAXIMAP_OPENED). Boats and
-- zeppelins: walk to the dock, which is close enough for the arrow.
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

-- Boats and zeppelins: two docks, one each end. kind: "boat" or "zeppelin".
D.TRANSPORTS = {
    { kind = "zeppelin", side = "Horde",
      { "Orgrimmar",          map = 1411, x = 0.506, y = 0.126 },
      { "Undercity",          map = 1420, x = 0.607, y = 0.588 } },
    { kind = "zeppelin", side = "Horde",
      { "Orgrimmar",          map = 1411, x = 0.514, y = 0.143 },
      { "Grom'gol Base Camp", map = 1434, x = 0.316, y = 0.292 } },
    { kind = "zeppelin", side = "Horde",
      { "Undercity",          map = 1420, x = 0.619, y = 0.590 },
      { "Grom'gol Base Camp", map = 1434, x = 0.312, y = 0.300 } },
    { kind = "boat",
      { "Booty Bay",          map = 1434, x = 0.259, y = 0.731 },
      { "Ratchet",            map = 1413, x = 0.637, y = 0.386 } },
    { kind = "boat", side = "Alliance",
      { "Menethil Harbor",    map = 1437, x = 0.046, y = 0.571 },
      { "Theramore",          map = 1445, x = 0.715, y = 0.564 } },
    { kind = "boat", side = "Alliance",
      { "Menethil Harbor",    map = 1437, x = 0.050, y = 0.635 },
      { "Auberdine",          map = 1439, x = 0.324, y = 0.438 } },
    { kind = "boat", side = "Alliance",
      { "Auberdine",          map = 1439, x = 0.332, y = 0.403 },
      { "Rut'theran Village", map = 1438, x = 0.550, y = 0.969 } },
}

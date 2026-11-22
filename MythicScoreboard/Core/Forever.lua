-- WoW Forever support. Loaded only by MythicScoreboard_Forever.toc.
--
-- Forever has classic-era dungeons (plus new ones), Normal/Heroic only and no
-- Mythic+. Everything the scoreboard needs to know about those dungeons lives
-- in Data/ForeverDungeons.lua, so the addon works on its own. Boss portraits
-- are learned from the game as the bosses are met (Portraits.lua).

local MS = _G["MythicScoreboard"]
-- (How Forever differs from retail is in Flavor_Forever.lua.)

-- ── Dungeon data (Data/ForeverDungeons.lua) ──────────────────────────────
local DUNGEONS, INSTANCE_ALIASES, INSTANCE_IDS =
    MS.ForeverData.DUNGEONS, MS.ForeverData.INSTANCE_ALIASES, MS.ForeverData.INSTANCE_IDS

-- Normalise entries to { name=, rare=, summon=, aka= }.
for _, def in pairs(DUNGEONS) do
    for i, b in ipairs(def.bosses) do
        if type(b) == "string" then
            def.bosses[i] = { name = b }
        else
            b.name = b[1]; b[1] = nil
        end
    end
end
MS.FOREVER_DUNGEONS = DUNGEONS

local function Canonical(name)
    name = (name or ""):gsub("\226\128\153", "'")
    return INSTANCE_ALIASES[name] or name
end


-- The instance a dungeon key is part of: "Scarlet Monastery" for
-- "Scarlet Monastery: Library", its `instance` for Blackrock Spire's halves.
local function InstanceOf(key)
    local def = DUNGEONS[key]
    return (def and def.instance) or key:match("^(.-): ") or key
end
local function IsWingOf(key, name) return key ~= name and InstanceOf(key) == name end

-- ── Lookups ─────────────────────────────────────────────────────────────

-- Lower-cased, curly apostrophe made straight. Remembered: the same few
-- boss names are compared over and over while the scoreboard is open.
local Norm = MS.BossKey

local FINAL_NAMES = {}
for _, def in pairs(DUNGEONS) do
    if def.final then FINAL_NAMES[Norm(def.final)] = true end
end

-- Each boss's names (name and aka), normalised, worked out on first use.
local _names = setmetatable({}, { __mode = "k" })
local function Names(entry)
    local set = _names[entry]
    if not set then
        set = {}
        if entry.name then set[Norm(entry.name)] = true end
        for _, a in ipairs(entry.aka or {}) do set[Norm(a)] = true end
        _names[entry] = set
    end
    return set
end

local function EntryMatches(entry, name)
    local n = Norm(name)
    if not n or type(entry) ~= "table" then return false end
    return Names(entry)[n] == true
end

local function IsRequired(entry)
    return not entry.rare and not entry.summon
end


-- The run's dungeon as DUNGEONS names it: its own name, or (another
-- language) the name its instance ID stands for.
local _isBase = {}
for key in pairs(DUNGEONS) do _isBase[InstanceOf(key)] = true end
local function RunName(run)
    local name = Canonical(run and run.dungeonName)
    if DUNGEONS[name] or _isBase[name] then return name end
    return INSTANCE_IDS[run and run.instanceID or 0] or name
end

-- The lookups above, for the boss lists in ForeverBosses.lua.
MS.ForeverLib = {
    DUNGEONS = DUNGEONS, FINAL_NAMES = FINAL_NAMES, Norm = Norm,
    Canonical = Canonical, InstanceOf = InstanceOf, IsWingOf = IsWingOf,
    Names = Names, EntryMatches = EntryMatches, IsRequired = IsRequired, RunName = RunName,
}

-- ── Which wing, from where you are ─────────────────────────────────────────
-- Each wing is its own map. Its name (the map's, its floor's, or the
-- journal's) says which wing in English; whatever the language, a map is
-- remembered as the wing its bosses turned out to be, for next time.
local function WingMaps()
    local acc = MS.AccountDB()
    if not acc then return nil end
    acc.wingMaps = acc.wingMaps or {}
    return acc.wingMaps
end

local function MapNames(map)
    local out = {}
    local C = rawget(_G, "C_Map")
    if C and C.GetMapInfo then
        local ok, info = pcall(C.GetMapInfo, map)
        if ok and type(info) == "table" and type(info.name) == "string" then out[#out + 1] = info.name end
    end
    if C and C.GetMapGroupID and C.GetMapGroupMembersInfo then
        local ok, group = pcall(C.GetMapGroupID, map)
        local members
        if ok and group then
            local ok2, list = pcall(C.GetMapGroupMembersInfo, group)
            if ok2 and type(list) == "table" then members = list end
        end
        for _, m in ipairs(members or {}) do
            if m.mapID == map and type(m.name) == "string" then out[#out + 1] = m.name end
        end
    end
    local ForMap, Info = rawget(_G, "EJ_GetInstanceForMap"), rawget(_G, "EJ_GetInstanceInfo")
    if ForMap and Info then
        local ok, inst = pcall(ForMap, map)
        if ok and inst and inst ~= 0 then
            local ok2, ejName = pcall(Info, inst)
            if ok2 and type(ejName) == "string" then out[#out + 1] = ejName end
        end
    end
    return out
end

local function WingAt(run, name)
    local map = run.uiMapID
    if type(map) ~= "number" then return nil end
    local learned = WingMaps()
    learned = learned and learned[map]
    if learned and DUNGEONS[learned] and IsWingOf(learned, name) then return learned end
    local known = (MS.ForeverData.WING_MAPS or {})[map]
    if known and DUNGEONS[known] and IsWingOf(known, name) then return known end
    local names = MapNames(map)
    for key in pairs(DUNGEONS) do
        if IsWingOf(key, name) then
            local wing = (key:match(": (.+)$") or key):lower()
            for _, n in ipairs(names) do
                n = n:lower()
                if n == key:lower() or n == wing or n:find(wing, 1, true) then return key end
            end
        end
    end
end

-- Which dungeon a run is in, as DUNGEONS names it, and how that's known:
--   "name"    its name is a DUNGEONS key
--   "bosses"  the dungeon (or wing) holding the bosses the group has fought
--   "map"     the wing its map is (learned, or named after the wing)
-- Only reads: nothing on the run or in saved data changes (NoteForeverWing
-- below writes what's learned, for the run in progress). Remembered per run
-- until its name, boss count or map change.
local _resolved = setmetatable({}, { __mode = "k" })   -- run -> { sig, key, how }

local function BestByBosses(run, name)
    local best, bestScore
    for key, def in pairs(DUNGEONS) do
        local score = 0
        for _, b in ipairs(run.bosses or {}) do
            for _, e in ipairs(def.bosses) do
                if EntryMatches(e, b.name) then score = score + 1; break end
            end
        end
        if score > 0 and IsWingOf(key, name) then score = score + 0.5 end
        if score > 0 and (not bestScore or score > bestScore) then best, bestScore = key, score end
    end
    return best
end

local function Resolve(run)
    local name, nb = RunName(run), #(run.bosses or {})
    local sig = name .. "#" .. nb .. "#" .. tostring(run.uiMapID) .. "#" .. tostring(run.wingName)
    local hit = _resolved[run]
    if hit and hit.sig == sig then return hit.key, hit.how end
    local key, how
    if DUNGEONS[name] then
        key, how = name, "name"
    else
        key = nb > 0 and BestByBosses(run, name)
        if key then how = "bosses" else key = WingAt(run, name); how = key and "map" end
        -- The wing already worked out from where you are (RecheckWing).
        local w = run.wingName
        if not key and w and DUNGEONS[w] and IsWingOf(w, name) then key, how = w, "known" end
    end
    _resolved[run] = { sig = sig, key = key or nil, how = how }
    return key or nil, how
end

-- The run's dungeon entry and its key, or nil.
function MS:ForeverDungeon(run)
    if not run then return nil end
    local key = Resolve(run)
    if key then return DUNGEONS[key], key end
    return nil
end

-- The part of the dungeon you're in, by its name (GetSubZoneText).
local function SubZone()
    local fn = rawget(_G, "GetSubZoneText")
    local ok, z = pcall(fn or function() end)
    z = ok and MS.Readable(z)
    if z and z ~= "" then return z end
end
local function WingZones()
    local acc = MS.AccountDB()
    if not acc then return nil end
    acc.wingZones = acc.wingZones or {}
    return acc.wingZones
end
local function WingFromZone(name)
    local z = SubZone()
    if not z then return nil end
    local learned = WingZones()
    local w = learned and learned[z]
    if w and DUNGEONS[w] and IsWingOf(w, name) then return w end
    w = (MS.ForeverData.WING_ZONES or {})[z]
    if w and DUNGEONS[w] and IsWingOf(w, name) then return w end
end

-- ── Which wing, from the door you came in by ──────────────────────────────
-- WoW Forever has no dungeon maps, and the rooms near the doors have no
-- names: but each wing has its own door outside. Where you last stood
-- before the loading screen is that door.
-- The same door: within this much of one learned, or of one measured (the
-- measured ones are exact, and another wing's door may be close by).
local DOOR_RADIUS, KNOWN_DOOR_RADIUS = 0.006, 0.004
local DOOR_FRESH = 120                                   -- seconds: a sample this recent is how you came in
local lastOutside                                        -- { map, x, y, at }

local function SampleOutside()
    if IsInInstance() then return end
    local C = rawget(_G, "C_Map")
    if not (C and C.GetBestMapForUnit and C.GetPlayerMapPosition) then return end
    local ok, map = pcall(C.GetBestMapForUnit, "player")
    map = ok and MS.ReadableNumber(map)
    if not map then return end
    local ok2, pos = pcall(C.GetPlayerMapPosition, map, "player")
    if not (ok2 and pos and pos.GetXY) then return end
    local ok3, x, y = pcall(pos.GetXY, pos)
    x, y = ok3 and MS.ReadableNumber(x), ok3 and MS.ReadableNumber(y)
    if not (x and y) or (x <= 0 and y <= 0) then return end
    lastOutside = { map = map, x = x, y = y, at = GetTime() }
end
-- Sampled twice a second, only outside in a zone with a wing's door (no
-- cost anywhere else), and once more as the loading screen starts.
local sampler
local function DoorZones()
    local zones = {}
    for _, d in ipairs(MS.ForeverData.WING_DOORS or {}) do zones[d.map] = true end
    -- Where a dungeon with wings has its entrance, so its doors can be learned.
    for _, e in ipairs(MS.ForeverData.ENTRANCES or {}) do
        if e.map and MS:DungeonHasWings(InstanceOf(e[1])) then zones[e.map] = true end
    end
    local acc = MS.AccountDB()
    for _, d in ipairs(acc and acc.wingDoors or {}) do zones[d.map] = true end
    return zones
end
local function UpdateSampler()
    local C = rawget(_G, "C_Map")
    local map
    if not IsInInstance() and C and C.GetBestMapForUnit then
        local ok, m = pcall(C.GetBestMapForUnit, "player")
        map = ok and MS.ReadableNumber(m)
    end
    local want = map and DoorZones()[map]
    if want and not sampler then
        sampler = C_Timer.NewTicker(0.5, function() pcall(SampleOutside) end)
    elseif not want and sampler then
        sampler:Cancel(); sampler = nil
    end
end
MS:On("PLAYER_LEAVING_WORLD", function() pcall(SampleOutside) end)
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    MS:On(ev, function() pcall(UpdateSampler) end)
end

-- The door you just came in by, or nil (a /reload inside, say).
local function DoorJustUsed()
    if lastOutside and GetTime() - lastOutside.at <= DOOR_FRESH then
        return { map = lastOutside.map, x = lastOutside.x, y = lastOutside.y }
    end
end

local function WingDoors()
    local acc = MS.AccountDB()
    if not acc then return nil end
    acc.wingDoors = acc.wingDoors or {}
    return acc.wingDoors
end
local function Near(a, b, r)
    if a.map ~= b.map then return false end
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy <= r * r
end
local function Nearest(list, door, r)
    local best, bestD
    for _, d in ipairs(list or {}) do
        if Near(d, door, r) then
            local dx, dy = d.x - door.x, d.y - door.y
            local dist = dx * dx + dy * dy
            if not bestD or dist < bestD then best, bestD = d, dist end
        end
    end
    return best
end
local function WingFromDoor(door, name)
    if type(door) ~= "table" then return nil end
    local d = Nearest(WingDoors(), door, DOOR_RADIUS) or Nearest(MS.ForeverData.WING_DOORS, door, KNOWN_DOOR_RADIUS)
    local w = d and d.wing
    if w and DUNGEONS[w] and IsWingOf(w, name) then return w end
end
local function LearnDoor(door, wing)
    local doors = type(door) == "table" and WingDoors()
    if not doors then return end
    for i = #doors, 1, -1 do
        if Near(doors[i], door, DOOR_RADIUS) then table.remove(doors, i) end
    end
    doors[#doors + 1] = { map = door.map, x = door.x, y = door.y, wing = wing }
end

-- The wing you're in now, if where you are or how you came in says (for
-- Lifecycle: a paused run carries on only in the same wing).
function MS:ForeverWingHere(dungeonName)
    local name = Canonical(dungeonName)
    return WingFromZone(name) or WingFromDoor(DoorJustUsed(), name)
end
-- False when you just came in by another door than the run did.
function MS:ForeverSameDoor(run)
    local here = DoorJustUsed()
    if not (here and type(run.entryDoor) == "table") then return nil end
    return Near(here, run.entryDoor, DOOR_RADIUS)
end

-- For the run in progress: which wing it's in (shown as its name), and,
-- once its bosses say so, the wing its door, room and map are, for the next
-- time. (A room or map that turns out to hold two wings isn't used to tell
-- them apart.)
function MS:NoteForeverWing(run)
    if not run then return end
    local key, how = Resolve(run)
    if not (key and IsWingOf(key, RunName(run))) then return end
    run.wingName = key
    if how ~= "known" then run._wingBy = how end       -- (known: as worked out before)
    if how ~= "bosses" then return end
    if run.entryDoor then LearnDoor(run.entryDoor, key) end
    -- Learn where you are as this wing (only for the run you're in).
    local z = run == MS.currentRun and SubZone()
    local zones = z and WingZones()
    if zones then
        local had = zones[z]
        zones[z] = (had == nil or had == key) and key or false
    end
    if type(run.uiMapID) ~= "number" then return end
    local maps = WingMaps()
    if maps then
        local had = maps[run.uiMapID]
        maps[run.uiMapID] = (had == nil or had == key) and key or false
    end
end
MS:OnBossFight(function(run) MS:NoteForeverWing(run) end)

-- The wing again, once you're in: while the loading screen is up the game
-- doesn't always know your map yet, so the check when the run starts can
-- come up empty (or with the zone outside). Asked again a few seconds after
-- arriving and whenever the zone changes, until a boss fight settles it.
local wingDebug = false                -- /sb wingdebug (below)
-- What the wing was worked out from, surest first. A door can be a near
-- miss, so the room you walk into (or a boss) still corrects it.
local SURE = { bosses = true, map = true, zone = true, trash = true }
local function RecheckWing()
    local run = MS.currentRun
    if wingDebug then MS.Say("|cff9aa0a6wing:|r rechecking"); MS:WingDebug() end
    if not run or #(run.bosses or {}) > 0 then return end
    if run.wingName and (SURE[run._wingBy] or run._wingBy == nil and not run.entryDoor) then return end
    if not MS:DungeonHasWings(RunName(run)) then return end
    local C = rawget(_G, "C_Map")
    if C and C.GetBestMapForUnit then
        local ok, map = pcall(C.GetBestMapForUnit, "player")
        map = ok and MS.ReadableNumber(map)
        if map then run.uiMapID = map end
    end
    run.entryDoor = run.entryDoor or DoorJustUsed()
    local before = run.wingName
    if run._wingBy == "door" then run.wingName = nil end      -- a guess: look again
    MS:NoteForeverWing(run)
    if not SURE[run._wingBy] or not run.wingName then
        local name = RunName(run)
        local z = WingFromZone(name)
        if z then
            run.wingName, run._wingBy = z, "zone"
        else
            local d = WingFromDoor(run.entryDoor, name)
            if d then run.wingName, run._wingBy = d, "door" else run.wingName = before end
        end
    end
    if run.wingName ~= before then MS:SaveCurrentRun(); MS:Changed("run") end
end
-- ── Which wing, from the mobs you kill ────────────────────────────────────
-- Most wings have trash found nowhere else (WING_TRASH). The first of those
-- killed says which wing: surer than the door or the room, and kept unless a
-- boss says otherwise. Kills are seen by name (the XP line, "<mob> dies.")
-- and by NPC ID (UNIT_DIED and PARTY_KILL carry the mob's GUID). WING_TRASH
-- lists names only, so a kill seen by its NPC ID alone shows in /sb
-- wingdebug but doesn't say which wing.
local lastKillSeen                                   -- for /sb wingdebug
local function NpcOf(guid)
    guid = MS.Readable(guid)
    if not guid then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
local function TrashWing(name, base)
    local lname = type(name) == "string" and name:lower()
    local found
    for wing, list in pairs(MS.ForeverData.WING_TRASH or {}) do
        if DUNGEONS[wing] and IsWingOf(wing, base) then
            for _, english in ipairs(list) do
                if lname and lname == english:lower() then
                    if found and found ~= wing then return nil end   -- in two wings: no vote
                    found = wing
                    break
                end
            end
        end
    end
    return found
end
function MS:NoteForeverKill(npc, name)
    local run = MS.currentRun
    if not (run and MS.inDungeon) then return end
    local base = RunName(run)
    if not MS:DungeonHasWings(base) then return end
    local wing = TrashWing(name, base)
    lastKillSeen = { npc = npc, name = name, wing = wing }
    if wingDebug then
        MS.Say(string.format("|cff9aa0a6wing:|r killed %s (%s): %s", tostring(name), tostring(npc), tostring(wing)))
    end
    if not wing or #(run.bosses or {}) > 0 then return end
    if run._wingBy == "bosses" or run._wingBy == "map" or run._wingBy == "trash" then return end
    run.wingName, run._wingBy = wing, "trash"
    if run.entryDoor then LearnDoor(run.entryDoor, wing) end
    MS:SaveCurrentRun(); MS:Changed("run")
end

local DEATH_PATTERNS
local function Patterns()
    if DEATH_PATTERNS then return DEATH_PATTERNS end
    local list = {}
    for _, g in ipairs({ "UNITDIESOTHER", "PARTYKILLOTHER", "SELFKILLOTHER" }) do
        local fp = MS.FormatPattern(rawget(_G, g), "start")
        if fp then list[#list + 1] = fp end
    end
    if #list > 0 then DEATH_PATTERNS = list end      -- (kept once the game's strings are there)
    return list
end
-- A boss among the dead is its kill, if no fight of it was open
-- (Encounters.lua: NoteMobDied, BossKillSeen).
local function BossDied(npc, name, how)
    local run = MS.currentRun
    if not run then return end
    name = name or MS:ForeverBossByNpc(run, npc)
    if name then MS:NoteMobDied(name, how) end
end
MS:On("CHAT_MSG_COMBAT_HOSTILE_DEATH", function(_, text)
    if not MS.inDungeon then return end
    text = MS.Readable(text)
    if not text then return end
    for _, fp in ipairs(Patterns()) do
        local mob = MS.MatchFormat(text, fp)
        if mob and mob ~= "" then MS:NoteForeverKill(nil, mob); BossDied(nil, mob, "death"); return end
    end
end)
MS:On("UNIT_DIED", function(_, guid)
    if not MS.inDungeon then return end
    local npc = NpcOf(guid)
    if npc then MS:NoteForeverKill(npc, nil); BossDied(npc, nil, "npc") end
end)
MS:On("PARTY_KILL", function(_, _, guid)
    if not MS.inDungeon then return end
    local npc = NpcOf(guid)
    if npc then MS:NoteForeverKill(npc, nil); BossDied(npc, nil, "npc") end
end)

-- A boss's corpse, seen on your target, mouseover or a nameplate: it's
-- dead, whoever saw it die (inside, Forever hides most deaths from
-- addons, and a boss gray to you gives no experience line). Only a boss
-- of this dungeon, only once.
local function Corpse(unit)
    if not (MS.inDungeon and MS.currentRun and type(unit) == "string") then return end
    if not (UnitExists and UnitExists(unit)) then return end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not okP or MS.IsSecret(isPlayer) or isPlayer then return end
    local okD, dead = pcall(UnitIsDead, unit)
    if not okD or MS.IsSecret(dead) or dead ~= true then return end
    local okN, name = pcall(UnitName, unit)
    name = okN and MS.Readable(name)
    local npc = NpcOf(select(2, pcall(UnitGUID, unit)))
    if type(name) ~= "string" or name == "" then name = nil end
    if not (name and MS:ForeverIsBoss(MS.currentRun, name)) then name = MS:ForeverBossByNpc(MS.currentRun, npc) end
    if name then MS:BossKillSeen(name, nil, "corpse") end
end
MS:On("PLAYER_TARGET_CHANGED", function() Corpse("target") end)
MS:On("UPDATE_MOUSEOVER_UNIT", function() Corpse("mouseover") end)
MS:On("NAME_PLATE_UNIT_ADDED", function(_, unit) Corpse(unit) end)

-- /sb wingdebug: everything the wing check goes on, said in chat, now and
-- each time it runs.
local function Show(v)
    if MS.IsSecret(v) then return "hidden" end
    return tostring(v)
end
function MS:WingDebug(toggle)
    if toggle then
        wingDebug = not wingDebug
        MS.Say("Wing debug " .. (wingDebug and "on" or "off"))
        if not wingDebug then return end
    end
    local say = function(...) MS.Say("|cff9aa0a6wing:|r " .. string.format(...)) end
    local iname, itype, diff, _, _, _, _, iid = GetInstanceInfo()
    say("instance %s, %s, difficulty %s, id %s", Show(iname), Show(itype), Show(diff), Show(iid))
    local C = rawget(_G, "C_Map")
    local map = C and C.GetBestMapForUnit and select(2, pcall(C.GetBestMapForUnit, "player"))
    local zfn, mfn = rawget(_G, "GetSubZoneText"), rawget(_G, "GetMinimapZoneText")
    say("subzone %s, minimap zone %s; wing from it %s", Show(zfn and zfn()), Show(mfn and mfn()),
        Show(WingFromZone(MS.currentRun and RunName(MS.currentRun) or "Scarlet Monastery")))
    say("map now %s; names: %s", Show(map), type(map) == "number" and table.concat(MapNames(map), " | ") or "-")
    local ForMap, Info = rawget(_G, "EJ_GetInstanceForMap"), rawget(_G, "EJ_GetInstanceInfo")
    if ForMap and type(map) == "number" then
        local ok, inst = pcall(ForMap, map)
        say("journal: %s %s", Show(ok and inst),
            (ok and inst and inst ~= 0 and Info) and Show(select(2, pcall(Info, inst))) or "-")
    else
        say("journal: no EJ_GetInstanceForMap")
    end
    local run = MS.currentRun
    if not run then say("no run"); return end
    local learned = WingMaps()
    say("run: dungeonName %s, as %s, has wings %s, map %s, wing %s, bosses %d",
        Show(run.dungeonName), Show(RunName(run)), tostring(MS:DungeonHasWings(RunName(run))),
        Show(run.uiMapID), Show(run.wingName), #(run.bosses or {}))
    local m = run.uiMapID
    say("map %s: learned %s, built in %s", Show(m), Show(learned and m and learned[m]),
        Show(m and (MS.ForeverData.WING_MAPS or {})[m]))
    local key, how = Resolve(run)
    say("resolves to %s (by %s)", Show(key), Show(how))
    local k = lastKillSeen
    say("wing by %s; last kill seen %s", Show(run._wingBy),
        k and string.format("%s (npc %s) = %s", tostring(k.name), tostring(k.npc), tostring(k.wing)) or "-")
    local o, e = lastOutside, run.entryDoor
    say("last outside %s; came in by %s, wing %s; doors learned %d",
        o and string.format("%d %.4f,%.4f %ds ago", o.map, o.x, o.y, GetTime() - o.at) or "-",
        e and string.format("%d %.4f,%.4f", e.map, e.x, e.y) or "-",
        Show(WingFromDoor(e, RunName(run))), #(WingDoors() or {}))
end

local function SafeRecheck()
    local ok, err = pcall(RecheckWing)
    if not ok then MS:ReportError("Wing", err) end
end
local function RecheckSoon()
    for _, delay in ipairs({ 1, 4, 10 }) do C_Timer.After(delay, SafeRecheck) end
end
-- Arriving somewhere: always (the run may start a moment later).
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    MS:On(ev, RecheckSoon)
end
-- From room to room: these come all the time out in the world too, so
-- only with a run going.
local function RecheckInRun() if MS.currentRun or wingDebug then RecheckSoon() end end
for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
    MS:On(ev, RecheckInRun)
end
MS._RecheckWing = RecheckWing          -- for tests

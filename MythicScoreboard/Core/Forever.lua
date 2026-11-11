-- WoW Forever support. Loaded only by MythicScoreboard_Forever.toc.
--
-- Forever has classic-era dungeons (plus new ones), Normal/Heroic only and no
-- Mythic+. Everything the scoreboard needs to know about those dungeons lives
-- in Data/ForeverDungeons.lua, so the addon works on its own. When the
-- ForeverDungeonJournal addon is installed its boss portraits are preferred;
-- otherwise the bundled copy in Data/BossPortraits.lua is used.

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

-- Each boss's names (name and aliases), normalised, worked out on first use.
-- (Kept beside the entry, not on it: entries may be ForeverDungeonJournal's.)
local _names = setmetatable({}, { __mode = "k" })
local function Names(entry)
    local set = _names[entry]
    if not set then
        set = {}
        if entry.name then set[Norm(entry.name)] = true end
        for _, a in ipairs(entry.aka or entry.aliases or {}) do set[Norm(a)] = true end
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
    -- (entry.trash / summonItem: ForeverDungeonJournal's flags, for portraits lookups)
    return not entry.rare and not entry.summon and not entry.trash and not entry.summonItem
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
    local sig = name .. "#" .. nb .. "#" .. tostring(run.uiMapID)
    local hit = _resolved[run]
    if hit and hit.sig == sig then return hit.key, hit.how end
    local key, how
    if DUNGEONS[name] then
        key, how = name, "name"
    else
        key = nb > 0 and BestByBosses(run, name)
        if key then how = "bosses" else key = WingAt(run, name); how = key and "map" end
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

-- For the run in progress: which wing it's in (shown as its name), and,
-- once its bosses say so, the wing its map is, for the next time. (A map
-- that turns out to hold two wings isn't used to tell them apart.)
function MS:NoteForeverWing(run)
    if not run then return end
    local key, how = Resolve(run)
    if not (key and IsWingOf(key, RunName(run))) then return end
    run.wingName = key
    if how ~= "bosses" or type(run.uiMapID) ~= "number" then return end
    local maps = WingMaps()
    if maps then
        local had = maps[run.uiMapID]
        maps[run.uiMapID] = (had == nil or had == key) and key or false
    end
end
MS:OnBossFight(function(run) MS:NoteForeverWing(run) end)

-- Whether a dungeon's instance holds several wings ("Scarlet Monastery" for
-- its Graveyard, Library, Armory and Cathedral).
local _wings = {}
for key in pairs(DUNGEONS) do
    local base = InstanceOf(key)
    if base ~= key then _wings[base] = true end
end
function MS:DungeonHasWings(name) return _wings[Canonical(name)] == true end

-- The dungeon entries a run may be in: the one it's known to be, else every
-- wing of its instance.
function MS:ForeverDefsFor(run)
    local def = self:ForeverDungeon(run)
    if def then return { def } end
    local out, name = {}, RunName(run)
    for key, d in pairs(DUNGEONS) do
        if key == name or IsWingOf(key, name) then out[#out + 1] = d end
    end
    return out
end

-- Can this run ever be marked cleared? False for undocumented dungeons and
-- for names the table doesn't know (e.g. non-English clients).
function MS:ForeverCanDetectClear(run)
    local def = self:ForeverDungeon(run)
    if def then return #def.bosses > 0 end
    local name = RunName(run)
    if name == "" then return false end
    for key, d in pairs(DUNGEONS) do
        if IsWingOf(key, name) and #d.bosses > 0 then return true end   -- a wing
    end
    return false
end

local function RequiredBosses(def)
    local out = {}
    for _, e in ipairs(def and def.bosses or {}) do
        if IsRequired(e) then out[#out + 1] = e end
    end
    return out
end

local function Killed(run, entry)
    for _, b in ipairs(run.bosses or {}) do
        if b.killTime and EntryMatches(entry, b.name) then return true end
    end
    return false
end

-- In another language the bosses' names don't match the English ones, so
-- bosses are counted instead: nil when names match (English), else how many
-- different bosses have died.
local function KillsByCount(run, def)
    if (MS.ClientLocale or "enUS") == "enUS" then return nil end   -- the game's language names the bosses
    local kills, seen = 0, {}
    for _, b in ipairs(run.bosses or {}) do
        for _, e in ipairs(def.bosses) do
            if EntryMatches(e, b.name) then return nil end
        end
        if b.killTime and b.name and not seen[b.name] then seen[b.name] = true; kills = kills + 1 end
    end
    return kills
end

-- The clear rule (Settings.lua) applied after each boss kill.
local function CheckRunCleared(self, run, killedBoss)
    local rule = self:GetClearRule()
    run.clearRule = rule
    if rule == "leave" then return false end

    local def = self:ForeverDungeon(run)
    -- Names that don't match: cleared once as many bosses as the dungeon
    -- requires have died (both rules; the final boss can't be told apart).
    local counted = def and #def.bosses > 0 and KillsByCount(run, def)
    if counted then
        local req = #RequiredBosses(def)
        if req > 0 and counted >= req then run.finalDown = true; return true end
        return false
    end
    if rule == "all" and def then
        local req = RequiredBosses(def)
        if #req == 0 then return false end
        for _, e in ipairs(req) do
            if not Killed(run, e) then return false end
        end
        return true
    end

    -- "Final boss": some dungeons can be done in any order (Ruins of
    -- Lordaeron), so the final boss isn't always the last kill. With it down
    -- the run is cleared once every other required boss is too, or when you
    -- leave (run.finalDown).
    if def and def.final then
        local finalEntry
        for _, e in ipairs(def.bosses) do
            if e.name == def.final then finalEntry = e end
        end
        local finalDown
        if finalEntry then finalDown = Killed(run, finalEntry)
        else
            for _, b in ipairs(run.bosses or {}) do
                if b.killTime and Norm(b.name) == Norm(def.final) then finalDown = true end
            end
        end
        if not finalDown then return false end
        run.finalDown = true
        for _, e in ipairs(RequiredBosses(def)) do
            if not Killed(run, e) then return false end
        end
        return true
    end
    if not killedBoss or not killedBoss.killTime then return false end
    return FINAL_NAMES[Norm(killedBoss.name) or ""] == true
end

-- How Completion.lua decides a Forever run is cleared.
MS:SetClearStrategy({
    isCleared = CheckRunCleared,
    canDetect = function(self, run) return self:ForeverCanDetectClear(run) end,
})

-- "6 of 9": required bosses killed / required bosses.
function MS:ForeverBossProgress(run)
    local def = self:ForeverDungeon(run)
    if not def then return nil end
    local req = RequiredBosses(def)
    if #req == 0 then return nil end
    local counted = KillsByCount(run, def)
    if counted then return math.min(counted, #req), #req end
    local n = 0
    for _, e in ipairs(req) do if Killed(run, e) then n = n + 1 end end
    return n, #req
end

-- Dungeon level range, e.g. 17, 26. Works before any boss is pulled for
-- single-wing dungeons; multi-wing ones resolve after the first boss.
function MS:ForeverLevelRange(run)
    local def = self:ForeverDungeon(run)
    if def and def.levels then return def.levels[1], def.levels[2] end
    return nil
end

-- Other names the game may use for a boss (for learned portraits).
function MS:ForeverBossAliases(boss, run)
    local def = self:ForeverDungeon(run)
    for _, e in ipairs(def and def.bosses or {}) do
        if EntryMatches(e, boss.name) then
            local out = { e.name }
            for _, a in ipairs(e.aka or {}) do out[#out + 1] = a end
            return out
        end
    end
    return nil
end

-- Portrait for a boss medallion: "display", displayID  or  "file", path.
-- ForeverDungeonJournal's live data wins when it's installed (it may be newer
-- and has custom art for a few bosses); otherwise the bundled table in
-- Data/BossPortraits.lua is used.
local function ArtFromFDJ(self, boss, run)
    local ns = _G.ForeverDungeonJournal_NS
    local db = ns and type(ns.DB) == "table" and ns.DB
    if not db then return nil end
    local _, key = self:ForeverDungeon(run)
    local jdef = key and db[key]
    if type(jdef) ~= "table" or type(jdef.bosses) ~= "table" then return nil end
    for _, e in ipairs(jdef.bosses) do
        if EntryMatches(e, boss.name) then
            local display = e.displayID
                or (e.npcID and ns.STATIC_DISPLAY_IDS and ns.STATIC_DISPLAY_IDS[e.npcID])
            if display then return "display", display end
            if type(e.customIcon) == "string" then return "file", e.customIcon end
            return nil
        end
    end
    return nil
end

-- Bundled tables, re-keyed by normalised name on first use.
local _bundled
local function Bundled()
    if _bundled then return _bundled end
    _bundled = { display = {}, icons = {} }
    for src, dst in pairs({ [MS.FOREVER_BOSS_DISPLAY or {}] = _bundled.display,
                            [MS.FOREVER_BOSS_ICONS or {}]   = _bundled.icons }) do
        for dungeon, list in pairs(src) do
            local t = {}
            for name, v in pairs(list) do t[Norm(name)] = v end
            dst[dungeon] = t
        end
    end
    return _bundled
end

local function ArtFromBundle(self, boss, run)
    local b = Bundled()
    local names = { Norm(boss.name) }
    for _, a in ipairs(self:ForeverBossAliases(boss, run) or {}) do names[#names + 1] = Norm(a) end
    local _, key = self:ForeverDungeon(run)
    local function find(tbl)
        local list = key and tbl[key]
        if list then
            for _, n in ipairs(names) do if list[n] then return list[n] end end
        end
        -- Dungeon not recognised: boss names are unique enough across Forever.
        for _, l in pairs(tbl) do
            for _, n in ipairs(names) do if l[n] then return l[n] end end
        end
    end
    local display = find(b.display)
    if display then return "display", display end
    local icon = find(b.icons)
    if icon then return "file", icon end
    return nil
end

function MS:ForeverBossArt(boss, run)
    if not boss or not boss.name then return nil end
    local kind, art = ArtFromFDJ(self, boss, run)
    if kind then return kind, art end
    return ArtFromBundle(self, boss, run)
end

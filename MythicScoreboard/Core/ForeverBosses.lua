-- WoW Forever's boss lists, from Data/ForeverDungeons.lua: which bosses a
-- dungeon (or wing) has, which are needed for a clear, when a run is
-- cleared, whether a name is one of its bosses, the encounter IDs, and the
-- "6 of 9" count. Which dungeon or wing you're in is Forever.lua's.

local MS = _G["MythicScoreboard"]
local F = MS.ForeverLib
local DUNGEONS, FINAL_NAMES, Norm = F.DUNGEONS, F.FINAL_NAMES, F.Norm
local Canonical, InstanceOf, IsWingOf = F.Canonical, F.InstanceOf, F.IsWingOf
local Names, EntryMatches, IsRequired, RunName = F.Names, F.EntryMatches, F.IsRequired, F.RunName

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

-- ── Is it one of this dungeon's bosses? ─────────────────────────────────────
-- For kills seen without a boss fight (Encounters.lua: BossKillSeen): the
-- name, or another name for it, in this dungeon's boss list (rares and
-- summoned bosses too). Trash with a boss's name elsewhere doesn't count.
local function EntryFor(run, name)
    local def = MS:ForeverDungeon(run)
    for _, e in ipairs(def and def.bosses or {}) do
        if EntryMatches(e, name) then return e end
    end
end
function MS:ForeverIsBoss(run, name)
    return EntryFor(run, name) ~= nil
end
-- Two names for the same boss of this dungeon ("Zarmok", "Twilight Commander Zarmok").
function MS:ForeverSameBoss(run, a, b)
    local e = EntryFor(run, a)
    return e ~= nil and EntryMatches(e, b)
end
-- A boss fight by its encounter ID (Data/ForeverEncounters.lua): the name
-- to record it under, and the other bosses the same fight ends. The game's
-- own name is kept when it's one of the boss's names; otherwise (another
-- language, a name the list doesn't have) the list's name is used, so the
-- kill counts. Unknown IDs: the game's name, as before.
function MS:ForeverEncounterName(id, name)
    local enc = type(id) == "number" and (MS.ForeverData.ENCOUNTERS or {})[id]
    if not enc then return name, nil end
    local def = DUNGEONS[enc[1]]
    for _, e in ipairs(def and def.bosses or {}) do
        if e.name == enc[2] then
            if type(name) == "string" and EntryMatches(e, name) then return name, enc.also end
            return e.name, enc.also
        end
    end
    return name, enc.also
end

-- This dungeon's boss with this NPC ID (ForeverBossNpcs.lua), by name.
function MS:ForeverBossByNpc(run, npc)
    if not npc then return nil end
    local def = MS:ForeverDungeon(run)
    local npcs = MS.ForeverData.BOSSES or {}
    for _, e in ipairs(def and def.bosses or {}) do
        for n in pairs(Names(e)) do
            for name, info in pairs(npcs) do
                if info.npc == npc and Norm(name) == n then return e.name end
            end
        end
    end
end

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


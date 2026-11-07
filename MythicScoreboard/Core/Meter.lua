-- Reading Blizzard's damage meter (C_DamageMeter) into the current run.
--
-- The meter keeps an "overall" session per stat type; each source is one
-- player, pet or guardian with a running total. A snapshot copies those
-- totals onto the run's players:
--
--   1. bail out while the game hides the numbers (IsMeterHidden)
--   2. keep earlier totals if the meter started over mid-run (carry)
--   3. damage and healing, with per-second rates
--   4. damage taken, avoidable damage, interrupts, dispels (pets credited
--      to their owner)
--   5. deaths the meter knows about that the death poll missed

local MS = _G["MythicScoreboard"]
local _issecret = issecretvalue
local _ins = table.insert
local Readable = MS.Readable
local ShortName = MS.ShortName

MS._petGUIDToOwner = MS._petGUIDToOwner or {}
MS._petNameToOwner = MS._petNameToOwner or {}

local TYPE = {   -- Enum.DamageMeterType
    damage = 0, healing = 2, interrupts = 5, dispels = 6,
    damageTaken = 7, avoidable = 8, deaths = 9,
}
local CARRY_FIELDS = { "damageDone", "healingDone", "damageTaken",
                       "avoidableDamageTaken", "interrupts", "dispels" }

local function Overall()
    return (Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall) or 0
end

-- A number the addon may store, or nil.
local function Num(v)
    if v == nil or (_issecret and _issecret(v)) then return nil end
    return tonumber(v)
end

-- ── Hidden data ────────────────────────────────────────────────────────────
-- True while the game hides the meter's numbers (Midnight's combat
-- protection, e.g. during a Mythic+ key). Nothing may be read or stored then:
-- secret values taint addon tables. Hidden *names* don't count here; players
-- are matched by GUID and unreadable names are skipped source by source.
-- `s` may be the overall damage session already read, to save reading it again.
function MS:IsMeterHidden(s)
    if not (_issecret and C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return false end
    if not s then
        local ok
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, 0, 0)
        if not (ok and s) then return false end
    end
    if (s.maxValue ~= nil and _issecret(s.maxValue))
            or (s.duration ~= nil and _issecret(s.duration)) then
        return true
    end
    local first = s.combatSources and s.combatSources[1]
    return first ~= nil and first.totalAmount ~= nil and _issecret(first.totalAmount)
end

-- The overall session for one stat type, or nil.
local function Session(statType)
    local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, Overall(), statType)
    if ok and type(s) == "table" then return s end
end

-- ── Pets ───────────────────────────────────────────────────────────────────
-- Remembers which group member owns each visible pet, by GUID and by name.
-- Called on roster/pet changes; the meter may only show the pet later.
function MS:RebuildPetGUIDCache()
    local prefix = IsInRaid() and "raid" or "party"
    for i = 0, math.max(GetNumGroupMembers(), 4) do
        local ownerUnit = i == 0 and "player" or (prefix .. i)
        local petUnit   = i == 0 and "pet"    or (prefix .. i .. "pet")
        if UnitExists(petUnit) then
            local owner = self:UnitPlayerName(ownerUnit)
            local guid = MS.UnitGUIDReadable(petUnit)
            if owner and guid and (guid:find("^Pet%-") or guid:find("^Creature%-")) then
                self._petGUIDToOwner[guid] = ShortName(owner)
            end
            local petName = Readable(UnitName(petUnit))
            if owner and petName then
                self._petNameToOwner[petName] = ShortName(owner)
            end
        end
    end
end

local PET_TITLES   -- "%s's Pet" and friends, built on first use

-- The tooltip of a pet names its owner on line 2, as a GUID or as text.
local function OwnerFromTooltip(self, petGUID, run)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
    local ok, td = pcall(C_TooltipInfo.GetHyperlink, "unit:" .. petGUID)
    local line2 = ok and td and td.lines and td.lines[2]
    if not line2 then return nil end

    local ownerGUID = Readable(line2.guid)
    if ownerGUID and ownerGUID:find("^Player") then
        local p = self:PlayerByGUID(ownerGUID, run)
        if p then return p end
    end

    local text = Readable(line2.leftText)
    if not text then return nil end
    if not PET_TITLES then
        PET_TITLES = {}
        for _, fmt in ipairs({ UNITNAME_TITLE_PET, UNITNAME_TITLE_COMPANION, UNITNAME_TITLE_GUARDIAN,
                               UNITNAME_TITLE_MINION, UNITNAME_TITLE_CHARM, UNITNAME_TITLE_CREATION }) do
            PET_TITLES[#PET_TITLES + 1] = fmt
        end
        if UNITNAME_TITLE_PET and PET_TYPE_DEMON then
            PET_TITLES[#PET_TITLES + 1] = UNITNAME_TITLE_PET:gsub(PET_TYPE_PET or "Pet", PET_TYPE_DEMON)
        end
    end
    local realm = GetRealmName and GetRealmName() or ""
    -- Forever tooltips may give the owner's full name or just the first name.
    local match
    for _, p in pairs(run.players) do
        local key = p.name or ""
        local first = key:match("^([^%-]+)") or key
        for _, fmt in ipairs(PET_TITLES) do
            if text == fmt:format(key) or text == fmt:format(key .. "-" .. realm)
                    or text == fmt:format(MS.DisplayName(key)) then
                return p
            end
            if first ~= key and text == fmt:format(first) then
                if match and match ~= p then return nil end   -- two owners named alike: don't guess
                match = p
            end
        end
    end
    return match
end

-- The group member who owns a pet or guardian meter source, or nil.
-- Only sources with a pet/creature GUID are considered: an unmatched player
-- must never be credited to someone else.
function MS:PetOwnerForSource(src, run)
    local guid = Readable(src.sourceGUID)
    if not (guid and (guid:find("^Pet%-") or guid:find("^Creature%-") or guid:find("^Vehicle%-"))) then
        return nil
    end
    -- 1. A pet in the group right now with that GUID.
    local prefix = IsInRaid() and "raid" or "party"
    for i = 0, math.max(GetNumGroupMembers(), 4) do
        local petUnit = i == 0 and "pet" or (prefix .. i .. "pet")
        if UnitExists(petUnit) and MS.UnitGUIDReadable(petUnit) == guid then
            local p = self:PlayerForUnit(i == 0 and "player" or (prefix .. i), run)
            if p then self._petGUIDToOwner[guid] = p.name; return p end
        end
    end
    -- 2. A pet seen earlier (it may have died or been dismissed).
    if not self._petGUIDToOwner[guid] then self:RebuildPetGUIDCache() end
    local owner = self._petGUIDToOwner[guid] and self:PlayerByName(self._petGUIDToOwner[guid], run)
    if owner then return owner end
    -- 3. The pet's tooltip, which names its owner.
    owner = OwnerFromTooltip(self, guid, run)
    if owner then self._petGUIDToOwner[guid] = owner.name; return owner end
    -- 4. A pet name seen on a group member's pet.
    local byName = Readable(src.name) and self._petNameToOwner[src.name]
    owner = byName and self:PlayerByName(byName, run)
    if owner then self._petGUIDToOwner[guid] = owner.name end
    return owner
end

-- ── Carry-over ─────────────────────────────────────────────────────────────
-- The overall session only grows during a run. If its duration drops, the
-- meter started over (it can, e.g. while released and outside): keep what was
-- recorded and add the new totals on top of it.
local function UpdateCarry(run, duration)
    if duration <= 0 then return end
    if run._lastDur and duration + 2 < run._lastDur then
        run._carry = run._carry or {}
        run._deathBase = run._deathBase or {}
        for key, p in pairs(run.players) do
            local c = {}
            for _, f in ipairs(CARRY_FIELDS) do c[f] = p[f] or 0 end
            run._carry[key] = c
            run._deathBase[key] = p.deaths or 0     -- the meter counts deaths from 0 again too
        end
        run._carryDur = (run._carryDur or 0) + run._lastDur
    end
    run._lastDur = duration
end

local function Base(run, p, field)
    local c = run._carry and run._carry[p.name]
    return (c and c[field]) or 0
end

-- ── Snapshot steps ─────────────────────────────────────────────────────────
-- Damage or healing total plus a per-second rate.
local function ApplyRate(self, run, s, totalField, rateField, duration)
    if not (s and s.combatSources) then return end
    local totalDur = duration + (run._carryDur or 0)
    for _, src in ipairs(s.combatSources) do
        local p = self:PlayerForMeterSource(src, run)
        if p then
            p[totalField] = Base(run, p, totalField) + (Num(src.totalAmount) or 0)
            local aps = Num(src.amountPerSecond) or 0
            if run._carry and run._carry[p.name] then
                p[rateField] = totalDur > 0 and p[totalField] / totalDur or 0
            elseif aps > 0 then
                p[rateField] = aps
            else
                p[rateField] = duration > 0 and p[totalField] / duration or 0
            end
        end
    end
end

-- A plain total. The meter's list is cumulative, so every player starts from
-- their carried base each time and pets are added on top of their owner.
local function ApplyTotal(self, run, statType, field)
    local s = Session(statType)
    if not (s and s.combatSources) then return end
    for _, p in pairs(run.players) do p[field] = Base(run, p, field) end
    for _, src in ipairs(s.combatSources) do
        local amt = Num(src.totalAmount) or 0
        local p = self:PlayerForMeterSource(src, run)
        if p then
            p[field] = p[field] + amt
        else
            local owner = self:PetOwnerForSource(src, run)
            if owner then owner[field] = owner[field] + amt end
        end
    end
end

-- Deaths the meter counted that the 0.75s death poll didn't see.
local function ApplyDeaths(self, run)
    local s = Session(TYPE.deaths)
    if not (s and s.combatSources) then return end
    for _, src in ipairs(s.combatSources) do
        local meterDeaths = Num(src.totalAmount) or 0
        local p = meterDeaths > 0 and self:PlayerForMeterSource(src, run)
        if p then
            local now = self:GetRunDuration(run)
            local base = run._deathBase and run._deathBase[p.name] or 0
            for _ = 1, meterDeaths + base - p.deaths do
                if not self:IsDupDeath(p, now) then
                    _ins(p.deathEvents, { time = now })
                    p.deaths = p.deaths + 1
                end
            end
            local isLocal = src.isLocalPlayer
            if isLocal ~= nil and issecretvalue and issecretvalue(isLocal) then isLocal = nil end
            if isLocal then
                local ok, id = pcall(rawget, src, "deathRecapID")
                if ok and Num(id) and id ~= 0 then self:NoteDeathRecap(p, id) end
            end
        end
    end
end

-- The meter wasn't reset when the run started ("Reset meter on zone-in" is
-- off), so its totals include whatever came before. The first reading of
-- the run becomes its zero point: kept as a negative carry-over, so every
-- later reading counts only what happened since, and rates use the run's
-- own time.
local function TakeBaseline(self, run, damage, duration)
    run._carry, run._carryDur = nil, nil
    ApplyRate(self, run, damage, "damageDone", "dps", duration)
    ApplyRate(self, run, Session(TYPE.healing), "healingDone", "hps", duration)
    ApplyTotal(self, run, TYPE.damageTaken, "damageTaken")
    ApplyTotal(self, run, TYPE.avoidable,   "avoidableDamageTaken")
    ApplyTotal(self, run, TYPE.interrupts,  "interrupts")
    ApplyTotal(self, run, TYPE.dispels,     "dispels")
    run._carry = {}
    for key, p in pairs(run.players) do
        local c = {}
        for _, f in ipairs(CARRY_FIELDS) do c[f] = -(p[f] or 0); p[f] = 0 end
        p.dps, p.hps = 0, 0
        run._carry[key] = c
    end
    run._carryDur = -duration
    run._lastDur  = duration
    run._deathBase = {}
    local s = Session(TYPE.deaths)
    for _, src in ipairs(s and s.combatSources or {}) do
        local p = self:PlayerForMeterSource(src, run)
        if p then run._deathBase[p.name] = (p.deaths or 0) - (Num(src.totalAmount) or 0) end
    end
    run._baselinePending = nil
end

-- One read of each stat type. Returns true when the numbers were read.
function MS:SnapshotFromDamageMeter()
    local run = self.currentRun
    if not run then return end
    if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable()
            and C_DamageMeter.GetCombatSessionFromType) then return end

    local damage = Session(TYPE.damage)
    if not (damage and damage.combatSources) then return end
    if self:IsMeterHidden(damage) then return end
    local duration = Num(damage.duration) or 0
    if run._baselinePending then TakeBaseline(self, run, damage, duration) end
    UpdateCarry(run, duration)

    ApplyRate(self, run, damage, "damageDone", "dps", duration)
    ApplyRate(self, run, Session(TYPE.healing), "healingDone", "hps", duration)
    ApplyTotal(self, run, TYPE.damageTaken, "damageTaken")
    ApplyTotal(self, run, TYPE.avoidable,   "avoidableDamageTaken")
    ApplyTotal(self, run, TYPE.interrupts,  "interrupts")
    ApplyTotal(self, run, TYPE.dispels,     "dispels")
    self:_BackfillSyntheticInterrupts()
    ApplyDeaths(self, run)
    self:CaptureFightStats(run, true)

    self:PopulateAll()
    self:SaveCurrentRun()
    return true
end

-- ── Per-fight numbers ──────────────────────────────────────────────────────
-- Besides the overall session the meter keeps one session per combat. When a
-- boss fight ends, its session is noted; once the numbers can be read (out of
-- combat, or after a key), that fight's totals are copied onto the boss:
--
--   boss.stats[player] = { dmg, heal, taken, avoid, int, disp }
--
-- Without per-combat sessions, the fight is worked out instead as the
-- difference between the totals at the pull and the first reading after it
-- (boss.statsApprox); that only works before the next boss is pulled.
local FIGHT_FIELDS = { dmg = "damageDone", heal = "healingDone", taken = "damageTaken",
                       avoid = "avoidableDamageTaken", int = "interrupts", disp = "dispels" }
local FIGHT_TYPES  = { dmg = TYPE.damage, heal = TYPE.healing, taken = TYPE.damageTaken,
                       avoid = TYPE.avoidable, int = TYPE.interrupts, disp = TYPE.dispels }
local OWNER_GETS_PET = { taken = true, avoid = true, int = true, disp = true }
local MAX_TRIES = 20      -- readable readings of a missing session before giving up

-- The totals so far, for the fallback.
function MS:NoteFightStart(boss)
    local run = self.currentRun
    if not (run and boss) then return end
    local before = {}
    for key, p in pairs(run.players) do
        local b = {}
        for short, field in pairs(FIGHT_FIELDS) do b[short] = p[field] or 0 end
        before[key] = b
    end
    boss._before = before
end

-- The session the fight was in: the newest one, or the newest named after
-- the boss. Called at ENCOUNTER_END.
function MS:NoteFightEnd(boss)
    if not (boss and C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return end
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not (ok and type(list) == "table") then return end
    local newest, named
    for _, s in ipairs(list) do
        local id = Num(s.sessionID)
        if id then
            if not newest or id > newest then newest = id end
            local nm = Readable(s.name)
            if nm and nm == boss.name and (not named or id > named) then named = id end
        end
    end
    local id = named or newest
    -- One combat holding two bosses can't be split between them.
    for _, b in ipairs((self.currentRun and self.currentRun.bosses) or {}) do
        if b ~= boss and b._session == id then id = nil; break end
    end
    boss._session = id
end

-- One session's totals by player, or nil while hidden / when it's gone.
local function ReadSession(self, run, id)
    if not C_DamageMeter.GetCombatSessionFromID then return nil end
    local out, any = {}, false
    for short, statType in pairs(FIGHT_TYPES) do
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, id, statType)
        if not (ok and type(s) == "table" and s.combatSources) then return nil end
        for _, src in ipairs(s.combatSources) do
            if src.totalAmount ~= nil and _issecret and _issecret(src.totalAmount) then return nil end
            local amt = tonumber(src.totalAmount) or 0
            if amt > 0 then
                local p = self:PlayerForMeterSource(src, run)
                if not p and OWNER_GETS_PET[short] then p = self:PetOwnerForSource(src, run) end
                if p and p.name then
                    local row = out[p.name] or {}
                    out[p.name] = row
                    row[short] = (row[short] or 0) + amt
                    any = true
                end
            end
        end
    end
    return any and out or nil
end

local function Difference(run, before)
    local out = {}
    for key, p in pairs(run.players) do
        local b = before[key] or {}
        local row
        for short, field in pairs(FIGHT_FIELDS) do
            local v = (p[field] or 0) - (b[short] or 0)
            if v > 0 then row = row or {}; row[short] = v end
        end
        if row then out[key] = row end
    end
    return out
end

-- When the session list was hidden at the kill (during a key), the fight's
-- session is found later by name: the last fight against a boss is the
-- newest session with its name, the one before it the next newest, and so on.
local function SessionsByName()
    local out = {}
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not (ok and type(list) == "table") then return out end
    for _, s in ipairs(list) do
        local id, nm = Num(s.sessionID), Readable(s.name)
        if id and nm then
            out[nm] = out[nm] or {}
            _ins(out[nm], id)
        end
    end
    for _, ids in pairs(out) do table.sort(ids) end
    return out
end

local function LateSession(run, boss, byName)
    local ids = boss.name and byName[boss.name]
    if not ids then return nil end
    local fromEnd = 0
    for j = #run.bosses, 1, -1 do
        local b = run.bosses[j]
        if b.name == boss.name then fromEnd = fromEnd + 1 end
        if b == boss then break end
    end
    return ids[#ids - fromEnd + 1]
end

-- Fills in boss.stats for fights that have ended. Called after each reading.
function MS:CaptureFightStats(run, readable)
    run = run or self.currentRun
    if not (run and run.bosses) then return end
    if not readable and self:IsMeterHidden() then return end
    if InCombatLockdown and InCombatLockdown() then return end   -- the fight's combat may still be going
    local n = #run.bosses
    local byName
    for i, boss in ipairs(run.bosses) do
        if (boss.killTime or boss.wipeTime) and not boss.stats then
            local stats
            if not boss._session and not boss._named and C_DamageMeter.GetAvailableCombatSessions then
                boss._named = true
                byName = byName or SessionsByName()
                boss._session = LateSession(run, boss, byName)
            end
            if boss._session then
                stats = ReadSession(self, run, boss._session)
                if not stats then
                    boss._tries = (boss._tries or 0) + 1
                    if boss._tries >= MAX_TRIES then boss._session = nil end
                end
            end
            if not stats and not boss._session and boss._before and i == n and not run.activeBoss then
                stats = Difference(run, boss._before)
                boss.statsApprox = true
            end
            if stats then
                boss.stats = stats
                boss._before, boss._session, boss._tries, boss._named = nil, nil, nil, nil
                run._seq = (run._seq or 0) + 1
            elseif i < n then
                boss._before = nil       -- a later fight has started: the difference is gone
            end
        end
    end
end

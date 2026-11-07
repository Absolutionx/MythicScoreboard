-- What happens in a run: boss pulls, kills and wipes, deaths, enemy forces.
--
-- Every time recorded here comes from MS:GetRunDuration (RunModel.lua), so
-- bosses, deaths, interrupts and loot share one clock.

local _floor, _min = math.floor, math.min
local _ins = table.insert

local MS = _G["MythicScoreboard"]
local _issecret = issecretvalue

local function Now(run) return MS:GetRunDuration(run) end

-- ── Enemy forces ───────────────────────────────────────────────────────────
-- The isWeightedProgress scenario criterion, as a completion %.
local function GetEnemyForcesPercent()
    if not (C_Scenario and C_Scenario.GetStepInfo) then return nil end
    local ok1, _, _, numCriteria = pcall(C_Scenario.GetStepInfo)
    if not ok1 or not numCriteria or numCriteria <= 0 then return nil end

    for i = 1, numCriteria do
        local ok2, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if ok2 and info and info.isWeightedProgress then
            if info.completed then return 100 end
            local curValue = info.quantity    or 0
            local maxValue = info.totalQuantity or 0
            if maxValue <= 0 then return nil end
            -- quantityString may be "42%": strip the suffix for the raw count.
            if info.quantityString and info.quantityString ~= "" then
                local stripped = tonumber(info.quantityString:sub(1, -2))
                if stripped then curValue = stripped end
            end
            local pct = (curValue / maxValue) * 100
            pct = _floor(pct * 100 + 0.5) / 100
            return _min(100, pct)
        end
    end
    return nil
end

-- Whether every scenario criterion is done (a key's last step).
function MS:AllCriteriaComplete()
    if not (C_Scenario and C_Scenario.GetStepInfo) then return false end
    local ok, _, _, numCriteria = pcall(C_Scenario.GetStepInfo)
    if not (ok and numCriteria and numCriteria > 0) then return false end
    local done = 0
    for i = 1, numCriteria do
        local ok2, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if ok2 and info and info.completed then done = done + 1 end
    end
    return done >= numCriteria
end

function MS:SnapshotBossProgress(boss, atPull)
    if not boss then return end
    local pct = (self.currentRun and self.currentRun.currentPct) or GetEnemyForcesPercent()
    if not pct then return end
    if atPull then boss.pullProgressPct = pct
    else            boss.progressPct    = pct end
end

function MS:UpdateEnemyForcesProgress()
    if not self.currentRun then return end
    local pct = GetEnemyForcesPercent()
    if pct ~= nil then
        self.currentRun.currentPct = pct
    elseif (self.currentRun.keystoneLevel or 0) > 0
            and self.currentRun.currentPct == nil then
        self.currentRun.currentPct = 0
    end
end

-- ── Bosses ─────────────────────────────────────────────────────────────────
local function NoteEncounter(b, id)
    if id and not b.dungeonEncounterId then b.dungeonEncounterId = id end
end

function MS:BossPull(bossName, dungeonEncounterId)
    local run = self.currentRun
    if not run then return end
    local now = Now(run)
    -- Re-use existing entry on double-fire; stamp as wipe if > 10s have passed.
    for i = #run.bosses, 1, -1 do
        local b = run.bosses[i]
        if b.name == bossName and not b.killTime and not b.wipeTime then
            if now - (b.pullTime or 0) < 10 then
                run.activeBoss = b
                NoteEncounter(b, dungeonEncounterId)
                return
            end
            b.wipeTime = now
            break
        elseif b.name == bossName and b.wipeTime and not b.killTime then
            break
        end
    end
    local boss = { name = bossName, pullTime = now, dungeonEncounterId = dungeonEncounterId }
    _ins(run.bosses, boss)
    run.activeBoss = boss
    if self.NoteFightStart then self:NoteFightStart(boss) end
    self:SnapshotBossProgress(boss, true)
    if self.ResolveBossIcon then self:ResolveBossIcon(boss) end
    self:SaveCurrentRun()
end

-- The fight with this boss that hasn't ended yet.
local function OpenFight(run, bossName)
    local ab = run.activeBoss
    if ab and ab.name == bossName then return ab end
    for i = #run.bosses, 1, -1 do
        local b = run.bosses[i]
        if b.name == bossName and not b.killTime and not b.wipeTime then return b end
    end
end

local function EndFight(self, bossName, dungeonEncounterId, field)
    local run = self.currentRun
    if not run then return nil end
    local boss = OpenFight(run, bossName)
    if not boss then return nil end
    boss[field] = Now(run)
    NoteEncounter(boss, dungeonEncounterId)
    if run.activeBoss == boss then run.activeBoss = nil end
    if self.NoteFightEnd then self:NoteFightEnd(boss) end
    self:SaveCurrentRun()
    return boss
end

function MS:BossKill(bossName, dungeonEncounterId) return EndFight(self, bossName, dungeonEncounterId, "killTime") end
function MS:BossWipe(bossName, dungeonEncounterId) return EndFight(self, bossName, dungeonEncounterId, "wipeTime") end

-- ── Deaths ─────────────────────────────────────────────────────────────────
-- who: a player from the run, or any form of their name.
function MS:RecordDeathEvent(who)
    local run = self.currentRun
    if not run or not who then return end
    local p = type(who) == "table" and who or self:PlayerByName(who)
    if not p then return end
    local t = Now(run)
    p.deaths = p.deaths + 1
    p._lastDeathTime = t
    _ins(p.deathEvents, { time = t })
    -- Time lost to deaths: the game's own count in a key; else the old rule
    -- of thumb (15s at +12, 5s at +4 to +11).
    local level = run.keystoneLevel or 0
    local lost = level > 0 and self.KeyDeathPenalty and self:KeyDeathPenalty()
    if lost then
        run.deathPenaltySeconds = lost
    elseif level >= 12 then
        run.deathPenaltySeconds = (run.deathPenaltySeconds or 0) + 15
    elseif level >= 4 then
        run.deathPenaltySeconds = (run.deathPenaltySeconds or 0) + 5
    end
    self:SaveCurrentRun()
end

local function Plain(v)
    if v == nil or (_issecret and _issecret(v)) then return nil end
    return v
end

-- The killing blow and the two hits before it, copied off a death recap.
local function RecapHits(recapID)
    if not DeathRecap_GetEvents then return nil end
    local ok, events = pcall(DeathRecap_GetEvents, recapID)
    if not (ok and type(events) == "table" and #events > 0) then return nil end
    local out = {}
    for i = math.max(1, #events - 2), #events do
        local ev = events[i]
        if type(ev) == "table" then
            local name = Plain(ev.spellName)
            if type(name) == "string" then
                local amount, overkill = Plain(ev.amount), Plain(ev.overkill)
                local caster = Plain(ev.caster)
                out[#out + 1] = {
                    spellName = name,
                    caster    = type(caster) == "string" and caster or nil,
                    amount    = type(amount) == "number" and amount or nil,
                    overkill  = type(overkill) == "number" and overkill or nil,
                }
            end
        end
    end
    return #out > 0 and out or nil
end

-- A death recap ID the meter gave for the local player. It belongs to their
-- latest death; its hits are copied onto that death now, since the ID means
-- nothing after this session.
function MS:NoteDeathRecap(p, recapID)
    if not (p and recapID) or p._lastRecapID == recapID then return end
    p._lastRecapID = recapID
    local de = p.deathEvents and p.deathEvents[#p.deathEvents]
    if not de or de.events then return end
    de.events = RecapHits(recapID)
    if de.events then self:SaveCurrentRun() end
end

-- The killing blow among a death's hits (the one with overkill, else the last).
function MS.KillingBlow(events)
    if not events then return nil end
    for i = #events, 1, -1 do
        local ev = events[i]
        if ev and (ev.overkill or 0) > 0 then return ev end
    end
    return events[#events]
end

-- Deaths are polled (UNIT_DIED through the combat log is blocked in Midnight).
local _deadUnits = MS._deadUnits

local function PollDeaths()
    if not MS.inDungeon then return end
    local run = MS.currentRun
    if not run then return end
    local now = Now(run)
    for _, unit in ipairs(MS:GroupUnits()) do
        -- Skip mind-controlled mobs temporarily showing as players in the roster.
        if UnitIsPlayer(unit) then
            local dead = UnitIsDeadOrGhost(unit)
            if dead and not _deadUnits[unit] then
                _deadUnits[unit] = true
                local p = MS:PlayerForUnit(unit)
                if p and not MS:IsDupDeath(p, now) then MS:RecordDeathEvent(p) end
            elseif not dead and _deadUnits[unit] then
                _deadUnits[unit] = nil
            end
        end
    end
end
MS.PollDeaths = PollDeaths   -- polled every 0.75s during a run (Events.lua)

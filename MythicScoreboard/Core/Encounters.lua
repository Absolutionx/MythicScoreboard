-- What happens in a run: boss pulls, kills and wipes, deaths, enemy forces.
--
-- Every time recorded here comes from MS:GetRunDuration (RunModel.lua), so
-- bosses, deaths, interrupts and loot share one clock.

local _floor, _min = math.floor, math.min
local _ins = table.insert

local MS = _G["MythicScoreboard"]

local function Now(run) return MS:GetRunDuration(run) end

-- Code that wants to know when a boss fight starts or ends (Forever.lua uses
-- it to tell which wing a run is in): fn(run, boss).
local fightWatchers = {}
function MS:OnBossFight(fn) fightWatchers[#fightWatchers + 1] = fn end
local function FightChanged(run, boss)
    for i = 1, #fightWatchers do fightWatchers[i](run, boss) end
end

-- ── Enemy forces ───────────────────────────────────────────────────────────
-- The isWeightedProgress scenario criterion, as a completion %.
local function GetEnemyForcesPercent()
    if not (C_Scenario and C_Scenario.GetStepInfo) then return nil end
    local ok1, _, _, numCriteria = pcall(C_Scenario.GetStepInfo)
    numCriteria = ok1 and MS.ReadableNumber(numCriteria)
    if not numCriteria or numCriteria <= 0 then return nil end

    for i = 1, numCriteria do
        local ok2, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        -- Each field read through Readable*: a value the game hides is skipped.
        if ok2 and type(info) == "table" and MS.ReadableValue(info.isWeightedProgress) then
            if MS.ReadableValue(info.completed) then return 100 end
            local curValue = MS.ReadableNumber(info.quantity) or 0
            local maxValue = MS.ReadableNumber(info.totalQuantity) or 0
            if maxValue <= 0 then return nil end
            -- quantityString may be "42%": strip the suffix for the raw count.
            local qs = MS.Readable(info.quantityString)
            if qs then
                local stripped = tonumber(qs:sub(1, -2))
                if stripped then curValue = stripped end
            end
            local pct = (curValue / maxValue) * 100
            pct = _floor(pct * 100 + 0.5) / 100
            return _min(100, pct), curValue, maxValue
        end
    end
    return nil
end

-- Whether every scenario criterion is done (a key's last step).
function MS:AllCriteriaComplete()
    if not (C_Scenario and C_Scenario.GetStepInfo) then return false end
    local ok, _, _, numCriteria = pcall(C_Scenario.GetStepInfo)
    numCriteria = ok and MS.ReadableNumber(numCriteria)
    if not (numCriteria and numCriteria > 0) then return false end
    local done = 0
    for i = 1, numCriteria do
        local ok2, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if ok2 and type(info) == "table" and MS.ReadableValue(info.completed) then done = done + 1 end
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
    local pct, count, total = GetEnemyForcesPercent()
    if pct ~= nil then
        self.currentRun.currentPct = pct
        self.currentRun.forcesCount, self.currentRun.forcesTotal = count, total
    elseif (self.currentRun.keystoneLevel or 0) > 0
            and self.currentRun.currentPct == nil then
        self.currentRun.currentPct = 0
    end
end

-- What the last pack was worth: enemy forces when combat began and again
-- once it ended (a moment later: the count can trail the last kill). Each
-- mob's own value is hidden from addons in Midnight, so a pull is only
-- known once it's over. A wipe or a reset pack comes to nothing and leaves
-- the last value as it was.
local PULL_SETTLE = 1.0
function MS:NotePullStart()
    local run = self.currentRun
    if not (run and (run.keystoneLevel or 0) > 0) then return end
    self:UpdateEnemyForcesProgress()
    run._pullFrom = run.currentPct
end
function MS:NotePullEnd()
    local run = self.currentRun
    if not (run and run._pullFrom) then return end
    self:AfterForRun(run, PULL_SETTLE, function()
        if not run._pullFrom then return end
        MS:UpdateEnemyForcesProgress()
        local gained = (run.currentPct or 0) - run._pullFrom
        run._pullFrom = nil
        if gained >= 0.01 then
            run.lastPull = _floor(gained * 100 + 0.5) / 100
            MS:Changed("run")
        end
    end)
end

-- ── Bosses ─────────────────────────────────────────────────────────────────
local function NoteEncounter(b, id)
    if id and not b.dungeonEncounterId then b.dungeonEncounterId = id end
end

function MS:BossPull(bossName, dungeonEncounterId)
    local run = self.currentRun
    if not run then return end
    local now = Now(run)
    -- Another boss's fight still open (the game never ended it): over now.
    local ab = run.activeBoss
    if ab and ab.name ~= bossName and not ab.killTime and not ab.wipeTime then
        self:CloseOpenFight(run, run._combatEndedAt or now)
    end
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
    FightChanged(run, boss)
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

-- The game's end for a fight the addon already closed as a reset (nobody
-- was fighting, so it looked over): the game knows better. A kill turns the
-- reset into a kill, at the moment combat ended if the report came soon after
-- (closing waits a few quiet seconds), or now if the fight had carried on. A
-- wipe makes it a plain wipe.
local LATE_END = 10 * 60
local function LateEnd(self, run, bossName, dungeonEncounterId, field)
    local now = Now(run)
    for i = #run.bosses, 1, -1 do
        local b = run.bosses[i]
        if MS.SameBossName(b.name, bossName) then
            if not (b.reset and b.wipeTime and not b.killTime and now - b.wipeTime <= LATE_END) then return nil end
            b.reset = nil
            if field == "killTime" then
                b.killTime = (now - b.wipeTime <= 20) and b.wipeTime or now
                b.wipeTime = nil
            end
            NoteEncounter(b, dungeonEncounterId)
            if self.NoteFightEnd then self:NoteFightEnd(b) end
            FightChanged(run, b)
            self:SaveCurrentRun()
            return b
        end
    end
end

local function EndFight(self, bossName, dungeonEncounterId, field, at)
    local run = self.currentRun
    if not run then return nil end
    local boss = OpenFight(run, bossName)
    if not boss then return LateEnd(self, run, bossName, dungeonEncounterId, field) end
    boss[field] = at or Now(run)
    NoteEncounter(boss, dungeonEncounterId)
    if run.activeBoss == boss then run.activeBoss = nil end
    if self.NoteFightEnd then self:NoteFightEnd(boss) end
    FightChanged(run, boss)
    self:SaveCurrentRun()
    return boss
end

function MS:BossKill(bossName, dungeonEncounterId) return EndFight(self, bossName, dungeonEncounterId, "killTime") end
function MS:BossWipe(bossName, dungeonEncounterId) return EndFight(self, bossName, dungeonEncounterId, "wipeTime") end

-- A boss fight the game started but never ended (no ENCOUNTER_END: the boss
-- reset, or some encounters on Forever simply don't send one). Ended at `at`:
-- killed if the experience line said the boss died, else reset (a wipe, with
-- `reset` set so it reads as one).
function MS:CloseOpenFight(run, at)
    run = run or self.currentRun
    local boss = run and run.activeBoss
    if not boss or boss.killTime or boss.wipeTime then return nil end
    at = math.max(boss.pullTime or 0, at or Now(run))
    if boss._diedAt then
        local killed = EndFight(self, boss.name, nil, "killTime", boss._diedAt)
        if killed and self.CheckClearedAfterKill then self:CheckClearedAfterKill(killed) end
        return killed
    end
    boss.reset = true
    return EndFight(self, boss.name, nil, "wipeTime", at)
end

-- A mob the experience line said died: a boss whose fight is open is killed
-- (kept until the fight ends, in case ENCOUNTER_END follows as it should).
function MS:NoteMobDied(name)
    local run = self.currentRun
    local boss = run and run.activeBoss
    if not boss or boss.killTime or boss.wipeTime or type(name) ~= "string" then return end
    if MS.SameBossName(boss.name, name) then boss._diedAt = Now(run) end
end

-- Out of combat with a fight still open: once nobody in the group has been
-- fighting for a few seconds, the fight is over whatever the game says.
local QUIET_SECONDS = 6
local function AnyoneFighting()
    if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end   -- the group may fight on
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists and UnitExists(u) and UnitAffectingCombat and UnitAffectingCombat(u) then return true end
    end
    return false
end
function MS:OnCombatEnded()
    local run = self.currentRun
    if not run or not run.activeBoss then return end
    local endedAt = Now(run)
    run._combatEndedAt = endedAt
    local function check(tries)
        local r = self.currentRun
        if r ~= run or not r.activeBoss or r.activeBoss.killTime or r.activeBoss.wipeTime then return end
        if AnyoneFighting() then
            if tries < 20 then C_Timer.After(QUIET_SECONDS, function() check(tries + 1) end) end
            return
        end
        self:CloseOpenFight(r, r._combatEndedAt or endedAt)
    end
    C_Timer.After(QUIET_SECONDS, function() check(0) end)
end

-- ── Deaths ─────────────────────────────────────────────────────────────────
-- A cleared run stays open until you leave, but it ended at the clear: deaths
-- after it (a few seconds' grace for the poll) aren't the run's.
-- (The run's clock stops at the clear, so this goes by the game clock.)
function MS:AfterClear(run)
    return run and run.completed and run._clearedClock and GetTime() > run._clearedClock + 3 or false
end

-- who: a player from the run, or any form of their name.
function MS:RecordDeathEvent(who)
    local run = self.currentRun
    if not run or not who then return end
    local p = type(who) == "table" and who or self:PlayerByName(who)
    if not p then return end
    local t = Now(run)
    if self:AfterClear(run) then return end
    p.deaths = p.deaths + 1
    p._lastDeathTime = t
    _ins(p.deathEvents, { time = t })
    -- Time lost to deaths: the game's own count in a key; else the old rule
    -- of thumb (15s at +12, 5s at +4 to +11).
    local level = run.keystoneLevel or 0
    local lost = level > 0 and self.KeyDeathPenalty and self:KeyDeathPenalty()
    if lost then
        run.deathPenaltySeconds = lost
    elseif level > 0 then
        run.deathPenaltySeconds = (run.deathPenaltySeconds or 0) + MS.DeathPenaltyFor(level)
    end
    self:SaveCurrentRun()
end

local Plain = MS.ReadableValue

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
-- Who has been seen dead, by GUID (a unit token like party2 can move to
-- someone else when the group changes), so each death counts once. Forgotten
-- whenever the run stops recording.
local _deadUnits = {}
MS:WatchRunState(function(state)
    if state ~= "active" then wipe(_deadUnits) end
end)

local function PollDeaths()
    if not MS.inDungeon then return end
    local run = MS.currentRun
    if not run then return end
    local now = Now(run)
    for _, unit in ipairs(MS:GroupUnits()) do
        -- Skip mind-controlled mobs temporarily showing as players in the roster.
        if UnitIsPlayer(unit) then
            local dead = UnitIsDeadOrGhost(unit)
            local who = MS.Readable(UnitGUID(unit)) or unit
            if MS.IsSecret(dead) then dead = _deadUnits[who] end   -- hidden: as last seen
            if dead and not _deadUnits[who] then
                _deadUnits[who] = true
                local p = MS:PlayerForUnit(unit)
                if p and not MS:IsDupDeath(p, now) then MS:RecordDeathEvent(p) end
            elseif not dead and _deadUnits[who] then
                _deadUnits[who] = nil
            end
        end
    end
end
MS.PollDeaths = PollDeaths   -- polled every 0.75s during a run (Events.lua)

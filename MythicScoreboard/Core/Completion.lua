-- When a run counts as cleared, and how a finished run is saved.
--
-- Cleared:
--   Mythic+      the game says so (CHALLENGE_MODE_COMPLETED), then the addon
--                waits for the last criteria and the meter's final numbers.
--   Other runs   checked after each boss kill by the clear strategy:
--                  retail   every boss down (Seasons.lua's counts, else the
--                           Encounter Journal's list for this instance)
--                  Forever  the clear rule in settings (Forever.lua)
--
-- Saved: MS:CommitRun is the one way a run leaves MS.currentRun for history.
-- Lifecycle.lua (leaving, abandoning, pause timeouts) and the key's
-- completion here both end in it.

local _max = math.max

local MS = _G["MythicScoreboard"]
local L = MS.L
local _issecret = issecretvalue

local function Readable(v) return v ~= nil and not (_issecret and _issecret(v)) and v or nil end

-- ── Clear strategies ───────────────────────────────────────────────────────
-- A strategy has:
--   isCleared(self, run, killedBoss) -> bool   after each kill
--   canDetect(self, run) -> bool               false: this run can never be
--                                              marked cleared (no boss data),
--                                              so leaving finishes it

-- How many bosses this dungeon has, from the Encounter Journal. The journal
-- is asked about the instance the player is in (by its map, which is what
-- EJ_GetInstanceForMap takes), and its selection isn't changed.
local function JournalBossCount()
    if not (EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex and C_Map and C_Map.GetBestMapForUnit) then
        return nil
    end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    map = ok and Readable(map)
    if type(map) ~= "number" then return nil end
    local ok2, inst = pcall(EJ_GetInstanceForMap, map)
    inst = ok2 and Readable(inst)
    if type(inst) ~= "number" or inst <= 0 then return nil end
    local n = 0
    for i = 1, 40 do
        local ok3, name = pcall(EJ_GetEncounterInfoByIndex, i, inst)
        if not (ok3 and Readable(name)) then break end
        n = n + 1
    end
    return n > 0 and n or nil
end
MS._JournalBossCount = JournalBossCount   -- for tests

local function BossTotal(run)
    if run._bossTotal then return run._bossTotal end
    local n = MS.BOSS_COUNTS and MS.BOSS_COUNTS[run.dungeonName or ""] or JournalBossCount()
    run._bossTotal = n
    return n
end

local BossCount = {
    isCleared = function(_, run)
        local total = BossTotal(run)
        if not total then return false end
        local killed = 0
        for _, b in ipairs(run.bosses or {}) do
            if b.killTime then killed = killed + 1 end
        end
        return killed >= total
    end,
    canDetect = function() return true end,
}

local strategy = BossCount
function MS:SetClearStrategy(s) strategy = s end

function MS:IsRunCleared(run, killedBoss)
    run = run or self.currentRun
    return run ~= nil and strategy.isCleared(self, run, killedBoss) == true
end

function MS:CanDetectClear(run) return strategy.canDetect(self, run) ~= false end

-- Runs end on leaving the dungeon under this clear rule (never cleared).
function MS:LeaveEndsRuns() return self:GetClearRule() == "leave" end

-- ── After a kill ───────────────────────────────────────────────────────────
function MS:MarkCleared(run, at)
    run.completed = true
    run.clearedAt = at
    run._clearedClock = GetTime()
    self:SaveCurrentRun()
    C_Timer.After(0.5, function()
        if MS:GetAutoOpenOnComplete() then MS:ShowScoreboard() end
    end)
end

-- After a boss kill outside Mythic+: decide whether the run is cleared.
-- The decision only needs the boss list, so it's made straight away, even
-- if the group is still fighting (classic-style dungeons often are: adds,
-- trash, a long pull after the last boss). The meter is read once combat
-- ends, since its numbers can be hidden until then.
function MS:CheckClearedAfterKill(killedBoss)
    C_Timer.After(1.5, function()
        local run = MS.currentRun
        if not MS.inDungeon or not run or run.completed then return end
        if MS:IsRunCleared(run, killedBoss) then
            MS:MarkCleared(run, killedBoss and killedBoss.killTime)
        end
        if not InCombatLockdown() then MS:SnapshotFromDamageMeter() end
    end)
end

-- ── Leaving ────────────────────────────────────────────────────────────────
-- What leaving makes of an unfinished run, before it's saved. Returns true
-- when the "leaving" clear rule is in force.
function MS:ApplyLeaveRules(run)
    if not run then return false end
    -- A fight still open is over: ended when combat did, if that's known.
    local ab = run.activeBoss
    if ab and not ab.killTime and not ab.wipeTime then
        self:CloseOpenFight(run, run._combatEndedAt or ab.pullTime)
    end
    -- Final boss down with optional bosses left: leaving finishes it, cleared.
    if not run.completed and run.finalDown then
        local last = 0
        for _, b in ipairs(run.bosses or {}) do last = _max(last, b.killTime or 0) end
        run.completed = true
        if last > 0 then
            run.clearedAt = last
            -- The run ended at that kill: deaths after it (waiting around
            -- before leaving) aren't the run's.
            for _, p in pairs(run.players or {}) do
                local kept = {}
                for _, de in ipairs(p.deathEvents or {}) do
                    if (de.time or 0) <= last + 2 then kept[#kept + 1] = de end
                end
                if p.deathEvents and #kept < #p.deathEvents then
                    p.deaths = math.max(0, (p.deaths or 0) - (#p.deathEvents - #kept))
                    p.deathEvents = kept
                end
            end
        end
    end
    local leaveMode = self:LeaveEndsRuns()
    -- Dungeons the addon has no boss data for can never be marked cleared,
    -- so leaving them counts as finishing rather than abandoning.
    if (leaveMode or not self:CanDetectClear(run)) and not run.completed then
        run.finishedOnLeave = true
        if leaveMode then run.clearRule = "leave" end
    end
    return leaveMode
end

-- ── Mythic+ ────────────────────────────────────────────────────────────────
-- The key's official result: time in milliseconds and whether it was in
-- time. CHALLENGE_MODE_COMPLETED carries no values; the game keeps them in
-- GetChallengeCompletionInfo (11.0.5+), or GetCompletionInfo before that.
local function KeyResult()
    if not C_ChallengeMode then return nil end
    if C_ChallengeMode.GetChallengeCompletionInfo then
        local ok, info = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
        if ok and type(info) == "table" then
            local ms, onTime = Readable(info.time), Readable(info.onTime)
            if type(ms) == "number" and ms > 0 then return ms, onTime end
        end
    end
    if C_ChallengeMode.GetCompletionInfo then
        local ok, _, _, ms, onTime = pcall(C_ChallengeMode.GetCompletionInfo)
        ms, onTime = ok and Readable(ms), ok and Readable(onTime)
        if type(ms) == "number" and ms > 0 then return ms, onTime end
    end
end

-- Time the key lost to deaths, as the game counts it.
function MS:KeyDeathPenalty()
    if not (C_ChallengeMode and C_ChallengeMode.GetDeathCount) then return nil end
    local ok, _, timeLost = pcall(C_ChallengeMode.GetDeathCount)
    timeLost = ok and Readable(timeLost)
    return type(timeLost) == "number" and timeLost >= 0 and timeLost or nil
end

-- The key is done. Its time and result are known now; the meter's numbers
-- are hidden for a moment, so the save waits (FinalizeKey).
function MS:OnKeyCompleted(totalTimeMs, onTime)
    local run = self.currentRun
    if not (self.inDungeon and run) then return end
    self:SetRunState("finishing")
    if not totalTimeMs then totalTimeMs, onTime = KeyResult() end
    run.deathPenaltySeconds = self:KeyDeathPenalty() or run.deathPenaltySeconds

    local elapsed = totalTimeMs and totalTimeMs > 0 and totalTimeMs / 1000 or nil
    if not elapsed then elapsed = GetWorldElapsedTime and select(2, GetWorldElapsedTime(1)) end
    if not (elapsed and elapsed > 0) then elapsed = GetTime() - run.startTime end
    run.duration = elapsed

    local inTime = onTime
    if type(inTime) ~= "boolean" then inTime = nil end
    if inTime == nil then
        local limit = run.keystoneTimeLimit
        inTime = (limit and limit > 0 and elapsed > 0) and elapsed <= limit or false
    end
    run.completed = true
    run.inTime    = inTime
    -- Saved once SCENARIO_CRITERIA_UPDATE says every criterion is done, or
    -- after 3 seconds regardless.
    run._pendingFinalize = true
    self:SaveCurrentRun()
    C_Timer.After(3, function()
        if MS.currentRun == run and run._pendingFinalize then MS:FinalizeKey(run) end
    end)
end

function MS:OnScenarioCriteriaUpdate()
    local run = self.currentRun
    if run and run._pendingFinalize and self:AllCriteriaComplete() then self:FinalizeKey(run) end
end

-- Waits for the meter to show its numbers again, then saves the key.
local FINALIZE_DELAY, FINALIZE_STEP, FINALIZE_TRIES = 2, 0.1, 60
function MS:FinalizeKey(run)
    if not run or self.currentRun ~= run then return end
    run._pendingFinalize = nil
    run.currentPct = 100
    local tries = 0
    local function Try()
        if self.currentRun ~= run then return end
        tries = tries + 1
        if self:IsMeterHidden() and tries < FINALIZE_TRIES then
            C_Timer.After(FINALIZE_STEP, Try)
            return
        end
        self:CommitRun({ snapshot = true, show = true })
    end
    C_Timer.After(FINALIZE_DELAY, Try)
end

-- ── Saving ─────────────────────────────────────────────────────────────────
-- Ends the current run and saves it to history.
--   outcome.completed   mark it cleared (a run already cleared stays so)
--   outcome.inTime      the key's result (left as it is when nil)
--   outcome.snapshot    read the meter first; by default yes, except for
--                       keys (the meter is hidden as a key ends) and paused
--                       runs (the meter may hold another place's numbers)
--   outcome.show        open the scoreboard afterwards
function MS:CommitRun(outcome)
    local run = self.currentRun
    if not run then return end
    outcome = outcome or {}
    local paused = run._suspended ~= nil
    -- Its length: up to now, or when it was paused, or the kill that cleared it.
    if not run.duration then
        local d = self:GetRunDuration(run)
        -- A key's own timer is gone once it's reset: the game clock, then.
        if d <= 0 and run.startTime then d = _max(0, GetTime() - run.startTime) end
        run.duration = d
    end
    if outcome.completed then run.completed = true end
    if outcome.inTime ~= nil then run.inTime = outcome.inTime end
    self:SetRunState("finishing")

    local snapshot = outcome.snapshot
    if snapshot == nil then snapshot = (run.keystoneLevel or 0) == 0 and not paused end
    if snapshot then self:SnapshotFromDamageMeter() end
    self:PopulateAll()
    self:_BackfillSyntheticInterrupts(run)

    local before = self:BestKeyTime(run.dungeonName, run.keystoneLevel)
    self:_CommitRunToHistory(run)
    self:_AnnouncePB(run, before)
    self:ClearSavedActiveRun()
    self.displayRun = nil
    self:SetRunState("none")
    if self.RefreshOverview then self:RefreshOverview() end
    if outcome.show then C_Timer.After(0.5, function() MS:ShowScoreboard() end) end
end

-- Older name, kept for anything that still calls it.
function MS:EndRun(completed, inTime)
    self:CommitRun({ completed = completed, inTime = inTime })
end

-- Drops the current run without saving: the placeholder made while waiting
-- for a keystone to be inserted.
function MS:DiscardCurrentRun()
    self:ClearSavedActiveRun()
    self:SetRunState("none")
end

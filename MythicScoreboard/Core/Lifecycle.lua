-- When a run starts, pauses, resumes and ends.
--
-- A run is in one of four states:
--
--   none       no run in progress
--   active     in the dungeon, recording          (MS.inDungeon == true)
--   paused     stepped outside before the run was done (currentRun._suspended set)
--   finishing  being saved (a key waiting for its final numbers, or the
--              moment between ending a run and committing it); reads as none
--
-- MS:SetRunState() is the only thing that changes MS.currentRun / MS.inDungeon
-- / currentRun._suspended, and it switches the run-only polls and listeners
-- on and off (the watchers below), so no transition can forget them.
--
-- MS:CheckLocation() is the only place that moves between them based on
-- where the player is. Zone and loading-screen events call it a few times
-- while the game's instance info settles (see MS:ScheduleLocationChecks).
-- Mythic+ start/finish come from the CHALLENGE_MODE_* events in Events.lua,
-- which use the same Begin/Finish functions. Whether a run is cleared, and
-- saving it, is Completion.lua.

local _max = math.max
local MS = _G["MythicScoreboard"]

local MYTHIC_PLUS = MS.MYTHIC_PLUS
local PAUSE_LIMIT = 30 * 60      -- a paused run closes after this many seconds

local function Say(msg) print("|cff00ccff[MythicScoreboard]|r " .. msg) end

-- ── Difficulties ───────────────────────────────────────────────────────────
local DIFF_LABEL = {
    [1]="Normal",      [2]="Heroic",    [23]="Mythic",
    [8]="Mythic Keystone",
    [24]="Timewalking", [33]="Timewalking",
    [205]="Follower (N)", [207]="Follower (H)", [208]="Follower (M)",
}

-- Difficulty groups: Flavor.lua.

function MS:DifficultyLabel(diff)
    if DIFF_LABEL[diff] then return DIFF_LABEL[diff] end
    if GetDifficultyInfo then
        local ok, name = pcall(GetDifficultyInfo, diff)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "Unknown"
end

function MS:CurrentDifficulty() return select(3, GetInstanceInfo()) or 0 end

function MS:IsTrackedDifficulty(diff)
    local catchAll
    for _, grp in ipairs(MS.DIFF_GROUPS) do
        if grp.catchAll then catchAll = grp end
        for _, id in ipairs(grp.ids) do
            if id == diff then
                return self:IsDifficultyGroupOn(grp.key)
            end
        end
    end
    if catchAll and diff then
        if catchAll.alwaysOn then return true end
        return self:IsDifficultyGroupOn(catchAll.key)
    end
    return false
end

-- ── Where are we ───────────────────────────────────────────────────────────
function MS:CurrentDungeonName()
    local instanceName, itype = GetInstanceInfo()
    if instanceName and instanceName ~= "" and itype == "party" then
        return instanceName
    end
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local id = C_ChallengeMode.GetActiveChallengeMapID()
        if id and id > 0 then
            local info = C_ChallengeMode.GetMapInfo and C_ChallengeMode.GetMapInfo(id)
            if info and info.name then return info.name end
        end
    end
    return GetRealZoneText() or "Unknown"
end

function MS:CurrentKeystoneLevel()
    return (C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo
        and select(1, C_ChallengeMode.GetActiveKeystoneInfo())) or 0
end

-- The player's map (a wing or floor of the dungeon), when the game says.
local function CurrentUiMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and type(map) == "number" and not (issecretvalue and issecretvalue(map)) then return map end
end

-- Whether a paused run can carry on here: the same dungeon, and for an
-- instance with several wings, the same wing (the map you started in).
local function SamePlace(self, run)
    if self:CurrentDungeonName() ~= run.dungeonName then return false end
    if self.DungeonHasWings and self:DungeonHasWings(run.dungeonName) and run.uiMapID then
        local here = CurrentUiMap()
        if here and here ~= run.uiMapID then return false end
    end
    return true
end

local function ActiveChallengeMap()
    return C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
        and C_ChallengeMode.GetActiveChallengeMapID()
end

-- ── State ──────────────────────────────────────────────────────────────────
MS._deadUnits = MS._deadUnits or {}   -- units seen dead, so each death counts once

function MS:RunState()
    local run = self.currentRun
    if self.inDungeon and run then return "active" end
    if run and run._suspended then return "paused" end
    return "none"
end

-- Things that only need to run during a run (polls, event listeners) are
-- switched on and off here, so nothing ticks or listens while you're out in
-- the world. Each watcher gets the state and should do nothing if it hasn't
-- changed.
local _watchers = {}
function MS:WatchRunState(fn) _watchers[#_watchers + 1] = fn end
function MS:UpdateRunWatchers()
    local state = self:RunState()
    for i = 1, #_watchers do _watchers[i](state) end
end

-- The one place the run state changes.
--   "active", run?   recording (run becomes the current run when given)
--   "paused"         stepped out; keeps the moment it was paused
--   "finishing"      being saved: not recording, not paused
--   "none"           no run
function MS:SetRunState(state, run)
    if run then self.currentRun = run end
    local cur = self.currentRun
    if state == "none" then
        self.currentRun, self.inDungeon = nil, false
    elseif state == "active" then
        if cur then cur._suspended = nil end
        self.inDungeon = cur ~= nil
    elseif state == "paused" then
        -- (time logged out so far is noted: it doesn't count toward the run)
        if cur then cur._suspended = cur._suspended or { at = time(), offline = cur._offline } end
        self.inDungeon = false
    elseif state == "finishing" then
        if cur then cur._suspended = nil end
        self.inDungeon = false
    else
        error("unknown run state " .. tostring(state))
    end
    if state ~= "active" then wipe(self._deadUnits) end
    self:UpdateRunWatchers()
end

-- A repeating timer that only runs in some run states.
function MS:StateTicker(every, states, fn)
    local ticker
    self:WatchRunState(function(state)
        local want = states[state] or false
        if want and not ticker then
            ticker = C_Timer.NewTicker(every, fn)
        elseif not want and ticker then
            ticker:Cancel(); ticker = nil
        end
    end)
end

function MS:AutoResetMeter()
    if not self:GetAutoResetMeter() then return end
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        C_DamageMeter.ResetAllCombatSessions()
    end
end

-- Pets appear a moment after a zone-in; look again a few times.
function MS:WarmPetCache(...)
    self:RebuildPetGUIDCache()
    for i = 1, select("#", ...) do
        C_Timer.After((select(i, ...)), function() MS:RebuildPetGUIDCache() end)
    end
end

-- ── Transitions ────────────────────────────────────────────────────────────
-- ── Starting a run ─────────────────────────────────────────────────────────
-- The key's affixes: the keystone's own list, else the week's.
local function CurrentAffixes()
    local out = {}
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local _, ids = C_ChallengeMode.GetActiveKeystoneInfo()
        for _, id in ipairs(ids or {}) do out[#out + 1] = { id = id } end
    end
    if #out == 0 and C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
        for _, af in ipairs(C_MythicPlus.GetCurrentAffixes() or {}) do
            local id = af.affixID or af.id
            if id then out[#out + 1] = { id = id } end
        end
    end
    return out
end

-- A new run, recording from now.
function MS:StartRun(dungeonName, keystoneLevel, difficultyID, difficultyLabel)
    self.itemLevelCache = {}
    self.displayRun     = nil
    local run = MS.NewRunData()
    self:SetRunState("active", run)
    run.dungeonName     = dungeonName or "Unknown Dungeon"
    run.keystoneLevel   = keystoneLevel or 0
    run.difficultyID    = difficultyID or 0
    run.difficultyLabel = difficultyLabel or ""
    run.startTime       = GetTime()
    run.challengeMapID  = ActiveChallengeMap()
    local instanceID    = select(8, GetInstanceInfo())
    if type(instanceID) == "number" and not (issecretvalue and issecretvalue(instanceID)) then
        run.instanceID = instanceID
    end
    run.affixes = CurrentAffixes()
    run.uiMapID = CurrentUiMap()
    -- Meter not reset for this run: its first reading is the zero point (Meter.lua).
    if not self:GetAutoResetMeter() then run._baselinePending = true end

    if difficultyID == MYTHIC_PLUS then
        run.keystoneTimeLimit = self:KnownTimeLimit(run)
        if not run.keystoneTimeLimit then
            -- The map's info can take a moment after the key starts.
            local function TryFetchTimeLimit()
                if self.currentRun ~= run or run.keystoneTimeLimit then return end
                run.challengeMapID = run.challengeMapID or ActiveChallengeMap()
                local tl = self:KnownTimeLimit(run)
                if tl then
                    run.keystoneTimeLimit = tl
                    self:SaveCurrentRun()
                    if self.RefreshOverview then self:RefreshOverview() end
                end
            end
            C_Timer.After(1.0, TryFetchTimeLimit)
            C_Timer.After(4.0, TryFetchTimeLimit)
        end
        run.currentPct = 0
    end

    local function SeedPlayers()
        if self.currentRun ~= run then return end
        for _, unit in ipairs(self:GroupUnits()) do self:EnsurePlayer(unit) end
    end
    SeedPlayers()
    -- Solo, or the group not loaded yet: look again in a moment.
    if GetNumGroupMembers() == 0 then
        C_Timer.After(2.0, function()
            SeedPlayers()
            self:PopulateAll()
            self:PopulateRolesAndScores()
            if self.RefreshOverview then self:RefreshOverview() end
        end)
    end
    self:PopulateAll()
    self:PopulateRolesAndScores()
    run._wallClockStart = time()
    self:SaveCurrentRun()
    if self.RefreshOverview then self:RefreshOverview() end
    -- Short delay lets roster seeding settle before first snapshot.
    C_Timer.After(0.5, function()
        if self.currentRun and not InCombatLockdown() then
            self:SnapshotFromDamageMeter()
            self:SaveCurrentRun()
            if self.RefreshOverview then self:RefreshOverview() end
        end
    end)
end

-- none -> active: a new run in the dungeon we're standing in.
function MS:BeginRun()
    if self.inDungeon then return end
    local diff = self:CurrentDifficulty()
    if not self:IsTrackedDifficulty(diff) then return end
    local name, level = self:CurrentDungeonName(), self:CurrentKeystoneLevel()
    -- Abandoned by hand while still inside: no new run until you've left.
    if self._abandonedIn and self._abandonedIn == name and level == 0 then return end
    self._abandonedIn = nil
    -- A paused run elsewhere is saved first (a key started while it waited).
    if self:RunState() == "paused" then self:ClosePausedRun() end
    self:StartRun(name, level, diff, self:DifficultyLabel(diff))
    Say("Run started: " .. (level > 0 and (name .. " +" .. level)
                                      or (name .. " [" .. self:DifficultyLabel(diff) .. "]")))
end

-- active or paused -> none: save the run to history, applying the clear rules.
function MS:FinishRun(completed, inTime)
    local state = self:RunState()
    if state ~= "active" and state ~= "paused" then return end
    local leaveMode = self:ApplyLeaveRules(self.currentRun)
    self:CommitRun({ completed = completed, inTime = inTime or false })
    if leaveMode and self:GetAutoOpenOnComplete() then
        C_Timer.After(2, function() MS:ShowScoreboard() end)
    end
end

-- active -> paused: left before the run was done (released after dying,
-- or out to repair/sell). Walking back in resumes the run.
function MS:PauseRun()
    local run = self.currentRun
    if not (self.inDungeon and run) then return end
    self:SnapshotFromDamageMeter()          -- last numbers from inside
    self:SetRunState("paused")
    self:SaveCurrentRun()
    Say("Run paused. Return to " .. (run.dungeonName or "the dungeon")
        .. " within " .. (PAUSE_LIMIT / 60) .. " minutes to continue it.")
end

-- paused -> active
function MS:ResumeRun()
    local run = self.currentRun
    if not (run and run._suspended) then return end
    self:SetRunState("active")
    self:WarmPetCache(1.0)
    self:SaveCurrentRun()
    Say("Run resumed: " .. (run.dungeonName or ""))
    if self.RefreshOverview then self:RefreshOverview() end
end

-- paused -> none: closed as abandoned (or finished, under the clear rules).
function MS:ClosePausedRun()
    local run = self.currentRun
    if not (run and run._suspended) then return end
    self:FinishRun(false, false)            -- applies the clear rules
end

-- active or paused -> none, by hand: saved as abandoned, whatever the clear
-- rules would say. Standing in the dungeon doesn't start a new run until you
-- leave it (or reset it).
function MS:AbandonRun()
    local run = self.currentRun
    if not run or run.completed then return false end
    run.finalDown, run.finishedOnLeave, run.clearedAt = nil, nil, nil
    run.abandoned = true
    if self.inDungeon then self._abandonedIn = run.dungeonName end
    self:CommitRun({ completed = false, inTime = false })
    Say("Run abandoned: " .. (run.dungeonName or ""))
    return true
end

-- ── The location check ─────────────────────────────────────────────────────
-- Moves between states based on where the player is. Safe to call any time;
-- calling it twice in a row with nothing changed does nothing.
--
-- `confirmedOutside` must be true before an active run is ended or paused,
-- so a single odd reading during a loading screen can't close it.
local function CheckLocation(self, confirmedOutside)
    local _, itype, diff = GetInstanceInfo()
    local inTracked = itype == "party" and self:IsTrackedDifficulty(diff)
    local state, run = self:RunState(), self.currentRun

    if state == "active" then
        if inTracked then return "inside" end
        if (run.keystoneLevel or 0) > 0 then
            -- A key keeps running if you step out to the open world.
            if ActiveChallengeMap() or itype ~= "party" then return "inside" end
        end
        if not confirmedOutside then return "outside" end
        -- Unfinished: pause, so a corpse run or a repair trip doesn't end it.
        -- Cleared runs, and the "leaving the dungeon" clear rule, end here;
        -- but a ghost outside is on a corpse run, whatever the rule.
        local leaveRule = self:LeaveEndsRuns()
        local ghost = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
        if issecretvalue and issecretvalue(ghost) then ghost = false end
        if (run.keystoneLevel or 0) == 0 and not run.completed and not run.finalDown
                and (not leaveRule or ghost) then
            self:PauseRun()
        else
            self:FinishRun(false, false)
        end
        return "outside"

    elseif state == "paused" then
        if not (inTracked and diff ~= MYTHIC_PLUS) then return "outside" end
        if SamePlace(self, run) then
            self:ResumeRun()
            return "inside"
        end
        self:ClosePausedRun()                -- a different dungeon: start over
        state = "none"
    end

    if not inTracked then self._abandonedIn = nil end
    if state == "none" and inTracked and diff ~= MYTHIC_PLUS then
        self:AutoResetMeter()
        self:BeginRun()
        self:WarmPetCache(1.0, 3.0)
        return "inside"
    end
    return inTracked and "inside" or "outside"
end

-- Every location check ends by updating the watchers.
function MS:CheckLocation(confirmedOutside)
    local where = CheckLocation(self, confirmedOutside)
    self:UpdateRunWatchers()
    return where
end

-- After a zone change the instance info can take a few seconds to settle,
-- so look again over ~8 seconds. Leaving needs two "outside" readings in a
-- row; a newer zone change restarts the sequence.
local CHECK_DELAYS = { 0.4, 1.2, 2.4, 4.8, 8.4 }   -- seconds after the event
local _seq = 0
function MS:ScheduleLocationChecks()
    _seq = _seq + 1
    local mySeq, idx, outsideBefore = _seq, 1, false
    local function step()
        if mySeq ~= _seq then return end          -- superseded by a newer zone change
        outsideBefore = (MS:CheckLocation(outsideBefore) == "outside")
        local nextAt = CHECK_DELAYS[idx + 1]
        if nextAt then
            local wait = nextAt - CHECK_DELAYS[idx]
            idx = idx + 1
            C_Timer.After(wait, step)
        end
    end
    C_Timer.After(CHECK_DELAYS[1], step)
end

-- A reset instance is a fresh dungeon: the paused run can't continue in it.
-- The game announces it as "<Dungeon> has been reset." to the group.
local _resetPattern
if type(INSTANCE_RESET_SUCCESS) == "string" then
    local escaped = INSTANCE_RESET_SUCCESS:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    _resetPattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end
local resetFrame = CreateFrame("Frame")
MS:WatchRunState(function(state)              -- only listened for while paused
    if state == "paused" then pcall(resetFrame.RegisterEvent, resetFrame, "CHAT_MSG_SYSTEM")
    else resetFrame:UnregisterEvent("CHAT_MSG_SYSTEM") end
end)
resetFrame:SetScript("OnEvent", function(_, _, msg)
    local run = MS.currentRun
    if not (_resetPattern and run and run._suspended and type(msg) == "string") then return end
    if issecretvalue and issecretvalue(msg) then return end
    local dungeon = msg:match(_resetPattern)
    if dungeon and dungeon == run.dungeonName then MS:ClosePausedRun() end
end)

-- A paused run doesn't wait forever.
MS:StateTicker(30, { paused = true }, function()
    local run = MS.currentRun
    if run and run._suspended and run._suspended.at and time() - run._suspended.at > PAUSE_LIMIT then
        MS:ClosePausedRun()
    end
end)

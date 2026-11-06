local _max  = math.max

local MS = _G["MythicScoreboard"]

local _issecret = issecretvalue

-- Difficulties, run start/pause/resume/end and the location check live in
-- Lifecycle.lua. This file routes game events to them.
local MYTHIC_PLUS = MS.MYTHIC_PLUS

local BOSS_COUNTS = MS.BOSS_COUNTS   -- Seasons.lua

-- Every setting's default, in one place.
local DEFAULTS = {
    autoResetMeter          = true,
    autoOpenOnComplete      = true,
    historyLimit            = 10,
    clearRule               = "final",
    showMobForces           = true,
    showMobForcesNameplates = true,
    minimapButton           = true,
}

local _deadUnits = MS._deadUnits

local function HandleUnitDied()
    if not MS.inDungeon then return end
    local run = MS.currentRun
    if not run then return end
    local worldElapsed = GetWorldElapsedTime and select(2, GetWorldElapsedTime(1))
    local now = (worldElapsed and worldElapsed > 0)
        and worldElapsed
        or  _max(0, GetTime() - run.startTime)
    for _, unit in ipairs(MS:GroupUnits()) do
        -- Skip mind-controlled mobs temporarily showing as players in the roster.
        if UnitIsPlayer(unit) then
            local dead = UnitIsDeadOrGhost(unit)
            if dead and not _deadUnits[unit] then
                _deadUnits[unit] = true
                local p = MS:PlayerForUnit(unit)
                if p and not MS:IsDupDeath(p, now) then
                    MS:RecordDeathEvent(p)
                end
            elseif not dead and _deadUnits[unit] then
                _deadUnits[unit] = nil
            end
        end
    end
end

local function HandleDamageMeterUpdated()
    if not MS.inDungeon then return end
    if MS:SnapshotFromDamageMeter() then MS:RefreshOverview() end
end

local function SyncRoster()
    if not MS.inDungeon or not MS.currentRun then return end
    if GetNumGroupMembers() == 0 then return end
    local present = {}
    for _, unit in ipairs(MS:GroupUnits()) do
        local p = MS:EnsurePlayer(unit)
        if p then present[p] = true end
    end
    for _, p in pairs(MS.currentRun.players) do
        if not present[p] then p.left = true end
    end
end

-- After a boss kill (non-Mythic+): decide whether the run is cleared.
-- Classic-style dungeons often stay in combat after a kill (adds, trash),
-- so retry until combat ends rather than skipping the check.
function MS:_CheckCompletionAfterKill(killedBoss, attempt)
    attempt = attempt or 1
    C_Timer.After(attempt == 1 and 1.5 or 2, function()
        if not MS.inDungeon or not MS.currentRun then return end
        if InCombatLockdown() then
            if attempt < 60 then MS:_CheckCompletionAfterKill(killedBoss, attempt + 1) end
            return
        end
        MS:SnapshotFromDamageMeter()
        if not MS.currentRun or MS.currentRun.completed then return end

        local cleared
        if MS.CheckRunCleared then
            cleared = MS:CheckRunCleared(MS.currentRun, killedBoss)
        else
            local dungName    = MS.currentRun.dungeonName or ""
            local totalBosses = BOSS_COUNTS[dungName]
            if not totalBosses then
                local ejInstance = EJ_GetInstanceForMap
                    and MS.currentRun.challengeMapID
                    and EJ_GetInstanceForMap(MS.currentRun.challengeMapID)
                if ejInstance and ejInstance > 0 then
                    local ok = pcall(EJ_SelectInstance, ejInstance)
                    if ok then
                        local idx = 1; totalBosses = 0
                        while EJ_GetEncounterInfoByIndex(idx, ejInstance) do
                            totalBosses = totalBosses + 1; idx = idx + 1
                        end
                        if totalBosses == 0 then totalBosses = nil end
                    end
                end
            end
            if totalBosses then
                local killed = 0
                for _, b in ipairs(MS.currentRun.bosses) do
                    if b.killTime then killed = killed + 1 end
                end
                cleared = killed >= totalBosses
            end
        end

        if cleared then
            MS.currentRun.completed = true
            MS.currentRun.clearedAt = killedBoss and killedBoss.killTime
            MS:SaveCurrentRun()
            C_Timer.After(0.5, function()
                if MS:GetAutoOpenOnComplete() then MS:ShowScoreboard() end
            end)
        end
    end)
end

local frame = CreateFrame("Frame")

-- COMBAT_LOG_EVENT_UNFILTERED and DAMAGE_METER_COMBAT_SESSION_UPDATED are
-- blocked in Midnight instances; damage is polled via C_DamageMeter instead.
local _eventsToRegister = {
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT",
    "PLAYER_DIFFICULTY_CHANGED",
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
    "ENCOUNTER_START", "ENCOUNTER_END",
    "PLAYER_DEAD", "GROUP_ROSTER_UPDATE",
    "UNIT_PET",
    "SCENARIO_CRITERIA_UPDATE",
}

local function RegisterAllEvents()
    for _, ev in ipairs(_eventsToRegister) do pcall(frame.RegisterEvent, frame, ev) end
end

-- Defer registration if loaded mid-combat to avoid ADDON_ACTION_FORBIDDEN.
if InCombatLockdown() then
    local _deferFrame = CreateFrame("Frame")
    _deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _deferFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        RegisterAllEvents()
    end)
else
    RegisterAllEvents()
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == "MythicScoreboard" then
            MythicScoreboardDB = MythicScoreboardDB or { runs = {} }
            MythicScoreboardDB.runs = MythicScoreboardDB.runs or {}
            MythicScoreboardDB.personalBests = MythicScoreboardDB.personalBests or {}
            local s = MythicScoreboardDB.settings
            if not s then
                MythicScoreboardDB.settings = {}
                s = MythicScoreboardDB.settings
            end
            for k, v in pairs(DEFAULTS) do
                if s[k] == nil then s[k] = v end
            end
            -- Defaults come from each difficulty group (Forever.lua swaps the groups).
            if s.trackedDifficulties      == nil then s.trackedDifficulties = {} end
            for _, grp in ipairs(MS.DIFF_GROUPS) do
                if s.trackedDifficulties[grp.key] == nil then
                    s.trackedDifficulties[grp.key] = grp.default and true or false
                end
            end
            MythicScoreboardDB.mobForces = MythicScoreboardDB.mobForces or {}
            if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable) then
                print("|cffff4444[MythicScoreboard]|r C_DamageMeter unavailable — requires WoW 12.0+.")
            end
            MS:RunMigrations()                  -- saved data up to date before anything reads it
            if MS.SyncAccountStats then MS:SyncAccountStats() end   -- this character's runs, account-wide
            -- The window is built the first time it's opened.
            if MS.UpdateMinimapButton then MS:UpdateMinimapButton() end
            local _, itype = GetInstanceInfo()
            local active = MythicScoreboardDB.activeRun
            if active and (itype == "party" or active._suspended) then
                MS:RestoreCurrentRun()
                C_Timer.After(0.2, function() MS:RefreshOverview() end)
            end
            print("|cff00ccff[MythicScoreboard]|r v" .. MS.version .. "  /sb to open.")
        end

    elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
        MS:FlushSave()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Reload inside a run: the run was restored at ADDON_LOADED.
        if MS.inDungeon then MS:WarmPetCache(1.0, 3.0, 6.0) end
        MS:ScheduleLocationChecks()

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_DIFFICULTY_CHANGED" then
        MS:ScheduleLocationChecks()

    elseif event:find("^CHALLENGE_MODE_") and not C_ChallengeMode then
        return

    elseif event == "CHALLENGE_MODE_START" then
        local mapID = C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID()
        if not mapID then return end

        local newName  = MS:CurrentDungeonName()
        local newLevel = MS:CurrentKeystoneLevel()

        -- Same dungeon+level, unfinished run → resume rather than restart.
        if MS.currentRun and (MS.currentRun.keystoneLevel or 0) > 0
                and not MS.currentRun.completed
                and MS.currentRun.dungeonName == newName
                and MS.currentRun.keystoneLevel == newLevel then
            MS:SetRunState("active")
            MS:WarmPetCache(1.0, 3.0)
            return
        end

        -- Commit any in-progress run before starting fresh.
        if MS.currentRun and (MS.currentRun.keystoneLevel or 0) > 0
                and not MS.currentRun.completed then
            if MS.inDungeon then
                MS:FinishRun(false, false)
            else
                MS:EndRun(false, false)
            end
        elseif MS.inDungeon then
            -- Discard a non-M+ placeholder started before the key was inserted.
            MS:DiscardCurrentRun()
        end

        MS:AutoResetMeter(); MS:BeginRun()
        wipe(MS._petGUIDToOwner)
        if MS._petNameToOwner then wipe(MS._petNameToOwner) end
        MS:WarmPetCache(1.0, 3.0)

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        if MS.inDungeon and MS.currentRun then
            MS:SetRunState("finishing")       -- saved once the final numbers can be read

            local _, _, totalTimeMs, onTime = ...

            local worldElapsed
            if totalTimeMs and totalTimeMs > 0 then
                worldElapsed = totalTimeMs / 1000
            else
                worldElapsed = GetWorldElapsedTime and select(2, GetWorldElapsedTime(1))
            end

            if not (worldElapsed and worldElapsed > 0) then
                worldElapsed = GetTime() - MS.currentRun.startTime
            end
            MS.currentRun.duration = worldElapsed

            local inTime
            if onTime ~= nil then
                inTime = onTime
            else
                local timeLimit = MS.currentRun.keystoneTimeLimit
                if timeLimit and timeLimit > 0 and worldElapsed and worldElapsed > 0 then
                    inTime = worldElapsed <= timeLimit
                else
                    inTime = false
                end
            end

            MS.currentRun.completed = true
            MS.currentRun.inTime    = inTime
            -- Wait for SCENARIO_CRITERIA_UPDATE to confirm all criteria complete.
            MS.currentRun._pendingFinalize = true
            MS:SaveCurrentRun()
            local safetyRun = MS.currentRun
            C_Timer.After(3, function()
                if MS.currentRun == safetyRun and safetyRun._pendingFinalize then
                    safetyRun._pendingFinalize = nil
                    safetyRun.currentPct = 100
                    MS:FinalizeMythicPlusRun()
                end
            end)
        end

    elseif event == "CHALLENGE_MODE_RESET" then
        if MS.inDungeon then
            MS:FinishRun(false, false)
        elseif MS.currentRun and not MS.currentRun.completed then
            wipe(_deadUnits)
            MS:EndRun(false, false)
        end

    elseif event == "ENCOUNTER_START" then
        -- encounterID here is the dungeonEncounterID from EJ_GetEncounterInfoByIndex,
        -- not the journal's own encounter ID — they're different namespaces.
        local encounterID, bossName = ...
        if MS.inDungeon then MS:BossPull(bossName or "Boss", encounterID) end

    elseif event == "ENCOUNTER_END" then
        local encounterID, bossName, _, _, success = ...
        if MS.inDungeon then
            if success == 0 then
                MS:BossWipe(bossName or "Boss", encounterID)
            elseif success == 1 then
                local killedBoss = MS:BossKill(bossName or "Boss", encounterID)
                MS:SnapshotBossProgress(killedBoss)
                if MS:CurrentDifficulty() ~= MYTHIC_PLUS then
                    MS:_CheckCompletionAfterKill(killedBoss)
                end
            end
        end

    elseif event == "SCENARIO_CRITERIA_UPDATE" then
        MS:UpdateEnemyForcesProgress()
        if MS.currentRun and MS.currentRun._pendingFinalize then
            local allDone = false
            if C_Scenario and C_Scenario.GetStepInfo then
                local ok, _, _, numCriteria = pcall(C_Scenario.GetStepInfo)
                if ok and numCriteria and numCriteria > 0 then
                    local completedCount = 0
                    for i = 1, numCriteria do
                        local ok2, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
                        if ok2 and info and info.completed then completedCount = completedCount + 1 end
                    end
                    allDone = (completedCount >= numCriteria)
                end
            end
            if allDone then
                MS.currentRun._pendingFinalize = nil
                MS.currentRun.currentPct = 100
                MS:FinalizeMythicPlusRun()
            end
        end

    elseif event == "PLAYER_DEAD" then
        if MS.inDungeon then HandleUnitDied() end

    elseif event == "GROUP_ROSTER_UPDATE" then
        MS:InvalidateGroupUnits()
        if MS.currentRun and MS.currentRun._suspended and GetNumGroupMembers() == 0 then
            MS:ClosePausedRun()
            return
        end
        SyncRoster(); MS:PopulateAll()
        MS:PopulateRolesAndScores()
        MS:RebuildPetGUIDCache()
        C_Timer.After(2.0, function() MS:RebuildPetGUIDCache() end)
        if MS.currentRun and (MS.currentRun.keystoneLevel or 0) > 0
                and not MS.currentRun.completed
                and GetNumGroupMembers() == 0 then
            if MS.inDungeon then
                MS:FinishRun(false, false)
            else
                MS:EndRun(false, false)
            end
            return
        end
        C_Timer.After(2.0, function()
            if MS.RefreshOverview and MS.sbFrameVisible and MS.sbFrameVisible() then
                MS:RefreshOverview()
            end
        end)

    elseif event == "UNIT_PET" then
        -- Read the pet GUID immediately — this is the window before any lockdown.
        local ownerUnit = ...
        if ownerUnit then
            local petUnit = ownerUnit .. "pet"
            if UnitExists(petUnit) then
                local ok, petGUID = pcall(UnitGUID, petUnit)
                if ok and petGUID and not (_issecret and _issecret(petGUID))
                        and type(petGUID) == "string"
                        and (petGUID:find("^Pet%-") or petGUID:find("^Creature%-")) then
                    local ownerName = MS:UnitPlayerName(ownerUnit)
                    if ownerName and not (_issecret and _issecret(ownerName)) then
                        MS._petGUIDToOwner[petGUID] = MS.ShortName(ownerName)
                    end
                end
            end
        end
        MS:RebuildPetGUIDCache()
        C_Timer.After(0.5, function() MS:RebuildPetGUIDCache() end)
        C_Timer.After(1.5, function() MS:RebuildPetGUIDCache() end)
    end
end)

-- Poll C_DamageMeter every 2s (DAMAGE_METER_COMBAT_SESSION_UPDATED is blocked
-- in M+) and death state every 0.75s (UNIT_DIED via CLEU is blocked in M+).
-- Both only run while you're in a run.
local ACTIVE = { active = true }
MS:StateTicker(2, ACTIVE, function()
    local ok, err = pcall(HandleDamageMeterUpdated)
    if not ok then
        print("|cffff4444[MythicScoreboard]|r Meter poll error: " .. tostring(err))
    end
end)
MS:StateTicker(0.75, ACTIVE, function()
    if not MS.inDungeon then return end
    local ok, err = pcall(HandleUnitDied)
    if not ok then
        print("|cffff4444[MythicScoreboard]|r Death poll error: " .. tostring(err))
    end
end)

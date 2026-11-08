-- Game events, routed to where they're handled.
--
-- Run start/pause/resume/end and the location check: Lifecycle.lua.
-- Cleared runs and saving them: Completion.lua. Bosses and deaths:
-- Encounters.lua. Loading saved data: Bootstrap.lua.

local MS = _G["MythicScoreboard"]
local L = MS.L
local IsSecret = _G["MythicScoreboard"].IsSecret

local MYTHIC_PLUS = MS.MYTHIC_PLUS

local function IsKey(run) return run and (run.keystoneLevel or 0) > 0 end

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

-- An unfinished key ends (reset, or the group gone): saved as it stands.
local function EndUnfinishedKey()
    if MS.inDungeon then MS:FinishRun(false, false) else MS:EndRun(false, false) end
end

local function ResetPetCaches()
    wipe(MS._petGUIDToOwner)
    if MS._petNameToOwner then wipe(MS._petNameToOwner) end
end

-- ── Handlers ───────────────────────────────────────────────────────────────
local H = {}

function H.PLAYER_LEAVING_WORLD() MS:FlushSave() end
H.PLAYER_LOGOUT = H.PLAYER_LEAVING_WORLD

function H.PLAYER_ENTERING_WORLD()
    -- Reload inside a run: the run was restored at ADDON_LOADED.
    if MS.inDungeon then MS:WarmPetCache(1.0, 3.0, 6.0) end
    MS:ScheduleLocationChecks()
end

function H.ZONE_CHANGED_NEW_AREA() MS:ScheduleLocationChecks() end
H.PLAYER_DIFFICULTY_CHANGED = H.ZONE_CHANGED_NEW_AREA

function H.CHALLENGE_MODE_START()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID()
    if not mapID then return end
    local run = MS.currentRun
    local name, level = MS:CurrentDungeonName(), MS:CurrentKeystoneLevel()

    -- Same dungeon and level, unfinished: carry on rather than restart.
    if IsKey(run) and not run.completed and run.dungeonName == name and run.keystoneLevel == level then
        MS:SetRunState("active")
        MS:WarmPetCache(1.0, 3.0)
        return
    end
    if IsKey(run) and not run.completed then
        EndUnfinishedKey()                  -- a different key: save the old one first
    elseif MS.inDungeon then
        MS:DiscardCurrentRun()              -- the placeholder from before the key went in
    end

    MS:AutoResetMeter(); MS:BeginRun()
    ResetPetCaches()
    MS:WarmPetCache(1.0, 3.0)
end

function H.CHALLENGE_MODE_COMPLETED(_, _, totalTimeMs, onTime)
    MS:OnKeyCompleted(totalTimeMs, onTime)
end

function H.CHALLENGE_MODE_RESET()
    if MS.inDungeon then
        MS:FinishRun(false, false)
    elseif MS.currentRun and not MS.currentRun.completed then
        wipe(MS._deadUnits)
        MS:EndRun(false, false)
    end
end

function H.PLAYER_REGEN_ENABLED()
    if MS.inDungeon and MS.OnCombatEnded then MS:OnCombatEnded() end
end
function H.PLAYER_REGEN_DISABLED()
    local run = MS.currentRun
    if run then run._combatEndedAt = nil end
end

-- encounterID is the dungeonEncounterID (as in EJ_GetEncounterInfoByIndex's
-- seventh value), not the journal's own encounter ID.
function H.ENCOUNTER_START(encounterID, bossName)
    if MS.inDungeon then MS:BossPull(bossName or "Boss", encounterID) end
end

function H.ENCOUNTER_END(encounterID, bossName, _, _, success)
    if not MS.inDungeon then return end
    if success == 0 then
        MS:BossWipe(bossName or "Boss", encounterID)
    elseif success == 1 then
        local killedBoss = MS:BossKill(bossName or "Boss", encounterID)
        MS:SnapshotBossProgress(killedBoss)
        if MS:CurrentDifficulty() ~= MYTHIC_PLUS then MS:CheckClearedAfterKill(killedBoss) end
    end
end

function H.SCENARIO_CRITERIA_UPDATE()
    MS:UpdateEnemyForcesProgress()
    MS:OnScenarioCriteriaUpdate()
end

function H.PLAYER_DEAD() if MS.inDungeon then MS.PollDeaths() end end

function H.GROUP_ROSTER_UPDATE()
    MS:InvalidateGroupUnits()
    local run = MS.currentRun
    if run and run._suspended and GetNumGroupMembers() == 0 then
        MS:ClosePausedRun()
        return
    end
    SyncRoster(); MS:PopulateAll()
    MS:PopulateRolesAndScores()
    MS:RebuildPetGUIDCache()
    C_Timer.After(2.0, function() MS:RebuildPetGUIDCache() end)
    if IsKey(MS.currentRun) and not MS.currentRun.completed and GetNumGroupMembers() == 0 then
        EndUnfinishedKey()
        return
    end
    C_Timer.After(2.0, function() MS:Changed("run") end)
end

function H.UNIT_PET(ownerUnit)
    -- Read the pet GUID immediately: this is the window before any lockdown.
    if ownerUnit then
        local petUnit = ownerUnit .. "pet"
        if UnitExists(petUnit) then
            local ok, petGUID = pcall(UnitGUID, petUnit)
            if ok and petGUID and not IsSecret(petGUID)
                    and type(petGUID) == "string"
                    and (petGUID:find("^Pet%-") or petGUID:find("^Creature%-")) then
                local ownerName = MS:UnitPlayerName(ownerUnit)
                if ownerName then MS._petGUIDToOwner[petGUID] = MS.ShortName(ownerName) end
            end
        end
    end
    MS:RebuildPetGUIDCache()
    C_Timer.After(0.5, function() MS:RebuildPetGUIDCache() end)
    C_Timer.After(1.5, function() MS:RebuildPetGUIDCache() end)
end

MS.EventHandlers = H        -- Bootstrap.lua adds ADDON_LOADED

-- ── Registration ───────────────────────────────────────────────────────────
-- COMBAT_LOG_EVENT_UNFILTERED and DAMAGE_METER_COMBAT_SESSION_UPDATED are
-- blocked in Midnight instances; damage is polled via C_DamageMeter instead.
local frame = CreateFrame("Frame")
local EVENTS = {
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT",
    "PLAYER_DIFFICULTY_CHANGED",
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
    "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "PLAYER_DEAD", "GROUP_ROSTER_UPDATE",
    "UNIT_PET",
    "SCENARIO_CRITERIA_UPDATE",
}

local function RegisterAllEvents()
    for _, ev in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, ev) end
end

-- Defer registration if loaded mid-combat to avoid ADDON_ACTION_FORBIDDEN.
if InCombatLockdown() then
    local deferFrame = CreateFrame("Frame")
    deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    deferFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        RegisterAllEvents()
    end)
else
    RegisterAllEvents()
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event:find("^CHALLENGE_MODE_") and not C_ChallengeMode then return end
    local fn = H[event]
    if fn then fn(...) end
end)

-- ── Polls ──────────────────────────────────────────────────────────────────
-- C_DamageMeter every 2s (DAMAGE_METER_COMBAT_SESSION_UPDATED is blocked in
-- M+) and death state every 0.75s (UNIT_DIED via the combat log is blocked).
-- Both only run while you're in a run.
local ACTIVE = { active = true }
local function SayOnce(what, err) MS:ReportError(what, err) end
MS:StateTicker(2, ACTIVE, function()
    if not MS.inDungeon then return end
    local ok, err = pcall(function()
        if MS:SnapshotFromDamageMeter() then MS:Changed("run") end
    end)
    if not ok then SayOnce("Meter poll", err) end
end)
MS:StateTicker(0.75, ACTIVE, function()
    if not MS.inDungeon then return end
    local ok, err = pcall(MS.PollDeaths)
    if not ok then SayOnce("Death poll", err) end
end)

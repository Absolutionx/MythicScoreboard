-- Keeping the run in progress across a /reload or logout.
--
-- The game writes saved variables to disk only at logout and /reload, never
-- during play (nor after a crash), so the run in progress is copied into
-- them only then (PLAYER_LEAVING_WORLD / PLAYER_LOGOUT call FlushSave).
-- SaveCurrentRun just notes that there's something to write. It also marks
-- the run as changed, so the scoreboard redraws its rows.

local MS = _G["MythicScoreboard"]
local L = MS.L

local OFFLINE_AFTER = 60     -- a gap longer than this between saving and loading was a logout

function MS:SaveCurrentRun()
    self._saveDirty = true
    local run = self.currentRun
    if run then run._seq = (run._seq or 0) + 1 end
end

function MS:FlushSave()
    if not MythicScoreboardDB then return end
    self._saveDirty = false
    if not self.currentRun then MythicScoreboardDB.activeRun = nil; return end
    local ok, err = pcall(function()
        local saved = self:SerializeRun(self.currentRun, true)
        saved._active         = true
        saved._wallClockStart = self.currentRun._wallClockStart or time()
        saved._savedAt        = time()
        MythicScoreboardDB.activeRun = saved
        local pets = {}
        for guid, owner in pairs(self._petGUIDToOwner) do pets[guid] = owner end
        MythicScoreboardDB.petGUIDCache = pets
    end)
    if not ok then
        print("|cffff4444[MythicScoreboard]|r " .. L["Saving the run in progress failed:"] .. " " .. tostring(err))
    end
end

function MS:ClearSavedActiveRun()
    if MythicScoreboardDB then MythicScoreboardDB.activeRun = nil end
end

function MS:RestoreCurrentRun()
    if not MythicScoreboardDB or not MythicScoreboardDB.activeRun then return end
    local saved = MythicScoreboardDB.activeRun
    if not saved._active then return end
    -- Time logged out doesn't count (a /reload's few seconds do). A key's
    -- clock is the game's own and needs none of this.
    local now = time()
    local gap = saved._savedAt and (now - saved._savedAt) or 0
    local offline = (saved._offline or 0) + (gap > OFFLINE_AFTER and gap or 0)
    local elapsed = math.max(0, now - (saved._wallClockStart or now) - offline)
    -- Everything the run had (cleared, the clear rule, boss fights, ...),
    -- with times moved onto this session's clock.
    local run = MS.NewRunData()
    for k, v in pairs(saved) do run[k] = v end
    run._active          = nil
    run._savedAt         = nil
    run._offline         = offline > 0 and offline or nil
    run.dungeonName      = saved.dungeonName or "Unknown"
    run.startTime        = GetTime() - elapsed
    run.duration         = nil
    run._wallClockStart  = saved._wallClockStart
    run.players          = saved.players or {}
    run.bosses           = saved.bosses or {}
    run.affixes          = saved.affixes or {}
    -- A fight in progress at the reload: the copy saved as activeBoss is
    -- the same fight as the one in the boss list.
    run.activeBoss = nil
    local ab = saved.activeBoss
    if ab then
        for _, b in ipairs(run.bosses) do
            if b.name == ab.name and b.pullTime == ab.pullTime and not b.killTime then run.activeBoss = b end
        end
    end
    -- Cleared before the reload: the clear's moment on the game clock (deaths
    -- after it aren't the run's). Its saved value only holds while the
    -- computer hasn't restarted; past the clear by now either way.
    if run.completed then
        local t = GetTime()
        local c = tonumber(run._clearedClock)
        if not c or c > t or elapsed > 0 and c < t - elapsed - 60 then run._clearedClock = t - 10 end
    end
    if MythicScoreboardDB.petGUIDCache then
        for guid, owner in pairs(MythicScoreboardDB.petGUIDCache) do
            self._petGUIDToOwner[guid] = owner
        end
    end
    self.itemLevelCache = {}
    self.specCache = {}
    self:SetRunState(run._suspended and "paused" or "active", run)
    print("|cff00ccff[MythicScoreboard]|r " .. L["Run restored after UI reload."])
end

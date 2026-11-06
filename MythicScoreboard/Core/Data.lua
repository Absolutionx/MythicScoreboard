local _abs   = math.abs
local _fmt   = string.format
local _floor = math.floor
local _min   = math.min
local _max   = math.max
local _ins   = table.insert
local _rem   = table.remove

local MS = _G["MythicScoreboard"]


local _issecret = issecretvalue  -- nil on pre-12.0 clients

-- Seconds into a run. Every time inside a run (boss pulls and kills, deaths,
-- interrupts, loot) counts from its start the same way.
--   finished   run.duration, fixed when it ended
--   live key   the key's own timer (GetWorldElapsedTime, from the countdown)
--   live       the game clock since the start (run.startTime, this session
--              only: it's worked out again after a /reload)
local function GetCurrentElapsed(run)
    if not run then return 0 end
    if run.duration then return run.duration end
    if (run.keystoneLevel or 0) > 0 then
        if GetWorldElapsedTime then
            local worldElapsed = select(2, GetWorldElapsedTime(1))
            if worldElapsed and worldElapsed > 0 then return worldElapsed end
        end
        return 0
    end
    -- A cleared dungeon's time stops at the kill that cleared it.
    if run.completed and run.clearedAt then return run.clearedAt end
    -- A paused run's clock stands still until you're back inside.
    local sus = run._suspended
    if sus and sus.at and run._wallClockStart and sus.at > run._wallClockStart then
        return sus.at - run._wallClockStart
    end
    return _max(0, GetTime() - run.startTime)
end

-- Mythic+ time limits: Seasons.lua.

local MYTHIC_PLUS = MS.MYTHIC_PLUS

-- Names, GUIDs, group units and player lookups live in Roster.lua.

local DUPLICATE_DEATH_WINDOW = 2

function MS:IsDupDeath(p, now)
    return _abs((p._lastDeathTime or -999) - now) < DUPLICATE_DEATH_WINDOW
end

local function NewRunData()
    return {
        dungeonName          = "",
        keystoneLevel        = 0,
        difficultyID         = 0,
        difficultyLabel      = "",
        startTime            = 0,
        completed            = false,
        inTime               = false,
        affixes              = {},
        players              = {},
        bosses               = {},
        activeBoss           = nil,
        deathPenaltySeconds  = 0,
        currentPct           = nil,
        _wallClockStart      = nil,
        challengeMapID       = nil,  -- UiMapID for EJ icon resolution
    }
end

local function NewPlayerStats(name, classToken, guid)
    return {
        name                 = name,
        class                = classToken or "UNKNOWN",
        guid                 = guid,
        role                 = "",
        damageDone           = 0,
        healingDone          = 0,
        damageTaken          = 0,
        avoidableDamageTaken = 0,
        dps                  = 0,
        hps                  = 0,
        interrupts           = 0,
        interruptEvents      = {},
        dispels              = 0,
        deaths               = 0,
        deathEvents          = {},
        mythicScore          = 0,
        itemLevel            = 0,
        deathRecapID         = 0,
        loot                 = {},
        level                = 0,
    }
end

MS.currentRun      = nil
MS.inDungeon       = false
MS.scoreCache      = {}
MS.NewPlayerStats  = NewPlayerStats


local SYNTH_INTERRUPT_MIN_WINDOW = 2

-- Interrupts are kept as a plain list of times (to a tenth of a second);
-- runs saved before 2.5 have { time = t, spell = "Unknown" } tables instead.
local function EventTime(e) return type(e) == "table" and (e.time or 0) or e or 0 end
MS.EventTime = EventTime
local function Tenth(t) return _floor(t * 10 + 0.5) / 10 end
MS.Tenth = Tenth


-- Fills in synthetic interruptEvent timestamps from the C_DamageMeter count.
-- Distributes events evenly across the current boss window with per-player
-- jitter to avoid stacking timeline markers.
function MS:_BackfillSyntheticInterrupts(run)
    run = run or self.currentRun
    if not run then return end
    local now = GetCurrentElapsed(run)

    local bossAnchor = 0
    if run.bosses then
        for _, boss in ipairs(run.bosses) do
            local pt = boss.pullTime or 0
            if pt <= now and pt > bossAnchor then bossAnchor = pt end
        end
    end

    local function playerJitter(name)
        local h = 0
        for i = 1, #name do h = h + name:byte(i) end
        return ((h % 31) / 30 - 0.5) * 6.0
    end

    for _, p in pairs(run.players) do
        p.interruptEvents = p.interruptEvents or {}
        local recorded = #p.interruptEvents
        local total    = p.interrupts or 0
        local delta    = total - recorded
        if delta > 0 then
            local tStart = bossAnchor
            if recorded > 0 then
                tStart = _max(tStart, EventTime(p.interruptEvents[recorded]))
            end
            local window = now - tStart
            if window < SYNTH_INTERRUPT_MIN_WINDOW then
                tStart = _max(0, now - SYNTH_INTERRUPT_MIN_WINDOW)
                window = now - tStart
            end
            local step   = window / (delta + 1)
            local jitter = playerJitter(p.name or "")
            for i = 1, delta do
                local t = tStart + step * i + jitter
                _ins(p.interruptEvents, Tenth(_max(tStart, _min(now, t))))
            end
        end
    end
end

-- Inserts at index 1 so the newest run is always first.
function MS:_CommitRunToHistory(run)
    if not (MythicScoreboardDB and MythicScoreboardDB.runs) then return end
    local cap = MythicScoreboardDB.settings and MythicScoreboardDB.settings.historyLimit or 10
    cap = _max(1, _min(30, cap))
    local saved = self:SerializeRun(run)
    _ins(MythicScoreboardDB.runs, 1, saved)
    while #MythicScoreboardDB.runs > cap do _rem(MythicScoreboardDB.runs) end
    -- Loot (e.g. the Mythic+ chest) can arrive after this; Loot.lua attaches
    -- it to the saved copy for a few minutes.
    self._lastCommittedRun = saved
    self._lastCommittedAt  = GetTime()
    if self.ArchiveRun then self:ArchiveRun(saved) end   -- permanent summary (Archive.lua)
end

-- Drops the current run without saving. Used to discard the Mythic (diff=23)
-- placeholder that's created while waiting for a keystone to be inserted.
function MS:DiscardCurrentRun()
    if MythicScoreboardDB then MythicScoreboardDB.activeRun = nil end
    self:SetRunState("none")
end

-- Announces a PB or first clear. Must be called after _CommitRunToHistory.
function MS:_AnnouncePB(run)
    if not (run.completed and run.inTime and (run.keystoneLevel or 0) > 0) then return end
    if not MythicScoreboardDB then return end
    local thisDur = self:GetRunDuration(run)
    local key = (run.dungeonName or "") .. ":" .. run.keystoneLevel

    MythicScoreboardDB.personalBests = MythicScoreboardDB.personalBests or {}
    local prevBest = MythicScoreboardDB.personalBests[key]
    if not prevBest and MythicScoreboardDB.runs then
        for i = 2, #MythicScoreboardDB.runs do
            local r = MythicScoreboardDB.runs[i]
            if r.completed and r.inTime
                    and r.dungeonName == run.dungeonName
                    and (r.keystoneLevel or 0) == run.keystoneLevel then
                local dur = r.duration or 0
                if dur > 0 and (not prevBest or dur < prevBest) then prevBest = dur end
            end
        end
    end

    local timeStr = self:FormatTime(thisDur)
    if not prevBest or thisDur < prevBest then
        MythicScoreboardDB.personalBests[key] = thisDur
        if not prevBest then
            print(_fmt("|cff00ccff[MythicScoreboard]|r |cffffcc00** First recorded clear!|r %s +%d -- %s",
                run.dungeonName, run.keystoneLevel, timeStr))
        else
            print(_fmt("|cff00ccff[MythicScoreboard]|r |cffffcc00** New personal best!|r %s +%d -- %s |cff888888(-%s)|r",
                run.dungeonName, run.keystoneLevel, timeStr,
                self:FormatTime(prevBest - thisDur)))
        end
    end
end

-- Reading C_DamageMeter into the run lives in Meter.lua.

-- Inspect queue for item levels.
-- Frame is created lazily — CreateFrame can't be called at file scope.
local inspectQueue   = {}
local inspectPending = nil
local INSPECT_DELAY  = 0.5
local inspectFrame   = nil

local function EnsureInspectFrame()
    if inspectFrame then return end
    inspectFrame = CreateFrame("Frame")
    inspectFrame:RegisterEvent("INSPECT_READY")
    inspectFrame:SetScript("OnEvent", function(_, event, guid)
        if event ~= "INSPECT_READY" or not inspectPending then return end
        local targetUnit
        for _, unit in ipairs(MS:GroupUnits()) do
            if UnitGUID(unit) == guid then targetUnit = unit; break end
        end
        local name = inspectPending
        inspectPending = nil
        if targetUnit and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
            local il = C_PaperDollInfo.GetInspectItemLevel(targetUnit)
            if il and il > 0 then
                il = _floor(il)
                MS.itemLevelCache = MS.itemLevelCache or {}
                MS.itemLevelCache[name] = il
                local p = MS:PlayerByName(name)
                if p then p.itemLevel = il end
                if MS.RefreshOverview and MS.sbFrameVisible and MS.sbFrameVisible() then
                    MS:RefreshOverview()
                end
            end
        end
        ClearInspectPlayer()
        if #inspectQueue > 0 then
            C_Timer.After(INSPECT_DELAY, function() MS:_ProcessInspectQueue() end)
        end
    end)
end

function MS:_ProcessInspectQueue()
    if inspectPending or #inspectQueue == 0 then return end
    if InCombatLockdown() then
        C_Timer.After(5.0, function() self:_ProcessInspectQueue() end); return
    end
    EnsureInspectFrame()
    local entry = _rem(inspectQueue, 1)
    local unit
    for _, u in ipairs(self:GroupUnits()) do
        local p = self:PlayerForUnit(u)
        if p and p.name == entry.name then unit = u; break end
    end
    if unit and CanInspect(unit) then
        inspectPending = entry.name
        NotifyInspect(unit)
        local pendingAtCall = entry.name
        C_Timer.After(5.0, function()
            if inspectPending == pendingAtCall then
                inspectPending = nil
                ClearInspectPlayer()
                if #inspectQueue > 0 then
                    C_Timer.After(INSPECT_DELAY, function() self:_ProcessInspectQueue() end)
                end
            end
        end)
    elseif #inspectQueue > 0 then
        C_Timer.After(INSPECT_DELAY, function() self:_ProcessInspectQueue() end)
    end
end

-- Roles and scores are stable mid-run; only call on GROUP_ROSTER_UPDATE.
function MS:PopulateRolesAndScores()
    if not self.currentRun then return end
    for _, unit in ipairs(self:GroupUnits()) do
        local p = self:PlayerForUnit(unit)
        local short = p and p.name
        do
            if p then
                local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
                if role and role ~= "" and role ~= "NONE" then p.role = role end
                local sc = C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
                    and C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
                if sc and sc.currentSeasonScore and sc.currentSeasonScore > 0 then
                    p.mythicScore = sc.currentSeasonScore
                    if self.scoreCache then self.scoreCache[short] = sc.currentSeasonScore end
                elseif self.scoreCache and self.scoreCache[short] then
                    p.mythicScore = self.scoreCache[short]
                end
            end
        end
    end
end

function MS:PopulateAll()
    if not self.currentRun then return end
    self.itemLevelCache = self.itemLevelCache or {}
    local needsInspect = false
    for _, unit in ipairs(self:GroupUnits()) do
        local p = self:PlayerForUnit(unit)
        local short = p and p.name
        do
            if p then
                -- Character level matters in Forever's levelling dungeons and
                -- can change mid-run, so it's refreshed on every snapshot.
                local lvl = UnitLevel and UnitLevel(unit)
                if type(lvl) == "number" and lvl > 0 and not (_issecret and _issecret(lvl)) then
                    p.level = lvl
                end
                local cached = self.itemLevelCache[short]
                if cached and cached > 0 then
                    p.itemLevel = cached
                elseif not inspectPending then
                    local already = false
                    for _, e in ipairs(inspectQueue) do
                        if e.name == short then already = true; break end
                    end
                    if not already then
                        _ins(inspectQueue, { name = short })
                        needsInspect = true
                    end
                end
            end
        end
    end
    if needsInspect then
        C_Timer.After(INSPECT_DELAY, function() self:_ProcessInspectQueue() end)
    end
end

function MS:StartRun(dungeonName, keystoneLevel, difficultyID, difficultyLabel)
    self.itemLevelCache = {}
    self.displayRun     = nil
    self:SetRunState("active", NewRunData())
    self.currentRun.dungeonName     = dungeonName or "Unknown Dungeon"
    self.currentRun.keystoneLevel   = keystoneLevel or 0
    self.currentRun.difficultyID    = difficultyID or 0
    self.currentRun.difficultyLabel = difficultyLabel or ""
    self.currentRun.startTime       = GetTime()
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        self.currentRun.challengeMapID = C_ChallengeMode.GetActiveChallengeMapID()
    end
    -- Prefer keystone API (plain integer array), fall back to C_MythicPlus.
    local affixesRaw
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local _, keystoneAffixes = C_ChallengeMode.GetActiveKeystoneInfo()
        if keystoneAffixes and #keystoneAffixes > 0 then
            affixesRaw = keystoneAffixes
        end
    end
    if not affixesRaw and C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
        local afs = C_MythicPlus.GetCurrentAffixes()
        if afs and #afs > 0 then
            affixesRaw = {}
            for _, af in ipairs(afs) do
                local id = af.affixID or af.id
                if id then _ins(affixesRaw, id) end
            end
        end
    end
    if affixesRaw then
        for _, id in ipairs(affixesRaw) do
            _ins(self.currentRun.affixes, { id = id })
        end
    end

    if difficultyID == MYTHIC_PLUS then
        local knownLimit = MS.DUNGEON_TIMERS and MS.DUNGEON_TIMERS[dungeonName or ""]
        if knownLimit then
            self.currentRun.keystoneTimeLimit = knownLimit
        end

        if not self.currentRun.keystoneTimeLimit and C_ChallengeMode then
            local function TryFetchTimeLimit()
                if not self.currentRun then return end
                if C_ChallengeMode.GetActiveKeystoneInfo then
                    local _, _, tl = C_ChallengeMode.GetActiveKeystoneInfo()
                    local tlNum = tonumber(tl)
                    if tlNum and tlNum > 10 and tlNum < 7200 then
                        self.currentRun.keystoneTimeLimit = tlNum
                        self:SaveCurrentRun()
                        if self.RefreshOverview then self:RefreshOverview() end
                    end
                end
            end
            TryFetchTimeLimit()
            C_Timer.After(1.0, TryFetchTimeLimit)
            C_Timer.After(4.0, TryFetchTimeLimit)
        end

        self.currentRun.currentPct = 0
    end

    local function SeedPlayers()
        if not self.currentRun then return end
        for _, unit in ipairs(self:GroupUnits()) do self:EnsurePlayer(unit) end
    end

    SeedPlayers()
    -- Deferred seed for solo/late-join cases.
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
    self.currentRun._wallClockStart = time()
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

function MS:EndRun(completed, inTime)
    if not self.currentRun then return end
    -- Its length: up to now, or when it was paused (a run closed while paused
    -- ends when it was paused), or the kill that cleared it.
    local sus, run = self.currentRun._suspended, self.currentRun
    if not run.duration then
        local d = GetCurrentElapsed(run)
        -- A key's own timer is gone once it's reset: the game clock, then.
        if d <= 0 and run.startTime then d = _max(0, GetTime() - run.startTime) end
        run.duration = d
    end
    -- Don't overwrite completed=true already set by boss-count check.
    if not self.currentRun.completed then
        self.currentRun.completed = completed
    end
    self.currentRun.inTime = inTime
    self:SetRunState("finishing")
    -- M+ skips snapshot here: C_DamageMeter is still protected at
    -- CHALLENGE_MODE_COMPLETED. Deferred to FinalizeMythicPlusRun().
    -- A run closed while paused (released and never came back) keeps the
    -- numbers it had; the meter may hold another place's data by now.
    if (self.currentRun.keystoneLevel or 0) == 0 and not sus then
        self:SnapshotFromDamageMeter()
    end
    self:PopulateAll()
    self:_CommitRunToHistory(self.currentRun)
    self:_AnnouncePB(self.currentRun)
    if MythicScoreboardDB then MythicScoreboardDB.activeRun = nil end
    self.displayRun = nil
    self:SetRunState("none")
    if self.RefreshOverview then self:RefreshOverview() end
end

-- C_DamageMeter values are protected immediately when a key completes.
-- Poll until protection clears, then snapshot and open the scoreboard.
function MS:FinalizeMythicPlusRun()
    if not self.currentRun then return end
    local capturedRun = self.currentRun

    local attempts    = 0
    local maxAttempts = 60

    local function TryFinalize()
        if self.currentRun ~= capturedRun then return end
        attempts = attempts + 1
        if self:IsMeterHidden() and attempts < maxAttempts then
            C_Timer.After(0.1, TryFinalize)
            return
        end
        self:SnapshotFromDamageMeter()
        if not self.currentRun.currentPct or self.currentRun.currentPct < 100 then
            self.currentRun.currentPct = 100
        end
        self:PopulateAll()
        self:_CommitRunToHistory(self.currentRun)
        self:_AnnouncePB(self.currentRun)
        MythicScoreboardDB.activeRun = nil
        self.displayRun = nil
        self:SetRunState("none")
        C_Timer.After(0.5, function() self:ShowScoreboard() end)
    end

    C_Timer.After(2, TryFinalize)
end

-- The game writes saved variables to disk only at logout and /reload, never
-- during play (nor after a crash), so the run in progress is copied into
-- them only then (PLAYER_LEAVING_WORLD / PLAYER_LOGOUT call FlushSave).
-- SaveCurrentRun just notes that there's something to write.
-- It also marks the run as changed, so the scoreboard redraws its rows.
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
        MythicScoreboardDB.activeRun = saved
        local pets = {}
        for guid, owner in pairs(self._petGUIDToOwner) do pets[guid] = owner end
        MythicScoreboardDB.petGUIDCache = pets
    end)
    if not ok then
        print("|cffff4444[MythicScoreboard]|r Saving the run in progress failed: " .. tostring(err))
    end
end

function MS:RestoreCurrentRun()
    if not MythicScoreboardDB or not MythicScoreboardDB.activeRun then return end
    local saved = MythicScoreboardDB.activeRun
    if not saved._active then return end
    local elapsed = time() - (saved._wallClockStart or time())
    -- Everything the run had (cleared, the clear rule, boss fights, ...),
    -- with times moved onto this session's clock.
    local run = NewRunData()
    for k, v in pairs(saved) do run[k] = v end
    run._active          = nil
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
    if MythicScoreboardDB.petGUIDCache then
        for guid, owner in pairs(MythicScoreboardDB.petGUIDCache) do
            self._petGUIDToOwner[guid] = owner
        end
    end
    self.itemLevelCache = {}
    self:SetRunState(run._suspended and "paused" or "active", run)
    print("|cff00ccff[MythicScoreboard]|r Run restored after UI reload.")
end

-- Finds the isWeightedProgress scenario criterion and returns completion %.
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
            -- quantityString may be "42%" — strip the suffix for the raw count.
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

-- Looks up the boss portrait (Encounter Journal creature icon) for an
-- encounter and stores it on the boss entry, so the timeline can show it.
-- Cached per encounter in SavedVariables so saved runs keep their portraits.
function MS:_ResolveBossIcon(boss)
    if not boss or boss.icon then return end
    local id = boss.dungeonEncounterId
    if not id or (_issecret and _issecret(id)) then return end
    local cache = MythicScoreboardDB and MythicScoreboardDB.bossIcons
    if cache and cache[id] then boss.icon = cache[id]; return end
    C_Timer.After(0, function()
        local ok, icon = pcall(function()
            if not (EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex and EJ_GetCreatureInfo
                    and C_Map and C_Map.GetBestMapForUnit) then return nil end
            local mapID = C_Map.GetBestMapForUnit("player")
            local inst  = mapID and EJ_GetInstanceForMap(mapID)
            if not inst or inst == 0 then return nil end
            for i = 1, 40 do
                local name, _, journalID, _, _, _, dungeonEncID = EJ_GetEncounterInfoByIndex(i, inst)
                if not name then break end
                if dungeonEncID == id then
                    local _, _, _, _, iconImage = EJ_GetCreatureInfo(1, journalID)
                    return iconImage
                end
            end
        end)
        if ok and icon then
            boss.icon = icon
            if MythicScoreboardDB then
                MythicScoreboardDB.bossIcons = MythicScoreboardDB.bossIcons or {}
                MythicScoreboardDB.bossIcons[id] = icon
            end
            self:SaveCurrentRun()
            if self.RefreshOverview then self:RefreshOverview() end
        end
    end)
end

-- One-time scan of the Adventure Guide: every dungeon boss's portrait, keyed
-- by dungeonEncounterID and by "n:<boss name>". Gives portraits to saved runs
-- recorded before portraits were captured. Skipped in combat and while the
-- Adventure Guide is open (it changes the guide's selected tier briefly).
local _ejIndexBuilt = false
function MS:_BuildEJIndex()
    if _ejIndexBuilt or not MythicScoreboardDB then return end
    if InCombatLockdown() then return end
    if EncounterJournal and EncounterJournal.IsShown and EncounterJournal:IsShown() then return end
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex
            and EJ_GetEncounterInfoByIndex and EJ_GetCreatureInfo) then return end
    _ejIndexBuilt = true
    MythicScoreboardDB.bossIcons = MythicScoreboardDB.bossIcons or {}
    local cache = MythicScoreboardDB.bossIcons
    local prevTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
    pcall(function()
        for tier = EJ_GetNumTiers(), 1, -1 do       -- newest first: remakes win
            EJ_SelectTier(tier)
            for i = 1, 80 do
                local instID = EJ_GetInstanceByIndex(i, false)
                if not instID then break end
                for e = 1, 30 do
                    local name, _, journalID, _, _, _, dungeonEncID = EJ_GetEncounterInfoByIndex(e, instID)
                    if not name then break end
                    local _, _, _, _, icon = EJ_GetCreatureInfo(1, journalID)
                    if icon then
                        if dungeonEncID and not cache[dungeonEncID] then cache[dungeonEncID] = icon end
                        if not cache["n:" .. name] then cache["n:" .. name] = icon end
                    end
                end
            end
        end
    end)
    if prevTier then pcall(EJ_SelectTier, prevTier) end
end

function MS:BossPull(bossName, dungeonEncounterId)
    if not self.currentRun then return end
    local now = GetCurrentElapsed(self.currentRun)
    -- Re-use existing entry on double-fire; stamp as wipe if > 10s have passed.
    for i = #self.currentRun.bosses, 1, -1 do
        local b = self.currentRun.bosses[i]
        if b.name == bossName and not b.killTime and not b.wipeTime then
            local elapsed = now - (b.pullTime or 0)
            if elapsed < 10 then
                self.currentRun.activeBoss = b
                if dungeonEncounterId and not b.dungeonEncounterId then
                    b.dungeonEncounterId = dungeonEncounterId
                end
                return
            else
                b.wipeTime = now
            end
            break
        elseif b.name == bossName and b.wipeTime and not b.killTime then
            break
        end
    end
    local boss = { name = bossName, pullTime = now, dungeonEncounterId = dungeonEncounterId }
    _ins(self.currentRun.bosses, boss)
    self.currentRun.activeBoss = boss
    if self.NoteFightStart then self:NoteFightStart(boss) end
    self:SnapshotBossProgress(boss, true)
    self:_ResolveBossIcon(boss)
    self:SaveCurrentRun()
end

function MS:BossKill(bossName, dungeonEncounterId)
    if not self.currentRun then return nil end
    local t = GetCurrentElapsed(self.currentRun)
    if self.currentRun.activeBoss and self.currentRun.activeBoss.name == bossName then
        local boss = self.currentRun.activeBoss
        boss.killTime = t
        if dungeonEncounterId and not boss.dungeonEncounterId then
            boss.dungeonEncounterId = dungeonEncounterId
        end
        self.currentRun.activeBoss = nil
        if self.NoteFightEnd then self:NoteFightEnd(boss) end
        self:SaveCurrentRun()
        return boss
    end
    for i = #self.currentRun.bosses, 1, -1 do
        local b = self.currentRun.bosses[i]
        if b.name == bossName and not b.killTime and not b.wipeTime then
            b.killTime = t
            if dungeonEncounterId and not b.dungeonEncounterId then
                b.dungeonEncounterId = dungeonEncounterId
            end
            if self.NoteFightEnd then self:NoteFightEnd(b) end
            self:SaveCurrentRun(); return b
        end
    end
    return nil
end

function MS:BossWipe(bossName, dungeonEncounterId)
    if not self.currentRun then return end
    local t = GetCurrentElapsed(self.currentRun)
    local boss = self.currentRun.activeBoss
    if boss and boss.name ~= bossName then boss = nil end
    if not boss then
        for i = #self.currentRun.bosses, 1, -1 do
            local b = self.currentRun.bosses[i]
            if b.name == bossName and not b.killTime and not b.wipeTime then
                boss = b; break
            end
        end
    end
    if boss then
        boss.wipeTime = t
        if dungeonEncounterId and not boss.dungeonEncounterId then
            boss.dungeonEncounterId = dungeonEncounterId
        end
        self.currentRun.activeBoss = nil
        if self.NoteFightEnd then self:NoteFightEnd(boss) end
        self:SaveCurrentRun()
    end
end

-- who: a player from the run, or any form of their name.
function MS:RecordDeathEvent(who)
    if not self.currentRun or not who then return end
    local p = type(who) == "table" and who or self:PlayerByName(who)
    if not p then return end
    local t = GetCurrentElapsed(self.currentRun)
    p.deaths = p.deaths + 1
    p._lastDeathTime = t
    _ins(p.deathEvents, { time = t })
    -- 15s penalty at +12, 5s at +4–11, 0 below +4.
    local level = self.currentRun.keystoneLevel or 0
    if level >= 12 then
        self.currentRun.deathPenaltySeconds = (self.currentRun.deathPenaltySeconds or 0) + 15
    elseif level >= 4 then
        self.currentRun.deathPenaltySeconds = (self.currentRun.deathPenaltySeconds or 0) + 5
    end
    self:SaveCurrentRun()
end

-- Scans all party/raid pet units and populates _petGUIDToOwner.
-- Called on UNIT_PET, GROUP_ROSTER_UPDATE, and CHALLENGE_MODE_START.
-- Additive — never removes entries. Wiped only at CHALLENGE_MODE_START.

function MS:GetAutoResetMeter()
    return MythicScoreboardDB and MythicScoreboardDB.settings
        and MythicScoreboardDB.settings.autoResetMeter
end

function MS:SetAutoResetMeter(value)
    if MythicScoreboardDB and MythicScoreboardDB.settings then
        MythicScoreboardDB.settings.autoResetMeter = value and true or false
    end
end

function MS:GetAutoOpenOnComplete()
    if not (MythicScoreboardDB and MythicScoreboardDB.settings) then return true end
    local v = MythicScoreboardDB.settings.autoOpenOnComplete
    return v == nil or v
end

function MS:SetAutoOpenOnComplete(value)
    if MythicScoreboardDB and MythicScoreboardDB.settings then
        MythicScoreboardDB.settings.autoOpenOnComplete = value and true or false
    end
end

function MS:GetHistoryLimit()
    local v = MythicScoreboardDB and MythicScoreboardDB.settings
        and MythicScoreboardDB.settings.historyLimit
    return _max(1, _min(30, v or 10))
end

function MS:SetHistoryLimit(value)
    value = _max(1, _min(30, _floor(tonumber(value) or 10)))
    if MythicScoreboardDB and MythicScoreboardDB.settings then
        MythicScoreboardDB.settings.historyLimit = value
        if MythicScoreboardDB.runs then
            while #MythicScoreboardDB.runs > value do _rem(MythicScoreboardDB.runs) end
        end
    end
end

function MS:SetSBFrameVisibleCallback(fn) MS.sbFrameVisible = fn end

-- A copy for saving. Fractions are kept to two places: the game writes
-- numbers with all 17 digits, which is most of a saved run's size.
local function SavedCopy(v)
    local tv = type(v)
    if tv == "number" then
        if v % 1 ~= 0 and v == v and v > -1e12 and v < 1e12 then return _floor(v * 100 + 0.5) / 100 end
        return v
    end
    if tv ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = SavedCopy(x) end
    return out
end
-- What a saved run doesn't keep: state that only means something while the
-- run is live (meter bookkeeping, the fight being read, the game clock).
local LIVE = {
    run    = { "_carry", "_carryDur", "_lastDur", "_seq", "_pendingFinalize", "activeBoss",
               "_active", "_suspended", "startTime", "endTime" },
    boss   = { "_before", "_session", "_tries", "_named" },
    player = { "_lastDeathTime" },
}
function MS:StripLive(run)
    for _, k in ipairs(LIVE.run) do run[k] = nil end
    for _, b in ipairs(run.bosses or {}) do
        for _, k in ipairs(LIVE.boss) do b[k] = nil end
    end
    for _, p in pairs(run.players or {}) do
        for _, k in ipairs(LIVE.player) do p[k] = nil end
    end
    return run
end

-- A copy for saving: for history (live state left out), or with keepLive
-- for the run in progress, which carries on after a /reload.
function MS:SerializeRun(run, keepLive)
    local out = SavedCopy(run)
    if not keepLive then self:StripLive(out) end
    -- Loot: the chat link holds the item string; the arrival time and
    -- source only matter while the run is live.
    for _, p in pairs(out.players or {}) do
        for _, l in ipairs(p.loot or {}) do
            if l.link then l.item = nil end
            l.at, l.src = nil, nil
        end
    end
    return out
end

function MS:GetRunDuration(run)
    run = run or self.currentRun
    if not run then return 0 end
    return GetCurrentElapsed(run)
end

function MS:FormatTime(seconds)
    seconds = seconds or 0
    return _fmt("%d:%02d", _floor(seconds / 60), _floor(seconds % 60))
end

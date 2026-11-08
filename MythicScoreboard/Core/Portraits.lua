-- Boss portraits.
--
-- MS:BossPortrait(boss, run) is the one place that decides what a boss's
-- medallion shows. In order:
--   1. the journal's creature icon (retail: saved per encounter)
--   2. a model ID learned from the journal or in play (below)
--   3. Forever's bundled table (Core/BossPortraits.lua, via Forever.lua)
-- and nil when there's nothing: the medallion shows a crest.
--
-- Main source: the game's Encounter Journal, read on entering an instance.
-- WoW Forever has no journal for its dungeons and uses the bundled table in
-- Core/BossPortraits.lua instead (see MS:ForeverBossArt in Core/Forever.lua).
--
-- As a last resort the game is asked for a boss's model ID whenever the addon
-- gets a look at it: encounter start, target, mouseover, nameplate, corpse.
-- Midnight usually hides this; when it does, nothing is recorded.
--
-- IDs are saved account-wide and medallions draw a portrait the game renders
-- from its own model. No artwork ships with the addon.

local MS = _G["MythicScoreboard"]
local L = MS.L
local IsSecret = _G["MythicScoreboard"].IsSecret

local Secret = IsSecret

local Norm = MS.BossKey      -- (the key portraits are saved under)

local function DB()
    MythicScoreboardPortraitsDB = MythicScoreboardPortraitsDB or {}
    local db = MythicScoreboardPortraitsDB
    db.display     = db.display or {}
    db.meta        = db.meta or {}
    db.byEncounter = db.byEncounter or {}
    db.log         = nil   -- diagnostics log from 2.4 test builds
    return db
end
local function Store() return DB().display end

local function Safe(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or Secret(v) then return nil end
    return v
end

local function Changed()
    MS._portraitRev = (MS._portraitRev or 0) + 1
    MS:Changed("portraits")
end

-- ── Encounter Journal ──────────────────────────────────────────────────────
-- The journal lists every boss of an instance with its display ID, and that
-- data isn't restricted. On entering an instance it's copied into the store,
-- so medallions have portraits before anything is pulled. Bosses learned in
-- play are never overwritten.

local _scanned = {}

local function JournalInstanceHere()
    if not (EJ_GetInstanceForMap and C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = Safe(C_Map.GetBestMapForUnit, "player")
    local inst = map and Safe(EJ_GetInstanceForMap, map)
    if type(inst) == "number" and inst > 0 then return inst end
end

local function ScanJournal(instanceID)
    if not (instanceID and EJ_GetEncounterInfoByIndex and EJ_GetCreatureInfo) then return end
    if _scanned[instanceID] then return end
    -- Don't yank the journal window to another instance while it's open.
    if EncounterJournal and EncounterJournal:IsShown() then return end
    pcall(EJ_SelectInstance, instanceID)

    local db = DB()
    local saved = 0
    local function Put(name, display)
        local key = Norm(name)
        if not key then return end
        local m = db.meta[key]
        if db.display[key] and not (m and m.src == "journal") then return end  -- learned in play wins
        if db.display[key] ~= display then saved = saved + 1 end
        db.display[key] = display
        db.meta[key] = { src = "journal" }
    end
    for i = 1, 30 do
        local ok, ename, _, encID, _, _, _, dungeonEncID = pcall(EJ_GetEncounterInfoByIndex, i, instanceID)
        if not ok or Secret(ename) or not ename then break end
        local first
        for c = 1, 9 do
            local ok2, _, cname, _, display = pcall(EJ_GetCreatureInfo, c, encID)
            if not ok2 or Secret(cname) or not cname then break end
            if not Secret(display) and type(display) == "number" and display > 0 then
                first = first or display
                Put(cname, display)
            end
        end
        if first then
            Put(ename, first)   -- the run may record the encounter's name
            if type(dungeonEncID) == "number" and not Secret(dungeonEncID) then
                db.byEncounter[dungeonEncID] = first
            end
        end
    end
    _scanned[instanceID] = true
    if saved > 0 then Changed() end
end

local function ScanHere()
    if IsInInstance and IsInInstance() then ScanJournal(JournalInstanceHere()) end
end

-- ── Learning from live units ───────────────────────────────────────────────
-- Hidden model used only to ask the game for a unit's model ID.
local probe
local function DisplayIDForUnit(unit)
    if not UnitExists(unit) then return nil end
    if not probe then
        probe = CreateFrame("PlayerModel", nil, UIParent)
        probe:SetSize(1, 1)
        probe:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)  -- off-screen
        probe:SetAlpha(0)
    end
    if not pcall(probe.SetUnit, probe, unit) then return nil end
    local ok, id = pcall(probe.GetDisplayInfo, probe)
    if not ok or Secret(id) or type(id) ~= "number" or id <= 0 then return nil end
    return id
end

local function Learn(name, id, src)
    local key = Norm(name)
    if not key or not id then return end
    local db = DB()
    if db.display[key] == id then return end
    db.display[key] = id
    db.meta[key] = { src = src }
    Changed()
end

-- Names this run expects, so an elite only counts if it's a boss here.
local function KnownBossName(name)
    local n = Norm(name)
    if not n then return false end
    local run = MS.currentRun
    for _, b in ipairs(run and run.bosses or {}) do
        if Norm(b.name) == n then return true end
    end
    -- Forever: this dungeon's bosses, or every wing's while it isn't known yet.
    local defs = run and MS.ForeverDefsFor and MS:ForeverDefsFor(run) or {}
    for _, def in ipairs(defs) do
        for _, e in ipairs(def.bosses or {}) do
            if Norm(e.name) == n then return true end
            for _, a in ipairs(e.aka or {}) do if Norm(a) == n then return true end end
        end
    end
    return false
end

-- The game's own boss markers, for bosses the run hasn't met yet.
local function GameSaysBoss(unit)
    if Safe(UnitIsBossMob, unit) then return true end
    if Safe(UnitClassification, unit) == "worldboss" then return true end
    return Safe(UnitLevel, unit) == -1 and Safe(UnitClassification, unit) == "elite"
end

local _tried = {}       -- name key -> GetTime() of last attempt
local RETRY_SECS = 5

local function TryUnit(unit, src, alsoAs)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    if Secret(name) or type(name) ~= "string" then name = nil end
    local id = DisplayIDForUnit(unit)
    if not id then return end
    if name then Learn(name, id, src) end
    if alsoAs and alsoAs ~= name then Learn(alsoAs, id, src) end
end

-- Units seen outside the encounter: only bosses, and only if not known yet.
local function Consider(unit, src)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    if Safe(UnitIsFriend, "player", unit) then return end
    local name = UnitName(unit)
    if Secret(name) or type(name) ~= "string" then return end
    local key = Norm(name)
    if Store()[key] then return end
    if not (KnownBossName(name) or GameSaysBoss(unit)) then return end
    local last = _tried[key]
    if last and GetTime() - last < RETRY_SECS then return end
    _tried[key] = GetTime()
    TryUnit(unit, src)
end

local function SweepNameplates(src)
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then Consider(unit, src) end
    end
end

-- ── Public ─────────────────────────────────────────────────────────────────
-- Model ID for a boss (by encounter, name or any alias), if known.
function MS:LearnedBossDisplay(boss, aliases)
    local db = MythicScoreboardPortraitsDB
    local store = db and db.display
    if not store or not boss then return nil end
    local enc = boss.dungeonEncounterId
    if enc and db.byEncounter and db.byEncounter[enc] then return db.byEncounter[enc] end
    local id = store[Norm(boss.name) or ""]
    if id then return id end
    for _, a in ipairs(aliases or {}) do
        id = store[Norm(a) or ""]
        if id then return id end
    end
    return nil
end

-- ── Journal icons (retail) ─────────────────────────────────────────────────
-- The journal's creature icon for an encounter, cached per encounter in
-- MythicScoreboardDB.bossIcons so saved runs keep their portraits.
local function IconCache(create)
    local db = rawget(_G, "MythicScoreboardDB")
    if not db then return nil end
    if create then db.bossIcons = db.bossIcons or {} end
    return db.bossIcons
end

local function CachedIcon(boss)
    if boss.icon then return boss.icon end
    local cache = IconCache()
    if not cache then return nil end
    local id = boss.dungeonEncounterId
    if id and cache[id] then return cache[id] end
    if boss.name and cache["n:" .. boss.name] then return cache["n:" .. boss.name] end
    return nil
end

-- At a pull: look the encounter up in the journal for this instance.
function MS:ResolveBossIcon(boss)
    if not boss or boss.icon then return end
    local id = boss.dungeonEncounterId
    if not id or Secret(id) then return end
    local cache = IconCache()
    if cache and cache[id] then boss.icon = cache[id]; return end
    C_Timer.After(0, function()
        local inst = JournalInstanceHere()
        if not (inst and EJ_GetEncounterInfoByIndex and EJ_GetCreatureInfo) then return end
        local icon
        for i = 1, 40 do
            local ok, name, _, journalID, _, _, _, dungeonEncID = pcall(EJ_GetEncounterInfoByIndex, i, inst)
            if not ok or not name or Secret(name) then break end
            if dungeonEncID == id then
                local ok2, _, _, _, _, iconImage = pcall(EJ_GetCreatureInfo, 1, journalID)
                if ok2 and not Secret(iconImage) then icon = iconImage end
                break
            end
        end
        if icon then
            boss.icon = icon
            IconCache(true)[id] = icon
            self:SaveCurrentRun()
            Changed()
        end
    end)
end

-- One-time scan of the whole journal: every dungeon boss's icon, keyed by
-- dungeonEncounterID and by "n:<boss name>", for saved runs recorded before
-- icons were captured. Skipped in combat and while the journal is open
-- (it changes the journal's selected tier briefly).
local _ejIndexBuilt = false
local function BuildJournalIndex()
    if _ejIndexBuilt or not rawget(_G, "MythicScoreboardDB") then return end
    if InCombatLockdown() then return end
    if EncounterJournal and EncounterJournal.IsShown and EncounterJournal:IsShown() then return end
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex
            and EJ_GetEncounterInfoByIndex and EJ_GetCreatureInfo) then return end
    _ejIndexBuilt = true
    local cache = IconCache(true)
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

-- ── The answer ─────────────────────────────────────────────────────────────
-- What a boss's medallion shows: "icon", texture | "display", model ID |
-- "file", path | nil.
function MS:BossPortrait(boss, run)
    if not boss then return nil end
    local icon = CachedIcon(boss)
    if not icon and not MS.ForeverBossArt then
        BuildJournalIndex()                 -- saved runs from before icons were kept
        icon = CachedIcon(boss)
    end
    if icon then return "icon", icon end
    local aliases = MS.ForeverBossAliases and MS:ForeverBossAliases(boss, run)
    local learned = MS:LearnedBossDisplay(boss, aliases)
    if learned then return "display", learned end
    if MS.ForeverBossArt then return MS:ForeverBossArt(boss, run) end
    return nil
end

-- ── Events ─────────────────────────────────────────────────────────────────
local frame = CreateFrame("Frame")
local _activeEncounter
pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")
pcall(frame.RegisterEvent, frame, "ZONE_CHANGED_NEW_AREA")
-- Targets, mouse-overs and nameplates are only looked at during a run.
local RUN_EVENTS = { "ENCOUNTER_START", "ENCOUNTER_END", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
                     "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
                     "NAME_PLATE_UNIT_ADDED", "PLAYER_REGEN_ENABLED" }
local listening = false
MS:WatchRunState(function(state)
    local want = state == "active"
    if want == listening then return end
    listening = want
    for _, ev in ipairs(RUN_EVENTS) do
        if want then pcall(frame.RegisterEvent, frame, ev) else frame:UnregisterEvent(ev) end
    end
end)

local function ScanSoon() pcall(ScanHere) end

local function OnRunEvent(event, ...)
    if event == "ENCOUNTER_START" then
        local _, name = ...
        _activeEncounter = (not Secret(name)) and name or nil
        C_Timer.After(0.5, function()
            if not UnitExists("boss1") then return end
            -- Single-boss encounters: the encounter name gets the portrait too.
            local single = not UnitExists("boss2")
            TryUnit("boss1", "encounter", single and _activeEncounter or nil)
        end)
    elseif event == "ENCOUNTER_END" then
        _activeEncounter = nil
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        for i = 1, 5 do
            if UnitExists("boss" .. i) then TryUnit("boss" .. i, "engage") end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        Consider("target", "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Consider("mouseover", "mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        if unit and not Secret(unit) then Consider(unit, "nameplate") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Retry a journal read skipped while its window was open, and give
        -- anything hidden during the fight another look.
        pcall(ScanHere)
        wipe(_tried)
        Consider("target", "after-combat")
        SweepNameplates("after-combat")
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(2, ScanSoon)
        return
    end
    if not MS.inDungeon then return end
    pcall(OnRunEvent, event, ...)
end)

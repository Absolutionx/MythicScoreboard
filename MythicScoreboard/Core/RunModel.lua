-- What a run is: its tables, its clock, and its saved form.
--
-- A run (MS.currentRun while it's going, MythicScoreboardDB.runs once saved):
--   dungeonName, keystoneLevel, difficultyID, difficultyLabel
--   challengeMapID   Mythic+ map ID (C_ChallengeMode), keys only
--   instanceID       the instance's map ID (GetInstanceInfo), every run
--   startTime        GetTime() at the start (this session only)
--   _wallClockStart  time() at the start
--   duration         set when the run ends
--   completed, inTime, clearedAt, finishedOnLeave, abandoned
--   players[key]     see NewPlayerStats (keys: Roster.lua)
--   bosses[]         { name, pullTime, killTime | wipeTime, reset, dungeonEncounterId, stats, ... }
--                    (how a fight went: MS.FightResult, never the fields directly)
--
-- Who is in it: Roster.lua. Recording it: Meter.lua, Encounters.lua.
-- Starting and ending it: Lifecycle.lua, Completion.lua.

local _abs, _floor, _min, _max = math.abs, math.floor, math.min, math.max
local _fmt, _ins = string.format, table.insert

local MS = _G["MythicScoreboard"]
local L = MS.L

MS.currentRun = nil
MS.inDungeon  = false
MS.scoreCache = {}

-- ── Boss fights ────────────────────────────────────────────────────────────
-- How a fight went, the one place that's worked out:
--   "kill"   killTime set
--   "wipe"   wipeTime set: the group died, or the fight ended without a kill
--   "reset"  wipeTime set by Encounters' CloseOpenFight: the game never ended
--            the fight and the boss didn't die (it reset, or was left)
--   "open"   neither: going on now, or never finished in a run saved before
--            such fights were closed
function MS.FightResult(b)
    if b.killTime then return "kill" end
    if b.wipeTime then return b.reset and "reset" or "wipe" end
    return "open"
end
-- When it ended (nil while open).
function MS.FightEnd(b) return b.killTime or b.wipeTime end
-- True for a fight that ended without a kill (wipe or reset).
function MS.FightLost(b) return b.wipeTime ~= nil and not b.killTime end
-- Boss names, compared the one way everywhere: the key is lower case with
-- the game's curly apostrophe made plain ("Ner’zhul" = "ner'zhul"). It's
-- also the key learned portraits are saved under, so it mustn't change.
local _keyCache = {}
function MS.BossKey(name)
    if type(name) ~= "string" then return nil end
    local k = _keyCache[name]
    if not k then
        k = (name:gsub("\226\128\153", "'")):lower()
        _keyCache[name] = k
    end
    return k
end
-- Two names for the same boss: the same key, or the same letters once
-- spaces and punctuation are dropped (a chat line's "Lorgus Jett" against
-- an encounter's "Lorgus-Jett").
function MS.SameBossName(a, b)
    local ka, kb = MS.BossKey(a), MS.BossKey(b)
    if not ka or not kb then return false end
    if ka == kb then return true end
    return (ka:gsub("[%s%p]", "")) == (kb:gsub("[%s%p]", ""))
end

-- " (wipe)" / " (reset)" after a boss's name, or "".
function MS.FightTag(b)
    local r = MS.FightResult(b)
    if r == "wipe" then return " " .. L["(wipe)"] end
    if r == "reset" then return " " .. L["(reset)"] end
    return ""
end

-- ── The clock ──────────────────────────────────────────────────────────────
-- Seconds into a run. Every time inside a run (boss pulls and kills, deaths,
-- interrupts, loot) counts from its start the same way.
--   finished   run.duration, fixed when it ended
--   live key   the key's own timer (GetWorldElapsedTime, from the countdown)
--   live       the game clock since the start (run.startTime, this session
--              only: it's worked out again after a /reload)
local function Elapsed(run)
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
        return _max(0, sus.at - run._wallClockStart - (sus.offline or 0))   -- (time logged out left out)
    end
    return _max(0, GetTime() - (run.startTime or GetTime()))
end

function MS:GetRunDuration(run)
    return Elapsed(run or self.currentRun)
end

function MS:FormatTime(seconds)
    seconds = seconds or 0
    return _fmt("%d:%02d", _floor(seconds / 60), _floor(seconds % 60))
end

-- Like FormatTime, with hours once a run passes an hour ("1:02:05").
function MS:FormatLongTime(seconds)
    if not seconds then return "-" end
    local s = _floor(seconds + 0.5)
    if s >= 3600 then return _fmt("%d:%02d:%02d", _floor(s / 3600), _floor(s % 3600 / 60), s % 60) end
    return _fmt("%d:%02d", _floor(s / 60), s % 60)
end

-- ── New tables ─────────────────────────────────────────────────────────────
function MS.NewRunData()
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
        challengeMapID       = nil,
        instanceID           = nil,
    }
end

function MS.NewPlayerStats(name, classToken, guid)
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
        deathEvents          = {},    -- { time, events = killing blow and the hits before it }
        mythicScore          = 0,
        itemLevel            = 0,
        loot                 = {},
        level                = 0,
    }
end

-- The name a run is shown and grouped under: the wing once it's known
-- (Forever's "Scarlet Monastery: Library", whose instance is named
-- "Scarlet Monastery" for every wing), else the instance's name.
function MS:RunTitle(run)
    if not run then return "?" end
    return run.wingName or run.dungeonName or "?"
end

-- ── What a run came to ─────────────────────────────────────────────────────
-- One answer for the header, history and Stats page:
--   "inTime" / "overTime"   a finished key
--   "cleared"               a cleared dungeon
--   "live" / "paused"       the run in progress
--   "finished"              ended on leaving, under the clear rules
--   "abandoned"             anything else
function MS:RunStatus(run)
    if not run then return nil end
    if run.completed then
        if (run.keystoneLevel or 0) > 0 then return run.inTime and "inTime" or "overTime" end
        return "cleared"
    end
    if run == self.currentRun then
        if self.inDungeon then return "live" end
        if run._suspended then return "paused" end
    end
    if run.finishedOnLeave then return "finished" end
    return "abandoned"
end

-- The same for an archive entry (Archive.lua).
function MS:ArchiveStatus(e)
    if e.cleared then
        if e.key then return e.inTime and "inTime" or "overTime" end
        return "cleared"
    end
    if e.onLeave then return "finished" end
    return "abandoned"
end

-- ── Deaths and interrupts ──────────────────────────────────────────────────
local DUPLICATE_DEATH_WINDOW = 2

function MS:IsDupDeath(p, now)
    return _abs((p._lastDeathTime or -999) - now) < DUPLICATE_DEATH_WINDOW
end

-- Interrupts are kept as a plain list of times (to a tenth of a second);
-- runs saved before 2.5 have { time = t, spell = "Unknown" } tables instead.
local function EventTime(e) return type(e) == "table" and (e.time or 0) or e or 0 end
MS.EventTime = EventTime
local function Tenth(t) return _floor(t * 10 + 0.5) / 10 end
MS.Tenth = Tenth

local SYNTH_INTERRUPT_MIN_WINDOW = 2

-- The meter gives each player's interrupt count but not when they happened.
-- New ones get times spread across the stretch since the last one (or the
-- current fight), with a small per-player offset so markers don't stack.
-- Called as the meter is read, never while drawing.
function MS:_BackfillSyntheticInterrupts(run)
    run = run or self.currentRun
    if not run then return end
    local now = Elapsed(run)

    local bossAnchor = 0
    for _, boss in ipairs(run.bosses or {}) do
        local pt = boss.pullTime or 0
        if pt <= now and pt > bossAnchor then bossAnchor = pt end
    end

    local function playerJitter(name)
        local h = 0
        for i = 1, #name do h = h + name:byte(i) end
        return ((h % 31) / 30 - 0.5) * 6.0
    end

    for _, p in pairs(run.players or {}) do
        p.interruptEvents = p.interruptEvents or {}
        local recorded = #p.interruptEvents
        local delta    = (p.interrupts or 0) - recorded
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

-- ── The saved form ─────────────────────────────────────────────────────────
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
    run    = { "_carry", "_carryDur", "_lastDur", "_seq", "_pendingFinalize", "_combatEndedAt", "_clearedClock", "activeBoss",
               "_active", "_suspended", "startTime", "endTime", "_bossTotal",
               "_baselinePending", "_deathBase", "_offline", "_savedAt" },
    boss   = { "_before", "_session", "_tries", "_named", "_diedAt" },
    player = { "_lastDeathTime", "_lastRecapID" },
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
    for _, p in pairs(out.players or {}) do
        -- Loot: the chat link holds the item string; the arrival time and
        -- source only matter while the run is live.
        for _, l in ipairs(p.loot or {}) do
            if l.link then l.item = nil end
            l.at, l.src = nil, nil
        end
        -- Death recap IDs only mean something in the session they came from
        -- (the hits themselves are copied onto each death when it happens).
        p.deathRecapID = nil
    end
    return out
end

function MS:SetSBFrameVisibleCallback(fn) MS.sbFrameVisible = fn end

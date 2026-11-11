-- One-time changes to saved data, in order.
--
-- Each kind of saved data carries one version number, and every step below
-- moves it up by one. On login, whatever is behind is brought up to date,
-- step by step, so a player skipping versions gets every change in order. A
-- new change to the saved format is one new numbered step here.
--
--   per character   MythicScoreboardDB.dataVersion       (history, run in progress)
--   per archive     archive.v                             (the Stats page's runs)
--
-- Versions before this file used separate flags (historyRepair, compact,
-- bossTimes, lootFilled); they're read once to work out where to start.

local MS = _G["MythicScoreboard"]
local _floor, _max = math.floor, math.max
local _ins, _rem, _sort = table.insert, table.remove, table.sort

local SPLIT_GAP = 30 * 60   -- same window a paused run gets now
local Int = MS.Round

-- ── Split runs (before 2.5) ────────────────────────────────────────────────
-- Two forms of the same repair: archive summaries and full history runs.
-- Leaving a dungeon used to end the run, and coming back started a new one,
-- so one real run was saved as an abandoned run plus a shorter one. The
-- shorter half could even become a "best" clear. Two runs in the same
-- dungeon, the first not finished and the second starting within SPLIT_GAP
-- of its end, are joined back into one. Only applied to runs recorded before
-- the fix (the archive's first version, and runs seeded from history).

local function Merge(a, b)
    local offset = (b.at or 0) - (a.at or 0)
    local m = {
        at = a.at, dungeon = a.dungeon, diff = b.diff or a.diff, key = b.key or a.key,
        dur = (b.at + b.dur) - a.at,
        cleared = b.cleared, inTime = b.inTime, onLeave = b.onLeave,
        deaths = (a.deaths or 0) + (b.deaths or 0),
        wipes = (a.wipes or 0) + (b.wipes or 0),
        bosses = {}, group = {}, merged = (a.merged or 1) + (b.merged or 1),
    }
    for _, x in ipairs(a.bosses or {}) do _ins(m.bosses, { n = x.n, t = x.t, d = x.d, m = x.m }) end
    for _, x in ipairs(b.bosses or {}) do _ins(m.bosses, { n = x.n, t = x.t + offset, d = x.d, m = x.m }) end
    if a.loot or b.loot then
        m.loot = {}
        for _, x in ipairs(a.loot or {}) do _ins(m.loot, x) end
        for _, x in ipairs(b.loot or {}) do
            local c = {}
            for k, v in pairs(x) do c[k] = v end
            c.t = (c.t or 0) + offset
            _ins(m.loot, c)
        end
    end
    local seen = {}
    for _, list in ipairs({ a.group or {}, b.group or {} }) do
        for _, g in ipairs(list) do
            if not seen[g.n] then seen[g.n] = true; _ins(m.group, { n = g.n, c = g.c }) end
        end
    end
    _sort(m.group, function(x, y) return x.n < y.n end)
    local ma, mb = a.me, b.me
    if ma and mb then
        local da, db = a.dur, b.dur
        local function W(k) return Int(((ma[k] or 0) * da + (mb[k] or 0) * db) / _max(1, da + db)) end
        local function S(k) return (ma[k] or 0) + (mb[k] or 0) end
        m.me = {
            lvl = mb.lvl or ma.lvl, ilvl = _max(ma.ilvl or 0, mb.ilvl or 0), cls = mb.cls or ma.cls,
            role = mb.role or ma.role, dps = W("dps"), hps = W("hps"),
            dmg = S("dmg"), heal = S("heal"), taken = S("taken"), avoid = S("avoid"),
            int = S("int"), deaths = S("deaths"),
        }
    else
        m.me = mb or ma
    end
    return m
end

-- The rule both forms share: b started right after a ended (within SPLIT_GAP).
local function Follows(aStart, aDur, bStart)
    return aStart and aDur and bStart
        and bStart >= aStart + aDur - 5 and bStart - (aStart + aDur) <= SPLIT_GAP
end

local function IsSplit(a, b)
    return a.dungeon == b.dungeon and not a.cleared and not a.onLeave and not a.quit
        and Follows(a.at, a.dur, b.at)
end

-- Joins neighbours in a list. older(i) / newer(i) say which of list[i] and
-- list[i + 1] came first. Returns how many joins were made.
local function JoinSplits(list, isSplit, merge, newestFirst)
    local joined, i = 0, 1
    while i < #list do
        local older, newer = list[i], list[i + 1]
        if newestFirst then older, newer = newer, older end
        if isSplit(older, newer) then
            list[i] = merge(older, newer)
            _rem(list, i + 1)
            joined = joined + 1
        else
            i = i + 1
        end
    end
    return joined
end

-- Archive entries, oldest first (also used when seeding a new archive).
function MS.JoinSplitEntries(list) return JoinSplits(list, IsSplit, Merge, false) end

-- The same repair for the full runs in history (the dropdown). Times inside
-- a run (boss pulls/kills, deaths, interrupts, loot) count from its start,
-- so the second half's are shifted by the gap between the two starts.
local function RunDur(run) return (run.endTime or 0) - (run.startTime or 0) end

local function IsSplitRun(a, b)   -- a older, b newer
    local da = RunDur(a)
    return a.dungeonName == b.dungeonName and not a.completed and not a.finishedOnLeave and not a.abandoned
        and (a.keystoneLevel or 0) == 0 and (b.keystoneLevel or 0) == 0
        and da > 0 and RunDur(b) > 0 and Follows(a._wallClockStart, da, b._wallClockStart)
end

local function MergeRuns(a, b)
    local offset = b._wallClockStart - a._wallClockStart
    local da, db = RunDur(a), RunDur(b)
    local m = {}
    for k, v in pairs(b) do m[k] = v end              -- result, labels, flags: the later half
    m._wallClockStart = a._wallClockStart
    m.startTime = a.startTime
    m.endTime = a.startTime + offset + db
    m.deathPenaltySeconds = (a.deathPenaltySeconds or 0) + (b.deathPenaltySeconds or 0)
    m._seq = (a._seq or 0) + (b._seq or 0) + 1
    m.merged = true

    m.bosses = {}
    for _, x in ipairs(a.bosses or {}) do _ins(m.bosses, x) end
    for _, x in ipairs(b.bosses or {}) do
        local c = {}
        for k, v in pairs(x) do c[k] = v end
        if c.pullTime then c.pullTime = c.pullTime + offset end
        if c.killTime then c.killTime = c.killTime + offset end
        _ins(m.bosses, c)
    end

    local SUM = { "damageDone", "healingDone", "damageTaken", "avoidableDamageTaken",
                  "interrupts", "dispels", "deaths" }
    local function Shifted(list, field)
        local out = {}
        for _, e in ipairs(list or {}) do
            if type(e) == "number" then
                _ins(out, e + offset)           -- interrupts: plain times
            else
                local c = {}
                for k, v in pairs(e) do c[k] = v end
                if c[field] then c[field] = c[field] + offset end
                _ins(out, c)
            end
        end
        return out
    end
    m.players = {}
    for key, pa in pairs(a.players or {}) do m.players[key] = pa end
    for key, pb in pairs(b.players or {}) do
        local pa = m.players[key]
        if not pa then
            local c = {}
            for k, v in pairs(pb) do c[k] = v end
            c.deathEvents = Shifted(pb.deathEvents, "time")
            c.interruptEvents = Shifted(pb.interruptEvents, "time")
            c.loot = Shifted(pb.loot, "t")
            m.players[key] = c
        else
            local c = {}
            for k, v in pairs(pb) do c[k] = v end      -- level, gear, class, role: the later half
            for _, f in ipairs(SUM) do c[f] = (pa[f] or 0) + (pb[f] or 0) end
            local inside = _max(1, da + db)            -- time actually spent in the dungeon
            c.dps = c.damageDone / inside
            c.hps = c.healingDone / inside
            c.deathEvents, c.interruptEvents, c.loot = {}, {}, {}
            for _, e in ipairs(pa.deathEvents or {}) do _ins(c.deathEvents, e) end
            for _, e in ipairs(Shifted(pb.deathEvents, "time")) do _ins(c.deathEvents, e) end
            for _, e in ipairs(pa.interruptEvents or {}) do _ins(c.interruptEvents, e) end
            for _, e in ipairs(Shifted(pb.interruptEvents, "time")) do _ins(c.interruptEvents, e) end
            for _, e in ipairs(pa.loot or {}) do _ins(c.loot, e) end
            for _, e in ipairs(Shifted(pb.loot, "t")) do _ins(c.loot, e) end
            c.left = pb.left
            m.players[key] = c
        end
    end
    -- Someone only in the first half left partway.
    for key, p in pairs(m.players) do
        if a.players and a.players[key] and not (b.players and b.players[key]) then p.left = true end
    end
    return m
end


-- ── Steps: history and the run in progress ─────────────────────────────────
local function CompactRun(run)
    for _, p in pairs(run and run.players or {}) do
        local list = p.interruptEvents
        if list then
            for i, e in ipairs(list) do
                if type(e) == "table" then list[i] = MS.Tenth(e.time or 0) end
            end
        end
    end
end

-- ── Loot listed twice (2.9.0) ──────────────────────────────────────────────
-- The same drop could be saved twice for a player who also ran the addon:
-- their addon's copy of the item link differed from the one seen in chat.
-- Later copies of an item (by its ID) within a few seconds of the first go.
local DUP_SECONDS = 15
local function ItemID(l)
    local s = MS.LootItemString(l)
    return s and s:match("^item:(%d+)") or s
end
local function DedupeLoot(list)
    if type(list) ~= "table" then return end
    local kept = {}
    for _, l in ipairs(list) do
        local id, dup = ItemID(l), false
        for _, k in ipairs(kept) do
            if id and ItemID(k) == id and math.abs((l.t or 0) - (k.t or 0)) <= DUP_SECONDS then dup = true; break end
        end
        if not dup then _ins(kept, l) end
    end
    for i = #list, 1, -1 do list[i] = nil end
    for i, l in ipairs(kept) do list[i] = l end
end

local CHAR_STEPS = {
    -- 1 (2.5): runs split in two by the old zone-out bug are joined.
    function(db)
        JoinSplits(db.runs, IsSplitRun, MergeRuns, true)
    end,
    -- 2 (2.6): smaller saved runs: interrupts as plain times, loot as its
    -- link, numbers to two places.
    function(db)
        for i, r in ipairs(db.runs) do CompactRun(r); db.runs[i] = MS:SerializeRun(r, true) end
        CompactRun(db.activeRun)
    end,
    -- 3 (2.6): a saved run keeps its length (run.duration) instead of the
    -- game clock at its start and end, and no live-only state. The old
    -- times could be off (a clock from an earlier session); those fall back
    -- to the last boss kill.
    function(db)
        for _, r in ipairs(db.runs) do
            if not r.duration then
                local d = (r.endTime or 0) - (r.startTime or 0)
                if not (d > 0 and d < 7200) then
                    d = 0
                    for _, b in ipairs(r.bosses or {}) do
                        if (b.killTime or 0) > d then d = b.killTime end
                    end
                    if d > 0 then d = d + 30 end
                end
                r.duration = d
            end
            MS:StripLive(r)
        end
    end,
    -- 4 (2.7): interrupt times filled in once, when a run is saved, instead
    -- of each time its timeline is drawn; death recap IDs (which only meant
    -- something in the session they came from) dropped.
    function(db)
        for _, r in ipairs(db.runs) do
            MS:_BackfillSyntheticInterrupts(r)
            for _, p in pairs(r.players or {}) do p.deathRecapID = nil end
        end
    end,
    -- 5 (2.9.1): loot saved twice for the same player.
    function(db)
        for _, r in ipairs(db.runs) do
            for _, p in pairs(r.players or {}) do DedupeLoot(p.loot) end
        end
    end,
    -- 6 (2.9.3): finished keys on their result's clock (RunModel.lua,
    -- MS.ToResultClock): their bosses died after the key ended, by about
    -- what the deaths cost.
    function(db)
        for _, r in ipairs(db.runs) do
            if r.completed and (r.keystoneLevel or 0) > 0 and (r.duration or 0) > 0 then MS.ToResultClock(r) end
        end
    end,
}
MS.DATA_VERSION = #CHAR_STEPS

-- ── Steps: the archive ─────────────────────────────────────────────────────
-- (Entries written by this version are already in the latest form, so a new
-- archive starts at ARCHIVE_VERSION.)
-- What steps 3 and 4 need from a run still in history: each kill's fight
-- length and your DPS in it, and your loot. Worked out here as 2.5 did, so
-- a later change to MS:SummarizeRun can't change what these steps do.
local function Summary25(run)
    if type(run) ~= "table" or not run.dungeonName or run.dungeonName == "" then return nil end
    local me
    local myGUID = MS.UnitGUIDReadable and MS.UnitGUIDReadable("player")
    for _, p in pairs(run.players or {}) do
        if myGUID and MS.Readable(p.guid) == myGUID then me = p end
    end
    if not me then
        local myName = MS:UnitPlayerName("player")
        me = myName and MS:PlayerByName(myName, run) or nil
    end
    local e = { at = run._wallClockStart, dungeon = run.dungeonName, bosses = {} }
    for _, b in ipairs(run.bosses or {}) do
        if b.killTime then
            local d = b.pullTime and b.killTime > b.pullTime and _floor(b.killTime - b.pullTime) or nil
            local mine = me and b.stats and b.stats[me.name]
            e.bosses[#e.bosses + 1] = { n = b.name, d = d,
                m = (mine and d and d > 0) and Int((mine.dmg or 0) / d) or nil }
        end
    end
    if me and me.loot and #me.loot > 0 then
        e.loot = {}
        for _, l in ipairs(me.loot) do
            local boss, at = nil, -1
            local t = l.t or 0
            for _, b in ipairs(run.bosses or {}) do
                if b.killTime and b.killTime <= t + 2 and b.killTime >= t - 120 and b.killTime > at then
                    boss, at = b.name, b.killTime
                end
            end
            e.loot[#e.loot + 1] = { i = (not l.link) and MS.LootItemString(l) or nil, l = l.link,
                                    q = l.quality, t = Int(l.t), b = boss }
        end
    end
    return e
end

local function FromHistory(a, fn)
    for _, run in ipairs(MythicScoreboardDB and MythicScoreboardDB.runs or {}) do
        local e = Summary25(run)
        if e then
            for _, x in ipairs(a.runs) do
                if x.at == e.at and x.dungeon == e.dungeon then fn(x, e) end
            end
        end
    end
end

local ARCHIVE_STEPS = {
    -- 2 (2.5): split runs joined (everything in a version-1 archive predates the fix).
    [2] = function(a)
        _sort(a.runs, function(x, y) return (x.at or 0) < (y.at or 0) end)
        MS.JoinSplitEntries(a.runs)
    end,
    -- 3 (2.5): fight lengths and your DPS per boss, from runs still in history.
    [3] = function(a)
        FromHistory(a, function(x, e)
            if #(x.bosses or {}) ~= #e.bosses then return end
            for i, b in ipairs(x.bosses) do
                if b.n == e.bosses[i].n then
                    b.d = b.d or e.bosses[i].d
                    b.m = b.m or e.bosses[i].m
                end
            end
        end)
    end,
    -- 4 (2.5): your loot, from runs still in history.
    [4] = function(a)
        FromHistory(a, function(x, e)
            if e.loot and not x.loot then x.loot = e.loot end
        end)
    end,
    -- 5 (2.6): archived loot keeps only the chat link when there is one.
    [5] = function(a)
        for _, e in ipairs(a.runs) do
            for _, l in ipairs(e.loot or {}) do
                if l.l then l.i = nil end
            end
        end
    end,
    -- 6 (2.9.1): your loot saved twice.
    [6] = function(a)
        for _, e in ipairs(a.runs) do DedupeLoot(e.loot) end
    end,
    -- 7 (2.9.3): keys still in history put their boss times on the result's
    -- clock (the character's step 6 above did the full runs): each kill's
    -- time and fight length, and your DPS in it, from the corrected run.
    [7] = function(a)
        for _, run in ipairs(MythicScoreboardDB and MythicScoreboardDB.runs or {}) do
            if run.resultClock then
                local kills = {}
                for _, b in ipairs(run.bosses or {}) do
                    if b.killTime then kills[#kills + 1] = b end
                end
                for _, x in ipairs(a.runs) do
                    if x.key and x.at == run._wallClockStart and x.dungeon == run.dungeonName
                            and #(x.bosses or {}) == #kills then
                        for i, xb in ipairs(x.bosses) do
                            local b = kills[i]
                            if xb.n == b.name then
                                xb.t = Int(b.killTime)
                                local d = b.pullTime and b.killTime > b.pullTime and _floor(b.killTime - b.pullTime) or nil
                                if d and d > 0 then
                                    if xb.m and xb.d and xb.d > 0 then xb.m = Int(xb.m * xb.d / d) end
                                    xb.d = d
                                end
                            end
                        end
                    end
                end
            end
        end
    end,
}
MS.ARCHIVE_VERSION = 7

-- ── Running them ───────────────────────────────────────────────────────────
function MS:MigrateArchive(a)
    if type(a) ~= "table" or type(a.runs) ~= "table" then return end
    local v = a.v or 1
    if v >= MS.ARCHIVE_VERSION then return end
    -- Where an archive from before this file is up to.
    if v >= 2 and a.bossTimes then v = 3 end
    if v >= 3 and a.lootFilled then v = 4 end
    if v >= 4 and MythicScoreboardDB and (MythicScoreboardDB.compact or 0) >= 1 then v = 5 end
    a.bossTimes, a.lootFilled = nil, nil
    for step = v + 1, MS.ARCHIVE_VERSION do
        ARCHIVE_STEPS[step](a)
        a.v = step
    end
    if MS.BumpStats then MS.BumpStats() end
end

-- At login, before anything reads the saved data.
function MS:RunMigrations()
    local db = MythicScoreboardDB
    if not db then return end
    db.runs = db.runs or {}
    local v = db.dataVersion
    if not v then                                   -- from before this file
        v = ((db.compact or 0) >= 1 and 2) or ((db.historyRepair or 0) >= 1 and 1) or 0
    end
    for step = v + 1, MS.DATA_VERSION do
        CHAR_STEPS[step](db)
        db.dataVersion = step
    end
    db.dataVersion = _max(v, MS.DATA_VERSION)
    if self._ArchiveStore then self._ArchiveStore() end   -- the archive's own steps (and its move account-wide)
    db.historyRepair, db.compact = nil, nil
end

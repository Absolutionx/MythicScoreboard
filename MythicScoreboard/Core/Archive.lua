-- Permanent run archive and the numbers behind the Stats page.
--
-- History (MythicScoreboardDB.runs) keeps a handful of full runs for the
-- scoreboard. The archive keeps a small summary of *every* finished run,
-- oldest first, so trends survive after a run drops out of history:
--
--   at       wall-clock start (time())      dungeon, diff, key
--   dur      run time in seconds            cleared, inTime, onLeave, quit
--   deaths   group deaths                   wipes   failed boss pulls
--   bosses   { {n = name, t = kill time, d = fight length, m = your DPS in it} }  in kill order
--   loot     { {i = item string, l = link, q = quality, t = time, b = boss} }  gear that dropped for you
--   me       your own numbers: lvl ilvl cls role dps hps dmg heal taken avoid int deaths
--   group    { {n = name key, c = class} }  everyone else
--   prog     (Forever) what the run did for you: xp, lv levels, k kills,
--            q quests, g gold in copper, rep { [faction] = amount };
--            qx / qg the XP and gold of quests done in it (apart from xp, g)
--   (keys)   up levels the key went up (0 over time), lim the timer,
--            r0 / r1 your rating before and after (r0 alone on older runs)
--
-- Roughly 300 bytes a run; MAX_RUNS keeps the saved file small.

local MS = _G["MythicScoreboard"]
local _floor, _max = math.floor, math.max
local _ins, _rem, _sort = table.insert, table.remove, table.sort

local MAX_RUNS = 2000

local function Int(n) return _floor((tonumber(n) or 0) + 0.5) end

-- Stats are worked out once and kept until the runs change. Anything that
-- changes an archive bumps this; the cache key also notes each character's
-- run list and its length, so a change made elsewhere is noticed too.
local _rev = 0
local function Bump() _rev = _rev + 1 end
MS.BumpStats = Bump
function MS:StatsRevision() return _rev end   -- changes whenever any archived run does

-- ── Storage ────────────────────────────────────────────────────────────────
-- Each character's archive lives in the account-wide saved variables
-- (MythicScoreboardAccountDB.chars[name@realm].archive), so the Stats page can
-- show every character, and it's written to disk once. Before 2.5 it was
-- saved with the character and copied account-wide (written twice); that
-- copy is moved over the first time the character logs in.

local function Account()
    if type(rawget(_G, "MythicScoreboardAccountDB")) ~= "table" then MythicScoreboardAccountDB = {} end
    local acc = MythicScoreboardAccountDB
    if type(acc.chars) ~= "table" then acc.chars = {} end
    return acc
end

local function Plain(v)
    if v == nil or MS.IsSecret(v) then return nil end
    return v
end

local function CharKey()
    local name = Plain(MS.UnitPlayerName and MS:UnitPlayerName("player") or UnitName("player"))
    if type(name) ~= "string" or name == "" then return nil end
    local realm = Plain(GetRealmName and GetRealmName())   -- known from the start of the login
    return name .. "@" .. (type(realm) == "string" and realm or ""), name, realm
end

local function NewArchive() return { v = MS.ARCHIVE_VERSION, runs = {} } end
local function Valid(a) return type(a) == "table" and type(a.runs) == "table" end

-- An archive is brought up to date (Migrations.lua) the first time it's
-- used in a session, not on every read.
local _ready = setmetatable({}, { __mode = "k" })
local function Ready(a)
    if not _ready[a] then
        if MS.MigrateArchive then MS:MigrateArchive(a) end
        _ready[a] = true
    end
    return a
end

-- Once per character: the archive saved with the character before 2.5 (and
-- the old account-wide copy of its runs) moved into its account-wide slot.
local function MoveAccountWide(key)
    local chars = Account().chars
    local c = chars[key]
    if not c then c = {}; chars[key] = c end
    local old = MythicScoreboardDB.archive
    if Valid(old) then
        c.archive = old
        Bump()
    end
    MythicScoreboardDB.archive = nil
    c.runs = nil
    if not Valid(c.archive) then c.archive = NewArchive() end
    return c.archive
end

-- This character's archive table: { v = data version, runs, seeded }.
-- Reading it changes nothing once it's in place.
local function Store()
    if not MythicScoreboardDB then return nil end
    local key = MS._charKey or CharKey()
    if not key then
        -- Name not known yet: keep it with the character until it is.
        if not Valid(MythicScoreboardDB.archive) then MythicScoreboardDB.archive = NewArchive() end
        return Ready(MythicScoreboardDB.archive)
    end
    MS._charKey = key
    local acc = rawget(_G, "MythicScoreboardAccountDB")
    local c = type(acc) == "table" and type(acc.chars) == "table" and acc.chars[key]
    if c and Valid(c.archive) and c.runs == nil and MythicScoreboardDB.archive == nil then
        return Ready(c.archive)
    end
    return Ready(MoveAccountWide(key))
end
MS._ArchiveStore = Store                      -- for tests

-- A character's runs: its archive, or (characters not logged in since 2.5)
-- the copy saved account-wide before.
local function CharRuns(c)
    return (type(c.archive) == "table" and c.archive.runs) or c.runs or {}
end

-- The local player in a run: by GUID, then by name.
local function FindSelf(run)
    local myGUID = MS.UnitGUIDReadable and MS.UnitGUIDReadable("player")
    if myGUID then
        for _, p in pairs(run.players or {}) do
            if MS.Readable(p.guid) == myGUID then return p end
        end
    end
    local myName = MS.UnitPlayerName and MS:UnitPlayerName("player")
    return myName and MS:PlayerByName(myName, run) or nil
end

-- The boss a piece of loot came from: a kill in the two minutes before it
-- dropped. Anything later came from trash (or the end-of-run chest).
local function LootBoss(run, t)
    local boss, at = nil, -1
    for _, b in ipairs(run.bosses or {}) do
        if b.killTime and b.killTime <= t + 2 and b.killTime >= t - 120 and b.killTime > at then
            boss, at = b.name, b.killTime
        end
    end
    return boss
end

-- A compact summary of a finished run, or nil if there's nothing to keep.
-- A key's upgrade, timer and your rating, from the saved run: the rating
-- the game reported after it, or else your rating going in (from the group
-- roster, read when the run started).
local function KeyInfo(self, e, run, me)
    if run.completed then
        local up = self.RunUpgrades and self:RunUpgrades(run)
        if up then e.up = up end
    end
    local lim = tonumber(run.keystoneTimeLimit)
    if lim and lim > 0 then e.lim = Int(lim) end
    local r0 = tonumber(run.ratingBefore) or (me and tonumber(me.mythicScore))
    local r1 = tonumber(run.ratingAfter)
    if r0 and r0 > 0 then e.r0 = Int(r0) end
    if r1 and r1 > 0 then e.r1 = Int(r1) end
end

function MS:SummarizeRun(run)
    if type(run) ~= "table" or not run.dungeonName or run.dungeonName == "" then return nil end
    local dur = Int(self:GetRunDuration(run))
    if dur <= 0 then return nil end

    local e = {
        at      = run._wallClockStart,
        dungeon = self:RunTitle(run),
        diff    = (run.difficultyLabel ~= "" and run.difficultyLabel) or nil,
        key     = ((run.keystoneLevel or 0) > 0) and run.keystoneLevel or nil,
        dur     = dur,
        cleared = run.completed and true or nil,
        inTime  = run.inTime and true or nil,
        onLeave = run.finishedOnLeave and true or nil,
        quit    = run.abandoned and true or nil,     -- abandoned by hand (never joined to the next run)
        deaths  = 0,
        wipes   = 0,
        bosses  = {},
        group   = {},
    }
    local me = FindSelf(run)
    for _, b in ipairs(run.bosses or {}) do
        if b.killTime then
            local d = b.pullTime and b.killTime > b.pullTime and _floor(b.killTime - b.pullTime) or nil
            local mine = me and b.stats and b.stats[me.name]
            _ins(e.bosses, { n = b.name, t = Int(b.killTime), d = d,
                             m = (mine and d and d > 0) and Int((mine.dmg or 0) / d) or nil })
        else
            e.wipes = e.wipes + 1
        end
    end
    for _, p in pairs(run.players or {}) do
        e.deaths = e.deaths + (p.deaths or 0)
        if p == me then
            e.me = {
                lvl = p.level ~= 0 and p.level or nil, ilvl = Int(p.itemLevel),
                cls = p.class, role = p.role ~= "" and p.role or nil,
                dps = Int(p.dps), hps = Int(p.hps), dmg = Int(p.damageDone), heal = Int(p.healingDone),
                taken = Int(p.damageTaken), avoid = Int(p.avoidableDamageTaken),
                int = p.interrupts or 0, deaths = p.deaths or 0,
            }
        elseif p.name then
            _ins(e.group, { n = p.name, c = p.class })
        end
    end
    _sort(e.group, function(a, b) return a.n < b.n end)
    if e.key then KeyInfo(self, e, run, me) end
    local pr = run.progress
    if pr then
        local rep
        for f, n in pairs(pr.rep or {}) do rep = rep or {}; rep[f] = Int(n) end
        e.prog = { xp = Int(_max(0, pr.xp or 0)), lv = (pr.levels or 0) > 0 and pr.levels or nil, k = pr.kills or 0,
                   q = #(pr.quests or {}), g = Int(_max(0, pr.gold or 0)), rep = rep,
                   qx = pr.qx and Int(pr.qx) or nil, qg = pr.qg and Int(pr.qg) or nil }
    end
    -- Your loot, with the boss it came from: a kill in the two minutes
    -- before it dropped. Anything later came from trash.
    if me and me.loot and #me.loot > 0 then
        e.loot = {}
        for _, l in ipairs(me.loot) do
            _ins(e.loot, { i = (not l.link) and MS.LootItemString(l) or nil, l = l.link, q = l.quality,
                           t = Int(l.t), b = LootBoss(run, l.t or 0) })
        end
    end
    return e
end

local function SameRun(a, b)
    return a.dungeon == b.dungeon and a.dur == b.dur and a.at == b.at
end

-- Adds a finished run to the archive (once).
function MS:ArchiveRun(run)
    local a = Store()
    if not a then return end
    self:_SeedArchive()
    local e = self:SummarizeRun(run)
    if not e then return end
    for i = #a.runs, _max(1, #a.runs - 20), -1 do
        if SameRun(a.runs[i], e) then return end
    end
    _ins(a.runs, e)
    while #a.runs > MAX_RUNS do _rem(a.runs, 1) end
    Bump()
end

-- Your loot that arrived after a run was saved (the Mythic+ chest): added to
-- that run's archived summary too, so the Stats page's loot list has it.
function MS:ArchiveLateLoot(run, l)
    local a = Store()
    if not (a and run and l) then return end
    for i = #a.runs, _max(1, #a.runs - 5), -1 do
        local e = a.runs[i]
        if e.at == run._wallClockStart and e.dungeon == MS:RunTitle(run) then
            e.loot = e.loot or {}
            _ins(e.loot, { i = (not l.link) and MS.LootItemString(l) or nil, l = l.link, q = l.quality,
                           t = Int(l.t), b = LootBoss(run, l.t or 0) })
            Bump()
            return true
        end
    end
end

-- First use: copy in the runs already in history, oldest first.
function MS:_SeedArchive()
    local a = Store()
    if not a or a.seeded then return end
    a.seeded = true
    Bump()
    local runs = MythicScoreboardDB.runs or {}
    for i = #runs, 1, -1 do
        local e = self:SummarizeRun(runs[i])
        if e then
            local dup = false
            for _, x in ipairs(a.runs) do if SameRun(x, e) then dup = true; break end end
            if not dup then _ins(a.runs, e) end
        end
    end
    _sort(a.runs, function(x, y) return (x.at or 0) < (y.at or 0) end)
    MS.JoinSplitEntries(a.runs)        -- history from older versions may hold split runs
end

function MS:ArchiveRuns()
    local a = Store()
    if not a then return {} end
    self:_SeedArchive()
    if not a.keysV then self:_BackfillKeys(a) end
    return a.runs
end

-- Keys archived before 2.9.1 lack the upgrade, timer and rating: filled in
-- from the full runs still in history (the same run: same start and
-- dungeon), once.
function MS:_BackfillKeys(a)
    a.keysV = 1
    local hist = (MythicScoreboardDB and MythicScoreboardDB.runs) or {}
    local byAt = {}
    for _, r in ipairs(hist) do
        if (r.keystoneLevel or 0) > 0 and r._wallClockStart then byAt[r._wallClockStart] = r end
    end
    for _, e in ipairs(a.runs) do
        local r = e.key and e.at and byAt[e.at]
        if r and r.keystoneLevel == e.key and self:RunTitle(r) == e.dungeon then
            KeyInfo(self, e, r, FindSelf(r))
        end
    end
    Bump()
end

-- ── Removing runs ──────────────────────────────────────────────────────────
-- One archived run (from the Stats page).
function MS:RemoveArchivedRun(entry)
    local a = Store()
    if not a then return end
    for i = #a.runs, 1, -1 do
        if a.runs[i] == entry then _rem(a.runs, i); Bump(); return true end
    end
end

-- The archived copy of a run deleted from history, if there is one.
function MS:RemoveArchivedFor(run)
    local a = Store()
    local e = a and self:SummarizeRun(run)
    if not e then return end
    for i = #a.runs, 1, -1 do
        local x = a.runs[i]
        if x.dungeon == e.dungeon and x.at == e.at and math.abs((x.dur or 0) - e.dur) <= 2 then
            _rem(a.runs, i); Bump(); return true
        end
    end
end

-- Empties the archive. History is not read back in afterwards.
function MS:ResetArchive()
    local a = Store()
    if not a then return end
    wipe(a.runs)
    a.seeded = true
    Bump()
end

-- ── All your characters ────────────────────────────────────────────────────
-- Every character's archive is account-wide (see Storage above), so the
-- Stats page can show all your characters together or one at a time. Only
-- the character you're on can change its own runs.
-- Notes this character's name and class account-wide (its archive is there).
function MS:SyncAccountStats()
    local a = Store()
    if not a then return end
    local key, name, realm = CharKey()
    if not key then return end
    local c = Account().chars[key]
    c.name, c.realm = name, realm
    local _, cls = UnitClass("player")
    c.class = Plain(cls) or c.class
    self._charKey = key
end

-- "all", or one character's key.
function MS:GetStatsChar()
    local want = Account().statsChar or "all"
    if want ~= "all" and not Account().chars[want] then want = "all" end
    return want
end
function MS:SetStatsChar(key) Account().statsChar = key; Bump() end

-- Characters with runs: this one first, then the others by name.
function MS:StatsCharacters()
    self:SyncAccountStats()
    local out = {}
    for key, c in pairs(Account().chars) do
        local n = #CharRuns(c)
        if n > 0 or key == self._charKey then
            _ins(out, { key = key, name = c.name or key, class = c.class, runs = n, me = key == self._charKey })
        end
    end
    _sort(out, function(x, y)
        if x.me ~= y.me then return x.me end
        return (x.name or "") < (y.name or "")
    end)
    return out
end

function MS:CharacterInfo(key) return key and Account().chars[key] end

-- The cache key for what the Stats page shows right now.
local _memo, _memoKey = {}, nil
local function StatsKey(self)
    local parts = { _rev, tostring(self._charKey), self:GetStatsChar() }
    for key, c in pairs(Account().chars) do
        local runs = CharRuns(c)
        parts[#parts + 1] = key .. tostring(runs) .. #runs
    end
    return table.concat(parts, "|")
end
-- fn's answer for this key, worked out once.
local function Memo(self, name, fn, ...)
    local key = StatsKey(self)
    if key ~= _memoKey then _memo, _memoKey = {}, key end
    local v = _memo[name]
    if v == nil then v = fn(self, ...); _memo[name] = v end
    return v
end

-- Which character each archived run belongs to.
local function OwnersNow(self)
    local out = {}
    for _, e in ipairs(self:ArchiveRuns()) do out[e] = self._charKey end
    for key, c in pairs(Account().chars) do
        if key ~= self._charKey then
            for _, e in ipairs(CharRuns(c)) do out[e] = key end
        end
    end
    return out
end
function MS:RunOwner(e) return Memo(self, "owners", OwnersNow)[e] end
function MS:IsOwnRun(e)
    if not self._charKey then return true end      -- name not known yet: everything is ours
    local owner = self:RunOwner(e)
    return owner ~= nil and owner == self._charKey
end

-- The runs the Stats page shows, oldest first.
local StatsRunsNow
function MS:StatsRuns()
    self:ArchiveRuns()
    self:SyncAccountStats()
    return Memo(self, "runs", StatsRunsNow)
end
function StatsRunsNow(self)
    local mine = self:ArchiveRuns()
    local me, want = self._charKey, self:GetStatsChar()
    if not me or want == me then return mine end
    local out = {}
    for key, c in pairs(Account().chars) do
        if want == "all" or want == key then
            for _, e in ipairs(key == me and mine or CharRuns(c)) do _ins(out, e) end
        end
    end
    _sort(out, function(x, y) return (x.at or 0) < (y.at or 0) end)
    return out
end

-- Every item in the shown runs, newest first.
local function LootHistoryNow(self)
    local out = {}
    for _, e in ipairs(self:StatsRuns()) do
        for _, l in ipairs(e.loot or {}) do _ins(out, { item = l, run = e }) end
    end
    _sort(out, function(x, y)
        local ax, ay = (x.run.at or 0) + (x.item.t or 0), (y.run.at or 0) + (y.item.t or 0)
        return ax > ay
    end)
    return out
end

-- ── Comparing two runs ─────────────────────────────────────────────────────
-- Boss by boss: when each run killed it, how far ahead or behind the later
-- run was at that point, the fight itself, and the trash before it (from
-- the previous kill in that run to the pull). Bosses are matched by name,
-- in the earlier run's order; one only killed in one run still gets a row.
-- Differences are later minus earlier: negative means the later run was
-- faster.
local function Segments(e)
    local out, prev = {}, 0
    for _, b in ipairs(e.bosses or {}) do
        local pull = b.d and (b.t - b.d) or nil
        out[#out + 1] = { n = b.n, t = b.t, d = b.d, m = b.m,
                          trash = pull and _max(0, pull - prev) or nil }
        prev = b.t
    end
    return out
end

function MS:CompareRuns(x, y)
    if not (x and y) then return nil end
    local a, b = x, y
    if (b.at or 0) < (a.at or 0) then a, b = b, a end
    local sa, sb = Segments(a), Segments(b)
    local byName = {}
    for _, s in ipairs(sb) do byName[s.n] = byName[s.n] or s end
    local rows, used = {}, {}
    for _, s in ipairs(sa) do
        local o = byName[s.n]
        if o and not used[o] then used[o] = true else o = nil end
        rows[#rows + 1] = { name = s.n, a = s, b = o }
    end
    for _, s in ipairs(sb) do
        if not used[s] then rows[#rows + 1] = { name = s.n, b = s } end
    end
    for _, r in ipairs(rows) do
        local ra, rb = r.a, r.b
        if ra and rb then
            r.split = rb.t - ra.t
            if ra.d and rb.d then r.fight = rb.d - ra.d end
            if ra.trash and rb.trash then r.trashDiff = rb.trash - ra.trash end
        end
    end
    local function Sum(list, key)
        local t, ok = 0, #list > 0
        for _, s in ipairs(list) do
            if s[key] then t = t + s[key] else ok = false end
        end
        return ok and t or nil
    end
    local last = function(list) return list[#list] and list[#list].t or 0 end
    local total = {
        a = a.dur, b = b.dur, diff = (b.dur or 0) - (a.dur or 0),
        fightA = Sum(sa, "d"), fightB = Sum(sb, "d"),
        trashA = Sum(sa, "trash"), trashB = Sum(sb, "trash"),
        endA = (a.dur or 0) - last(sa), endB = (b.dur or 0) - last(sb),
        deathsA = a.deaths or 0, deathsB = b.deaths or 0,
        dpsA = a.me and a.me.dps, dpsB = b.me and b.me.dps,
    }
    return { first = a, second = b, rows = rows, total = total }
end

-- ── Numbers for the Stats page ─────────────────────────────────────────────
local function Median(list)
    local n = #list
    if n == 0 then return nil end
    local s = {}
    for i, v in ipairs(list) do s[i] = v end
    _sort(s)
    if n % 2 == 1 then return s[(n + 1) / 2] end
    return _floor((s[n / 2] + s[n / 2 + 1]) / 2 + 0.5)
end
MS._Median = Median

local RECENT = 12   -- runs in a dungeon's recent-times strip

-- Everything the overview shows, from the archive.
local function StatsOverviewNow(self)
    local runs = self:StatsRuns()
    local out = { runs = #runs, cleared = 0, time = 0, deaths = 0, dungeons = {}, mates = {},
                  xp = 0, levels = 0, kills = 0, quests = 0, gold = 0, progRuns = 0 }
    local byName, mates = {}, {}

    for _, e in ipairs(runs) do
        out.time = out.time + (e.dur or 0)
        out.deaths = out.deaths + (e.deaths or 0)
        if e.cleared then out.cleared = out.cleared + 1 end

        local d = byName[e.dungeon]
        if not d then
            d = { name = e.dungeon, runs = 0, cleared = 0, deaths = 0, clearTimes = {}, recent = {}, last = 0 }
            byName[e.dungeon] = d
            _ins(out.dungeons, d)
        end
        d.runs = d.runs + 1
        d.deaths = d.deaths + (e.deaths or 0)
        local pg = e.prog
        if pg then
            out.progRuns = out.progRuns + 1
            local xp = (pg.xp or 0) + (pg.qx or 0)
            out.xp, out.kills = out.xp + xp, out.kills + (pg.k or 0)
            out.levels, out.quests = out.levels + (pg.lv or 0), out.quests + (pg.q or 0)
            out.gold = out.gold + (pg.g or 0) + (pg.qg or 0)
            d.xp, d.xpRuns = (d.xp or 0) + xp, (d.xpRuns or 0) + 1
            d.questXP = (d.questXP or 0) + (pg.qx or 0)
            d.xpTime = (d.xpTime or 0) + (e.dur or 0)
        end
        if e.cleared then
            d.cleared = d.cleared + 1
            _ins(d.clearTimes, e.dur)
            if not d.best or e.dur < d.best then d.best = e.dur end
        end
        _ins(d.recent, e)
        if #d.recent > RECENT then _rem(d.recent, 1) end
        if (e.at or 0) >= d.last then
            d.last = e.at or 0
            if e.me then d.lastDps, d.lastLvl = e.me.dps, e.me.lvl end
        end

        for _, g in ipairs(e.group or {}) do
            local m = mates[g.n]
            if not m then
                m = { name = g.n, class = g.c, runs = 0, cleared = 0 }
                mates[g.n] = m
                _ins(out.mates, m)
            end
            m.runs = m.runs + 1
            if e.cleared then m.cleared = m.cleared + 1 end
            m.class = g.c or m.class
        end
    end

    for _, d in ipairs(out.dungeons) do
        d.typical = Median(d.clearTimes)
        d.deathsPerRun = d.runs > 0 and d.deaths / d.runs or 0
        if d.xpRuns and d.xpRuns > 0 then
            d.xpPerRun = d.xp / d.xpRuns
            d.xpPerHour = (d.xpTime or 0) > 0 and d.xp / d.xpTime * 3600 or nil
        end
    end
    _sort(out.dungeons, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.name < b.name
    end)
    _sort(out.mates, function(a, b)
        if a.runs ~= b.runs then return a.runs > b.runs end
        return a.name < b.name
    end)
    out.deathsPerRun = out.runs > 0 and out.deaths / out.runs or 0
    return out
end

-- One dungeon's runs, oldest first, with its best and typical clear times.
local function StatsForDungeonNow(self, name)
    local list, clears = {}, {}
    local best
    for _, e in ipairs(self:StatsRuns()) do
        if e.dungeon == name then
            _ins(list, e)
            if e.cleared then
                _ins(clears, e.dur)
                if not best or e.dur < best then best = e.dur end
            end
        end
    end
    -- Each boss: kills, fight lengths (best and typical) and your best DPS,
    -- in the order they're usually killed.
    local bosses, byBoss = {}, {}
    for _, e in ipairs(list) do
        for i, b in ipairs(e.bosses or {}) do
            local x = byBoss[b.n]
            if not x then
                x = { name = b.n, kills = 0, fights = {}, order = 0 }
                byBoss[b.n] = x
                _ins(bosses, x)
            end
            x.kills = x.kills + 1
            x.order = x.order + i
            if b.d and b.d > 0 then
                _ins(x.fights, b.d)
                if not x.best or b.d < x.best then x.best = b.d end
            end
            if b.m and (not x.bestDps or b.m > x.bestDps) then x.bestDps = b.m end
        end
    end
    for _, x in ipairs(bosses) do
        x.typical = Median(x.fights)
        x.order = x.order / x.kills
    end
    _sort(bosses, function(p, q)
        if p.order ~= q.order then return p.order < q.order end
        return p.name < q.name
    end)
    return {
        name = name, runs = list, best = best, typical = Median(clears),
        cleared = #clears, clearRate = #list > 0 and #clears / #list or 0,
        bosses = bosses,
    }
end

-- ── Keys (Mythic+) ──────────────────────────────────────────────────────────
-- From the shown runs' keys:
--   keys, timed               counts
--   dungeons  { name, keys, timed, upSum, upN, bestTimed, highest }  most keys first
--   levels    { level, keys, timed }   highest first
--   rating    { [character key] = { {at, v, after, e}, ... } }   oldest first;
--             v is the rating after the key, or going into it on older runs
local function KeyStatsNow(self)
    local out = { keys = 0, timed = 0, dungeons = {}, levels = {}, rating = {}, ratingChars = 0 }
    local byName, byLevel = {}, {}
    for _, e in ipairs(self:StatsRuns()) do
        if e.key and not e.quit then
            out.keys = out.keys + 1
            local timed = e.inTime and true or false
            if timed then out.timed = out.timed + 1 end
            local d = byName[e.dungeon]
            if not d then
                d = { name = e.dungeon, keys = 0, timed = 0, upSum = 0, upN = 0 }
                byName[e.dungeon] = d
                _ins(out.dungeons, d)
            end
            d.keys = d.keys + 1
            d.highest = _max(d.highest or 0, e.key)
            if timed then
                d.timed = d.timed + 1
                d.bestTimed = _max(d.bestTimed or 0, e.key)
            end
            local up = tonumber(e.up) or (e.cleared and not timed and 0) or nil
            if up then d.upSum, d.upN = d.upSum + up, d.upN + 1 end
            local lv = byLevel[e.key]
            if not lv then
                lv = { level = e.key, keys = 0, timed = 0 }
                byLevel[e.key] = lv
                _ins(out.levels, lv)
            end
            lv.keys = lv.keys + 1
            if timed then lv.timed = lv.timed + 1 end
            local v = tonumber(e.r1) or tonumber(e.r0)
            if v and v > 0 then
                local who = self:RunOwner(e) or "?"
                local list = out.rating[who]
                if not list then list = {}; out.rating[who] = list; out.ratingChars = out.ratingChars + 1 end
                _ins(list, { at = e.at or 0, v = v, after = e.r1 ~= nil, e = e })
            end
        end
    end
    _sort(out.dungeons, function(x, y)
        if x.keys ~= y.keys then return x.keys > y.keys end
        return x.name < y.name
    end)
    _sort(out.levels, function(x, y) return x.level > y.level end)
    for _, list in pairs(out.rating) do _sort(list, function(x, y) return x.at < y.at end) end
    return out
end
function MS:KeyStats() local _ = self:StatsRuns(); return Memo(self, "keys", KeyStatsNow) end

function MS:StatsOverview() local _ = self:StatsRuns(); return Memo(self, "overview", StatsOverviewNow) end
function MS:LootHistory() local _ = self:StatsRuns(); return Memo(self, "loot", LootHistoryNow) end
function MS:StatsForDungeon(name)
    local _ = self:StatsRuns()
    return Memo(self, "d:" .. tostring(name), StatsForDungeonNow, name)
end

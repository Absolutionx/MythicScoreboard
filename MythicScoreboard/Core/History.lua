-- Run history: the last few finished runs, in full, for the scoreboard.
--
-- MythicScoreboardDB.runs, newest first, up to the "Runs to keep" setting.
-- Every finished run is also summarised into the permanent archive
-- (Archive.lua), which is where personal bests come from.
--
-- Each character's history is also kept account-wide
-- (MythicScoreboardAccountDB.chars[name@realm].history, the same table while
-- that character is logged in), so the history list can show the runs of
-- all your characters. Only the character a run belongs to can delete it.

local _fmt, _ins, _rem = string.format, table.insert, table.remove

local MS = _G["MythicScoreboard"]
local L = MS.L

local function Runs() return MythicScoreboardDB and MythicScoreboardDB.runs end

local function Trim(runs, cap)
    while #runs > cap do _rem(runs) end
end

-- A finished run, saved: newest first in history, and into the archive.
function MS:_CommitRunToHistory(run)
    local runs = Runs()
    if not runs then return end
    local saved = self:SerializeRun(run)
    _ins(runs, 1, saved)
    Trim(runs, self:GetHistoryLimit())
    -- Loot (e.g. the Mythic+ chest) can arrive after this; Loot.lua attaches
    -- it to the saved copy for a few minutes.
    self._lastCommittedRun = saved
    self._lastCommittedAt  = GetTime()
    if self.ArchiveRun then self:ArchiveRun(saved) end
    return saved
end

-- Fewer runs to keep: the oldest go now.
MS:OnSettingChanged("historyLimit", function(cap)
    local runs = Runs()
    if runs then Trim(runs, MS:GetHistoryLimit()) end
end)

-- Empties history. The run in progress (or paused) carries on, and the
-- archive behind the Stats page is left alone.
function MS:ClearHistory()
    if MythicScoreboardDB then MythicScoreboardDB.runs = {} end
    self._lastCommittedRun = nil
    self.displayRun = nil
    self:MirrorHistory()
    self:Changed("history")
end

-- ── All your characters ────────────────────────────────────────────────────
local function AccountChars()
    local acc = rawget(_G, "MythicScoreboardAccountDB")
    return type(acc) == "table" and type(acc.chars) == "table" and acc.chars or nil
end

-- This character's history, account-wide (the same table).
function MS:MirrorHistory()
    if not self._charKey and self.SyncAccountStats then self:SyncAccountStats() end
    local key, chars = self._charKey, AccountChars()
    local runs = Runs()
    if not (key and chars and runs) then return end
    chars[key] = chars[key] or {}
    chars[key].history = runs
end

-- Whose runs the history list shows: "all" characters or just "me".
function MS:GetHistoryScope()
    local acc = rawget(_G, "MythicScoreboardAccountDB")
    return (type(acc) == "table" and acc.historyScope == "me") and "me" or "all"
end
function MS:SetHistoryScope(scope)
    local acc = rawget(_G, "MythicScoreboardAccountDB")
    if type(acc) == "table" then acc.historyScope = (scope == "me") and "me" or nil end
    self:Changed("history")
end

-- Which character a saved run belongs to (name, class), for runs from the
-- account-wide lists. Nil for this character's own.
local _owner = setmetatable({}, { __mode = "k" })
function MS:HistoryOwner(run) return _owner[run] end
function MS:IsOwnHistoryRun(run) return run ~= nil and _owner[run] == nil end

-- Other characters with saved runs.
function MS:OtherHistoryChars()
    local out, chars, me = {}, AccountChars(), self._charKey
    if not (chars and me) then return out end
    for key, c in pairs(chars) do
        if key ~= me and type(c.history) == "table" and #c.history > 0 then
            _ins(out, { key = key, name = c.name or key:match("^[^@]+") or key, class = c.class, runs = c.history })
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- The runs the history list shows, newest first:
-- { run, own = true | owner = { name, class } }.
function MS:HistoryEntries(scope)
    scope = scope or self:GetHistoryScope()
    local out = {}
    for _, r in ipairs(Runs() or {}) do _ins(out, { run = r, own = true }) end
    if scope == "all" then
        for _, c in ipairs(self:OtherHistoryChars()) do
            local who = { name = c.name, class = c.class, key = c.key }
            for _, r in ipairs(c.runs) do
                if type(r) == "table" then
                    _owner[r] = who
                    _ins(out, { run = r, owner = who })
                end
            end
        end
        -- Interleaved by when each run started (stable for equal times).
        for i, e in ipairs(out) do e._i = i end
        table.sort(out, function(a, b)
            local ta, tb = a.run._wallClockStart or 0, b.run._wallClockStart or 0
            if ta ~= tb then return ta > tb end
            return a._i < b._i
        end)
    end
    return out
end

-- A saved run's place in the history list (1 = newest), or nil.
function MS:HistoryIndexOf(run)
    for i, e in ipairs(self:HistoryEntries()) do
        if e.run == run then return i end
    end
end

-- ── Personal bests ─────────────────────────────────────────────────────────
-- A key's best time: your fastest in-time run of that dungeon at that level,
-- from the archive (every run you've finished), and from the table older
-- versions kept.
function MS:BestKeyTime(dungeon, level)
    local best
    local legacy = MythicScoreboardDB and MythicScoreboardDB.personalBests
    local old = legacy and legacy[(dungeon or "") .. ":" .. (level or 0)]
    if type(old) == "number" and old > 0 then best = old end
    if self.ArchiveRuns then
        for _, e in ipairs(self:ArchiveRuns()) do
            if e.dungeon == dungeon and e.key == level and e.cleared and e.inTime
                    and (e.dur or 0) > 0 and (not best or e.dur < best) then
                best = e.dur
            end
        end
    end
    return best
end

local function IsTimedKey(run)
    return run and run.completed and run.inTime and (run.keystoneLevel or 0) > 0
end

-- Whether a run (live or saved) is your best time for its key.
function MS:IsPersonalBest(run)
    if not IsTimedKey(run) then return false end
    if run._demo or self:HistoryOwner(run) then return false end   -- another character's run: its bests aren't this one's
    local dur = run.duration or 0
    if dur <= 0 then return false end
    local best = self:BestKeyTime(run.dungeonName, run.keystoneLevel)
    return not best or dur <= best + 0.5      -- archived times are whole seconds
end

-- After a timed key is saved: a line in chat for a first clear or a new best.
-- `before` is the best time as it stood before this run was archived.
function MS:_AnnouncePB(run, before)
    if not IsTimedKey(run) then return end
    local dur = self:GetRunDuration(run)
    local timeStr = self:FormatTime(dur)
    if not before then
        print(_fmt("|cff00ccff[MythicScoreboard]|r |cffffcc00** " .. L["First recorded clear!"] .. "|r %s +%d -- %s",
            run.dungeonName, run.keystoneLevel, timeStr))
    elseif dur < before then
        print(_fmt("|cff00ccff[MythicScoreboard]|r |cffffcc00** " .. L["New personal best!"] .. "|r %s +%d -- %s |cff888888(-%s)|r",
            run.dungeonName, run.keystoneLevel, timeStr, self:FormatTime(before - dur)))
    end
end

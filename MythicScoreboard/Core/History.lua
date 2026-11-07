-- Run history: the last few finished runs, in full, for the scoreboard.
--
-- MythicScoreboardDB.runs, newest first, up to the "Runs to keep" setting.
-- Every finished run is also summarised into the permanent archive
-- (Archive.lua), which is where personal bests come from.

local _fmt, _ins, _rem = string.format, table.insert, table.remove

local MS = _G["MythicScoreboard"]

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
    if self.RefreshOverview then self:RefreshOverview() end
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
        print(_fmt("|cff00ccff[MythicScoreboard]|r |cffffcc00** First recorded clear!|r %s +%d -- %s",
            run.dungeonName, run.keystoneLevel, timeStr))
    elseif dur < before then
        print(_fmt("|cff00ccff[MythicScoreboard]|r |cffffcc00** New personal best!|r %s +%d -- %s |cff888888(-%s)|r",
            run.dungeonName, run.keystoneLevel, timeStr, self:FormatTime(before - dur)))
    end
end

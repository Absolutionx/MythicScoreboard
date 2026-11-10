local _abs    = math.abs
local _floor  = math.floor
local _huge   = math.huge
local _max    = math.max
local _min    = math.min
local _fmt    = string.format
local _ins    = table.insert
local _rem    = table.remove
local _sort   = table.sort

local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local Abbrev, Art, Btn, BuildTimeline, CELL_FONT_SIZE = UI.Abbrev, UI.Art, UI.Btn, UI.BuildTimeline, UI.CELL_FONT_SIZE
local CLASS_ICON_COORDS, COLS, CT, ClassColor, ComputeColumnAnchors = UI.CLASS_ICON_COORDS, UI.COLS, UI.CT, UI.ClassColor, UI.ComputeColumnAnchors
local DN, DiffShort, FRAME_W, GetRole, GetTimelineDuration, HGrad = UI.DN, UI.DiffShort, UI.FRAME_W, UI.GetRole, UI.GetTimelineDuration, UI.HGrad
local Outline, P, PAD_X, ROLE_ICON_COORDS, ROLE_ICON_TEX, ROW_H = UI.Outline, UI.P, UI.PAD_X, UI.ROLE_ICON_COORDS, UI.ROLE_ICON_TEX, UI.ROW_H
local ScoreColor, SetFont, Solid, SplitAbbrev, Text, Tint = UI.ScoreColor, UI.SetFont, UI.Solid, UI.SplitAbbrev, UI.Text, UI.Tint

-- Scoreboard: the header line, the table's layout and sorting, the timeline
-- slot, and the refresh. The rows themselves: UI_ScoreboardRows.lua.

-- ===========================================================================
-- Table state: rows on screen, the sort
-- ===========================================================================

local overviewRows = {}
local _playersBuf = {}

local sortState    = { key = nil, dir = 1 }
local colHdrLabels = {}

local COL_SORT_VALUES = {
    player     = function(p) return p.name or "" end,
    loot       = function(p) return p.loot and #p.loot or 0 end,
    level      = function(p) return p.level or 0 end,
    score      = function(p) return p.mythicScore or 0 end,
    deaths     = function(p) return p.deaths or 0 end,
    dmgTaken   = function(p) return p.damageTaken or 0 end,
    avoidable  = function(p) return p.avoidableDamageTaken or 0 end,
    damage     = function(p) return p.damageDone or 0 end,
    healing    = function(p) return p.healingDone or 0 end,
    -- Per second, as shown: the meter's rate, else the total over the run.
    dps        = function(p, dur) return (p.dps or 0) > 0 and p.dps or ((dur or 0) > 0 and (p.damageDone or 0) / dur or 0) end,
    hps        = function(p, dur) return (p.hps or 0) > 0 and p.hps or ((dur or 0) > 0 and (p.healingDone or 0) / dur or 0) end,
    interrupts = function(p) return p.interrupts or 0 end,
    dispels    = function(p) return p.dispels or 0 end,
}

-- Shared with UI.lua (the column header) and the tests.
UI.overviewRows, UI.sortState, UI.colHdrLabels = overviewRows, sortState, colHdrLabels

-- ── Rows: UI_ScoreboardRows.lua ───────────────────────────────────────────
local Rows = UI.Rows
local AcquireRow, ReleaseRow, FillRow = Rows.AcquireRow, Rows.ReleaseRow, Rows.FillRow
local RateOf, COL_RENDERERS = Rows.RateOf, Rows.COL_RENDERERS

local function FightEnd(run, boss)
    return MS.FightEnd(boss) or MS:GetRunDuration(run)
end

local function WithinFight(list, field, t1, t2)
    local out = {}
    for _, x in ipairs(list or {}) do
        local t = type(x) == "table" and (x[field] or 0) or x
        if t >= t1 and t <= t2 then _ins(out, x) end
    end
    return out
end

local function FightView(run, boss)
    local pullT = boss.pullTime or 0
    local endT  = FightEnd(run, boss)
    local dur   = _max(1, endT - pullT)
    -- Loot from the pull until the next pull (at most 5 minutes after the kill).
    local lootEnd = endT + 300
    for _, b in ipairs(run.bosses or {}) do
        if b ~= boss and (b.pullTime or 0) > pullT then lootEnd = _min(lootEnd, b.pullTime) end
    end
    local stats = boss.stats
    local players = {}
    for key, p in pairs(run.players or {}) do
        local s = stats and stats[key]
        local deaths = WithinFight(p.deathEvents, "time", pullT, endT)
        local kicks  = WithinFight(p.interruptEvents, "time", pullT, endT)
        -- With the fight's numbers, players with none weren't in it.
        if not stats or s or #deaths > 0 then
            s = s or {}
            players[key] = setmetatable({
                damageDone = s.dmg or 0, healingDone = s.heal or 0,
                dps = (s.dmg or 0) / dur, hps = (s.heal or 0) / dur,
                damageTaken = s.taken or 0, avoidableDamageTaken = s.avoid or 0,
                interrupts = stats and (s.int or 0) or #kicks, dispels = s.disp or 0,
                deaths = #deaths, deathEvents = deaths, interruptEvents = kicks,
                loot = WithinFight(p.loot, "t", pullT, lootEnd),
            }, { __index = p })
        end
    end
    return setmetatable({ players = players, _fight = boss, _fightDur = dur }, { __index = run }), dur
end

local function FocusedBoss(run)
    local f = UI.focus
    if f and f.run == run then return f.boss end
    return nil
end

-- Shows one fight, or the whole run again when that fight is already shown.
function UI.FocusBoss(run, boss)
    if not boss or (UI.focus and UI.focus.boss == boss) then
        UI.focus = nil
    elseif MS.FightEnd(boss) then
        UI.focus = { run = run, boss = boss }
    end
    if GameTooltip then GameTooltip:Hide() end
    MS:RefreshOverview()
end

local function WholeRunButton()
    local f = UI.frame
    if f.WholeRunBtn then return f.WholeRunBtn end
    local b = Btn(f)
    b:SetSize(112, 22)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -54)   -- where L["New personal best"] sits
    b:SetFrameLevel(f:GetFrameLevel() + 20)
    local arrow = Art(b, "Chevron", "OVERLAY")
    arrow:SetSize(12, 12); arrow:SetRotation(-math.pi / 2); Tint(arrow, P.ash)
    local txt = Text(b, "medium", 13, P.ash, "RIGHT")
    txt:SetPoint("RIGHT", b, "RIGHT", -4, 0); txt:SetText(L["Whole run"])
    arrow:SetPoint("RIGHT", txt, "LEFT", -4, 0)
    b:SetScript("OnEnter", function(self2)
        Tint(arrow, P.ivory); txt:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:SetOwner(self2, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Back to the whole run"], P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        Tint(arrow, P.ash); txt:SetTextColor(P.ash[1], P.ash[2], P.ash[3])
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function() UI.FocusBoss(nil, nil) end)
    b:Hide()
    f.WholeRunBtn = b
    return b
end

-- L["Abandon run"]: on the run in progress (or paused), two clicks.
local function AbandonButton()
    local f = UI.frame
    if f.AbandonBtn then return f.AbandonBtn end
    local b = Btn(f)
    b:SetSize(130, 22)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -54)
    b:SetFrameLevel(f:GetFrameLevel() + 20)
    local txt = Text(b, "medium", 13, P.ash2, "RIGHT")
    txt:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    local armed, timer = false, nil
    local function Look()
        local c = armed and P.bloodHi or P.ash2
        txt:SetText(armed and L["Click again to abandon"] or L["Abandon run"])
        txt:SetTextColor(c[1], c[2], c[3])
    end
    local function Disarm()
        armed = false
        if timer then timer:Cancel(); timer = nil end
        Look()
    end
    b.Disarm = Disarm
    b:SetScript("OnClick", function()
        if armed then
            Disarm()
            GameTooltip:Hide()
            MS:AbandonRun()
        else
            armed = true; Look()
            timer = C_Timer.NewTimer(3, Disarm)
        end
    end)
    b:SetScript("OnEnter", function(self2)
        if not armed then txt:SetTextColor(P.bloodHi[1], P.bloodHi[2], P.bloodHi[3]) end
        GameTooltip:SetOwner(self2, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Abandon run"], P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:AddLine(L["Ends this run now and saves it as abandoned. A new run starts the next time you enter a dungeon."],
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        if not armed then Look() end
        GameTooltip:Hide()
    end)
    Look()
    b:Hide()
    f.AbandonBtn = b
    return b
end

-- After abandoning a run inside a dungeon: start a new one right here, from
-- now, without leaving and coming back in. Sits where "Abandon run" was.
local function StartFreshButton()
    local f = UI.frame
    if f.FreshRunBtn then return f.FreshRunBtn end
    local b = Btn(f)
    b:SetSize(130, 22)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -54)
    b:SetFrameLevel(f:GetFrameLevel() + 20)
    local txt = Text(b, "medium", 13, P.bronzeHi, "RIGHT")
    txt:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    txt:SetText(L["Start new run"])
    b:SetScript("OnClick", function()
        GameTooltip:Hide()
        MS:StartFresh()
    end)
    b:SetScript("OnEnter", function(self2)
        txt:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:SetOwner(self2, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Start new run"], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        GameTooltip:AddLine(L["Starts a new run in this dungeon, from now. No need to leave and come back in."],
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        txt:SetTextColor(P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        GameTooltip:Hide()
    end)
    b:Hide()
    f.FreshRunBtn = b
    return b
end

-- ===========================================================================
-- Public API
-- ===========================================================================

function MS:ShowScoreboard()
    if not UI.frame then self:BuildUI() end
    UI.frame:Show(); UI.frame:Raise()
    self._refreshPending = false
    -- Fresh numbers on opening; while open, the 2-second poll keeps them fresh.
    if self.inDungeon and not InCombatLockdown() then self:SnapshotFromDamageMeter() end
    local ok, err = pcall(self._DoRefreshOverview, self)
    if not ok then
        UI.SayOnce("Scoreboard refresh", err)
    end
    if UI.frame.RefreshHistBtn then UI.frame.RefreshHistBtn() end
end

-- Redraws soon (once per frame at most). Nothing is drawn while the window
-- is closed: opening it draws everything as it stands.
function MS:RefreshOverview()
    if not (UI.frame and UI.frame:IsShown()) then return end
    if self._refreshPending then return end
    self._refreshPending = true
    C_Timer.After(0, function()
        self._refreshPending = false
        if not (UI.frame and UI.frame:IsShown()) then return end
        if self._refreshing then return end
        self._refreshing = true
        local ok, err = pcall(self._DoRefreshOverview, self)
        self._refreshing = false
        if not ok then
            UI.SayOnce("Scoreboard refresh", err)
        end
        if UI.frame and UI.frame.RefreshHistBtn then UI.frame.RefreshHistBtn() end
    end)
end

-- Whatever the core says changed, the scoreboard redraws (batched above).
MS:OnChanged(function() MS:RefreshOverview() end)

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

local function DefaultPlayerSort(a, b)
    local aLeft = a.left and 1 or 0
    local bLeft = b.left and 1 or 0
    if aLeft ~= bLeft then return aLeft < bLeft end
    local ra = ROLE_ORDER[GetRole(a)] or 3
    local rb = ROLE_ORDER[GetRole(b)] or 3
    if ra ~= rb then return ra < rb end
    return (a.damageDone or 0) > (b.damageDone or 0)
end

local function Thousands(n)
    n = _floor(n + 0.5)
    local B = rawget(_G, "BreakUpLargeNumbers")
    return B and B(n) or tostring(n)
end

local function RefreshHeader(run)
    if not run then
        UI.frame.DungeonName:SetText(L["Dungeon Scoreboard"])
        UI.frame.SetBadge(nil)
        UI.frame.Subline:SetText(L["No runs yet. Enter a dungeon you track and the scoreboard fills in as you play."])
        UI.frame.SublineRun = nil
        UI.frame.PBLabel:Hide()
        UI.frame.LayoutAffixIcons(0)
        if UI.frame.WholeRunBtn then UI.frame.WholeRunBtn:Hide() end
        if UI.frame.AbandonBtn then UI.frame.AbandonBtn:Hide() end
        StartFreshButton():SetShown(MS:CanStartFresh())
        return
    end

    local isMPlus = (run.keystoneLevel or 0) > 0
    local title = UI.frame.DungeonName
    title:SetText(MS:RunTitle(run))
    SetFont(title, "title", 24)
    if title:GetStringWidth() > 560 then SetFont(title, "title", 19) end

    if isMPlus then UI.frame.SetBadge("+" .. run.keystoneLevel, true)
    elseif not MS.Flavor.difficulties then UI.frame.SetBadge(nil)
    else UI.frame.SetBadge(DiffShort(run), false) end

    -- Subline: [mode]  [time]  [result]  [deaths]
    local parts = {}
    local dur = MS:GetRunDuration(run)
    local limit = tonumber(run.keystoneTimeLimit)
    if isMPlus then _ins(parts, L["Mythic Keystone"]) end
    if isMPlus and limit and limit > 0 then
        _ins(parts, CT(P.ivory, MS:FormatTime(dur)) .. " / " .. MS:FormatTime(limit))
    else
        _ins(parts, CT(P.ivory, MS:FormatTime(dur)))
    end

    if run.completed then
        if isMPlus and limit and limit > 0 then
            local diff = _abs(limit - dur)
            local res
            if run.inTime then res = CT(P.verd, _fmt(L["In time, %s to spare"], MS:FormatTime(diff)))
            else res = CT(P.avoid, _fmt(L["Over time by %s"], MS:FormatTime(diff))) end
            _ins(parts, res .. "  " .. UI.Pips(MS:RunUpgrades(run), 13))
        elseif isMPlus then
            _ins(parts, (run.inTime and CT(P.verd, L["In time"]) or CT(P.avoid, L["Over time"]))
                .. "  " .. UI.Pips(MS:RunUpgrades(run), 13))
        else
            _ins(parts, CT(P.verd, L["Cleared"]))
        end
    else
        local text, col = UI.RunResult(run)    -- in progress, paused, finished or abandoned
        _ins(parts, CT(col, text))
    end

    if MS.Flavor.bossProgress and not isMPlus then
        local killed, total = MS:ForeverBossProgress(run)
        if total then
            _ins(parts, _fmt(L["%s of %s bosses"], CT(P.ivory, killed), CT(P.ivory, total)))
        else
            local n = 0
            for _, b in ipairs(run.bosses or {}) do if b.killTime then n = n + 1 end end
            _ins(parts, MS.Plural(n, "%d boss killed", "%d bosses killed"))
        end
        local lo, hi = MS:ForeverLevelRange(run)
        if lo then _ins(parts, _fmt(L["Levels %d-%d"], lo, hi)) end
    end

    local deaths = 0
    for _, p in pairs(run.players or {}) do deaths = deaths + (p.deaths or 0) end
    if deaths == 0 then
        _ins(parts, L["No deaths"])
    else
        local s = MS.Plural(deaths, "%d death", "%d deaths")
        local penalty = run.deathPenaltySeconds or 0
        if isMPlus and penalty > 0 then s = s .. ", -" .. MS:FormatTime(penalty) end
        _ins(parts, CT(P.blood, s))
    end
    -- Your rating after a key, and what it gained.
    if isMPlus and run.completed and (run.ratingAfter or 0) > 0 then
        local r = _fmt(L["Rating %s"], CT(P.ivory, Thousands(run.ratingAfter)))
        local gain = math.floor(run.ratingAfter - (run.ratingBefore or run.ratingAfter) + 0.5)
        if gain > 0 then r = r .. " " .. CT(P.verdHi, "+" .. gain) end
        _ins(parts, r)
    end
    -- Forever: what the run did for you (the full list is in the tooltip).
    local pr = MS.Flavor.progressStats and run.progress
    if pr then
        local mobXP, questXP = UI.RunXP(pr)
        local xp = _fmt(L["%s XP"], CT(P.ivory, MS.FormatThousands(mobXP + questXP)))
        if questXP > 0 then xp = xp .. "  " .. UI.XPSplit(mobXP, questXP, 56, 6) end
        if (pr.levels or 0) > 0 then
            xp = xp .. CT(P.verdHi, "  " .. MS.Plural(pr.levels, "+%d level", "+%d levels"))
        end
        _ins(parts, xp)
        _ins(parts, MS.Plural(pr.kills or 0, "%d kill", "%d kills", CT(P.ivory, pr.kills or 0)))
        local nq = #(pr.quests or {})
        if nq > 0 then _ins(parts, MS.Plural(nq, "%d quest", "%d quests", CT(P.ivory, nq))) end
        local gold = math.max(0, pr.gold or 0) + (pr.qg or 0)
        if gold > 0 then _ins(parts, CT(P.bronzeHi, MS.FormatGold(gold))) end
    end
    -- (A tighter gap when the line also carries the run's progress.)
    UI.frame.Subline:SetText(table.concat(parts, pr and "    " or "      "))
    UI.frame.SublineRun = pr and run or nil

    UI.frame.PBLabel:SetShown(MS:IsPersonalBest(run))

    -- Affixes
    local affixIDs = {}
    for _, af in ipairs(run.affixes or {}) do _ins(affixIDs, af.id or af) end
    if #affixIDs == 0 and isMPlus and run == MS.currentRun and C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local _, keystoneAffixes = C_ChallengeMode.GetActiveKeystoneInfo()
        for _, id in ipairs(keystoneAffixes or {}) do _ins(affixIDs, id) end
    end
    local count = isMPlus and _min(4, #affixIDs) or 0
    for i = 1, count do
        local fr = UI.frame.AffixIcons[i]
        if fr.affix_id ~= affixIDs[i] then
            pcall(fr.SetUp, fr, affixIDs[i])
            fr.affix_id = affixIDs[i]
        end
    end
    UI.frame.LayoutAffixIcons(count)

    -- The run in progress can be abandoned by hand.
    local ab = AbandonButton()
    local canAbandon = run == MS.currentRun and not run.completed
    if not canAbandon and ab:IsShown() then ab.Disarm() end
    ab:SetShown(canAbandon)
    local fresh = not canAbandon and MS:CanStartFresh()
    StartFreshButton():SetShown(fresh)
    local boss = FocusedBoss(run)
    local wr = WholeRunButton()
    wr:SetShown(boss ~= nil)
    wr:ClearAllPoints()
    if canAbandon then wr:SetPoint("RIGHT", ab, "LEFT", -12, 0)
    elseif fresh then wr:SetPoint("RIGHT", StartFreshButton(), "LEFT", -12, 0)
    else wr:SetPoint("TOPRIGHT", UI.frame, "TOPRIGHT", -14, -54) end
    if not boss then return end
    UI.frame.PBLabel:Hide()
    local result = MS.FightResult(boss)
    local isWipe = MS.FightLost(boss)
    local endT = FightEnd(run, boss)
    local fp = {
        CT(P.bronzeHi, boss.name or L["Boss"]),
        _fmt(L["Fight %s"], CT(P.ivory, MS:FormatTime(endT - (boss.pullTime or 0)))),
        isWipe and CT(P.blood, _fmt(result == "reset" and L["Reset at %s"] or L["Wipe at %s"], MS:FormatTime(endT)))
            or _fmt(L["Killed at %s"], CT(P.ivory, MS:FormatTime(endT))),
    }
    local fd = 0
    for _, p in pairs(run.players or {}) do
        for _, de in ipairs(p.deathEvents or {}) do
            if (de.time or 0) >= (boss.pullTime or 0) and (de.time or 0) <= endT then fd = fd + 1 end
        end
    end
    _ins(fp, fd == 0 and L["No deaths"] or CT(P.blood, MS.Plural(fd, "%d death", "%d deaths")))
    if not boss.stats then
        local waiting = run == MS.currentRun and (boss._session or boss._before)
        _ins(fp, CT(P.ash2, waiting and L["Damage and healing appear once you're out of combat"]
            or L["Damage and healing weren't recorded for this fight"]))
    end
    UI.frame.Subline:SetText(table.concat(fp, "      "))
    UI.frame.SublineRun = nil
end

local function BossSig(r)
    if not r or not r.bosses then return "" end
    local last, icons = 0, 0
    for _, b in ipairs(r.bosses) do
        local e = MS.FightEnd(b) or 0
        if e > last then last = e end
        if b.icon then icons = icons + 1 end
    end
    -- Deaths always redraw; interrupts redraw in batches so a live run
    -- doesn't rebuild the timeline on every kick.
    local deaths, kicks = 0, 0
    for _, p in pairs(r.players or {}) do
        deaths = deaths + #(p.deathEvents or {})
        kicks  = kicks + #(p.interruptEvents or {})
    end
    return table.concat({ #r.bosses, last, icons, MS._portraitRev or 0, tostring(r.completed),
        tostring(r.keystoneTimeLimit), deaths, _floor(kicks / 8), tostring(FocusedBoss(r)) }, ":")
end

-- ── Timeline ───────────────────────────────────────────────────────────────
-- What the timeline last drew, so it's rebuilt only when that changes.
local tl = { run = nil, builtRun = nil, sig = nil, builtAt = nil, totalDur = nil, busy = false }

local function RebuildTimeline(force)
    if tl.busy or not UI.frame then return end
    local r   = tl.run
    local sig = BossSig(r)
    local changed = (r ~= tl.builtRun) or (sig ~= tl.sig)
    if not force and not changed and tl.builtAt then return end
    tl.builtAt, tl.builtRun, tl.sig, tl.busy = GetTime(), r, sig, true
    local tlc = UI.frame.timelineContainer
    if r then
        tlc:Show()
        tl.totalDur = GetTimelineDuration(r)
        local ok, err = pcall(BuildTimeline, tlc, r, tl.totalDur)
        if not ok then
            UI.SayOnce("Timeline", err)
            tl.builtAt = GetTime() + 2.0
            tlc:Hide()
        end
    else
        tlc:Hide()
    end
    tl.busy = false
end
UI.RebuildTimeline = RebuildTimeline      -- the live head asks for it when its window fills

-- ── The table's numbers ────────────────────────────────────────────────────
-- Worked out from the players before anything is drawn.

local function SortPlayers(players, dur)
    if sortState.key and COL_SORT_VALUES[sortState.key] then
        local getter, dir = COL_SORT_VALUES[sortState.key], sortState.dir
        local isStr = sortState.key == "player"
        _sort(players, function(a, b)
            if not a or not b then return false end
            local av, bv = getter(a, dur), getter(b, dur)
            if isStr then
                if dir == 1 then return av < bv else return av > bv end
            end
            if av ~= bv then
                if dir == 1 then return av > bv else return av < bv end
            end
            return (a.name or "") < (b.name or "")
        end)
    else
        _sort(players, DefaultPlayerSort)
    end
end

-- Columns where some value reads "25.8K": a plain "549" there lines up with
-- their right edge instead of their decimal point.
local function SuffixColumns(players, dur, run)
    local out = {}
    for _, c in ipairs(COLS) do
        if c.num == "abbr" then
            for _, p in ipairs(players) do
                if (tonumber((COL_RENDERERS[c.key](p, dur, run))) or 0) >= 1000 then out[c.key] = true; break end
            end
        end
    end
    return out
end

-- The top DPS and HPS, which the share bars are measured against.
local function TopRates(players, dur)
    local topDps, topHps = 0, 0
    for _, p in ipairs(players) do
        topDps = _max(topDps, RateOf(p, "dps", "damageDone", dur))
        topHps = _max(topHps, RateOf(p, "hps", "healingDone", dur))
    end
    return topDps, topHps
end
UI.TableModel = { Sort = SortPlayers, SuffixColumns = SuffixColumns, TopRates = TopRates }   -- for tests

-- What the rows last showed.
local drawn = {}

function MS:_DoRefreshOverview()
    if not UI.frame then return end
    -- The Stats page owns the window while it's open.
    if UI.statsOpen then UI.RefreshStats(); return end

    -- A run picked from history wins, even during a live run; the live run
    -- is back at the top of the history list ("Now").
    local run = self.displayRun or self.currentRun
    if not run and MythicScoreboardDB and MythicScoreboardDB.runs and #MythicScoreboardDB.runs > 0 then
        run = MythicScoreboardDB.runs[1]
    end

    if UI.focus and UI.focus.run ~= run then UI.focus = nil end
    RefreshHeader(run)

    -- ── Timeline (rebuilt only when the run or its bosses change) ────────
    tl.run = run
    RebuildTimeline()
    local tlc = UI.frame.timelineContainer
    if tlc.UpdateLive and tl.run then
        tlc.UpdateLive(tl.run, tl.totalDur or GetTimelineDuration(tl.run))
    end

    -- ── Player rows ──────────────────────────────────────────────────────
    local sf      = UI.overviewSF
    local content = sf.scrollContent

    local runSeq  = run and (run._seq or 0) or -1
    local focus   = run and FocusedBoss(run)
    local focusSig = focus and (tostring(focus) .. (focus.stats and "+" or "")) or ""
    local lootRev = MS._lootRev or 0
    if drawn.done and run == drawn.run and focusSig == drawn.focus and runSeq == drawn.seq
            and sortState.key == drawn.sortKey and sortState.dir == drawn.sortDir and lootRev == drawn.loot then
        return
    end
    drawn.done, drawn.run, drawn.focus, drawn.seq = true, run, focusSig, runSeq
    drawn.sortKey, drawn.sortDir, drawn.loot = sortState.key, sortState.dir, lootRev

    -- Rows are reused in place between refreshes. Handing them back to the
    -- pool and re-anchoring them every poll swapped out the row under the
    -- mouse, which closed its tooltip.
    local prevRows = {}
    for i, r in ipairs(overviewRows) do prevRows[i] = r end
    wipe(overviewRows)
    local function ReleaseFrom(i)
        for k = i, #prevRows do ReleaseRow(prevRows[k]) end
    end

    if not run then
        ReleaseFrom(1)
        if not UI.frame._emptyLbl then
            UI.frame._emptyLbl = Text(content, "regular", 14, P.ash, "CENTER")
            UI.frame._emptyLbl:SetPoint("TOP", content, "TOP", 0, -90)
        end
        UI.frame._emptyLbl:SetText(L["Your group's damage, healing, deaths and interrupts will show here."])
        UI.frame._emptyLbl:Show()
        content:SetHeight(60); sf.UpdateRange()
        return
    end

    local dur = self:GetRunDuration(run)
    -- Another character's run: that character's row is the highlighted one.
    local owner = self:HistoryOwner(run)
    if focus then run, dur = FightView(run, focus) end
    wipe(_playersBuf)
    for _, p in pairs(run.players) do _ins(_playersBuf, p) end
    local players = _playersBuf

    SortPlayers(players, dur)
    local hasSuffix = SuffixColumns(players, dur, run)
    local topDps, topHps = TopRates(players, dur)
    -- Share bars run from the value's right edge back toward the column start.
    local dpsCellW, hpsCellW
    for _, c in ipairs(COLS) do
        if c.key == "dps" then dpsCellW = c.anchor + c.tailW - (c.x + 10) end
        if c.key == "hps" then hpsCellW = c.anchor + c.tailW - (c.x + 10) end
    end

    local ctx = { run = run, dur = dur, hasSuffix = hasSuffix, topDps = topDps, topHps = topHps,
                  dpsCellW = dpsCellW, hpsCellW = hpsCellW, count = #players }
    local yOff, localName = 0, owner and owner.name or MS:UnitPlayerName("player")
    for idx, p in ipairs(players) do
        local isSelf  = (p.name == MS.ShortName(localName or ""))
        local row = prevRows[idx]
        if row and row._nameFs then
            prevRows[idx] = nil                 -- kept: don't release it below
            if row._y ~= yOff then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
            end
        else
            row = AcquireRow(content)
            row:SetSize(FRAME_W - 2, ROW_H)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
        end
        row._y = yOff

        FillRow(row, idx, p, isSelf, ctx)

        yOff = yOff - ROW_H
        _ins(overviewRows, row)
    end
    for k = 1, #players do prevRows[k] = nil end
    for k, r in pairs(prevRows) do ReleaseRow(r) end   -- rows no longer needed (and the empty label)
    if UI.frame._emptyLbl then UI.frame._emptyLbl:Hide() end

    content:SetHeight(_max(60, _abs(yOff)))
    sf.UpdateRange()
end

-- The in-run frame: a small, movable frame with the run at a glance (the
-- clock, the key's timer, bosses, enemy forces, deaths, your pace against
-- your best), for while you play. Three styles (Settings: compactStyle):
--   compact    the clock, the upgrade bar, bosses / forces / deaths, pace
--   detailed   adds time left to each upgrade, every boss with its kill time
--              and your best, forces to two decimals and the last pull,
--              who died, and the week's affixes
--   minimal    one line
-- Shown while a run is recording; /sb compact demo shows a made-up run.
-- Left-click opens the scoreboard, right-click changes the style,
-- Shift-click posts the time left to your party, drag moves it.

local _abs, _ceil, _floor, _max, _min = math.abs, math.ceil, math.floor, math.max, math.min
local _fmt, _ins = string.format, table.insert

local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
local P, Text, Solid, Art, Tint, CT = UI.P, UI.Text, UI.Solid, UI.Art, UI.Tint, UI.CT

local W, PAD = 270, 12                 -- width (compact and detailed), inner margin
local BADGE = { 0.85, 0.66, 0.40 }     -- the key level's filled badge
local TRACK = { 0.165, 0.137, 0.110 }  -- an empty bar
local FILL  = { 0.77, 0.57, 0.33 }     -- the key's time used
local PANEL = { 0.12, 0.10, 0.08 }     -- the pace strip

local f                                -- the frame, made the first time it's shown
local demo                             -- the sample run, while /sb compact demo is on
local changed = false                  -- the run changed since the last draw
local el, used = {}, {}                -- pieces by name; the ones this draw used

-- A script handler that can't break: an error is said once in chat
-- (MS:ReportError) instead of the game's error popup.
local function Safe(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then MS:ReportError("In-run frame", err) end
    end
end

local function T(s) return MS:FormatTime(_max(0, s or 0)) end
local function IsKey(run) return (run.keystoneLevel or 0) > 0 end
local function Clock(run) return run._demoElapsed or MS:GetRunDuration(run) end

-- ── Pieces ─────────────────────────────────────────────────────────────────
-- Each piece is made once, by name, and reused; a draw shows the ones it
-- places and hides the rest.
local function Piece(key, make)
    local x = el[key]
    if not x then x = make(); el[key] = x end
    used[key] = true
    x:Show()
    return x
end
-- The piece if it's been made (shown and kept for this draw), else nil. The
-- callers below write "Got(key) or Piece(key, function() ... end)" so the
-- maker, a new function each time, is only made the first time: the frame
-- redraws every second and these added up to a lot of garbage.
local function Got(key)
    local x = el[key]
    if x then used[key] = true; x:Show() end
    return x
end
-- Text is in the game's own font (Friz Quadrata, or the client's font for
-- its language), a size smaller than the sizes given: it runs wider than the
-- condensed font they were picked for. With the game's drop shadow, so it
-- stays sharp on any background.
local function GameSize(size) return size >= 20 and size - 2 or size - 1 end
local function FS(key, _, size, col, justify)
    local fs = Got(key) or Piece(key, function()
        local t = Text(f, "game", GameSize(size), col, justify)
        t:SetShadowOffset(1, -1); t:SetShadowColor(0, 0, 0, 0.9)
        return t
    end)
    fs:SetTextColor(col[1], col[2], col[3], 1)
    return fs
end
-- A flat bar. Backgrounds go on the BORDER layer, fills over them on
-- ARTWORK, marks over the fills (one layer each: two textures on the same
-- layer and sublevel draw in no set order, so a fill could hide under its track).
local LAYER = { back = { "BORDER", 0 }, fill = { "ARTWORK", 1 }, mark = { "ARTWORK", 3 } }
local function Bar(key, col, a, kind)
    local lay = LAYER[kind or "fill"]
    local t = Got(key) or Piece(key, function() return Solid(f, lay[1], lay[2], 1, 1, 1, 1) end)
    t:SetColorTexture(col[1], col[2], col[3], a or 1)
    return t
end
local function Place(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
end
local function PlaceRight(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPRIGHT", f, "TOPLEFT", x, y)
end
-- A fixed-width line of text that cuts off with "..." when too long. The
-- height is set too, with room to spare: a fontstring given no height, or
-- less than a line of its font, draws nothing.
local function LineH(size) return size + 8 end
local function OneLine(fs, w, size)
    fs:SetWordWrap(false); fs:SetMaxLines(1)
    fs:SetJustifyV("TOP")
    fs:SetSize(w, LineH(size))
end
-- How wide a line's text is, whatever width it's been given.
local function TextWidth(fs)
    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    return _ceil(w or 0)
end
local function Rule(key, y)
    local t = Bar(key, P.line)
    Place(t, PAD, y); t:SetSize(W - 2 * PAD, 1)
end

-- ── What's shown ───────────────────────────────────────────────────────────
-- A key's bosses, from the scenario's objectives (names and done), so the
-- ones still to come are listed too.
local function KeyObjectives(run)
    if run._demoObjectives then return run._demoObjectives end
    local out = {}
    if not (C_Scenario and C_Scenario.GetStepInfo and C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo) then
        return out
    end
    local ok, _, _, n = pcall(C_Scenario.GetStepInfo)
    for i = 1, (ok and MS.ReadableNumber(n)) or 0 do
        local ok2, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if ok2 and type(info) == "table" and not MS.ReadableValue(info.isWeightedProgress) then
            local name = MS.Readable(info.description)
            if name then _ins(out, { name = name, done = MS.ReadableValue(info.completed) == true }) end
        end
    end
    return out
end

-- The same boss, under any of its names (Forever: "The Butcher" for The
-- Baron, the Ring of Law's challenger for the Ring of Law).
local function Same(run, a, b)
    if MS.SameBossName(a, b) then return true end
    return MS.ForeverSameBoss ~= nil and MS:ForeverSameBoss(run, b, a)
end
local function LastFight(run, name)
    for i = #(run.bosses or {}), 1, -1 do
        local b = run.bosses[i]
        if Same(run, b.name, name) then return b end
    end
end

-- The bosses to list: { name, kill (the game's timer), done, fighting, best }.
local BuildBosses
-- Kept until a fight starts or ends (outside keys, whose objectives come from
-- the game): the frame redraws every second, and building the list each
-- time, a table per boss, was most of its garbage.
local bossCache = {}
local function Bosses(run, best)
    if IsKey(run) or run._demo then return BuildBosses(run, best) end
    local list = run.bosses or {}
    local n = #list
    local last, act = list[n], run.activeBoss
    local c = bossCache
    if c.out and c.run == run and c.best == best and c.n == n and c.last == last
            and c.lastKill == (last and last.killTime) and c.act == act
            and c.actKill == (act and act.killTime) and c.name == run.dungeonName and c.wing == run.wingName and c.map == run.uiMapID then
        return c.out
    end
    c.out = BuildBosses(run, best)
    c.run, c.best, c.n, c.last, c.act = run, best, n, last, act
    c.lastKill, c.actKill = last and last.killTime, act and act.killTime
    c.name, c.wing, c.map = run.dungeonName, run.wingName, run.uiMapID
    return c.out
end
function BuildBosses(run, best)
    local names = {}
    if IsKey(run) then
        for _, o in ipairs(KeyObjectives(run)) do _ins(names, { name = o.name, done = o.done }) end
    elseif MS.ForeverDefsFor then
        local defs = MS:ForeverDefsFor(run)
        if defs and #defs == 1 then
            for _, e in ipairs(defs[1].bosses) do
                local b = LastFight(run, e.name)
                if not (e.rare or e.summon) or (b and b.killTime) then _ins(names, { name = e.name }) end
            end
        end
    end
    if #names == 0 then                                  -- nothing to go by: the bosses met so far
        local seen = {}
        for _, b in ipairs(run.bosses or {}) do
            local name = MS.Readable(b.name)
            if name and not seen[name] then seen[name] = true; _ins(names, { name = name }) end
        end
    end
    local out = {}
    for _, n in ipairs(names) do
        local b = LastFight(run, n.name)
        local bt
        for _, x in ipairs(best and best.bosses or {}) do
            if Same(run, x.n, n.name) then bt = x.t end
        end
        _ins(out, { name = n.name, kill = b and b.killTime, done = n.done or (b and b.killTime ~= nil),
                    fighting = b ~= nil and run.activeBoss == b and not b.killTime, best = bt })
    end
    return out
end

-- How far ahead of (negative) or behind your best you were at the last boss
-- down, on the key's own clock (the deaths' cost left out, as in your best).
local function Pace(run, bosses)
    local F = MS.ResultTimeFn(run) or function(t) return t end
    for i = #bosses, 1, -1 do
        local b = bosses[i]
        if b.kill and b.best then return F(b.kill) - b.best, b.name end
    end
end

local function DeathCount(run)
    local n = 0
    for _, p in pairs(run.players or {}) do n = n + (p.deaths or 0) end
    return n
end
local function DeathCost(run)
    if run._demo then return run.deathPenaltySeconds end
    return MS:KeyDeathPenalty() or run.deathPenaltySeconds
end

-- ── Drawing ────────────────────────────────────────────────────────────────
local function Header(run, y)
    -- The whole name: on two lines when it's too long for one (the key's
    -- badge takes room on the right).
    local title = FS("title", "title", 14, P.ivory, "LEFT")
    local room = W - 2 * PAD - (IsKey(run) and 44 or 0)
    Place(title, PAD, y)
    title:SetWordWrap(false); title:SetMaxLines(1); title:SetSize(0, 0)
    title:SetText(MS:RunTitle(run))
    local lines = (title:GetStringWidth() or 0) > room and 2 or 1
    title:SetWordWrap(lines > 1); title:SetMaxLines(lines)
    title:SetJustifyV("TOP")
    title:SetSize(room, lines * LineH(14))
    if IsKey(run) then
        local badge = FS("badge", "semibold", 13, P.dark, "CENTER")
        badge:SetText("+" .. run.keystoneLevel)
        local bw = _floor(badge:GetStringWidth()) + 12
        local bg = Bar("badgeBg", BADGE, 1, "back")
        PlaceRight(bg, W - PAD, y); bg:SetSize(bw, 18)
        badge:ClearAllPoints(); badge:SetPoint("CENTER", bg, "CENTER", 0, 0)
    end
    y = y - 22 - (lines - 1) * 18
    local lo, hi
    if MS.ForeverLevelRange then lo, hi = MS:ForeverLevelRange(run) end
    if lo then
        local sub = FS("sub", "regular", 12, P.ash, "LEFT")
        Place(sub, PAD, y + 4); sub:SetText(_fmt(L["Levels %d-%d"], lo, hi))
        y = y - 14
    end
    return y
end

local function Affixes(run, y)
    local ids = {}
    for _, a in ipairs(run.affixes or {}) do
        local id = type(a) == "table" and a.id or a                -- a list of ids, or of { id = }
        if type(id) == "number" then _ins(ids, id) end
    end
    local n = 0
    local getInfo = C_ChallengeMode and C_ChallengeMode.GetAffixInfo
    if not getInfo then return y end
    for _, id in ipairs(ids) do
        local ok, name, desc, fileID = pcall(getInfo, id)
        if ok and fileID then
            n = n + 1
            local b = Got("affix" .. n) or Piece("affix" .. n, function()
                local fr = CreateFrame("Frame", nil, f)
                fr:SetSize(18, 18); fr:EnableMouse(true)
                fr.icon = fr:CreateTexture(nil, "ARTWORK"); fr.icon:SetAllPoints()
                fr:SetScript("OnEnter", Safe(function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                    GameTooltip:SetText(self.name or "", 1, 1, 1)
                    if self.desc then GameTooltip:AddLine(self.desc, 0.8, 0.8, 0.8, true) end
                    GameTooltip:Show()
                end))
                fr:SetScript("OnLeave", GameTooltip_Hide)
                return fr
            end)
            b.icon:SetTexture(fileID); b.name, b.desc = MS.Readable(name), MS.Readable(desc)
            Place(b, PAD + (n - 1) * 22, y)
            if n == 4 then break end
        end
    end
    return n > 0 and (y - 24) or y
end

local function ClockRow(run, y, style)
    local now = Clock(run)
    local clock = FS("clock", "semibold", 26, P.ivory, "LEFT")
    Place(clock, PAD, y); clock:SetText(T(now))
    local limit = IsKey(run) and tonumber(run.keystoneTimeLimit)
    if limit and limit > 0 then
        local of = FS("limit", "regular", 13, P.ash, "LEFT")
        of:ClearAllPoints(); of:SetPoint("BOTTOMLEFT", clock, "BOTTOMRIGHT", 5, 3)
        of:SetText("/ " .. T(limit))
        local right = FS("clockR", "semibold", 13, P.ivory, "RIGHT")
        PlaceRight(right, W - PAD, y - 10)
        if style == "detailed" then
            local left = limit - now
            right:SetText(left > 0 and _fmt(L["%s left"], T(left)) or CT(P.bloodHi, L["Behind the timer"]))
        else
            -- The next upgrade still in reach, and how long is left for it.
            local text = CT(P.bloodHi, L["Behind the timer"])
            for _, m in ipairs({ { 3, 0.6, P.gold }, { 2, 0.8, P.silver }, { 1, 1.0, P.bronze } }) do
                local left = limit * m[2] - now
                if left > 0 then text = CT(m[3], _fmt(L["+%d in %s"], m[1], T(left))); break end
            end
            right:SetText(text)
        end
    end
    return y - 32
end

local function UpgradeBar(run, y, style)
    local limit = tonumber(run.keystoneTimeLimit)
    if not (limit and limit > 0) then return y end
    local w = W - 2 * PAD
    local track = Bar("track", TRACK, 1, "back"); Place(track, PAD, y); track:SetSize(w, 8)
    local frac = _min(1, Clock(run) / limit)
    local fill = Bar("fill", FILL); Place(fill, PAD, y); fill:SetSize(_max(1, w * frac), 8)
    local marks = { { 3, 0.6, P.gold }, { 2, 0.8, P.silver }, { 1, 1.0, P.bronze } }
    for _, m in ipairs(marks) do
        local t = Bar("mark" .. m[1], m[3], 1, "mark")
        Place(t, PAD + _min(w - 2, w * m[2] - 1), y + 3); t:SetSize(2, 14)
    end
    y = y - 14
    if style == "detailed" then
        for i, m in ipairs(marks) do
            local fs = FS("left" .. m[1], "medium", 12, P.ivory, "LEFT")
            Place(fs, PAD + (i - 1) * (w / 3), y)
            local left = limit * m[2] - Clock(run)
            fs:SetText(CT(m[3], "+" .. m[1]) .. " " .. (left > 0 and _fmt(L["%s left"], T(left)) or CT(P.ash2, "-")))
        end
    else
        for _, m in ipairs(marks) do
            local fs = FS("tag" .. m[1], "semibold", 11, m[3], "CENTER")
            fs:ClearAllPoints(); fs:SetPoint("TOP", f, "TOPLEFT", PAD + _min(w - 6, w * m[2]), y)
            fs:SetText("+" .. m[1])
        end
    end
    return y - 18
end

-- Bosses, forces and deaths side by side (compact key).
local function KeyStats(run, bosses, y)
    Rule("rule1", y); y = y - 8
    local col = (W - 2 * PAD) / 3
    local done = 0
    for _, b in ipairs(bosses) do if b.done then done = done + 1 end end
    local deaths, cost = DeathCount(run), DeathCost(run) or 0
    local cells = {
        { L["Bosses"], #bosses > 0 and (done .. "/" .. #bosses) or tostring(done) },
        { L["Enemy Forces"], _floor(run.currentPct or 0) .. "%" },
        { L["Deaths"], deaths > 0 and CT(P.bloodHi, deaths .. (cost > 0 and ("  -" .. T(cost)) or "")) or "0" },
    }
    for i, c in ipairs(cells) do
        local lbl = FS("cellL" .. i, "regular", 11, P.ash, "LEFT")
        Place(lbl, PAD + (i - 1) * col, y); lbl:SetText(c[1])
        local val = FS("cellV" .. i, "semibold", 15, P.ivory, "LEFT")
        Place(val, PAD + (i - 1) * col, y - 13); val:SetText(c[2])
    end
    return y - 34
end

-- A long list (Blackrock Depths' 18) cut to MAX_BOSS_ROWS lines (8), in the
-- dungeon's order: the earlier kills folded into one "N killed" line at the
-- top, your two latest kills and the fight you're in kept, then the bosses
-- still to come as far as there's room, "+N more", and the final boss last.
local MAX_BOSS_ROWS = 8
local function Trim(bosses)
    local n = #bosses
    if n <= MAX_BOSS_ROWS then return bosses end
    local keep = { [n] = true }                          -- the final boss
    local kills = {}
    for i, b in ipairs(bosses) do
        if b.fighting then keep[i] = true end
        if b.done and i < n then kills[#kills + 1] = i end
    end
    table.sort(kills, function(a, b) return (bosses[a].kill or 0) > (bosses[b].kill or 0) end)
    for k = 1, _min(2, #kills) do keep[kills[k]] = true end
    local folded = _max(0, #kills - 2)
    local lines = (folded > 0 and 1 or 0)
    for _ in pairs(keep) do lines = lines + 1 end
    local room = MAX_BOSS_ROWS - lines - 1                -- (one line for "+N more")
    local later = 0
    for i, b in ipairs(bosses) do
        if not b.done and not keep[i] then
            if room > 0 then keep[i] = true; room = room - 1 else later = later + 1 end
        end
    end
    -- (What each folded line stands for, for its tooltip: the kills in the
    -- order they fell, the bosses to come in the dungeon's.)
    local foldedList, laterList = {}, {}
    for k = #kills, 3, -1 do _ins(foldedList, bosses[kills[k]]) end
    for i, b in ipairs(bosses) do
        if not keep[i] and not b.done then _ins(laterList, b) end
    end
    local out = {}
    if folded > 0 then _ins(out, { name = _fmt(L["%d killed"], folded), done = true, folded = true, list = foldedList }) end
    for i, b in ipairs(bosses) do
        if i == n and later > 0 then _ins(out, { name = _fmt(L["+%d more"], later), more = true, list = laterList }) end
        if keep[i] then _ins(out, b) end
    end
    return out
end

-- Every boss, with when it died, your best, and the difference (detailed).
local COLS = { kill = 92, best = 50, diff = 0 }    -- right edges, in from the right margin
local function BossRows(run, bosses, y, withBest)
    bosses = Trim(bosses)
    local F = MS.ResultTimeFn(run) or function(t) return t end
    if withBest then
        local h1 = FS("bh1", "regular", 11, P.ash, "RIGHT")
        PlaceRight(h1, W - PAD - COLS.kill, y); h1:SetText(L["Killed"])
        local h2 = FS("bh2", "regular", 11, P.ash, "RIGHT")
        PlaceRight(h2, W - PAD - COLS.best, y); h2:SetText(L["Best"])
        local h3 = FS("bh3", "regular", 11, P.ash, "RIGHT")
        PlaceRight(h3, W - PAD, y); h3:SetText(L["vs best"])
        y = y - 15
    end
    for i, b in ipairs(bosses) do
        local dia = Got("bd" .. i) or Piece("bd" .. i, function() return Art(f, "Diamond", "ARTWORK", 2) end)
        dia:SetSize(10, 10); Place(dia, PAD, y - 2)
        Tint(dia, b.done and P.bronzeHi or P.ash2, b.done and 1 or 0.7)
        dia:SetShown(not b.more)
        -- (The fight you're in is said where its kill time will go, so the
        -- name keeps its size.)
        local killText = b.kill and T(b.kill) or ((b.done and not b.folded) and "-" or "")
        if b.fighting and not b.kill then killText = CT(P.bronzeHi, L["fighting"]) end
        local kill = FS("bk" .. i, "medium", 13, P.ivory, "RIGHT")
        PlaceRight(kill, W - PAD - (withBest and COLS.kill or 0), y)
        kill:SetText(killText)
        local right = withBest and 130 or _max(50, TextWidth(kill) + 8)
        local name = FS("bn" .. i, "medium", 13, (b.done and not b.folded) and P.ivory or P.ash, "LEFT")
        Place(name, PAD + 16, y); OneLine(name, W - 2 * PAD - 16 - right, 13)
        UI.FitText(name, b.name, "game", GameSize(13), 9)
        -- A folded line names what it stands for on hover.
        local hov = Got("bhov" .. i) or Piece("bhov" .. i, function()
            local h = CreateFrame("Frame", nil, f)
            h:EnableMouse(true)
            if h.SetMouseClickEnabled then h:SetMouseClickEnabled(false) end
            h:SetScript("OnEnter", Safe(function(self)
                local row = self.row
                if not (row and row.list and #row.list > 0) then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(row.name, 1, 1, 1)
                for _, x in ipairs(row.list) do
                    if row.folded then
                        GameTooltip:AddDoubleLine(x.name, x.kill and T(x.kill) or "", 0.85, 0.82, 0.75, 1, 1, 1)
                    else
                        GameTooltip:AddLine(x.name, 0.6, 0.57, 0.5)
                    end
                end
                GameTooltip:Show()
            end))
            h:SetScript("OnLeave", GameTooltip_Hide)
            return h
        end)
        hov.row = b
        hov:SetShown(b.list ~= nil)
        Place(hov, PAD, y + 2); hov:SetSize(W - 2 * PAD, 17)
        if withBest then
            local best = FS("bb" .. i, "medium", 13, P.ash, "RIGHT")
            PlaceRight(best, W - PAD - COLS.best, y); best:SetText(b.best and T(b.best) or "")
            local diff = FS("bdf" .. i, "medium", 13, P.ivory, "RIGHT")
            PlaceRight(diff, W - PAD, y)
            if b.kill and b.best then
                local d = F(b.kill) - b.best
                diff:SetText(_abs(d) < 1 and CT(P.ash, "0:00")
                    or d < 0 and CT(P.verdHi, "-" .. T(-d)) or CT(P.bloodHi, "+" .. T(d)))
            else
                diff:SetText("")
            end
        end
        y = y - 17
    end
    return y - 4
end

local function Forces(run, y)
    Rule("rule2", y); y = y - 8
    local lbl = FS("fl", "regular", 11, P.ash, "LEFT"); Place(lbl, PAD, y + 1); lbl:SetText(L["Enemy Forces"])
    local count = FS("fc", "regular", 12, P.ash, "RIGHT"); PlaceRight(count, W - PAD, y)
    count:SetText(run.forcesTotal and _fmt("%d / %d", run.forcesCount or 0, run.forcesTotal) or "")
    local pct = FS("fp", "semibold", 15, P.ivory, "RIGHT")
    PlaceRight(pct, W - PAD - (run.forcesTotal and (count:GetStringWidth() + 8) or 0), y + 2)
    pct:SetText(_fmt("%.2f%%", run.currentPct or 0))
    y = y - 18
    local w = W - 2 * PAD
    local now, last = (run.currentPct or 0) / 100, (run.lastPull or 0) / 100
    local track = Bar("ftrack", TRACK, 1, "back"); Place(track, PAD, y); track:SetSize(w, 6)
    local before = Bar("fbefore", FILL); Place(before, PAD, y); before:SetSize(_max(1, w * _max(0, now - last)), 6)
    if last > 0 then
        local pull = Bar("fpull", P.bronzeHi)
        Place(pull, PAD + w * _max(0, now - last), y); pull:SetSize(_max(1, w * last), 6)
    end
    y = y - 10
    local lp = FS("flp", "regular", 12, P.ash, "LEFT"); Place(lp, PAD, y)
    lp:SetText(run.lastPull and _fmt(L["Last pull %s"], CT(P.bronzeHi, _fmt("+%.2f%%", run.lastPull))) or "")
    local togo = FS("fgo", "regular", 12, P.ash, "RIGHT"); PlaceRight(togo, W - PAD, y)
    togo:SetText((run.currentPct or 0) < 100 and _fmt(L["%s to go"], _fmt("%.2f%%", 100 - (run.currentPct or 0))) or "")
    return y - 18
end

local function Deaths(run, y)
    Rule("rule3", y); y = y - 8
    local lbl = FS("dl", "regular", 11, P.ash, "LEFT"); Place(lbl, PAD, y + 1); lbl:SetText(L["Deaths"])
    local n, cost = DeathCount(run), DeathCost(run) or 0
    local val = FS("dv", "semibold", 13, n > 0 and P.bloodHi or P.ivory, "RIGHT"); PlaceRight(val, W - PAD, y)
    val:SetText(n > 0 and (n .. (IsKey(run) and cost > 0 and ("  -" .. T(cost)) or "")) or "0")
    -- Hovering the line: who died, and how often.
    local hov = Got("dhover") or Piece("dhover", function()
        local h = CreateFrame("Frame", nil, f)
        h:EnableMouse(true)
        if h.SetMouseClickEnabled then h:SetMouseClickEnabled(false) end
        h:SetScript("OnEnter", Safe(function(self)
            local r = self.run
            if not r or DeathCount(r) == 0 then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Deaths"], 1, 1, 1)
            local list = {}
            for _, p in pairs(r.players or {}) do if (p.deaths or 0) > 0 then _ins(list, p) end end
            table.sort(list, function(a, b) return a.deaths > b.deaths end)
            for _, p in ipairs(list) do
                local cr, cg, cb = UI.ClassColor(p.class)
                GameTooltip:AddDoubleLine(UI.DN(p.name), p.deaths, cr, cg, cb, 1, 1, 1)
            end
            GameTooltip:Show()
        end))
        h:SetScript("OnLeave", GameTooltip_Hide)
        return h
    end)
    hov.run = run
    Place(hov, PAD, y + 2); hov:SetSize(W - 2 * PAD, 16)
    return y - 20
end

local function PaceStrip(run, bosses, y)
    local d, boss = Pace(run, bosses)
    if not d then return y end
    local bg = Bar("paceBg", PANEL, 1, "back"); Place(bg, PAD, y); bg:SetSize(W - 2 * PAD, 24)
    local lbl = FS("paceL", "medium", 13, P.ash, "LEFT"); Place(lbl, PAD + 8, y - 5)
    OneLine(lbl, W - 2 * PAD - 110, 13); lbl:SetText(boss)
    local val = FS("paceV", "semibold", 13, P.ivory, "RIGHT"); PlaceRight(val, W - PAD - 8, y - 5)
    val:SetText(_abs(d) < 1 and CT(P.ash, L["level"])
        or d < 0 and CT(P.verdHi, _fmt(L["%s ahead"], T(-d))) or CT(P.bloodHi, _fmt(L["%s behind"], T(d))))
    return y - 30
end

-- Forever: what the run did for you.
-- Hover areas: they show a tooltip but let clicks and drags through to the
-- frame (so it still moves and clicks wherever you grab it).
local function HoverArea(key, onEnter)
    return Got(key) or Piece(key, function()
        local h = CreateFrame("Frame", nil, f)
        h:EnableMouse(true)
        if h.SetMouseClickEnabled then h:SetMouseClickEnabled(false) end
        h:SetScript("OnEnter", Safe(onEnter))
        h:SetScript("OnLeave", GameTooltip_Hide)
        return h
    end)
end

-- The run's XP, split: from the dungeon's mobs and from quests, with each
-- quest's reward. At the mouse.
local function XPTooltip(self)
    local pr = self.run and self.run.progress
    if not pr then return end
    local mobXP, questXP = UI.RunXP(pr)
    local total = mobXP + questXP
    local function Pct(n) return total > 0 and _fmt("  |cff9a9080%d%%|r", _floor(n * 100 / total + 0.5)) or "" end
    local a, b, c = P.ash[1], P.ash[2], P.ash[3]
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(L["Experience"] .. "  " .. MS.FormatThousands(total), 1, 1, 1)
    if questXP > 0 then GameTooltip:AddLine(UI.XPSplit(mobXP, questXP, 200, 6)) end
    GameTooltip:AddDoubleLine(UI.Swatch(P.xpMob, 8, 8) .. " " .. L["From the dungeon"],
        MS.FormatThousands(mobXP) .. Pct(mobXP), a, b, c, 1, 1, 1)
    GameTooltip:AddDoubleLine(UI.Swatch(P.xpQuest, 8, 8) .. " " .. L["From quests"],
        MS.FormatThousands(questXP) .. Pct(questXP), a, b, c, 1, 1, 1)
    local rewards = pr.questRewards or {}
    for i, t in ipairs(pr.quests or {}) do
        local x = rewards[i] and rewards[i].x
        GameTooltip:AddDoubleLine("    " .. t, x and _fmt(L["+%s XP"], MS.FormatThousands(x)) or "",
            0.8, 0.8, 0.8, P.xpQuest[1], P.xpQuest[2], P.xpQuest[3])
    end
    GameTooltip:Show()
end

local function Progress(run, y)
    local pr = run.progress
    if not pr then return y end
    Rule("rule4", y); y = y - 8
    local mobXP, questXP = UI.RunXP(pr)
    local lbl = FS("xl", "regular", 11, P.ash, "LEFT"); Place(lbl, PAD, y + 1); lbl:SetText(L["Experience"])
    local xp = FS("xv", "semibold", 13, P.ivory, "RIGHT"); PlaceRight(xp, W - PAD, y)
    xp:SetText(MS.FormatThousands(mobXP + questXP))
    y = y - 17
    local w = W - 2 * PAD
    local total = mobXP + questXP
    local qw = total > 0 and _floor(w * questXP / total + 0.5) or 0
    local mob = Bar("xmob", P.xpMob); Place(mob, PAD, y); mob:SetSize(_max(1, w - qw), 5)
    if qw > 0 then local q = Bar("xq", P.xpQuest); Place(q, PAD + w - qw, y); q:SetSize(qw, 5) end
    local hov = HoverArea("xhover", XPTooltip)               -- the label, the number and the bar
    hov.run = run
    Place(hov, PAD, y + 20); hov:SetSize(w, 28)
    y = y - 12
    local col = w / 3
    local cells = {
        { L["Mobs killed"], tostring(pr.kills or 0) },
        { L["Deaths"], tostring(DeathCount(run)) },
        { L["Gold looted"], CT(P.bronzeHi, MS.FormatGold(_max(0, pr.gold or 0) + (pr.qg or 0))) },
    }
    for i, c in ipairs(cells) do
        local l = FS("pcl" .. i, "regular", 11, P.ash, "LEFT")
        Place(l, PAD + (i - 1) * col, y); l:SetText(c[1])
        local v = FS("pcv" .. i, "semibold", 14, P.ivory, "LEFT")
        Place(v, PAD + (i - 1) * col, y - 13); v:SetText(c[2])
    end
    return y - 34
end

-- A dungeon run, compact: one row of numbers in place of the boss list and
-- the XP bar.
local function RunCells(run, bosses, y)
    Rule("rule4", y); y = y - 8
    local done = 0
    for _, b in ipairs(bosses) do if b.done then done = done + 1 end end
    local deaths = DeathCount(run)
    local cells = { { L["Bosses"], #bosses > 0 and (done .. "/" .. #bosses) or tostring(done) } }
    local pr = MS.Flavor.progressStats and run.progress
    if pr then
        local mobXP, questXP = UI.RunXP(pr)
        _ins(cells, { L["Experience"], MS.FormatThousands(mobXP + questXP) })
        _ins(cells, { L["Deaths"], deaths > 0 and CT(P.bloodHi, tostring(deaths)) or "0" })
        _ins(cells, { L["Gold looted"], CT(P.bronzeHi, MS.FormatGold(_max(0, pr.gold or 0) + (pr.qg or 0))) })
    else
        _ins(cells, { L["Deaths"], deaths > 0 and CT(P.bloodHi, tostring(deaths)) or "0" })
    end
    -- Each column as wide as its label or number, the space left over shared
    -- out between them (shrunk alike only when even that doesn't fit).
    local inner = W - 2 * PAD
    local labels, values, widths, total = {}, {}, {}, 0
    for i, c in ipairs(cells) do
        local l = FS("rcl" .. i, "regular", 11, P.ash, "LEFT")
        local v = FS("rcv" .. i, "semibold", 14, P.ivory, "LEFT")
        OneLine(l, inner, 10); l:SetText(c[1])
        OneLine(v, inner, 13); v:SetText(c[2])
        local wide = _max(TextWidth(l), TextWidth(v))
        labels[i], values[i], widths[i] = l, v, wide
        total = total + wide
    end
    local n = #cells
    local gap = n > 1 and (inner - total) / (n - 1) or 0
    local scale = 1
    if gap < 6 then
        gap = n > 1 and 6 or 0
        scale = (inner - gap * (n - 1)) / total
    end
    local x = PAD
    for i, c in ipairs(cells) do
        local w = _floor(widths[i] * scale)
        Place(labels[i], x, y); OneLine(labels[i], w + 2, 10)
        Place(values[i], x, y - 13); OneLine(values[i], w + 2, 13)
        if c[1] == L["Experience"] then
            local hov = HoverArea("rchover", XPTooltip)
            hov.run = run
            Place(hov, x, y + 2); hov:SetSize(w, 32)
        end
        x = x + w + gap
    end
    return y - 34
end

-- The instance limit (InstanceLimit.lua), once any are used this hour:
-- "This dungeon this hour  3 of 5" (or, counted all together, "Instances
-- this hour"), a pip for each, when the next frees. The preview shows yours,
-- or a sample (3 of 5) when you've used none.
local function LimitRow(y, run)
    local info = MS.InstanceLimit and MS:InstanceLimit()
    if run._demoElapsed and info and info.used == 0 then
        info = { scope = info.scope, used = math.max(1, info.limit - 2), limit = info.limit,
                 nextFree = time() + 12 * 60, entries = {} }
    end
    if not (info and info.used > 0 and info.nextFree) then return y end
    local full = info.locked or info.used >= info.limit
    Rule("rule9", y); y = y - 8
    local inner = W - 2 * PAD
    local lbl = FS("illbl", "regular", 11, P.ash, "LEFT")
    OneLine(lbl, inner - 70, 10)
    lbl:SetText(info.scope == "all" and L["Instances this hour"] or L["This dungeon this hour"])
    Place(lbl, PAD, y)
    local val = FS("ilval", "semibold", 14, full and P.bloodHi or P.ivory, "RIGHT")
    OneLine(val, 70, 13); val:SetText(_fmt(L["%d of %d"], info.used, info.limit)); PlaceRight(val, W - PAD, y + 2)
    y = y - 18
    local n = _min(info.limit, 30)
    local gap = 3
    local pw = (inner - gap * (n - 1)) / n
    for i = 1, n do
        local pip = Bar("ilpip" .. i, i <= info.used and (full and P.blood or FILL) or TRACK, 1, i <= info.used and "fill" or "back")
        Place(pip, PAD + (i - 1) * (pw + gap), y); pip:SetSize(_max(1, pw), 5)
    end
    y = y - 11
    local nxt = FS("ilnext", "regular", 11, P.ash, "LEFT")
    -- (Short: the line above says which dungeon. Smaller type before it's cut.)
    OneLine(nxt, inner, 10); Place(nxt, PAD, y)
    UI.FitText(nxt, _fmt(L["Next frees at %s (in %s)"], MS.ClockTime(info.nextFree), MS.MinutesFrom(info.nextFree - time())),
        "game", GameSize(11), 8)
    return y - 16
end

-- One line: the essentials.
local function DrawMinimal(run)
    local parts = {}
    if IsKey(run) then
        _ins(parts, CT(BADGE, "+" .. run.keystoneLevel))
        local limit = tonumber(run.keystoneTimeLimit)
        _ins(parts, CT(P.ivory, T(Clock(run))) .. (limit and limit > 0 and CT(P.ash, " / " .. T(limit)) or ""))
    else
        _ins(parts, CT(P.ivory, T(Clock(run))))
    end
    local best = IsKey(run) and (run._demoBest or MS:BestKeyRun(run.dungeonName, run.keystoneLevel))
    local bosses = Bosses(run, best)
    local done = 0
    for _, b in ipairs(bosses) do if b.done then done = done + 1 end end
    _ins(parts, (#bosses > 0 and (done .. "/" .. #bosses) or tostring(done)) .. " " .. CT(P.ash, L["Bosses"]))
    if IsKey(run) then _ins(parts, _floor(run.currentPct or 0) .. "%") end
    local deaths = DeathCount(run)
    local deathText = MS.Plural(deaths, "%d death", "%d deaths")
    _ins(parts, deaths > 0 and CT(P.bloodHi, deathText) or deathText)
    if IsKey(run) then
        local d = Pace(run, bosses)
        if d and _abs(d) >= 1 then _ins(parts, d < 0 and CT(P.verdHi, "-" .. T(-d)) or CT(P.bloodHi, "+" .. T(d))) end
    elseif run.progress and MS.Flavor.progressStats then
        local m, q = UI.RunXP(run.progress)
        _ins(parts, CT(P.xpMob, MS.FormatThousands(m + q) .. " XP"))
    end
    local line = FS("line", "medium", 14, P.ivory, "LEFT")
    -- Centred in the stone between the bronze rule along the top and the
    -- bottom edge: a box that fills that space, the text in its middle (a
    -- box a point taller at the bottom, as most of the line has no
    -- descenders and so sits high in its box).
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -5)
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 0)
    line:SetJustifyV("MIDDLE")
    line:SetText(table.concat(parts, "   "))
    f:SetSize(_floor(line:GetStringWidth()) + 20, 28)
end

local function Draw(run, style)
    wipe(used)
    if style == "minimal" then
        DrawMinimal(run)
    else
        local key = IsKey(run)
        local best = key and (run._demoBest or MS:BestKeyRun(run.dungeonName, run.keystoneLevel))
        local bosses = Bosses(run, best)
        local y = Header(run, -PAD)
        if key and style == "detailed" then y = Affixes(run, y) end
        y = ClockRow(run, y, style)
        if key then
            y = UpgradeBar(run, y, style)
            if style == "detailed" then
                Rule("rule0", y); y = BossRows(run, bosses, y - 8, best ~= nil)
                y = Forces(run, y)
                y = Deaths(run, y)
            else
                y = KeyStats(run, bosses, y)
            end
            y = PaceStrip(run, bosses, y)
        elseif style == "compact" then
            y = RunCells(run, bosses, y)
        else
            if #bosses > 0 then Rule("rule0", y); y = BossRows(run, bosses, y - 8, false) end
            if run.progress and MS.Flavor.progressStats then
                y = Progress(run, y)
            else
                y = Deaths(run, y)
            end
        end
        y = LimitRow(y, run)
        f:SetSize(W, -y + PAD - 6)
    end
    for k, x in pairs(el) do
        if not used[k] then x:Hide() end
    end
end

-- ── The frame ──────────────────────────────────────────────────────────────
local STYLE_NAMES = {
    compact = MS.LK("Compact"), detailed = MS.LK("Detailed"), minimal = MS.LK("Minimal"), off = MS.LK("Off"),
}

local function TimeLeftLine(run)
    local limit = tonumber(run.keystoneTimeLimit)
    if not (IsKey(run) and limit and limit > 0) then return nil end
    return _fmt(L["%s +%d: %s left"], MS:RunTitle(run), run.keystoneLevel, T(limit - Clock(run)))
end

local function PostTimeLeft(run)
    local text = TimeLeftLine(run)
    if not text then return end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or rawget(_G, "SendChatMessage")
    local ok = send and IsInGroup() and pcall(send, text, "PARTY")
    if not ok then MS.Say(L["Couldn't post to party chat here."]) end
end

local previewStyle                     -- the preview's view until you pick one (detailed)
local function ShownStyle()
    local style = MS:GetCompactStyle()
    if demo and previewStyle then return previewStyle end
    if demo and style == "off" then return "detailed" end
    return style
end

local function NextStyle()
    local cur = ShownStyle()
    for i, s in ipairs(MS.COMPACT_STYLES) do
        if s == cur then return MS.COMPACT_STYLES[i % #MS.COMPACT_STYLES + 1] end
    end
    return MS.COMPACT_STYLES[1]
end

local function SavePosition()
    local p, _, rp, x, y = f:GetPoint()
    if p then MS:SetSetting("compactPos", { p, rp, _floor(x + 0.5), _floor(y + 0.5) }) end
end

local function Build()
    f = CreateFrame("Button", "MythicScoreboardCompact", UIParent)
    f:SetSize(W, 120)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    UI.BuildChrome(f, 44)                -- the scoreboard window's stone and bronze
    f:SetScale(MS:GetCompactScale())     -- (its size first: the place is in its own units)
    local pos = MS:GetSetting("compactPos")
    if type(pos) == "table" and pos[1] then
        f:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -220)
    end
    f:SetScript("OnDragStart", Safe(function(self) self:StartMoving(); self._moved = true end))
    f:SetScript("OnDragStop", Safe(function(self) self:StopMovingOrSizing(); SavePosition() end))
    f:SetScript("OnClick", Safe(function(self, button)
        if self._moved then self._moved = nil; return end
        local run = demo or MS.currentRun
        if button == "RightButton" then
            local nextStyle = NextStyle()
            previewStyle = nil                -- (the view picked: the one used from now on)
            MS:SetCompactStyle(nextStyle)
            MS.Say(_fmt(L["In-run frame: %s"], L[STYLE_NAMES[MS:GetCompactStyle()]]))
        elseif IsShiftKeyDown() and run then
            PostTimeLeft(run)
        else
            MS:ShowScoreboard()
        end
    end))

    -- Resized by its corner while the preview's up (not in the way in a run).
    f.ResizeGrip = UI.MakeResizeGrip(f, {
        get = function() return MS:GetCompactScale() end,
        set = function(v) MS:SetCompactScale(v) end,
        min = MS.COMPACT_SCALE_MIN, max = MS.COMPACT_SCALE_MAX,
        posKey = "compactPos", setting = "compactScale",
        shown = function() return demo ~= nil end,
    })

    -- Anything that changes in the run redraws the frame at its next check
    -- (MS:OnChanged, below: a burst of changes in one moment, a pull's kills,
    -- XP and loot, is one redraw, not one each); what moves on its own (the
    -- clock, the timer bar, "frees in 12 min") moves once a second, as the
    -- second turns. The demo runs fast: four times a second.
    local wait, lastSecond = 0, nil
    -- Redrawn when the run's clock ticks over a second (not the computer's
    -- second: the run started part way through one, and redrawing on the
    -- computer's showed the clock skipping a second now and then), and at
    -- least once a second while it stands still (paused, before the pull).
    local lastDraw = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.05
        local now = GetTime()
        local run = MS.inDungeon and MS.currentRun
        local second = run and _floor(Clock(run)) or _floor(now)
        if demo == nil and not changed and second == lastSecond and now - lastDraw < 1 then return end
        if demo ~= nil and now - lastDraw < 0.25 then return end
        lastSecond, lastDraw = second, now
        MS:RefreshCompact()
    end)
end

-- Shows, redraws or hides the frame, from where things stand. It runs every
-- second and from other code (settings, run changes), so nothing in it may
-- throw: an error is said once in chat and the frame carries on.
local function Refresh(self)
    local style = ShownStyle()
    local run = demo or (self.inDungeon and self.currentRun)
    if not run or style == "off" then
        if f then
            f:Hide()
            if f.ResizeGrip then f.ResizeGrip.Update() end
            if f.PreviewBar then f.PreviewBar:Hide() end
        end
        return
    end
    if not f then Build() end
    if run == demo then UI.CompactDemoAt(demo) end
    -- The preview: in front of the scoreboard and its settings, so it can be
    -- seen and moved; in a run, back where it sits.
    local strata = demo and "FULLSCREEN_DIALOG" or "MEDIUM"
    if f:GetFrameStrata() ~= strata then
        f:SetFrameStrata(strata)
        if demo then f:SetFrameLevel(100); f:Raise() end
    end
    f:Show()
    if f.ResizeGrip then f.ResizeGrip.Update() end
    if demo then MS:ShowCompactPreviewBar() elseif f.PreviewBar then f.PreviewBar:Hide() end
    Draw(run, style)
end
function MS:RefreshCompact()
    changed = false
    local ok, err = pcall(Refresh, self)
    if not ok then MS:ReportError("In-run frame", err) end
end

MS._CompactDemo = function() return demo end     -- for tests

-- Under the preview: how to change it, and buttons to put its size back
-- and to finish.
local function SmallButton(parent, label)
    local b = UI.Btn(parent)
    UI.Box(b, true)
    local t = Text(b, "medium", 12, P.ivory, "CENTER")
    t:SetAllPoints(); t:SetText(label)
    b:SetSize(math.ceil(t:GetStringWidth()) + 24, 22)
    return b
end

function MS:ShowCompactPreviewBar()
    if not f then return end
    local bar = f.PreviewBar
    if not bar then
        bar = CreateFrame("Frame", nil, UIParent)
        bar:SetFrameStrata("FULLSCREEN_DIALOG")
        bar:SetSize(300, 64)
        UI.Box(bar)
        bar.hint = Text(bar, "regular", 12, P.ivory, "CENTER")
        bar.hint:SetWordWrap(true)
        bar.hint:SetPoint("TOPLEFT", 10, -8); bar.hint:SetPoint("TOPRIGHT", -10, -8)
        bar.hint:SetText(L["Right-click the frame for another view. Drag it to move it, or its corner to resize it."])
        local reset = SmallButton(bar, L["Reset size"])
        local done = SmallButton(bar, L["Done"])
        reset:SetPoint("BOTTOMRIGHT", bar, "BOTTOM", -4, 8)
        done:SetPoint("BOTTOMLEFT", bar, "BOTTOM", 4, 8)
        reset:SetScript("OnClick", function() MS:SetCompactScale(1) end)
        done:SetScript("OnClick", function() if demo then MS:ToggleCompactPreview() end end)
        bar.reset, bar.done = reset, done
        f.PreviewBar = bar
    end
    bar:ClearAllPoints()
    bar:SetPoint("TOP", f, "BOTTOM", 0, -6)
    bar:Show()
end

-- The preview (the settings' button): the sample run, to move and resize
-- the frame outside a run, in the detailed view until you pick another. On
-- or off; returns whether it's on.
function MS:ToggleCompactPreview()
    if demo then
        demo, previewStyle = nil, nil
        -- (the instance limit's preview goes with it: UI_InstanceLimit.lua)
        if MS.PreviewInstanceLimitPanel then MS:PreviewInstanceLimitPanel(false) end
    else
        local ok, r = pcall(UI.CompactDemoRun)
        if not ok then MS:ReportError("In-run frame", r); return false end
        demo, previewStyle = r, "detailed"
    end
    self:RefreshCompact()
    return demo ~= nil
end
function MS:IsCompactPreviewOn() return demo ~= nil end

-- /sb compact [demo | compact | detailed | minimal | off]
-- (WoW Forever) The dungeon "/sb compact demo <name>" names: the whole name,
-- else the one whose name has it in it ("brd" won't do; "depths" will).
local function DemoDungeon(text)
    local defs = MS.FOREVER_DUNGEONS
    if type(defs) ~= "table" or text == "" then return nil end
    local keys = {}
    for key in pairs(defs) do keys[#keys + 1] = key end
    table.sort(keys)
    local plain = text:gsub("\226\128\153", "'")
    for _, key in ipairs(keys) do if key:lower() == plain then return key end end
    for _, key in ipairs(keys) do if key:lower():find(plain, 1, true) then return key end end
end

function MS:CompactCommand(arg)
    arg = (arg or ""):lower()
    local which = arg:match("^demo%s+(.-)%s*$")
    if which and which ~= "" then
        local key = DemoDungeon(which)
        if not key then
            MS.Say(_fmt(L["No dungeon called %s."], which))
            return
        end
        local ok, r = pcall(UI.CompactDemoRun, key)
        if not ok then MS:ReportError("In-run frame", r); return end
        demo = r
        MS.Say(L["A sample run in the in-run frame. Type /sb compact demo again to hide it."])
    elseif arg == "demo" then
        if demo then
            demo, previewStyle = nil, nil
        else
            local ok, r = pcall(UI.CompactDemoRun)
            if not ok then MS:ReportError("In-run frame", r); return end
            demo = r
            MS.Say(L["A sample run in the in-run frame. Type /sb compact demo again to hide it."])
        end
    elseif STYLE_NAMES[arg] then
        self:SetCompactStyle(arg)
        MS.Say(_fmt(L["In-run frame: %s"], L[STYLE_NAMES[arg]]))
    else
        MS.Say(_fmt(L["In-run frame: %s"], L[STYLE_NAMES[self:GetCompactStyle()]])
            .. "  (/sb compact compact | detailed | minimal | off | demo"
            .. (MS.FOREVER_DUNGEONS and " [dungeon]" or "") .. ")")
    end
    self:RefreshCompact()
end

-- Shown: redrawn at the frame's next check (within 0.05s). Hidden: at once,
-- as the change may be what shows it.
MS:OnChanged(function()
    if f and f:IsShown() then changed = true else MS:RefreshCompact() end
end)
MS:WatchRunState(function(state)
    if state == "active" then demo, previewStyle = nil, nil end      -- a real run takes the frame
    MS:RefreshCompact()
end)
MS:OnSettingChanged("compactStyle", function() MS:RefreshCompact() end)

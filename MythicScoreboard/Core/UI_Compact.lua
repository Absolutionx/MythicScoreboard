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

local _abs, _floor, _max, _min = math.abs, math.floor, math.max, math.min
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
local DemoAt                           -- moves it on (the demo, below)
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
-- Text is in the game's own font (Friz Quadrata, or the client's font for
-- its language), a size smaller than the sizes given: it runs wider than the
-- condensed font they were picked for. With the game's drop shadow, so it
-- stays sharp on any background.
local function GameSize(size) return size >= 20 and size - 2 or size - 1 end
local function FS(key, _, size, col, justify)
    local fs = Piece(key, function()
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
    local t = Piece(key, function() return Solid(f, lay[1], lay[2], 1, 1, 1, 1) end)
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
    if not (C_Scenario and C_Scenario.GetStepInfo and C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo) then return out end
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

local function LastFight(run, name)
    for i = #(run.bosses or {}), 1, -1 do
        local b = run.bosses[i]
        if MS.SameBossName(b.name, name) then return b end
    end
end

-- The bosses to list: { name, kill (the game's timer), done, fighting, best }.
local function Bosses(run, best)
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
            if MS.SameBossName(x.n, n.name) then bt = x.t end
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
            local b = Piece("affix" .. n, function()
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
        local t = Bar("mark" .. m[1], m[3], 1, "mark"); Place(t, PAD + _min(w - 2, w * m[2] - 1), y + 3); t:SetSize(2, 14)
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
        local lbl = FS("cellL" .. i, "regular", 11, P.ash, "LEFT"); Place(lbl, PAD + (i - 1) * col, y); lbl:SetText(c[1])
        local val = FS("cellV" .. i, "semibold", 15, P.ivory, "LEFT"); Place(val, PAD + (i - 1) * col, y - 13); val:SetText(c[2])
    end
    return y - 34
end

-- Every boss, with when it died, your best, and the difference (detailed).
local COLS = { kill = 92, best = 50, diff = 0 }    -- right edges, in from the right margin
local function BossRows(run, bosses, y, withBest)
    local F = MS.ResultTimeFn(run) or function(t) return t end
    if withBest then
        local h1 = FS("bh1", "regular", 11, P.ash, "RIGHT"); PlaceRight(h1, W - PAD - COLS.kill, y); h1:SetText(L["Killed"])
        local h2 = FS("bh2", "regular", 11, P.ash, "RIGHT"); PlaceRight(h2, W - PAD - COLS.best, y); h2:SetText(L["Best"])
        local h3 = FS("bh3", "regular", 11, P.ash, "RIGHT"); PlaceRight(h3, W - PAD, y); h3:SetText(L["vs best"])
        y = y - 15
    end
    for i, b in ipairs(bosses) do
        local dia = Piece("bd" .. i, function() return Art(f, "Diamond", "ARTWORK", 2) end)
        dia:SetSize(10, 10); Place(dia, PAD, y - 2)
        Tint(dia, b.done and P.bronzeHi or P.ash2, b.done and 1 or 0.7)
        local name = FS("bn" .. i, "medium", 13, b.done and P.ivory or P.ash, "LEFT")
        Place(name, PAD + 16, y); OneLine(name, W - 2 * PAD - 16 - (withBest and 130 or 50), 13)
        UI.FitText(name, b.name .. (b.fighting and ("  " .. CT(P.bronzeHi, L["fighting"])) or ""), "game", GameSize(13), 9)
        local kill = FS("bk" .. i, "medium", 13, P.ivory, "RIGHT")
        PlaceRight(kill, W - PAD - (withBest and COLS.kill or 0), y)
        kill:SetText(b.kill and T(b.kill) or (b.done and "-" or ""))
        if withBest then
            local best = FS("bb" .. i, "medium", 13, P.ash, "RIGHT")
            PlaceRight(best, W - PAD - COLS.best, y); best:SetText(b.best and T(b.best) or "")
            local diff = FS("bdf" .. i, "medium", 13, P.ivory, "RIGHT")
            PlaceRight(diff, W - PAD, y)
            if b.kill and b.best then
                local d = F(b.kill) - b.best
                diff:SetText(_abs(d) < 1 and CT(P.ash, "0:00") or d < 0 and CT(P.verdHi, "-" .. T(-d)) or CT(P.bloodHi, "+" .. T(d)))
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
        local pull = Bar("fpull", P.bronzeHi); Place(pull, PAD + w * _max(0, now - last), y); pull:SetSize(_max(1, w * last), 6)
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
    local hov = Piece("dhover", function()
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
    return Piece(key, function()
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
        local l = FS("pcl" .. i, "regular", 11, P.ash, "LEFT"); Place(l, PAD + (i - 1) * col, y); l:SetText(c[1])
        local v = FS("pcv" .. i, "semibold", 14, P.ivory, "LEFT"); Place(v, PAD + (i - 1) * col, y - 13); v:SetText(c[2])
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
    local col = (W - 2 * PAD) / #cells
    for i, c in ipairs(cells) do
        local l = FS("rcl" .. i, "regular", 11, P.ash, "LEFT"); Place(l, PAD + (i - 1) * col, y)
        OneLine(l, col - 4, 10); l:SetText(c[1])
        local v = FS("rcv" .. i, "semibold", 14, P.ivory, "LEFT"); Place(v, PAD + (i - 1) * col, y - 13)
        OneLine(v, col - 4, 13); v:SetText(c[2])
        if c[1] == L["Experience"] then
            local hov = HoverArea("rchover", XPTooltip)
            hov.run = run
            Place(hov, PAD + (i - 1) * col, y + 2); hov:SetSize(col, 32)
        end
    end
    return y - 34
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
    _ins(parts, deaths > 0 and CT(P.bloodHi, MS.Plural(deaths, "%d death", "%d deaths")) or MS.Plural(0, "%d death", "%d deaths"))
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
        f:SetSize(W, -y + PAD - 6)
    end
    for k, x in pairs(el) do
        if not used[k] then x:Hide() end
    end
end

-- ── The frame ──────────────────────────────────────────────────────────────
local STYLE_NAMES = { compact = MS.LK("Compact"), detailed = MS.LK("Detailed"), minimal = MS.LK("Minimal"), off = MS.LK("Off") }

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

local function NextStyle()
    local cur = MS:GetCompactStyle()
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
            MS:SetCompactStyle(NextStyle())
            MS.Say(_fmt(L["In-run frame: %s"], L[STYLE_NAMES[MS:GetCompactStyle()]]))
        elseif IsShiftKeyDown() and run then
            PostTimeLeft(run)
        else
            MS:ShowScoreboard()
        end
    end))

    -- The clock moves on its own: a redraw four times a second while shown.
    local wait = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.25
        MS:RefreshCompact()
    end)
end

-- Shows, redraws or hides the frame, from where things stand. It runs four
-- times a second and from other code (settings, run changes), so nothing in
-- it may throw: an error is said once in chat and the frame carries on.
local function Refresh(self)
    local style = self:GetCompactStyle()
    local run = demo or (self.inDungeon and self.currentRun)
    if demo and style == "off" then style = "compact" end
    if not run or style == "off" then
        if f then f:Hide() end
        return
    end
    if not f then Build() end
    if run == demo then DemoAt(demo) end
    f:Show()
    Draw(run, style)
end
function MS:RefreshCompact()
    local ok, err = pcall(Refresh, self)
    if not ok then MS:ReportError("In-run frame", err) end
end

-- ── The demo ───────────────────────────────────────────────────────────────
-- A made-up run in the frame (/sb compact demo) that plays out at DEMO_SPEED
-- times real time, then starts over: on retail a key (packs pulled one after
-- another, three bosses, four deaths, finished in time), on Forever a run of
-- the Library wing (mobs, two bosses, a quest, a death). Every redraw works
-- the run out afresh from the script for the moment it has reached.
local DEMO_SPEED = 20

local KEY_SCRIPT = {
    limit = 1800, finish = 1440, loop = 1520,
    bosses = { { "Avanoxx", 250, 372 }, { "Anub'zekt", 640, 751 }, { "Ki'katal the Harvester", 980, 1180 } },
    -- packs: from, to, forces (%)
    pulls = { { 40, 110, 8.20 }, { 140, 220, 9.50 }, { 400, 470, 11.10 }, { 500, 600, 10.30 },
              { 800, 880, 12.78 }, { 900, 960, 12.40 }, { 1200, 1260, 13.20 }, { 1280, 1350, 12.00 },
              { 1370, 1440, 10.52 } },
    deaths = { { 300, 2 }, { 540, 3 }, { 700, 2 }, { 1300, 4 } },     -- when, which player (in order)
    best = { dur = 1410, bosses = { { n = "Avanoxx", t = 355 }, { n = "Anub'zekt", t = 790 },
                                    { n = "Ki'katal the Harvester", t = 1300 } } },
    forcesTotal = 308, deathCost = 15,
}
local FOREVER_SCRIPT = {
    finish = 1460, loop = 1540,
    bosses = { { "Houndmaster Loksey", 600, 663 }, { "Arcanist Doan", 1380, 1460 } },
    deaths = { 820 },
    quest = { at = 1000, name = "Compendium of the Fallen", xp = 8450 },
}

-- ── A different dungeon each time ─────────────────────────────────────────
-- The scripts above are the fallback; each loop of the demo picks a dungeon
-- (a key from this season's, a Forever dungeon from its table) and spreads
-- that dungeon's bosses over the same shape of run.
local _rand = math.random

-- A dungeon's bosses from the Encounter Journal, by the dungeon's name.
-- (It changes the journal's selected tier briefly, so not while it's open.)
local function JournalBosses(dungeon)
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex) then return nil end
    if EncounterJournal and EncounterJournal.IsShown and EncounterJournal:IsShown() then return nil end
    local prev = EJ_GetCurrentTier and EJ_GetCurrentTier()
    local out
    pcall(function()
        for tier = EJ_GetNumTiers(), 1, -1 do
            EJ_SelectTier(tier)
            for i = 1, 80 do
                local id, name = EJ_GetInstanceByIndex(i, false)
                if not id then break end
                if name == dungeon then
                    out = {}
                    for e = 1, 20 do
                        local boss = EJ_GetEncounterInfoByIndex(e, id)
                        if not boss then break end
                        out[#out + 1] = boss
                    end
                    return
                end
            end
        end
    end)
    if prev then pcall(EJ_SelectTier, prev) end
    return out and #out > 0 and out or nil
end

-- A key: this season's dungeons in random order, the first the journal knows.
local function RandomKeyScript()
    local CM = C_ChallengeMode
    if not (CM and CM.GetMapTable and CM.GetMapUIInfo) then return nil end
    local ok, maps = pcall(CM.GetMapTable)
    if not ok or type(maps) ~= "table" or #maps == 0 then return nil end
    maps = { unpack(maps) }
    for i = #maps, 2, -1 do local j = _rand(i); maps[i], maps[j] = maps[j], maps[i] end
    for _, mapID in ipairs(maps) do
        local ok2, name, _, limit = pcall(CM.GetMapUIInfo, mapID)
        name, limit = ok2 and MS.Readable(name), ok2 and MS.ReadableNumber(limit)
        local names = name and limit and limit > 600 and JournalBosses(name)
        if names then
            local S = KEY_SCRIPT
            local finish = _floor(limit * 0.8)
            local k, n = finish / S.finish, #names
            local out = { name = name, mapID = mapID, limit = limit, finish = finish, loop = finish + 80,
                          forcesTotal = _rand(25, 45) * 10, deathCost = S.deathCost,
                          bosses = {}, pulls = {}, deaths = {}, best = { dur = finish - 30, bosses = {} } }
            for i, b in ipairs(names) do
                local kill = (i == n) and finish or _floor(finish * i / n - 60)
                out.bosses[i] = { b, kill - _rand(70, 130), kill }
                out.best.bosses[i] = { n = b, t = _max(60, kill + _rand(-50, 40)) }
            end
            for i, pl in ipairs(S.pulls) do out.pulls[i] = { _floor(pl[1] * k), _floor(pl[2] * k), pl[3] } end
            for i, d in ipairs(S.deaths) do out.deaths[i] = { _floor(d[1] * k), d[2] } end
            return out
        end
    end
    return nil
end

-- A Forever dungeon from its table: its required bosses, the final one last.
local function RandomForeverScript()
    local defs = MS.FOREVER_DUNGEONS
    if type(defs) ~= "table" then return nil end
    local keys = {}
    for key, def in pairs(defs) do
        local n = 0
        for _, b in ipairs(def.bosses or {}) do if not (b.rare or b.summon) then n = n + 1 end end
        if n > 0 and n <= 14 then keys[#keys + 1] = key end
    end
    if #keys == 0 then return nil end
    table.sort(keys)                                   -- pairs' order isn't the same each time
    local key = keys[_rand(#keys)]
    local def = defs[key]
    local names = {}
    for _, b in ipairs(def.bosses) do
        if not (b.rare or b.summon) and b.name ~= def.final then names[#names + 1] = b.name end
    end
    if def.final then names[#names + 1] = def.final end
    local n = #names
    local finish = 900 + n * 120 + _rand(0, 300)
    local out = { key = key, finish = finish, loop = finish + 80, bosses = {},
                  deaths = { _floor(finish * (0.3 + _rand() * 0.4)) },
                  quest = { at = _floor(finish * 0.7), name = FOREVER_SCRIPT.quest.name, xp = _rand(40, 120) * 100 } }
    for i, b in ipairs(names) do
        local kill = (i == n) and finish or _floor(finish * i / n - 40)
        out.bosses[i] = { b, kill - _rand(45, 90), kill }
    end
    return out
end

local function DemoPlayers(r)
    local list = {}
    for _, p in pairs(r.players or {}) do _ins(list, p) end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

local function KeyAt(r, t)
    local S = r._script or KEY_SCRIPT
    local now = _min(t, S.finish)
    r._demoElapsed = now
    r.completed = t >= S.finish
    r.inTime = r.completed or nil
    r.bosses, r.activeBoss, r._demoObjectives = {}, nil, {}
    for _, b in ipairs(S.bosses) do
        local done = now >= b[3]
        if now >= b[2] then
            local boss = { name = b[1], pullTime = b[2], killTime = done and b[3] or nil }
            _ins(r.bosses, boss)
            if not done then r.activeBoss = boss end
        end
        _ins(r._demoObjectives, { name = b[1], done = done })
    end
    local pct, last = 0, nil
    for _, p in ipairs(S.pulls) do
        if now >= p[2] then pct, last = pct + p[3], p[3]
        elseif now > p[1] then pct = pct + p[3] * (now - p[1]) / (p[2] - p[1]) end
    end
    r.currentPct = _min(100, _floor(pct * 100 + 0.5) / 100)
    r.forcesTotal = S.forcesTotal
    r.forcesCount = _floor(S.forcesTotal * r.currentPct / 100 + 0.5)
    r.lastPull = last
    local players = DemoPlayers(r)
    for _, p in ipairs(players) do p.deaths, p.deathEvents = 0, {} end
    local n = 0
    for _, d in ipairs(S.deaths) do
        local p = players[d[2]]
        if p and now >= d[1] then
            p.deaths = p.deaths + 1; _ins(p.deathEvents, { time = d[1] }); n = n + 1
        end
    end
    r.deathPenaltySeconds = n * S.deathCost
end

local function ForeverAt(r, t)
    local S = r._script or FOREVER_SCRIPT
    local now = _min(t, S.finish)
    r._demoElapsed = now
    r.bosses, r.activeBoss = {}, nil
    local bossXP = 0
    for _, b in ipairs(S.bosses) do
        if now >= b[2] then
            local boss = { name = b[1], pullTime = b[2], killTime = now >= b[3] and b[3] or nil }
            _ins(r.bosses, boss)
            if boss.killTime then bossXP = bossXP + 640 else r.activeBoss = boss end
        end
    end
    local kills = _max(0, _min(_floor(S.finish / 18), _floor((now - 30) / 18)))
    local pr = r.progress
    pr.kills, pr.xp, pr.gold = kills, kills * 114 + bossXP, kills * 77
    local q = S.quest
    if now >= q.at then
        pr.quests, pr.questRewards, pr.qx = { q.name }, { { x = q.xp } }, q.xp
    else
        pr.quests, pr.questRewards, pr.qx = {}, {}, 0
    end
    local me = DemoPlayers(r)[1]
    if me then
        me.deaths = (now >= S.deaths[1]) and 1 or 0
        me.deathEvents = me.deaths > 0 and { { time = S.deaths[1] } } or {}
    end
end

-- Puts a newly picked dungeon on the demo run (or keeps the fallback).
local function Reroll(r)
    if MS._demoFixed then return end         -- tests: the scripted dungeon
    if MS.Flavor.mythicPlus then
        local S = RandomKeyScript()
        if S then
            r._script = S
            r.dungeonName, r.challengeMapID, r.keystoneTimeLimit = S.name, S.mapID, S.limit
            r.keystoneLevel = _rand(8, 18)
            r._demoBest = S.best
        end
    else
        local S = RandomForeverScript()
        if S then
            r._script = S
            r.dungeonName, r.wingName, r.instanceID, r.uiMapID = S.key, S.key, nil, nil
        end
    end
end

-- The demo run as it stands now: a new dungeon each time round.
function DemoAt(r)
    local S = r._script or (MS.Flavor.mythicPlus and KEY_SCRIPT or FOREVER_SCRIPT)
    local elapsed = (GetTime() - r._demoStart) * DEMO_SPEED
    if elapsed >= S.loop then
        elapsed = elapsed % S.loop
        r._demoStart = GetTime() - elapsed / DEMO_SPEED
        Reroll(r)
    end
    if MS.Flavor.mythicPlus then KeyAt(r, elapsed) else ForeverAt(r, elapsed) end
end

local function DemoRun()
    local r
    if MS.Flavor.mythicPlus then
        r = UI.DemoRun(2)
        r.keyUpgrades, r.duration, r.ratingAfter = nil, nil, nil
        r.keystoneTimeLimit = KEY_SCRIPT.limit
        r._demoBest = KEY_SCRIPT.best
        if C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
            local ok, list = pcall(C_MythicPlus.GetCurrentAffixes)
            if ok and type(list) == "table" then r.affixes = list end
        end
    else
        r = MS.NewRunData()
        r.dungeonName, r.wingName, r.difficultyLabel = "Scarlet Monastery", "Scarlet Monastery: Library", "Normal"
        r.progress = { xp = 0, qx = 0, kills = 0, gold = 0, quests = {}, questRewards = {}, levels = 0, rep = {} }
        local me = MS.NewPlayerStats(MS.ShortName(MS:UnitPlayerName("player") or "You"), select(2, UnitClass("player")) or "WARRIOR", "Demo-1")
        r.players = { [me.name] = me }
    end
    r._demo, r._demoStart = true, GetTime()
    Reroll(r)
    DemoAt(r)
    return r
end

MS._CompactDemo = function() return demo end     -- for tests

-- /sb compact [demo | compact | detailed | minimal | off]
function MS:CompactCommand(arg)
    arg = (arg or ""):lower()
    if arg == "demo" then
        if demo then
            demo = nil
        else
            local ok, r = pcall(DemoRun)
            if not ok then MS:ReportError("In-run frame", r); return end
            demo = r
            MS.Say(L["A sample run in the in-run frame. Type /sb compact demo again to hide it."])
        end
    elseif STYLE_NAMES[arg] then
        self:SetCompactStyle(arg)
        MS.Say(_fmt(L["In-run frame: %s"], L[STYLE_NAMES[arg]]))
    else
        MS.Say(_fmt(L["In-run frame: %s"], L[STYLE_NAMES[self:GetCompactStyle()]]) .. "  (/sb compact compact | detailed | minimal | off | demo)")
    end
    self:RefreshCompact()
end

MS:OnChanged(function() MS:RefreshCompact() end)
MS:WatchRunState(function(state)
    if state == "active" then demo = nil end      -- a real run takes the frame
    MS:RefreshCompact()
end)
MS:OnSettingChanged("compactStyle", function() MS:RefreshCompact() end)

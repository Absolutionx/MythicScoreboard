local MS = _G["MythicScoreboard"]
local L, UI = MS.L, MS.UI
local P, Text, Solid, Outline, VGrad = UI.P, UI.Text, UI.Solid, UI.Outline, UI.VGrad
local moved = {}                         -- frames dragged away from their window
local _fmt, _floor, _max = string.format, math.floor, math.max

-- ── The in-run frame in a raid ─────────────────────────────────────────────
-- What the in-run frame shows in a raid, for now with the sample raids
-- (UI_RaidDemo.lua; opened with the raid scoreboard by /sb raid 10, 20, 40):
--   the raid, its size, the clock, bosses down and wipes;
--   a panel for the moment: the fight going on (boss health, last wipe,
--   who's alive, who died), between pulls (the last kill), or a boss with
--   phases (each phase's time, where the next one starts);
--   the bosses (grouped by path where a raid has paths), or for a raid of
--   one boss its pulls; deaths and gold; the raid's weekly lockout.
-- The clock and the fight's timer count up while it's shown.

local W, PAD = 270, 12
local frames, shown = {}, nil

local function Clock(s)
    s = _floor(s or 0)
    if s >= 3600 then return _fmt("%d:%02d:%02d", _floor(s / 3600), _floor((s % 3600) / 60), s % 60) end
    return _fmt("%d:%02d", _floor(s / 60), s % 60)
end

local cur   -- the raid being built
local function BossName(n, r)
    r = r or cur
    return r and r.bossNames and r.bossNames[n] or _fmt(L["Boss %d"], n)
end

-- ── Pieces, top to bottom (y: the next free line, counting down) ──────────
local function Row(f, y, left, right, lcol, rcol, size)
    local l = Text(f, "medium", size or 12, lcol or P.ash)
    l:SetPoint("TOPLEFT", PAD, y); l:SetText(left)
    local r = Text(f, "medium", size or 12, rcol or P.ivory, "RIGHT")
    r:SetPoint("TOPRIGHT", -PAD, y); r:SetText(right or "")
    return y - (size or 12) - 6, l, r
end

local function Rule(f, y)
    local t = Solid(f, "BORDER", 0, P.line[1], P.line[2], P.line[3], 1)
    t:SetPoint("TOPLEFT", PAD, y); t:SetPoint("TOPRIGHT", -PAD, y); t:SetHeight(1)
    return y - 7
end

local function Diamond(f, col, filled)
    local d = Solid(f, "ARTWORK", 1, col[1], col[2], col[3], filled and 1 or 0.35)
    d:SetSize(7, 7)
    if d.SetRotation then d:SetRotation(math.pi / 4) end
    return d
end

local function Header(f, r)
    local name = Text(f, "semibold", 15, P.ivory)
    name:SetPoint("TOPLEFT", PAD, -PAD); name:SetText(r.name)
    local pill = CreateFrame("Frame", nil, f)
    local pt = Text(pill, "semibold", 11, P.ivory, "CENTER")
    pt:SetPoint("CENTER"); pt:SetText(_fmt(L["%d players"], r.size))
    pill:SetSize(_max(60, (pt:GetStringWidth() or 0) + 12), 17)
    pill:SetPoint("TOPRIGHT", -PAD, -PAD)
    Outline(pill, P.bronze, 1)
    -- The clock, and beside it what's done.
    local fr = r.frame
    f.clock = Text(f, "semibold", 30, P.ivory)
    f.clock:SetPoint("TOPLEFT", PAD, -36)
    local l1 = fr.mode == "phases" and _fmt(L["Pull %d"], fr.pull) or _fmt(L["%d of %d bosses"], fr.killedNow, r.bosses)
    local a = Text(f, "medium", 12, P.ash, "RIGHT"); a:SetPoint("TOPRIGHT", -PAD, -38); a:SetText(l1)
    local b = Text(f, "medium", 12, P.ash, "RIGHT"); b:SetPoint("TOPRIGHT", -PAD, -53)
    b:SetText(MS.Plural(fr.wipes, "%d wipe", "%d wipes"))
    return -76
end

-- The panel: a boxed block for the moment.
local function Panel(f, y, h, active)
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", PAD, y); box:SetPoint("TOPRIGHT", -PAD, y); box:SetHeight(h)
    local bg = box:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetAllPoints(); VGrad(bg, P.btnBot, P.btnTop)
    Outline(box, active and P.bronzeDk or P.line, 1)
    return box
end

local function HealthBar(box, y, pct)
    local track = Solid(box, "ARTWORK", 0, P.stoneBot[1], P.stoneBot[2], P.stoneBot[3], 1)
    track:SetPoint("TOPLEFT", 8, y); track:SetPoint("TOPRIGHT", -8, y); track:SetHeight(8)
    local fill = Solid(box, "ARTWORK", 1, P.blood[1], P.blood[2], P.blood[3], 1)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT"); fill:SetHeight(8)
    fill:SetWidth(_max(1, (W - 2 * PAD - 16) * pct / 100))
    return y - 14
end

local function BoxRow(box, y, left, right, lcol, rcol, lkind)
    local l = Text(box, lkind or "medium", lkind and 13 or 12, lcol or P.ash)
    l:SetPoint("TOPLEFT", 8, y); l:SetText(left)
    local r = Text(box, "medium", 12, rcol or P.ivory, "RIGHT")
    r:SetPoint("TOPRIGHT", -8, y); r:SetText(right or "")
    return y - 18, l, r
end

-- A fight going on: the boss, its pull, its health, who's alive.
local function FightPanel(f, y, r)
    local fr = r.frame
    local box = Panel(f, y, 112, true)
    local yy, _, timer = BoxRow(box, -8, _fmt(L["%s, pull %d"], BossName(fr.fightBoss), fr.fightPull), "",
        P.ivory, P.bronzeHi, "semibold")
    f.fightTimer, f.fightBase = timer, fr.fightTime
    yy = HealthBar(box, yy + 2, fr.health)
    yy = BoxRow(box, yy, _fmt(L["Health %d%%"], fr.health), _fmt(L["Last pull: wipe at %d%%"], fr.lastWipeAt), P.ash, P.ash)
    yy = BoxRow(box, yy, L["Alive"], _fmt(L["%d of %d"], fr.alive, r.size))
    -- Deaths this pull: the latest one, and how many more (hover: all of them).
    local list = fr.pullDeaths or {}
    if #list > 0 then
        local last = list[#list]
        local _, l = BoxRow(box, yy, _fmt(L["%s died at %s"], last[1], last[2]),
            #list > 1 and _fmt(L["+%d more"], #list - 1) or "", P.bloodHi, P.ash)
        local h = CreateFrame("Frame", nil, box)
        h:SetPoint("TOPLEFT", 4, yy + 2); h:SetPoint("TOPRIGHT", -4, yy + 2); h:SetHeight(18)
        h:EnableMouse(true)
        h:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 12, 12)
            GameTooltip:SetText(MS.Plural(#list, "%d death", "%d deaths"), P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
            for i = #list, 1, -1 do
                local e, class = list[i], "UNKNOWN"
                for _, pl in ipairs(r.players) do if pl.name == e[1] then class = pl.class end end
                local cr, cg, cb = UI.ClassColor(class)
                GameTooltip:AddDoubleLine(e[1], e[2], cr, cg, cb, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.pullDeathsRow, f.pullDeathsHover = l, h
    end
    return y - 112 - 10
end

-- Between pulls: who's up, the last kill.
local function RestPanel(f, y, r)
    local fr = r.frame
    local box = Panel(f, y, 48)
    local yy = BoxRow(box, -8, L["Between pulls"], _fmt(L["%d of %d alive"], fr.alive, r.size), P.ivory, P.ivory, "semibold")
    local k = fr.lastKill
    BoxRow(box, yy, _fmt(L["%s down at %s, on pull %d"], BossName(k.boss), k.t, k.pull), "", P.verd)
    return y - 48 - 10
end

-- A boss with phases: the phase, its health, each phase's time.
local function PhasePanel(f, y, r)
    local fr = r.frame
    local box = Panel(f, y, 150, true)
    local yy, _, timer = BoxRow(box, -8, _fmt(L["%s, phase %d"], "Onyxia", fr.phase), "", P.ivory, P.bronzeHi, "semibold")
    f.fightTimer, f.fightBase = timer, fr.fightTime
    yy = HealthBar(box, yy + 2, fr.health)
    yy = BoxRow(box, yy, _fmt(L["Health %d%%"], fr.health), _fmt(L["Phase %d at %d%%"], fr.phase + 1, fr.nextPhaseAt), P.ash, P.ash)
    -- Three tiles, outlined only: done (green, its time), now (bronze), to come (grey).
    local tw = _floor((W - 2 * PAD - 16 - 8) / 3)
    for i = 1, 3 do
        local tile = CreateFrame("Frame", nil, box)
        tile:SetSize(tw, 36); tile:SetPoint("TOPLEFT", 8 + (i - 1) * (tw + 4), yy)
        local now, done = i == fr.phase, i < fr.phase
        local col = done and P.verd or now and P.ivory or P.ash
        Outline(tile, done and P.verd or now and P.bronze or P.line, 1)
        local n = Text(tile, "medium", 11, col); n:SetPoint("TOPLEFT", 6, -4); n:SetText(_fmt(L["Phase %d"], i))
        local t = Text(tile, "semibold", 13, col); t:SetPoint("TOPLEFT", 6, -18)
        if done then t:SetText(Clock(fr.phases[i]))
        elseif now then
            local before = 0
            for j = 1, i - 1 do before = before + (fr.phases[j] or 0) end
            t:SetText(""); f.phaseTimer, f.phaseDone = t, before
        else t:SetText("-") end
    end
    yy = yy - 42
    yy = BoxRow(box, yy, L["Alive"], _fmt(L["%d of %d"], fr.alive, r.size))
    BoxRow(box, yy, L["Deaths this pull"], tostring(fr.pullDeaths), P.ash, P.bloodHi)
    return y - 150 - 10
end

-- One boss line: a diamond, the name, its kill time (or "fighting").
local function BossLine(f, y, e)
    local killed = e.t ~= nil or e.folded
    local col = (killed and P.verd) or (e.fighting and P.ivory) or P.ash
    local d = Diamond(f, killed and P.verd or P.ash, killed)
    d:SetPoint("LEFT", f, "TOPLEFT", PAD + 4, y - 8)
    local name = e.folded and _fmt(L["%d killed"], e.folded) or e.more and _fmt(L["+%d more"], e.more) or BossName(e.boss)
    local l = Text(f, "medium", 13, col); l:SetPoint("LEFT", f, "TOPLEFT", PAD + 14, y - 8); l:SetText(name)
    local r = Text(f, "medium", 13, e.fighting and P.bronzeHi or P.ivory, "RIGHT")
    r:SetPoint("RIGHT", f, "TOPRIGHT", -PAD, y - 8); r:SetText(e.fighting and L["fighting"] or e.t or "")
    if e.more then d:Hide() end
    -- A folded line names what it stands for on hover, as in a dungeon: the
    -- kills with their times, or the bosses still to come.
    if e.list then
        local raid = cur
        local h = CreateFrame("Frame", nil, f)
        h:EnableMouse(true)
        h:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y + 1); h:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y + 1)
        h:SetHeight(18)
        h:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 12, 12)
            GameTooltip:SetText(name, 1, 1, 1)
            for _, x in ipairs(e.list) do
                if e.folded then
                    GameTooltip:AddDoubleLine(BossName(x.boss, raid), x.t or "", 0.85, 0.82, 0.75, 1, 1, 1)
                else
                    GameTooltip:AddLine(BossName(x.boss, raid), 0.6, 0.57, 0.5)
                end
            end
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        e.hover = h
    end
    return y - 19
end

local function SectionTitle(f, y, text, right)
    local t = Text(f, "medium", 11, P.ash); t:SetPoint("TOPLEFT", PAD, y); t:SetText(text)
    if right then
        local r = Text(f, "medium", 11, P.ash, "RIGHT"); r:SetPoint("TOPRIGHT", -PAD, y); r:SetText(right)
    end
    return y - 17
end


local function Build(r)
    cur = r
    local fr = r.frame
    local f = CreateFrame("Frame", "MythicScoreboardRaidRun" .. r.size, UIParent)
    f:SetWidth(W)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); moved[self] = true end)
    UI.BuildChrome(f, 50)

    local y = Header(f, r)
    if fr.mode == "fight" then y = FightPanel(f, y, r)
    elseif fr.mode == "rest" then y = RestPanel(f, y, r)
    else y = PhasePanel(f, y, r) end

    if fr.list then
        y = SectionTitle(f, y, L["Bosses"])
        for _, e in ipairs(fr.list) do y = BossLine(f, y, e) end
    elseif fr.tries then
        y = SectionTitle(f, y, L["Pulls"])
        for _, e in ipairs(fr.tries) do
            local right = e.fighting and L["fighting"] or _fmt(L["Wipe in phase %d at %d%%"], e.phase, e.at)
            y = Row(f, y, _fmt(L["Pull %d"], e.pull), right, P.ivory, e.fighting and P.bronzeHi or P.bloodHi, 13)
        end
    end

    y = Rule(f, y - 4)
    y = Row(f, y, L["Deaths"], tostring(fr.deaths))
    if fr.gold then y = Row(f, y, L["Gold looted"], fr.gold) end
    y = Rule(f, y - 2)
    y = Row(f, y, MS.Plural(fr.resetDays, "Saved to this raid. Resets in %d day.", "Saved to this raid. Resets in %d days."))
    -- A work in progress (as on the raid window): sample raids, not yours.
    y = Row(f, y - 2, "! " .. L["Work in progress"], "", { 1, 0.66, 0.2 }, nil, 13)
    f:SetHeight(-y + PAD - 4)

    -- The clock and the fight's timer count up.
    local start, last = GetTime(), -1
    f:SetScript("OnShow", function() start, last = GetTime(), -1 end)
    f:SetScript("OnUpdate", function()
        local s = _floor(GetTime() - start)
        if s == last then return end
        last = s
        f.clock:SetText(Clock(fr.clock + s))
        if f.fightTimer then f.fightTimer:SetText(Clock(f.fightBase + s)) end
        if f.phaseTimer then f.phaseTimer:SetText(Clock(f.fightBase - f.phaseDone + s)) end
    end)
    f:Hide()
    return f
end

-- Beside the raid scoreboard (its top right), above it, unless dragged away.
function UI.ShowRaidFrame(r, window)
    UI.HideRaidFrame()
    if not frames[r.key] then
        local ok, f = pcall(Build, r)
        if not ok then MS:ReportError("Raid", f); return end
        frames[r.key] = f
    end
    shown = frames[r.key]
    if window and not moved[shown] then
        shown:ClearAllPoints()
        shown:SetPoint("TOPLEFT", window, "TOPRIGHT", 10, 0)
    elseif not shown:GetPoint() then
        shown:SetPoint("TOPLEFT", UIParent, "CENTER", 440, 300)
    end
    if window then shown:SetFrameLevel(window:GetFrameLevel() + 20) end
    shown:Show()
end

-- ── /sb raid live (dev) ────────────────────────────────────────────────────
-- A test of the in-run frame's live parts in a dungeon, while no raid is
-- open: a small frame that follows the real boss fight. On a pull it shows
-- the boss's name and pull number, a timer, and its health from the game
-- (bar and percent); at the end, a kill or a wipe. It also says in chat what
-- the game gave it (plain numbers, hidden ones, or nothing), once a pull.
local liveF, liveOn, livePull, liveStart, liveSaid = nil, false, 0, nil, false
local Secret = MS.IsSecret or function() return false end

local function BossUnit()
    for i = 1, 5 do
        local u = "boss" .. i
        if UnitExists(u) then return u end
    end
    if UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") then return "target" end
end

local function BuildLive()
    local f = CreateFrame("Frame", "MythicScoreboardRaidLive", UIParent)
    f:SetWidth(W); f:SetHeight(150)
    f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetPoint("CENTER", UIParent, "CENTER", 360, 80)
    UI.BuildChrome(f, 50)
    local title = Text(f, "semibold", 15, P.ivory); title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText("Raid frame live test")
    local box = Panel(f, -42, 92, true)
    f.who = Text(box, "semibold", 13, P.ivory); f.who:SetPoint("TOPLEFT", 8, -8)
    f.timer = Text(box, "medium", 12, P.bronzeHi, "RIGHT"); f.timer:SetPoint("TOPRIGHT", -8, -8)
    local track = Solid(box, "ARTWORK", 0, P.stoneBot[1], P.stoneBot[2], P.stoneBot[3], 1)
    track:SetPoint("TOPLEFT", 8, -28); track:SetPoint("TOPRIGHT", -8, -28); track:SetHeight(8)
    -- A status bar: it can show the boss's health even when the game hides
    -- the numbers from addons.
    local bar = CreateFrame("StatusBar", nil, box)
    bar:SetPoint("TOPLEFT", track, "TOPLEFT"); bar:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT")
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(P.blood[1], P.blood[2], P.blood[3], 1)
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    f.bar = bar
    f.pct = Text(box, "medium", 12, P.ash); f.pct:SetPoint("TOPLEFT", 8, -42)
    f.note = Text(box, "medium", 12, P.ash); f.note:SetPoint("TOPLEFT", 8, -60)
    f.who:SetText("Waiting for a boss pull...")
    f.pct:SetText("")
    f.note:SetText("Pull a dungeon boss to test.")
    f:Hide()
    return f
end

local function UpdateLive()
    if not liveF or not liveStart then return end
    liveF.timer:SetText(Clock(GetTime() - liveStart))
    local u = BossUnit()
    if not u then return end
    local G = function(n) return rawget(_G, n) end
    local okC, hp = pcall(G("UnitHealth"), u)
    local okM, max = pcall(G("UnitHealthMax"), u)
    local barOK = okC and okM and pcall(liveF.bar.SetMinMaxValues, liveF.bar, 0, max)
        and pcall(liveF.bar.SetValue, liveF.bar, hp)
    local hidden = okC and Secret(hp)
    local textOK = false
    if okC and okM and not hidden and type(hp) == "number" and type(max) == "number" and max > 0 then
        liveF.pct:SetText(_fmt(L["Health %d%%"], _floor(hp / max * 100 + 0.5))); textOK = true
    elseif G("UnitHealthPercent") then
        local cc = G("CurveConstants")
        local okP, pct = pcall(G("UnitHealthPercent"), u, true, cc and cc.ScaleTo100)
        if okP and pct ~= nil then
            textOK = pcall(liveF.pct.SetFormattedText, liveF.pct, "Health %.0f%%", pct)
        end
    end
    if not textOK then liveF.pct:SetText("Health: hidden by the game") end
    if not liveSaid then
        liveSaid = true
        MS.Say(_fmt("Raid live test, %s: health %s, bar %s, percent %s.",
            (u == "target") and "target" or u,
            not okC and "not readable" or hidden and "hidden (secret)" or "readable",
            barOK and "works" or "failed", textOK and "works" or "failed"))
    end
end

local function LiveEvent(_, event, ...)
    if not liveOn then return end
    if event == "ENCOUNTER_START" then
        local _, name = ...
        livePull = livePull + 1
        liveStart, liveSaid = GetTime(), false
        liveF.who:SetText(_fmt(L["%s, pull %d"], tostring(name), livePull))
        liveF.note:SetText(""); liveF.bar:SetValue(0)
        liveF.bar:SetMinMaxValues(0, 1); liveF.bar:SetValue(1)
    elseif event == "ENCOUNTER_END" then
        local _, name, _, _, success = ...
        if liveStart then liveF.timer:SetText(Clock(GetTime() - liveStart)) end
        liveStart = nil
        liveF.note:SetText(success == 1 and (tostring(name) .. " killed") or "Wipe")
        liveF.note:SetTextColor(success == 1 and P.verd[1] or P.bloodHi[1], success == 1 and P.verd[2] or P.bloodHi[2],
            success == 1 and P.verd[3] or P.bloodHi[3])
    end
end

function UI.RaidLiveTest()
    liveF = liveF or BuildLive()
    liveOn = not liveOn
    if liveOn then
        if not liveF.events then
            liveF.events = CreateFrame("Frame")
            liveF.events:SetScript("OnEvent", LiveEvent)
        end
        liveF.events:RegisterEvent("ENCOUNTER_START"); liveF.events:RegisterEvent("ENCOUNTER_END")
        liveF:SetScript("OnUpdate", function(self, el)
            self.acc = (self.acc or 0) + el
            if self.acc >= 0.2 then self.acc = 0; UpdateLive() end
        end)
        liveF:Show()
        MS.Say("Raid live test on: pull a boss in a dungeon. /sb raid live again turns it off.")
    else
        liveF.events:UnregisterAllEvents()
        liveF:SetScript("OnUpdate", nil)
        liveF:Hide()
        MS.Say("Raid live test off.")
    end
    return liveOn
end
UI._RaidLive = { Frame = function() return liveF end, Event = LiveEvent, Update = UpdateLive }   -- for tests

function UI.HideRaidFrame()
    if shown then shown:Hide(); shown = nil end
end

UI.RaidFrames = frames   -- for tests

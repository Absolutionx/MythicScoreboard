local _abs    = math.abs
local _ceil   = math.ceil
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
local Abbrev, Art, Btn, ClassColor, ClassHex, DN = UI.Abbrev, UI.Art, UI.Btn, UI.ClassColor, UI.ClassHex, UI.DN
local FIGHT_BOT, FIGHT_TOP, FRAME_W, MEDIA, P, PAD_X = UI.FIGHT_BOT, UI.FIGHT_TOP, UI.FRAME_W, UI.MEDIA, UI.P, UI.PAD_X
local Solid, TL_H, Text, Tint, VGrad, WIPE_BOT = UI.Solid, UI.TL_H, UI.Text, UI.Tint, UI.VGrad, UI.WIPE_BOT
local WIPE_TOP = UI.WIPE_TOP

-- Run timeline, part 3: everything marked on it besides the bosses. The tail
-- of the run, the key timer, the completion line, deaths, interrupts, and
-- the live head of a run in progress. Called from BuildTimeline
-- (UI_Timeline.lua) through UI.TL.

local TL_L      = PAD_X
local TL = UI.TL                     -- shared by the timeline's files
local TRACK_Y, TRACK_H = TL.TRACK_Y, TL.TRACK_H
local MED_R, MED_ROWS  = TL.MED_R, TL.MED_ROWS
local DEATH_Y   = TL.DEATH_Y
local INT_BASE  = TL.INT_BASE
local INT_MAXH  = TL.INT_MAXH
local COMPACT_W = TL.COMPACT_W
local SegmentLabelFor = TL.SegmentLabelFor


-- ── Tail of the run ────────────────────────────────────────────────────────
-- Returns the growing segment of a live run, if there is one.
local function DrawTail(c, prevT, liveKind)
    local cv, run, isMPlus, live, Solid, Art = c.cv, c.run, c.isMPlus, c.live, c.Solid, c.Art
    local Tex, Seg, SegButton, InBarText, keyLimit, visualEnd = c.Tex, c.Seg, c.SegButton, c.InBarText, c.keyLimit, c.visualEnd
    local liveSeg
    if visualEnd then
        if visualEnd > prevT then
            Seg(prevT, visualEnd, "trash")
            local tStart = prevT
            local lastPct = (run.bosses and #run.bosses > 0) and run.bosses[#run.bosses].progressPct or 0
            local txt = MS:FormatTime(visualEnd - tStart)
            if isMPlus and run.inTime and (lastPct or 0) < 100 then txt = txt .. "   100%" end
            InBarText(tStart, visualEnd, txt, {0.62, 0.57, 0.50})
            SegButton(tStart, visualEnd, function(self2)
                GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                GameTooltip:SetText(L["Trash"], P.ivory[1], P.ivory[2], P.ivory[3])
                GameTooltip:AddDoubleLine(L["Duration"], MS:FormatTime(visualEnd - tStart), 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:Show()
            end)
        end
        if isMPlus and keyLimit then
            if run.inTime and keyLimit > visualEnd then
                Seg(visualEnd, keyLimit, "spare")
                InBarText(visualEnd, keyLimit, _fmt(L["%s spare"], MS:FormatTime(keyLimit - visualEnd)), P.verdHi)
            elseif not run.inTime and visualEnd > keyLimit then
                Seg(keyLimit, visualEnd, "over")
            end
        end
    elseif live then
        -- Growing segment from the last event to "now": hatched trash, or a
        -- lit bronze bar while a boss is engaged.
        liveSeg = {}
        if liveKind == "fight" then
            local t1 = Tex(cv, "ARTWORK", 2)
            VGrad(t1, FIGHT_BOT, FIGHT_TOP)
            liveSeg[1] = t1
        else
            liveSeg[1] = Solid(cv, "ARTWORK", 0, 0.16, 0.14, 0.12, 1)
            local h = Art(cv, "Hatch", "ARTWORK", 1, true)
            h:SetVertexColor(0.225, 0.195, 0.165, 1)
            liveSeg[2] = h
            local g = Art(cv, "Grit", "ARTWORK", 2, true)
            g:SetBlendMode("MOD")
            liveSeg[3] = g
        end
        for _, tx in ipairs(liveSeg) do tx:SetHeight(TRACK_H); tx:Hide() end
    end
    return liveSeg
end

-- ── Key timer marker (Mythic+ only) ───────────────────────────────────────
local function DrawKeyTimer(c)
    local cv, run, isMPlus, X, At, Solid = c.cv, c.run, c.isMPlus, c.X, c.At, c.Solid
    local Btn, keyLimit = c.Btn, c.keyLimit
    if isMPlus and keyLimit then
        local kx = X(keyLimit)
        local runDur = MS:GetRunDuration(run)
        local inTime = run.completed and run.inTime or (not run.completed and runDur <= keyLimit)
        local kc = inTime and P.ash2 or P.blood
        local kl = Solid(cv, "OVERLAY", 0, kc[1], kc[2], kc[3], 1)
        kl:SetSize(2, TL_H - 30 - TRACK_Y + 6)
        At(kl, "BOTTOMLEFT", _floor(kx) - 1, TRACK_Y - 6)
        local kb = Btn(cv)
        kb:SetSize(12, TL_H - 30 - TRACK_Y + 6)
        At(kb, "BOTTOMLEFT", kx - 6, TRACK_Y - 6)
        kb:SetFrameLevel(cv:GetFrameLevel() + 5)
        kb:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_TOP")
            GameTooltip:SetText(L["Key timer"], P.ivory[1], P.ivory[2], P.ivory[3])
            GameTooltip:AddLine(MS:FormatTime(keyLimit), 1, 1, 1)
            local penalty = run.deathPenaltySeconds or 0
            if penalty > 0 then
                local deaths = 0
                for _, p in pairs(run.players or {}) do deaths = deaths + (p.deaths or 0) end
                GameTooltip:AddLine(_fmt(L["-%s time penalty (%s)"], MS:FormatTime(penalty),
                    MS.Plural(deaths, "%d death", "%d deaths")), P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
            end
            if runDur > 0 then
                local diff = _abs(runDur - keyLimit)
                if inTime then
                    GameTooltip:AddLine(_fmt(L["In time by %s"], MS:FormatTime(diff)), P.verdHi[1], P.verdHi[2], P.verdHi[3])
                else
                    GameTooltip:AddLine(_fmt(L["Over by %s"], MS:FormatTime(diff)), P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
                end
            end
            GameTooltip:Show()
        end)
        kb:SetScript("OnLeave", GameTooltip_Hide)
    end
end

-- ── Upgrade thresholds (Mythic+ only) ──────────────────────────────────────
-- On the time axis, like a ruler: a diamond where the key would go up three
-- levels (60% of the timer), two (80%) and one (the timer), labelled "+3",
-- "+2", "+1" beside it on the axis line. Filled bronze for a threshold the
-- key beat, hollow otherwise.
local NOTCH_Y = 27                   -- the axis ticks' middle
local function DrawThresholds(c)
    local cv, run, X, At, Art, Text, Btn = c.cv, c.run, c.X, c.At, c.Art, c.Text, c.Btn
    if not c.thresholds then return end
    local runDur = MS:GetRunDuration(run)
    local up = MS:RunUpgrades(run) or 0
    local compX = c.endLineL and (c.endLineL + c.endLineW / 2)
    for _, th in ipairs(c.thresholds) do
        local n, t = th[1], th[2]
        local x = X(t)
        local beat = run.completed and up >= n
        local col = beat and P.bronzeHi or P.ash
        local d = Art(cv, beat and "PipFull" or "PipEmpty", "OVERLAY", 3)
        d:SetSize(11, 11); Tint(d, col)
        At(d, "CENTER", x, NOTCH_Y)

        -- The label beside its diamond, on the axis line (the time labels
        -- below keep their row). Right of it, unless the finishing time or
        -- the end of the track is there.
        local lbl = Text(cv, "semibold", 11, col, "LEFT")
        lbl:SetText("+" .. n)
        local right = x + 7 + lbl:GetStringWidth() <= TL_L + c.W
        if compX and compX > x and compX - x < 40 then right = false end
        if right then At(lbl, "LEFT", x + 7, NOTCH_Y)
        else lbl:SetJustifyH("RIGHT"); At(lbl, "RIGHT", x - 7, NOTCH_Y) end

        local b = Btn(cv)
        b:SetSize(18, 30)
        At(b, "BOTTOMLEFT", x - 9, 4)
        b:SetFrameLevel(cv:GetFrameLevel() + 7)
        b:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_TOP")
            GameTooltip:SetText(n == 1 and L["Key timer"] or _fmt(L["+%d timer"], n), P.ivory[1], P.ivory[2], P.ivory[3])
            GameTooltip:AddLine(MS:FormatTime(t), 1, 1, 1)
            if run.completed and runDur > 0 then
                if runDur <= t then
                    GameTooltip:AddLine(_fmt(L["In time by %s"], MS:FormatTime(t - runDur)), P.verdHi[1], P.verdHi[2], P.verdHi[3])
                else
                    GameTooltip:AddLine(_fmt(L["Over by %s"], MS:FormatTime(runDur - t)), P.ash[1], P.ash[2], P.ash[3])
                end
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
    end
end

-- ── Completion marker: a line from the track down to the axis, with ──
-- ── the finishing time printed on the axis itself ────────────────────
local function DrawCompletion(c)
    local cv, run, W, isMPlus, X, At = c.cv, c.run, c.W, c.isMPlus, c.X, c.At
    local Solid, Art, Text, Btn, keyLimit, compSec = c.Solid, c.Art, c.Text, c.Btn, c.keyLimit, c.compSec
    if compSec then
        -- Finished on a boss kill: END_GAP past that boss's block (NewContext).
        local lineL = c.endLineL
        local fx = lineL + c.endLineW / 2               -- the line's middle
        local fc = (isMPlus and not run.inTime) and P.avoid or P.verd

        local line = Solid(cv, "OVERLAY", 1, fc[1], fc[2], fc[3], 1)
        line:SetSize(c.endLineW, TRACK_Y + TRACK_H + 4 - 22)
        At(line, "BOTTOMLEFT", lineL, 22)
        local cap = Art(cv, "Diamond", "OVERLAY", 2)
        cap:SetSize(10, 10); Tint(cap, fc)
        At(cap, "CENTER", fx, TRACK_Y + TRACK_H + 4)
        local glow = Art(cv, "Glow", "BACKGROUND", 6)
        glow:SetBlendMode("ADD"); glow:SetSize(26, 60); Tint(glow, fc, 0.35)
        At(glow, "CENTER", fx, TRACK_Y + TRACK_H / 2)

        local ft = Text(cv, "semibold", 13, fc, "CENTER")
        ft:SetText(MS:FormatTime(compSec))
        local half = ft:GetStringWidth() / 2
        local lx = _max(TL_L + half, _min(TL_L + W - half, fx))
        At(ft, "BOTTOM", lx, 7)

        local fb = Btn(cv)
        fb:SetSize(14, TRACK_Y + TRACK_H + 8 - 4)
        At(fb, "BOTTOMLEFT", fx - 7, 4)
        fb:SetFrameLevel(cv:GetFrameLevel() + 6)
        fb:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_TOP")
            GameTooltip:SetText(L["Run completed"], fc[1], fc[2], fc[3])
            GameTooltip:AddLine(MS:FormatTime(compSec), 1, 1, 1)
            if keyLimit and keyLimit > compSec then
                GameTooltip:AddLine(_fmt(L["Under the timer by %s"], MS:FormatTime(keyLimit - compSec)),
                    P.verdHi[1], P.verdHi[2], P.verdHi[3])
            elseif keyLimit then
                GameTooltip:AddLine(_fmt(L["Over the timer by %s"], MS:FormatTime(compSec - keyLimit)),
                    P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
            end
            GameTooltip:Show()
        end)
        fb:SetScript("OnLeave", GameTooltip_Hide)
    end
end

-- ── Deaths: a red cut through the track and a blood diamond below it.
-- ── The rim takes the class colour; deaths close together merge into
-- ── one diamond with a count.
local function DrawDeaths(c)
    local cv, run, W, X, At, Solid = c.cv, c.run, c.W, c.X, c.At, c.Solid
    local Art, Text, Btn, clampT = c.Art, c.Text, c.Btn, c.clampT
    local allDeaths = {}
    for _, p in pairs(run.players or {}) do
        for _, de in ipairs(p.deathEvents or {}) do
            _ins(allDeaths, { player = p, playerName = DN(p.name), playerClass = p.class,
                              time = clampT and _min(de.time or 0, clampT) or (de.time or 0),
                              rawTime = de.time or 0,
                              spell = de.spell or "Unknown", killer = de.killer or "Unknown",
                              events = de.events })
        end
    end
    _sort(allDeaths, function(a, b) return a.time < b.time end)

    local groups = {}
    for _, d in ipairs(allDeaths) do
        local x = X(d.time)
        local g = groups[#groups]
        if g and x - g.x1 < 14 then
            _ins(g.list, d); g.x2 = x
        else
            _ins(groups, { x1 = x, x2 = x, list = { d } })
        end
    end

    -- The killing blow and the hits before it, copied when the death happened.
    local function AddRecap(d)
        local events = d.events
        local kill = MS.KillingBlow(events)
        if kill then
            local spell = "|cffff9944" .. (kill.spellName or L["Unknown"]) .. "|r"
            local line = "    |cffaaaaaa" .. L["Killing blow:"] .. "|r " .. spell
            if kill.caster and kill.caster ~= "" then
                line = "    |cffaaaaaa" .. L["Killing blow:"] .. "|r "
                    .. _fmt(L["%s |cff888888by|r %s"], spell, "|cffffd700" .. kill.caster .. "|r")
            end
            GameTooltip:AddLine(line, 1, 1, 1)
            for _, ev in ipairs(events) do
                local hit = "      |cff777777" .. (ev.spellName or "?") .. "|r"
                if ev.amount and ev.amount ~= 0 then hit = hit .. "  |cffff6666" .. Abbrev(-(ev.amount)) .. "|r" end
                if ev.overkill and ev.overkill > 0 then hit = hit .. " |cffff0000(" .. L["killing blow"] .. ")|r" end
                GameTooltip:AddLine(hit, 1, 1, 1)
            end
        elseif d.killer ~= "Unknown" then
            local line = "    |cffaaaaaa" .. L["Killed by"] .. "|r |cffff9944" .. d.killer .. "|r"
            if d.spell ~= "Unknown" then line = line .. " |cff888888(" .. d.spell .. ")|r" end
            GameTooltip:AddLine(line, 1, 1, 1)
        end
    end

    local lastMarkX = -_huge
    for _, g in ipairs(groups) do
        -- Cuts through the track at each exact death time.
        for _, d in ipairs(g.list) do
            local cut = Solid(cv, "ARTWORK", 5, P.bloodHi[1], P.bloodHi[2], P.bloodHi[3], 0.95)
            cut:SetSize(2, TRACK_H + 4)
            At(cut, "BOTTOMLEFT", _floor(X(d.time)) - 1, TRACK_Y - 2)
        end
        local mx = _max((g.x1 + g.x2) / 2, lastMarkX + 20)
        mx = _min(mx, TL_L + W + 6)
        lastMarkX = mx

        local stem = Solid(cv, "ARTWORK", 0, P.blood[1], P.blood[2], P.blood[3], 0.7)
        stem:SetSize(1, (TRACK_Y - 2) - (DEATH_Y + 9))
        At(stem, "BOTTOM", _floor(mx) + 0.5, DEATH_Y + 9)

        local single = (#g.list == 1)
        local rimC
        if single then rimC = { ClassColor(g.list[1].playerClass) } else rimC = P.bronzeHi end

        local mk = Btn(cv)
        mk:SetSize(20, 20)
        At(mk, "CENTER", mx, DEATH_Y)
        mk:SetFrameLevel(cv:GetFrameLevel() + 5)
        local shadow = Art(mk, "Diamond", "ARTWORK", 0); shadow:SetSize(22, 22); shadow:SetPoint("CENTER", 0, -1)
        Tint(shadow, {0, 0, 0}, 0.85)
        local rim = Art(mk, "Diamond", "ARTWORK", 1); rim:SetSize(19, 19); rim:SetPoint("CENTER")
        Tint(rim, rimC)
        local fill = Art(mk, "Diamond", "ARTWORK", 2); fill:SetSize(14, 14); fill:SetPoint("CENTER")
        Tint(fill, { 0.62, 0.15, 0.13 })
        if single then
            local sk = Art(mk, "Skull", "OVERLAY", 0); sk:SetSize(9, 9); sk:SetPoint("CENTER", 0, 0)
            Tint(sk, { 1, 0.90, 0.84 })
        else
            local n = Text(mk, "semibold", 11, { 1, 0.92, 0.86 }, "CENTER")
            n:SetPoint("CENTER", 0, 0); n:SetText(#g.list)
        end
        local hl = Art(mk, "Glow", "HIGHLIGHT", 0); hl:SetSize(40, 40); hl:SetPoint("CENTER")
        hl:SetBlendMode("ADD"); Tint(hl, P.bloodHi, 0.6)

        local list = g.list
        mk:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_TOP")
            if #list == 1 then
                local r, gg, b = ClassColor(list[1].playerClass)
                GameTooltip:SetText(_fmt(L["%s died"], list[1].playerName), r, gg, b)
            else
                GameTooltip:SetText(MS.Plural(#list, "%d death", "%d deaths"), P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
            end
            local seg = SegmentLabelFor(run, list[1].rawTime)
            if seg then GameTooltip:AddLine(_fmt(L["During %s"], seg), P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3]) end
            GameTooltip:AddLine(" ")
            for _, d in ipairs(list) do
                GameTooltip:AddDoubleLine("|cff" .. ClassHex(d.playerClass) .. d.playerName .. "|r",
                    MS:FormatTime(d.rawTime), 1, 1, 1, 0.8, 0.8, 0.8)
                AddRecap(d)
            end
            GameTooltip:Show()
        end)
        mk:SetScript("OnLeave", GameTooltip_Hide)
    end
end

-- ── Interrupts: a small bar chart of how many kicks landed in each ──
-- ── stretch of time. (When exact kick times are hidden by the game,
-- ── the addon spaces them evenly, so per-kick ticks implied a
-- ── precision the data doesn't have.)
local function DrawInterrupts(c)
    local cv, run, totalDur, W, X, At = c.cv, c.run, c.totalDur, c.W, c.X, c.At
    local Solid, Btn, clampT = c.Solid, c.Btn, c.clampT
    do
        local BUCKET_PX = 6
        local nb = _ceil(W / BUCKET_PX)
        local buckets = {}
        local peak = 0
        for _, p in pairs(run.players or {}) do
            for _, ie in ipairs(p.interruptEvents or {}) do
                local t = MS.EventTime(ie)
                if clampT then t = _min(t, clampT) end
                local bi = _min(nb, _floor((X(t) - TL_L) / BUCKET_PX) + 1)
                local b = buckets[bi]
                if not b then b = { n = 0, who = {} }; buckets[bi] = b end
                b.n = b.n + 1
                local who = DN(p.name)
                b.who[who] = b.who[who] or { n = 0, class = p.class }
                b.who[who].n = b.who[who].n + 1
                if b.n > peak then peak = b.n end
            end
        end
        if peak > 0 then
            local base = Solid(cv, "ARTWORK", 0, P.line[1], P.line[2], P.line[3], 1)
            base:SetSize(W, 1); At(base, "BOTTOMLEFT", TL_L, INT_BASE - 1)
            for bi, b in pairs(buckets) do
                local x = TL_L + (bi - 1) * BUCKET_PX
                local f = b.n / peak
                local bar = Solid(cv, "ARTWORK", 1, P.kick[1], P.kick[2], P.kick[3], 0.35 + 0.55 * f)
                bar:SetSize(BUCKET_PX - 2, _max(2, _floor(INT_MAXH * f + 0.5)))
                At(bar, "BOTTOMLEFT", x + 1, INT_BASE)

                local hb = Btn(cv)
                hb:SetSize(BUCKET_PX, INT_MAXH + 6)
                At(hb, "BOTTOMLEFT", x, INT_BASE - 3)
                hb:SetFrameLevel(cv:GetFrameLevel() + 4)
                local hl = Solid(hb, "HIGHLIGHT", 0, 1, 1, 1, 0.12); hl:SetAllPoints()
                local t1 = (x - TL_L) / W * totalDur
                local t2 = (x + BUCKET_PX - TL_L) / W * totalDur
                hb:SetScript("OnEnter", function(self2)
                    GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                    GameTooltip:SetText(_fmt(L["Interrupts: %d"], b.n), P.kick[1], P.kick[2], P.kick[3])
                    GameTooltip:AddLine(_fmt(L["%s to %s"], MS:FormatTime(t1), MS:FormatTime(t2)), 0.8, 0.8, 0.8)
                    local seg = SegmentLabelFor(run, (t1 + t2) / 2)
                    if seg then GameTooltip:AddLine(_fmt(L["During %s"], seg), P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3]) end
                    GameTooltip:AddLine(" ")
                    local rows = {}
                    for name, w in pairs(b.who) do _ins(rows, { name = name, n = w.n, class = w.class }) end
                    _sort(rows, function(a, c) return a.n > c.n end)
                    for _, r in ipairs(rows) do
                        GameTooltip:AddDoubleLine("|cff" .. ClassHex(r.class) .. r.name .. "|r", r.n, 1, 1, 1, 1, 1, 1)
                    end
                    GameTooltip:Show()
                end)
                hb:SetScript("OnLeave", GameTooltip_Hide)
            end
        end
    end
end

-- ── Live head (in-progress runs) ───────────────────────────────────────────
local function DrawLiveHead(strip, c, prevT, liveSeg)
    local cv, run, totalDur, W, live, X = c.cv, c.run, c.totalDur, c.W, c.live, c.X
    local Solid, Art, Text = c.Solid, c.Art, c.Text
    if live then
        if strip._liveTag then strip._liveTag:Show() end

        local headGlow = Art(cv, "Glow", "OVERLAY", 3)
        headGlow:SetBlendMode("ADD"); headGlow:SetSize(36, 36)
        Tint(headGlow, P.ivory, 0.8)
        local pulse = headGlow._pulse
        if not pulse then
            pulse = headGlow:CreateAnimationGroup()
            local a1 = pulse:CreateAnimation("Alpha")
            a1:SetFromAlpha(1); a1:SetToAlpha(0.25); a1:SetDuration(0.9); a1:SetSmoothing("IN_OUT")
            pulse:SetLooping("BOUNCE")
            headGlow._pulse = pulse
        end
        pulse:Play()

        local head = Solid(cv, "OVERLAY", 4, P.ivory[1], P.ivory[2], P.ivory[3], 1)
        head:SetSize(2, TRACK_H + 10)

        local headLbl = Text(cv, "semibold", 12, P.ivory, "LEFT")

        strip.UpdateLive = function(lRun, lTotalDur)
            if not lRun or not lTotalDur or lTotalDur <= 0 then return end
            local elapsed = MS:GetRunDuration(lRun)
            if (lRun.keystoneLevel or 0) == 0 and not lRun.completed
                    and elapsed >= lTotalDur - 2 and UI.RebuildTimeline then
                UI.RebuildTimeline(true)        -- rolling window is full: grow it
                return
            end
            local hx = TL_L + _min(1, elapsed / lTotalDur) * W
            if liveSeg then
                local sx = X(prevT)
                for _, tx in ipairs(liveSeg) do
                    if hx - sx >= 1 then
                        tx:ClearAllPoints()
                        tx:SetPoint("BOTTOMLEFT", cv, "BOTTOMLEFT", sx, TRACK_Y)
                        tx:SetWidth(hx - sx); tx:Show()
                    else
                        tx:Hide()
                    end
                end
            end
            head:ClearAllPoints(); head:SetPoint("BOTTOMLEFT", cv, "BOTTOMLEFT", _floor(hx) - 1, TRACK_Y - 5)
            headGlow:ClearAllPoints(); headGlow:SetPoint("CENTER", cv, "BOTTOMLEFT", hx, TRACK_Y + TRACK_H / 2)
            local txt = MS:FormatTime(elapsed)
            if (lRun.keystoneLevel or 0) > 0 then
                txt = txt .. "   " .. _floor(lRun.currentPct or 0) .. "%"
            end
            headLbl:SetText(txt)
            headLbl:ClearAllPoints()
            if hx + 8 + headLbl:GetStringWidth() > TL_L + W then
                headLbl:SetPoint("BOTTOMRIGHT", cv, "BOTTOMLEFT", hx - 8, TRACK_Y + TRACK_H + 3)
            else
                headLbl:SetPoint("BOTTOMLEFT", cv, "BOTTOMLEFT", hx + 8, TRACK_Y + TRACK_H + 3)
            end
        end

        local last = 0
        strip:SetScript("OnUpdate", function()
            local now = GetTime()
            if now - last >= 0.1 then
                last = now
                if strip.UpdateLive then strip.UpdateLive(run, totalDur) end
            end
        end)
    end
end

TL.DrawTail, TL.DrawKeyTimer, TL.DrawCompletion = DrawTail, DrawKeyTimer, DrawCompletion
TL.DrawThresholds = DrawThresholds
TL.DrawDeaths, TL.DrawInterrupts, TL.DrawLiveHead = DrawDeaths, DrawInterrupts, DrawLiveHead

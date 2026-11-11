local _floor  = math.floor
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
local ClassHex, DN = UI.ClassHex, UI.DN
local MEDIA, P = UI.MEDIA, UI.P
local Tint = UI.Tint

-- Run timeline, part 2: the boss fights. Their blocks on the track, the
-- medallions above (labels measured, then placed), and the boss tooltip.
-- Called from BuildTimeline (UI_Timeline.lua) through UI.TL.

local TL = UI.TL                     -- shared by the timeline's files
local TRACK_Y, TRACK_H = TL.TRACK_Y, TL.TRACK_H
local MED_R, MED_ROWS  = TL.MED_R, TL.MED_ROWS
local COMPACT_W = TL.COMPACT_W


local function ShowBossTooltip(owner, boss, run)
    local isWipe = MS.FightLost(boss)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    local tc = isWipe and P.bloodHi or P.bronzeHi
    GameTooltip:SetText((boss.name or L["Boss"]) .. (MS.FightLost(boss) and " " or "") .. MS.FightTag(boss), tc[1], tc[2], tc[3])

    local pullT = boss.pullTime or 0
    local endT  = MS.FightEnd(boss)
    GameTooltip:AddLine(" ")
    if endT then
        GameTooltip:AddDoubleLine(L["Pulled"], MS:FormatTime(pullT), 0.8, 0.8, 0.8, 1, 1, 1)
        local r = MS.FightResult(boss)
        GameTooltip:AddDoubleLine(r == "reset" and L["Reset"] or r == "wipe" and L["Wiped"] or L["Killed"], MS:FormatTime(endT), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Fight length"], MS:FormatTime(endT - pullT), 0.8, 0.8, 0.8, 1, 1, 1)
    else
        GameTooltip:AddDoubleLine(L["Pulled"], MS:FormatTime(pullT), 0.8, 0.8, 0.8, 1, 1, 1)
        endT = MS:GetRunDuration(run)
    end
    if boss.pullProgressPct then
        GameTooltip:AddDoubleLine(L["Enemy forces at pull"], _fmt("%d%%", boss.pullProgressPct),
            0.8, 0.8, 0.8, 1, 1, 1)
    end

    if run and run.players then
        local deaths = {}
        for _, p in pairs(run.players) do
            for _, de in ipairs(p.deathEvents or {}) do
                local t = de.time or 0
                if t >= pullT and t <= endT then
                    _ins(deaths, { name = DN(p.name), class = p.class, time = t, spell = de.spell or "Unknown" })
                end
            end
        end
        _sort(deaths, function(a, b) return a.time < b.time end)
        GameTooltip:AddLine(" ")
        if #deaths == 0 then
            GameTooltip:AddLine(L["No deaths"], P.verdHi[1], P.verdHi[2], P.verdHi[3])
        else
            GameTooltip:AddLine(_fmt(L["Deaths: %d"], #deaths), P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
            for _, d in ipairs(deaths) do
                local line = "  |cff" .. ClassHex(d.class) .. d.name .. "|r  " .. MS:FormatTime(d.time)
                    .. "  |cff999999(" .. _fmt(L["%s into the fight"], MS:FormatTime(d.time - pullT)) .. ")|r"
                if d.spell ~= "Unknown" then line = line .. "  |cffff9944" .. d.spell .. "|r" end
                GameTooltip:AddLine(line, 1, 1, 1)
            end
        end

        local byPlayer, total = {}, 0
        for _, p in pairs(run.players) do
            local cnt = 0
            for _, ie in ipairs(p.interruptEvents or {}) do
                local t = MS.EventTime(ie)
                if t >= pullT and t <= endT then cnt = cnt + 1 end
            end
            if cnt > 0 then
                _ins(byPlayer, { name = DN(p.name), class = p.class, count = cnt })
                total = total + cnt
            end
        end
        if total > 0 then
            _sort(byPlayer, function(a, b) return a.count > b.count end)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(_fmt(L["Interrupts: %d"], total), P.kick[1], P.kick[2], P.kick[3])
            for _, ip in ipairs(byPlayer) do
                GameTooltip:AddLine("  |cff" .. ClassHex(ip.class) .. ip.name .. "|r  " .. ip.count, 1, 1, 1)
            end
        end
    end
    if MS.FightEnd(boss) then
        local shown = UI.focus and UI.focus.boss == boss
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(shown and L["Click to see the whole run again"] or L["Click to see this fight in the table"],
            P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
    end
    GameTooltip:Show()
end

-- ── Segments + medallions ─────────────────────────────────────────────────
-- Returns where the drawn track ends and what is still going on there.
-- ── Medallions: labels measured, then placed ──────────────────────────────
-- Returns which bosses get no medallion of their own (wipes before a later
-- kill) and, for the rest, their labels and placement.
local function PlaceMedallions(c)
    local cv, run, X, Text, clampT = c.cv, c.run, c.X, c.Text, c.clampT
    -- A wipe followed later by a kill of the same boss shows only as its red
    -- segment; the kill's label mentions the wipes. Keeps retries from
    -- crowding the medallion rows.
    local superseded, wipesBefore, pendingWipes = {}, {}, {}
    for i, b in ipairs(run.bosses or {}) do
        local nm = b.name or "Boss"
        if MS.FightLost(b) then
            pendingWipes[nm] = pendingWipes[nm] or {}
            _ins(pendingWipes[nm], i)
        elseif b.killTime and pendingWipes[nm] then
            for _, j in ipairs(pendingWipes[nm]) do superseded[j] = true end
            wipesBefore[i] = #pendingWipes[nm]
            pendingWipes[nm] = nil
        end
    end

    -- ── Medallion placement (before drawing) ─────────────────────────────
    -- Labels are measured first, then placed by priority: the final kill
    -- claims its spot first so the run's last boss never loses its label,
    -- then everything else in time order.
    local medInfo, order = {}, {}
    local lastKillBi, lastKillT = nil, -1
    for bi, boss in ipairs(run.bosses or {}) do
        if not superseded[bi] then
            local pullT = boss.pullTime or 0
            local endT  = MS.FightEnd(boss) or pullT
            if clampT then pullT = _min(pullT, clampT); endT = _min(endT, clampT) end
            local result = MS.FightResult(boss)
            local isWipe = result == "wipe" or result == "reset"
            local name = Text(cv, "game", 13, isWipe and P.bloodHi or P.ivory)
            name:SetText(boss.name or L["Boss"])
            local sub = Text(cv, "regular", 12, P.ash)
            if isWipe then sub:SetText(_fmt(result == "reset" and L["Reset at %s"] or L["Wipe at %s"], MS:FormatTime(endT)))
            elseif result == "kill" then
                local w = wipesBefore[bi]
                sub:SetText(w and _fmt(L["Killed at %s after %s"], MS:FormatTime(endT), MS.Plural(w, "%d wipe", "%d wipes"))
                    or _fmt(L["Killed at %s"], MS:FormatTime(endT)))
            elseif c.live then sub:SetText(L["In combat"])
            else sub:SetText(L["No result"]) end                   -- saved before fights were closed
            medInfo[bi] = { mx = (X(pullT) + X(endT)) / 2, name = name, sub = sub,
                            lblW = _max(name:GetStringWidth(), sub:GetStringWidth()) }
            if boss.killTime and boss.killTime > lastKillT then lastKillBi, lastKillT = bi, boss.killTime end
            _ins(order, bi)
        end
    end
    if lastKillBi then
        for i, bi in ipairs(order) do
            if bi == lastKillBi then _rem(order, i); _ins(order, 1, bi); break end
        end
    end
    -- Where each goes: UI_TimelineLayout.lua.
    for _, bi in ipairs(order) do
        local info = medInfo[bi]
        info.compW = _min(info.name:GetStringWidth(), COMPACT_W)
    end
    local bestPlan = UI.PlaceMedallions(medInfo, order, tostring(run))
    UI._medLayout = {}     -- for tests: what was placed where
    for _, bi in ipairs(order) do
        local p = bestPlan[bi]
        local info = medInfo[bi]
        _ins(UI._medLayout, { name = info.name:GetText(), row = p.row, cx = p.cx, x1 = p.x1, x2 = p.x2, mx = info.mx,
                              bare = p.mode.bare, compact = p.mode.compact, left = p.mode.left, elbow = p.elbow,
                              sub = info.sub:GetText() })
        info.row, info.cx, info.elbow = p.row, p.cx, p.elbow
        info.bare = p.mode.bare
        info.labelLeft = p.mode.left and true or false
        info.compact = p.mode.compact
    end
    return superseded, medInfo
end

-- One boss's medallion: stem, portrait, ring, label, and its handlers.
local function DrawMedallion(c, boss, info, pullT, endT, isWipe)
    local cv, run, X, At, Solid, Art = c.cv, c.run, c.X, c.At, c.Solid, c.Art
    local Tex, Mask, Btn = c.Tex, c.Mask, c.Btn
    local mx    = (X(pullT) + X(endT)) / 2
    local ringC = isWipe and P.blood or P.bronzeHi

    local name, sub = info.name, info.sub
    local row, labelLeft = info.row, info.labelLeft
    local bare = info.bare
    if bare then name:Hide(); sub:Hide() end
    local cy = MED_ROWS[row]

    local cx = info.cx or mx
    local stemC = isWipe and P.blood or P.bronze
    local top = TRACK_Y + TRACK_H
    local function StemPiece(w, h, x, y)
        local t = Solid(cv, "ARTWORK", 0, stemC[1], stemC[2], stemC[3], 0.55)
        t:SetSize(w, h); At(t, "BOTTOMLEFT", x, y)
    end
    if math.abs(cx - mx) < 1 then
        StemPiece(1, cy - MED_R - top, _floor(mx), top)
    else
        -- Moved aside: up from the fight, across, then up to the medallion.
        local elbow = info.elbow or (top + 7)
        StemPiece(1, elbow - top, _floor(mx), top)
        StemPiece(math.abs(_floor(cx) - _floor(mx)) + 1, 1, _min(_floor(mx), _floor(cx)), elbow)
        StemPiece(1, cy - MED_R - elbow, _floor(cx), elbow)
    end

    local med = Btn(cv)
    med:SetSize(MED_R * 2 + 6, MED_R * 2 + 6)
    At(med, "CENTER", cx, cy)
    med:SetFrameLevel(cv:GetFrameLevel() + 4)

    local halo = Art(med, "Glow", "BACKGROUND", 0)
    halo:SetBlendMode("ADD"); halo:SetSize(84, 84); halo:SetPoint("CENTER")
    Tint(halo, ringC, 0)

    local shadow = Art(med, "Disc", "BACKGROUND", 1)
    shadow:SetSize(MED_R * 2 + 6, MED_R * 2 + 6); shadow:SetPoint("CENTER", 0, -1)
    Tint(shadow, {0, 0, 0}, 0.9)

    local portrait = Tex(med, "ARTWORK", 0)
    portrait:SetSize(MED_R * 2 - 4, MED_R * 2 - 4); portrait:SetPoint("CENTER")
    local function Circle()
        local mask = Mask(med)
        mask:SetTexture(MEDIA .. "CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(portrait)
        portrait:AddMaskTexture(mask)
        if isWipe then portrait:SetDesaturated(true); portrait:SetVertexColor(0.9, 0.6, 0.6) end
    end
    local kind, art = MS:BossPortrait(boss, run)       -- Portraits.lua
    local drawn = false
    if kind == "icon" then
        portrait:SetTexture(art)
        portrait:SetTexCoord(0.25, 0.75, 0.0, 1.0)
        Circle(); drawn = true
    elseif kind == "display" and SetPortraitTextureFromCreatureDisplayID then
        drawn = pcall(SetPortraitTextureFromCreatureDisplayID, portrait, art)
        if drawn then Circle() end
    elseif kind == "file" then
        portrait:SetTexture(art)
        portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        Circle(); drawn = true
    end
    if not drawn then
        portrait:SetTexture(MEDIA .. "Crest")
        if isWipe then portrait:SetVertexColor(1, 0.55, 0.5) end
    end

    local ring = Art(med, "Ring", "OVERLAY", 0)
    ring:SetSize(MED_R * 2 + 4, MED_R * 2 + 4); ring:SetPoint("CENTER")
    Tint(ring, ringC)

    name:ClearAllPoints(); sub:ClearAllPoints()
    name:SetParent(med); sub:SetParent(med)
    if info.compact and not bare then
        -- Compact: the name alone, wrapped onto two lines.
        sub:Hide()
        name:SetWidth(COMPACT_W); name:SetWordWrap(true); name:SetMaxLines(2)
        if labelLeft then
            name:SetPoint("RIGHT", med, "LEFT", -5, 0); name:SetJustifyH("RIGHT")
        else
            name:SetPoint("LEFT", med, "RIGHT", 5, 0); name:SetJustifyH("LEFT")
        end
    elseif labelLeft then
        name:SetPoint("BOTTOMRIGHT", med, "LEFT", -5, 1)
        sub:SetPoint("TOPRIGHT", med, "LEFT", -5, -1)
        name:SetJustifyH("RIGHT"); sub:SetJustifyH("RIGHT")
    else
        name:SetPoint("BOTTOMLEFT", med, "RIGHT", 5, 1)
        sub:SetPoint("TOPLEFT", med, "RIGHT", 5, -1)
    end

    local focused = UI.focus and UI.focus.boss == boss
    Tint(halo, ringC, focused and 0.55 or 0)
    med:SetScript("OnEnter", function(self2)
        halo:SetAlpha(1); Tint(halo, ringC, 0.55)
        ShowBossTooltip(self2, boss, run)
    end)
    med:SetScript("OnLeave", function()
        Tint(halo, ringC, focused and 0.55 or 0)
        GameTooltip:Hide()
    end)
    med:SetScript("OnClick", function() UI.FocusBoss(run, boss) end)
end

-- ── Segments + medallions ─────────────────────────────────────────────────
-- Returns where the drawn track ends and what is still going on there.
local function DrawBosses(c)
    local cv, run, live, X, At, Solid = c.cv, c.run, c.live, c.X, c.At, c.Solid
    local Art, Seg, SegButton, InBarText, CountDeaths, clampT = c.Art, c.Seg, c.SegButton, c.InBarText, c.CountDeaths, c.clampT
    local prevT = 0
    local liveKind = "trash"
    local superseded, medInfo = PlaceMedallions(c)

    for bi, boss in ipairs(run.bosses or {}) do
        local pullT  = boss.pullTime or 0
        local isWipe = MS.FightLost(boss)
        local active = MS.FightResult(boss) == "open" and live
        -- An in-progress fight is drawn by UpdateLive so it can grow.
        local endT   = MS.FightEnd(boss) or pullT
        if clampT then
            pullT = _min(pullT, clampT)
            endT  = _min(endT, clampT)
        end

        -- Trash leading up to the pull
        if pullT > prevT then
            Seg(prevT, pullT, "trash")
            local tStart = prevT
            local pct = boss.pullProgressPct
            SegButton(tStart, pullT, function(self2)
                GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                GameTooltip:SetText(L["Trash"], P.ivory[1], P.ivory[2], P.ivory[3])
                GameTooltip:AddDoubleLine(L["Duration"], MS:FormatTime(pullT - tStart), 0.8, 0.8, 0.8, 1, 1, 1)
                if pct then GameTooltip:AddDoubleLine(L["Enemy forces at pull"], _fmt("%d%%", pct), 0.8, 0.8, 0.8, 1, 1, 1) end
                local d = CountDeaths(tStart, pullT)
                if d > 0 then GameTooltip:AddDoubleLine(L["Deaths"], d, 0.8, 0.8, 0.8, P.bloodHi[1], P.bloodHi[2], P.bloodHi[3]) end
                GameTooltip:Show()
            end)
            local trashTxt = MS:FormatTime(pullT - tStart)
            if pct then trashTxt = trashTxt .. "   " .. _floor(pct) .. "%" end
            InBarText(tStart, pullT, trashTxt, {0.62, 0.57, 0.50})
        end

        -- The fight itself, with a soft glow behind kills
        if endT > pullT then
            local mid = (X(pullT) + X(endT)) / 2
            if not isWipe then
                local glow = Art(cv, "Glow", "BACKGROUND", 5)
                glow:SetBlendMode("ADD")
                Tint(glow, P.bronzeHi, 0.45)
                glow:SetSize(X(endT) - X(pullT) + 30, 40)
                At(glow, "CENTER", mid, TRACK_Y + TRACK_H / 2)
            end
            Seg(pullT, endT, isWipe and "wipe" or "fight")
            if not active then
                InBarText(pullT, endT, MS:FormatTime(endT - pullT), isWipe and {1, 0.88, 0.85} or P.dark,
                    isWipe and P.blood or P.bronzeHi)
            end
            local sb = SegButton(pullT, endT, function(self2) ShowBossTooltip(self2, boss, run) end)
            if sb then sb:SetScript("OnClick", function() UI.FocusBoss(run, boss) end) end
            -- The fight shown in the table gets a bright frame.
            if UI.focus and UI.focus.boss == boss then
                local w = _max(2, X(endT) - X(pullT))
                for _, y in ipairs({ TRACK_Y - 3, TRACK_Y + TRACK_H + 1 }) do
                    local edge = Solid(cv, "OVERLAY", 3, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 1)
                    edge:SetSize(w + 4, 2); At(edge, "BOTTOMLEFT", X(pullT) - 2, y)
                end
                for _, x in ipairs({ X(pullT) - 2, X(pullT) + w }) do
                    local edge = Solid(cv, "OVERLAY", 3, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 1)
                    edge:SetSize(2, TRACK_H + 6); At(edge, "BOTTOMLEFT", x, TRACK_Y - 3)
                end
            end
        end

        if not superseded[bi] then DrawMedallion(c, boss, medInfo[bi], pullT, endT, isWipe) end

        if active then
            prevT, liveKind = pullT, "fight"
        else
            prevT = _max(prevT, endT)
        end
    end
    return prevT, liveKind
end

TL.ShowBossTooltip = ShowBossTooltip
TL.DrawBosses = DrawBosses

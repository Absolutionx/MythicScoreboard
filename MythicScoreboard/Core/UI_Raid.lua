local MS = _G["MythicScoreboard"]
local L, UI, LK = MS.L, MS.UI, MS.LK
local P, Text, Solid, Outline, HGrad, Box, Btn, Art = UI.P, UI.Text, UI.Solid, UI.Outline, UI.HGrad, UI.Box, UI.Btn, UI.Art
local _fmt, _floor, _max, _min, _ceil = string.format, math.floor, math.max, math.min, math.ceil

-- ── The raid scoreboard ────────────────────────────────────────────────────
-- A window for raids of 10, 20 and 40 players, shown for now with the sample
-- raids (UI_RaidDemo.lua): /sb raid 10, 20 or 40, and /sb raid to close.
-- The dungeon scoreboard's stone and bronze (UI.BuildChrome), and:
--   Header: the raid, its size, bosses down; time, wipes, deaths, raid DPS.
--   Boss pulls: every pull along the run, a kill or a wipe.
--   Tabs: Overview (everyone, every column; 20 and 40 grouped into tanks,
--   healers and damage; 40 scrolls), then one stat at a time over the raid
--   in groups of five, like raid frames, and the loot.
-- Each sample's window is built the first time it's shown and kept.

local W, PAD = UI.FRAME_W, 22
local HDR_H, PULLS_H, TABS_H, FOOT_H = 86, 132, 44, 36
local VIEW_Y = -(HDR_H + PULLS_H + TABS_H)
local ME = "Brannick Pinecrest"                   -- the sample's "you"
local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local function Clock(s)
    s = _floor(s or 0)
    if s >= 3600 then return _fmt("%d:%02d:%02d", _floor(s / 3600), _floor((s % 3600) / 60), s % 60) end
    return _fmt("%d:%02d", _floor(s / 60), s % 60)
end

local function Rule(parent, y, col, a)
    col = col or P.line
    local t = Solid(parent, "BORDER", 0, col[1], col[2], col[3], a or 1)
    t:SetPoint("TOPLEFT", 2, y); t:SetPoint("TOPRIGHT", -2, y); t:SetHeight(1)
    return t
end

-- A run's totals, and each player's rates over the run's time.
local function Totals(r)
    local t = { taken = 0, damage = 0, healing = 0, deaths = 0, kicks = 0, dispels = 0 }
    for _, p in ipairs(r.players) do
        for k in pairs(t) do t[k] = t[k] + (p[k] or 0) end
        p.dps, p.hps = p.damage / r.time, p.healing / r.time
    end
    t.dps, t.hps = t.damage / r.time, t.healing / r.time
    -- Each player's place in the raid for every stat (for the tooltips).
    for _, key in ipairs({ "dps", "hps", "taken", "deaths", "kicks", "dispels" }) do
        local list = {}
        for i, p in ipairs(r.players) do list[i] = p end
        table.sort(list, function(a, b)
            if (a[key] or 0) ~= (b[key] or 0) then return (a[key] or 0) > (b[key] or 0) end
            return a.name < b.name
        end)
        for i, p in ipairs(list) do p.rank = p.rank or {}; p.rank[key] = (p[key] or 0) > 0 and i or nil end
    end
    return t
end

-- ── Tooltips ───────────────────────────────────────────────────────────────
-- A player: their role and group, every stat with their place in the raid
-- (the tab's stat in bronze), then what it's made of: damage and healing by
-- spell, dispels by type, and each death.
local ROLE_NAME = { TANK = LK("Tank"), HEALER = LK("Healer"), DAMAGER = LK("Damage") }
local DISPEL_NAME = { Magic = LK("Magic"), Curse = LK("Curse"), Poison = LK("Poison"), Disease = LK("Disease") }
local GREY, WHITE = { 0.8, 0.8, 0.8 }, { 1, 1, 1 }
local TIP_STATS = {
    { key = "dps",     label = LK("Damage"),       total = "damage",  rate = LK("DPS") },
    { key = "hps",     label = LK("Healing"),      total = "healing", rate = LK("HPS") },
    { key = "taken",   label = LK("Damage taken"), abbr = true },
    { key = "deaths",  label = LK("Deaths") },
    { key = "kicks",   label = LK("Interrupts") },
    { key = "dispels", label = LK("Dispels") },
}

local function Tip2(left, right, lc, rc)
    lc, rc = lc or GREY, rc or WHITE
    GameTooltip:AddDoubleLine(left, right, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
end

local function TipSection(title, list, total, fmt)
    if not list or #list == 0 then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(title, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
    for _, e in ipairs(list) do fmt(e, total) end
end

function UI.RaidPlayerTooltip(owner, p, r, metric)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local cr, cg, cb = UI.ClassColor(p.class)
    GameTooltip:SetText(p.name, cr, cg, cb)
    Tip2(L[ROLE_NAME[p.role] or "Damage"] .. (p.name == ME and ("  ·  " .. L["You"]) or ""),
        p.group and _fmt(L["Group %d"], p.group) or "", GREY, GREY)
    GameTooltip:AddLine(" ")
    for _, s in ipairs(TIP_STATS) do
        local val = s.total and (p[s.total] or 0) or (p[s.key] or 0)
        local text = s.total and (UI.Abbrev(val) .. "  ·  " .. UI.Abbrev(p[s.key] or 0) .. " " .. L[s.rate])
            or s.abbr and UI.Abbrev(val) or tostring(val)
        local place = p.rank and p.rank[s.key]
        Tip2(L[s.label], (val > 0 and text or "-") .. (place and ("   #" .. place) or ""),
            s.key == metric and P.bronzeHi or GREY, s.key == metric and P.bronzeHi or WHITE)
    end
    local function Amount(e, total)
        Tip2("  " .. e.name, _fmt("%s   %d%%", UI.Abbrev(e.amount), total > 0 and e.amount / total * 100 + 0.5 or 0))
    end
    TipSection(L["Damage by spell"], p.spells, p.damage or 0, Amount)
    TipSection(L["Healing by spell"], p.heals, p.healing or 0, Amount)
    TipSection(L["Dispels by type"], p.dispelTypes, p.dispels or 0, function(e)
        Tip2("  " .. L[DISPEL_NAME[e.name] or e.name], tostring(e.amount))
    end)
    TipSection(L["Deaths"], p.deathLog, 0, function(e)
        Tip2("  " .. L["Killed by"] .. " " .. e.by, Clock(e.t), P.bloodHi, GREY)
    end)
    GameTooltip:Show()
end

-- Hover: the frame's outline (if any) goes bronze, and the tooltip shows.
local function Hover(frame, show, outline, idle)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if outline then outline:SetColor(P.bronzeHi, 1) end
        if self.hoverBg then self.hoverBg:Show() end
        show(self)
    end)
    frame:SetScript("OnLeave", function(self)
        if outline then outline:SetColor(idle and idle(self) or P.line, 1) end
        if self.hoverBg then self.hoverBg:Hide() end
        GameTooltip:Hide()
    end)
end

local function SortBy(list, key)
    table.sort(list, function(a, b)
        if (a[key] or 0) ~= (b[key] or 0) then return (a[key] or 0) > (b[key] or 0) end
        return a.name < b.name
    end)
    return list
end

-- ── A player's row: the dungeon scoreboard's look ──────────────────────────
-- Stripe, a wash of the class colour from the left, its 3px edge, the class
-- icon; yours in bronze. PaintRow colours it for a player.
local function MakeRow(parent, w, h)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(w, h)
    row.stripe = Solid(row, "BACKGROUND", 0, 1, 0.94, 0.86, 0.018); row.stripe:SetAllPoints()
    row.wash = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.wash:SetPoint("TOPLEFT"); row.wash:SetPoint("BOTTOMLEFT"); row.wash:SetWidth(260)
    row.edge = Solid(row, "BORDER", 0, 1, 1, 1, 1)
    row.edge:SetPoint("TOPLEFT"); row.edge:SetPoint("BOTTOMLEFT"); row.edge:SetWidth(3)
    row.selfBg = Solid(row, "BACKGROUND", 2, P.bronze[1], P.bronze[2], P.bronze[3], 0.07); row.selfBg:SetAllPoints()
    row.selfLine = Outline(row, P.bronze, 0.6, "BORDER", 1)
    row.hoverBg = Solid(row, "BACKGROUND", 3, P.bronze[1], P.bronze[2], P.bronze[3], 0.10); row.hoverBg:SetAllPoints()
    row.hoverBg:Hide()
    row.sep = Solid(row, "ARTWORK", 3, P.line[1], P.line[2], P.line[3], 0.55)
    row.sep:SetPoint("BOTTOMLEFT"); row.sep:SetPoint("BOTTOMRIGHT"); row.sep:SetHeight(1)
    row.rank = Text(row, "medium", 12, P.ash, "RIGHT"); row.rank:SetPoint("RIGHT", row, "LEFT", 26, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexture(CLASS_TEX); row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", 34, 0)
    row.name = Text(row, "semibold", 15, P.ivory); row.name:SetPoint("LEFT", 58, 0)
    row.you = Text(row, "semibold", 11, P.bronzeHi); row.you:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    return row
end

local function PaintRow(row, p, idx)
    local cr, cg, cb = UI.ClassColor(p.class)
    local me = p.name == ME
    row.stripe:SetShown(idx % 2 == 0)
    row.selfBg:SetShown(me)
    for i = 1, 4 do row.selfLine[i]:SetShown(me) end
    row.edge:SetColorTexture(cr, cg, cb, 1)
    HGrad(row.wash, { cr, cg, cb }, { cr, cg, cb }, 0.15, 0)
    local cc = UI.CLASS_ICON_COORDS[p.class] or UI.CLASS_ICON_COORDS.UNKNOWN
    row.icon:SetTexCoord(cc[1], cc[2], cc[3], cc[4])
    row.rank:SetText(tostring(idx))
    row.name:SetText(p.name); row.name:SetTextColor(cr, cg, cb)
    row.you:SetText(me and L["You"] or "")
end

-- ── Header ─────────────────────────────────────────────────────────────────
-- Where to comment on the raid views: the links, in a small window you can
-- copy them from (a tooltip can't be copied).
UI.RAID_LINKS = {
    { "CurseForge", "https://www.curseforge.com/wow/addons/mythic-scoreboard" },
    { "GitHub",     "https://github.com/Absolutionx/MythicScoreboard" },
}
local linksF
-- The whole link selected, scrolled back to its start so none of it is cut off.
local function Start(e) if e.SetCursorPosition then e:SetCursorPosition(0) end end
local function Select(e) Start(e); e:HighlightText() end

function UI.ShowRaidLinks(anchor)
    if not linksF then
        local d = CreateFrame("Frame", "MythicScoreboardRaidLinks", UIParent)
        d:SetSize(540, 128)
        d:SetFrameStrata("DIALOG")
        d:EnableMouse(true)
        UI.BuildChrome(d, 30)
        local title = Text(d, "semibold", 14, P.ivory); title:SetPoint("TOPLEFT", 14, -12)
        title:SetText(L["Comments and suggestions"])
        local hint = Text(d, "medium", 12, P.ash, "RIGHT"); hint:SetPoint("TOPRIGHT", -40, -14)
        hint:SetText(L["Click a link, then Ctrl+C."])
        local close = Box(Btn(d), true)
        close:SetSize(20, 20); close:SetPoint("TOPRIGHT", -10, -9)
        local x = Text(close, "semibold", 12, P.ash, "CENTER"); x:SetPoint("CENTER", 0, 1); x:SetText("x")
        close:SetScript("OnClick", function() d:Hide() end)
        d.boxes = {}
        for i, link in ipairs(UI.RAID_LINKS) do
            local y = -40 - (i - 1) * 40
            local lbl = Text(d, "medium", 12, P.ash); lbl:SetPoint("TOPLEFT", 14, y - 8); lbl:SetText(link[1])
            local e = CreateFrame("EditBox", nil, d)
            e:SetSize(430, 26); e:SetPoint("TOPLEFT", 96, y)
            e:SetAutoFocus(false)
            e:SetTextInsets(8, 8, 0, 0)
            UI.SetFont(e, "medium", 12)
            e:SetTextColor(1, 1, 1)
            -- (a soft bronze selection, and the link shown from its start)
            if e.SetHighlightColor then e:SetHighlightColor(P.bronze[1], P.bronze[2], P.bronze[3], 0.45) end
            Box(e)
            e:SetText(link[2])
            -- Read only: whatever's typed, the link stays, ready to copy.
            e:SetScript("OnTextChanged", function(self) if self:GetText() ~= link[2] then self:SetText(link[2]); Select(self) end end)
            e:SetScript("OnEditFocusGained", Select)
            e:SetScript("OnMouseUp", function(self) self:SetFocus(); Select(self) end)
            e:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0); Start(self) end)
            e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); d:Hide() end)
            e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            d.boxes[i] = e
        end
        tinsert(UISpecialFrames, d:GetName())
        linksF = d
    end
    linksF:ClearAllPoints()
    linksF:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    linksF:Show()
    linksF.boxes[1]:SetFocus(); Select(linksF.boxes[1])
    return linksF
end

-- The boss a wipe was on: the next kill after it, if any.
local function NextKill(r, wipe)
    local after = false
    for _, q in ipairs(r.pulls) do
        if q == wipe then after = true
        elseif after and q.kill then return q.name or (q.boss and _fmt(L["Boss %d"], q.boss)) end
    end
end

local function BuildHeader(f, r, t)
    local title = Text(f, "title", 24, P.ivory)
    title:SetPoint("TOPLEFT", PAD, -17); title:SetText(r.name)
    title:SetShadowOffset(0, -2); title:SetShadowColor(0, 0, 0, 1)


    local pill = CreateFrame("Frame", nil, f)
    local pt = Text(pill, "semibold", 12, P.ivory, "CENTER")
    pt:SetPoint("CENTER"); pt:SetText(_fmt(L["%d players"], r.size))
    pill:SetSize(_max(70, (pt:GetStringWidth() or 0) + 16), 20)
    pill:SetPoint("TOPLEFT", PAD, -52)
    Outline(pill, P.bronze, 0.9)

    local sub = Text(f, "medium", 14, P.ash)
    sub:SetPoint("LEFT", pill, "RIGHT", 10, 0)
    sub:SetText(_fmt(L["%d of %d bosses"], r.killed, r.bosses))

    -- A work in progress, said where it can't be missed: an amber tag after
    -- the bosses line, saying these are sample raids; more on hover.
    local AMBER = { 1, 0.66, 0.2 }
    local wip = CreateFrame("Frame", nil, f)
    local bang = Text(wip, "semibold", 14, AMBER, "CENTER")
    bang:SetPoint("LEFT", 9, 0); bang:SetText("!")
    local wt = Text(wip, "semibold", 13, AMBER)
    wt:SetPoint("LEFT", 22, 0); wt:SetText(L["Work in progress"])
    local ws = Text(wip, "medium", 13, P.ivory)
    ws:SetPoint("LEFT", wt, "RIGHT", 8, 0); ws:SetText(L["Showing sample raids, not yours"])
    -- (a fight's line is longer: then the tag alone, so it stays clear of the stats)
    if r.focus then ws:Hide() end
    wip:SetSize(22 + (wt:GetStringWidth() or 0) + (r.focus and 0 or 8 + (ws:GetStringWidth() or 0)) + 12, 22)
    wip:SetPoint("LEFT", sub, "RIGHT", 16, 0)
    Outline(wip, AMBER, 0.9)
    Hover(wip, function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(L["Raids: a preview"], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        GameTooltip:AddLine(L["The raid views are still being built. Until the raids open, they show sample raids, not yours."],
            0.85, 0.82, 0.75, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Things will change. Comments and suggestions are welcome on the addon's CurseForge page or on GitHub:"],
            0.85, 0.82, 0.75, true)
        for _, link in ipairs(UI.RAID_LINKS) do
            GameTooltip:AddLine(link[2], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to copy the links."], 0.6, 0.57, 0.5)
        GameTooltip:Show()
    end)
    wip:SetScript("OnMouseUp", function() GameTooltip:Hide(); UI.ShowRaidLinks(wip) end)
    f.wipNote = wip
    if r.focus then
        -- One fight: which, and how it ended.
        local p = r.pulls[r.focus]
        local who = p.name or NextKill(r, p) or ""
        sub:SetTextColor(P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        sub:SetText(who .. "  ·  " .. (p.kill and (L["Kill"] .. " " .. (p.t or "")) or L["Wipe"]))
    end

    local stats = {
        { L["Time"], Clock(r.time), P.ivory }, { L["Wipes"], tostring(r.wipes), P.bloodHi },
        { L["Deaths"], tostring(t.deaths), P.ivory }, { L["Raid DPS"], UI.Abbrev(t.dps), P.bronzeHi },
    }
    for i = #stats, 1, -1 do
        local x = -(PAD + 46 + (#stats - i) * 112)
        local lbl = Text(f, "medium", 12, P.ash, "RIGHT")
        lbl:SetPoint("TOPRIGHT", x, -20); lbl:SetText(stats[i][1])
        local val = Text(f, "semibold", 24, stats[i][3], "RIGHT")
        val:SetPoint("TOPRIGHT", x, -38); val:SetText(stats[i][2])
    end

    local close = Box(Btn(f), true)
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -12, -14)
    local x = Text(close, "semibold", 14, P.ash, "CENTER")
    x:SetPoint("CENTER", 0, 1); x:SetText("x")
    close:HookScript("OnEnter", function() x:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3]) end)
    close:HookScript("OnLeave", function() x:SetTextColor(P.ash[1], P.ash[2], P.ash[3]) end)
    close:SetScript("OnClick", function() f:Hide() end)
    Rule(f, -HDR_H)
end

-- ── Boss pulls ─────────────────────────────────────────────────────────────


-- A boss's medallion: its portrait (the game draws it from the creature's
-- model, learned from its NPC ID: Portraits.lua) in a bronze ring.
local MEDIA = "Interface\\AddOns\\MythicScoreboard\\Media\\"
local function PaintPortrait(m)
    local tex = m.portrait
    -- Which creature it is, so Portraits.lua can ask the game for its model.
    local db = MythicScoreboardPortraitsDB
    local key = MS.BossKey and MS.BossKey(m.bossName)
    if db and key and m.npc then db.npc = db.npc or {}; db.npc[key] = db.npc[key] or m.npc end
    local kind, art
    if MS.BossPortrait then kind, art = MS:BossPortrait({ name = m.bossName }) end
    local drawn = false
    if kind == "display" and rawget(_G, "SetPortraitTextureFromCreatureDisplayID") then
        drawn = pcall(SetPortraitTextureFromCreatureDisplayID, tex, art)
    elseif kind == "icon" or kind == "file" then
        tex:SetTexture(art); drawn = true
    end
    if drawn then
        tex:SetTexCoord(0, 1, 0, 1)
        if not m.mask and tex.AddMaskTexture then
            m.mask = m:CreateMaskTexture()
            m.mask:SetTexture(MEDIA .. "CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m.mask:SetAllPoints(tex)
            tex:AddMaskTexture(m.mask)
        end
    else
        tex:SetTexture(MEDIA .. "Crest")
    end
    m.drawn = drawn
end
local medallions = {}
MS:OnChanged(function(what)
    if what ~= "portraits" then return end
    for _, m in ipairs(medallions) do if not m.drawn then PaintPortrait(m) end end
end)

local MED_R = 14
local function NpcOf(r, name)
    for _, e in ipairs((UI.RAID_ENCOUNTERS or {})[r.key] or {}) do if e.name == name then return e.npc end end
end
local function Medallion(f, name, npc, cx, cy)
    local m = CreateFrame("Frame", nil, f)
    m:SetSize(MED_R * 2 + 6, MED_R * 2 + 6); m:SetPoint("CENTER", f, "TOPLEFT", cx, cy)
    m:SetFrameLevel(f:GetFrameLevel() + 4)
    local shadow = Art(m, "Disc", "BACKGROUND", 1)
    shadow:SetSize(MED_R * 2 + 6, MED_R * 2 + 6); shadow:SetPoint("CENTER", 0, -1)
    shadow:SetVertexColor(0, 0, 0, 0.9)
    m.portrait = m:CreateTexture(nil, "ARTWORK")
    m.portrait:SetSize(MED_R * 2 - 4, MED_R * 2 - 4); m.portrait:SetPoint("CENTER")
    local ring = Art(m, "Ring", "OVERLAY", 0)
    ring:SetSize(MED_R * 2 + 4, MED_R * 2 + 4); ring:SetPoint("CENTER")
    ring:SetVertexColor(P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 1)
    m.bossName, m.npc = name, npc
    PaintPortrait(m)
    medallions[#medallions + 1] = m
    return m
end

-- Deaths along the run, in clusters (those close together share a mark).
local function DeathMarks(r)
    local all = {}
    for _, p in ipairs(r.players) do
        for _, d in ipairs(p.deathLog or {}) do all[#all + 1] = { t = d.t, by = d.by, p = p } end
    end
    table.sort(all, function(a, b) return a.t < b.t end)
    local marks = {}
    for _, d in ipairs(all) do
        local m = marks[#marks]
        if m and d.t - m.last <= (r.runTime or r.time) / 60 then
            m.list[#m.list + 1] = d; m.last = d.t
        else
            marks[#marks + 1] = { list = { d }, first = d.t, last = d.t }
        end
    end
    return marks
end

local function BuildPulls(f, r)
    local RT = r.runTime or r.time          -- (a fight's window shows the whole run)
    local y0 = -HDR_H
    local lbl = Text(f, "medium", 12, P.ash)
    lbl:SetPoint("TOPLEFT", PAD, y0 - 12); lbl:SetText(L["Boss pulls"])
    -- The key, after the title: kill, wipe, death.
    local x = PAD + (lbl:GetStringWidth() or 60) + 18
    for _, k in ipairs({ { P.bronzeHi, L["Kill"], P.ivory }, { P.blood, L["Wipe"], P.bloodHi }, { P.blood, L["Deaths"], P.bloodHi, true } }) do
        if k[4] then
            local ring = Art(f, "Ring", "OVERLAY", 0); ring:SetSize(11, 11)
            ring:SetPoint("CENTER", f, "TOPLEFT", x + 5, y0 - 18); ring:SetVertexColor(k[1][1], k[1][2], k[1][3], 1)
        else
            local bar = Solid(f, "ARTWORK", 0, k[1][1], k[1][2], k[1][3], 1)
            bar:SetPoint("LEFT", f, "TOPLEFT", x, y0 - 18); bar:SetSize(12, 4)
        end
        local t = Text(f, "medium", 12, k[3]); t:SetPoint("LEFT", f, "TOPLEFT", x + 16, y0 - 18); t:SetText(k[2])
        x = x + 16 + (t:GetStringWidth() or 30) + 16
    end

    -- A compact timeline: one thin line for the run, each fight on it (bronze
    -- for a kill, red for a wipe); each kill's boss sitting on the line at
    -- the moment it died, with the time beside it; the minutes under the
    -- line; who died, and when, below that; and the run's end time at the
    -- right. Everything says more on hover.
    local LINE_Y, LH = y0 - 70, 8
    local TICK_Y = LINE_Y - LH
    local AXIS_Y = TICK_Y - 8
    local DEATH_Y = AXIS_Y - 25
    local span = W - 2 * PAD
    local endX = PAD + span
    local function X(t) return PAD + _floor(span * _min(1, _max(0, t / RT)) + 0.5) end

    -- The line: hatched between pulls (the time spent on trash), with grit,
    -- as on the dungeon timeline.
    local line = Solid(f, "ARTWORK", 0, 0.16, 0.14, 0.12, 1)
    line:SetPoint("TOPLEFT", PAD, LINE_Y); line:SetSize(span, LH)
    local hatch = Art(f, "Hatch", "ARTWORK", 1, true)
    hatch:SetVertexColor(0.30, 0.26, 0.21, 1)
    hatch:SetPoint("TOPLEFT", PAD, LINE_Y); hatch:SetSize(span, LH)
    f.trashHatch = hatch
    local grit = Art(f, "Grit", "ARTWORK", 3, true)
    grit:SetBlendMode("MOD"); grit:SetPoint("TOPLEFT", PAD, LINE_Y); grit:SetSize(span, LH)
    for _, p in ipairs(r.pulls) do
        if p.s and p.e then
            local x1, x2 = X(p.s), X(p.e)
            local seg = f:CreateTexture(nil, "ARTWORK", nil, 2)
            seg:SetPoint("TOPLEFT", x1, LINE_Y); seg:SetSize(_max(2, x2 - x1), LH)
            if p.kill then UI.VGrad(seg, UI.FIGHT_BOT, UI.FIGHT_TOP) else UI.VGrad(seg, UI.WIPE_BOT, UI.WIPE_TOP) end
        end
    end
    local shine = f:CreateTexture(nil, "ARTWORK", nil, 4)
    shine:SetPoint("TOPLEFT", PAD, LINE_Y); shine:SetSize(span, 1)
    HGrad(shine, P.bronze, P.bronzeHi, 0.2, 0.6)

    -- The minutes: a tick through the line and the time under it.
    -- The end of the run: a gold tick and its time, at the right.
    local endTick = Solid(f, "OVERLAY", 2, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 1)
    endTick:SetPoint("TOPLEFT", endX - 2, LINE_Y + 5); endTick:SetSize(2, LH + 10)
    local endT = Text(f, "semibold", 13, P.bronzeHi, "RIGHT")
    endT:SetPoint("TOPRIGHT", f, "TOPLEFT", endX, AXIS_Y - 1); endT:SetText(Clock(RT))
    f.pullsEnd = endT
    local endLeft = endX - (endT:GetStringWidth() or 40)

    -- The minutes: a faint bronze tick under the line and the time beside
    -- it; none that would run into the end time.
    local step = UI._TickStep and UI._TickStep(RT, span) or 600
    f.axis = {}
    for t = 0, RT, step do
        local ax = X(t)
        local a = Text(f, "medium", 11, P.ash, "LEFT")
        a:SetText(Clock(t))
        if ax + 3 + (a:GetStringWidth() or 30) + 12 <= endLeft then
            local tick = Solid(f, "ARTWORK", 2, P.bronze[1], P.bronze[2], P.bronze[3], 0.6)
            tick:SetPoint("TOPLEFT", ax, LINE_Y - LH); tick:SetSize(1, 6)
            a:SetPoint("TOPLEFT", f, "TOPLEFT", ax + 3, AXIS_Y)
            f.axis[#f.axis + 1] = a
        else
            a:Hide()
        end
    end

    -- A kill's time, beside its boss.
    local function Badge(bx, by, text, col)
        local t = Text(f, "semibold", 12, col, "LEFT")
        t:SetText(text)
        t:SetPoint("BOTTOMLEFT", f, "TOPLEFT", bx, by + 2)
        return t, (t:GetStringWidth() or 30) + 2
    end

    local function PullTip(self, p)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 12, 12)
        local c = p.kill and P.verd or P.bloodHi
        GameTooltip:SetText(p.kill and L["Kill"] or L["Wipe"], c[1], c[2], c[3])
        if p.pull then Tip2(_fmt(L["Pull %d"], p.pull), "") end
        local on = p.name or p.boss and _fmt(L["Boss %d"], p.boss) or NextKill(r, p)
        if on then Tip2(L["Boss"], on) end
        if p.phase then Tip2(_fmt(L["Phase %d"], p.phase), "") end
        if p.s and p.e then Tip2(L["Fight length"], Clock(p.e - p.s)) end
        Tip2(L["Time"], p.t or Clock(p.e or RT * p.at))
        GameTooltip:AddLine(r.focus and r.pulls[r.focus] == p and L["Click to show the whole raid."]
            or L["Click to show this fight on its own."], 0.6, 0.57, 0.5)
        GameTooltip:Show()
    end
    f.pullTip = PullTip

    -- Each fight can be hovered along the line.
    f.pullHits = {}
    for _, p in ipairs(r.pulls) do
        local px = PAD + _floor(span * p.at + 0.5)
        local x1 = p.s and X(p.s) or px - 8
        local hit = CreateFrame("Frame", nil, f)
        hit:SetSize(_max(16, px - x1), LH + 12); hit:SetPoint("TOPLEFT", f, "TOPLEFT", _min(x1, px - 8), LINE_Y + 6)
        hit:SetFrameLevel(f:GetFrameLevel() + 5)
        f.pullHits[#f.pullHits + 1] = hit
        Hover(hit, function(self) PullTip(self, p) end)
        hit:SetScript("OnMouseUp", function() UI.RaidFocus(r, p) end)
    end

    -- Each kill's boss on the line at the moment it died, its time beside it
    -- (moved along when it would touch the one before).
    local lastRight = -1e9
    for _, p in ipairs(r.pulls) do
        local who = p.kill and (p.name or (p.boss and r.bossNames and r.bossNames[p.boss]))
        if who and p.e then
            local kx = X(p.e)
            local tw = #(p.t or Clock(p.e)) * 7 + 10          -- (about: the badge's width)
            local mx = _max(PAD + MED_R + 1, lastRight + MED_R + 6, _min(kx - MED_R, endX - 6 - tw - MED_R - 2))
            local cy = LINE_Y + MED_R + 4
            p.medallion = Medallion(f, who, NpcOf(r, who), mx, cy)
            local m = p.medallion
            m:EnableMouse(true)
            Hover(m, function(self) PullTip(self, p) end)
            m:SetScript("OnMouseUp", function() UI.RaidFocus(r, p) end)
            if r.focus and r.pulls[r.focus] == p then
                local halo = Art(m, "Glow", "BACKGROUND", 0)
                halo:SetBlendMode("ADD"); halo:SetSize(64, 64); halo:SetPoint("CENTER")
                halo:SetVertexColor(P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 0.6)
                m.halo = halo
            end
            local bt, bw = Badge(mx + MED_R + 2, LINE_Y + 6, p.t or Clock(p.e), P.bronzeHi)
            p.badge = bt
            lastRight = mx + MED_R + 2 + bw
            p.medSpan = { mx - MED_R, lastRight }
        end
    end

    -- Who died, under the minutes: their class icon at the moment, close ones
    -- side by side (never on top of each other), with how many when there
    -- are more than three.
    f.deathMarks = {}
    local lastD = -1e9
    for _, dm in ipairs(DeathMarks(r)) do
        local STEP = 20
        local cx = _max(X(dm.first), lastD + 4 + 10)
        local shown = _min(3, #dm.list)
        for i = 1, shown do
            local e = dm.list[i]
            -- (Cut round, so the icon's square corners don't show past the ring.)
            local ic = f:CreateTexture(nil, "OVERLAY", nil, 1)
            ic:SetTexture(CLASS_TEX); ic:SetSize(15, 15)
            local cc = UI.CLASS_ICON_COORDS[e.p.class] or UI.CLASS_ICON_COORDS.UNKNOWN
            local iw, ih = (cc[2] - cc[1]) * 0.08, (cc[4] - cc[3]) * 0.08
            ic:SetTexCoord(cc[1] + iw, cc[2] - iw, cc[3] + ih, cc[4] - ih)
            if ic.AddMaskTexture and f.CreateMaskTexture then
                local mask = f:CreateMaskTexture()
                mask:SetTexture(MEDIA .. "CircleMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(ic)
                ic:AddMaskTexture(mask)
            end
            ic:SetPoint("CENTER", f, "TOPLEFT", cx + (i - 1) * STEP, DEATH_Y)
            local ring = Art(f, "Ring", "OVERLAY", 2)
            ring:SetSize(19, 19); ring:SetPoint("CENTER", ic, "CENTER")
            ring:SetVertexColor(P.blood[1], P.blood[2], P.blood[3], 1)
        end
        local right = cx + (shown - 1) * STEP + 10
        if #dm.list > shown then
            local n = Text(f, "semibold", 11, P.bloodHi, "LEFT")
            n:SetPoint("LEFT", f, "TOPLEFT", right + 2, DEATH_Y); n:SetText("+" .. (#dm.list - shown))
            right = right + 18
        end
        lastD = right
        local hit = CreateFrame("Frame", nil, f)
        hit:SetSize(right - cx + 12, 22); hit:SetPoint("LEFT", f, "TOPLEFT", cx - 10, DEATH_Y)
        hit:SetFrameLevel(f:GetFrameLevel() + 6)
        Hover(hit, function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 12, 12)
            GameTooltip:SetText(MS.Plural(#dm.list, "%d death", "%d deaths"), P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
            for _, e in ipairs(dm.list) do
                local cr, cg, cb = UI.ClassColor(e.p.class)
                GameTooltip:AddDoubleLine(e.p.name .. "  |cffa09a8c" .. e.by .. "|r", Clock(e.t), cr, cg, cb, 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        dm.hit, dm.span = hit, { cx - 10, right }
        f.deathMarks[#f.deathMarks + 1] = dm
    end
    Rule(f, -(HDR_H + PULLS_H))
end

-- The band behind column labels, as on the dungeon scoreboard.
local function LabelBand(parent, y, h)
    local bg = Solid(parent, "BACKGROUND", 0, 0, 0, 0, 0.25)
    bg:SetPoint("TOPLEFT", 2, y); bg:SetPoint("TOPRIGHT", -2, y); bg:SetHeight(h)
    Rule(parent, y - h)
end

-- The footer: a darker band under a bronze rule that fades to the corners.
local function Footer(view)
    local bg = Solid(view, "BACKGROUND", 0, 0, 0, 0, 0.3)
    bg:SetPoint("BOTTOMLEFT", 2, 2); bg:SetPoint("BOTTOMRIGHT", -2, 2); bg:SetHeight(FOOT_H)
    local l = view:CreateTexture(nil, "BORDER", nil, 2)
    l:SetPoint("BOTTOMLEFT", 2, FOOT_H + 2); l:SetPoint("BOTTOMRIGHT", view, "BOTTOM", 0, FOOT_H + 2); l:SetHeight(1)
    HGrad(l, P.bronze, P.bronzeHi, 0, 0.8)
    local rr = view:CreateTexture(nil, "BORDER", nil, 2)
    rr:SetPoint("BOTTOMRIGHT", -2, FOOT_H + 2); rr:SetPoint("BOTTOMLEFT", view, "BOTTOM", 0, FOOT_H + 2); rr:SetHeight(1)
    HGrad(rr, P.bronzeHi, P.bronze, 0.8, 0)
    local lbl = Text(view, "semibold", 15, P.bronzeHi)
    lbl:SetPoint("LEFT", view, "BOTTOMLEFT", PAD, FOOT_H / 2 + 2); lbl:SetText(L["Raid total"])
    return lbl
end

local function View(f)
    local v = CreateFrame("Frame", nil, f)
    v:SetPoint("TOPLEFT", 0, VIEW_Y); v:SetPoint("BOTTOMRIGHT", 0, 0)
    v:Hide()
    return v
end

-- ── Overview: every column ────────────────────────────────────────────────
local TCOLS = {
    { key = "name",    label = LK("Player"),       w = 205, left = true },
    { key = "loot",    label = LK("Loot"),         w = 95, left = true, loot = true },
    { key = "deaths",  label = LK("Deaths"),       w = 70 },
    { key = "taken",   label = LK("Damage taken"), w = 110, abbr = true },
    { key = "damage",  label = LK("Damage"),       w = 110, abbr = true },
    { key = "dps",     label = LK("DPS"),          w = 100, abbr = true, strong = true },
    { key = "healing", label = LK("Healing"),      w = 110, abbr = true },
    { key = "hps",     label = LK("HPS"),          w = 100, abbr = true, strong = true },
    { key = "kicks",   label = LK("Interrupts"),   w = 110 },
    { key = "dispels", label = LK("Dispels"),      w = 100 },
}
do
    local x = PAD
    for _, c in ipairs(TCOLS) do c.x = x; x = x + c.w end
end

local function CellText(c, v)
    if c.abbr then return (v or 0) > 0 and UI.Abbrev(v) or "-" end
    return tostring(v or 0)
end

local function CellColor(c, v)
    if c.key == "deaths" then return (v or 0) > 1 and P.bloodHi or (v or 0) == 0 and P.ash or P.ivory end
    if c.key == "kicks" then return P.kick end
    return c.strong and P.ivory or P.dmg
end

-- An item's tooltip: the game's own for a real item (a link); the samples'
-- made-up items get one built from what's known.
local function ItemTip(owner, e, who, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    local qr, qg, qb = UI.QualityColor(e.q)
    if e.link then
        pcall(GameTooltip.SetHyperlink, GameTooltip, e.link)
    else
        GameTooltip:SetText(e.name, qr, qg, qb)
        GameTooltip:AddLine(_fmt(L["%d item level"], e.ilvl), 1, 0.82, 0)
    end
    GameTooltip:AddLine(" ")
    if who then
        local cr, cg, cb = UI.ClassColor(who.class)
        Tip2(L["Looted by"], who.name, GREY, { cr, cg, cb })
    end
    local from = e.boss or e.from and _fmt(L["Boss %d"], e.from) or ""
    if from ~= "" then Tip2(L["Dropped by"], from) end
    GameTooltip:Show()
end

-- A player's loot, as on the dungeon scoreboard: the items' icons in their
-- quality's colour with the item level on them, three at most and "+N".
local function LootIcons(row, x, list, p)
    for i = 1, _min(3, #list) do
        local e = list[i]
        local qr, qg, qb = UI.QualityColor(e.q)
        local b = CreateFrame("Frame", nil, row)
        b:SetSize(22, 22); b:SetPoint("LEFT", row, "LEFT", x + (i - 1) * 26, 0)
        b:SetFrameLevel(row:GetFrameLevel() + 3)
        local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetAllPoints()
        ic:SetTexture("Interface\\Icons\\" .. e.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        Outline(b, { qr, qg, qb }, 1, "OVERLAY")
        local il = Text(b, "semibold", 10, P.ivory, "CENTER")
        il:SetPoint("BOTTOM", b, "BOTTOM", 0, -1); il:SetText(tostring(e.ilvl))
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self) ItemTip(self, e, p) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.lootIcons = row.lootIcons or {}
        row.lootIcons[i] = b
    end
    if #list > 3 then
        local more = Text(row, "medium", 12, P.ash)
        more:SetPoint("LEFT", row, "LEFT", x + 3 * 26, 0); more:SetText("+" .. (#list - 3))
        row.lootMore = more
    elseif #list == 0 then
        local none = Text(row, "medium", 15, P.ash)
        none:SetPoint("LEFT", row, "LEFT", x + 4, 0); none:SetText("-")
    end
end

local function OverviewRow(v, y, h, p, idx, top, lootBy)
    local row = MakeRow(v, W - 4, h)
    row:SetPoint("TOPLEFT", 2, y)
    PaintRow(row, p, idx)
    Hover(row, function(self) UI.RaidPlayerTooltip(self, p) end)
    for i = 2, #TCOLS do
        local c = TCOLS[i]
        if c.loot then LootIcons(row, c.x - 2, lootBy and lootBy[p.name] or {}, p) end
        local val = p[c.key]
        if c.loot then val = nil end
        local t = Text(row, c.strong and "semibold" or "medium", 15, CellColor(c, val), "RIGHT")
        t:SetPoint("RIGHT", row, "LEFT", c.x + c.w - 2, c.strong and 2 or 0)
        t:SetText(c.loot and "" or CellText(c, val))
        -- DPS and HPS: a bronze share bar under the number.
        if c.strong and (val or 0) > 0 and (top[c.key] or 0) > 0 then
            local bar = Solid(row, "ARTWORK", 2, P.bronze[1], P.bronze[2], P.bronze[3], 0.85)
            bar:SetHeight(2); bar:SetWidth(_max(2, (c.w - 24) * val / top[c.key]))
            bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", c.x + c.w - 2, 4)
        end
    end
    return y - h
end

local GROUPS = {
    { role = "TANK",    title = LK("Tanks"),   sort = "taken" },
    { role = "HEALER",  title = LK("Healers"), sort = "healing" },
    { role = "DAMAGER", title = LK("Damage"),  sort = "damage" },
}

local function GroupSummary(role, list, time)
    local taken, healing, damage, deaths = 0, 0, 0, 0
    for _, p in ipairs(list) do
        taken, healing, damage = taken + p.taken, healing + p.healing, damage + p.damage
        deaths = deaths + (p.deaths or 0)
    end
    local what = role == "TANK" and (UI.Abbrev(taken) .. " " .. L["Damage taken"])
        or role == "HEALER" and (UI.Abbrev(healing / time) .. " " .. L["HPS"])
        or (UI.Abbrev(damage / time) .. " " .. L["DPS"])
    return what .. "    " .. MS.Plural(deaths, "%d death", "%d deaths")
end

local function GroupHeader(v, y, g, list, time)
    local bg = v:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 2, y); bg:SetPoint("TOPRIGHT", -2, y); bg:SetHeight(24)
    HGrad(bg, P.bronze, P.bronze, 0.14, 0.02)
    local gt = Text(v, "semibold", 13, P.ivory)
    gt:SetPoint("LEFT", v, "TOPLEFT", PAD, y - 12); gt:SetText(L[g.title] .. "  (" .. #list .. ")")
    local gs = Text(v, "medium", 13, P.ash, "RIGHT")
    gs:SetPoint("RIGHT", v, "TOPLEFT", W - PAD, y - 12); gs:SetText(GroupSummary(g.role, list, time))
    Rule(v, y - 24, P.bronzeDk)
    return y - 24
end

local OVERVIEW_BODY_40 = 411

local function BuildOverview(f, r, t)
    local v = View(f)
    LabelBand(v, 0, 28)
    for _, c in ipairs(TCOLS) do
        local lt = Text(v, "medium", 12, c.strong and P.ivory or P.ash, c.left and "LEFT" or "RIGHT")
        if c.left then lt:SetPoint("LEFT", v, "TOPLEFT", c.x + (c.loot and 0 or 36), -14)
        else lt:SetPoint("RIGHT", v, "TOPLEFT", c.x + c.w, -14) end
        lt:SetText(L[c.label])
    end
    local top = {}
    for _, p in ipairs(r.players) do top.dps = _max(top.dps or 0, p.dps); top.hps = _max(top.hps or 0, p.hps) end
    local lootBy = {}
    for _, e in ipairs(r.loot or {}) do
        lootBy[e.who] = lootBy[e.who] or {}
        table.insert(lootBy[e.who], e)
    end
    -- 40 players scroll, in a body as tall as the groups view, so the
    -- window doesn't grow past the screen.
    local body, y = v, -29
    if r.size >= 40 then
        v.scroll = UI.MakeScrollFrame(v)
        v.scroll:SetPoint("TOPLEFT", 0, -29); v.scroll:SetPoint("TOPRIGHT", 0, -29)
        v.scroll:SetHeight(OVERVIEW_BODY_40)
        body, y = v.scroll.scrollContent, 0
    end
    if r.size < 20 then
        local list = {}
        for _, p in ipairs(r.players) do list[#list + 1] = p end
        for i, p in ipairs(SortBy(list, "damage")) do y = OverviewRow(body, y, 26, p, i, top, lootBy) end
    else
        for _, g in ipairs(GROUPS) do
            local list = {}
            for _, p in ipairs(r.players) do if p.role == g.role then list[#list + 1] = p end end
            y = GroupHeader(body, y, g, list, r.time)
            for i, p in ipairs(SortBy(list, g.sort)) do y = OverviewRow(body, y, 24, p, i, top, lootBy) end
        end
    end
    if v.scroll then
        body:SetHeight(-y); v.scroll.UpdateRange()
        v.height = 29 + OVERVIEW_BODY_40
    else
        v.height = -y
    end
    Footer(v)
    for i = 2, #TCOLS do
        local c = TCOLS[i]
        if c.loot then
            local lt = Text(v, "medium", 15, P.dmg, "LEFT")
            lt:SetPoint("LEFT", v, "BOTTOMLEFT", c.x, FOOT_H / 2 + 2)
            lt:SetText(MS.Plural(#(r.loot or {}), "%d item", "%d items"))
        else
            local tt = Text(v, c.strong and "semibold" or "medium", 15, CellColor(c, 2), "RIGHT")
            tt:SetPoint("RIGHT", v, "BOTTOMLEFT", c.x + c.w, FOOT_H / 2 + 2)
            tt:SetText(CellText(c, t[c.key]))
        end
    end
    return v
end

-- ── One stat at a time ─────────────────────────────────────────────────────
local METRICS = {
    { key = "dps",     tab = LK("Damage"),       col = LK("DPS"),          abbr = true, share = "damage" },
    { key = "hps",     tab = LK("Healing"),      col = LK("HPS"),          abbr = true, share = "healing" },
    { key = "taken",   tab = LK("Damage taken"), col = LK("Damage taken"), abbr = true },
    { key = "deaths",  tab = LK("Deaths"),       col = LK("Deaths") },
    { key = "kicks",   tab = LK("Interrupts"),   col = LK("Interrupts") },
    { key = "dispels", tab = LK("Dispels"),      col = LK("Dispels") },
}
-- The raid in groups of five, like the game's raid frames: 10 players in
-- two groups side by side, 20 in four, 40 in two rows of four. Each player
-- is a cell that fills with their class colour by the stat, with their role,
-- deaths and rank across the raid. Tanks, then healers, then damage are dealt
-- round the groups, so each group has its share of each.
local CELL_H, CELL_GAP, GHDR_H, GCOL_GAP, GROW_GAP, BAND_H = 30, 4, 22, 14, 14, 26
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

local function GroupCols(size) return size >= 20 and 4 or 2 end

local function DealGroups(r)
    local roster = {}
    for i, p in ipairs(r.players) do roster[i] = p end
    table.sort(roster, function(a, b)
        local ra, rb = ROLE_ORDER[a.role] or 3, ROLE_ORDER[b.role] or 3
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    local n, groups = _ceil(#roster / 5), {}
    for g = 1, n do groups[g] = {} end
    for i, p in ipairs(roster) do
        local gi = (i - 1) % n + 1
        local g = groups[gi]; g[#g + 1] = p
        p.group = gi
    end
    return groups
end

local function MakeCell(parent, w)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(w, CELL_H)
    c.bg = Solid(c, "BACKGROUND", 0, 0, 0, 0, 0.32); c.bg:SetAllPoints()
    c.fill = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.fill:SetPoint("TOPLEFT", 1, -1); c.fill:SetPoint("BOTTOMLEFT", 1, 1)
    c.barW = w - 2
    c.line = Outline(c, P.line, 1, "BORDER", 0)
    c.role = c:CreateTexture(nil, "ARTWORK")
    c.role:SetTexture(UI.ROLE_ICON_TEX); c.role:SetSize(16, 16); c.role:SetPoint("LEFT", 6, 0)
    c.rank = Text(c, "medium", 12, P.ash, "RIGHT"); c.rank:SetPoint("RIGHT", -6, 0); c.rank:SetWidth(30)
    c.value = Text(c, "semibold", 14, P.ivory, "RIGHT"); c.value:SetPoint("RIGHT", -38, 0)
    -- Names are first and last (as on Forever): cut short with "..." when
    -- they don't fit; deaths sit by the value, so they never move.
    c.died = Text(c, "semibold", 12, P.bloodHi, "RIGHT"); c.died:SetPoint("RIGHT", c.value, "LEFT", -8, 0)
    c.name = Text(c, "semibold", 13, P.ivory); c.name:SetPoint("LEFT", 28, 0)
    c.name:SetWidth(w - 28 - 38 - 46 - 26); c.name:SetWordWrap(false)
    return c
end

local function BuildRanks(f, r)
    local v = View(f)
    local cols = GroupCols(r.size)
    local inner = W - 2 * PAD
    local colW = _floor((inner - (cols - 1) * GCOL_GAP) / cols)
    LabelBand(v, 0, BAND_H)
    v.hint = Text(v, "medium", 12, P.ash, "RIGHT"); v.hint:SetPoint("RIGHT", v, "TOPRIGHT", -PAD, -BAND_H / 2)
    v.groupLbl = Text(v, "medium", 12, P.ash); v.groupLbl:SetPoint("LEFT", v, "TOPLEFT", PAD, -BAND_H / 2)
    v.groupLbl:SetText(MS.Plural(_ceil(#r.players / 5), "%d group", "%d groups"))
    v.groups, v.cells = DealGroups(r), {}
    local groupH = GHDR_H + 5 * (CELL_H + CELL_GAP)
    v.groupFrames = {}
    for gi, list in ipairs(v.groups) do
        local col, row = (gi - 1) % cols, _floor((gi - 1) / cols)
        local x, y = PAD + col * (colW + GCOL_GAP), -(BAND_H + 10) - row * (groupH + GROW_GAP)
        local g = CreateFrame("Frame", nil, v)
        g:SetSize(colW, groupH); g:SetPoint("TOPLEFT", x, y)
        g.col, g.row = col, row
        g.title = Text(g, "semibold", 13, P.bronzeHi); g.title:SetPoint("TOPLEFT", 2, -3)
        g.title:SetText(_fmt(L["Group %d"], gi))
        g.sum = Text(g, "medium", 12, P.ash, "RIGHT"); g.sum:SetPoint("TOPRIGHT", -2, -4)
        local u = Solid(g, "BORDER", 0, P.bronzeDk[1], P.bronzeDk[2], P.bronzeDk[3], 1)
        u:SetPoint("TOPLEFT", 0, -(GHDR_H - 4)); u:SetPoint("TOPRIGHT", 0, -(GHDR_H - 4)); u:SetHeight(1)
        g.cells = {}
        for i = 1, 5 do
            local c = MakeCell(g, colW)
            c:SetPoint("TOPLEFT", 0, -GHDR_H - (i - 1) * (CELL_H + CELL_GAP))
            c.player = list[i]
            c:SetShown(list[i] ~= nil)
            Hover(c, function(self) UI.RaidPlayerTooltip(self, self.player, r, v.metric) end, c.line,
                function(self) return self.player and self.player.name == ME and P.bronzeHi or P.line end)
            g.cells[i] = c
            if list[i] then v.cells[#v.cells + 1] = c end
        end
        v.groupFrames[gi] = g
    end
    local rows = _ceil(#v.groups / cols)
    v.height = BAND_H + 10 + rows * groupH + (rows - 1) * GROW_GAP + 6
    v.total = Text(v, "medium", 15, P.dmg)
    v.total:SetPoint("LEFT", Footer(v), "RIGHT", 14, 0)
    return v
end

local function Fmt(m, val)
    if m.abbr then return val > 0 and UI.Abbrev(val) or "-" end
    return tostring(val)
end

local function FillRanks(v, r, t, m)
    v.metric = m.key
    local ranked, top = {}, 0
    for i, p in ipairs(r.players) do ranked[i] = p; top = _max(top, p[m.key] or 0) end
    SortBy(ranked, m.key)
    local place = {}
    for i, p in ipairs(ranked) do place[p] = i end
    for gi, g in ipairs(v.groupFrames) do
        local sum = 0
        for _, c in ipairs(g.cells) do
            local p = c.player
            if p then
                local val = p[m.key] or 0
                sum = sum + val
                local cr, cg, cb = UI.ClassColor(p.class)
                local me = p.name == ME
                HGrad(c.fill, { cr, cg, cb }, { cr, cg, cb }, 0.34, 0.16)
                c.fill:SetWidth(_max(1, c.barW * (top > 0 and val / top or 0)))
                c.fill:SetShown(val > 0)
                c.line:SetColor(me and P.bronzeHi or P.line, me and 0.9 or 1)
                local rc = UI.ROLE_ICON_COORDS[p.role] or UI.ROLE_ICON_COORDS.DAMAGER
                c.role:SetTexCoord(rc[1], rc[2], rc[3], rc[4])
                c.name:SetText(p.name); c.name:SetTextColor(cr, cg, cb)
                c.died:SetText(m.key ~= "deaths" and (p.deaths or 0) > 0 and ("x" .. p.deaths) or "")
                c.value:SetText(Fmt(m, val))
                c.rank:SetText("#" .. place[p])
            end
        end
        g.sum:SetText(Fmt(m, sum))
    end
    v.hint:SetText(_fmt(L["Bars by %s, # is the rank in the raid"], L[m.col]))
    local sum = m.share and t[m.share] or t[m.key]
    v.total:SetText((m.abbr and UI.Abbrev(sum) or tostring(sum)) .. " " .. L[m.tab]
        .. (m.share and ("    " .. UI.Abbrev(t[m.key]) .. " " .. L[m.col]) or ""))
end

-- ── Loot ───────────────────────────────────────────────────────────────────
local LCOLS = {
    { label = LK("Item"),       x = PAD + 36 },
    { label = LK("Item level"), x = 560, right = true },
    { label = LK("Player"),     x = 620 },
    { label = LK("Boss"),       x = 860 },
}
local LOOT_H = 34

local function LootRow(v, y, e, idx, byName)
    local p = byName[e.who] or { name = e.who, class = "UNKNOWN" }
    local row = MakeRow(v, W - 4, LOOT_H)
    row:SetPoint("TOPLEFT", 2, y)
    PaintRow(row, p, idx)
    -- The row is the item's: no class icon or rank, the name goes to its column.
    row.icon:Hide(); row.rank:SetText("")
    local qr, qg, qb = UI.QualityColor(e.q)
    local holder = CreateFrame("Frame", nil, row)
    holder:SetSize(26, 26); holder:SetPoint("LEFT", PAD - 2, 0)
    local ic = holder:CreateTexture(nil, "ARTWORK"); ic:SetAllPoints()
    ic:SetTexture("Interface\\Icons\\" .. e.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Outline(holder, { qr, qg, qb }, 1, "OVERLAY")
    local item = Text(row, "semibold", 15, { qr, qg, qb }); item:SetPoint("LEFT", LCOLS[1].x - 2, 0); item:SetText(e.name)
    local il = Text(row, "medium", 15, P.ivory, "RIGHT"); il:SetPoint("RIGHT", row, "LEFT", LCOLS[2].x - 2, 0)
    il:SetText(tostring(e.ilvl))
    row.name:ClearAllPoints(); row.name:SetPoint("LEFT", LCOLS[3].x - 2, 0)
    local boss = Text(row, "medium", 15, P.ash); boss:SetPoint("LEFT", LCOLS[4].x - 2, 0)
    local from = e.boss or e.from and _fmt(L["Boss %d"], e.from) or ""
    boss:SetText(from)
    -- Hover: the item's own tooltip when there's a link (a real raid); the
    -- samples' made-up items get one built from what's known.
    Hover(row, function(self) ItemTip(self, e, p, "ANCHOR_CURSOR_RIGHT") end)
    return y - LOOT_H
end

local function BuildLoot(f, r)
    local v = View(f)
    LabelBand(v, 0, 26)
    for _, c in ipairs(LCOLS) do
        local lt = Text(v, "medium", 12, P.ash, c.right and "RIGHT" or "LEFT")
        if c.right then lt:SetPoint("RIGHT", v, "TOPLEFT", c.x, -13) else lt:SetPoint("LEFT", v, "TOPLEFT", c.x, -13) end
        lt:SetText(L[c.label])
    end
    local byName = {}
    for _, p in ipairs(r.players) do byName[p.name] = p end
    local y = -27
    for i, e in ipairs(r.loot or {}) do y = LootRow(v, y, e, i, byName) end
    v.height = -y
    local sum = Text(v, "medium", 15, P.dmg)
    sum:SetPoint("LEFT", Footer(v), "RIGHT", 14, 0)
    sum:SetText(MS.Plural(#(r.loot or {}), "%d item", "%d items"))
    return v
end

-- ── Tabs ───────────────────────────────────────────────────────────────────
local function Tab(f, x, label)
    local b = Box(Btn(f))
    b.label = Text(b, "medium", 14, P.ash, "CENTER"); b.label:SetPoint("CENTER")
    b.label:SetText(label)
    local w = _max(76, _ceil((b.label:GetStringWidth() or 0) + 26))
    b:SetSize(w, 26); b:SetPoint("TOPLEFT", x, -(HDR_H + PULLS_H) - 9)
    -- Hover: an unselected tab's outline goes bronze and its label ivory, as
    -- the selected one's already is.
    b:SetScript("OnEnter", function(self)
        if f.selected ~= self then self._outline:SetColor(P.bronze, 0.7) end
        self.label:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3])
    end)
    b:SetScript("OnLeave", function(self)
        local on = f.selected == self
        self._outline:SetColor(on and P.bronze or P.line, 1)
        local c = on and P.ivory or P.ash
        self.label:SetTextColor(c[1], c[2], c[3])
    end)
    return b, w
end

local function SelectTab(f, tab)
    f.selected = tab
    for _, b in ipairs(f.tabs) do
        local on = b == tab
        b._outline:SetColor(on and P.bronze or P.line, 1)
        local c = on and P.ivory or P.ash
        b.label:SetTextColor(c[1], c[2], c[3])
    end
    for _, v in pairs(f.views) do v:Hide() end
    -- The window is as tall as this tab needs (the 20-player overview is the
    -- tall one; it opens on its two columns).
    -- Kept even: the window is centred, and an odd height puts its edges (and
    -- the tabs' 1px outlines) on half pixels, where they drop out.
    local h = _ceil(-VIEW_Y + (tab.view.height or 300) + 8 + FOOT_H + 2)
    f:SetHeight(h + h % 2)
    tab.view:Show()
    if tab.metric then FillRanks(tab.view, f.run, f.totals, tab.metric) end
end

local function BuildTabs(f, r, t)
    f.tabs, f.views = {}, {}
    local x = PAD
    local function Add(label, view, metric)
        local b, w = Tab(f, x, label)
        b.view, b.metric = view, metric
        b:SetScript("OnClick", function() SelectTab(f, b) end)
        f.tabs[#f.tabs + 1] = b
        x = x + w + 6
    end
    f.views.overview = BuildOverview(f, r, t); Add(L["Overview"], f.views.overview)
    f.views.ranks = BuildRanks(f, r)
    for _, m in ipairs(METRICS) do Add(L[m.tab], f.views.ranks, m) end
    f.views.loot = BuildLoot(f, r)
    Add(L["Loot"], f.views.loot)
    SelectTab(f, f.tabs[1])
end

-- ── The window ─────────────────────────────────────────────────────────────
local windows = {}

local function Build(r)
    local t = Totals(r)
    local f = CreateFrame("Frame", "MythicScoreboardRaid" .. r.size .. (r.focus and ("Fight" .. r.focus) or ""), UIParent)
    f.run, f.totals = r, t
    f:SetWidth(W)
    f:SetPoint("CENTER", UIParent, "CENTER", -150, 30)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.BuildChrome(f, 90)
    BuildHeader(f, r, t)
    BuildPulls(f, r)
    BuildTabs(f, r, t)
    UI.AddRaidSwitch(f)
    -- Closing the window closes the sample's in-run frame too.
    f:SetScript("OnHide", function() if UI.HideRaidFrame then UI.HideRaidFrame() end end)
    tinsert(UISpecialFrames, f:GetName())
    f:Hide()
    return f
end

local function HideAll()
    for _, f in pairs(windows) do f:Hide() end
end

-- Which window /sb opens out of an instance: the one used last.
local lastBoard, lastRaid

local function OpenRaid(r, quiet)
    HideAll()
    if not windows[r.key] then
        local ok, f = pcall(Build, r)
        if not ok then MS:ReportError("Raid", f); return end
        windows[r.key] = f
    end
    local f = windows[r.key]
    SelectTab(f, f.tabs[1])                              -- always opens on Overview
    if UI.frame and UI.frame:IsShown() then UI.frame:Hide() end
    f:Show()
    if UI.ShowRaidFrame then UI.ShowRaidFrame(r, f) end
    lastBoard, lastRaid = "raid", r
    if not quiet then MS.Say(L["A sample raid, not saved. Type /sb raid to close it."]) end
    return f
end

local function OpenDungeon() MS:ShowScoreboard() end

-- ── One fight on its own ───────────────────────────────────────────────────
-- Clicking a boss (or a fight on the timeline) shows that pull alone, as the
-- dungeon scoreboard does: everyone's numbers for that fight, its deaths,
-- its loot; the timeline still shows the whole raid, the fight lit up.
-- (The samples share each player's numbers over the fights by length.)
local function Scale(list, k)
    local out = {}
    for i, e in ipairs(list or {}) do out[i] = { name = e.name, amount = _floor(e.amount * k + 0.5) } end
    return out
end

local function FightOf(r, idx)
    local p = r.pulls[idx]
    local d = p.e - p.s
    local all = 0
    for _, q in ipairs(r.pulls) do if q.s then all = all + (q.e - q.s) end end
    local rf = setmetatable({}, { __index = r })
    rf.key, rf.focus, rf.base = r.key .. "#" .. idx, idx, r
    rf.time, rf.runTime = d, r.time
    rf.wipes = p.kill and 0 or 1
    rf.players = {}
    for i, pl in ipairs(r.players) do
        local k = d / all * (0.8 + ((i * 7 + idx * 13) % 9) / 20)
        local np = setmetatable({}, { __index = pl })
        np.damage, np.healing, np.taken = _floor(pl.damage * k), _floor(pl.healing * k), _floor(pl.taken * k)
        np.kicks, np.dispels = _floor(pl.kicks * k + 0.5), _floor(pl.dispels * k + 0.5)
        np.spells, np.heals = Scale(pl.spells, k), Scale(pl.heals, k)
        np.dispelTypes = Scale(pl.dispelTypes, np.dispels / _max(1, pl.dispels))
        np.deathLog = {}
        for _, e in ipairs(pl.deathLog or {}) do
            if e.t >= p.s and e.t <= p.e then np.deathLog[#np.deathLog + 1] = e end
        end
        np.deaths, np.rank = #np.deathLog, nil
        rf.players[i] = np
    end
    local who = p.name or NextKill(r, p)
    rf.loot = {}
    if p.kill then
        for _, e in ipairs(r.loot or {}) do if e.boss == who then rf.loot[#rf.loot + 1] = e end end
    end
    return rf
end

-- Show one fight (nil: the whole raid), in the same place, on the same tab.
function UI.RaidFocus(r, p)
    local base = r.base or r
    local idx
    for i, q in ipairs(base.pulls) do if q == p then idx = i end end
    if idx and r.focus == idx then idx = nil end            -- clicking it again: back
    local was = windows[r.key]
    local tabAt = 1
    if was and was.selected then for i, t in ipairs(was.tabs) do if t == was.selected then tabAt = i end end end
    local target = idx and FightOf(base, idx) or base
    target = idx and (windows[target.key] and windows[target.key].run or target) or base
    local f = OpenRaid(target, true)
    if not f then return end
    lastRaid = base
    if was and was ~= f then
        local pt, rel, rp, x, y = was:GetPoint()
        if pt then f:ClearAllPoints(); f:SetPoint(pt, rel, rp, x, y) end
    end
    if f.tabs[tabAt] then SelectTab(f, f.tabs[tabAt]) end
    if UI.ShowRaidFrame then UI.ShowRaidFrame(base, f) end
    return f
end

-- The raid for where you are. There's no raid tracking yet, so for now it's
-- the sample nearest the instance's size.
local function RaidHere()
    local maxPlayers = select(5, GetInstanceInfo()) or 10
    return UI.RaidDemo(maxPlayers > 25 and "40" or maxPlayers > 10 and "20" or "10")
end

-- /sb: the raid window in a raid, the dungeon scoreboard in a dungeon, and
-- elsewhere whichever was open last.
function MS:OpenBoard()
    local inInst, kind = IsInInstance()
    if inInst and kind == "raid" then
        local r = RaidHere()
        if r then OpenRaid(r) return end
    end
    if not inInst and lastBoard == "raid" and lastRaid then OpenRaid(lastRaid, true) return end
    OpenDungeon()
end

-- /sb raid [10 | 20 | 40 | a raid's name]: that sample's views; nothing,
-- closes them.
function MS:RaidCommand(arg)
    arg = arg or ""
    if arg == "dump" then MS:RaidDump() return end
    if arg == "live" and UI.RaidLiveTest then UI.RaidLiveTest() return end
    if arg == "hp" and UI.BossHealthCheck then UI.BossHealthCheck() return end
    local r = UI.RaidDemo(arg)
    if not r then
        local open = false
        for _, f in pairs(windows) do open = open or f:IsShown() end
        HideAll()
        if arg ~= "" or not open then MS.Say(L["Raid views: /sb raid 10, /sb raid 20 or /sb raid 40."]) end
        return
    end
    OpenRaid(r)
end

-- Each window has a way to the other: "Dungeons" at the right end of the raid
-- window's tab row,
-- "Raids" under the dungeon scoreboard's gear and close buttons.
local function SwitchButton(parent, label, tip, onClick)
    local b = Box(Btn(parent), true)
    local t = Text(b, "medium", 13, P.ash, "CENTER"); t:SetPoint("CENTER", 0, 0); t:SetText(label)
    b:SetSize(_max(70, _ceil((t:GetStringWidth() or 0) + 24)), 26)
    b.label = t
    b:HookScript("OnEnter", function(self)
        t:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(tip); GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() t:SetTextColor(P.ash[1], P.ash[2], P.ash[3]); GameTooltip:Hide() end)
    b:SetScript("OnClick", onClick)
    return b
end

-- ── Raid history ───────────────────────────────────────────────────────────
-- (Closes with the window.)
-- A list of saved raids under its button, as on the dungeon scoreboard:
-- newest first, each with its size, time and how far the raid got. Clicking
-- one opens it in the window's place.
local HIST_ROW = 26
local function RaidResult(r)
    if (r.killed or 0) >= (r.bosses or 1) then return L["Cleared"], P.verd end
    return _fmt(L["%d of %d bosses"], r.killed or 0, r.bosses or 0), P.ash
end

local function OpenFromHistory(from, r)
    local f = OpenRaid(r, true)
    if f and from and from ~= f then
        local pt, rel, rp, x, y = from:GetPoint()
        if pt then f:ClearAllPoints(); f:SetPoint(pt, rel, rp, x, y) end
    end
end

local function BuildHistory(f, anchor)
    local d = CreateFrame("Frame", nil, f)
    d:SetFrameStrata("DIALOG")
    d:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    UI.BuildChrome(d, 20)
    d:EnableMouse(true)
    d.rows = {}
    local list = UI.RaidHistory and UI.RaidHistory() or {}
    local w = 440
    for i, r in ipairs(list) do
        local row = Btn(d)
        row:SetSize(w - 8, HIST_ROW); row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * HIST_ROW)
        local hov = Solid(row, "BACKGROUND", 1, P.bronze[1], P.bronze[2], P.bronze[3], 0.14); hov:SetAllPoints()
        local mark = Solid(row, "ARTWORK", 0, P.bronze[1], P.bronze[2], P.bronze[3], 1)
        mark:SetPoint("TOPLEFT"); mark:SetPoint("BOTTOMLEFT"); mark:SetWidth(2)
        local idx = Text(row, "medium", 12, P.ash2 or P.ash, "CENTER"); idx:SetPoint("LEFT", 6, 0); idx:SetWidth(22)
        idx:SetText(tostring(i))
        local name = Text(row, "medium", 13, P.ivory); name:SetPoint("LEFT", 34, 0); name:SetText(r.name)
        local size = Text(row, "medium", 12, P.ash); size:SetPoint("LEFT", 170, 0); size:SetText(_fmt(L["%d players"], r.size))
        local tm = Text(row, "medium", 13, P.ash, "RIGHT"); tm:SetPoint("RIGHT", row, "RIGHT", -110, 0); tm:SetText(Clock(r.time))
        local res, rc = RaidResult(r)
        local rt = Text(row, "medium", 13, rc, "RIGHT"); rt:SetPoint("RIGHT", row, "RIGHT", -8, 0); rt:SetText(res)
        row.raid, row.hov, row.mark = r, hov, mark
        row:SetScript("OnEnter", function() hov:Show() end)
        row:SetScript("OnLeave", function() if not row.selected then hov:Hide() end end)
        row:SetScript("OnClick", function() d:Hide(); OpenFromHistory(f, r) end)
        d.rows[i] = row
    end
    d:SetSize(w, #list * HIST_ROW + 8)
    d:SetScript("OnShow", function()
        local base = f.run.base or f.run
        for _, row in ipairs(d.rows) do
            row.selected = row.raid == base
            row.hov:SetShown(row.selected); row.mark:SetShown(row.selected)
        end
    end)
    d:Hide()
    return d
end

UI.AddRaidSwitch = function(f)
    local b = SwitchButton(f, L["Dungeons"], L["Open the dungeon scoreboard"], OpenDungeon)
    b:SetPoint("TOPRIGHT", -PAD, -(HDR_H + PULLS_H) - 9)
    b:SetFrameLevel(f:GetFrameLevel() + 10)
    f.dungeonButton = b
    local h = SwitchButton(f, L["Run history"], L["Run history"], function()
        f.history = f.history or BuildHistory(f, f.historyButton)
        f.history:SetShown(not f.history:IsShown())
    end)
    -- (a chevron after the words, as on the dungeon scoreboard's)
    h:SetWidth(h:GetWidth() + 14)
    h.label:ClearAllPoints(); h.label:SetPoint("CENTER", -7, 0)
    local chev = Art(h, "Chevron", "OVERLAY", 0)
    chev:SetSize(10, 10); chev:SetPoint("LEFT", h.label, "RIGHT", 6, 0)
    chev:SetVertexColor(P.ash[1], P.ash[2], P.ash[3], 1)
    h:SetPoint("RIGHT", b, "LEFT", -8, 0)
    h:SetFrameLevel(f:GetFrameLevel() + 10)
    f.historyButton = h
    if f.run.focus then
        local back = SwitchButton(f, L["Whole raid"], L["Back to the whole raid"], function() UI.RaidFocus(f.run, nil) end)
        back:SetPoint("RIGHT", h, "LEFT", -8, 0)
        back:SetFrameLevel(f:GetFrameLevel() + 10)
        f.wholeButton = back
    end
end

local function AddDungeonSwitch()
    local sb = UI.frame
    if not sb or sb.raidButton or not sb.CloseButton then return end
    local b = SwitchButton(sb.CloseButton:GetParent(), L["Raids"], L["Open the raid scoreboard"], function()
        sb:Hide()
        OpenRaid(lastRaid or RaidHere() or UI.RaidDemo("10"), true)
    end)
    -- Under the gear and close buttons, as wide as the two.
    b:SetSize(68, 24)
    b:SetPoint("TOPRIGHT", sb.CloseButton, "BOTTOMRIGHT", 0, -6)
    sb.raidButton = b
end
-- The dungeon scoreboard opening any way (at a key's end, say) takes over
-- from the raid window.
local showScoreboard = MS.ShowScoreboard
MS.ShowScoreboard = function(self, ...)
    lastBoard = "dungeon"
    HideAll()
    return showScoreboard(self, ...)
end
local buildUI = MS.BuildUI
MS.BuildUI = function(self, ...)
    local r = buildUI(self, ...)
    AddDungeonSwitch()
    return r
end
AddDungeonSwitch()

-- ── /sb raid dump (dev) ────────────────────────────────────────────────────
-- What this game client already knows about the new raids, for building
-- raid tracking before they open: achievements (and their criteria) that name
-- a raid or a boss, the encounter journal's entries (with the encounter IDs
-- ENCOUNTER_START uses), and the map and instance IDs with the raids' names.
-- Saved account-wide; a /reload writes it to the SavedVariables file.
local DUMP_WORDS = { "Barrow Deeps", "Hyjal Summit", "Onyxia" }
for _, list in pairs(UI.RAID_BOSSES or {}) do
    for _, n in ipairs(list) do DUMP_WORDS[#DUMP_WORDS + 1] = n end
end

local function Hit(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and v ~= "" then
            for _, w in ipairs(DUMP_WORDS) do if v:find(w, 1, true) then return true end end
        end
    end
    return false
end

local function Pack(...)
    local t = {}
    for i = 1, select("#", ...) do local v = select(i, ...); t[i] = v == nil and "nil" or tostring(v) end
    return t
end

local function G(name) return rawget(_G, name) end

function MS:RaidDump()
    local out = { build = Pack(G("GetBuildInfo") and G("GetBuildInfo")()), achievements = {}, journal = {},
        maps = {}, instances = {} }
    MythicScoreboardAccountDB = MythicScoreboardAccountDB or {}
    MythicScoreboardAccountDB.raidDump = out
    MS.Say("Raid dump: reading the game's data...")

    -- Achievements, by ID, a slice per frame.
    local GAI, NC, CI = G("GetAchievementInfo"), G("GetAchievementNumCriteria"), G("GetAchievementCriteriaInfo")
    local function Achievement(id)
        local ok, aid, name, _, _, _, _, _, desc = pcall(GAI, id)
        if not ok or not aid then return end
        local crit, any = {}, Hit(name, desc)
        local n = NC and select(2, pcall(NC, id)) or 0
        for i = 1, (type(n) == "number" and n or 0) do
            local c = Pack(select(2, pcall(CI, id, i)))
            crit[i] = c
            any = any or Hit(c[1])
        end
        if any then out.achievements[#out.achievements + 1] = { id = aid, name = name, desc = desc, criteria = crit } end
    end

    local function Rest()
        -- The encounter journal: every tier's raids and dungeons, then by ID.
        if G("EJ_GetNumTiers") then
            local seen = {}
            local function Instance(jid, name)
                if seen[jid] or not Hit(name) then return end
                seen[jid] = true
                pcall(EJ_SelectInstance, jid)
                local e = { journalInstanceID = jid, name = name, info = Pack(pcall(G("EJ_GetInstanceInfo") or error, jid)), encounters = {} }
                for j = 1, 30 do
                    local r = Pack(pcall(EJ_GetEncounterInfoByIndex, j, jid))
                    if r[1] ~= "true" or r[2] == "nil" then break end
                    -- name, description, journalEncounterID, rootSectionID, link, journalInstanceID,
                    -- dungeonEncounterID, instanceID
                    e.encounters[j] = { name = r[2], journalEncounterID = r[4], dungeonEncounterID = r[8], instanceID = r[9] }
                end
                out.journal[#out.journal + 1] = e
            end
            local okT, tiers = pcall(EJ_GetNumTiers)
            for tier = 1, (okT and tiers or 0) do
                pcall(EJ_SelectTier, tier)
                for _, raid in ipairs({ true, false }) do
                    for i = 1, 60 do
                        local ok, jid, name = pcall(EJ_GetInstanceByIndex, i, raid)
                        if not ok or not jid then break end
                        Instance(jid, name)
                    end
                end
            end
            if G("EJ_GetInstanceInfo") then
                for jid = 1, 3000 do
                    local ok, name = pcall(G("EJ_GetInstanceInfo"), jid)
                    if ok and name then Instance(jid, name) end
                end
            end
        end
        -- Map IDs (the world map's) and instance IDs (GetInstanceInfo's 8th).
        local GMI = C_Map and C_Map.GetMapInfo
        if GMI then
            for id = 1, 5000 do
                local ok, mi = pcall(GMI, id)
                if ok and type(mi) == "table" and Hit(mi.name) then
                    out.maps[#out.maps + 1] = { id = id, name = mi.name, mapType = mi.mapType, parent = mi.parentMapID }
                end
            end
        end
        if G("GetRealZoneText") then
            for id = 1, 5000 do
                local ok, name = pcall(GetRealZoneText, id)
                if ok and Hit(name) then out.instances[#out.instances + 1] = { id = id, name = name } end
            end
        end
        MS.Say(_fmt("Raid dump: %d achievements, %d journal raids, %d maps, %d instances. Type /reload to save it.",
            #out.achievements, #out.journal, #out.maps, #out.instances))
    end

    if not GAI then Rest() return end
    local id, LAST, STEP = 1, 100000, 4000
    local function Slice()
        for i = id, _min(LAST, id + STEP - 1) do Achievement(i) end
        id = id + STEP
        if id <= LAST then C_Timer.After(0, Slice) else Rest() end
    end
    Slice()
end

UI.RaidWindows = windows   -- for tests

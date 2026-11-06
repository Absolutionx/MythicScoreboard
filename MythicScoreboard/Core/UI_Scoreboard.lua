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
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local Abbrev, Art, BossIcon, Btn, BuildTimeline, CELL_FONT_SIZE = UI.Abbrev, UI.Art, UI.BossIcon, UI.Btn, UI.BuildTimeline, UI.CELL_FONT_SIZE
local CLASS_ICON_COORDS, COLS, COL_SORT_VALUES, CT, ClassColor, ComputeColumnAnchors = UI.CLASS_ICON_COORDS, UI.COLS, UI.COL_SORT_VALUES, UI.CT, UI.ClassColor, UI.ComputeColumnAnchors
local DN, DiffShort, FRAME_W, GetRole, GetTimelineDuration, HGrad = UI.DN, UI.DiffShort, UI.FRAME_W, UI.GetRole, UI.GetTimelineDuration, UI.HGrad
local Outline, P, PAD_X, ROLE_ICON_COORDS, ROLE_ICON_TEX, ROW_H = UI.Outline, UI.P, UI.PAD_X, UI.ROLE_ICON_COORDS, UI.ROLE_ICON_TEX, UI.ROW_H
local ScoreColor, SetFont, Solid, SplitAbbrev, Text, Tint = UI.ScoreColor, UI.SetFont, UI.Solid, UI.SplitAbbrev, UI.Text, UI.Tint
local _playersBuf, _rowPool, overviewRows, sortState = UI._playersBuf, UI._rowPool, UI.overviewRows, UI.sortState

-- Scoreboard table: rows, cells, header line and refresh.

-- ===========================================================================
-- Row pool
-- ===========================================================================

-- ── Loot icons ──────────────────────────────────────────────────────────

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetInfo    = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function LootDetails(entry)
    local link, quality, icon, ilvl = entry.link, entry.quality, nil, entry.ilvl
    local item = MS.LootItemString(entry)
    if GetInfo then
        local ok, _, fullLink, q = pcall(GetInfo, entry.link or item)
        if ok then
            link = link or fullLink
            quality = quality or q
            if q and not entry.quality then entry.quality = q end
            if fullLink and not entry.link then entry.link = fullLink end
        end
    end
    if GetInstant then
        local ok, _, _, _, _, ic = pcall(GetInstant, item)
        if ok then icon = ic end
    end
    if not ilvl and C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, lvl = pcall(C_Item.GetDetailedItemLevelInfo, link or item)
        if ok and lvl and lvl > 0 then ilvl = lvl; entry.ilvl = lvl end
    end
    return link or item, quality, icon, ilvl
end

local function QualityColor(q)
    if q and C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
        if ok and r then return r, g, b end
    end
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return P.bronze[1], P.bronze[2], P.bronze[3]
end

local function MakeLootIcon(row, x, idx)
    local b = Btn(row)
    b:SetSize(30, 30)
    b:SetPoint("LEFT", row, "LEFT", x, 0)
    b:SetFrameLevel(row:GetFrameLevel() + 2)
    local shadow = Solid(b, "BACKGROUND", 0, 0, 0, 0, 1); shadow:SetAllPoints()
    local rim = Solid(b, "BORDER", 0, 1, 1, 1, 1)
    rim:SetPoint("TOPLEFT", 1, -1); rim:SetPoint("BOTTOMRIGHT", -1, 1)
    local inner = Solid(b, "BORDER", 1, 0, 0, 0, 1)
    inner:SetPoint("TOPLEFT", 2, -2); inner:SetPoint("BOTTOMRIGHT", -2, 2)
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("TOPLEFT", 3, -3); ic:SetPoint("BOTTOMRIGHT", -3, 3)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local lvl = Text(b, "semibold", 11, P.ivory, "CENTER", "OUTLINE")
    lvl:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
    local hl = Solid(b, "HIGHLIGHT", 0, 1, 1, 1, 0.15)
    hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3)
    b._rim, b._icon, b._lvl = rim, ic, lvl

    b:SetScript("OnEnter", function(self2)
        if not self2._entry then return end
        GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
        local link = LootDetails(self2._entry)
        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", function(self2)
        if not self2._entry then return end
        local link = LootDetails(self2._entry)
        if link and HandleModifiedItemClick then pcall(HandleModifiedItemClick, link) end
    end)

    b.SetEntry = function(self2, entry)
        self2._entry = entry
        if not entry then self2:Hide(); return end
        local _, quality, icon, ilvl = LootDetails(entry)
        self2._icon:SetTexture(icon or 134400)   -- 134400: question-mark icon
        self2._rim:SetColorTexture(QualityColor(quality))
        self2._lvl:SetText(ilvl and tostring(ilvl) or "")
        self2:Show()
    end
    b:Hide()
    return b
end

-- One tooltip handler for every row; it reads the row's player and run.
local function RowOnEnter(self2)
    local pc = self2._player
    if not pc then return end
    GameTooltip:SetOwner(self2, "ANCHOR_CURSOR_RIGHT", 12, 12)
    local r2, g2, b2 = ClassColor(pc.class)
    GameTooltip:SetText(DN(pc.name) or "?", r2, g2, b2)

    if (pc.level or 0) > 0 and MS.Flavor.dungeonLevels then
        local lo, hi = MS:ForeverLevelRange(self2._run)
        GameTooltip:AddDoubleLine("Level", pc.level .. (lo and ("  (dungeon " .. lo .. "-" .. hi .. ")") or ""),
            0.8, 0.8, 0.8, 1, 1, 1)
    end
    local sc = pc.mythicScore or 0
    if sc > 0 then
        local sr, sg, sb2 = ScoreColor(sc)
        GameTooltip:AddDoubleLine("Mythic+ rating", sc, 0.8, 0.8, 0.8, sr, sg, sb2)
    end
    if (pc.itemLevel or 0) > 0 then
        GameTooltip:AddDoubleLine("Item level", pc.itemLevel, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local avoid = pc.avoidableDamageTaken or 0
    if avoid > 0 then
        GameTooltip:AddDoubleLine("Avoidable damage", Abbrev(avoid), 0.8, 0.8, 0.8, P.avoid[1], P.avoid[2], P.avoid[3])
    end

    -- Highest / lowest interrupt badge (healers other than Shaman excluded from "lowest").
    local intCount = pc.interrupts or 0
    local canKick = (pc.role ~= "HEALER") or (pc.class == "SHAMAN")
    local badge = ""
    local rr = self2._run
    if rr and rr.players then
        local hi, lo, n, loN = 0, _huge, 0, 0
        for _, op in pairs(rr.players) do
            local v = op.interrupts or 0
            n = n + 1
            if v > hi then hi = v end
            if op.role ~= "HEALER" or op.class == "SHAMAN" then
                loN = loN + 1
                if v < lo then lo = v end
            end
        end
        if n > 1 then
            if intCount > 0 and intCount == hi then badge = "  |cffe7b877most in group|r"
            elseif loN > 1 and canKick and intCount == lo then badge = "  |cffe57068fewest in group|r" end
        end
    end
    if intCount > 0 or badge ~= "" then
        GameTooltip:AddDoubleLine("Interrupts", intCount .. badge, 0.8, 0.8, 0.8, P.kick[1], P.kick[2], P.kick[3])
    end

    if pc.loot and #pc.loot > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Loot", P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        for _, e in ipairs(pc.loot) do
            local link, _, _, ilvl = LootDetails(e)
            local shownLink = (type(link) == "string" and link:find("|H")) and link or "Item not loaded yet"
            GameTooltip:AddDoubleLine("  " .. shownLink, ilvl and ("ilvl " .. ilvl) or "", 1, 1, 1, 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(" ")
    end

    local deathCount = pc.deaths or 0
    if deathCount == 0 then
        GameTooltip:AddDoubleLine("Deaths", "None", 0.8, 0.8, 0.8, P.verdHi[1], P.verdHi[2], P.verdHi[3])
    else
        GameTooltip:AddDoubleLine("Deaths", deathCount, 0.8, 0.8, 0.8, P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        if pc.deathEvents and #pc.deathEvents > 0 then
            GameTooltip:AddLine(" ")
            for _, de in ipairs(pc.deathEvents) do
                local dt = de.time or 0
                local segStr = ""
                for _, boss in ipairs((rr and rr.bosses) or {}) do
                    local pullT = boss.pullTime or 0
                    local killT = boss.killTime or boss.wipeTime
                        or rr.duration or _huge
                    if dt >= pullT and dt <= killT then
                        segStr = "  |cff999999" .. (boss.name or "?")
                            .. ((boss.wipeTime and not boss.killTime) and " (wipe)" or "")
                            .. ", " .. MS:FormatTime(dt - pullT) .. " into the fight|r"
                        break
                    end
                end
                GameTooltip:AddLine("|cffff9900" .. MS:FormatTime(dt) .. "|r" .. segStr, 1, 1, 1)
                if de.events then
                    local kill
                    for i = #de.events, 1, -1 do
                        local ev = de.events[i]
                        if ev and ev.overkill and ev.overkill > 0 then kill = ev; break end
                    end
                    kill = kill or de.events[#de.events]
                    if kill then
                        local line = "  |cffff9944" .. (kill.spellName or "Unknown") .. "|r"
                        if kill.caster and kill.caster ~= "" then
                            line = line .. " |cff888888by|r |cffffd700" .. kill.caster .. "|r"
                        end
                        if (kill.amount or 0) > 0 then
                            line = line .. " |cffff4444(" .. Abbrev(-kill.amount) .. ")|r"
                        end
                        GameTooltip:AddLine(line, 1, 1, 1)
                    end
                end
            end
        end
    end
    GameTooltip:Show()
end

local function AcquireRow(parent)
    local row = _rem(_rowPool)
    if row then
        row:SetParent(parent)
        row:ClearAllPoints()
        row:Show()
        return row
    end

    row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_W - 2, ROW_H)

    row._stripe = Solid(row, "BACKGROUND", 0, 1, 0.94, 0.86, 0.018)
    row._stripe:SetAllPoints()

    row._wash = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row._wash:SetPoint("TOPLEFT"); row._wash:SetPoint("BOTTOMLEFT"); row._wash:SetWidth(320)

    row._bar = Solid(row, "BORDER", 0, 1, 1, 1, 1)
    row._bar:SetPoint("TOPLEFT"); row._bar:SetPoint("BOTTOMLEFT"); row._bar:SetWidth(3)

    row._selfBg = Solid(row, "BACKGROUND", 2, P.bronze[1], P.bronze[2], P.bronze[3], 0.06)
    row._selfBg:SetAllPoints()
    row._selfLine = Outline(row, P.bronze, 0.6, "BORDER", 1)

    -- Class icon in a bronze frame
    local iconFrame = Solid(row, "ARTWORK", 0, 0, 0, 0, 1)
    iconFrame:SetSize(34, 34); iconFrame:SetPoint("LEFT", row, "LEFT", 12, 0)
    local iconRim = Solid(row, "ARTWORK", 1, P.bronzeDk[1], P.bronzeDk[2], P.bronzeDk[3], 1)
    iconRim:SetSize(32, 32); iconRim:SetPoint("CENTER", iconFrame)
    local classIcon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    classIcon:SetSize(30, 30); classIcon:SetPoint("CENTER", iconFrame)
    classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    row._classIcon = classIcon

    local roleBg = Art(row, "Disc", "OVERLAY", 0)
    roleBg:SetSize(17, 17); roleBg:SetPoint("CENTER", iconFrame, "BOTTOMRIGHT", -1, 2)
    Tint(roleBg, {0, 0, 0}, 0.9)
    local roleIcon = row:CreateTexture(nil, "OVERLAY", nil, 1)
    roleIcon:SetSize(14, 14); roleIcon:SetPoint("CENTER", roleBg)
    row._roleIcon = roleIcon

    local nameX = PAD_X - 2 + 46
    local nameW = COLS[1].w - 50
    row._nameFs = Text(row, "game", 14, P.ivory)
    row._nameFs:SetPoint("LEFT", row, "LEFT", nameX, 8); row._nameFs:SetWidth(nameW)
    row._subFs = Text(row, "regular", 12, P.ash)
    row._subFs:SetPoint("LEFT", row, "LEFT", nameX, -9); row._subFs:SetWidth(nameW)

    ComputeColumnAnchors()
    row._statFs = {}
    row._shareBar = {}
    for _, col in ipairs(COLS) do
        if col.key == "loot" then
            row._lootX = col.x
        elseif col.num then
            local font = col.strong and "semibold" or "medium"
            local main = Text(row, font, CELL_FONT_SIZE, P.ivory, "RIGHT")
            main:SetPoint("RIGHT", row, "LEFT", col.anchor, 0)
            local tail
            if col.num == "abbr" then
                tail = Text(row, font, CELL_FONT_SIZE, P.ivory, "LEFT")
                tail:SetPoint("LEFT", row, "LEFT", col.anchor, 0)
            end
            row._statFs[col.key] = { main = main, tail = tail }
            if col.strong then
                local bar = Solid(row, "ARTWORK", 0, P.bronze[1], P.bronze[2], P.bronze[3], 0.7)
                bar:SetHeight(2)
                bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", col.anchor + col.tailW, 9)
                row._shareBar[col.key] = bar
            end
        end
    end

    -- Loot icons (up to three; a fourth slot shows "+N")
    row._loot = {}
    for i = 1, 3 do row._loot[i] = MakeLootIcon(row, row._lootX + (i - 1) * 33, i) end
    row._lootMore = Text(row, "semibold", 13, P.ash, "LEFT")
    row._lootMore:SetPoint("LEFT", row, "LEFT", row._lootX + 2 * 33 + 2, 0)
    row._lootNone = Text(row, "medium", 16, P.ash2, "LEFT")
    row._lootNone:SetPoint("LEFT", row, "LEFT", row._lootX, 0)
    row._lootNone:SetText("-")

    local hov = Solid(row, "HIGHLIGHT", 0, 1, 0.94, 0.86, 0.035); hov:SetAllPoints()

    row._sep = Solid(row, "ARTWORK", 3, P.line[1], P.line[2], P.line[3], 0.55)
    row._sep:SetPoint("BOTTOMLEFT"); row._sep:SetPoint("BOTTOMRIGHT"); row._sep:SetHeight(1)

    row:EnableMouse(true)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function ReleaseRow(row)
    if not row then return end
    if row.GetObjectType and row:GetObjectType() ~= "Frame" then
        if row.Hide then row:Hide() end
        return
    end
    row:Hide()
    row:SetParent(UIParent)
    row:ClearAllPoints()
    _ins(_rowPool, row)
end

-- ===========================================================================
-- Column rendering
-- ===========================================================================

local COL_RENDERERS = {
    -- Forever: red-orange below the dungeon's level range, dimmed above it.
    level = function(p, _, run)
        local lvl = p.level or 0
        if lvl <= 0 then return "-", P.ash2[1], P.ash2[2], P.ash2[3] end
        local lo, hi
        if MS.ForeverLevelRange then lo, hi = MS:ForeverLevelRange(run) end
        if lo and lvl < lo then return lvl, P.avoid[1], P.avoid[2], P.avoid[3] end
        if hi and lvl > hi then return lvl, P.ash[1], P.ash[2], P.ash[3] end
        return lvl, P.ivory[1], P.ivory[2], P.ivory[3]
    end,
    score = function(p)
        local sc = p.mythicScore or 0
        if sc > 0 then return tostring(sc), ScoreColor(sc) end
        return "-", P.ash2[1], P.ash2[2], P.ash2[3]
    end,
    deaths = function(p)
        local d = p.deaths or 0
        if d > 0 then return tostring(d), P.blood[1], P.blood[2], P.blood[3] end
        return "0", P.ash2[1], P.ash2[2], P.ash2[3]
    end,
    -- "abbr" columns return the raw number; the cell splits it.
    dmgTaken = function(p)
        local v = p.damageTaken or 0
        if v > 0 then return v, P.dmg[1], P.dmg[2], P.dmg[3] end
        return 0, P.ash2[1], P.ash2[2], P.ash2[3]
    end,
    avoidable = function(p)
        local v = p.avoidableDamageTaken or 0
        if v > 0 then return v, P.avoid[1], P.avoid[2], P.avoid[3] end
        return 0, P.ash2[1], P.ash2[2], P.ash2[3]
    end,
    damage = function(p)
        local v = p.damageDone or 0
        if v <= 0 then return 0, P.ash2[1], P.ash2[2], P.ash2[3] end
        return v, P.ivory[1], P.ivory[2], P.ivory[3]
    end,
    healing = function(p)
        local v = p.healingDone or 0
        if v <= 0 then return 0, P.ash2[1], P.ash2[2], P.ash2[3] end
        return v, P.ivory[1], P.ivory[2], P.ivory[3]
    end,
    dps = function(p, dur)
        local v = (p.dps or 0) > 0 and p.dps
               or ((dur > 0 and (p.damageDone or 0) > 0) and (p.damageDone / dur) or 0)
        if v <= 0 then return 0, P.ash2[1], P.ash2[2], P.ash2[3] end
        return v, P.ivory[1], P.ivory[2], P.ivory[3]
    end,
    hps = function(p, dur)
        local v = (p.hps or 0) > 0 and p.hps
               or ((dur > 0 and (p.healingDone or 0) > 0) and (p.healingDone / dur) or 0)
        if v <= 0 then return 0, P.ash2[1], P.ash2[2], P.ash2[3] end
        local c = (GetRole(p) == "HEALER") and P.ivory or P.ash
        return v, c[1], c[2], c[3]
    end,
    interrupts = function(p)
        local v = p.interrupts or 0
        if v > 0 then return tostring(v), P.kick[1], P.kick[2], P.kick[3] end
        return "0", P.ash2[1], P.ash2[2], P.ash2[3]
    end,
    dispels = function(p)
        local v = p.dispels or 0
        if v > 0 then return tostring(v), P.verd[1], P.verd[2], P.verd[3] end
        return "0", P.ash2[1], P.ash2[2], P.ash2[3]
    end,
}

local function RateOf(p, field, total, dur)
    local v = p[field] or 0
    if v > 0 then return v end
    return (dur > 0 and (p[total] or 0) > 0) and (p[total] / dur) or 0
end

-- ===========================================================================
-- One boss fight
-- ===========================================================================
-- Clicking a boss on the timeline shows the table for that fight alone.
-- The fight is a stand-in for the run: same players, with their numbers,
-- deaths, interrupts and loot from the fight in place of the run's.

UI.focus = nil      -- { run = run, boss = boss } while a fight is shown

local function FightEnd(run, boss)
    return boss.killTime or boss.wipeTime or MS:GetRunDuration(run)
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
    elseif boss.killTime or boss.wipeTime then
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
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -54)   -- where "New personal best" sits
    b:SetFrameLevel(f:GetFrameLevel() + 20)
    local arrow = Art(b, "Chevron", "OVERLAY")
    arrow:SetSize(12, 12); arrow:SetRotation(-math.pi / 2); Tint(arrow, P.ash)
    local txt = Text(b, "medium", 13, P.ash, "RIGHT")
    txt:SetPoint("RIGHT", b, "RIGHT", -4, 0); txt:SetText("Whole run")
    arrow:SetPoint("RIGHT", txt, "LEFT", -4, 0)
    b:SetScript("OnEnter", function(self2)
        Tint(arrow, P.ivory); txt:SetTextColor(P.ivory[1], P.ivory[2], P.ivory[3])
        GameTooltip:SetOwner(self2, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Back to the whole run", P.ivory[1], P.ivory[2], P.ivory[3])
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

-- "Abandon run": on the run in progress (or paused), two clicks.
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
        txt:SetText(armed and "Click again to abandon" or "Abandon run")
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
        GameTooltip:SetText("Abandon run", P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:AddLine("Ends this run now and saves it as abandoned. A new run starts the next "
            .. "time you enter a dungeon.", 0.8, 0.8, 0.8, true)
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
        print("|cffff4444[MythicScoreboard]|r Scoreboard refresh error: " .. tostring(err))
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
            print("|cffff4444[MythicScoreboard]|r Scoreboard refresh error: " .. tostring(err))
        end
        if UI.frame and UI.frame.RefreshHistBtn then UI.frame.RefreshHistBtn() end
    end)
end

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

local function IsPersonalBest(run)
    if not (run.completed and run.inTime and (run.keystoneLevel or 0) > 0 and MythicScoreboardDB) then
        return false
    end
    local thisDur = run.duration or 0
    if thisDur <= 0 then return false end
    local key = (run.dungeonName or "") .. ":" .. (run.keystoneLevel or 0)
    local pb = MythicScoreboardDB.personalBests and MythicScoreboardDB.personalBests[key]
    if pb then return thisDur <= pb end
    for _, r in ipairs(MythicScoreboardDB.runs or {}) do
        if r ~= run and r.completed and r.inTime and r.dungeonName == run.dungeonName
                and (r.keystoneLevel or 0) == (run.keystoneLevel or 0) then
            local d = r.duration or 0
            if d > 0 and d < thisDur then return false end
        end
    end
    return true
end

local function RefreshHeader(run)
    if not run then
        UI.frame.DungeonName:SetText("Dungeon Scoreboard")
        UI.frame.SetBadge(nil)
        UI.frame.Subline:SetText("No runs yet. Enter a dungeon you track and the scoreboard fills in as you play.")
        UI.frame.PBLabel:Hide()
        UI.frame.LayoutAffixIcons(0)
        if UI.frame.WholeRunBtn then UI.frame.WholeRunBtn:Hide() end
        if UI.frame.AbandonBtn then UI.frame.AbandonBtn:Hide() end
        return
    end

    local isMPlus = (run.keystoneLevel or 0) > 0
    local title = UI.frame.DungeonName
    title:SetText(run.dungeonName or "?")
    SetFont(title, "title", 24)
    if title:GetStringWidth() > 560 then SetFont(title, "title", 19) end

    if isMPlus then UI.frame.SetBadge("+" .. run.keystoneLevel, true)
    elseif not MS.Flavor.difficulties then UI.frame.SetBadge(nil)
    else UI.frame.SetBadge(DiffShort(run), false) end

    -- Subline: [mode]  [time]  [result]  [deaths]
    local parts = {}
    local dur = MS:GetRunDuration(run)
    local limit = tonumber(run.keystoneTimeLimit)
    if isMPlus then _ins(parts, "Mythic Keystone") end
    if isMPlus and limit and limit > 0 then
        _ins(parts, CT(P.ivory, MS:FormatTime(dur)) .. " / " .. MS:FormatTime(limit))
    else
        _ins(parts, CT(P.ivory, MS:FormatTime(dur)))
    end

    local live = (run == MS.currentRun and MS.inDungeon and not run.completed)
    if run.completed then
        if isMPlus and limit and limit > 0 then
            local diff = _abs(limit - dur)
            if run.inTime then _ins(parts, CT(P.verd, "In time, " .. MS:FormatTime(diff) .. " to spare"))
            else _ins(parts, CT(P.avoid, "Over time by " .. MS:FormatTime(diff))) end
        elseif isMPlus then
            _ins(parts, run.inTime and CT(P.verd, "In time") or CT(P.avoid, "Over time"))
        else
            _ins(parts, CT(P.verd, "Cleared"))
        end
    elseif live then
        _ins(parts, CT(P.bronzeHi, "In progress"))
    else
        _ins(parts, "Abandoned")
    end

    if MS.Flavor.bossProgress and not isMPlus then
        local killed, total = MS:ForeverBossProgress(run)
        if total then
            _ins(parts, CT(P.ivory, killed .. " of " .. total) .. " bosses")
        else
            local n = 0
            for _, b in ipairs(run.bosses or {}) do if b.killTime then n = n + 1 end end
            _ins(parts, n .. (n == 1 and " boss" or " bosses") .. " killed")
        end
        local lo, hi = MS:ForeverLevelRange(run)
        if lo then _ins(parts, "Levels " .. lo .. "-" .. hi) end
    end

    local deaths = 0
    for _, p in pairs(run.players or {}) do deaths = deaths + (p.deaths or 0) end
    if deaths == 0 then
        _ins(parts, "No deaths")
    else
        local s = deaths .. " death" .. (deaths == 1 and "" or "s")
        local penalty = run.deathPenaltySeconds or 0
        if isMPlus and penalty > 0 then s = s .. ", -" .. MS:FormatTime(penalty) end
        _ins(parts, CT(P.blood, s))
    end
    UI.frame.Subline:SetText(table.concat(parts, "      "))

    UI.frame.PBLabel:SetShown(IsPersonalBest(run))

    -- Affixes
    local affixIDs = {}
    for _, af in ipairs(run.affixes or {}) do _ins(affixIDs, af.id or af) end
    if #affixIDs == 0 and isMPlus and C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
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
    local boss = FocusedBoss(run)
    local wr = WholeRunButton()
    wr:SetShown(boss ~= nil)
    wr:ClearAllPoints()
    if canAbandon then wr:SetPoint("RIGHT", ab, "LEFT", -12, 0)
    else wr:SetPoint("TOPRIGHT", UI.frame, "TOPRIGHT", -14, -54) end
    if not boss then return end
    UI.frame.PBLabel:Hide()
    local isWipe = boss.wipeTime and not boss.killTime
    local endT = FightEnd(run, boss)
    local fp = {
        CT(P.bronzeHi, boss.name or "Boss"),
        "Fight " .. CT(P.ivory, MS:FormatTime(endT - (boss.pullTime or 0))),
        isWipe and CT(P.blood, "Wipe at " .. MS:FormatTime(endT)) or ("Killed at " .. CT(P.ivory, MS:FormatTime(endT))),
    }
    local fd = 0
    for _, p in pairs(run.players or {}) do
        for _, de in ipairs(p.deathEvents or {}) do
            if (de.time or 0) >= (boss.pullTime or 0) and (de.time or 0) <= endT then fd = fd + 1 end
        end
    end
    _ins(fp, fd == 0 and "No deaths" or CT(P.blood, fd .. (fd == 1 and " death" or " deaths")))
    if not boss.stats then
        local waiting = run == MS.currentRun and (boss._session or boss._before)
        _ins(fp, CT(P.ash2, waiting and "Damage and healing appear once you're out of combat"
            or "Damage and healing weren't recorded for this fight"))
    end
    UI.frame.Subline:SetText(table.concat(fp, "      "))
end

local function BossSig(r)
    if not r or not r.bosses then return "" end
    local last, icons = 0, 0
    for _, b in ipairs(r.bosses) do
        local e = b.killTime or b.wipeTime or 0
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
    UI.frame._tlRun = run
    if not UI.frame._rebuildTimeline then
        UI.frame._rebuildTimeline = function(force)
            if UI.frame._tlRebuilding then return end
            local r   = UI.frame._tlRun
            local sig = BossSig(r)
            local changed = (r ~= UI.frame._tlLastBuiltRun) or (sig ~= (UI.frame._tlLastBossSig or ""))
            -- Redrawn only when the run or what's on it changed (or forced).
            if not force and not changed and UI.frame._tlLastBuild then return end
            UI.frame._tlLastBuild    = GetTime()
            UI.frame._tlLastBuiltRun = r
            UI.frame._tlLastBossSig  = sig
            UI.frame._tlRebuilding   = true

            local tlc = UI.frame.timelineContainer
            if r then
                -- Saved runs without portraits: fill them in from the guide.
                for _, b in ipairs(r.bosses or {}) do
                    if not BossIcon(b) then MS:_BuildEJIndex(); break end
                end
                tlc:Show()
                local totalDur = GetTimelineDuration(r)
                UI.frame._tlTotalDur = totalDur
                local ok, err = pcall(BuildTimeline, tlc, r, totalDur)
                if not ok then
                    print("|cffff4444[MythicScoreboard]|r Timeline build error: " .. tostring(err))
                    UI.frame._tlLastBuild = GetTime() + 2.0
                    tlc:Hide()
                end
            else
                tlc:Hide()
            end
            UI.frame._tlRebuilding = false
        end
    end
    UI.frame._rebuildTimeline()

    local tlc = UI.frame.timelineContainer
    if tlc.UpdateLive and UI.frame._tlRun then
        tlc.UpdateLive(UI.frame._tlRun, UI.frame._tlTotalDur or GetTimelineDuration(UI.frame._tlRun))
    end

    -- ── Player rows ──────────────────────────────────────────────────────
    local sf      = UI.overviewSF
    local content = sf.scrollContent

    local runSeq  = run and (run._seq or 0) or -1
    local focus   = run and FocusedBoss(run)
    local focusSig = focus and (tostring(focus) .. (focus.stats and "+" or "")) or ""
    local rowsDirty = (run ~= UI.frame._lastRowsRun)
                   or (focusSig ~= UI.frame._lastFocusSig)
                   or (runSeq ~= (UI.frame._lastRowsSeq or -2))
                   or (sortState.key ~= UI.frame._lastRowsSortKey)
                   or (sortState.dir ~= UI.frame._lastRowsSortDir)
                   or ((MS._lootRev or 0) ~= UI.frame._lastLootRev)
    if not rowsDirty then return end
    UI.frame._lastLootRev = MS._lootRev or 0
    UI.frame._lastRowsRun     = run
    UI.frame._lastFocusSig    = focusSig
    UI.frame._lastRowsSeq     = runSeq
    UI.frame._lastRowsSortKey = sortState.key
    UI.frame._lastRowsSortDir = sortState.dir

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
        UI.frame._emptyLbl:SetText("Your group's damage, healing, deaths and interrupts will show here.")
        UI.frame._emptyLbl:Show()
        _ins(overviewRows, UI.frame._emptyLbl)
        content:SetHeight(60); sf.UpdateRange()
        return
    end

    local dur = self:GetRunDuration(run)
    if focus then run, dur = FightView(run, focus) end
    wipe(_playersBuf)
    for _, p in pairs(run.players) do _ins(_playersBuf, p) end
    local players = _playersBuf

    if sortState.key and COL_SORT_VALUES[sortState.key] then
        local getter, dir = COL_SORT_VALUES[sortState.key], sortState.dir
        local isStr = sortState.key == "player"
        _sort(players, function(a, b)
            if not a or not b then return false end
            local av, bv = getter(a), getter(b)
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

    -- In a column where some values read "25.8K", a plain "549" lines up
    -- with their right edge instead of their decimal point.
    local hasSuffix = {}
    for _, c in ipairs(COLS) do
        if c.num == "abbr" then
            for _, p in ipairs(players) do
                if (tonumber((COL_RENDERERS[c.key](p, dur, run))) or 0) >= 1000 then hasSuffix[c.key] = true; break end
            end
        end
    end

    -- Top values drive the share bars under DPS and HPS.
    local topDps, topHps = 0, 0
    for _, p in ipairs(players) do
        topDps = _max(topDps, RateOf(p, "dps", "damageDone", dur))
        topHps = _max(topHps, RateOf(p, "hps", "healingDone", dur))
    end
    -- Share bars run from the value's right edge back toward the column start.
    local dpsCellW, hpsCellW
    for _, c in ipairs(COLS) do
        if c.key == "dps" then dpsCellW = c.anchor + c.tailW - (c.x + 10) end
        if c.key == "hps" then hpsCellW = c.anchor + c.tailW - (c.x + 10) end
    end

    local yOff, localName = 0, MS:UnitPlayerName("player")
    for idx, p in ipairs(players) do
        local hasLeft = p.left == true
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

        row._stripe:SetShown(idx % 2 == 0)
        row._selfBg:SetShown(isSelf)
        row._selfLine:SetShown(isSelf)

        local cr, cg, cb = ClassColor(p.class)
        local dim = hasLeft and 0.4 or 1
        row._bar:SetColorTexture(cr * dim, cg * dim, cb * dim, 1)
        HGrad(row._wash, {cr, cg, cb}, {cr, cg, cb}, hasLeft and 0.06 or 0.17, 0)
        row._sep:SetShown(idx < #players)

        local cc = CLASS_ICON_COORDS[p.class] or CLASS_ICON_COORDS.UNKNOWN
        row._classIcon:SetTexCoord(cc[1], cc[2], cc[3], cc[4])
        row._classIcon:SetDesaturated(hasLeft)

        local role = GetRole(p)
        row._roleIcon:SetTexture(ROLE_ICON_TEX)
        if GetTexCoordsForRoleSmallCircle then
            row._roleIcon:SetTexCoord(GetTexCoordsForRoleSmallCircle(role))
        else
            local rc = ROLE_ICON_COORDS[role] or ROLE_ICON_COORDS.DAMAGER
            row._roleIcon:SetTexCoord(rc[1], rc[2], rc[3], rc[4])
        end

        row._nameFs:SetText(DN(p.name) or "?")
        row._nameFs:SetTextColor(cr * dim, cg * dim, cb * dim)
        if hasLeft then
            row._subFs:SetText("Left the group")
        elseif (p.itemLevel or 0) > 0 then
            row._subFs:SetText(p.itemLevel .. " item level")
        else
            row._subFs:SetText("")
        end

        local fade = hasLeft and 0.6 or 1
        for _, col in ipairs(COLS) do
            local cell = row._statFs[col.key]
            if cell then
                local val, vr, vg, vb = COL_RENDERERS[col.key](p, dur, run)
                vr, vg, vb = vr * fade, vg * fade, vb * fade
                if col.num == "abbr" then
                    local int, dec, suf = SplitAbbrev(tonumber(val) or 0)
                    cell.main:SetText(int)
                    cell.shifted = (suf == "" and hasSuffix[col.key]) and col.kW or 0
                    cell.main:ClearAllPoints()
                    cell.main:SetPoint("RIGHT", row, "LEFT", col.anchor + cell.shifted, 0)
                    -- Suffix a step dimmer than the number.
                    local sufHex = _fmt("%02x%02x%02x", _floor(vr * 160), _floor(vg * 160), _floor(vb * 160))
                    cell.tail:SetText(dec .. (suf ~= "" and ("|cff" .. sufHex .. suf .. "|r") or ""))
                    cell.tail:SetTextColor(vr, vg, vb)
                else
                    cell.main:SetText(tostring(val))
                end
                cell.main:SetTextColor(vr, vg, vb)
            end
        end

        local loot = p.loot or {}
        local nLoot = #loot
        local shown = (nLoot > 3) and 2 or nLoot
        for i = 1, 3 do row._loot[i]:SetEntry(i <= shown and loot[i] or nil) end
        row._lootMore:SetShown(nLoot > 3)
        if nLoot > 3 then row._lootMore:SetText("+" .. (nLoot - 2)) end
        row._lootNone:SetShown(nLoot == 0)

        local dpsV = RateOf(p, "dps", "damageDone", dur)
        local hpsV = RateOf(p, "hps", "healingDone", dur)
        local db, hb = row._shareBar.dps, row._shareBar.hps
        -- Each bar ends under the right edge of the number actually shown
        -- (with or without a ".2K"), so a short bar sits under its number.
        for _, c in ipairs(COLS) do
            local bar = row._shareBar[c.key]
            if bar then
                local cell = row._statFs[c.key]
                local tail = cell.tail
                local tw = (tail and tail:GetText() ~= "") and tail:GetStringWidth() or (cell.shifted or 0)
                bar:ClearAllPoints()
                bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", c.anchor + tw, 9)
            end
        end
        if topDps > 0 and dpsV > 0 then
            db:SetWidth(_max(2, dpsCellW * dpsV / topDps)); db:Show()
        else db:Hide() end
        -- Healers always; anyone else when their healing is a real share
        -- (a quarter of the top healer's or more), not incidental.
        if topHps > 0 and hpsV > 0 and (role == "HEALER" or hpsV >= topHps * 0.25) then
            hb:SetWidth(_max(2, hpsCellW * hpsV / topHps)); hb:Show()
        else hb:Hide() end

        row._player = p
        row._run    = run

        yOff = yOff - ROW_H
        _ins(overviewRows, row)
    end
    for k = 1, #players do prevRows[k] = nil end
    for k, r in pairs(prevRows) do ReleaseRow(r) end   -- rows no longer needed (and the empty label)
    if UI.frame._emptyLbl then UI.frame._emptyLbl:Hide() end

    content:SetHeight(_max(60, _abs(yOff)))
    sf.UpdateRange()
end

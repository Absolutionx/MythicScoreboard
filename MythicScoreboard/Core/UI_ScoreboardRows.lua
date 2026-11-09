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

-- Scoreboard, the player rows: each row's frames (made once, then reused),
-- its loot icons and tooltip, the numbers in each column, and filling a row
-- in. UI_Scoreboard.lua lays the rows out and refreshes them, through UI.Rows.

local _rowPool = {}       -- rows handed back, for reuse

-- ── Loot icons ──────────────────────────────────────────────────────────

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetInfo    = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Link, quality, icon and item level for a loot entry. What the game fills
-- in later is remembered here, beside the entry; saved data isn't changed
-- by drawing it.
local _looked = setmetatable({}, { __mode = "k" })
local function LootDetails(entry)
    local known = _looked[entry]
    if not known then known = {}; _looked[entry] = known end
    local item = MS.LootItemString(entry)
    local link = entry.link or known.link
    local quality = entry.quality or known.quality
    local ilvl = entry.ilvl or known.ilvl
    if GetInfo and not (link and quality) then
        local ok, _, fullLink, q = pcall(GetInfo, link or item)
        if ok then
            link = link or fullLink; known.link = link
            quality = quality or q; known.quality = quality
        end
    end
    local icon
    if GetInstant then
        local ok, _, _, _, _, ic = pcall(GetInstant, item)
        if ok then icon = ic end
    end
    if not ilvl and C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, lvl = pcall(C_Item.GetDetailedItemLevelInfo, link or item)
        if ok and lvl and lvl > 0 then ilvl = lvl; known.ilvl = lvl end
    end
    return link or item, quality, icon, ilvl
end

local QualityColor = UI.QualityColor

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

-- Healers who have an interrupt (Wind Shear / Earth Shock, Spear Hand
-- Strike, Quell), so "fewest in group" can apply to them.
local KICK_HEALERS = { SHAMAN = true, MONK = true, EVOKER = true }

-- One tooltip handler for every row; it reads the row's player and run.
local function RowOnEnter(self2)
    local pc = self2._player
    if not pc then return end
    GameTooltip:SetOwner(self2, "ANCHOR_CURSOR_RIGHT", 12, 12)
    local r2, g2, b2 = ClassColor(pc.class)
    GameTooltip:SetText(DN(pc.name) or "?", r2, g2, b2)
    local spec, specRole = MS.SpecLabel and MS.SpecLabel(pc.specID, pc.class)
    if spec then
        local role = (pc.role ~= "" and pc.role) or specRole
        local roleName = role and rawget(_G, role)
        GameTooltip:AddDoubleLine(spec, type(roleName) == "string" and roleName or "", r2, g2, b2, 1, 1, 1)
    end

    if (pc.level or 0) > 0 and MS.Flavor.dungeonLevels then
        local lo, hi = MS:ForeverLevelRange(self2._run)
        GameTooltip:AddDoubleLine(L["Level"], pc.level .. (lo and ("  (" .. _fmt(L["dungeon %d-%d"], lo, hi) .. ")") or ""),
            0.8, 0.8, 0.8, 1, 1, 1)
    end
    local sc = pc.mythicScore or 0
    if sc > 0 then
        local sr, sg, sb2 = ScoreColor(sc)
        local gain = (pc.ratingGain or 0) > 0 and (" " .. CT(P.verdHi, "(+" .. pc.ratingGain .. ")")) or ""
        GameTooltip:AddDoubleLine(L["Mythic+ rating"], sc .. gain, 0.8, 0.8, 0.8, sr, sg, sb2)
    end
    if (pc.itemLevel or 0) > 0 then
        GameTooltip:AddDoubleLine(L["Item level"], pc.itemLevel, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local avoid = pc.avoidableDamageTaken or 0
    if avoid > 0 then
        GameTooltip:AddDoubleLine(L["Avoidable damage"], Abbrev(avoid), 0.8, 0.8, 0.8, P.avoid[1], P.avoid[2], P.avoid[3])
    end

    -- Highest / lowest interrupt badge (healers other than Shaman excluded from "lowest").
    local intCount = pc.interrupts or 0
    local canKick = (pc.role ~= "HEALER") or KICK_HEALERS[pc.class]
    local badge = ""
    local rr = self2._run
    if rr and rr.players then
        local hi, lo, n, loN = 0, _huge, 0, 0
        for _, op in pairs(rr.players) do
            local v = op.interrupts or 0
            n = n + 1
            if v > hi then hi = v end
            if op.role ~= "HEALER" or KICK_HEALERS[op.class] then
                loN = loN + 1
                if v < lo then lo = v end
            end
        end
        if n > 1 then
            if intCount > 0 and intCount == hi then badge = "  |cffe7b877" .. L["most in group"] .. "|r"
            elseif loN > 1 and canKick and intCount == lo then badge = "  |cffe57068" .. L["fewest in group"] .. "|r" end
        end
    end
    if intCount > 0 or badge ~= "" then
        GameTooltip:AddDoubleLine(L["Interrupts"], intCount .. badge, 0.8, 0.8, 0.8, P.kick[1], P.kick[2], P.kick[3])
    end

    if pc.loot and #pc.loot > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Loot"], P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
        for _, e in ipairs(pc.loot) do
            local link, _, _, ilvl = LootDetails(e)
            local shownLink = (type(link) == "string" and link:find("|H")) and link or L["Item not loaded yet"]
            GameTooltip:AddDoubleLine("  " .. shownLink, ilvl and _fmt(L["ilvl %d"], ilvl) or "", 1, 1, 1, 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(" ")
    end

    local deathCount = pc.deaths or 0
    if deathCount == 0 then
        GameTooltip:AddDoubleLine(L["Deaths"], L["None"], 0.8, 0.8, 0.8, P.verdHi[1], P.verdHi[2], P.verdHi[3])
    else
        GameTooltip:AddDoubleLine(L["Deaths"], deathCount, 0.8, 0.8, 0.8, P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        if pc.deathEvents and #pc.deathEvents > 0 then
            GameTooltip:AddLine(" ")
            for _, de in ipairs(pc.deathEvents) do
                local dt = de.time or 0
                local segStr = ""
                for _, boss in ipairs((rr and rr.bosses) or {}) do
                    local pullT = boss.pullTime or 0
                    local killT = MS.FightEnd(boss) or rr.duration or _huge
                    if dt >= pullT and dt <= killT then
                        segStr = "  |cff999999" .. (boss.name or "?") .. MS.FightTag(boss)
                            .. ", " .. _fmt(L["%s into the fight"], MS:FormatTime(dt - pullT)) .. "|r"
                        break
                    end
                end
                GameTooltip:AddLine("|cffff9900" .. MS:FormatTime(dt) .. "|r" .. segStr, 1, 1, 1)
                do
                    local kill = MS.KillingBlow(de.events)
                    if kill then
                        local line = "  |cffff9944" .. (kill.spellName or L["Unknown"]) .. "|r"
                        if kill.caster and kill.caster ~= "" then
                            line = "  " .. _fmt(L["%s |cff888888by|r %s"], "|cffff9944" .. (kill.spellName or L["Unknown"]) .. "|r",
                                "|cffffd700" .. kill.caster .. "|r")
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
            if col.key == "score" then
                row._scoreAnchor = col.anchor
                -- Your rating gain from this key, centred under the rating.
                local gain = Text(row, "medium", 11, P.verdHi, "CENTER")
                gain:SetPoint("TOP", main, "BOTTOM", 0, 1)
                row._gainFs = gain
            end
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

-- One player's row: colours, icons, name, the numbers, loot and share bars.
-- ctx: run, dur (the whole run's or the focused fight's), hasSuffix, topDps,
-- topHps, dpsCellW, hpsCellW, count (rows in all).
local function FillRow(row, idx, p, isSelf, ctx)
    local run, dur = ctx.run, ctx.dur
    local hasSuffix, topDps, topHps = ctx.hasSuffix, ctx.topDps, ctx.topHps
    local dpsCellW, hpsCellW = ctx.dpsCellW, ctx.hpsCellW
    local hasLeft = p.left == true
    row._stripe:SetShown(idx % 2 == 0)
    row._selfBg:SetShown(isSelf)
    row._selfLine:SetShown(isSelf)

    local cr, cg, cb = ClassColor(p.class)
    local dim = hasLeft and 0.4 or 1
    row._bar:SetColorTexture(cr * dim, cg * dim, cb * dim, 1)
    HGrad(row._wash, {cr, cg, cb}, {cr, cg, cb}, hasLeft and 0.06 or 0.17, 0)
    row._sep:SetShown(idx < ctx.count)

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

    UI.SetNameText(row._nameFs, DN(p.name) or "?")
    row._nameFs:SetTextColor(cr * dim, cg * dim, cb * dim)
    if hasLeft then
        row._subFs:SetText(L["Left the group"])
    elseif (p.itemLevel or 0) > 0 then
        row._subFs:SetText(_fmt(L["%d item level"], p.itemLevel))
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

    if row._gainFs then
        -- With a gain, the rating moves up so the two sit centred in the row.
        local g = p.ratingGain or 0
        row._gainFs:SetText(g > 0 and ("+" .. g) or "")
        local main = row._statFs.score.main
        local y = g > 0 and 5 or 0
        if main._msY ~= y then
            main:ClearAllPoints()
            main:SetPoint("RIGHT", row, "LEFT", row._scoreAnchor, y)
            main._msY = y
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
end

UI.Rows = {
    AcquireRow = AcquireRow, ReleaseRow = ReleaseRow, FillRow = FillRow,
    RateOf = RateOf, COL_RENDERERS = COL_RENDERERS,
}

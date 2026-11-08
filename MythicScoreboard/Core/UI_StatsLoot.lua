local _floor, _max, _min = math.floor, math.max, math.min
local _fmt = string.format

local MS = _G["MythicScoreboard"]
local L = MS.L
local LK = MS.LK      -- a label kept in English, translated where it is shown
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local P, PAD_X, HDR_H, COL_HDR_H, FRAME_W = UI.P, UI.PAD_X, UI.HDR_H, UI.COL_HDR_H, UI.FRAME_W
local Text, Solid, Btn, Tint, Art, Box = UI.Text, UI.Solid, UI.Btn, UI.Tint, UI.Art, UI.Box
local VGrad, MakeScrollFrame, ClassHex, CT, DN, Abbrev = UI.VGrad, UI.MakeScrollFrame, UI.ClassHex, UI.CT, UI.DN, UI.Abbrev
local FIGHT_BOT, FIGHT_TOP = UI.FIGHT_BOT, UI.FIGHT_TOP

-- Stats page, part 3: the Loot tab, every piece of gear that dropped for you,
-- newest first. Built and filled from UI_Stats.lua through UI.StatsKit.

local K = UI.StatsKit                  -- shared by UI_Stats.lua
local Band, Cells, CharName, Day, HoverRow = K.Band, K.Cells, K.CharName, K.Day, K.HoverRow
local LCOLS, LOOT_ROW, MAX_LOOT, Pool, S = K.LCOLS, K.LOOT_ROW, K.MAX_LOOT, K.Pool, K.S
local X0 = K.X0

-- ── Loot ───────────────────────────────────────────────────────────────────
local function ItemID(item) return tonumber(tostring(item or ""):match("item:(%d+)")) end

local function ItemName(l)
    local fromLink = l.l and l.l:match("|h%[(.-)%]|h")
    if fromLink then return fromLink end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name = pcall(get, MS.LootItemString(l))
    if ok and name then return name end
    return nil
end

local function ItemIcon(l)
    local id = ItemID(MS.LootItemString(l))
    if not id then return nil end
    local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    local ok, icon = pcall(get, id)
    return ok and icon or nil
end

local function QualityColor(q)
    if not q then return P.ivory end
    return { UI.QualityColor(q) }
end

-- Item names can arrive a moment after they're asked for.
local waitingForItems = false
local itemFrame = CreateFrame("Frame")
itemFrame:SetScript("OnEvent", function()
    if not waitingForItems then return end
    waitingForItems = false
    C_Timer.After(0.3, function() if UI.statsOpen and S.tab == "loot" then UI.RefreshStats(true) end end)
end)
pcall(itemFrame.RegisterEvent, itemFrame, "GET_ITEM_INFO_RECEIVED")

local function MakeLootRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_W - 2 * X0 - 10, LOOT_ROW)
    row:EnableMouse(true)
    HoverRow(row)
    row.cells = Cells(row, LCOLS, 14)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22); row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.cells.item:ClearAllPoints()
    row.cells.item:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.cells.item:SetWidth(LCOLS[1].w - 40)
    row:SetScript("OnEnter", function(self)
        local l = self.data and self.data.item
        if not l then return end
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("BOTTOMLEFT", self.icon, "TOPRIGHT", 4, 2)
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, l.l or MS.LootItemString(l)) then
            GameTooltip:SetText(ItemName(l) or L["Item"])
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Shift-click links it in chat, as with any item.
    row:SetScript("OnMouseUp", function(self)
        local l = self.data and self.data.item
        if l and HandleModifiedItemClick then pcall(HandleModifiedItemClick, l.l or MS.LootItemString(l)) end
    end)
    return row
end

local function BuildLoot(parent)
    local lv = CreateFrame("Frame", nil, parent)
    lv:SetAllPoints()
    local band = Band(lv, LCOLS, X0)
    band:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", lv, "TOPRIGHT", 0, 0)
    lv.band = band
    lv.sf = MakeScrollFrame(lv)
    lv.sf:SetPoint("TOPLEFT", lv, "TOPLEFT", X0, -COL_HDR_H)
    lv.sf:SetPoint("BOTTOMLEFT", lv, "BOTTOMLEFT", X0, 8)
    lv.sf:SetWidth(FRAME_W - 2 * X0)
    lv.rowAt, lv.rowsHideFrom = Pool(function() return MakeLootRow(lv.sf.scrollContent) end)
    lv.empty = Text(lv, "regular", 15, P.ash, "CENTER")
    lv.empty:SetPoint("CENTER", lv, "CENTER", 0, -10)
    lv.empty:SetWidth(560); lv.empty:SetWordWrap(true)
    lv.empty:SetText(L["No loot yet. Gear that drops for you in a dungeon is listed here."])
    return lv
end

local function FillLoot(lv, items)
    lv.band.labels.char:SetShown(S.multiChar)
    local y, n = 0, _min(#items, MAX_LOOT)
    for i = 1, n do
        local it = items[i]
        local l, e = it.item, it.run
        local row = lv.rowAt(i)
        row:SetPoint("TOPLEFT", lv.sf.scrollContent, "TOPLEFT", 0, -y)
        row.data = it
        row.icon:SetTexture(ItemIcon(l) or 134400)            -- question mark until known
        local name = ItemName(l)
        if not name then waitingForItems = true end
        local qc = QualityColor(l.q)
        row.cells.item:SetText(name or L["Loading..."])
        row.cells.item:SetTextColor(qc[1], qc[2], qc[3])
        row.cells.dungeon:SetText(e.dungeon or "?")
        row.cells.boss:SetText(l.b and CT(P.ash, l.b) or CT(P.ash2, L["Trash"]))
        row.cells.date:SetText(CT(P.ash, Day(e.at)))
        UI.SetNameText(row.cells.char, S.multiChar and CharName(MS:RunOwner(e)) or "")
        y = y + LOOT_ROW
    end
    lv.rowsHideFrom(n + 1)
    lv.sf.scrollContent:SetHeight(_max(1, y))
    lv.sf.UpdateRange()
    lv.empty:SetShown(n == 0)
end

K.BuildLoot, K.FillLoot = BuildLoot, FillLoot

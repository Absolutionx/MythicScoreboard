-- The Stats page's Loot tab: every piece of gear that dropped for you, newest
-- first, with its dungeon, boss and date. Items can be removed one at a
-- time (two clicks on the x) or all at once (Clear loot, after a yes).

local _max, _min = math.max, math.min
local _fmt = string.format

local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
-- Shared from earlier UI files (see UI_Theme.lua for the design tokens).
local P, COL_HDR_H, FRAME_W = UI.P, UI.COL_HDR_H, UI.FRAME_W
local Text, Btn, Tint, Art = UI.Text, UI.Btn, UI.Tint, UI.Art
local MakeScrollFrame, CT = UI.MakeScrollFrame, UI.CT

-- Stats page, part 3: the Loot tab, every piece of gear that dropped for you,
-- newest first. Built and filled from UI_Stats.lua through UI.StatsKit.

local K = UI.StatsKit                  -- shared by UI_Stats.lua
local Band, Cells, CharName, Day, HoverRow = K.Band, K.Cells, K.CharName, K.Day, K.HoverRow
local LCOLS, LOOT_ROW, MAX_LOOT, Pool, S = K.LCOLS, K.LOOT_ROW, K.MAX_LOOT, K.Pool, K.S
local TwoClick = K.TwoClick
local X0 = K.X0

-- ── Loot ───────────────────────────────────────────────────────────────────
local function ItemID(item) return tonumber(tostring(item or ""):match("item:(%d+)")) end

-- An item's name: from its link, or the game's item cache (nil until cached).
local function ItemName(l)
    local fromLink = l.l and l.l:match("|h%[(.-)%]|h")
    if fromLink then return fromLink end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name = pcall(get, MS.LootItemString(l))
    if ok and name then return name end
    return nil
end

-- Its icon, or a question mark until the game has the item.
local function ItemIcon(l)
    local id = ItemID(MS.LootItemString(l))
    if not id then return nil end
    local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    local ok, icon = pcall(get, id)
    return ok and icon or nil
end

-- The colour of a quality (green, blue, purple...).
local function QualityColor(q)
    if not q then return P.ivory end
    return { UI.QualityColor(q) }
end

-- Item names can arrive a moment after they're asked for.
local waitingForItems = false
MS:On("GET_ITEM_INFO_RECEIVED", function()
    if not waitingForItems then return end
    waitingForItems = false
    C_Timer.After(0.3, function() if UI.statsOpen and S.tab == "loot" then UI.RefreshStats(true) end end)
end)

-- One row of the list: icon, name, dungeon, boss, date, character, and the x.
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

    -- Remove this item from the list (two clicks). Your own items only. The
    -- first click marks the whole row in red and says so on the row itself;
    -- the second, within 3s, removes it.
    local del = Btn(row)
    del:SetSize(26, LOOT_ROW)
    del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    del:SetFrameLevel(row:GetFrameLevel() + 2)
    local icon = Art(del, "Close", "OVERLAY")
    icon:SetSize(11, 11); icon:SetPoint("CENTER"); Tint(icon, P.ash2)
    local armBg = UI.Solid(row, "BACKGROUND", 1, P.bloodHi[1], P.bloodHi[2], P.bloodHi[3], 0.16)
    armBg:SetAllPoints(); armBg:Hide()
    local armTxt = Text(row, "medium", 13, P.bloodHi, "RIGHT")
    armTxt:SetPoint("RIGHT", del, "LEFT", -4, 0)
    armTxt:SetText(L["Click again to remove"]); armTxt:Hide()
    row.armBg, row.armTxt = armBg, armTxt
    local function Tip(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Remove from loot list"], P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:AddLine(self.IsArmed() and L["Click again to remove this item."]
            or L["Your runs and stats are kept."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end
    TwoClick(del, function(armed)
        Tint(icon, (armed or del.hovered) and P.bloodHi or P.ash2)
        icon:SetSize(armed and 13 or 11, armed and 13 or 11)
        armBg:SetShown(armed); armTxt:SetShown(armed)
        row.cells.char:SetAlpha(armed and 0 or 1)       -- the message sits over it
        row.cells.date:SetAlpha(armed and 0 or 1)
        if del.hovered then Tip(del) end                 -- the tooltip follows at once
    end, function()
        GameTooltip:Hide()
        local it = row.data
        if it and MS:RemoveArchivedLoot(it.run, it.item) then UI.RefreshStats(true) end
    end)
    del:SetScript("OnEnter", function(self)
        self.hovered = true
        Tint(icon, P.bloodHi)
        Tip(self)
    end)
    del:SetScript("OnLeave", function(self)
        self.hovered = false
        if not self.IsArmed() then Tint(icon, P.ash2) end
        GameTooltip:Hide()
    end)
    row.del = del

    -- Shift-click links it in chat, as with any item.
    row:SetScript("OnMouseUp", function(self)
        local l = self.data and self.data.item
        if l and HandleModifiedItemClick then pcall(HandleModifiedItemClick, l.l or MS.LootItemString(l)) end
    end)
    return row
end

-- ── Clear loot ─────────────────────────────────────────────────────────────
-- Every item of this character's, after a yes in the game's own dialog.
local POPUP = "MYTHICSCOREBOARD_CLEAR_LOOT"

-- How many of the listed items are this character's (the only ones it can remove).
local function OwnItems(items)
    local n = 0
    for _, it in ipairs(items or MS:LootHistory()) do
        if MS:IsOwnRun(it.run) then n = n + 1 end
    end
    return n
end

-- Every item of this character's gone from the list (after the dialog's yes).
local function ClearNow()
    if MS:ClearLootHistory() > 0 then UI.RefreshStats(true) end
end

-- Clear loot: asks first, in the game's own Yes/No dialog.
function UI.AskClearLoot()
    local n = OwnItems()
    if n == 0 then return end
    local Dialogs = rawget(_G, "StaticPopupDialogs")
    local Show = rawget(_G, "StaticPopup_Show")
    if not (Dialogs and Show) then return end     -- no dialog, no clearing
    if not Dialogs[POPUP] then
        Dialogs[POPUP] = {
            text = "%s", button1 = rawget(_G, "YES") or "Yes", button2 = rawget(_G, "NO") or "No",
            timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1, preferredIndex = 3,
            OnAccept = function() ClearNow() end,
        }
    end
    local text = n == 1 and L["Remove the one item from your loot list?"]
        or _fmt(L["Remove %d items from your loot list?"], n)
    text = text .. "\n\n" .. L["Your runs and stats are kept."]
    if S.multiChar then text = text .. " " .. L["Only this character's items go. Your other characters keep theirs."] end
    Show(POPUP, text)
end

-- The tab: its column headers, the Clear loot button, the scrolling list.
local function BuildLoot(parent)
    local lv = CreateFrame("Frame", nil, parent)
    lv:SetAllPoints()
    local band = Band(lv, LCOLS, X0)
    band:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, 0); band:SetPoint("TOPRIGHT", lv, "TOPRIGHT", 0, 0)
    lv.band = band

    local clear = Btn(band)
    clear:SetSize(110, COL_HDR_H - 6)
    clear:SetPoint("RIGHT", band, "RIGHT", -(X0 + 4), 0)
    clear:SetFrameLevel(band:GetFrameLevel() + 2)
    local clearTxt = Text(clear, "medium", 13, P.ash2, "RIGHT")
    clearTxt:SetPoint("RIGHT", clear, "RIGHT", 0, 0); clearTxt:SetText(L["Clear loot"])
    clear:SetScript("OnClick", function() GameTooltip:Hide(); UI.AskClearLoot() end)
    clear:SetScript("OnEnter", function(self)
        clearTxt:SetTextColor(P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Clear loot"], P.bloodHi[1], P.bloodHi[2], P.bloodHi[3])
        GameTooltip:AddLine(L["Your runs and stats are kept."], 0.8, 0.8, 0.8, true)
        if S.multiChar then
            GameTooltip:AddLine(L["Only this character's items go. Your other characters keep theirs."], 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    clear:SetScript("OnLeave", function()
        clearTxt:SetTextColor(P.ash2[1], P.ash2[2], P.ash2[3])
        GameTooltip:Hide()
    end)
    lv.clear = clear
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

-- The list filled from LootHistory (Archive.lua), newest first.
local function FillLoot(lv, items)
    lv.band.labels.char:SetShown(S.multiChar)
    local y, n = 0, _min(#items, MAX_LOOT)
    for i = 1, n do
        local it = items[i]
        local l, e = it.item, it.run
        local row = lv.rowAt(i)
        row:SetPoint("TOPLEFT", lv.sf.scrollContent, "TOPLEFT", 0, -y)
        if not (row.data and row.data.item == it.item) then row.del.Disarm() end
        row.data = it
        row.del:SetShown(MS:IsOwnRun(e))       -- other characters' loot is changed on them
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
    lv.clear:SetShown(OwnItems(items) > 0)
end

K.BuildLoot, K.FillLoot = BuildLoot, FillLoot

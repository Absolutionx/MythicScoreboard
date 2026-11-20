local MS = _G["MythicScoreboard"]
local L = MS.L
local Readable = MS.Readable
local _fmt, _lower, _ins = string.format, string.lower, table.insert

-- ── Your blacklist ─────────────────────────────────────────────────────────
-- Players you'd rather not group with, each with a note. Kept for the
-- account (MythicScoreboardAccountDB.blacklist), so every character sees it:
--   [key] = { name = "Jay-Stormrage", note = "...", added = time(), class = "SHAMAN" }
-- A warning when one is in your group or invites you, a red border round
-- their listings in Looking For Group, and the note in their tooltips. The
-- window: UI_Blacklist.lua.

-- (WoW Forever only: Core/Flavor.lua's blacklist, and only its TOC loads
-- this file.)

-- The key a player is kept under, and how their name is shown: the
-- two-part name ("jay-breezy", "Jay Breezy"), however it was written. A
-- surname given apart (a menu's "server") is put back on.
function MS.BlacklistKey(name, surname)
    name = Readable(name)
    if type(name) ~= "string" or name == "" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if surname and not name:find("[%s%-]") then name = name .. "-" .. surname end
    local short = MS.ShortName(name)
    if type(short) ~= "string" or short == "" then return nil end
    return _lower(short), MS.DisplayName(short)
end

local function List(create)
    local acc = MS.AccountDB(create)
    if not acc then return nil end
    if create and type(acc.blacklist) ~= "table" then acc.blacklist = {} end
    return acc.blacklist
end

-- Anyone on it at all (nothing else is looked at until there is).
local function AnyoneListed()
    local list = List()
    return list ~= nil and next(list) ~= nil
end
MS.BlacklistHasAnyone = AnyoneListed

-- The entry for a player, or nil.
function MS:BlacklistEntry(name, realm)
    local list = List()
    if not list then return nil end
    local key = MS.BlacklistKey(name, realm)
    return key and list[key] or nil
end

local listeners = {}
function MS:OnBlacklistChanged(fn) _ins(listeners, fn) end
local function Changed()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then MS:ReportError("Blacklist", err) end
    end
end

-- Add a player (or change their note). Returns the entry.
function MS:AddToBlacklist(name, realm, note, class)
    local key, display = MS.BlacklistKey(name, realm)
    if not key then return nil end
    local list = List(true)
    local e = list[key]
    if not e then
        local acc = MS.AccountDB(true)
        acc.blacklistSeq = (acc.blacklistSeq or 0) + 1
        e = { name = display, added = time(), seq = acc.blacklistSeq }
    end
    e.note = Readable(note) or e.note or ""
    e.class = Readable(class) or e.class
    list[key] = e
    Changed()
    return e
end

function MS:RemoveFromBlacklist(name, realm)
    local key = MS.BlacklistKey(name, realm)
    local list = List()
    if not (key and list and list[key]) then return false end
    list[key] = nil
    Changed()
    return true
end

-- By the key it's kept under (the blacklist window).
function MS:RemoveBlacklistKey(key)
    local list = List()
    if not (key and list and list[key]) then return false end
    list[key] = nil
    Changed()
    return true
end

-- Every entry, newest first: { key, entry }.
function MS:BlacklistEntries()
    local out = {}
    for key, e in pairs(List() or {}) do _ins(out, { key = key, entry = e }) end
    table.sort(out, function(a, b)
        local ta, tb = a.entry.added or 0, b.entry.added or 0
        if ta ~= tb then return ta > tb end
        local sa, sb = a.entry.seq or 0, b.entry.seq or 0
        if sa ~= sb then return sa > sb end
        return a.key < b.key
    end)
    return out
end

-- A player from a run (the scoreboard): their name.
function MS:BlacklistNameOfPlayer(p)
    if type(p) ~= "table" or not p.name then return nil end
    return p.name
end

function MS:BlacklistEntryForPlayer(p)
    local name = MS:BlacklistNameOfPlayer(p)
    return name and MS:BlacklistEntry(name) or nil
end

-- A unit's name, as the blacklist reads it.
local function UnitKeyName(unit) return MS:UnitPlayerName(unit) end
MS._BlacklistUnitName = UnitKeyName

function MS:BlacklistEntryForUnit(unit)
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    if not (ok and isPlayer == true) then return nil end
    local name, realm = UnitKeyName(unit)
    return name and MS:BlacklistEntry(name, realm) or nil
end

-- ── In your group: a warning, once each time they join ────────────────────
-- Who's been warned about in this group is kept with the character, so a
-- /reload or a login with them still there doesn't warn again.
local RED = "|cffff2020"
local function Warned()
    local db = rawget(_G, "MythicScoreboardDB")
    if type(db) ~= "table" then return {} end
    if type(db.blacklistWarned) ~= "table" then db.blacklistWarned = {} end
    return db.blacklistWarned
end

local function Alert(text, note)
    MS.Say(RED .. text .. ((note or "") ~= "" and (": " .. note) or "") .. "|r")
    local frame = rawget(_G, "RaidWarningFrame")
    local Notice = rawget(_G, "RaidNotice_AddMessage")
    if frame and Notice then pcall(Notice, frame, text, { r = 1, g = 0.13, b = 0.13 }) end
    local Sound, kit = rawget(_G, "PlaySound"), rawget(_G, "SOUNDKIT")
    if Sound and kit and kit.RAID_WARNING then pcall(Sound, kit.RAID_WARNING) end
end

function MS:CheckGroupForBlacklist()
    local present, unsure = {}, false
    local warned = Warned()
    local grouped = IsInGroup and IsInGroup() or false
    if AnyoneListed() and grouped then
        local unknown = rawget(_G, "UNKNOWNOBJECT")
        for _, unit in ipairs(MS:GroupUnits()) do
            if unit ~= "player" then
                local name, realm = UnitKeyName(unit)
                local there = not UnitExists or UnitExists(unit)
                if there and (not name or name == unknown) then unsure = true end
                local key = name and MS.BlacklistKey(name, realm)
                local e = key and MS:BlacklistEntry(name, realm)
                if e then
                    present[key] = true
                    if not warned[key] and MS:GetBlacklistWarn() then
                        Alert(_fmt(L["%s from your blacklist is in your group"], e.name), e.note)
                    end
                end
            end
        end
    end
    -- Gone from the group: warned about again if they come back. (While
    -- some names aren't known yet, as just after a login, nobody's let go.)
    for key in pairs(warned) do
        if not present[key] and (not grouped or not unsure) then warned[key] = nil end
    end
    for key in pairs(present) do warned[key] = true end
end

-- ── An invite from them: a warning before you accept ──────────────────────
function MS:OnGroupInvite(inviter)
    if not AnyoneListed() then return end
    local name = Readable(inviter)
    local e = name and MS:BlacklistEntry(name)
    if not e then return end
    Alert(_fmt(L["%s, who invited you, is on your blacklist"], e.name), e.note)
    -- And under the game's invite box, once it's up.
    C_Timer.After(0, function()
        local Find = rawget(_G, "StaticPopup_FindVisible")
        local dialog = Find and Find("PARTY_INVITE")
        if dialog and MS.ShowBlacklistInviteWarning then
            local ok, err = pcall(MS.ShowBlacklistInviteWarning, MS, dialog, e)
            if not ok then MS:ReportError("Blacklist", err) end
        end
    end)
end
MS:On("PARTY_INVITE_REQUEST", function(_, inviter)
    local ok, err = pcall(MS.OnGroupInvite, MS, inviter)
    if not ok then MS:ReportError("Blacklist", err) end
end)

local function Check()
    MS:InvalidateGroupUnits()
    local ok, err = pcall(MS.CheckGroupForBlacklist, MS)
    if not ok then MS:ReportError("Blacklist", err) end
end
MS:On("GROUP_ROSTER_UPDATE", Check)
MS:On("PLAYER_ENTERING_WORLD", Check)
-- (Names can come in a moment after the roster.)
MS:On("UNIT_NAME_UPDATE", function(_, unit)
    if type(unit) == "string" and (unit:find("^party") or unit:find("^raid")) then Check() end
end)
-- Someone added while they're with you: said straight away (a changed
-- note isn't said again).
MS:OnBlacklistChanged(function() MS:CheckGroupForBlacklist() end)

-- ── Tooltips: the note ────────────────────────────────────────────────────
local function NoteLines(tooltip, e)
    tooltip:AddLine(L["On your blacklist"], 1, 0.13, 0.13)
    if (e.note or "") ~= "" then tooltip:AddLine(e.note, 1, 0.55, 0.55, true) end
end

local function UnitTooltip(tooltip)
    if not AnyoneListed() or tooltip ~= rawget(_G, "GameTooltip") or not tooltip.GetUnit then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and Readable(unit)
    if not unit then return end
    local e = MS:BlacklistEntryForUnit(unit)
    if e then NoteLines(tooltip, e); tooltip:Show() end
end

-- ── Looking For Group: a red border round their listings ──────────────────
local BRIGHT_RED = { 1, 0.1, 0.1 }
local function Red(fs)
    if fs and fs.SetTextColor then fs:SetTextColor(BRIGHT_RED[1], BRIGHT_RED[2], BRIGHT_RED[3]) end
end

local function LFG() return rawget(_G, "C_LFGList") end

-- A bright red border around a whole listing (made the first time it's
-- needed, then shown or hidden as the game reuses the frame).
local EDGE = 2
local function SetBorder(frame, on)
    if not (frame and frame.CreateTexture) then return end
    local b = frame._msBlacklistBorder
    if not b then
        if not on then return end
        b = {}
        for i = 1, 4 do
            b[i] = frame:CreateTexture(nil, "OVERLAY", nil, 7)
            b[i]:SetColorTexture(BRIGHT_RED[1], BRIGHT_RED[2], BRIGHT_RED[3], 1)
        end
        local inset = 2
        b[1]:SetPoint("TOPLEFT", inset, -inset);    b[1]:SetPoint("TOPRIGHT", -inset, -inset);    b[1]:SetHeight(EDGE)
        b[2]:SetPoint("BOTTOMLEFT", inset, inset);  b[2]:SetPoint("BOTTOMRIGHT", -inset, inset);  b[2]:SetHeight(EDGE)
        b[3]:SetPoint("TOPLEFT", inset, -inset);    b[3]:SetPoint("BOTTOMLEFT", inset, inset);    b[3]:SetWidth(EDGE)
        b[4]:SetPoint("TOPRIGHT", -inset, -inset);  b[4]:SetPoint("BOTTOMRIGHT", -inset, inset);  b[4]:SetWidth(EDGE)
        frame._msBlacklistBorder = b
    end
    for i = 1, 4 do b[i]:SetShown(on and true or false) end
end
MS._BlacklistBorder = SetBorder

local function LeaderOf(resultID)
    local C = LFG()
    if not (C and C.GetSearchResultInfo and resultID) then return nil end
    local ok, info = pcall(C.GetSearchResultInfo, resultID)
    return ok and type(info) == "table" and Readable(info.leaderName) or nil
end

MS._BlacklistLeaderOf = LeaderOf

local hooked = {}
local function Hook(name, fn)
    if hooked[name] or type(rawget(_G, name)) ~= "function" then return end
    hooked[name] = true
    hooksecurefunc(name, function(...)
        local ok, err = pcall(fn, ...)
        if not ok then MS:ReportError("Blacklist", err) end
    end)
end

-- WoW Forever's own Looking For Group window (Blizzard's classic style):
-- a red border around a listing when anyone in it is on your blacklist,
-- and their name in red in the listing's member tooltip.
local function MembersOf(resultID)
    local C = LFG()
    local out = {}
    if not (C and resultID) then return out end
    local leader = LeaderOf(resultID)
    if leader then out[#out + 1] = leader end
    local ok, info = pcall(C.GetSearchResultInfo, resultID)
    local n = ok and type(info) == "table" and MS.ReadableNumber(info.numMembers) or 0
    if C.GetSearchResultPlayerInfo then
        for i = 1, math.min(n, 40) do
            local okm, m = pcall(C.GetSearchResultPlayerInfo, resultID, i)
            local name = okm and type(m) == "table" and Readable(m.name)
            if name and name ~= leader then out[#out + 1] = name end
        end
    end
    return out
end
MS._BlacklistMembersOf = MembersOf

local function AnyListed(resultID)
    if not AnyoneListed() then return false end
    for _, name in ipairs(MembersOf(resultID)) do
        if MS:BlacklistEntry(name) then return true end
    end
    return false
end

local lastEntry, lastEntryAt  -- the listing last right-clicked: its menu comes next
local function HookBrowse()
    Hook("LFGBrowseSearchEntry_Update", function(entry)
        if entry then SetBorder(entry, AnyListed(entry.resultID)) end
    end)
    Hook("LFGBrowseSearchEntryTooltip_UpdateAndShow", function(tip)
        if not AnyoneListed() then return end
        local function RedIfListed(fs)
            local name = fs and fs.GetText and Readable(fs:GetText())
            if name and MS:BlacklistEntry(name) then Red(fs) end
        end
        RedIfListed(tip and tip.Leader and tip.Leader.Name)
        if tip and tip.memberPool and tip.memberPool.EnumerateActive then
            for frame in tip.memberPool:EnumerateActive() do RedIfListed(frame.Name) end
        end
    end)
    -- Which listing a right-click is on: seen as the button goes down, before
    -- the game opens its menu on the way up.
    Hook("LFGBrowseSearchEntry_Init", function(entry)
        if entry and not entry._msBlacklistWatch and entry.HookScript then
            entry._msBlacklistWatch = true
            entry:HookScript("OnMouseDown", function(self, button)
                if button == "RightButton" then lastEntry, lastEntryAt = self, GetTime() end
            end)
        end
    end)
end

-- The listing a menu being built is for, or nil: the Looking For Group
-- window is open, and the listing is under the mouse (or was right-clicked
-- a moment ago).
local function BrowseEntryForMenu(owner)
    local browse = rawget(_G, "LFGBrowseFrame")
    if not (browse and browse.IsVisible and browse:IsVisible()) then return nil end
    if owner and browse.SearchEntryDropDown and owner == browse.SearchEntryDropDown and lastEntry then
        return lastEntry
    end
    local Foci = rawget(_G, "GetMouseFoci")
    if Foci then
        local ok, list = pcall(Foci)
        for _, f in ipairs(ok and type(list) == "table" and list or {}) do
            local frame = f
            for _ = 1, 4 do                           -- (the listing, or something on it)
                if not frame then break end
                if frame.resultID and frame.Name and frame.GetParent then return frame end
                frame = frame.GetParent and frame:GetParent()
            end
        end
    end
    if lastEntry and lastEntryAt and GetTime() - lastEntryAt < 1 then return lastEntry end
    return nil
end

-- Its right-click menu has no name to add to, so the add is made as the
-- game builds that one menu.
local populateHooked
local function HookBrowseMenu()
    local Menu = rawget(_G, "Menu")
    if populateHooked or not (Menu and type(Menu.PopulateDescription) == "function") then return end
    populateHooked = true
    hooksecurefunc(Menu, "PopulateDescription", function(_, owner, root)
        local entry = BrowseEntryForMenu(owner)
        if not entry then return end
        local ok, err = pcall(function()
            local names = MembersOf(entry.resultID)
            MS:AddBlacklistMenuItems(root, names[1])
            -- Anyone else in the group: one by one, under their own heading.
            if #names > 1 then
                local sub = root:CreateButton(L["Someone else in this group"])
                for i = 2, #names do
                    local name = names[i]
                    local listed = MS:BlacklistEntry(name)
                    local _, shown = MS.BlacklistKey(name)
                    sub:CreateButton((listed and "|cffff4040" or "") .. (shown or name) .. (listed and "|r" or ""),
                        function() MS:AskBlacklistNote(name) end)
                end
            end
        end)
        if not ok then MS:ReportError("Blacklist", err) end
    end)
end

-- Redrawn when the list changes, if Looking For Group is open.
local function RefreshGroupFinder()
    local browse = rawget(_G, "LFGBrowseFrame")
    local BrowseUpdate = rawget(_G, "LFGBrowseSearchEntry_Update")
    local box = browse and browse.ScrollBox
    if box and box.ForEachFrame and BrowseUpdate and browse:IsVisible() then
        box:ForEachFrame(function(entry) pcall(BrowseUpdate, entry) end)
    end
end
MS:OnBlacklistChanged(RefreshGroupFinder)

-- ── Right-click menus: add, change the note, remove ───────────────────────
local function MenuName(contextData)
    if type(contextData) ~= "table" then return nil end
    local unit = Readable(contextData.unit)
    if unit then
        local ok, isPlayer = pcall(UnitIsPlayer, unit)
        if not ok or isPlayer ~= true then return nil end
        local okSelf, isSelf = pcall(rawget(_G, "UnitIsUnit") or error, unit, "player")
        if okSelf and isSelf == true then return nil end
        return UnitKeyName(unit)
    end
    local name = Readable(contextData.name)
    if not name then return nil end
    return name, Readable(contextData.server)
end

local MENUS = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_RAID",
    "MENU_UNIT_FRIEND", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_MEMBER", "MENU_UNIT_GUILD",
}

-- Adds the blacklist choices to a menu (also the scoreboard's).
function MS:AddBlacklistMenuItems(root, name, realm, class)
    if not (root and name and MS.BlacklistKey(name, realm)) then return end
    local e = MS:BlacklistEntry(name, realm)
    root:CreateDivider()
    if e then
        root:CreateButton(L["Change blacklist note"], function() MS:AskBlacklistNote(name, realm, class) end)
        root:CreateButton("|cffff4040" .. L["Remove from blacklist"] .. "|r",
            function() MS:RemoveFromBlacklist(name, realm) end)
    else
        root:CreateButton("|cffff4040" .. L["Add to blacklist"] .. "|r",
            function() MS:AskBlacklistNote(name, realm, class) end)
    end
end

local menusHooked, tooltipHooked
local function HookMenus()
    local Menu = rawget(_G, "Menu")
    if menusHooked or not (Menu and Menu.ModifyMenu) then return end
    menusHooked = true
    for _, tag in ipairs(MENUS) do
        pcall(Menu.ModifyMenu, tag, function(_, root, contextData)
            local ok, err = pcall(function()
                local name, realm = MenuName(contextData)
                local unit = type(contextData) == "table" and Readable(contextData.unit)
                local class = unit and select(2, UnitClass(unit))
                MS:AddBlacklistMenuItems(root, name, realm, class)
            end)
            if not ok then MS:ReportError("Blacklist", err) end
        end)
    end
end

-- ── The note: asked in a small box ────────────────────────────────────────
local POPUP = "MYTHICSCOREBOARD_BLACKLIST"
local function EditBoxOf(dialog)
    if dialog.GetEditBox then return dialog:GetEditBox() end
    return dialog.editBox or dialog.EditBox
end

local function Save(dialog, data)
    local eb = EditBoxOf(dialog)
    local note = eb and eb:GetText() or ""
    MS:AddToBlacklist(data.name, data.realm, note, data.class)
end

function MS:AskBlacklistNote(name, realm, class)
    local key, display = MS.BlacklistKey(name, realm)
    if not key then return end
    local Dialogs = rawget(_G, "StaticPopupDialogs")
    local Show = rawget(_G, "StaticPopup_Show")
    if not (Dialogs and Show) then
        MS:AddToBlacklist(name, realm, nil, class)
        return
    end
    if not Dialogs[POPUP] then
        Dialogs[POPUP] = {
            text = "%s", button1 = rawget(_G, "SAVE") or "Save", button2 = rawget(_G, "CANCEL") or "Cancel",
            hasEditBox = 1, maxLetters = 250, editBoxWidth = 260,
            timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
            OnShow = function(dialog, data)
                local eb = EditBoxOf(dialog)
                if eb then eb:SetText(data and data.note or ""); eb:HighlightText(); eb:SetFocus() end
            end,
            OnAccept = function(dialog, data) Save(dialog, data) end,
            EditBoxOnEnterPressed = function(eb, data)
                local dialog = eb:GetParent()
                Save(dialog, data)
                dialog:Hide()
            end,
            EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
        }
    end
    local e = MS:BlacklistEntry(name, realm)
    local title = _fmt(L["A note on %s for your blacklist:"], display)
    Show(POPUP, title, nil, { name = name, realm = realm, class = class, note = e and e.note or "" })
end

-- Adding someone by name (the window's button): their name first, with
-- your target's filled in when it's a player, then the note.
local NAME_POPUP = "MYTHICSCOREBOARD_BLACKLIST_NAME"
function MS:AskBlacklistName()
    local Dialogs = rawget(_G, "StaticPopupDialogs")
    local Show = rawget(_G, "StaticPopup_Show")
    if not (Dialogs and Show) then return end
    if not Dialogs[NAME_POPUP] then
        local function Next(dialog)
            local eb = EditBoxOf(dialog)
            local name = eb and eb:GetText() or ""
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" then
                dialog:Hide()
                MS:AskBlacklistNote(name)
            end
        end
        Dialogs[NAME_POPUP] = {
            text = "%s", button1 = rawget(_G, "NEXT") or "Next", button2 = rawget(_G, "CANCEL") or "Cancel",
            hasEditBox = 1, maxLetters = 60, editBoxWidth = 220,
            timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
            OnShow = function(dialog, data)
                local eb = EditBoxOf(dialog)
                if eb then eb:SetText(data and data.name or ""); eb:HighlightText(); eb:SetFocus() end
            end,
            OnAccept = function(dialog) Next(dialog); return true end,
            EditBoxOnEnterPressed = function(eb) Next(eb:GetParent()) end,
            EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
        }
    end
    local name
    local ok, isPlayer = pcall(UnitIsPlayer, "target")
    local IsUnit = rawget(_G, "UnitIsUnit")
    if ok and isPlayer == true and not (IsUnit and IsUnit("target", "player")) then
        local n, r = UnitKeyName("target")
        local _, display = MS.BlacklistKey(n, r)
        name = display
    end
    Show(NAME_POPUP, L["The player's name:"], nil, { name = name or "" })
end

-- ── Setting it up ──────────────────────────────────────────────────────────
MS:On("PLAYER_LOGIN", function()
    pcall(HookMenus)
    pcall(HookBrowseMenu)
    pcall(HookBrowse)
    local TDP = rawget(_G, "TooltipDataProcessor")
    local Enum_ = rawget(_G, "Enum")
    if not tooltipHooked and TDP and TDP.AddTooltipPostCall and Enum_ and Enum_.TooltipDataType then
        tooltipHooked = true
        TDP.AddTooltipPostCall(Enum_.TooltipDataType.Unit, function(tooltip)
            local ok, err = pcall(UnitTooltip, tooltip)
            if not ok then MS:ReportError("Blacklist", err) end
        end)
    end
end)
-- Looking For Group may load later.
MS:On("ADDON_LOADED", function() pcall(HookBrowse) end)

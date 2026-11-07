-- Loot tracking: which gear each group member received during a run.
--
-- Sources, merged and de-duplicated:
--   1. ENCOUNTER_LOOT_RECEIVED  - personal loot from bosses (everyone in group)
--   2. CHAT_MSG_LOOT            - "X receives loot: [item]", incl. end-of-run chest
--   3. Addon message (MSBLoot)  - MythicScoreboard users share their own loot,
--                                 a backup for when the game hides others' loot
--
-- Only equippable gear (weapons/armour, uncommon or better) is kept.
-- Loot that arrives just after a run is committed to history (the Mythic+
-- chest) is attached to that saved run for a few minutes.

local MS = _G["MythicScoreboard"]
local _issecret = issecretvalue
local _ins = table.insert

local PREFIX         = "MSBLoot"
local LATE_WINDOW    = 300     -- seconds after a run ends that loot still counts
local DEDUPE_WINDOW  = 15
local MAX_PER_PLAYER = 40      -- a full Blackrock Depths can drop a lot of greens

local function Secret(v) return _issecret and v ~= nil and _issecret(v) end

local function ItemString(link)
    if type(link) ~= "string" then return nil end
    return link:match("|H(item:[%-%d:]+)") or link:match("^(item:[%-%d:]+)$")
end

-- A loot entry's "item:..." string. Saved entries keep only the chat link
-- when there is one (the item string is inside it).
function MS.LootItemString(l)
    if not l then return nil end
    return l.item or l.i or ItemString(l.link or l.l)
end

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetInfo    = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Weapons (2) and armour (4) that can actually be equipped.
local function IsGear(link)
    if not GetInstant then return true end
    local ok, itemID, _, _, equipLoc, _, classID = pcall(GetInstant, link)
    if not ok or not itemID then return false end
    if classID ~= 2 and classID ~= 4 then return false end
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE"
            or equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then
        return false
    end
    return true
end

-- Quality from the link itself when the item isn't cached yet.
local function LinkQuality(link)
    if type(link) ~= "string" then return nil end
    local q = link:match("|cnIQ(%d):")
    if q then return tonumber(q) end
    if GetInfo then
        local ok, _, _, quality = pcall(GetInfo, link)
        if ok and quality then return quality end
    end
    return nil
end

-- ── Which run does a piece of loot belong to? ───────────────────────────

function MS:_LootTargetRun()
    if self.currentRun then return self.currentRun end
    local r = self._lastCommittedRun
    if r and self._lastCommittedAt and (GetTime() - self._lastCommittedAt) < LATE_WINDOW then
        return r
    end
    return nil
end

MS._lootRev = 0
local _recent = {}

function MS:RecordLoot(playerName, link, source)
    if not playerName or not link or Secret(playerName) or Secret(link) then return end
    if type(playerName) ~= "string" or type(link) ~= "string" then return end
    local run = self:_LootTargetRun()
    if not run or not run.players then return end
    local p = self:PlayerByName(playerName, run)
    if not p then return end
    local short = p.name

    local istr = ItemString(link)
    if not istr then return end
    if not IsGear(link) then return end
    local q = LinkQuality(link)
    if q and q < 2 then return end

    -- The same drop usually arrives via two or three sources.
    local key = short .. "|" .. istr
    local now = GetTime()
    if _recent[key] and now - _recent[key] < DEDUPE_WINDOW then return end
    _recent[key] = now

    p.loot = p.loot or {}
    for _, l in ipairs(p.loot) do
        if MS.LootItemString(l) == istr and (now - (l.at or 0)) < DEDUPE_WINDOW then return end
    end
    if #p.loot >= MAX_PER_PLAYER then return end

    local fullLink = link:find("|H") and link or nil
    local entry = {
        item    = istr,          -- "item:..." string: tooltips, icons, ilvl
        link    = fullLink,      -- coloured chat link when we have one
        quality = q,
        at      = now,
        t       = self.GetRunDuration and self:GetRunDuration(run) or 0,
        src     = source,
    }
    _ins(p.loot, entry)
    -- After the run was saved: its Stats summary gets your piece too.
    if run ~= self.currentRun and p == self:PlayerForUnit("player", run) and self.ArchiveLateLoot then
        self:ArchiveLateLoot(run, entry)
    end
    run._seq = (run._seq or 0) + 1
    self._lootRev = self._lootRev + 1
    if run == self.currentRun then self:SaveCurrentRun() end
    if self.RefreshOverview then self:RefreshOverview() end

    -- Share our own drops with other MythicScoreboard users in the group.
    if source ~= "comm" and p == self:PlayerForUnit("player", run) then
        self:_BroadcastLoot(istr)
    end
end

-- ── Addon messages ──────────────────────────────────────────────────────

local function GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

function MS:_BroadcastLoot(istr)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    -- Small delay: messages can be blocked in the instant combat ends.
    C_Timer.After(2, function()
        local ch = GroupChannel()
        if not ch then return end
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, "1|" .. istr, ch)
    end)
end

-- ── Chat parsing ────────────────────────────────────────────────────────

-- Turn a localized GlobalString like "%s receives loot: %s." into a pattern.
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    p = p:gsub("%%%%(%d)%%%$s", "(.+)"):gsub("%%%%(%d)%%%$d", "(%%d+)")
    -- Some languages put the item before the player ("%2$s ... %1$s").
    local i1, i2 = fmt:find("%1$s", 1, true), fmt:find("%2$s", 1, true)
    return "^" .. p .. "$", (i1 and i2 and i2 < i1) or false
end

local OTHER_PATTERNS, SELF_PATTERNS = {}, {}
local function BuildPatterns()
    wipe(OTHER_PATTERNS); wipe(SELF_PATTERNS)
    for _, g in ipairs({ "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_PUSHED_MULTIPLE",
                         "LOOT_ITEM_BONUS_ROLL_MULTIPLE", "LOOT_ITEM",
                         "LOOT_ITEM_PUSHED", "LOOT_ITEM_BONUS_ROLL" }) do
        local pat, swapped = ToPattern(_G[g])
        if pat then _ins(OTHER_PATTERNS, { pat, swapped }) end
    end
    for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
                         "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_SELF",
                         "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_BONUS_ROLL_SELF" }) do
        local pat = ToPattern(_G[g])
        if pat then _ins(SELF_PATTERNS, pat) end
    end
end

function MS:_ParseLootMessage(text)
    if type(text) ~= "string" or Secret(text) then return nil end
    for _, pat in ipairs(SELF_PATTERNS) do
        local item = text:match(pat)
        if item then return MS:UnitPlayerName("player"), item end
    end
    for _, pp in ipairs(OTHER_PATTERNS) do
        local who, item = text:match(pp[1])
        if pp[2] then who, item = item, who end
        if who and item then return who, item end
    end
    return nil
end

-- ── Events ──────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "ENCOUNTER_LOOT_RECEIVED", "CHAT_MSG_LOOT",
                     "CHAT_MSG_ADDON", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(frame.RegisterEvent, frame, ev)      -- (not every client has every event)
end

local _infoRefreshPending = false

local function OnLootMessage(text)
    local who, item = MS:_ParseLootMessage(text)
    if who and item then MS:RecordLoot(who, item, "chat") end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        BuildPatterns()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end

    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        if not MS:_LootTargetRun() then return end
        local _, _, itemLink, _, playerName = ...
        pcall(MS.RecordLoot, MS, playerName, itemLink, "encounter")

    elseif event == "CHAT_MSG_LOOT" then
        if not MS:_LootTargetRun() then return end     -- no run: nothing to parse
        pcall(OnLootMessage, (...))

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix ~= PREFIX or Secret(msg) or Secret(sender) then return end
        if type(msg) ~= "string" or type(sender) ~= "string" then return end
        local istr = msg:match("^1|(item:[%-%d:]+)$")
        if istr and #istr < 240 then
            MS:RecordLoot(sender, istr, "comm")
        end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Item names/qualities/levels fill in asynchronously; redraw once.
        if _infoRefreshPending or not (MS.sbFrameVisible and MS.sbFrameVisible()) then return end
        _infoRefreshPending = true
        C_Timer.After(0.3, function()
            _infoRefreshPending = false
            MS._lootRev = (MS._lootRev or 0) + 1
            if MS.RefreshOverview then MS:RefreshOverview() end
        end)
    end
end)

local MS = _G["MythicScoreboard"]
local L = MS.L
local _ceil, _max = math.ceil, math.max
local _fmt, _ins, _sort = string.format, table.insert, table.sort

-- ── The instance limit ─────────────────────────────────────────────────────
-- The game lets you into only so many new instances an hour (10, on today's
-- clients); one more and it turns you away at the door. Every new dungeon or
-- raid you enter is noted here, for all your characters on the realm
-- (MythicScoreboardAccountDB.instanceLimit), so the in-run frame, the minimap
-- button's tooltip and /sb limit can say how many you've used and when the
-- next one frees. A warning comes when you're down to your last, and a chat
-- line (and a chime) when a slot frees after you'd used them all. Turned
-- away at the door, a countdown to the next slot shows (UI_InstanceLimit.lua).
--
-- What counts as new: a different dungeon, the same one after it's been
-- reset ("<Dungeon> has been reset."), or the same one more than half an hour
-- after you left it (by then the game has closed it). Going back in after a
-- corpse run, a /reload or a logout inside is the same instance.
-- When the game does turn you away, how many you'd used is the real limit:
-- it's kept, so a client with another limit is learned the first time.
-- Only what's played on this PC with the addon on is counted.

MS.INSTANCE_LIMIT_DEFAULT = 10
local HOUR = 3600
local KEEP = 24 * HOUR                  -- older entries are dropped
local SAME_FOR = 30 * 60                -- left for less than this: still the same instance

-- ── Saved data ─────────────────────────────────────────────────────────────
-- { [realm] = { entries = { { t, map, name, char } }, limit, inside = { map, char },
--               last = { map, char, at, leftAt }, resets = { [dungeon name] = time },
--               lockedUntil } }
local function Realm()
    local r = GetRealmName and GetRealmName()
    return (type(r) == "string" and r ~= "" and not MS.IsSecret(r)) and r or "?"
end

local function Store()
    local acc = MS.AccountDB and MS.AccountDB(true)
    if not acc then return nil end
    if type(acc.instanceLimit) ~= "table" then acc.instanceLimit = {} end
    local realm = Realm()
    local s = acc.instanceLimit[realm]
    if type(s) ~= "table" then s = {}; acc.instanceLimit[realm] = s end
    if type(s.entries) ~= "table" then s.entries = {} end
    if type(s.resets) ~= "table" then s.resets = {} end
    return s
end

local function Prune(s, now)
    for i = #s.entries, 1, -1 do
        local e = s.entries[i]
        if type(e) ~= "table" or not e.t or now - e.t >= KEEP then table.remove(s.entries, i) end
    end
    for name, at in pairs(s.resets) do
        if now - at >= KEEP then s.resets[name] = nil end
    end
end

-- ── Where things stand ─────────────────────────────────────────────────────
-- { used, limit, entries (this hour, oldest first), nextFree (a time, while
-- any are used), locked (the game has turned you away and no slot has freed) }
function MS:InstanceLimit()
    local s = Store()
    local now = time()
    local info = { used = 0, limit = MS.INSTANCE_LIMIT_DEFAULT, entries = {} }
    if not s then return info end
    Prune(s, now)
    for _, e in ipairs(s.entries) do
        if now - e.t < HOUR then _ins(info.entries, e) end
    end
    _sort(info.entries, function(a, b) return a.t < b.t end)
    info.used = #info.entries
    info.limit = tonumber(s.limit) or MS.INSTANCE_LIMIT_DEFAULT
    if info.used > 0 then info.nextFree = info.entries[1].t + HOUR end
    info.locked = s.lockedUntil ~= nil and now < s.lockedUntil
    if info.locked then info.nextFree = s.lockedUntil end
    return info
end

-- (Clock times: MS.ClockTime, RunModel.lua.)

-- "12 min", rounded up (a slot "in 0 min" is never said).
function MS.MinutesFrom(seconds)
    return _fmt(L["%d min"], _max(1, _ceil((seconds or 0) / 60)))
end

local function NextFreeText(info)
    return _fmt(L["Next slot frees at %s (in %s)"], MS.ClockTime(info.nextFree), MS.MinutesFrom(info.nextFree - time()))
end
MS.InstanceNextFreeText = NextFreeText

-- ── Telling you ────────────────────────────────────────────────────────────
function MS:GetInstanceLimitWarn() return self:GetSetting("instanceLimitWarn") ~= false end
function MS:SetInstanceLimitWarn(v) self:SetSetting("instanceLimitWarn", v and true or false) end

local function Notice(text, gold)
    local frame, add = rawget(_G, "RaidWarningFrame"), rawget(_G, "RaidNotice_AddMessage")
    if frame and add then
        pcall(add, frame, text, gold and { r = 1, g = 0.82, b = 0.3 } or { r = 1, g = 0.3, b = 0.25 })
    end
end

local function Chime()
    local Sound, kit = rawget(_G, "PlaySound"), rawget(_G, "SOUNDKIT")
    if Sound and kit and kit.READY_CHECK then pcall(Sound, kit.READY_CHECK) end
end

local freeTimer

-- A slot frees: said once, if you'd used them all (or been turned away).
local function WatchForFreeSlot()
    if freeTimer then freeTimer:Cancel(); freeTimer = nil end
    local info = MS:InstanceLimit()
    if not info.nextFree or not (info.locked or info.used >= info.limit) then return end
    local wait = _max(1, info.nextFree - time() + 1)
    if not (C_Timer and C_Timer.NewTimer) then return end
    freeTimer = C_Timer.NewTimer(wait, function()
        freeTimer = nil
        local s = Store()
        if s and s.lockedUntil and time() >= s.lockedUntil then s.lockedUntil = nil end
        local now = MS:InstanceLimit()
        if now.locked or now.used >= now.limit then WatchForFreeSlot(); return end
        if MS:GetInstanceLimitWarn() then
            MS.Say(_fmt(L["A dungeon slot is free again (%d of %d this hour)."], now.used, now.limit))
            Chime()
        end
        MS:Changed("instanceLimit")
    end)
end

-- ── Counting ───────────────────────────────────────────────────────────────
local function Counted(s, map, name, char, now)
    _ins(s.entries, { t = now, map = map, name = name, char = char })
    s.last = { map = map, char = char, at = now }
    local info = MS:InstanceLimit()
    -- Not turned away, so the limit is at least what's been used.
    if info.used > info.limit then s.limit = info.used; info.limit = info.used end
    if MS:GetInstanceLimitWarn() and info.nextFree then
        local at = MS.ClockTime(info.nextFree)
        if info.used == info.limit then
            local text = _fmt(L["That was your last instance this hour. The next frees at %s."], at)
            MS.Say(text); Notice(text, true)
        elseif info.used == info.limit - 1 then
            MS.Say(_fmt(L["One instance left this hour. The next frees at %s."], at))
        end
    end
    WatchForFreeSlot()
    MS:Changed("instanceLimit")
end

local function InInstance()
    local inside, kind = IsInInstance()
    if MS.IsSecret(inside) or MS.IsSecret(kind) then return nil end
    if not (inside and (kind == "party" or kind == "raid")) then return nil end
    local name, _, _, _, _, _, _, map = GetInstanceInfo()
    if MS.IsSecret(name) or MS.IsSecret(map) then return nil end
    return map or name, name
end

-- Where you are now: counted the first time you're inside a new instance.
function MS:CheckInstanceEntry()
    local s = Store()
    if not s then return end
    local now = time()
    local map, name = InInstance()
    local char = UnitName("player")
    if not map then
        if s.inside then
            if s.last then s.last.leftAt = now end
            s.inside = nil
        end
        return
    end
    if s.inside and s.inside.map == map and s.inside.char == char then return end   -- still in it
    local last = s.last
    local same = last and last.map == map and last.char == char
        and not (name and s.resets[name] and s.resets[name] >= (last.at or 0))
        and (now - (last.leftAt or now)) < SAME_FOR
    s.inside = { map = map, char = char }
    if same then return end
    Counted(s, map, name, char, now)
end

-- "<Dungeon> has been reset.": going in again is a new instance.
local resetPattern = MS.FormatPattern and MS.FormatPattern(rawget(_G, "INSTANCE_RESET_SUCCESS"))
local tooMany = rawget(_G, "TRANSFER_ABORT_TOO_MANY_INSTANCES") or "You have entered too many instances recently."

-- Turned away: you've used them all; how many you'd used is the limit.
local function TurnedAway()
    local s = Store()
    if not s then return end
    local info = MS:InstanceLimit()
    if info.used >= 3 then s.limit = info.used end
    s.lockedUntil = info.used > 0 and info.entries[1].t + HOUR or time() + HOUR
    WatchForFreeSlot()
    MS:Changed("instanceLimit")         -- the countdown shows (UI_InstanceLimit.lua)
end

local function OnSystemMessage(_, msg)
    if type(msg) ~= "string" or MS.IsSecret(msg) then return end
    if msg == tooMany then TurnedAway(); return end
    local dungeon = resetPattern and MS.MatchFormat(msg, resetPattern)
    if dungeon then
        local s = Store()
        if s then s.resets[dungeon] = time() end
    end
end

local function OnErrorMessage(_, _, msg)
    if type(msg) == "string" and not MS.IsSecret(msg) and msg == tooMany then TurnedAway() end
end

MS:On("PLAYER_ENTERING_WORLD", function() MS:CheckInstanceEntry(); WatchForFreeSlot() end)
MS:On("ZONE_CHANGED_NEW_AREA", function() MS:CheckInstanceEntry() end)
MS:On("CHAT_MSG_SYSTEM", OnSystemMessage)
MS:On("UI_ERROR_MESSAGE", OnErrorMessage)

-- ── /sb limit ──────────────────────────────────────────────────────────────
function MS:SayInstanceLimit()
    local info = self:InstanceLimit()
    if info.used == 0 then MS.Say(L["No instances entered in the last hour."]); return end
    MS.Say(_fmt(L["Instances this hour: %d of %d."], info.used, info.limit))
    for _, e in ipairs(info.entries) do
        MS.Say("  " .. MS.ClockTime(e.t) .. "  " .. tostring(e.name or "?") .. "  (" .. tostring(e.char or "?") .. ")")
    end
    MS.Say(NextFreeText(info))
end


local MS = _G["MythicScoreboard"]
local L = MS.L
local _ceil, _max = math.ceil, math.max
local _fmt, _ins, _sort = string.format, table.insert, table.sort

-- ── The instance limit ─────────────────────────────────────────────────────
-- WoW Forever lets you reset and enter each dungeon only so many times an
-- hour (5, since the hotfixes of 20 November 2026; it was 10); one more and
-- it turns you away at the door. Every new dungeon or raid you enter is noted
-- here, for all your characters on the realm (MythicScoreboardAccountDB
-- .instanceLimit), so the in-run frame, the minimap button's tooltip and
-- /sb limit can say how many runs of each you've had and when the next one
-- frees. A warning comes when you're down to your last run of a dungeon, and
-- a chat line (and a chime) when it opens again after you'd used them all.
-- Turned away at the door, a countdown shows (UI_InstanceLimit.lua).
--
-- Counted each dungeon on its own (scope "dungeon"), as the hotfix says. If
-- the game turns you away at a dungeon you've had fewer than a handful of
-- runs of, the limit must be on all of them together: from then on they're
-- counted as one (scope "all").
--
-- What counts as new: a different dungeon, the same one after it's been
-- reset ("<Dungeon> has been reset."), or the same one more than half an hour
-- after you left it (by then the game has closed it). Going back in after a
-- corpse run, a /reload or a logout inside is the same instance.
-- When the game does turn you away, how many you'd used is the real limit:
-- it's kept, so a client with another limit is learned the first time.
-- Only what's played on this PC with the addon on is counted.

MS.INSTANCE_LIMIT_DEFAULT = 5
local DATA_VERSION = 2                  -- 2: per dungeon, 5 (what 1 learned, at 10, is dropped)
local HOUR = 3600
local KEEP = 24 * HOUR                  -- older entries are dropped
local SAME_FOR = 30 * 60                -- left for less than this: still the same instance

-- ── Saved data ─────────────────────────────────────────────────────────────
-- { [realm] = { v, entries = { { t, map, name, char } }, limit, scope,
--               inside = { map, char }, last = { map, name, char, at, leftAt },
--               resets = { [dungeon name] = time },
--               locked = { [dungeon name] = time } (scope "dungeon"), lockedUntil (scope "all") } }
local function Realm()
    local r = MS.PlayerRealm()
    if r then return r end
    -- (The game won't say: the realm your character's saved under.)
    local key = MS.CharKey and MS:CharKey()
    return key and key:match("@(.+)$") or "?"
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
    if s.v ~= DATA_VERSION then
        -- The limit changed (10 for all, then 5 each): what was learned goes.
        s.v, s.limit, s.scope, s.lockedUntil = DATA_VERSION, nil, nil, nil
    end
    if type(s.locked) ~= "table" then s.locked = {} end
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
    for name, at in pairs(s.locked) do
        if now >= at then s.locked[name] = nil end
    end
end

local function InInstance()
    local inside, kind = IsInInstance()
    if MS.IsSecret(inside) or MS.IsSecret(kind) then return nil end
    if not (inside and (kind == "party" or kind == "raid")) then return nil end
    local name, _, _, _, _, _, _, map = GetInstanceInfo()
    if MS.IsSecret(name) or MS.IsSecret(map) then return nil end
    return map or name, name
end

-- The dungeon a question's about, when none's named: the one you're in, or
-- else the last you were in.
local function ThisDungeon(s)
    local _, name = InInstance()
    if name then return name end
    return s.last and s.last.name
end

-- ── Where things stand ─────────────────────────────────────────────────────
-- MS:InstanceLimit(dungeon): { scope, dungeon (scope "dungeon": the one asked
-- about, or the one you're in or were last in), used, limit, entries (this
-- hour, oldest first), nextFree (a time, while any are used), locked (the
-- game has turned you away and it hasn't freed), dungeons (every one entered
-- this hour, the most runs first: { name, used, nextFree, full }) }.
function MS:InstanceLimit(dungeon)
    local s = Store()
    local now = time()
    local info = { scope = "dungeon", used = 0, limit = MS.INSTANCE_LIMIT_DEFAULT, entries = {}, dungeons = {} }
    if not s then return info end
    Prune(s, now)
    local all = s.scope == "all"
    info.scope = all and "all" or "dungeon"
    info.limit = tonumber(s.limit) or MS.INSTANCE_LIMIT_DEFAULT
    if not all then info.dungeon = dungeon or ThisDungeon(s) end
    local by = {}
    for _, e in ipairs(s.entries) do
        if now - e.t < HOUR then
            if all or e.name == info.dungeon then _ins(info.entries, e) end
            local k = tostring(e.name or "?")
            local d = by[k]
            if not d then d = { name = e.name or "?", used = 0 }; by[k] = d; _ins(info.dungeons, d) end
            d.used = d.used + 1
            if not d.first or e.t < d.first then d.first = e.t end
        end
    end
    _sort(info.entries, function(a, b) return a.t < b.t end)
    info.used = #info.entries
    if info.used > 0 then info.nextFree = info.entries[1].t + HOUR end
    if all then
        info.locked = s.lockedUntil ~= nil and now < s.lockedUntil
        if info.locked then info.nextFree = s.lockedUntil end
    else
        local until_ = info.dungeon and s.locked[info.dungeon]
        info.locked = until_ ~= nil and now < until_
        if info.locked then info.nextFree = until_ end
    end
    for _, d in ipairs(info.dungeons) do
        d.nextFree = d.first + HOUR
        local until_ = not all and s.locked[d.name]
        if until_ and now < until_ then d.nextFree, d.locked = until_, true end
        d.full = d.locked or (not all and d.used >= info.limit) or false
    end
    _sort(info.dungeons, function(a, b)
        if a.used ~= b.used then return a.used > b.used end
        return tostring(a.name) < tostring(b.name)
    end)
    return info
end

-- (Clock times: MS.ClockTime, RunModel.lua.)

-- "12 min", rounded up (a slot "in 0 min" is never said).
function MS.MinutesFrom(seconds)
    return _fmt(L["%d min"], _max(1, _ceil((seconds or 0) / 60)))
end

local function NextFreeText(info)
    if info.scope == "dungeon" and info.dungeon then
        return _fmt(L["Your next %s run frees at %s (in %s)"], info.dungeon, MS.ClockTime(info.nextFree),
            MS.MinutesFrom(info.nextFree - time()))
    end
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

-- What's full now (every dungeon you've used up, or all of them), and when
-- the first of them frees.
local function FullNow()
    local info = MS:InstanceLimit()
    local full, soonest = {}, nil
    if info.scope == "all" then
        if info.nextFree and (info.locked or info.used >= info.limit) then
            full["*"] = true; soonest = info.nextFree
        end
    else
        for _, d in ipairs(info.dungeons) do
            if d.full then
                full[d.name] = true
                if not soonest or d.nextFree < soonest then soonest = d.nextFree end
            end
        end
    end
    return full, soonest
end

-- A dungeon (or, scope "all", a slot) frees: said once, for what you'd used up.
local function WatchForFreeSlot()
    if freeTimer then freeTimer:Cancel(); freeTimer = nil end
    local before, soonest = FullNow()
    if not soonest then return end
    local wait = _max(1, soonest - time() + 1)
    if not (C_Timer and C_Timer.NewTimer) then return end
    freeTimer = C_Timer.NewTimer(wait, function()
        freeTimer = nil
        local s = Store()
        if s and s.lockedUntil and time() >= s.lockedUntil then s.lockedUntil = nil end
        local now = FullNow()
        local said = false
        for name in pairs(before) do
            if not now[name] and MS:GetInstanceLimitWarn() then
                if name == "*" then
                    local info = MS:InstanceLimit()
                    if info.scope ~= "all" then break end      -- (counted each on its own again)
                    MS.Say(_fmt(L["A dungeon slot is free again (%d of %d this hour)."], info.used, info.limit))
                else
                    local info = MS:InstanceLimit(name)
                    MS.Say(_fmt(L["%s is open again (%d of %d this hour)."], name, info.used, info.limit))
                end
                said = true
            end
        end
        if said then Chime() end
        WatchForFreeSlot()
        MS:Changed("instanceLimit")
    end)
end

-- ── Counting ───────────────────────────────────────────────────────────────
local function Counted(s, map, name, char, now)
    _ins(s.entries, { t = now, map = map, name = name, char = char })
    s.last = { map = map, name = name, char = char, at = now }
    local info = MS:InstanceLimit(name)
    -- Not turned away, so the limit is at least what's been used.
    if info.used > info.limit then s.limit = info.used; info.limit = info.used end
    if MS:GetInstanceLimitWarn() and info.nextFree then
        local at = MS.ClockTime(info.nextFree)
        local each = info.scope == "dungeon" and name
        if info.used == info.limit then
            local text = each and _fmt(L["That was your last %s run this hour. It opens again at %s."], name, at)
                or _fmt(L["That was your last instance this hour. The next frees at %s."], at)
            MS.Say(text); Notice(text, true)
        elseif info.used == info.limit - 1 then
            MS.Say(each and _fmt(L["One %s run left this hour. Another frees at %s."], name, at)
                or _fmt(L["One instance left this hour. The next frees at %s."], at))
        end
    end
    WatchForFreeSlot()
    MS:Changed("instanceLimit")
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

-- Turned away, at the door of (we take it) the dungeon you were last in.
-- Counted each on its own: that one's used up, and how many runs you'd had
-- is its limit. Fewer than a handful of runs of it, though, and it can't be
-- a limit on each dungeon: it's on all of them together, from now on.
local function TurnedAway()
    local s = Store()
    if not s then return end
    local now = time()
    if s.scope ~= "all" then
        local name = s.last and s.last.name
        local info = MS:InstanceLimit(name)
        if name and info.used >= 3 then
            if info.used < info.limit then s.limit = info.used end
            s.locked[name] = info.entries[1].t + HOUR
        else
            local total = MS:InstanceLimit()
            local sum = 0
            for _, d in ipairs(total.dungeons) do sum = sum + d.used end
            if sum >= 3 then
                s.scope, s.limit = "all", sum
                local all = MS:InstanceLimit()
                s.lockedUntil = all.entries[1] and all.entries[1].t + HOUR or now + HOUR
            elseif name then
                s.locked[name] = now + HOUR
            end
        end
    else
        local info = MS:InstanceLimit()
        if info.used >= 3 then s.limit = info.used end
        s.lockedUntil = info.used > 0 and info.entries[1].t + HOUR or now + HOUR
    end
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
    if #info.dungeons == 0 then MS.Say(L["No instances entered in the last hour."]); return end
    if info.scope == "dungeon" then
        -- Each dungeon: its runs this hour, and when the next frees.
        for _, d in ipairs(info.dungeons) do
            MS.Say(_fmt(L["%s: %d of %d this hour."], d.name, d.used, info.limit) .. "  "
                .. _fmt(L["Next frees at %s (in %s)"], MS.ClockTime(d.nextFree), MS.MinutesFrom(d.nextFree - time())))
        end
        return
    end
    MS.Say(_fmt(L["Instances this hour: %d of %d."], info.used, info.limit))
    for _, e in ipairs(info.entries) do
        MS.Say("  " .. MS.ClockTime(e.t) .. "  " .. tostring(e.name or "?") .. "  (" .. tostring(e.char or "?") .. ")")
    end
    MS.Say(NextFreeText(info))
end


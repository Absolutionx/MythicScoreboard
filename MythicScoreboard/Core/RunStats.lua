-- What a run did for your character (WoW Forever): experience and levels,
-- mobs killed, quests completed, gold looted, reputation gained.
--
--   run.progress = { xp, levels, kills, quests = { titles }, gold (copper),
--                    rep = { [faction] = amount } }
--
-- The combat log is blocked inside instances, so each number comes from
-- something the game still shows:
--   xp, levels   your XP bar, read whenever it changes
--   kills        hostile mobs seen alive, then dead: on their nameplates,
--                your target, focus or mouseover, or your group's targets;
--                and "<mob> dies, you gain N experience." in chat, for a kill
--                none of those showed (the two are matched, so a kill seen
--                both ways counts once)
--   quests       quests seen incomplete in your log during the run, that
--                the game said made progress in here, then
--                complete (not ones already done: the log loads in pieces
--                after a loading screen, and collapsed headers hide quests)
--   gold         money gained while the run is going (not while paused)
--   rep          "Your reputation with <faction> has increased by N." in chat
-- Only counted while the run is active; leaving and coming back starts each
-- reading again from where you are, so time outside never counts.

local MS = _G["MythicScoreboard"]
local L = MS.L
if not MS.Flavor.progressStats then return end

local Plain = MS.ReadableValue
local _fmt = string.format

local function Progress(run)
    run.progress = run.progress or { xp = 0, levels = 0, kills = 0, quests = {}, gold = 0, rep = {} }
    local p = run.progress
    p.quests, p.rep = p.quests or {}, p.rep or {}
    return p
end

local function Changed(run)
    MS:SaveCurrentRun()
    MS:Changed("run")
end

-- ── Readings ───────────────────────────────────────────────────────────────
local last = {}      -- xp, max, level, money: the last reading, while active

local function ReadXP()
    local xp = Plain(UnitXP and UnitXP("player"))
    local max = Plain(UnitXPMax and UnitXPMax("player"))
    local lvl = Plain(UnitLevel and UnitLevel("player"))
    if type(xp) == "number" and type(max) == "number" and type(lvl) == "number" then return xp, max, lvl end
end

local function ReadMoney()
    local m = Plain(GetMoney and GetMoney())
    return type(m) == "number" and m or nil
end

-- Where you are now becomes the starting point for every reading.
local function Baseline()
    last.xp, last.max, last.level = ReadXP()
    last.money = ReadMoney()
end

local function OnXP()
    local run = MS.currentRun
    if not (run and MS.inDungeon) then return end
    local xp, max, lvl = ReadXP()
    if not xp then return end
    if last.xp then
        local gained
        if lvl > last.level then
            gained = (last.max - last.xp) + xp           -- the rest of the old level, then into the new
            Progress(run).levels = Progress(run).levels + (lvl - last.level)
        elseif lvl == last.level then
            gained = xp - last.xp
        end
        if gained and gained > 0 then Progress(run).xp = Progress(run).xp + gained end
    end
    last.xp, last.max, last.level = xp, max, lvl
    Changed(run)
end

local function OnMoney()
    local run = MS.currentRun
    if not (run and MS.inDungeon) then return end
    local m = ReadMoney()
    if not m then return end
    if last.money and m > last.money then Progress(run).gold = Progress(run).gold + (m - last.money) end
    last.money = m
    Changed(run)
end

-- ── Chat lines ─────────────────────────────────────────────────────────────
-- Kill lines ("%s dies, you gain %d experience.") are matched up to the
-- first number (what follows varies: rested, group bonus); reputation lines
-- give the faction and the amount, in the format's order.
local KILL_PATTERNS, REP_PATTERNS = {}, {}
local function BuildPatterns()
    wipe(KILL_PATTERNS); wipe(REP_PATTERNS)
    for _, g in ipairs({ "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP",
                         "COMBATLOG_XPGAIN_FIRSTPERSON_RAID", "COMBATLOG_XPGAIN_EXHAUSTION1",
                         "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION1_RAID" }) do
        local fp = MS.FormatPattern(rawget(_G, g), "prefix")
        if fp then KILL_PATTERNS[#KILL_PATTERNS + 1] = fp end
    end
    for _, g in ipairs({ "FACTION_STANDING_INCREASED", "FACTION_STANDING_INCREASED_BONUS",
                         "FACTION_STANDING_INCREASED_DOUBLE_BONUS", "FACTION_STANDING_INCREASED_ACH_BONUS" }) do
        local fp = MS.FormatPattern(rawget(_G, g), "start")
        if fp then REP_PATTERNS[#REP_PATTERNS + 1] = fp end
    end
end
MS._RunStatsPatterns = BuildPatterns       -- for tests

-- ── Kills ──────────────────────────────────────────────────────────────────
-- The XP line comes only for kills that gave XP. Every kill (grey mobs, at
-- max level too) is also seen on the enemies the game shows: a hostile mob
-- seen alive, then dead. Each mob (by GUID) counts once, and the XP line is
-- matched by name to a kill seen in the last few seconds, either way round,
-- so a kill seen both ways counts once.
local MATCH_SECONDS = 5
local alive, counted = {}, {}          -- [guid] = true
local seenKills, xpKills = {}, {}      -- [mob name] = { times }, not yet matched
local trackRun

local function Track(run)
    if trackRun == run then return end
    trackRun = run
    wipe(alive); wipe(counted); wipe(seenKills); wipe(xpKills)
end

-- Takes the oldest entry for the name, if one is recent enough.
local function Take(list, name, now)
    local t = list[name]
    if not t then return false end
    while t[1] and now - t[1] > MATCH_SECONDS do table.remove(t, 1) end
    if not t[1] then list[name] = nil; return false end
    table.remove(t, 1)
    return true
end
-- Takes the oldest recent entry under any name (a nameplate whose name the
-- game hides: matched to whichever XP line came with it).
local ANY = "\0any"
local function TakeAny(list, now)
    local best, bestT
    for name, t in pairs(list) do
        while t[1] and now - t[1] > MATCH_SECONDS do table.remove(t, 1) end
        if t[1] and (not bestT or t[1] < bestT) then best, bestT = name, t[1] end
    end
    if best then return Take(list, best, now) end
    return false
end
local function Put(list, name, now)
    local t = list[name] or {}
    list[name] = t
    t[#t + 1] = now
end

local function CountKill(run, name)
    if name then MS:NoteMobDied(name) end
    Progress(run).kills = Progress(run).kills + 1
    Changed(run)
end

local function OnXPLine(text)
    local run = MS.currentRun
    if not (run and MS.inDungeon) or type(Plain(text)) ~= "string" then return end
    for _, fp in ipairs(KILL_PATTERNS) do
        local mob = MS.MatchFormat(text, fp)
        if mob and mob ~= "" then
            Track(run)
            if MS.NoteForeverKill then MS:NoteForeverKill(nil, mob) end     -- which wing (Forever.lua)
            local now = GetTime()
            -- Already counted when it died (by name, or a nameless one).
            if Take(seenKills, mob, now) or Take(seenKills, ANY, now) then return end
            Put(xpKills, mob, now)
            CountKill(run, mob)
            return
        end
    end
end

-- Yes/no from the game: true or 1 (older APIs), never a hidden value.
local function Yes(v) v = Plain(v); return v ~= nil and v ~= false and v ~= 0 end
local function Flag(fn, unit) return fn ~= nil and Yes(fn(unit)) end

-- /sb killdebug: says in chat what each enemy looked like, to find out why
-- a kill wasn't counted.
local debugKills = false
local debugSaid = {}
local function Debug(key, ...)
    if not debugKills then return end
    if key then
        if debugSaid[key] then return end
        debugSaid[key] = true
    end
    MS.Say("|cff9aa0a6kills:|r " .. _fmt(...))
end
function MS:KillDebug()
    debugKills = not debugKills
    wipe(debugSaid)
    MS.Say("Kill debug " .. (debugKills and "on" or "off"))
    if debugKills then
        local run = MS.currentRun
        Debug(nil, "run %s, in dungeon %s, listening %s", tostring(run ~= nil), tostring(MS.inDungeon),
            tostring(MS._RunStatsListening and MS._RunStatsListening()))
    end
end

-- Who the unit is: its GUID, or, when the game hides that, its nameplate
-- (the same mob for as long as the plate is up).
local function UnitKey(unit)
    local raw = UnitGUID(unit)
    local guid = MS.Readable(raw)
    if guid then
        if not (guid:find("^Creature") or guid:find("^Vehicle")) then   -- players, pets
            Debug("kind" .. (guid:match("^%a+") or "?"), "%s: not a creature (%s)", unit, guid:match("^%a+") or "?")
            return nil
        end
        return guid
    end
    if unit:find("^nameplate") then return "plate:" .. unit end
    Debug("noguid" .. unit, "%s: no readable GUID (%s)", unit, MS.IsSecret(raw) and "hidden" or type(raw))
end

-- A unit the game shows: a hostile mob is remembered alive, and counted
-- once when seen dead. A corpse never seen alive isn't counted (it may have
-- died before you came), nor one someone outside the group killed.
local function CheckUnit(unit)
    local run = MS.currentRun
    if not (run and MS.inDungeon) or type(unit) ~= "string" then return end
    if not (UnitExists and Yes(UnitExists(unit))) then return end
    local key = UnitKey(unit)
    if not key or counted[key] then return end
    Track(run)
    local name = MS.Readable(UnitName(unit))
    if not Flag(UnitIsDead, unit) then
        if alive[key] then return end
        local hostile = UnitCanAttack ~= nil and Yes(UnitCanAttack("player", unit))
        local theirs = Flag(UnitPlayerControlled, unit)
        if hostile and not theirs then
            alive[key] = true
            Debug(nil, "%s alive (%s)", tostring(name), unit)
        else
            Debug("skip" .. key, "%s skipped: hostile %s, player's %s", tostring(name), tostring(hostile), tostring(theirs))
        end
        return
    end
    if not alive[key] then
        Debug("corpse" .. key, "%s dead, never seen alive (%s)", tostring(name), unit)
        return
    end
    counted[key], alive[key] = true, nil
    if Flag(UnitIsTapDenied, unit) then Debug(nil, "%s dead, someone else's", tostring(name)); return end
    local now = GetTime()
    -- Already counted from its XP line: by name, or any one when the name is hidden.
    if (name and Take(xpKills, name, now)) or (not name and TakeAny(xpKills, now)) then
        Debug(nil, "%s dead, already counted (XP)", tostring(name)); return
    end
    Put(seenKills, name or ANY, now)
    Debug(nil, "%s dead: counted", tostring(name))
    CountKill(run, name)
end
-- A nameplate going to another mob: the old one's "plate:" key is done with.
local function PlateReset(unit)
    if type(unit) ~= "string" then return end
    local k = "plate:" .. unit
    alive[k], counted[k] = nil, nil
end

-- Everything the game shows right now (after a fight, in case an event was missed).
local function CheckAll()
    for i = 1, 40 do CheckUnit("nameplate" .. i) end
    CheckUnit("target"); CheckUnit("focus"); CheckUnit("mouseover")
    for i = 1, 4 do CheckUnit("party" .. i .. "target") end
end
MS._RunStatsCheckUnit = CheckUnit          -- for tests

local function OnRepLine(text)
    local run = MS.currentRun
    if not (run and MS.inDungeon) or type(Plain(text)) ~= "string" then return end
    for _, fp in ipairs(REP_PATTERNS) do
        local faction, amount = MS.MatchFormat(text, fp)
        if faction and amount then
            amount = tonumber(amount)
            if amount and amount > 0 then
                local rep = Progress(run).rep
                rep[faction] = (rep[faction] or 0) + amount
                Changed(run)
            end
            return
        end
    end
end

-- ── Quests ─────────────────────────────────────────────────────────────────
-- Every quest in your log with whether it's complete, by quest ID.
local function QuestLog()
    local out = {}
    local C_QuestLog = rawget(_G, "C_QuestLog")
    if GetNumQuestLogEntries and GetQuestLogTitle then           -- classic-style log
        local n = GetNumQuestLogEntries() or 0
        for i = 1, n do
            local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            if title and not isHeader and questID then
                -- The game's own answer when it has one; else the log line's flag.
                local done = isComplete == 1 or isComplete == true
                if C_QuestLog and C_QuestLog.IsComplete then
                    local ok, v = pcall(C_QuestLog.IsComplete, questID)
                    if ok and type(v) == "boolean" then done = v end
                end
                out[questID] = { title = title, done = done, index = i }
            end
        end
    elseif C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
                out[info.questID] = { title = info.title, done = done == true }
            end
        end
    end
    return out
end

-- quest ID -> whether it was complete when last seen. A quest counts only
-- when it's seen incomplete and later complete, AND the game said it made
-- progress in here. Right after a loading screen the log fills in over a
-- moment (even quests long since done read as not done at first), and
-- quests under collapsed headers aren't listed: neither proves anything.
local seen = {}
-- Progress the game reported during the run: per quest (QUEST_WATCH_UPDATE),
-- and the time of the last objective line ("Arcane Mote: 1/1").
local progressed = {}
local lastObjectiveAt = -math.huge
local OBJECTIVE_GRACE = 5            -- a quest completing within this of a line

local function QuestBaseline()
    wipe(seen); wipe(progressed)
    lastObjectiveAt = -math.huge
    for id, q in pairs(QuestLog()) do seen[id] = q.done end
end

-- QUEST_WATCH_UPDATE: an objective of this quest moved on. Classic clients
-- give the log index, newer ones the quest ID.
local function OnQuestProgress(arg)
    if type(arg) ~= "number" then return end
    local id = arg
    if GetQuestLogTitle and GetNumQuestLogEntries and arg <= (GetNumQuestLogEntries() or 0) then
        local qid = select(8, GetQuestLogTitle(arg))
        if type(qid) == "number" then id = qid end
    end
    progressed[id] = true
end

-- UI_INFO_MESSAGE: "Arcane Mote: 1/1", "Kobold slain: 4/10".
local function OnInfoMessage(msg)
    msg = Plain(msg)
    if type(msg) == "string" and msg:find("%d+/%d+") then lastObjectiveAt = GetTime() end
end

-- What a quest gives when handed in, from your quest log (classic logs read
-- the selected quest, so the selection is put back after). Counted with the
-- run as soon as the quest is done in here: you don't have to hand it in.
local function QuestReward(id, index)
    local okX, xp, okM, money
    local XP, Money = rawget(_G, "GetQuestLogRewardXP"), rawget(_G, "GetQuestLogRewardMoney")
    local Select, Selected = rawget(_G, "SelectQuestLogEntry"), rawget(_G, "GetQuestLogSelection")
    if index and Select and XP then
        local prev = Selected and Selected()
        pcall(Select, index)
        okX, xp = pcall(XP)
        if Money then okM, money = pcall(Money) end
        if prev then pcall(Select, prev) end
    elseif XP then
        okX, xp = pcall(XP, id)
        if Money then okM, money = pcall(Money, id) end
    end
    xp = okX and Plain(xp) or nil
    money = okM and Plain(money) or nil
    return type(xp) == "number" and xp > 0 and xp or nil, type(money) == "number" and money > 0 and money or nil
end

-- Quest XP and gold apart from what the dungeon gave: totals of each
-- quest's reward (questRewards, by the quest's place in the list).
local function QuestTotals(p)
    local x, g = 0, 0
    for _, r in pairs(p.questRewards or {}) do x = x + (r.x or 0); g = g + (r.g or 0) end
    p.qx = x > 0 and x or nil
    p.qg = g > 0 and g or nil
end

local function NoteQuest(run, id, title, xp, money)
    local p = Progress(run)
    p.questIDs = p.questIDs or {}
    if p.questIDs[id] then return false end
    p.quests[#p.quests + 1] = title or L["Quest %s"]:format(tostring(id))
    p.questIDs[id] = #p.quests
    if xp or money then
        p.questRewards = p.questRewards or {}
        p.questRewards[#p.quests] = { x = xp, g = money }
        QuestTotals(p)
    end
    return true
end

local pendingQuests = false
local function OnQuestLog()
    local run = MS.currentRun
    if not (run and MS.inDungeon) then return end
    local any = false
    local recentLine = GetTime() - lastObjectiveAt <= OBJECTIVE_GRACE
    for id, q in pairs(QuestLog()) do
        if q.done and seen[id] == false and (progressed[id] or recentLine) then
            if NoteQuest(run, id, q.title, QuestReward(id, q.index)) then any = true end
        end
        seen[id] = q.done
    end
    if any then Changed(run) end
end

-- A quest handed in inside the dungeon (some have their giver there). Its
-- reward also moved your XP bar and purse, which count as the dungeon's:
-- moved over to the quest's side, at what the game actually gave.
local function OnQuestTurnedIn(questID, xpReward, moneyReward)
    local run = MS.currentRun
    questID = Plain(questID)
    if not (run and MS.inDungeon) or not questID then return end
    xpReward, moneyReward = tonumber(Plain(xpReward)), tonumber(Plain(moneyReward))
    local p = Progress(run)
    local C_QuestLog = rawget(_G, "C_QuestLog")
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    NoteQuest(run, questID, Plain(title))
    local i = p.questIDs and p.questIDs[questID]
    if type(i) == "number" and ((xpReward or 0) > 0 or (moneyReward or 0) > 0) then
        p.questRewards = p.questRewards or {}
        local r = p.questRewards[i] or {}
        p.questRewards[i] = r
        if r.inside then return end          -- (already moved over)
        r.inside = true
        if (xpReward or 0) > 0 then
            r.x = xpReward
            p.xp = (p.xp or 0) - xpReward      -- (the bar may move before or after this)
        end
        if (moneyReward or 0) > 0 then
            r.g = moneyReward
            p.gold = (p.gold or 0) - moneyReward
        end
        QuestTotals(p)
    end
    Changed(run)
end

-- ── Events ─────────────────────────────────────────────────────────────────
local function OnEvent(event, ...)
    if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        -- PLAYER_LEVEL_UP comes before the bar shows the new level: read a moment later.
        C_Timer.After(event == "PLAYER_LEVEL_UP" and 0.5 or 0, OnXP)
    elseif event == "PLAYER_MONEY" then
        OnMoney()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        OnXPLine((...))
    elseif event == "UNIT_HEALTH" then
        CheckUnit((...))
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        PlateReset((...)); CheckUnit((...))
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        CheckUnit((...)); PlateReset((...))
    elseif event == "UNIT_TARGET" then
        local unit = ...
        if type(unit) == "string" then CheckUnit(unit .. "target") end
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckUnit("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        CheckUnit("focus")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        CheckUnit("mouseover")
    elseif event == "PLAYER_REGEN_ENABLED" then
        CheckAll()
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        OnRepLine((...))
    elseif event == "QUEST_LOG_UPDATE" then
        if pendingQuests then return end           -- fires in bursts: read once
        pendingQuests = true
        C_Timer.After(0.5, function() pendingQuests = false; OnQuestLog() end)
    elseif event == "QUEST_TURNED_IN" then
        OnQuestTurnedIn(...)
    elseif event == "QUEST_WATCH_UPDATE" then
        OnQuestProgress((...))
    elseif event == "UI_INFO_MESSAGE" then
        OnInfoMessage(select(2, ...))
    end
end

-- Listened for only while a run is recording.
local EVENTS = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "CHAT_MSG_COMBAT_XP_GAIN",
                 "CHAT_MSG_COMBAT_FACTION_CHANGE", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
                 "QUEST_WATCH_UPDATE", "UI_INFO_MESSAGE",
                 "UNIT_HEALTH", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_TARGET",
                 "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
                 "PLAYER_REGEN_ENABLED" }
local listening = false
MS._RunStatsListening = function() return listening end
MS:WatchRunState(function(state)
    local want = state == "active"
    if want == listening then return end
    listening = want
    if want then
        if #KILL_PATTERNS == 0 then BuildPatterns() end
        Baseline(); QuestBaseline()
        if MS.currentRun then Progress(MS.currentRun) end
        for _, ev in ipairs(EVENTS) do MS:On(ev, OnEvent) end
    else
        for _, ev in ipairs(EVENTS) do MS:Off(ev, OnEvent) end
    end
end)

-- ── Shown as ───────────────────────────────────────────────────────────────
-- "4g 12s 30c" (copper), largest parts only.
-- The coin letters and the thousands separator are the game's own, so they
-- match the client's language ("g" / "G" / "з" ...; "," / ".").
local function GameString(name, default)
    local v = rawget(_G, name)
    return (type(v) == "string" and v ~= "") and v or default
end

function MS.FormatGold(copper)
    copper = math.floor(copper or 0)
    local G, S, C = GameString("GOLD_AMOUNT_SYMBOL", "g"), GameString("SILVER_AMOUNT_SYMBOL", "s"),
                    GameString("COPPER_AMOUNT_SYMBOL", "c")
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if g > 0 then return MS.FormatThousands(g) .. G .. (s > 0 and (" " .. s .. S) or "") end
    if s > 0 then return s .. S .. (c > 0 and (" " .. c .. C) or "") end
    return c .. C
end

-- 12400 -> "12,400".
function MS.FormatThousands(n)
    local s = tostring(math.floor(n or 0))
    local sep = GameString("LARGE_NUMBER_SEPARATOR", ",")
    local out = s:reverse():gsub("(%d%d%d)", "%1\1"):reverse()
    return (out:gsub("^\1", ""):gsub("\1", function() return sep end))
end

-- What a run did for your character (WoW Forever): experience and levels,
-- mobs killed, quests completed, gold looted, reputation gained.
--
--   run.progress = { xp, levels, kills, quests = { titles }, gold (copper),
--                    rep = { [faction] = amount } }
--
-- The combat log is blocked inside instances, so each number comes from
-- something the game still shows:
--   xp, levels   your XP bar, read whenever it changes
--   kills        "<mob> dies, you gain N experience." in chat: kills that
--                gave you XP (none for grey mobs, or at max level)
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

local IsSecret = _G["MythicScoreboard"].IsSecret
local function Plain(v)
    if v == nil or IsSecret(v) then return nil end
    return v
end

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
-- A localized line like "%s dies, you gain %d experience." as a pattern for
-- its start, up to the first number (the rest varies: rested, group bonus).
local function Escape(s) return (s:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")) end
local function Prefix(fmt)
    if type(fmt) ~= "string" then return nil end
    local cut = fmt:find("%d", 1, true) or fmt:find("%1$d", 1, true) or fmt:find("%2$d", 1, true)
    local head = cut and fmt:sub(1, cut - 1) or fmt
    local p = Escape(head)
    p = p:gsub("%%%%s", "(.-)"):gsub("%%%%%d%%%$s", "(.-)")
    return "^" .. p
end

-- A full line with a name and an amount, either order.
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = Escape(fmt)
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    p = p:gsub("%%%%(%d)%%%$s", "(.+)"):gsub("%%%%(%d)%%%$d", "(%%d+)")
    local swapped = (fmt:find("%2$s", 1, true) or 99) < (fmt:find("%1$d", 1, true) or 0)
    return "^" .. p, swapped
end

local KILL_PATTERNS, REP_PATTERNS = {}, {}
local function BuildPatterns()
    wipe(KILL_PATTERNS); wipe(REP_PATTERNS)
    for _, g in ipairs({ "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP",
                         "COMBATLOG_XPGAIN_FIRSTPERSON_RAID", "COMBATLOG_XPGAIN_EXHAUSTION1",
                         "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION1_RAID" }) do
        local p = Prefix(rawget(_G, g))
        if p then KILL_PATTERNS[#KILL_PATTERNS + 1] = p end
    end
    for _, g in ipairs({ "FACTION_STANDING_INCREASED", "FACTION_STANDING_INCREASED_BONUS",
                         "FACTION_STANDING_INCREASED_DOUBLE_BONUS", "FACTION_STANDING_INCREASED_ACH_BONUS" }) do
        local p, swapped = Pattern(rawget(_G, g))
        if p then REP_PATTERNS[#REP_PATTERNS + 1] = { p, swapped } end
    end
end
MS._RunStatsPatterns = BuildPatterns       -- for tests

local function OnXPLine(text)
    local run = MS.currentRun
    if not (run and MS.inDungeon) or type(Plain(text)) ~= "string" then return end
    for _, p in ipairs(KILL_PATTERNS) do
        local mob = text:match(p)
        if mob and mob ~= "" then
            MS:NoteMobDied(mob)
            Progress(run).kills = Progress(run).kills + 1
            Changed(run)
            return
        end
    end
end

local function OnRepLine(text)
    local run = MS.currentRun
    if not (run and MS.inDungeon) or type(Plain(text)) ~= "string" then return end
    for _, pp in ipairs(REP_PATTERNS) do
        local a, b = text:match(pp[1])
        if a and b then
            local faction, amount = a, b
            if pp[2] or tonumber(a) then faction, amount = b, a end
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
                out[questID] = { title = title, done = done }
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

local function NoteQuest(run, id, title)
    local p = Progress(run)
    p.questIDs = p.questIDs or {}
    if p.questIDs[id] then return false end
    p.questIDs[id] = true
    p.quests[#p.quests + 1] = title or L["Quest %s"]:format(tostring(id))
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
            if NoteQuest(run, id, q.title) then any = true end
        end
        seen[id] = q.done
    end
    if any then Changed(run) end
end

-- A quest handed in inside the dungeon (some have their giver there).
local function OnQuestTurnedIn(questID)
    local run = MS.currentRun
    if not (run and MS.inDungeon) or not Plain(questID) then return end
    local C_QuestLog = rawget(_G, "C_QuestLog")
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    if NoteQuest(run, questID, Plain(title)) then Changed(run) end
end

-- ── Events ─────────────────────────────────────────────────────────────────
local frame = CreateFrame("Frame")
local EVENTS = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "CHAT_MSG_COMBAT_XP_GAIN",
                 "CHAT_MSG_COMBAT_FACTION_CHANGE", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
                 "QUEST_WATCH_UPDATE", "UI_INFO_MESSAGE" }
local listening = false
MS:WatchRunState(function(state)
    local want = state == "active"
    if want == listening then return end
    listening = want
    if want then
        if #KILL_PATTERNS == 0 then BuildPatterns() end
        Baseline(); QuestBaseline()
        if MS.currentRun then Progress(MS.currentRun) end
        for _, ev in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, ev) end
    else
        for _, ev in ipairs(EVENTS) do pcall(frame.UnregisterEvent, frame, ev) end
    end
end)

frame:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(function(...)
        if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
            -- PLAYER_LEVEL_UP comes before the bar shows the new level: read a moment later.
            C_Timer.After(event == "PLAYER_LEVEL_UP" and 0.5 or 0, OnXP)
        elseif event == "PLAYER_MONEY" then
            OnMoney()
        elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
            OnXPLine((...))
        elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
            OnRepLine((...))
        elseif event == "QUEST_LOG_UPDATE" then
            if pendingQuests then return end           -- fires in bursts: read once
            pendingQuests = true
            C_Timer.After(0.5, function() pendingQuests = false; OnQuestLog() end)
        elseif event == "QUEST_TURNED_IN" then
            OnQuestTurnedIn((...))
        elseif event == "QUEST_WATCH_UPDATE" then
            OnQuestProgress((...))
        elseif event == "UI_INFO_MESSAGE" then
            OnInfoMessage(select(2, ...))
        end
    end, ...)
    if not ok then MS:ReportError("Run stats", err) end
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

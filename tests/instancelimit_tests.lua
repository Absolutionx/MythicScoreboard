-- usage: lua5.1 instancelimit_tests.lua DIR TOC
-- The instance limit (Core/InstanceLimit.lua): 5 an hour for each dungeon
-- (WoW Forever's hotfixes of 20 November 2026; it was 10), what counts as a
-- new instance, the warnings, being turned away (and learning the limit is
-- on all dungeons together if the game says so), a dungeon opening again,
-- 12-hour times, and where it's shown (in-run frame, minimap tooltip,
-- /sb limit).
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")

-- A clock the test moves (the game's time()), and the game's messages.
local clock = os.time({ year = 2026, month = 11, day = 18, hour = 13, min = 30, sec = 0 })
time = function() return clock end
INSTANCE_RESET_SUCCESS = "%s has been reset."
TRANSFER_ABORT_TOO_MANY_INSTANCES = "You have entered too many instances recently."
local cvars = {}
GetCVar = function(k) return cvars[k] end

M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
-- WoW Forever only: elsewhere the files aren't loaded at all.
if not MS.InstanceLimit then
    io.stdout:write("instancelimit_tests: not on this game (WoW Forever only)\n")
    os.exit(0)
end
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4)

local function At(h, m) clock = os.time({ year = 2026, month = 11, day = 18, hour = h, min = m, sec = 0 }) end
local function Later(minutes) clock = clock + minutes * 60; M.Advance(minutes * 60) end
local function Enter(name, map) M.instance = { name, "party", 1, map }; M.Fire("PLAYER_ENTERING_WORLD", false, false) end
local function Leave() M.instance = { "Orgrimmar", "none", 0 }; M.Fire("PLAYER_ENTERING_WORLD", false, false) end
local function Used(d) return MS:InstanceLimit(d).used end
local function Printed(pat)
    for _, p in ipairs(M.printed) do if p:find(pat, 1, true) then return p end end
end

Leave()
check("nothing yet", #MS:InstanceLimit().dungeons == 0)
check("the default limit: 5", MS:InstanceLimit().limit == 5, MS:InstanceLimit().limit)
check("counted each dungeon on its own", MS:InstanceLimit().scope == "dungeon")

-- A dungeon: counted once.
At(13, 32)
Enter("Ragefire Chasm", 389)
local info = MS:InstanceLimit()
check("entered: counted", info.used == 1 and info.dungeon == "Ragefire Chasm", info.used)
check("entered: which and who", info.entries[1].name == "Ragefire Chasm" and info.entries[1].char ~= nil)
check("next frees an hour after", info.nextFree == clock + 3600)

-- Inside: a zone change, a /reload: the same.
M.Fire("ZONE_CHANGED_NEW_AREA")
M.Fire("PLAYER_ENTERING_WORLD", false, true)
check("inside, a /reload: not again", Used() == 1, Used())

-- A corpse run: out and back in within half an hour, the same instance.
Leave(); Later(5); Enter("Ragefire Chasm", 389)
check("back in after 5 min: the same", Used() == 1, Used())

-- Reset, then back in: a new one.
Leave()
M.Fire("CHAT_MSG_SYSTEM", "Ragefire Chasm has been reset.")
Later(1); Enter("Ragefire Chasm", 389)
check("after a reset: new", Used() == 2, Used())

-- Out for more than half an hour: the game has closed it.
Leave(); Later(31); Enter("Ragefire Chasm", 389)
check("back after 31 min: new", Used() == 3, Used())

-- Another dungeon: its own count; Ragefire's stays.
Leave(); Later(1); Enter("Wailing Caverns", 43)
check("another dungeon: its own", Used() == 1 and Used("Ragefire Chasm") == 3, Used() .. " " .. Used("Ragefire Chasm"))
check("outside: the last one you were in", (function() Leave(); return MS:InstanceLimit().dungeon end)() == "Wailing Caverns")

-- An alt in the same dungeon: its own instance.
local realName = UnitName
UnitName = function(u) if u == "player" then return "Altname" end return realName(u) end
Enter("Wailing Caverns", 43)
check("an alt: new", Used("Wailing Caverns") == 2, Used("Wailing Caverns"))
check("an alt: its name kept", MS:InstanceLimit("Wailing Caverns").entries[2].char == "Altname")
UnitName = realName

-- Raids count too; the open world and battlegrounds don't.
Leave()
M.instance = { "Warsong Gulch", "pvp", 0, 489 }; M.Fire("PLAYER_ENTERING_WORLD", false, false)
check("a battleground: not counted", #MS:InstanceLimit().dungeons == 2, #MS:InstanceLimit().dungeons)
Leave()

-- Down to the last run of a dungeon: a warning; the last used: another.
local s = MythicScoreboardAccountDB.instanceLimit[GetRealmName()]
local function Again(name, map)
    Later(1); Enter(name, map); Leave(); M.Fire("CHAT_MSG_SYSTEM", name .. " has been reset.")
end
M.Fire("CHAT_MSG_SYSTEM", "Ragefire Chasm has been reset.")
M.printed = {}
Again("Ragefire Chasm", 389)
check("one left: said", Printed("One Ragefire Chasm run left this hour") ~= nil, M.printed[1])
M.printed = {}
Again("Ragefire Chasm", 389)
local last = Printed("That was your last Ragefire Chasm run this hour")
check("the last: said", last ~= nil, M.printed[1])
check("the last: when it opens again, 12-hour", last and last:find("2:32 PM", 1, true) ~= nil, last)
check("Wailing Caverns: still open", Used("Wailing Caverns") == 2 and not MS:InstanceLimit("Wailing Caverns").locked)

-- 12-hour times, or 24 with the game's clock set so.
-- (Times written without moving the clock: set back, it'd look like the
-- computer's clock was, below.)
local function T(h, m) return os.time({ year = 2026, month = 11, day = 18, hour = h, min = m, sec = 0 }) end
check("12-hour", MS.ClockTime(T(14, 32)) == "2:32 PM", MS.ClockTime(T(14, 32)))
check("12-hour, after midnight", MS.ClockTime(T(0, 5)) == "12:05 AM", MS.ClockTime(T(0, 5)))
cvars.timeMgrUseMilitaryTime = "1"
check("24-hour when the game's clock is", MS.ClockTime(T(14, 32)) == "14:32", MS.ClockTime(T(14, 32)))
cvars.timeMgrUseMilitaryTime = nil

-- Turned away at Ragefire's door: it's locked; Wailing Caverns isn't; a
-- countdown names it.
At(14, 5)
M.Fire("UI_ERROR_MESSAGE", 0, "You have entered too many instances recently.")
info = MS:InstanceLimit("Ragefire Chasm")
check("turned away: locked", info.locked == true)
check("turned away: still 5 each", info.limit == 5, info.limit)
check("turned away: the others open", not MS:InstanceLimit("Wailing Caverns").locked)
local panel = rawget(_G, "MythicScoreboardInstanceLimit")
check("turned away: the countdown shows", panel and panel:IsShown())
local untilText
for _, w in ipairs(M.allFrames) do
    if w._kind == "FontString" and w._shown and (w._text or ""):find("until you can enter", 1, true) then untilText = w._text end
end
check("the countdown names it", untilText and untilText:find("Ragefire Chasm", 1, true) ~= nil, untilText)

-- Turned away at a dungeon with only a couple of runs: then the limit's on
-- all of them together; learned.
local keepEntries, keepLast, keepLocked = s.entries, s.last, s.locked
s.entries = {
    { t = clock - 600, map = 389, name = "Ragefire Chasm", char = "x" },
    { t = clock - 500, map = 389, name = "Ragefire Chasm", char = "x" },
    { t = clock - 400, map = 43, name = "Wailing Caverns", char = "x" },
    { t = clock - 300, map = 43, name = "Wailing Caverns", char = "x" },
}
s.last, s.locked = { map = 43, name = "Wailing Caverns", char = "x", at = clock - 300, leftAt = clock - 200 }, {}
M.Fire("CHAT_MSG_SYSTEM", "You have entered too many instances recently.")
local all = MS:InstanceLimit()
check("on all together: learned", all.scope == "all" and all.limit == 4 and all.locked, all.scope .. " " .. all.limit)
s.scope, s.limit, s.lockedUntil = nil, nil, nil
s.entries, s.last, s.locked = keepEntries, keepLast, keepLocked

-- What the old version learned (10, on all together) is dropped.
s.v, s.limit, s.scope = 1, 10, "all"
check("an old learned limit dropped", MS:InstanceLimit().limit == 5 and MS:InstanceLimit().scope == "dungeon",
    MS:InstanceLimit().limit)
s.locked["Ragefire Chasm"] = info.nextFree
M.Fire("PLAYER_ENTERING_WORLD", false, false)   -- (watching for it again)

-- An hour after the first Ragefire run: open again, said once; the countdown goes.
M.printed = {}
local first = MS:InstanceLimit("Ragefire Chasm").entries[1].t
clock = first + 3601
M.Advance(3700)
check("open again: said", Printed("Ragefire Chasm is open again") ~= nil, M.printed[1])
check("open again: not locked", not MS:InstanceLimit("Ragefire Chasm").locked)
check("open again: the countdown gone", not panel:IsShown())

-- /sb limit: a line a dungeon.
M.printed = {}
SlashCmdList.MYTHICSCOREBOARD("limit")
check("/sb limit: Ragefire", Printed("Ragefire Chasm: 4 of 5 this hour.") ~= nil, M.printed[1])
check("/sb limit: Wailing Caverns", Printed("Wailing Caverns: 2 of 5 this hour.") ~= nil, M.printed[2])
M.printed = {}
SlashCmdList.MYTHICSCOREBOARD("help")
check("/sb help lists it", Printed("/sb limit") ~= nil)

-- The minimap button's tooltip: a line a dungeon.
local lines = {}
local realDouble, realLine = GameTooltip.AddDoubleLine, GameTooltip.AddLine
GameTooltip.AddDoubleLine = function(_, a, b) lines[#lines + 1] = tostring(a) .. " | " .. tostring(b) end
GameTooltip.AddLine = function(_, a) lines[#lines + 1] = tostring(a) end
local btn = rawget(_G, "MythicScoreboardMinimapButton")
if btn then
    btn:Fire("OnEnter")
    local joined = table.concat(lines, "\n")
    check("tooltip: the heading", joined:find("Dungeons this hour", 1, true) ~= nil, joined)
    check("tooltip: each dungeon", joined:find("Ragefire Chasm | 4 of 5", 1, true) ~= nil
        and joined:find("Wailing Caverns | 2 of 5", 1, true) ~= nil, joined)
end
GameTooltip.AddDoubleLine, GameTooltip.AddLine = realDouble, realLine

-- In a run: the in-run frame has the row, for that dungeon.
Enter("Wailing Caverns", 43); M.RunTimers(4)
MS:RefreshCompact()
local row
for _, w in ipairs(M.allFrames) do
    if w._kind == "FontString" and w._shown and w._text == "This dungeon this hour" then row = w end
end
if MS.currentRun then check("in-run frame: the row", row ~= nil) end
local val
for _, w in ipairs(M.allFrames) do
    if w._kind == "FontString" and w._shown and (w._text or ""):find("^%d+ of 5$") then val = w._text end
end
if MS.currentRun then check("in-run frame: this dungeon's count", val == "3 of 5", val) end
Leave(); M.RunTimers(4)

-- Warnings off: counted, not said.
MS:SetInstanceLimitWarn(false)
s.entries = {}
for i = 1, 4 do s.entries[i] = { t = clock - 60, map = 70, name = "Uldaman", char = "x" } end
s.last = nil
M.printed = {}
Enter("Uldaman", 70); Leave()
check("warnings off: counted", Used("Uldaman") == 5, Used("Uldaman"))
check("warnings off: nothing said", Printed("last Uldaman") == nil)
MS:SetInstanceLimitWarn(true)

-- /sb limit test: a preview, the in-run frame (with the row) and the countdown.
local before = #s.entries
M.printed = {}
SlashCmdList.MYTHICSCOREBOARD("limit test")
check("preview: on", MS:IsInstanceLimitPreviewOn() and MS:IsCompactPreviewOn())
check("preview: the countdown", rawget(_G, "MythicScoreboardInstanceLimit"):IsShown())
local shownRow
for _, w in ipairs(M.allFrames) do
    if w._kind == "FontString" and w._shown and w._text == "This dungeon this hour" then shownRow = true end
end
check("preview: the in-run frame's row", shownRow)
check("preview: nothing saved", #s.entries == before, #s.entries)
check("preview: nothing in chat", #M.printed == 0, M.printed[1])
-- The countdown: dragged, kept where it's put; the drag isn't a click.
local cd = rawget(_G, "MythicScoreboardInstanceLimit")
cd:Fire("OnDragStart"); cd:ClearAllPoints(); cd:SetPoint("CENTER", UIParent, "CENTER", 120, -40)
cd:Fire("OnDragStop"); cd:Fire("OnClick")
local pos = MS:GetSetting("limitPanelPos")
check("drag: kept", type(pos) == "table" and pos[1] == "CENTER" and pos[3] == 120 and pos[4] == -40, pos and table.concat(pos, ","))
check("drag: not a click (still shown)", cd:IsShown() and MS:IsInstanceLimitPreviewOn())
SlashCmdList.MYTHICSCOREBOARD("limit test")
check("preview: off again", not MS:IsInstanceLimitPreviewOn() and not MS:IsCompactPreviewOn())
check("preview off: the countdown gone", not rawget(_G, "MythicScoreboardInstanceLimit"):IsShown())
-- Done under the in-run frame's preview turns both off.
MS:ToggleInstanceLimitPreview()
MS:ToggleCompactPreview()
check("Done: both off", not MS:IsInstanceLimitPreviewOn() and not rawget(_G, "MythicScoreboardInstanceLimit"):IsShown())

-- A day later: all gone.
Later(25 * 60)
check("a day later: none", #MS:InstanceLimit().dungeons == 0, #MS:InstanceLimit().dungeons)

-- The computer's clock set back a day: what was "later" doesn't count.
Enter("Ragefire Chasm", 389); Leave()
check("clock: counted", Used("Ragefire Chasm") == 1, Used("Ragefire Chasm"))
clock = clock - 86400
check("clock set back: the run 'from the future' isn't counted", Used("Ragefire Chasm") == 0, Used("Ragefire Chasm"))
local st = MythicScoreboardAccountDB.instanceLimit
for _, s2 in pairs(st) do
    s2.locked["Wailing Caverns"] = clock + 5 * 86400
    s2.lockedUntil = clock + 5 * 86400
end
local wc = MS:InstanceLimit("Wailing Caverns")
check("clock: a lock lasts an hour at most", wc.locked and wc.nextFree <= clock + 3600, wc.nextFree and (wc.nextFree - clock))
for _, s2 in pairs(st) do
    check("clock: all-lock capped too", s2.lockedUntil <= clock + 3600)
    s2.locked = "junk"; s2.entries = { { t = "x" }, 5 }
end
check("junk saved data: no error", pcall(MS.InstanceLimit, MS, "Wailing Caverns"))

io.stdout:write(("instancelimit_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

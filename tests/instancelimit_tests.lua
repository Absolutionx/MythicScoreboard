-- usage: lua5.1 instancelimit_tests.lua DIR TOC
-- The instance limit (Core/InstanceLimit.lua): what counts as a new
-- instance, the warnings, being turned away, a slot freeing, 12-hour times,
-- and where it's shown (in-run frame, minimap tooltip, /sb limit).
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
local function Used() return MS:InstanceLimit().used end
local function Printed(pat)
    for _, p in ipairs(M.printed) do if p:find(pat, 1, true) then return p end end
end

Leave()
local start = Used()
check("nothing yet", start == 0, start)

-- A dungeon: counted once.
At(13, 32)
Enter("Ragefire Chasm", 389)
local info = MS:InstanceLimit()
check("entered: counted", info.used == 1, info.used)
check("entered: which and who", info.entries[1].name == "Ragefire Chasm" and info.entries[1].char ~= nil)
check("the default limit", info.limit == 10, info.limit)
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

-- Another dungeon straight after: new.
Leave(); Later(1); Enter("Wailing Caverns", 43)
check("another dungeon: new", Used() == 4, Used())

-- An alt in the same dungeon: its own instance.
Leave()
local realName = UnitName
UnitName = function(u) if u == "player" then return "Altname" end return realName(u) end
Enter("Wailing Caverns", 43)
check("an alt: new", Used() == 5, Used())
check("an alt: its name kept", MS:InstanceLimit().entries[5].char == "Altname")
UnitName = realName

-- Raids count too; the open world and battlegrounds don't.
Leave()
M.instance = { "Warsong Gulch", "pvp", 0, 489 }; M.Fire("PLAYER_ENTERING_WORLD", false, false)
check("a battleground: not counted", Used() == 5, Used())
Leave()

-- Down to the last: a warning; the last used: another.
local s = MythicScoreboardAccountDB.instanceLimit[GetRealmName()]
for i = 1, 3 do
    Later(1); Enter("The Deadmines " .. i, 36 + i * 1000); Leave()
end
check("eight used", Used() == 8, Used())
M.printed = {}
Later(1); Enter("Shadowfang Keep", 33); Leave()
check("one left: said", Printed("One instance left this hour") ~= nil, M.printed[1])
M.printed = {}
Later(1); Enter("Blackfathom Deeps", 48); Leave()
local last = Printed("That was your last instance this hour")
check("the last: said", last ~= nil, M.printed[1])
check("the last: when the next frees, 12-hour", last and last:find("2:32 PM", 1, true) ~= nil, last)

-- 12-hour times, or 24 with the game's clock set so.
At(14, 32)
check("12-hour", MS.ClockTime(clock) == "2:32 PM", MS.ClockTime(clock))
At(0, 5)
check("12-hour, after midnight", MS.ClockTime(clock) == "12:05 AM", MS.ClockTime(clock))
cvars.timeMgrUseMilitaryTime = "1"
At(14, 32)
check("24-hour when the game's clock is", MS.ClockTime(clock) == "14:32", MS.ClockTime(clock))
cvars.timeMgrUseMilitaryTime = nil

-- Turned away at the door: the limit is what was used; a countdown shows.
At(13, 50)
M.Fire("UI_ERROR_MESSAGE", 0, "You have entered too many instances recently.")
info = MS:InstanceLimit()
check("turned away: locked", info.locked == true)
check("turned away: the limit learned", info.limit == info.used and info.used == 10, info.limit .. " " .. info.used)
local panel = rawget(_G, "MythicScoreboardInstanceLimit")
check("turned away: the countdown shows", panel and panel:IsShown())

-- A client with a lower limit (5): learned at the first turn-away.
local saved = s.limit
s.limit = nil
local keep = s.entries
s.entries = { keep[1], keep[2], keep[3], keep[4], keep[5] }
M.Fire("CHAT_MSG_SYSTEM", "You have entered too many instances recently.")
check("a lower limit learned", MS:InstanceLimit().limit == 5, MS:InstanceLimit().limit)
s.entries, s.limit = keep, saved

-- The oldest hour passes: a slot frees, said once, and the countdown goes.
M.printed = {}
clock = keep[1].t + 3601
M.Advance(3700)
check("a slot frees: said", Printed("A dungeon slot is free again") ~= nil, M.printed[1])
check("a slot frees: not locked", not MS:InstanceLimit().locked)
check("a slot frees: the countdown gone", not panel:IsShown())

-- /sb limit
M.printed = {}
SlashCmdList.MYTHICSCOREBOARD("limit")
check("/sb limit: the count", Printed("Instances this hour:") ~= nil, M.printed[1])
check("/sb limit: each one", Printed("Wailing Caverns") ~= nil)
M.printed = {}
SlashCmdList.MYTHICSCOREBOARD("help")
check("/sb help lists it", Printed("/sb limit") ~= nil)

-- The minimap button's tooltip.
local lines = {}
local realDouble = GameTooltip.AddDoubleLine
GameTooltip.AddDoubleLine = function(_, a, b) lines[#lines + 1] = tostring(a) .. " | " .. tostring(b) end
local btn = rawget(_G, "MythicScoreboardMinimapButton")
if btn then
    btn:Fire("OnEnter")
    local joined = table.concat(lines, "\n")
    check("tooltip: the count", joined:find("Instances this hour | ", 1, true) ~= nil, joined)
    check("tooltip: each with its time", joined:find("PM  ", 1, true) ~= nil, joined)
end
GameTooltip.AddDoubleLine = realDouble

-- In a run: the in-run frame has the row.
Enter("Ragefire Chasm", 389); M.RunTimers(4)
MS:RefreshCompact()
local row
for _, w in ipairs(M.allFrames) do
    if w._kind == "FontString" and w._shown and w._text == "Instances this hour" then row = w end
end
if MS.currentRun then check("in-run frame: the row", row ~= nil) end
local val
for _, w in ipairs(M.allFrames) do
    if w._kind == "FontString" and w._shown and (w._text or ""):find("^%d+ of %d+$") then val = w._text end
end
if MS.currentRun then check("in-run frame: the count", val ~= nil, val) end
Leave(); M.RunTimers(4)

-- Warnings off: counted, not said.
MS:SetInstanceLimitWarn(false)
s.entries = {}
for i = 1, 9 do s.entries[i] = { t = clock - 60, map = i, name = "D" .. i, char = "x" } end
M.printed = {}
Enter("Uldaman", 70); Leave()
check("warnings off: counted", Used() == 10, Used())
check("warnings off: nothing said", Printed("last instance") == nil)
MS:SetInstanceLimitWarn(true)

-- /sb limit test: a preview, the in-run frame (with the row) and the countdown.
local before = Used()
M.printed = {}
SlashCmdList.MYTHICSCOREBOARD("limit test")
check("preview: on", MS:IsInstanceLimitPreviewOn() and MS:IsCompactPreviewOn())
check("preview: the countdown", rawget(_G, "MythicScoreboardInstanceLimit"):IsShown())
local shownRow
for _, w in ipairs(M.allFrames) do
    if w._kind == "FontString" and w._shown and w._text == "Instances this hour" then shownRow = true end
end
check("preview: the in-run frame's row", shownRow)
check("preview: nothing saved", Used() == before, Used())
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
check("a day later: none", Used() == 0, Used())

io.stdout:write(("instancelimit_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

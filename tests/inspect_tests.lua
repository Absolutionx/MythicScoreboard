-- usage: lua5.1 inspect_tests.lua DIR TOC
-- Inspects: not for ever, not while your Inspect window is open, never
-- someone else's numbers; and listeners that only matter in a run.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.startOnPull = true
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local RFC, WORLD = { "Ragefire Chasm", "party", 1 }, { "Orgrimmar", "none", 0 }
local function zone(inst)
    M.instance = inst
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.RunTimers(8)
end

-- The game's inspect, as the addon uses it.
local asked, cleared, ilvl = {}, 0, {}
CanInspect = function() return true end
NotifyInspect = function(unit) asked[#asked + 1] = unit end
ClearInspectPlayer = function() cleared = cleared + 1 end
C_PaperDollInfo.GetInspectItemLevel = function(unit) return ilvl[unit] or 0 end
rawset(_G, "GetAverageItemLevel", function() return 61.4, 60.9 end)
local function count(unit)
    local n = 0
    for _, u in ipairs(asked) do if u == unit then n = n + 1 end end
    return n
end

M.instance = WORLD
M.Fire("ADDON_LOADED", "MythicScoreboard")
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
M.groupSize = 2                             -- you and Akasha
zone(RFC)
local me, other = MS:PlayerForUnit("player"), MS:PlayerForUnit("party1")
check("in a run", me ~= nil and other ~= nil)

-- Your own item level: read straight off, no inspect.
check("own item level: what you have on", me.itemLevel == 60, me.itemLevel)
check("own item level: no inspect of yourself", count("player") == 0, count("player"))

-- Someone whose inspect never brings anything: asked a few times, with
-- longer and longer waits, then no more.
for _ = 1, 400 do MS:PopulateAll(); M.Advance(2) end       -- over 13 minutes of readings
local n = count("party1")
check("no data: asked again, but not for ever", n >= 2 and n <= 5, n)
for _ = 1, 100 do MS:PopulateAll(); M.Advance(2) end
check("no data: then left alone", count("party1") == n, count("party1"))

-- A new run: asked again.
asked = {}
MS:AbandonRun(); zone(WORLD); zone(RFC)
other = MS:PlayerForUnit("party1")
check("a new run: asked again", count("party1") >= 1, count("party1"))
-- (An inspect on its way: the next one allowed, sent, not yet answered.)
M.Advance(6); asked = {}
MS:PopulateAll(); M.Advance(1)
check("an inspect on its way", count("party1") == 1, count("party1"))

-- Another inspect coming back meanwhile (yours, another addon's): not the
-- one waited for, and not this player's item level.
ilvl.party1, ilvl.player = 58, 99
M.Fire("INSPECT_READY", "Player-1-AAA")                    -- (you, not Akasha)
check("someone else's inspect: not taken", other.itemLevel == 0, other.itemLevel)
M.Fire("INSPECT_READY", "Player-1-BBB")
check("the one waited for: taken", other.itemLevel == 58, other.itemLevel)

-- Your Inspect window is open: nothing sent, nothing cleared.
MS:AbandonRun(); zone(WORLD); zone(RFC)
rawset(_G, "InspectFrame", { IsShown = function() return true end })
asked, cleared = {}, 0
for _ = 1, 10 do MS:PopulateAll(); M.Advance(2) end
check("Inspect window open: no inspects sent", #asked == 0, #asked)
check("Inspect window open: yours isn't cleared", cleared == 0, cleared)
rawset(_G, "InspectFrame", { IsShown = function() return false end })
for _ = 1, 5 do MS:PopulateAll(); M.Advance(2) end
check("Inspect window closed: carries on", count("party1") >= 1, count("party1"))
MS:AbandonRun(); zone(WORLD)

-- ── Listeners that only matter in a run ────────────────────────────────────
-- The group's combat flags: only while a run waits for its pull.
check("no run: not listening for the pull", MS._WatchingPull() == false)
zone(RFC)
check("waiting for the pull: listening", MS._WatchingPull() == true)
M.Fire("PLAYER_REGEN_DISABLED")
check("pulled: no longer listening", MS._WatchingPull() == false)
MS:AbandonRun(); zone(WORLD)
check("run over: not listening", MS._WatchingPull() == false)

-- Out in the world: a roster change or a pet does no work.
local rebuilds, changes = 0, 0
local realRebuild = MS.RebuildPetGUIDCache
MS.RebuildPetGUIDCache = function(...) rebuilds = rebuilds + 1; return realRebuild(...) end
MS:OnChanged(function() changes = changes + 1 end)
M.Fire("GROUP_ROSTER_UPDATE"); M.Fire("UNIT_PET", "party4"); M.RunTimers(3)
check("no run: roster and pets do nothing", rebuilds == 0 and changes == 0, rebuilds .. " " .. changes)
zone(RFC)
rebuilds = 0
M.Fire("UNIT_PET", "party4"); M.RunTimers(3)
check("in a run: pets are looked at", rebuilds > 0, rebuilds)
MS.RebuildPetGUIDCache = realRebuild

io.stdout:write(("inspect_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

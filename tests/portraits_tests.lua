-- usage: lua5.1 portraits_tests.lua DIR TOC
-- WoW Forever: a boss's portrait learned from the game the first time it's
-- seen. The game hides a unit's model, so it's asked by which creature it is.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if MS.FLAVOR ~= "forever" then
    io.stdout:write("portraits_tests: 0 passed, 0 failed (retail: the journal)\n")
    os.exit(0)
end

-- The game, as on Forever: the model off a unit is hidden (0); a creature's
-- model, asked by its number, comes after a moment.
local MODELS = { [11517] = 11611, [11520] = 7970 }
local asked = {}
local realCreate = CreateFrame
CreateFrame = function(kind, ...)
    local f = realCreate(kind, ...)
    if kind == "PlayerModel" then
        f._d = 0
        f.SetUnit = function(self) self._d = 0 end
        f.ClearModel = function(self) self._d, self._pending = 0, nil end
        f.SetCreature = function(self, id) asked[#asked + 1] = id; self._pending, self._loads = id, 2 end
        f.GetDisplayInfo = function(self)
            if self._pending then
                self._loads = self._loads - 1
                if self._loads <= 0 then self._d = MODELS[self._pending] or 0; self._pending = nil end
            end
            return self._d
        end
    end
    return f
end
UnitIsFriend = function(_, u) return not (M.roster[u] and M.roster[u].hostile) end

M.instance = { "Orgrimmar", "none", 0 }
M.Fire("ADDON_LOADED", "MythicScoreboard")
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
M.instance = { "Ragefire Chasm", "party", 1 }
M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8)
check("in a run", MS.currentRun ~= nil)

-- The built-in list, cut down to Jergosh's creature only (no model), known
-- before anyone's met him. (The full list: portraits_builtin_tests.lua.)
for name in pairs(MS.ForeverData.BOSSES) do MS.ForeverData.BOSSES[name] = nil end
MS.ForeverData.BOSSES["Jergosh the Invoker"] = { npc = 11518 }
MODELS[11518] = 11429
local boss = { name = "Oggleflint" }
check("not met yet: no portrait", MS:BossPortrait(boss, MS.currentRun) == nil)
check("not met, not known: nothing asked", #asked == 0, #asked)

-- Targeted: its creature's model, asked for and kept.
M.roster.target = { name = "Oggleflint", guid = "Creature-0-6826-389-24-11517-0B822C39DD", npc = true, hostile = true }
M.Fire("PLAYER_TARGET_CHANGED")
M.RunTimers(10)
local kind, id = MS:BossPortrait(boss, MS.currentRun)
check("targeted: the portrait", kind == "display" and id == 11611, tostring(kind) .. " " .. tostring(id))
check("asked by its creature", asked[1] == 11517, asked[1])
check("kept for the account", MythicScoreboardPortraitsDB.display.oggleflint == 11611 or next(MythicScoreboardPortraitsDB.display) ~= nil)
-- Seen again: not asked again.
local n = #asked
M.Fire("PLAYER_TARGET_CHANGED"); M.RunTimers(10)
check("known: not asked again", #asked == n, #asked)

-- Not a boss: nothing asked.
M.roster.target = { name = "Ragefire Shaman", guid = "Creature-0-6826-389-24-11319-AAAA", npc = true, hostile = true }
M.Fire("PLAYER_TARGET_CHANGED"); M.RunTimers(10)
check("not a boss: not asked", #asked == n, #asked)

-- A boss whose model the game doesn't have: tries a few times, then lets it be.
M.roster.target = { name = "Bazzalan", guid = "Creature-0-6826-389-24-11519-BBBB", npc = true, hostile = true }
M.Fire("PLAYER_TARGET_CHANGED"); M.RunTimers(20)
check("no model: no portrait, no error", MS:BossPortrait({ name = "Bazzalan" }, MS.currentRun) == nil)
-- And the next one still works (the queue moved on).
M.Advance(10)
M.roster.target = { name = "Taragaman the Hungerer", guid = "Creature-0-6826-389-24-11520-CCCC", npc = true, hostile = true }
M.Fire("PLAYER_TARGET_CHANGED"); M.RunTimers(20)
local k2, id2 = MS:BossPortrait({ name = "Taragaman the Hungerer" }, MS.currentRun)
check("after one without: the next learned", k2 == "display" and id2 == 7970, tostring(id2))

-- A player's GUID: never asked about.
n = #asked
M.roster.target = { name = "Oggleflint", guid = "Player-1-ZZZ", hostile = true, npc = true }
MythicScoreboardPortraitsDB.display.oggleflint = nil
M.Fire("PLAYER_TARGET_CHANGED"); M.RunTimers(10)
check("not a creature: not asked", #asked == n)

-- Known from the built-in list: asked when its medallion's drawn, then shown.
local jergosh = { name = "Jergosh the Invoker" }
check("known creature, not met: none yet", MS:BossPortrait(jergosh, MS.currentRun) == nil)
M.RunTimers(10)
local k3, id3 = MS:BossPortrait(jergosh, MS.currentRun)
check("known creature: asked, then shown", k3 == "display" and id3 == 11429, tostring(id3))
-- Met before (its creature kept), its portrait lost: asked again from that.
MythicScoreboardPortraitsDB.display.taragamanthehungerer = nil
for k in pairs(MythicScoreboardPortraitsDB.display) do if k:find("taragaman") then MythicScoreboardPortraitsDB.display[k] = nil end end
check("met before: creature kept", MS:BossNpcID("Taragaman the Hungerer") == 11520)
MS:BossPortrait({ name = "Taragaman the Hungerer" }, MS.currentRun); M.RunTimers(10)
check("met before: portrait back", select(2, MS:BossPortrait({ name = "Taragaman the Hungerer" }, MS.currentRun)) == 7970)
-- /sb bosses: how many are known, and which are still to meet.
M.printed = {}
SlashCmdList.MYTHICSCOREBOARD("bosses")
check("/sb bosses: the count", M.printed[1] and M.printed[1]:find("Bosses known: %d+ of %d+") ~= nil, M.printed[1])
local listed = table.concat(M.printed, "\n")
check("/sb bosses: the missing, by dungeon", listed:find("Blackfathom Deeps: ", 1, true) ~= nil, listed:sub(1, 300))
check("/sb bosses: a dungeon all met isn't listed", not listed:find("Ragefire Chasm:", 1, true))

for _, p in ipairs(M.printed) do if p:find("error") then check("no errors", false, p) end end
io.stdout:write(("portraits_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

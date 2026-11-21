-- usage: lua5.1 mapsearch_tests.lua DIR TOC   (the world map's search box; in combat the map waits)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if MS.FLAVOR ~= "forever" then
    io.stdout:write("retail: 0 passed, 0 failed (WoW Forever only)\n"); os.exit(0)
end

-- The mock's edit boxes lack a few calls the search box makes.
local RealCreate = CreateFrame
CreateFrame = function(kind, ...)
    local f = RealCreate(kind, ...)
    if kind == "EditBox" then
        local focus = false
        for _, m in ipairs({ "SetAutoFocus", "SetMaxLetters", "SetTextInsets", "SetTextColor", "HighlightText" }) do
            if not f[m] then f[m] = function() end end
        end
        f.HasFocus = function() return focus end
        f.SetFocus = function() focus = true end
        f.ClearFocus = function() focus = false end
        if not f.SetText then
            local t = ""
            f.SetText = function(_, v) t = v end
            f.GetText = function() return t end
        end
    end
    return f
end

-- A world map that notes what it was turned to.
local map = CreateFrame("Frame", "WorldMapFrame", UIParent)
map.ScrollContainer = CreateFrame("Frame", nil, map)
local turnedTo = {}
function map:SetMapID(id) turnedTo[#turnedTo + 1] = id end
function map:GetMapID() return 1414 end
WorldMapFrame = map
map:Show()
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(2)
M.Fire("ADDON_LOADED", "Blizzard_WorldMap"); M.RunTimers(1)
local box = rawget(_G, "MythicScoreboardMapSearch")
check("search box built", box ~= nil)

local inCombat = false
InCombatLockdown = function() return inCombat end
local function search(text)
    box:SetText(text); box:Fire("OnTextChanged"); M.RunTimers(1)
end

-- Out of combat: the map turns at once.
search("Ragefire")
box:Fire("OnEnterPressed"); M.RunTimers(1)
check("out of combat: the map turns", #turnedTo == 1, #turnedTo)

-- In combat: it waits for the fight to end.
inCombat = true
search("Wailing")
box:Fire("OnEnterPressed"); M.RunTimers(1)
check("in combat: the map isn't touched", #turnedTo == 1, #turnedTo)
inCombat = false
M.Fire("PLAYER_REGEN_ENABLED"); M.RunTimers(1)
check("after the fight: it turns", #turnedTo == 2, #turnedTo)

-- Closed in the meantime: left alone.
inCombat = true
search("Ragefire")
box:Fire("OnEnterPressed"); M.RunTimers(1)
inCombat = false
map:Hide()
M.Fire("PLAYER_REGEN_ENABLED"); M.RunTimers(1)
check("map closed meanwhile: not reopened or turned", #turnedTo == 2, #turnedTo)
M.Fire("PLAYER_REGEN_ENABLED"); M.RunTimers(1)
check("asked for once only", #turnedTo == 2, #turnedTo)

local function errorsPrinted()
    for _, p in ipairs(M.printed) do if p:find("rror") then return p end end
end
check("no errors at all", not errorsPrinted(), errorsPrinted())
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

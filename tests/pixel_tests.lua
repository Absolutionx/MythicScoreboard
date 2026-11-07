-- usage: lua5.1 pixel_tests.lua DIR TOC   (the completion line: whole pixels, equal gaps either side)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local forever = arg[2]:find("Forever") ~= nil
local clock = 1800000000
time = function() return clock end
local function wait(s) M.now = M.now + s; clock = clock + s end
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD", false, false); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end

local TRACK_Y, TRACK_H, GAP = 76, 14, 5

-- The timeline's pieces drawn since `from`: track bed, fight blocks, the line.
local function Geometry(from)
    local all = M.allFrames
    local bed, line, blocks = nil, nil, {}
    for i = from, #all do
        local f = all[i]
        local at = f._at
        if f._kind == "Texture" and at and at[1] == "BOTTOMLEFT" and f._shown ~= false then
            local x, y = at[4], at[5]
            if y == TRACK_Y and f._h == TRACK_H then
                if f._w > 1000 then bed = bed or { x = x, w = f._w }
                else blocks[#blocks + 1] = { x = x, w = f._w } end
            elseif y == 22 and f._w == 2 then line = { x = x }
            end
        end
    end
    return bed, line, blocks
end

local function Finish(bossTimes, trailing)
    M.timers = {}; MythicScoreboardDB, MythicScoreboardAccountDB = nil, nil
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    zone({ "Orgrimmar", "none", 0 })
    local startClock = M.now
    if forever then
        zone({ "Ragefire Chasm", "party", 1 })
    else
        -- Retail: a key that went over time, so the run ends at the window's edge.
        C_ChallengeMode = {
            GetActiveChallengeMapID = function() return 2526 end,
            GetActiveKeystoneInfo = function() return 10, {}, true end,
            GetMapInfo = function() return { name = "Skyreach" } end,
            GetMapUIInfo = function() return "Skyreach", 2526, 600 end,
            GetChallengeCompletionInfo = function()
                return { time = math.floor((M.now - startClock) * 1000), onTime = false, level = 10 } end,
            GetDeathCount = function() return 0, 0 end,
        }
        zone({ "Skyreach", "party", 8 })
        M.Fire("CHALLENGE_MODE_START", 2526); M.RunTimers(3)
        startClock = M.now
        GetWorldElapsedTime = function() return 1, M.now - startClock end
    end
    local names = { "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" }
    for i, t in ipairs(bossTimes) do
        wait(t[1]); M.Fire("ENCOUNTER_START", i, names[i]); wait(t[2]); M.Fire("ENCOUNTER_END", i, names[i], 1, 5, 1); M.RunTimers(4)
    end
    if trailing then wait(trailing) end
    if not forever then M.Fire("CHALLENGE_MODE_COMPLETED"); M.RunTimers(6) end
    zone({ "Orgrimmar", "none", 0 })
    local from = 1                       -- (pooled pieces are reused: scan everything shown)
    MS:ShowScoreboard(); M.RunTimers(3)
    return Geometry(from)
end

for _, case in ipairs({
    { "wide last block",   { {300, 60}, {400, 70}, {500, 40}, {600, 78} } },
    { "narrow last block", { {300, 60}, {400, 70}, {500, 40}, {600, 9} } },
    { "long run",          { {900, 60}, {800, 70}, {700, 40}, {600, 78} } },
}) do
    local bed, line, blocks = Finish(case[2])
    check(case[1] .. ": drawn", bed and line and #blocks > 0)
    if bed and line then
        local lastRight = -1
        for _, b in ipairs(blocks) do
            local r = b.x + b.w
            if r <= line.x and r > lastRight then lastRight = r end
            check(case[1] .. ": whole pixels", b.x == math.floor(b.x) and b.w == math.floor(b.w), b.x .. " " .. b.w)
        end
        check(case[1] .. ": gap before the line", line.x - lastRight == GAP, line.x - lastRight)
        check(case[1] .. ": gap after the line", (bed.x + bed.w) - (line.x + 2) == GAP, (bed.x + bed.w) - (line.x + 2))
    end
end

io.stdout:write(("pixel_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

-- usage: lua5.1 wc_layout_test.lua DIR TOC   (boss medallions never overlap)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
M.instance = { "Orgrimmar", "none", 0 }
M.Fire("ADDON_LOADED", "MythicScoreboard")
local function T(m, s) return m * 60 + s end
local function boss(name, killT, fight, wipe)
    if wipe then return { name = name, pullTime = killT - fight, wipeTime = killT } end
    return { name = name, pullTime = killT - fight, killTime = killT }
end
local function layout(bosses, dur)
    MythicScoreboardDB.runs = { { dungeonName = "Wailing Caverns", _wallClockStart = 1, duration = dur,
        completed = true, clearedAt = dur, players = {}, bosses = bosses } }
    MS.displayRun = nil; MS.UI._medPlanLRU = nil
    MS:ShowScoreboard(); MS:RefreshOverview(); M.RunTimers(3)
    local cv = MythicScoreboardFrame.timelineContainer._children[1]
    local meds = {}
    for _, w in ipairs(M.allFrames) do
        if w._parent and w._shown and w._kind == "Button" and w:GetWidth() == 40 and w._at and w._scripts.OnClick
                and w._at[4] and w._parent._parent == MythicScoreboardFrame.timelineContainer then
            meds[#meds + 1] = { x = w._at[4], y = w._at[5] }
        end
    end
    return meds
end
local function overlaps(meds)
    local n = 0
    for i = 1, #meds do for j = i + 1, #meds do
        local a, b = meds[i], meds[j]
        if a.y == b.y and math.abs(a.x - b.x) < 40 then n = n + 1 end
    end end
    return n
end
-- Wailing Caverns as played (screenshot).
local wc = {
    { name = "Lady Anacondra", pullTime = 785.9, killTime = 811.155 },
    { name = "Lord Cobrahn", pullTime = 1554.7, killTime = 1573.597 },
    { name = "Kresh", pullTime = 1598.5, killTime = 1616.098 },
    { name = "Lord Pythas", pullTime = 2523.6, wipeTime = 2599.615 },
    { name = "Lord Pythas", pullTime = 3018.1, killTime = 3067.307 },
    { name = "Skum", pullTime = 3652.8, killTime = 3686.613 },
    { name = "Lord Serpentis", pullTime = 4269.0, killTime = 4306.483 },
    { name = "Verdan the Everliving", pullTime = 4363.2, killTime = 4403.422 },
    { name = "Mutanus the Devourer", pullTime = 5032.4, killTime = 5073.767 },
}
local meds = layout(wc, 5073.767)
check("all medallions drawn", #meds == 8, #meds)
check("no medallions overlap (Wailing Caverns)", overlaps(meds) == 0, overlaps(meds))
local function shownNames()
    local out = {}
    for _, w in ipairs(M.allFrames) do
        if w._kind == "FontString" and w._shown and w._parent and w._parent._kind == "Button" and w._parent:GetWidth() == 40
                and w._parent._shown and w._text and not w._text:find("Killed") and not w._text:find("Wipe") then out[w._text] = true end
    end
    return out
end
local names = shownNames()
-- Nothing on a row may touch: labels and medallions, 10px apart.
local function clashes()
    local n, L = 0, MS.UI._medLayout
    for i = 1, #L do for j = i + 1, #L do
        local a, b = L[i], L[j]
        if a.row == b.row and math.min(a.x2, b.x2 + 10) - math.max(a.x1, b.x1 - 10) > 0 then
            n = n + 1; io.write("  clash: ", a.name, " / ", b.name, "\n")
        end
    end end
    return n
end
check("no labels touch (Wailing Caverns)", clashes() == 0)
local full = 0
for _, e in ipairs(MS.UI._medLayout) do if not e.bare and not e.compact then full = full + 1 end end
check("every boss keeps 'Killed at' (Wailing Caverns)", full == 8, full)
for _, e in ipairs(MS.UI._medLayout) do
    io.write(("  %-22s row %d %s at %d%s\n"):format(e.name, e.row, e.bare and "no name" or e.compact and "compact" or "full",
        e.cx, math.abs(e.cx - (e.cx)) > 0 and "" or ""))
end
for _, b in ipairs(wc) do
    if b.killTime then check("label shown: " .. b.name, names[b.name], "missing") end
end
-- Worst case: five kills within two minutes.
local packed = {}
for i = 1, 5 do packed[#packed + 1] = boss("Boss " .. i, T(30, 0) + i * 25, 15) end
packed[#packed + 1] = boss("Last", T(60, 0), 30)
meds = layout(packed, T(60, 0))
check("packed: all drawn", #meds == 6, #meds)
check("packed: no overlaps", overlaps(meds) == 0, overlaps(meds))
for _, p in ipairs(M.printed) do if p:find("rror") then check("no errors", false, p) end end
io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

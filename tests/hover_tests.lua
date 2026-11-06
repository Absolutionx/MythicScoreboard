-- usage: lua5.1 hover_tests.lua DIR TOC
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function zone(inst) M.instance = inst; M.Fire("PLAYER_ENTERING_WORLD"); M.Fire("ZONE_CHANGED_NEW_AREA"); M.RunTimers(8) end
M.Fire("ADDON_LOADED", "MythicScoreboard")
for k in pairs(MythicScoreboardDB.settings.trackedDifficulties) do MythicScoreboardDB.settings.trackedDifficulties[k] = true end
zone({ "Ragefire Chasm", "party", 1 }); MS.currentRun.completed = true; M.now = M.now + 600; zone({ "Orgrimmar", "none", 0 })
zone({ "The Deadmines", "party", 1 })
if not MythicScoreboardFrame then MS:BuildUI() end   -- built on first open
local f = MythicScoreboardFrame
local function src(n, g, a) return { name = n, sourceGUID = g, totalAmount = a, classFilename = "MAGE", amountPerSecond = 0 } end
local function meter(scale)
    M.meter = { [0] = { duration = 50 * scale, combatSources = { src("Akasha", "Player-1-BBB", 500 * scale), src("Girthy", "Player-1-CCC", 400 * scale) } } }
end
meter(1)
MS:ShowScoreboard(); M.RunTimers(2); M.Tick(); M.RunTimers(2)

-- 1. Board rows stay where they are across live polls (same order).
local rows = {}
for _, r in ipairs(UI.overviewRows) do if r._nameFs then rows[#rows + 1] = r end end
check("board has rows", #rows == 5, #rows)
local moved = 0
for _, r in ipairs(rows) do
    local ca, sp, par = r.ClearAllPoints, r.SetPoint, r.SetParent
    r.ClearAllPoints = function(...) moved = moved + 1; return ca(...) end
    r.SetParent = function(...) moved = moved + 1; return par(...) end
end
for i = 2, 5 do meter(i); M.Tick(); M.RunTimers(2) end
check("rows not re-anchored by polls", moved == 0, moved)
local same = 0
for i, r in ipairs(UI.overviewRows) do if r == rows[i] then same = same + 1 end end
check("same row objects reused", same == #rows, same)

-- 2. A reorder (sort change) still moves rows correctly.
UI.sortState.key, UI.sortState.dir = "dps", 1
MS:RefreshOverview(); M.RunTimers(2)
local first = UI.overviewRows[1]
check("sorted top row is highest dps", first and first._nameFs:GetText() == MS.DisplayName(MS:PlayerByName("Akasha").name), first and first._nameFs:GetText())
UI.sortState.key = nil

-- 3. The tooltip guard: something else hides the tooltip, the mouse is
--    still on the row, so it comes back; mouse leaves, it stops.
local guard
for _, w in ipairs(M.allFrames) do
    if w._scripts.OnUpdate and not w._parent then guard = w end
end
check("guard exists", guard ~= nil)
local row = UI.overviewRows[1]
row._mouse = true
row:Fire("OnEnter")
check("tooltip shown on row", GameTooltip:IsOwned(row))
GameTooltip:Hide(); GameTooltip._owner = nil            -- something closes it
guard._scripts.OnUpdate(guard, 0.2)
check("guard brings it back", GameTooltip:IsOwned(row) and GameTooltip:IsShown())
row._mouse = false
GameTooltip:Hide(); GameTooltip._owner = nil
guard._scripts.OnUpdate(guard, 0.2)
check("guard stops when mouse leaves", not GameTooltip:IsShown() and not guard._shown)

-- 4. Header buttons glow on hover (Box outline turns bronze) and still show tooltips.
local function outlineColor(b)
    local tex = b._outline and b._outline[1]
    return tex and tex._r
end
local P = UI.P
for _, name in ipairs({ "CloseButton", "SettingsBtn", "HistoryButton", "StatsBtn" }) do
    local b = f[name]
    local colors = {}
    for i = 1, 4 do
        local t = b._outline[i]
        t.SetColorTexture = function(self, r) self._r = r end
    end
    b:Fire("OnEnter")
    local lit = outlineColor(b) == P.bronze[1]
    b:Fire("OnLeave")
    local unlit = outlineColor(b) == P.line[1]
    check(name .. " glows on hover", lit and unlit, tostring(outlineColor(b)))
end
f.CloseButton:Fire("OnEnter")
check("close tooltip still shown", GameTooltip:IsOwned(f.CloseButton) and GameTooltip._text == "Close")
f.CloseButton:Fire("OnLeave")

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

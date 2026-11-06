-- usage: lua5.1 compare_tests.lua DIR TOC   (run comparison: maths, picking, view)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
M.instance = { "Orgrimmar", "none", 0 }
dofile("fixtures/wc.lua")
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4)
local runs = MS:ArchiveRuns()
check("archive moved account-wide on login", MythicScoreboardDB.archive == nil and #runs == 3, #runs)
local old
for _, e in ipairs(runs) do if e.dungeon == "Ragefire Chasm" then old = e end end
check("real Ragefire run present", old ~= nil)
-- A newer, faster Ragefire: one boss skipped, an extra one, no fight length on one.
local new = { dungeon = "Ragefire Chasm", at = old.at + 86400 * 3, dur = 3000, cleared = true, deaths = 1, wipes = 0,
    bosses = { { n = "Oggleflint", t = 900, d = 18, m = 20 }, { n = "Jergosh the Invoker", t = 2500, d = 40, m = 22 },
               { n = "Bazzalan", t = 2800 }, { n = "Extra Boss", t = 2950, d = 10 } },
    me = { dps = 21, dmg = 60000, role = "DAMAGER" }, group = {} }
table.insert(runs, new)

-- 1. The maths, either argument order.
local c = MS:CompareRuns(new, old)
check("earlier run first", c.first == old and c.second == new)
local function row(n) for _, r in ipairs(c.rows) do if r.name == n then return r end end end
check("rows in earlier run's order, extra at the end", c.rows[1].name == "Oggleflint" and c.rows[#c.rows].name == "Extra Boss", c.rows[1].name)
check("split", row("Oggleflint").split == 900 - 1077, row("Oggleflint").split)
check("fight diff", row("Oggleflint").fight == 18 - 21)
check("trash before the first boss", row("Oggleflint").a.trash == 1077 - 21 and row("Oggleflint").b.trash == 900 - 18)
check("skipped boss has no second side", row("Taragaman the Hungerer").b == nil and row("Taragaman the Hungerer").split == nil)
check("no fight length, no fight diff", row("Bazzalan").fight == nil)
check("total diff", c.total.diff == 3000 - 3714, c.total.diff)
check("end segments", c.total.endA == 3714 - 3505 and c.total.endB == 3000 - 2950, tostring(c.total.endA) .. " " .. tostring(c.total.endB))

-- 2. Picking in the UI.
UI.OpenStats(); M.RunTimers(2)
local rfc
for _, w in ipairs(M.allFrames) do if w._shown and w.dungeon == "Ragefire Chasm" and w._scripts.OnClick then rfc = w end end
check("dungeon row", rfc ~= nil)
rfc:Fire("OnClick"); M.RunTimers(2)
local function runRow(e) for _, w in ipairs(M.allFrames) do if w._shown and w.entry == e and w.cmp then return w end end end
local rOld, rNew = runRow(old), runRow(new)
check("both run rows have Compare", rOld and rNew and rOld.cmp._shown and rOld.cmp.text:GetText() == "Compare")
rOld.cmp:Fire("OnEnter"); rOld.cmp:Fire("OnLeave")
rOld.cmp:Fire("OnClick"); M.RunTimers(2)
check("picked", rOld.cmp.text:GetText() == "Picked")
local hint = false
for _, w in ipairs(M.allFrames) do if w._shown and w._kind == "FontString" and (w._text or ""):find("Pick a second run") then hint = true end end
check("hint shown", hint)
rOld.cmp:Fire("OnClick"); M.RunTimers(2)
check("click again cancels", rOld.cmp.text:GetText() == "Compare")
rNew.cmp:Fire("OnClick"); M.RunTimers(2)
rOld.cmp:Fire("OnClick"); M.RunTimers(2)
local function shownText(pat)
    for _, w in ipairs(M.allFrames) do
        if w._shown and w._kind == "FontString" and w._text and w._text:find(pat) then
            local p, ok = w, true
            while p do if p._shown == false then ok = false break end p = p._parent end
            if ok then return w._text end
        end
    end
end
check("compare view opens", shownText("Run comparison") ~= nil)
check("verdict faster", shownText("Run 2 was 11:54 faster") ~= nil, shownText("Run 2 was"))
check("split cell", shownText("2:57 ahead") ~= nil)
check("whole run row", shownText("Whole run") ~= nil)
check("extra boss row", shownText("Extra Boss") ~= nil)
check("dash for missing", shownText("^|c%x+%-|r$") ~= nil or shownText("%-") ~= nil)
local lines = 0
for _, w in ipairs(M.allFrames) do if w._kind == "Line" and w._shown then lines = lines + 1 end end
check("a line per shared boss", lines == 3, lines)
for _, p in ipairs(M.printed) do if p:lower():find("error") then check("no errors", false, p) end end

-- 3. Back returns to the dungeon with nothing picked.
local back
for _, w in ipairs(M.allFrames) do
    if w._shown and w._kind == "Button" and w._children then
        for _, ch in ipairs(w._children) do if ch._text == "Ragefire Chasm" and ch._shown then back = w end end
    end
end
check("back button", back ~= nil)
if back then back:Fire("OnClick"); M.RunTimers(2) end
check("back to run list", shownText("Run comparison") == nil and runRow(old) and runRow(old).cmp.text:GetText() == "Compare")

-- 4. Removing a picked run cancels.
rNew = runRow(new); rNew.cmp:Fire("OnClick"); M.RunTimers(2)
MS:RemoveArchivedRun(new); UI.RefreshStats(true); M.RunTimers(2)
check("removed pick forgotten", runRow(old) and runRow(old).cmp.text:GetText() == "Compare")

io.stdout:write(("%s: %d passed, %d failed\n"):format(MS.FLAVOR or "retail", passes, fails))
os.exit(fails == 0 and 0 or 1)

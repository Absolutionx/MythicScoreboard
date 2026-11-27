-- usage: lua5.1 raid_tests.lua DIR TOC   (Forever: the sample raid views, /sb raid 10, 20, 40)
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
if MS.FLAVOR ~= "forever" then
    check("retail: no raid command", MS.RaidCommand == nil)
    io.stdout:write("raid_tests (retail): ", passes, " passed, ", fails, " failed\n"); os.exit(fails == 0 and 0 or 1)
end
M.Fire("ADDON_LOADED", "MythicScoreboard")
local UI = MS.UI
local function slash(s) SlashCmdList["MYTHICSCOREBOARD"](s) end
local function win(key) return UI.RaidWindows[key] end
local function run(key) return UI.RaidFrames[key] end
-- The texts shown in a frame (its own, and its children's).
local function within(w, f)
    while w do if w == f then return true end; w = w._parent end
end
local function texts(f)
    local out = {}
    for _, w in ipairs(M.allFrames) do
        if w._kind == "FontString" and w._text and w._text ~= "" and within(w, f) then out[#out + 1] = w._text end
    end
    return out
end
local function has(f, pat)
    for _, t in ipairs(texts(f)) do if t:find(pat) then return t end end
end
-- The player ranked first in a groups view, and each group's size.
local function first(v)
    for _, c in ipairs(v.cells) do if c.rank._text == "#1" then return c.name._text end end
end
local function sizes(v)
    local out = {}
    for _, g in ipairs(v.groups) do out[#out + 1] = #g end
    return table.concat(out, ",")
end
local function errorsPrinted() for _, p in ipairs(M.printed) do if p:find("rror") then return p end end end

-- ── The samples ────────────────────────────────────────────────────────────
check("10: Barrow Deeps", UI.RaidDemo("10").name == "Barrow Deeps")
check("20: Hyjal Summit", UI.RaidDemo("20").name == "Hyjal Summit")
check("40: Onyxia", UI.RaidDemo("40").name == "Onyxia's Lair")
check("by name", UI.RaidDemo("hyj") == UI.RaidDemo("20") and UI.RaidDemo("onyxia's") == UI.RaidDemo("40"))
check("unknown: none", UI.RaidDemo("molten") == nil and UI.RaidDemo("") == nil)
for _, n in ipairs({ 10, 20, 40 }) do
    local r = UI.RaidDemo(tostring(n))
    check(n .. ": that many players", #r.players == n, #r.players)
end

-- ── /sb raid 10 ────────────────────────────────────────────────────────────
slash("raid")
check("no size: says how", M.printed[#M.printed]:find("/sb raid 10"), M.printed[#M.printed])
slash("raid 10")
check("10: scoreboard shown", win("barrow") and win("barrow")._shown)
check("10: in-run frame shown", run("barrow") and run("barrow")._shown)
check("10: says it's a sample", M.printed[#M.printed]:find("sample raid"), M.printed[#M.printed])
check("10: the raid's name", has(win("barrow"), "^Barrow Deeps$"))
check("10: bosses down", has(win("barrow"), "^4 of 8 bosses$"))
check("10: every player", has(win("barrow"), "^Kaelthor Oakshield$") and has(win("barrow"), "^Thandrel Frostwhisper$"))
check("10: you marked", has(win("barrow"), "^You$"))
check("10: raid total", has(win("barrow"), "^Raid total$"))
local b = win("barrow")
check("10: tabs", #b.tabs == 8 and b.tabs[1].label._text == "Overview" and b.tabs[8].label._text == "Loot")
check("10: opens on Overview", b.views.overview._shown and not b.views.ranks._shown)
b.tabs[2]:GetScript("OnClick")(b.tabs[2])
check("10: Damage: its groups", b.views.ranks._shown and not b.views.overview._shown)
check("10: two groups of five", sizes(b.views.ranks) == "5,5" and #b.views.ranks.cells == 10, sizes(b.views.ranks))
check("10: top damage ranked first", first(b.views.ranks) == "Kaelthor Oakshield", first(b.views.ranks))
check("10: the tank leads group 1", b.views.ranks.groups[1][1].name == "Dunmore Kettlewick")
check("10: group labels", has(b.views.ranks, "^Group 1$") and has(b.views.ranks, "^Group 2$"))
check("10: the hint names the stat", has(b.views.ranks, "^Bars by DPS"))
b.tabs[1]:GetScript("OnClick")(b.tabs[1])
check("10: overview tab", b.views.overview._shown and not b.views.ranks._shown)
b.tabs[8]:GetScript("OnClick")(b.tabs[8])
check("10: loot tab", b.views.loot._shown and has(b.views.loot, "^Jailer's Edge$") and has(b.views.loot, "^6 items$"))
b.tabs[1]:GetScript("OnClick")(b.tabs[1])
check("10: back to overview", b.views.overview._shown and not b.views.loot._shown)
local pt, rel, rp = run("barrow"):GetPoint()
check("10: frame beside the window", pt == "TOPLEFT" and rel == b and rp == "TOPRIGHT", tostring(rp))
check("10: frame's fight", has(run("barrow"), "^Well of Sorrow, pull 2$"), has(run("barrow"), "pull"))
check("10: frame's boss list", has(run("barrow"), "^Sonya Darkhallow$") and has(run("barrow"), "^fighting$"))
check("10: frame's lockout", has(run("barrow"), "Resets in 4 days"))

-- The clock counts up.
M.now = M.now + 5; run("barrow"):GetScript("OnUpdate")(run("barrow"), 5)
check("10: clock ticking", has(run("barrow"), "^41:2[45]$"), run("barrow").clock._text)

-- ── /sb raid 20: the other one closes ──────────────────────────────────────
slash("raid 20")
check("20: shown", win("hyjal")._shown and run("hyjal")._shown)
check("20: 10 closed", not win("barrow")._shown and not run("barrow")._shown)
local hy = win("hyjal")
check("20: four groups of five", #hy.views.ranks.cells == 20 and sizes(hy.views.ranks) == "5,5,5,5")
check("20: opens on Overview, from 10 on Damage", hy.views.overview._shown)
local tall = hy:GetHeight()
hy.tabs[2]:GetScript("OnClick")(hy.tabs[2])
check("20: Damage makes the window shorter", hy:GetHeight() < tall - 100, tall .. " -> " .. hy:GetHeight())
check("20: grouped by role", has(win("hyjal"), "^Tanks  %(2%)$") and has(win("hyjal"), "^Healers  %(5%)$")
    and has(win("hyjal"), "^Damage  %(13%)$"))
check("20: frame between pulls", has(run("hyjal"), "^Between pulls$") and has(run("hyjal"), "^20 of 20 alive$"))
check("20: frame: one boss list, no paths", not has(run("hyjal"), "ground$") and has(run("hyjal"), "^Bosses$"))
check("20: folded kills", has(run("hyjal"), "^3 killed$") and has(run("hyjal"), "^%+4 more$"))

-- ── /sb raid 40: one stat, two columns ─────────────────────────────────────
slash("raid 40")
local w = win("onyxia")
check("40: shown", w._shown and run("onyxia")._shown)
local rv = w.views.ranks
check("40: opens on Overview", w.tabs[1].label._text == "Overview" and w.tabs[2].label._text == "Damage"
    and w.views.overview._shown)
w.tabs[2]:GetScript("OnClick")(w.tabs[2])
local groupsH = w:GetHeight()
w.tabs[1]:GetScript("OnClick")(w.tabs[1])
local ov = w.views.overview
check("40: overview scrolls, same height window", ov._shown and ov.scroll ~= nil and w:GetHeight() == groupsH,
    groupsH .. " -> " .. w:GetHeight())
check("40: overview has everyone, grouped", has(ov, "^Tanks  %(3%)$") and has(ov, "^Healers  %(11%)$")
    and has(ov, "^Damage  %(26%)$") and has(ov, "^Piran Larkspur$") and has(ov, "^Kaelthor Oakshield$"))
check("40: overview body taller than its window", ov.scroll.scrollContent:GetHeight() > ov.scroll:GetHeight())
w.tabs[2]:GetScript("OnClick")(w.tabs[2])
check("40: eight groups of five", #rv.cells == 40 and sizes(rv) == "5,5,5,5,5,5,5,5", sizes(rv))
check("40: ranks shown first", rv._shown and not w.views.loot._shown)
check("40: top damage dealer ranked first", first(rv) == "Kaelthor Oakshield", first(rv))
local g4, g5 = rv.groupFrames[4], rv.groupFrames[5]
check("40: two rows of four", g4.row == 0 and g4.col == 3 and g5.row == 1 and g5.col == 0)
local tanks = 0
for gi = 1, 3 do if rv.groups[gi][1].role == "TANK" then tanks = tanks + 1 end end
check("40: tanks spread over groups 1-3", tanks == 3)
-- The Healing tab re-ranks.
w.tabs[3]:GetScript("OnClick")(w.tabs[3])
check("40: healing tab", has(rv, "^Bars by HPS") and first(rv) == "Edric Ravenhill", first(rv))
w.tabs[5]:GetScript("OnClick")(w.tabs[5])
check("40: deaths tab", first(rv) == "Vexalia Elmstead", first(rv))
check("40: selected tab has no fill", w.tabs[1].glow == nil)
local ht = w.tabs[4]
check("tab hover: has hover handlers", ht:GetScript("OnEnter") and ht:GetScript("OnLeave")
    and pcall(ht:GetScript("OnEnter"), ht) and pcall(ht:GetScript("OnLeave"), ht))
w.tabs[8]:GetScript("OnClick")(w.tabs[8])
check("40: loot tab", w.views.loot._shown and not rv._shown and has(w.views.loot, "^Head of Onyxia$")
    and has(w.views.loot, "^9 items$"))
check("40: frame's phases", has(run("onyxia"), "^Onyxia, phase 2$") and has(run("onyxia"), "^Phase 3 at 40%%$"))
check("40: frame's pulls", has(run("onyxia"), "^Wipe in phase 2 at 58%%$") and has(run("onyxia"), "^Pull 3$"))

-- ── Hovering ───────────────────────────────────────────────────────────────
local tip = {}
local addD, addL = GameTooltip.AddDoubleLine, GameTooltip.AddLine
GameTooltip.AddDoubleLine = function(_, l, r) tip[#tip + 1] = l .. "|" .. r end
GameTooltip.AddLine = function(_, l) tip[#tip + 1] = l end
local setT = GameTooltip.SetText
GameTooltip.SetText = function(self, t) tip = { "=" .. t }; self._text = t end
local function tipHas(pat) for _, l in ipairs(tip) do if l:find(pat) then return l end end end
local function hover(fr) fr:GetScript("OnEnter")(fr); local seen = GameTooltip._shown; fr:GetScript("OnLeave")(fr); return seen end
slash("raid 40")
w.tabs[2]:GetScript("OnClick")(w.tabs[2])
local kael
for _, c in ipairs(rv.cells) do if c.player.name == "Kaelthor Oakshield" then kael = c end end
check("hover a player: tooltip", hover(kael) and tip[1] == "=Kaelthor Oakshield", tip[1])
check("hover: role and group", tipHas("^Damage|Group %d$"), table.concat(tip, " / "))
check("hover: damage with DPS and rank", tipHas("^Damage|.* DPS   #1$"), tipHas("^Damage|"))
check("hover: damage by spell", tipHas("^Damage by spell$") and tipHas("^  Sinister Strike|"))
check("hover: deaths listed", tipHas("^  Killed by "), table.concat(tip, " / "))
check("hover: tooltip hides", not GameTooltip._shown)
local edric
for _, c in ipairs(rv.cells) do if c.player.name == "Edric Ravenhill" then edric = c end end
hover(edric)
check("hover a healer: healing by spell, dispels by type", tipHas("^Healing by spell$") and tipHas("^Dispels by type$")
    and tipHas("^  Magic|"), table.concat(tip, " / "))
w.tabs[1]:GetScript("OnClick")(w.tabs[1])
local orow
for _, k in ipairs({ ov.scroll.scrollContent:GetChildren() }) do if k:GetScript("OnEnter") then orow = k; break end end
check("hover an overview row", orow and hover(orow) and tip[1]:sub(1, 1) == "=")
w.tabs[8]:GetScript("OnClick")(w.tabs[8])
local lrow
for _, k in ipairs({ w.views.loot:GetChildren() }) do if k:GetScript("OnEnter") then lrow = k; break end end
check("hover loot: the item", lrow and hover(lrow) and tip[1] == "=Head of Onyxia" and tipHas("^Looted by|Dunmore Kettlewick$")
    and tipHas("^Dropped by|Onyxia$"), table.concat(tip, " / "))
slash("raid 10")
local pull
pull = b.pullHits and b.pullHits[1]
check("hover a pull", pull and hover(pull) and tip[1] == "=Kill" and tipHas("^Time|6:12$") and tipHas("^Fight length|2:10$"),
    table.concat(tip, " / "))
GameTooltip.AddDoubleLine, GameTooltip.AddLine, GameTooltip.SetText = addD, addL, setT

-- ── /sb: the raid window in a raid ─────────────────────────────────────────
slash("raid 20"); w = win("hyjal")
w.tabs[3]:GetScript("OnClick")(w.tabs[3])
slash("raid 10"); slash("raid 20")
check("reopening a size: back on Overview", w.views.overview._shown)
local gi, iii = GetInstanceInfo, IsInInstance
M.instance = { "Onyxia's Lair", "raid", 1, 249 }
GetInstanceInfo = function() return "Onyxia's Lair", "raid", 1, "Normal", 40, 0, false, 249 end
slash("")
check("/sb in a 40-player raid: the 40 window", win("onyxia")._shown and not (UI.frame and UI.frame._shown))
check("  on Overview", win("onyxia").views.overview._shown)
GetInstanceInfo = function() return "Somewhere", "raid", 1, "Normal", 20, 0, false, 1 end
slash("")
check("/sb in a 20-player raid: the 20 window", win("hyjal")._shown and not win("onyxia")._shown)
M.instance = { "Deadmines", "party", 1, 36 }
GetInstanceInfo = gi
slash("")
check("/sb in a dungeon: the dungeon scoreboard", UI.frame._shown and not win("hyjal")._shown)
M.instance = { "", "none", 0, 0 }
w = win("hyjal")
UI.frame.raidButton:GetScript("OnClick")(UI.frame.raidButton)
local bat, tat = w.dungeonButton._at, w.tabs[1]._at      -- (point, x, y) as set
check("Dungeons button: in the tab row, at the right", bat[1] == "TOPRIGHT" and bat[3] == tat[3],
    tostring(bat[1]) .. " " .. tostring(bat[3]))
local rat = UI.frame.raidButton._at
check("Raids button: under the close button", rat[1] == "TOPRIGHT" and rat[2] == UI.frame.CloseButton and rat[3] == "BOTTOMRIGHT")
check("Raids button: back to the last raid", w._shown and not UI.frame._shown)
w:Hide()
slash("")
check("/sb outside: the raid, used last", w._shown and not UI.frame._shown)
w.dungeonButton:GetScript("OnClick")(w.dungeonButton)
check("Dungeons button: the dungeon scoreboard", UI.frame._shown and not w._shown)
UI.frame:Hide()
slash("")
check("/sb outside: the dungeon scoreboard, used last", UI.frame._shown and not w._shown)
UI.frame:Hide()
GetInstanceInfo, IsInInstance = gi, iii
M.instance = { "Ragefire Chasm", "party", 1 }
slash("raid 40"); w = win("onyxia")

-- ── Boss names ─────────────────────────────────────────────────────────────
slash("raid 10")
-- Each kill's boss and time sit on the line; none touches the one before,
-- and none runs off the track, in any of the three.
local overlaps, kills = 0, 0
for _, size in ipairs({ "10", "20", "40" }) do
    slash("raid " .. size)
    local last = -1e9
    for _, p in ipairs(UI.RaidDemo(size).pulls) do
        if p.medSpan then
            kills = kills + 1
            if p.medSpan[1] < last or p.medSpan[1] < 0 or p.medSpan[2] > 1154 then overlaps = overlaps + 1 end
            last = p.medSpan[2]
        end
    end
end
check("bosses on the line never overlap", overlaps == 0 and kills == 10, overlaps .. " " .. kills)
check("a kill's time beside its boss", UI.RaidDemo("10").pulls[1].badge._text == "6:12")
slash("raid 20")
local enc = UI.RAID_ENCOUNTERS
check("raid data: 8 and 13 bosses, Barrow's encounter IDs all known", #enc.barrow == 8 and #enc.hyjal == 13
    and enc.barrow[8].encounter == 3490 and enc.hyjal[13].name == "Nythus the Dreambound")
local hyl = UI.RaidDemo("20").frame.list
local fold, more = hyl[1], hyl[7]
local tl = {}
local oD, oL, oT = GameTooltip.AddDoubleLine, GameTooltip.AddLine, GameTooltip.SetText
GameTooltip.AddDoubleLine = function(_, l, r) tl[#tl + 1] = l .. "|" .. r end
GameTooltip.AddLine = function(_, l) tl[#tl + 1] = l end
GameTooltip.SetText = function(_, t) tl = { "=" .. t } end
fold.hover:GetScript("OnEnter")(fold.hover)
check("in-run: '3 killed' lists the kills", tl[1] == "=3 killed" and tl[2] == "Bandalar|9:30" and #tl == 4, table.concat(tl, " / "))
more.hover:GetScript("OnEnter")(more.hover)
check("in-run: '+4 more' lists the bosses to come", tl[1] == "=+4 more" and #tl == 5 and tl[2] == "Sylvestris Dusksong",
    table.concat(tl, " / "))
GameTooltip.AddDoubleLine, GameTooltip.AddLine, GameTooltip.SetText = oD, oL, oT
check("in-run: the list names its bosses", has(run("hyjal"), "^Nythus the Dreambound$"))

-- ── /sb raid dump ──────────────────────────────────────────────────────────
local saved = {}
for _, k in ipairs({ "GetAchievementInfo", "GetAchievementNumCriteria", "GetAchievementCriteriaInfo",
    "EJ_GetInstanceInfo", "EJ_GetNumTiers", "EJ_GetInstanceByIndex", "EJ_GetEncounterInfoByIndex" }) do
    saved[k] = rawget(_G, k)
end
rawset(_G, "GetAchievementInfo", function(id)
    if id == 7001 then return 7001, "Hyjal Summit", 10, false, 0, 0, 0, "Defeat the bosses of Hyjal Summit." end
    if id == 7002 then return 7002, "Something else", 10, false, 0, 0, 0, "Nothing here." end
end)
rawset(_G, "GetAchievementNumCriteria", function(id) return id == 7001 and 2 or 0 end)
rawset(_G, "GetAchievementCriteriaInfo", function(_, i) return i == 1 and "Bandalar" or "Nythus the Dreambound", 0, false, 0, 1, "", 0, 9000 + i end)
rawset(_G, "EJ_GetNumTiers", function() return 1 end)
rawset(_G, "EJ_GetInstanceByIndex", function(i, raid) if raid and i == 1 then return 1301, "Barrow Deeps" end end)
rawset(_G, "EJ_GetEncounterInfoByIndex", function(j) if j <= 2 then return "Boss" .. j, "", 50 + j, 0, "", 1301, 3000 + j, 2980 end end)
rawset(_G, "EJ_GetInstanceInfo", function(jid) if jid == 1301 then return "Barrow Deeps" end end)
MythicScoreboardAccountDB = MythicScoreboardAccountDB or {}
slash("raid dump")
M.RunTimers(40)
local dump = MythicScoreboardAccountDB.raidDump
check("dump: achievements naming a raid", dump and #dump.achievements == 1 and dump.achievements[1].id == 7001
    and dump.achievements[1].criteria[2][1] == "Nythus the Dreambound")
check("dump: journal encounters with their IDs", dump and #dump.journal == 1
    and dump.journal[1].encounters[2].dungeonEncounterID == "3002" and dump.journal[1].encounters[2].instanceID == "2980")
for k, v in pairs(saved) do rawset(_G, k, v) end

-- ── The pulls track ────────────────────────────────────────────────────────
slash("raid 20")
local hw = win("hyjal")
check("track: the run's end time", hw.pullsEnd and hw.pullsEnd._text == "1:14:02")
local p1 = UI.RaidDemo("20").pulls[1]
check("track: kill times from the fights", p1.t == "9:30" and UI.RaidDemo("20").pulls[8].t == "58:10")
local meds = 0
for _, p in ipairs(UI.RaidDemo("20").pulls) do if p.medallion then meds = meds + 1 end end
check("track: a medallion for each kill", meds == 5, meds)
check("track: medallion names its boss", UI.RaidDemo("20").pulls[1].medallion.bossName == "Bandalar"
    and UI.RaidDemo("20").pulls[1].medallion.npc == 249790)
local dn = 0
for _, dm in ipairs(hw.deathMarks) do dn = dn + #dm.list end
check("track: every death marked", dn == 16, dn)
local dOver, lastR = 0, -1e9
for _, dm in ipairs(hw.deathMarks) do if dm.span[1] < lastR then dOver = dOver + 1 end; lastR = dm.span[2] end
check("track: death marks never overlap", dOver == 0, dOver)
local dt = {}
local o1, o2 = GameTooltip.SetText, GameTooltip.AddDoubleLine
GameTooltip.SetText = function(_, t) dt = { t } end
GameTooltip.AddDoubleLine = function(_, l, r) dt[#dt + 1] = l .. "=" .. r end
hw.deathMarks[1].hit:GetScript("OnEnter")(hw.deathMarks[1].hit)
GameTooltip.SetText, GameTooltip.AddDoubleLine = o1, o2
check("track: a death mark names who died", dt[1] and dt[1]:find("death") and dt[2] and dt[2]:find("="), table.concat(dt, " / "))
check("track: a time scale", #hw.axis >= 4 and hw.axis[1]._text == "0:00", #hw.axis)
local ax = hw.axis[#hw.axis]._at
check("track: the minutes stop short of the end time", ax[4] < 1154 - 22 - 40, ax[4])

-- ── One fight on its own ───────────────────────────────────────────────────
slash("raid 10")
local bw = win("barrow")
bw.tabs[2]:GetScript("OnClick")(bw.tabs[2])
local med = UI.RaidDemo("10").pulls[1].medallion
med:GetScript("OnMouseUp")(med)
local fw = UI.RaidWindows["barrow#1"]
check("fight: clicking a boss shows its fight", fw and fw._shown and not bw._shown)
check("fight: says which fight", fw and has(fw, "Chillhowl  ·  Kill 6:12"))
check("fight: the same tab", fw and fw.selected == fw.tabs[2])
check("fight: time is the fight's", fw and has(fw, "^2:10$"))
local whole, part = 0, 0
for _, pl in ipairs(UI.RaidDemo("10").players) do whole = whole + pl.damage end
for _, pl in ipairs(fw.run.players) do part = part + pl.damage end
check("fight: numbers for that fight only", part > 0 and part < whole / 3, part .. " of " .. whole)
check("fight: only its loot", fw and #fw.run.loot == 2, fw and #fw.run.loot)
check("fight: the boss lit up", UI.RaidDemo("10").pulls[1].medallion ~= nil and fw.run.pulls[1].medallion.halo ~= nil)
fw.wholeButton:GetScript("OnClick")(fw.wholeButton)
check("fight: 'Whole raid' goes back", bw._shown and not fw._shown and bw.selected == bw.tabs[2])
local wipeHit = bw.pullHits[2]
wipeHit:GetScript("OnMouseUp")(wipeHit)
local ww = UI.RaidWindows["barrow#2"]
check("fight: a wipe on its own", ww and ww._shown and has(ww, "Elder Tangleclaw  ·  Wipe"))
wipeHit = ww.pullHits[2]
wipeHit:GetScript("OnMouseUp")(wipeHit)
check("fight: clicking it again goes back", bw._shown and not ww._shown)

-- ── /sb raid live (dev) ────────────────────────────────────────────────────
local RL = UI._RaidLive
local keep = {}
for _, k in ipairs({ "UnitExists", "UnitHealth", "UnitHealthMax" }) do keep[k] = rawget(_G, k) end
slash("raid live")
local lf = RL.Frame()
check("live: on", lf and lf._shown)
RL.Event(nil, "ENCOUNTER_START", 2001, "Chillhowl", 1, 5)
check("live: names the pull", lf.who._text == "Chillhowl, pull 1", lf.who._text)
rawset(_G, "UnitExists", function(u) return u == "boss1" end)
rawset(_G, "UnitHealth", function() return 600 end)
rawset(_G, "UnitHealthMax", function() return 1000 end)
local n0 = #M.printed
RL.Update()
check("live: health from the game", lf.pct._text == "Health 60%", lf.pct._text)
check("live: says what the game gave", M.printed[n0 + 1] and M.printed[n0 + 1]:find("health readable, bar works, percent works"),
    M.printed[n0 + 1])
RL.Event(nil, "ENCOUNTER_END", 2001, "Chillhowl", 1, 5, 1)
check("live: a kill", lf.note._text == "Chillhowl killed", lf.note._text)
for k, v in pairs(keep) do rawset(_G, k, v) end
slash("raid live")
check("live: off", not lf._shown)

-- ── Deaths this pull (in-run) ──────────────────────────────────────────────
slash("raid 10")
local rf10 = run("barrow")
check("in-run: the latest death, and how many more", has(rf10, "^Kaelthor Oakshield died at 2:48$") and has(rf10, "^%+2 more$"))
local dl = {}
local s1, s2 = GameTooltip.SetText, GameTooltip.AddDoubleLine
GameTooltip.SetText = function(_, t) dl = { t } end
GameTooltip.AddDoubleLine = function(_, l, r) dl[#dl + 1] = l .. "=" .. r end
rf10.pullDeathsHover:GetScript("OnEnter")(rf10.pullDeathsHover)
GameTooltip.SetText, GameTooltip.AddDoubleLine = s1, s2
check("in-run: hover lists them all, latest first", dl[1] == "3 deaths" and dl[2] == "Kaelthor Oakshield=2:48" and #dl == 4,
    table.concat(dl, " / "))

-- ── Loot in the overview, as on the dungeon scoreboard ─────────────────────
slash("raid 20")
local lw = win("hyjal")
lw.tabs[1]:GetScript("OnClick")(lw.tabs[1])
local withLoot, icons = 0, 0
for _, k in ipairs({ lw.views.overview:GetChildren() }) do
    if k.lootIcons then withLoot = withLoot + 1; icons = icons + #k.lootIcons end
end
check("overview: loot icons on the players who looted", withLoot > 0 and icons == #UI.RaidDemo("20").loot, withLoot .. " " .. icons)
check("overview: the loot total", has(lw.views.overview, "^9 items$"))

-- ── Raid history ───────────────────────────────────────────────────────────
slash("raid 10")
local hb = win("barrow")
hb.historyButton:GetScript("OnClick")(hb.historyButton)
check("history: opens", hb.history and hb.history._shown and #hb.history.rows == 3)
check("history: the open raid marked", hb.history.rows[1].selected and not hb.history.rows[2].selected)
check("history: what each raid did", has(hb.history, "^4 of 8 bosses$") and has(hb.history, "^Cleared$")
    and has(hb.history, "^1:14:02$"))
hb.history.rows[2]:GetScript("OnClick")(hb.history.rows[2])
check("history: opens the raid picked", win("hyjal")._shown and not hb._shown and not hb.history._shown)

-- ── Work in progress ───────────────────────────────────────────────────────
slash("raid 40")
check("a work-in-progress note on the raid window", win("onyxia").wipNote and has(win("onyxia"), "^Work in progress$"))
local wn = win("onyxia").wipNote
wn:GetScript("OnMouseUp")(wn)
local lf2 = rawget(_G, "MythicScoreboardRaidLinks")
check("clicking it: the links, to copy", lf2 and lf2._shown and lf2.boxes[1]:GetText() == "https://www.curseforge.com/wow/addons/mythic-scoreboard"
    and lf2.boxes[2]:GetText() == "https://github.com/Absolutionx/MythicScoreboard")
lf2.boxes[1]:SetText("typed over")
lf2.boxes[1]:GetScript("OnTextChanged")(lf2.boxes[1])
check("the links can't be typed over", lf2.boxes[1]:GetText() == "https://www.curseforge.com/wow/addons/mythic-scoreboard")
lf2:Hide()

-- ── Themed tooltips ────────────────────────────────────────────────────────
local TS = UI._TooltipSkin
slash("raid 10")
local cell = win("barrow").views.ranks.cells[1]
cell:GetScript("OnEnter")(cell)
check("tooltip: our look on our frames", TS.IsWorn())
GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
check("tooltip: the game's look for anything else", not TS.IsWorn())
cell:GetScript("OnEnter")(cell); cell:GetScript("OnLeave")(cell)
check("tooltip: look comes off when it hides", not TS.IsWorn())

-- ── Closing ────────────────────────────────────────────────────────────────
slash("raid")
check("closed", not w._shown and not run("onyxia")._shown)
w:Show(); w:Hide()
check("closing the window closes the frame", not run("onyxia")._shown)
check("no errors", not errorsPrinted(), errorsPrinted())

io.stdout:write("raid_tests: ", passes, " passed, ", fails, " failed\n")
os.exit(fails == 0 and 0 or 1)

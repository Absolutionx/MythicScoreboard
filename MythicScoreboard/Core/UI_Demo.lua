-- The scoreboard's sample runs (/sb demo): a made-up key (retail) or
-- WoW Forever run, drawn like a real one and never saved. The in-run frame's
-- demo (UI_CompactDemo.lua) starts from the same key.

local MS = _G["MythicScoreboard"]
local UI = MS.UI

local DEMO_TIMES = { [0] = 1890, [1] = 1632, [2] = 1395, [3] = 1020 }   -- of a 30:00 timer
local function DemoRun(up)
    local dur, limit = DEMO_TIMES[up] or DEMO_TIMES[2], 1800
    local frac = dur / 1475                   -- boss times below are for a 24:35 run
    local function T(t) return math.floor(t * frac) end
    local run = MS.NewRunData()
    run.dungeonName, run.keystoneLevel, run.keystoneTimeLimit = "Ara-Kara, City of Echoes", 15, limit
    run.difficultyLabel = "Mythic Keystone"
    run.completed, run.inTime, run.keyUpgrades, run.duration = true, up > 0, up, dur
    run._wallClockStart, run._demo = time() - dur, true
    run.affixes = {}
    run.bosses = {
        { name = "Avanoxx",                 pullTime = T(300), killTime = T(420), progressPct = 38 },
        { name = "Anub'zekt",               pullTime = T(780), killTime = T(905), progressPct = 71 },
        { name = "Ki'katal the Harvester",  pullTime = T(1290), killTime = T(1475), progressPct = 100 },
    }
    -- Your current rating (if the game has one), and an 18-point gain.
    local before = 2827
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, sc = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        local v = ok and type(sc) == "table" and MS.ReadableValue(sc.currentSeasonScore)
        if type(v) == "number" and v > 0 then before = v end
    end
    local gain = up > 0 and (6 * up + 6) or 0
    run.ratingBefore, run.ratingAfter = before, before + gain

    local myName = MS:UnitPlayerName("player") or UNKNOWN or "You"
    local _, myClass = UnitClass("player")
    local mySpec
    local Spec, SpecInfo = rawget(_G, "GetSpecialization"), rawget(_G, "GetSpecializationInfo")
    if Spec and SpecInfo then
        local ok, idx = pcall(Spec)
        if ok and idx then local ok2, id = pcall(SpecInfo, idx); mySpec = ok2 and id or nil end
    end
    local role = MS.SpecLabel and select(2, MS.SpecLabel(mySpec, myClass)) or "DAMAGER"
    local group = {
        { MS.ShortName(myName), myClass or "WARRIOR", mySpec, role, 652, 0 },
        { "Ironhide",  "PALADIN",     66,  "TANK",    649, 2910 },
        { "Mosswhisper", "DRUID",     105, "HEALER",  651, 2766 },
        { "Frostbyte", "MAGE",        63,  "DAMAGER", 650, 2934 },
        { "Shadestep", "DEMONHUNTER", 577, "DAMAGER", 653, 2801 },
        { "Arrowyn",   "HUNTER",      254, "DAMAGER", 648, 2745 },   -- if one above stayed home
    }
    local seen = { [role] = true }
    run.players = {}
    for i, g in ipairs(group) do
        -- Your role is filled by you: the stand-in for it stays home.
        local n = 0
        for _ in pairs(run.players) do n = n + 1 end
        if n < 5 and (i == 1 or not (seen[g[4]] and g[4] ~= "DAMAGER")) then
            seen[g[4]] = true
            local p = MS.NewPlayerStats(g[1], g[2], "Demo-" .. i)
            p.specID, p.role, p.itemLevel = g[3], g[4], g[5]
            p.mythicScore = i == 1 and run.ratingAfter or g[6]
            if i == 1 and gain > 0 then p.ratingGain = gain end
            local dps = g[4] == "HEALER" and 210000 or (g[4] == "TANK" and 640000 or 980000 + i * 60000)
            p.damageDone, p.dps = dps * dur, dps
            local hps = g[4] == "HEALER" and 1150000 or 45000
            p.healingDone, p.hps = hps * dur, hps
            p.damageTaken = (g[4] == "TANK" and 160 or 60) * 1000000
            p.interrupts = g[4] == "HEALER" and 2 or 7 + i
            for k = 1, p.interrupts do p.interruptEvents[k] = math.floor(dur * k / (p.interrupts + 1)) end
            if i == 4 then
                p.deaths = 1
                p.deathEvents = { { time = T(860), events = {
                    { spellName = "Burrow Charge", caster = "Anub'zekt", amount = 812000, overkill = 1 } } } }
            end
            run.players[g[1]] = p
        end
    end
    return run
end

UI.DemoRun = DemoRun          -- (the in-run frame's sample, UI_Compact.lua)

-- WoW Forever: a finished run of one of its dungeons, picked at random from
-- the ones near your level (any, with none near), with its own bosses, a
-- group of the classes it has, numbers to suit the level, and the XP, kills
-- and gold a run gives.
local function ForeverDemoRun()
    local D = MS.ForeverData and MS.ForeverData.DUNGEONS or {}
    local lvl = UnitLevel and UnitLevel("player")
    if MS.IsSecret(lvl) or type(lvl) ~= "number" then lvl = 30 end
    local near, all = {}, {}
    for name, d in pairs(D) do
        if d.levels and #(d.bosses or {}) > 0 then
            all[#all + 1] = name
            if lvl >= d.levels[1] - 3 and lvl <= d.levels[2] + 3 then near[#near + 1] = name end
        end
    end
    local pool = #near > 0 and near or all
    table.sort(pool)
    local name = pool[math.random(math.max(1, #pool))] or "Zul'Farrak"
    local d = D[name] or { levels = { lvl, lvl }, bosses = {} }

    local run = MS.NewRunData()
    local wing = name:match("^(.-):%s")
    run.dungeonName = d.instance or wing or name
    if d.instance or wing then run.wingName = name end
    run.difficultyLabel = "Normal"
    local dur = math.random(28, 46) * 60
    run.completed, run.duration = true, dur
    run._wallClockStart, run._demo = time() - dur, true
    run.affixes = {}
    -- The bosses that are always there, spread over the run.
    local names = {}
    for _, b in ipairs(d.bosses) do
        -- (Forever.lua turns each into { name = ... } as it loads.)
        local bn = type(b) == "string" and b or (type(b) == "table" and not (b.rare or b.summon) and (b.name or b[1]))
        if bn then names[#names + 1] = bn end
    end
    run.bosses = {}
    for i, b in ipairs(names) do
        local kill = math.floor(dur * i / #names) - (i == #names and 0 or 40)
        local fight = math.random(35, 110)
        run.bosses[i] = { name = b, pullTime = kill - fight, killTime = kill, progressPct = math.floor(100 * i / #names) }
    end
    -- What it did for you.
    local xp = lvl < 60 and lvl * math.random(700, 1100) or 0
    run.progress = { xp = xp, qx = lvl < 60 and lvl * math.random(150, 400) or 0, levels = 0,
                     kills = math.random(80, 140), quests = {}, questRewards = {}, gold = lvl * math.random(250, 700), rep = {} }

    local myName = MS:UnitPlayerName("player") or UNKNOWN or "You"
    local _, myClass = UnitClass("player")
    local group = {
        { MS.ShortName(myName), myClass or "WARRIOR", "DAMAGER" },
        { "Ironhide",    "WARRIOR", "TANK" },
        { "Mosswhisper", "DRUID",   "HEALER" },
        { "Frostbyte",   "MAGE",    "DAMAGER" },
        { "Shadestep",   "ROGUE",   "DAMAGER" },
        { "Arrowyn",     "HUNTER",  "DAMAGER" },   -- if one above stayed home
    }
    -- Five: you and four others (a stand-in of your own class stays home,
    -- or else the spare at the end).
    local home = #group
    for i = 2, #group do
        if group[i][2] == myClass and group[i][3] == "DAMAGER" then home = i; break end
    end
    table.remove(group, home)
    run.players = {}
    for i, g in ipairs(group) do
        local p = MS.NewPlayerStats(g[1], g[2], "Demo-" .. i)
        p.role = g[3]
        p.level = math.max(1, math.min(60, lvl + (i == 1 and 0 or math.random(-2, 2))))
        p.itemLevel = math.max(1, p.level - math.random(2, 8))
        local dps = g[3] == "HEALER" and p.level * 0.6 or (g[3] == "TANK" and p.level * 1.4 or p.level * (1.8 + i * 0.15))
        p.dps, p.damageDone = math.floor(dps), math.floor(dps * dur)
        local hps = g[3] == "HEALER" and p.level * 2.2 or p.level * 0.15
        p.hps, p.healingDone = math.floor(hps), math.floor(hps * dur)
        p.damageTaken = (g[3] == "TANK" and 900 or 280) * p.level
        p.interrupts = g[3] == "HEALER" and 0 or math.random(1, 6)
        for k = 1, p.interrupts do p.interruptEvents[k] = math.floor(dur * k / (p.interrupts + 1)) end
        if i == 4 then
            p.deaths = 1
            local b = run.bosses[math.min(2, #run.bosses)]
            p.deathEvents = { { time = b and b.killTime - 10 or math.floor(dur / 2), events = {} } }
        end
        run.players[g[1]] = p
    end
    return run
end
UI.ForeverDemoRun = ForeverDemoRun
UI.DEMO_TIMES = DEMO_TIMES

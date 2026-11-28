-- The in-run frame's sample run (/sb compact demo): a made-up run that plays
-- itself out, a different dungeon (or key) each time round, or the one named.
-- The frame (Core/UI_Compact.lua) draws it like any run; this only makes it
-- and moves it on: UI.CompactDemoRun(pick) and UI.CompactDemoAt(run).

local _floor, _max, _min = math.floor, math.max, math.min
local _ins = table.insert

local MS = _G["MythicScoreboard"]
local UI = MS.UI

-- ── The demo ───────────────────────────────────────────────────────────────
-- A made-up run in the frame (/sb compact demo) that plays out at DEMO_SPEED
-- times real time, then starts over: on retail a key (packs pulled one after
-- another, three bosses, four deaths, finished in time), on Forever a run of
-- the Library wing (mobs, two bosses, a quest, a death). Every redraw works
-- the run out afresh from the script for the moment it has reached.
local DEMO_SPEED = 20

local KEY_SCRIPT = {
    limit = 1800, finish = 1440, loop = 1520,
    bosses = { { "Avanoxx", 250, 372 }, { "Anub'zekt", 640, 751 }, { "Ki'katal the Harvester", 980, 1180 } },
    -- packs: from, to, forces (%)
    pulls = { { 40, 110, 8.20 }, { 140, 220, 9.50 }, { 400, 470, 11.10 }, { 500, 600, 10.30 },
              { 800, 880, 12.78 }, { 900, 960, 12.40 }, { 1200, 1260, 13.20 }, { 1280, 1350, 12.00 },
              { 1370, 1440, 10.52 } },
    deaths = { { 300, 2 }, { 540, 3 }, { 700, 2 }, { 1300, 4 } },     -- when, which player (in order)
    best = { dur = 1410, bosses = { { n = "Avanoxx", t = 355 }, { n = "Anub'zekt", t = 790 },
                                    { n = "Ki'katal the Harvester", t = 1300 } } },
    forcesTotal = 308, deathCost = 15,
}
local FOREVER_SCRIPT = {
    finish = 1460, loop = 1540,
    bosses = { { "Houndmaster Loksey", 600, 663 }, { "Arcanist Doan", 1380, 1460 } },
    deaths = { 820 },
    quest = { at = 1000, name = "Compendium of the Fallen", xp = 8450 },
}

-- ── A different dungeon each time ─────────────────────────────────────────
-- The scripts above are the fallback; each loop of the demo picks a dungeon
-- (a key from this season's, a Forever dungeon from its table) and spreads
-- that dungeon's bosses over the same shape of run.
local _rand = math.random

-- A dungeon's bosses from the Encounter Journal, by the dungeon's name.
-- (It changes the journal's selected tier briefly, so not while it's open.)
local function JournalBosses(dungeon)
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex) then
        return nil
    end
    if EncounterJournal and EncounterJournal.IsShown and EncounterJournal:IsShown() then return nil end
    local prev = EJ_GetCurrentTier and EJ_GetCurrentTier()
    local out
    pcall(function()
        for tier = EJ_GetNumTiers(), 1, -1 do
            EJ_SelectTier(tier)
            for i = 1, 80 do
                local id, name = EJ_GetInstanceByIndex(i, false)
                if not id then break end
                if name == dungeon then
                    out = {}
                    for e = 1, 20 do
                        local boss = EJ_GetEncounterInfoByIndex(e, id)
                        if not boss then break end
                        out[#out + 1] = boss
                    end
                    return
                end
            end
        end
    end)
    if prev then pcall(EJ_SelectTier, prev) end
    return out and #out > 0 and out or nil
end

-- A key: this season's dungeons in random order, the first the journal knows.
local function RandomKeyScript()
    local CM = C_ChallengeMode
    if not (CM and CM.GetMapTable and CM.GetMapUIInfo) then return nil end
    local ok, maps = pcall(CM.GetMapTable)
    if not ok or type(maps) ~= "table" or #maps == 0 then return nil end
    maps = { unpack(maps) }
    for i = #maps, 2, -1 do local j = _rand(i); maps[i], maps[j] = maps[j], maps[i] end
    for _, mapID in ipairs(maps) do
        local ok2, name, _, limit = pcall(CM.GetMapUIInfo, mapID)
        name, limit = ok2 and MS.Readable(name), ok2 and MS.ReadableNumber(limit)
        local names = name and limit and limit > 600 and JournalBosses(name)
        if names then
            local S = KEY_SCRIPT
            local finish = _floor(limit * 0.8)
            local k, n = finish / S.finish, #names
            local out = { name = name, mapID = mapID, limit = limit, finish = finish, loop = finish + 80,
                          forcesTotal = _rand(25, 45) * 10, deathCost = S.deathCost,
                          bosses = {}, pulls = {}, deaths = {}, best = { dur = finish - 30, bosses = {} } }
            for i, b in ipairs(names) do
                local kill = (i == n) and finish or _floor(finish * i / n - 60)
                out.bosses[i] = { b, kill - _rand(70, 130), kill }
                out.best.bosses[i] = { n = b, t = _max(60, kill + _rand(-50, 40)) }
            end
            for i, pl in ipairs(S.pulls) do out.pulls[i] = { _floor(pl[1] * k), _floor(pl[2] * k), pl[3] } end
            for i, d in ipairs(S.deaths) do out.deaths[i] = { _floor(d[1] * k), d[2] } end
            return out
        end
    end
    return nil
end

-- A Forever dungeon from its table: its required bosses, the final one last.
-- That one (pick, from /sb compact demo <dungeon>), or one at random of
-- those with 14 bosses or fewer.
local function RandomForeverScript(pick)
    local defs = MS.FOREVER_DUNGEONS
    if type(defs) ~= "table" then return nil end
    local keys = {}
    for key, def in pairs(defs) do
        local n = 0
        for _, b in ipairs(def.bosses or {}) do if not (b.rare or b.summon) then n = n + 1 end end
        if n > 0 and (key == pick or (not pick and n <= 14)) then keys[#keys + 1] = key end
    end
    if #keys == 0 then return nil end
    table.sort(keys)                                   -- pairs' order isn't the same each time
    local key = keys[_rand(#keys)]
    local def = defs[key]
    local names = {}
    for _, b in ipairs(def.bosses) do
        if not (b.rare or b.summon) and b.name ~= def.final then names[#names + 1] = b.name end
    end
    if def.final then names[#names + 1] = def.final end
    local n = #names
    local finish = 900 + n * 120 + _rand(0, 300)
    local out = { key = key, finish = finish, loop = finish + 80, bosses = {},
                  deaths = { _floor(finish * (0.3 + _rand() * 0.4)) },
                  quest = { at = _floor(finish * 0.7), name = FOREVER_SCRIPT.quest.name, xp = _rand(40, 120) * 100 } }
    for i, b in ipairs(names) do
        local kill = (i == n) and finish or _floor(finish * i / n - 40)
        out.bosses[i] = { b, kill - _rand(45, 90), kill }
    end
    return out
end

local function DemoPlayers(r)
    local list = {}
    for _, p in pairs(r.players or {}) do _ins(list, p) end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

-- The boss being fought: its health, from full at the pull down to a sliver
-- just before the kill.
local function DemoHealth(now, b)
    local f = (now - b[2]) / _max(1, b[3] - b[2])
    return _max(1, _min(100, _floor(100 - f * 97 + 0.5)))
end

local function KeyAt(r, t)
    local S = r._script or KEY_SCRIPT
    local now = _min(t, S.finish)
    r._demoElapsed = now
    r.completed = t >= S.finish
    r.inTime = r.completed or nil
    r.bosses, r.activeBoss, r._demoObjectives = {}, nil, {}
    for _, b in ipairs(S.bosses) do
        local done = now >= b[3]
        if now >= b[2] then
            local boss = { name = b[1], pullTime = b[2], killTime = done and b[3] or nil }
            _ins(r.bosses, boss)
            if not done then r.activeBoss = boss; boss.demoHealth = DemoHealth(now, b) end
        end
        _ins(r._demoObjectives, { name = b[1], done = done })
    end
    local pct, last = 0, nil
    for _, p in ipairs(S.pulls) do
        if now >= p[2] then pct, last = pct + p[3], p[3]
        elseif now > p[1] then pct = pct + p[3] * (now - p[1]) / (p[2] - p[1]) end
    end
    r.currentPct = _min(100, _floor(pct * 100 + 0.5) / 100)
    r.forcesTotal = S.forcesTotal
    r.forcesCount = _floor(S.forcesTotal * r.currentPct / 100 + 0.5)
    r.lastPull = last
    local players = DemoPlayers(r)
    for _, p in ipairs(players) do p.deaths, p.deathEvents = 0, {} end
    local n = 0
    for _, d in ipairs(S.deaths) do
        local p = players[d[2]]
        if p and now >= d[1] then
            p.deaths = p.deaths + 1; _ins(p.deathEvents, { time = d[1] }); n = n + 1
        end
    end
    r.deathPenaltySeconds = n * S.deathCost
end

local function ForeverAt(r, t)
    local S = r._script or FOREVER_SCRIPT
    local now = _min(t, S.finish)
    r._demoElapsed = now
    r.bosses, r.activeBoss = {}, nil
    local bossXP = 0
    for _, b in ipairs(S.bosses) do
        if now >= b[2] then
            local boss = { name = b[1], pullTime = b[2], killTime = now >= b[3] and b[3] or nil }
            _ins(r.bosses, boss)
            if boss.killTime then bossXP = bossXP + 640 else r.activeBoss = boss; boss.demoHealth = DemoHealth(now, b) end
        end
    end
    local kills = _max(0, _min(_floor(S.finish / 18), _floor((now - 30) / 18)))
    local pr = r.progress
    pr.kills, pr.xp, pr.gold = kills, kills * 114 + bossXP, kills * 77
    local q = S.quest
    if now >= q.at then
        pr.quests, pr.questRewards, pr.qx = { q.name }, { { x = q.xp } }, q.xp
    else
        pr.quests, pr.questRewards, pr.qx = {}, {}, 0
    end
    local me = DemoPlayers(r)[1]
    if me then
        me.deaths = (now >= S.deaths[1]) and 1 or 0
        me.deathEvents = me.deaths > 0 and { { time = S.deaths[1] } } or {}
    end
end

-- Puts a newly picked dungeon on the demo run (or keeps the fallback).
local function Reroll(r)
    if MS._demoFixed and not r._demoPick then return end   -- tests: the scripted dungeon
    if MS.Flavor.mythicPlus then
        local S = RandomKeyScript()
        if S then
            r._script = S
            r.dungeonName, r.challengeMapID, r.keystoneTimeLimit = S.name, S.mapID, S.limit
            r.keystoneLevel = _rand(8, 18)
            r._demoBest = S.best
        end
    else
        local S = RandomForeverScript(r._demoPick)
        if S then
            r._script = S
            r.dungeonName, r.wingName, r.instanceID, r.uiMapID = S.key, S.key, nil, nil
        end
    end
end

-- The demo run as it stands now: a new dungeon each time round.
local function DemoAt(r)
    local S = r._script or (MS.Flavor.mythicPlus and KEY_SCRIPT or FOREVER_SCRIPT)
    local elapsed = (GetTime() - r._demoStart) * DEMO_SPEED
    if elapsed >= S.loop then
        elapsed = elapsed % S.loop
        r._demoStart = GetTime() - elapsed / DEMO_SPEED
        Reroll(r)
    end
    if MS.Flavor.mythicPlus then KeyAt(r, elapsed) else ForeverAt(r, elapsed) end
end

local function DemoRun(pick)
    local r
    if MS.Flavor.mythicPlus then
        r = UI.DemoRun(2)
        r.keyUpgrades, r.duration, r.ratingAfter = nil, nil, nil
        r.keystoneTimeLimit = KEY_SCRIPT.limit
        r._demoBest = KEY_SCRIPT.best
        if C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
            local ok, list = pcall(C_MythicPlus.GetCurrentAffixes)
            if ok and type(list) == "table" then r.affixes = list end
        end
    else
        r = MS.NewRunData()
        r.dungeonName, r.wingName, r.difficultyLabel = "Scarlet Monastery", "Scarlet Monastery: Library", "Normal"
        r.progress = { xp = 0, qx = 0, kills = 0, gold = 0, quests = {}, questRewards = {}, levels = 0, rep = {} }
        local myName = MS.ShortName(MS:UnitPlayerName("player") or "You")
        local me = MS.NewPlayerStats(myName, select(2, UnitClass("player")) or "WARRIOR", "Demo-1")
        r.players = { [me.name] = me }
    end
    r._demo, r._demoStart = true, GetTime()
    r._demoPick = pick
    Reroll(r)
    DemoAt(r)
    return r
end

UI.CompactDemoRun, UI.CompactDemoAt = DemoRun, DemoAt

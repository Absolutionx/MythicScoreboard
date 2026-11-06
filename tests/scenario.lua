-- usage: lua5.1 scenario.lua ADDON_DIR TOC
table.unpack = table.unpack or unpack
local dir, toc = arg[1], arg[2]
local M = dofile((arg[0]:match("^(.*)/") or ".") .. "/wowmock.lua")
local out = {}
local function say(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end out[#out + 1] = table.concat(t, " ") end
local function step(name, fn)
    local ok, err = pcall(fn)
    if not ok then say("!! ERROR in " .. name .. ": " .. tostring(err)) end
end

M.LoadTOC(dir, toc)
local MS = rawget(_G, "MythicScoreboard")
local forever = MS.FLAVOR == "forever"
say("flavor", MS.FLAVOR or "retail")

local function src(name, guid, amt, isLocal, cls)
    return { name = name, sourceGUID = guid, totalAmount = amt, isLocalPlayer = isLocal,
             classFilename = cls, amountPerSecond = 0 }
end
local function SetMeter(scale, dur)
    local list = {
        src("Jay-Breezy", "Player-1-AAA", 1000 * scale, true, "SHAMAN"),
        src("Akasha", "Player-1-BBB", 2000 * scale, false, "MAGE"),
        src("Girthy", "Player-1-CCC", 3000 * scale, false, "WARRIOR"),
        src("Skip", "Player-1-DDD", 500 * scale, false, "SHAMAN"),
        src("Hizazi", "Player-1-EEE", 800 * scale, false, "HUNTER"),
        src("Wolf", "Pet-0-1-99", 100 * scale, false, nil),
    }
    local small = {}
    for i, s in ipairs(list) do small[i] = src(s.name, s.sourceGUID, math.floor(s.totalAmount / 500), s.isLocalPlayer, s.classFilename) end
    M.meter = {
        [0] = { duration = dur, combatSources = list }, [2] = { duration = dur, combatSources = list },
        [5] = { combatSources = small }, [6] = { combatSources = {} }, [7] = { combatSources = list },
        [8] = { combatSources = {} }, [9] = { combatSources = {} },
    }
end
local function Players(tag)
    local run = MS.currentRun
    if not run then say(tag, "no current run"); return end
    local names = {}
    for k in pairs(run.players) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do
        local p = run.players[k]
        say(tag, k, "dmg=" .. (p.damageDone or 0), ("dps=%.1f"):format(p.dps or 0), "taken=" .. (p.damageTaken or 0),
            "int=" .. (p.interrupts or 0), "deaths=" .. (p.deaths or 0), "class=" .. tostring(p.class))
    end
end
local function State(tag)
    local r = MS.currentRun
    say(tag, "inDungeon=" .. tostring(MS.inDungeon), "run=" .. (r and r.dungeonName or "none"),
        "paused=" .. tostring(r and r._suspended ~= nil or false), "history=" .. #(MythicScoreboardDB.runs or {}))
end

step("login", function()
    M.Fire("ADDON_LOADED", "MythicScoreboard")
    M.Fire("PLAYER_LOGIN")
    local td = MythicScoreboardDB.settings.trackedDifficulties
    for k in pairs(td) do td[k] = true end
end)
step("enter dungeon", function()
    M.Fire("PLAYER_ENTERING_WORLD", true, false)
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.RunTimers(6)
end)
State("entered")
step("meter poll", function()
    SetMeter(1, 100)
    M.Tick(); M.Tick()
end)
Players("poll1")
step("boss", function()
    M.Fire("ENCOUNTER_START", 1443, "Oggleflint", 1, 5)
    M.now = M.now + 60
    M.Fire("ENCOUNTER_END", 1443, "Oggleflint", 1, 5, 1)
    M.RunTimers(3)
end)
step("death", function()
    M.dead.party1 = true
    M.Fire("PLAYER_DEAD"); M.Tick()
    M.dead.party1 = nil; M.Tick()
end)
Players("after-death")
step("scoreboard", function()
    MS:ShowScoreboard()
    MS:RefreshOverview()
    M.RunTimers(2)
end)
step("settings+history", function()
    local f = rawget(_G, "MythicScoreboardFrame")
    if f and f.SettingsBtn then f.SettingsBtn:Fire("OnClick"); say("settings shown", tostring(f.SettingsPopup:IsShown())) end
    if f and f.HistoryButton then f.HistoryButton:Fire("OnClick"); say("settings after history click", tostring(f.SettingsPopup:IsShown())) end
    if f and f.SettingsBtn then f.SettingsBtn:Fire("OnClick") end
end)
step("release", function()
    M.dead.player = true
    M.instance = { "Orgrimmar", "none", 0 }
    M.Fire("PLAYER_LEAVING_WORLD")
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.RunTimers(6)
end)
State("released")
step("return", function()
    M.dead.player = nil
    M.instance = { "Ragefire Chasm", "party", 1 }
    M.Fire("PLAYER_LEAVING_WORLD")
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.RunTimers(6)
    SetMeter(0.1, 20)     -- the meter started over while we were out
    M.Tick(); M.Tick()
end)
State("returned")
Players("after-return")
step("hover everything", function()
    MS:ShowScoreboard(); MS:RefreshOverview(); M.RunTimers(2)
    -- Fire hover scripts on every widget: tooltips are where missing locals hide.
    local seen = 0
    for _, w in ipairs((function() local t = {} for k, v in pairs(package.loaded) do end return t end)()) do end
    local stack = { rawget(_G, "MythicScoreboardFrame") }
    while #stack > 0 do
        local w = table.remove(stack)
        if w then
            for _, n in ipairs({ "OnEnter", "OnLeave" }) do
                local s = w._scripts and w._scripts[n]
                if s then seen = seen + 1; local ok, e = pcall(s, w); if not ok then say("!! hover error:", e) end end
            end
            for _, c in ipairs(w._children or {}) do stack[#stack + 1] = c end
        end
    end
    say("hover scripts fired", seen > 20 and "many" or seen)
end)
step("leave alive", function()
    M.instance = { "Orgrimmar", "none", 0 }
    M.Fire("PLAYER_LEAVING_WORLD")
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.RunTimers(6)
end)
State("left")
step("close paused run", function()
    -- 2.5+: leaving pauses; close it so the history view has a saved run.
    if MS.ClosePausedRun and MS.currentRun and MS.currentRun._suspended then MS:ClosePausedRun() end
end)
State("closed")
step("history view", function()
    local f = rawget(_G, "MythicScoreboardFrame")
    MS:ShowScoreboard(); MS:RefreshOverview(); M.RunTimers(2)
    if f and f.HistoryButton then f.HistoryButton:Fire("OnClick") end
    local saved = MythicScoreboardDB.runs[1]
    if saved then
        local ks = {}
        for k in pairs(saved.players) do ks[#ks + 1] = k end
        table.sort(ks)
        say("saved run", saved.dungeonName, "completed=" .. tostring(saved.completed), "bosses=" .. #saved.bosses, "players=" .. table.concat(ks, ","))
    end
end)
step("slash", function()
    SlashCmdList["MYTHICSCOREBOARD"]("help")
    SlashCmdList["MYTHICSCOREBOARD"]("")
end)
step("poke everything", function()
    -- Give history a second run, then hover and click every widget the addon
    -- made. Errors inside handlers are reported, not fatal.
    local errs, fired = {}, 0
    for pass = 1, 2 do
        local list = {}
        for i, w in ipairs(M.allFrames) do list[i] = w end
        for _, w in ipairs(list) do
            for _, n in ipairs({ "OnEnter", "OnLeave", "OnClick", "OnMouseUp", "OnMouseWheel" }) do
                local s = w._scripts and w._scripts[n]
                if s then
                    fired = fired + 1
                    local ok, e = pcall(s, w, n == "OnMouseWheel" and -1 or "LeftButton")
                    if not ok then errs[tostring(e)] = true end
                end
            end
        end
        M.RunTimers(3)
    end
    for e in pairs(errs) do say("!! handler error:", e) end
    say("handlers fired", fired > 100 and "100+" or fired)
end)
for _, p in ipairs(M.printed) do say("chat:", (p:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
io.write(table.concat(out, "\n"), "\n")

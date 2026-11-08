-- Loading: saved data set up and brought up to date, then the run in
-- progress (if a /reload happened inside one) picked up again.

local MS = _G["MythicScoreboard"]
local L = MS.L

local function InitDB()
    MythicScoreboardDB = MythicScoreboardDB or {}
    local db = MythicScoreboardDB
    db.runs = db.runs or {}
    db.mobForces = db.mobForces or {}
    MS:InitSettings(db)
    return db
end

local function OnLoaded()
    -- The client's language, or the one picked with /sb lang to preview it.
    local acc = rawget(_G, "MythicScoreboardAccountDB")
    MS:UseLocale(type(acc) == "table" and acc.previewLocale or nil)
    local db = InitDB()
    if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable) then
        print("|cffff4444[MythicScoreboard]|r " .. L["C_DamageMeter unavailable — requires WoW 12.0+."])
    end
    MS:RunMigrations()                      -- saved data up to date before anything reads it
    MS:SyncAccountStats()                   -- this character's runs, account-wide
    -- The window is built the first time it's opened.
    if MS.UpdateMinimapButton then MS:UpdateMinimapButton() end
    -- A run in progress at the last logout or /reload. Inside (or paused),
    -- it carries on. Logged in elsewhere, it isn't dropped: a key is saved as
    -- it stood, any other run comes back paused from the moment you logged
    -- out, so returning soon carries on and otherwise it closes as usual.
    local _, itype = GetInstanceInfo()
    local active = db.activeRun
    if active and active._active then
        if itype == "party" or active._suspended then
            MS:RestoreCurrentRun()
        elseif (active.keystoneLevel or 0) > 0 then
            -- Where you are isn't always known this early: decide once the
            -- loading screen is over. No key going by then: it's saved.
            MS:RestoreCurrentRun()
            local run = MS.currentRun
            C_Timer.After(10, function()
                if MS.currentRun ~= run or not run then return end
                local _, here = GetInstanceInfo()
                local key = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
                    and C_ChallengeMode.GetActiveChallengeMapID()
                if not key and here ~= "party" then
                    MS:CommitRun({ completed = run.completed, inTime = run.inTime or false })
                end
            end)
        else
            active._suspended = { at = active._savedAt or time(), offline = active._offline }
            MS:RestoreCurrentRun()
        end
        C_Timer.After(0.2, function() MS:Changed("run") end)
    end
    print("|cff00ccff[MythicScoreboard]|r v" .. MS.version .. "  " .. L["/sb to open."])
end

MS.EventHandlers.ADDON_LOADED = function(name)
    if name == "MythicScoreboard" then OnLoaded() end
end

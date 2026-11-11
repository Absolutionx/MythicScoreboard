-- Season data and shared constants, kept in one place: a new season is a
-- change to this file only.

local MS = _G["MythicScoreboard"]

MS.MYTHIC_PLUS = 8            -- difficulty ID of a Mythic+ keystone run

-- Time a death costs a key, by key level, used only when the game doesn't
-- say (C_ChallengeMode.GetDeathCount missing, or its number hidden). The
-- game's own figure always wins. (The War Within rules: 5 s, 15 s from +12.)
MS.DEATH_PENALTY = { { level = 12, seconds = 15 }, { level = 4, seconds = 5 } }
function MS.DeathPenaltyFor(level)
    for _, step in ipairs(MS.DEATH_PENALTY) do
        if (level or 0) >= step.level then return step.seconds end
    end
    return 0
end

-- M+ time limits, for when the game doesn't give one (see MS:KnownTimeLimit).
-- Keyed by the dungeon's English name: on other languages these are skipped
-- and the game's own numbers are used.
MS.DUNGEON_TIMERS = {
    -- Season 2 (patch 12.1)
    ["Altar of Fangs"]         = 30 * 60,
    ["Murder Row"]             = 34 * 60,
    ["Den of Nalorakk"]        = 32 * 60,
    ["The Blinding Vale"]      = 31 * 60,
    ["Voidscar Arena"]         = 30 * 60,
    ["King's Rest"]            = 33 * 60,
    ["Temple of Sethraliss"]   = 33 * 60,
    ["Ruby Life Pools"]        = 28 * 60,
    -- Season 1 (kept for saved-run display)
    ["Magisters' Terrace"]     = 34 * 60,
    ["Maisara Caverns"]        = 33 * 60,
    ["Nexus-Point Xenas"]      = 30 * 60,
    ["Windrunner Spire"]       = 33 * 60,
    ["Algeth'ar Academy"]      = 31 * 60,
    ["Pit of Saron"]           = 30 * 60,
    ["Seat of the Triumvirate"]= 34 * 60,
    ["Skyreach"]               = 28 * 60,
}

-- Boss counts for clear detection outside Mythic+ (Completion.lua). Dungeons
-- not listed, and every dungeon on other languages, are counted from the
-- Encounter Journal instead.
MS.BOSS_COUNTS = {
    -- Season 2 (patch 12.1)
    ["Altar of Fangs"]         = 3,
    ["Murder Row"]             = 4,
    ["Den of Nalorakk"]        = 3,
    ["The Blinding Vale"]      = 4,
    ["Voidscar Arena"]         = 3,
    ["King's Rest"]            = 4,
    ["Temple of Sethraliss"]   = 3,
    ["Ruby Life Pools"]        = 3,
    -- Season 1 (kept for saved-run completion detection)
    ["Windrunner Spire"]       = 4,
    ["Maisara Caverns"]        = 3,
    ["Magisters' Terrace"]     = 4,
    ["Nexus-Point Xenas"]      = 3,
    ["Algeth'ar Academy"]      = 4,
    ["Seat of the Triumvirate"]= 4,
    ["Skyreach"]               = 4,
    ["Pit of Saron"]           = 3,
}

-- A key's time limit: the game's own for this map, else the table above.
function MS:KnownTimeLimit(run)
    local mapID = run and run.challengeMapID
    if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local ok, _, _, limit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        if ok and type(limit) == "number" and not MS.IsSecret(limit)
                and limit > 10 and limit < 7200 then
            return limit
        end
    end
    return run and MS.DUNGEON_TIMERS[run.dungeonName or ""]
end

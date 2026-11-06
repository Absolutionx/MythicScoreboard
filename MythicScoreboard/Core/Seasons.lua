-- Season data and shared constants, kept in one place: a new season is a
-- change to this file only.

local MS = _G["MythicScoreboard"]

MS.MYTHIC_PLUS = 8            -- difficulty ID of a Mythic+ keystone run

-- M+ time limits, used when C_ChallengeMode.GetDeadlineExpiration() is unavailable.
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

-- Boss counts for completion detection. EJ is the fallback for unlisted dungeons.
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

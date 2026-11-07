-- How the two clients differ, in one place.
--
-- Both TOCs load this file; MythicScoreboard_Forever.toc then loads
-- Flavor_Forever.lua, which changes what differs on WoW Forever. Code asks
-- about a trait (MS.Flavor.twoPartNames), never which client it's on.

local MS = _G["MythicScoreboard"]

MS.Flavor = {
    name          = "retail",
    -- Names: "Name-Realm" (retail), or a first name and a surname (Forever,
    -- where UnitName's second value is the surname, not a realm).
    twoPartNames  = false,
    -- Mythic+ exists: keystones, the rating column, enemy forces settings.
    mythicPlus    = true,
    -- Dungeons come in several difficulties: a badge in the header, and a
    -- choice in Settings of which ones to track.
    difficulties  = true,
    -- Dungeons have a level range: a Level column instead of rating, and the
    -- range in the header, history and tooltips.
    dungeonLevels = false,
    -- The addon knows each dungeon's bosses: the header shows "3 of 6 bosses".
    bossProgress  = false,
    -- Runs record what they did for your character: experience and levels,
    -- mobs killed, quests, gold and reputation (Core/RunStats.lua).
    progressStats = false,
}
MS.FLAVOR = MS.Flavor.name

-- Which difficulties can be tracked, grouped as Settings shows them.
MS.DIFF_GROUPS = {
    { key="mythicplus",  label="Mythic+",     ids={8},           default=true  },
    { key="mythic",      label="Mythic",      ids={23},          default=false },
    { key="heroic",      label="Heroic",      ids={2},           default=false },
    { key="normal",      label="Normal",      ids={1},           default=false },
    { key="timewalking", label="Timewalking", ids={24,33},       default=false },
    { key="follower",    label="Follower",    ids={205,207,208}, default=false },
}

-- When a dungeon counts as cleared, if there's a choice (nil: the boss count).
MS.CLEAR_RULES = nil

-- WoW Forever: what differs from retail (see Flavor.lua).
-- Loaded only by MythicScoreboard_Forever.toc, right after Flavor.lua.
--
-- Forever has classic-era dungeons (plus new ones), Normal/Heroic only and no
-- Mythic+. The dungeons themselves are described in Forever.lua.

local MS = _G["MythicScoreboard"]

local F = MS.Flavor
F.name          = "forever"
F.twoPartNames  = true
F.mythicPlus    = false
F.difficulties  = false
F.dungeonLevels = true
F.bossProgress  = true
MS.FLAVOR = F.name

-- Forever dungeons have a single difficulty: every dungeon run is tracked and
-- the difficulty options are hidden from settings.
MS.DIFF_GROUPS = {
    { key = "dungeons", label = "Dungeons", ids = {}, default = true, catchAll = true, alwaysOn = true },
}

MS.CLEAR_RULES = {
    { key = "final", label = "Final boss killed", note = "Waits for other bosses or leaving" },
    { key = "all",   label = "Every non-rare boss killed" },
    { key = "leave", label = "Leaving the dungeon" },
}


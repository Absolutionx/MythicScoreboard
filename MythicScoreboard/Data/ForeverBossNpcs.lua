-- WoW Forever: which creature each dungeon boss is (its npc ID), so its
-- portrait can be asked of the game before anyone on this account has met
-- it (Core/Portraits.lua). Recorded by the addon itself in play: met bosses
-- are kept in MythicScoreboardPortraitsDB.npc, and /sb bosses shows which
-- are still missing. Loaded only by MythicScoreboard_Forever.toc.
--
-- [boss name] = npc ID

local MS = _G["MythicScoreboard"]

MS.ForeverData.BOSS_NPCS = {
}

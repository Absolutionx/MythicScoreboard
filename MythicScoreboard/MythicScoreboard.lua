_G["MythicScoreboard"] = _G["MythicScoreboard"] or {}
local MS = _G["MythicScoreboard"]

-- TOC is authoritative at runtime; fallback for dev environments.
-- (GetAddOnMetadata moved to C_AddOns; the old global is gone in current clients.)
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
MS.version = GetMeta and GetMeta("MythicScoreboard", "Version") or "2.7.0"

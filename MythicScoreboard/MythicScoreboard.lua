_G["MythicScoreboard"] = _G["MythicScoreboard"] or {}
local MS = _G["MythicScoreboard"]

-- TOC is authoritative at runtime; fallback for dev environments.
-- (GetAddOnMetadata moved to C_AddOns; the old global is gone in current clients.)
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
MS.version = GetMeta and GetMeta("MythicScoreboard", "Version") or "2.8.0"

-- ── Changes the windows show ───────────────────────────────────────────────
-- Core code says what changed (MS:Changed("run")); the windows listen
-- (MS:OnChanged) and redraw as they see fit. The core never calls the UI.
--   "run"        the run in progress: players, bosses, deaths, meter numbers
--   "loot"       an item dropped or was looked up
--   "portraits"  a boss portrait was learned
--   "history"    saved runs added or removed
local listeners = {}
function MS:OnChanged(fn) listeners[#listeners + 1] = fn end
function MS:Changed(what)
    for i = 1, #listeners do listeners[i](what or "run") end
end

-- An error worth one line in chat (once per message), from anywhere.
local said = {}
function MS:ReportError(what, err)
    local msg = tostring(err)
    if said[msg] then return end
    said[msg] = true
    print("|cffff4444[MythicScoreboard]|r " .. tostring(what) .. " error: " .. msg)
end

-- ── Midnight's hidden values ───────────────────────────────────────────────
-- From 12.0 the game hands addons some values it won't let them read (a
-- player's name or numbers in an instance): issecretvalue says which. The
-- check is here once; older clients (Forever) have no such values.
local issecret = issecretvalue
MS.HasSecrets = issecret ~= nil
function MS.IsSecret(v) return issecret ~= nil and v ~= nil and issecret(v) or false end
-- v, or nil when it's hidden. (MS.Readable, in Roster.lua, is for names: a
-- non-empty string or nil.)
function MS.ReadableValue(v)
    if v == nil or (issecret ~= nil and issecret(v)) then return nil end
    return v
end

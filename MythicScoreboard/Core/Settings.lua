-- Every setting: its default, how it's read and how it's changed.
--
-- Settings live in MythicScoreboardDB.settings (per character). Nothing else
-- reads or writes that table: other files use MS:GetSetting / MS:SetSetting,
-- or the named getters below, which the settings popup calls.
--
-- MS:OnSettingChanged(key, fn) runs fn(value) after a change, so whatever a
-- setting controls (the minimap button, nameplate labels, history length)
-- updates itself instead of the popup knowing about it.

local MS = _G["MythicScoreboard"]
local _floor, _max, _min = math.floor, math.max, math.min

local DEFAULTS = {
    autoResetMeter          = true,
    autoOpenOnComplete      = true,
    historyLimit            = 10,
    clearRule               = "final",
    showMobForces           = true,
    showMobForcesNameplates = true,
    minimapButton           = true,
    autoTakeFlights         = false,       -- WoW Forever: take the flight the directions say to
    compactStyle            = "detailed",  -- the in-run frame: compact | detailed | minimal | off (not saved until picked)
    -- compactPos: no default (the frame starts near the top right)
    -- minimapAngle: no default (the button's resting place is its own)
    -- trackedDifficulties: { [group key] = bool }, defaults from MS.DIFF_GROUPS
}
MS.SETTING_DEFAULTS = DEFAULTS

local HISTORY_MIN, HISTORY_MAX = 1, 30

-- Read from DEFAULTS until the player picks one, so a later default reaches
-- everyone who never chose.
local UNSAVED = { compactStyle = true }

local function Store()
    local db = rawget(_G, "MythicScoreboardDB")
    return db and db.settings
end

-- Fills in anything missing. Called once at load (Bootstrap.lua).
function MS:InitSettings(db)
    db.settings = type(db.settings) == "table" and db.settings or {}
    local s = db.settings
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil and not UNSAVED[k] then s[k] = v end
    end
    -- Test builds saved the in-run frame's first default as if picked.
    if s.compactStyle == "compact" and not s.compactPicked then s.compactStyle = nil end
    if type(s.trackedDifficulties) ~= "table" then s.trackedDifficulties = {} end
    for _, grp in ipairs(MS.DIFF_GROUPS) do
        if s.trackedDifficulties[grp.key] == nil then
            s.trackedDifficulties[grp.key] = grp.default and true or false
        end
    end
    return s
end

-- ── Generic ────────────────────────────────────────────────────────────────
local _listeners = {}

function MS:GetSetting(key)
    local s = Store()
    local v = s and s[key]
    if v == nil then v = DEFAULTS[key] end
    return v
end

function MS:SetSetting(key, value)
    local s = Store()
    if not s then return end
    s[key] = value
    for _, fn in ipairs(_listeners[key] or {}) do fn(value) end
end

function MS:OnSettingChanged(key, fn)
    _listeners[key] = _listeners[key] or {}
    table.insert(_listeners[key], fn)
end

local function Bool(key)
    return function() return MS:GetSetting(key) ~= false end,
           function(_, v) MS:SetSetting(key, v and true or false) end
end

-- ── Named settings ─────────────────────────────────────────────────────────
MS.GetAutoResetMeter,       MS.SetAutoResetMeter       = Bool("autoResetMeter")
MS.GetAutoOpenOnComplete,   MS.SetAutoOpenOnComplete   = Bool("autoOpenOnComplete")
MS.GetMobForcesTooltip,     MS.SetMobForcesTooltip     = Bool("showMobForces")
MS.GetMobForcesNameplate,   MS.SetMobForcesNameplate   = Bool("showMobForcesNameplates")
MS.GetMinimapButton,        MS.SetMinimapButton        = Bool("minimapButton")
MS.GetAutoTakeFlights,      MS.SetAutoTakeFlights      = Bool("autoTakeFlights")

-- The in-run frame's style (UI_Compact.lua); "off" hides it.
MS.COMPACT_STYLES = { "compact", "detailed", "minimal" }
function MS:GetCompactStyle()
    local v = self:GetSetting("compactStyle")
    if v == "off" then return "off" end
    for _, s in ipairs(MS.COMPACT_STYLES) do if s == v then return v end end
    return DEFAULTS.compactStyle
end
function MS:SetCompactStyle(v)
    local s = Store()
    if s then s.compactPicked = true end
    self:SetSetting("compactStyle", v)
end
-- On or off, for the settings popup; turning it back on brings back the style it had.
function MS:GetCompactFrame() return self:GetCompactStyle() ~= "off" end
function MS:SetCompactFrame(on)
    local s = Store()
    if on then
        self:SetCompactStyle((s and s.compactLastStyle) or DEFAULTS.compactStyle)
    else
        local cur = self:GetCompactStyle()
        if s and cur ~= "off" then s.compactLastStyle = cur end
        self:SetCompactStyle("off")
    end
end

function MS:GetHistoryLimit()
    return _max(HISTORY_MIN, _min(HISTORY_MAX, tonumber(self:GetSetting("historyLimit")) or DEFAULTS.historyLimit))
end

function MS:SetHistoryLimit(value)
    value = _max(HISTORY_MIN, _min(HISTORY_MAX, _floor(tonumber(value) or DEFAULTS.historyLimit)))
    self:SetSetting("historyLimit", value)
end

-- When a run counts as cleared, on clients that offer a choice
-- (MS.CLEAR_RULES). Nil where there's no choice: the boss count decides.
function MS:GetClearRule()
    if not MS.CLEAR_RULES then return nil end
    local r = self:GetSetting("clearRule")
    for _, rule in ipairs(MS.CLEAR_RULES) do
        if rule.key == r then return r end
    end
    return MS.CLEAR_RULES[1].key
end

function MS:SetClearRule(rule) self:SetSetting("clearRule", rule) end

-- Whether runs in a difficulty group are recorded.
function MS:IsDifficultyGroupOn(key)
    local s = Store()
    local td = s and s.trackedDifficulties
    if not td then return true end
    return td[key] == true
end

function MS:SetDifficultyGroupOn(key, on)
    local s = Store()
    if not (s and s.trackedDifficulties) then return end
    s.trackedDifficulties[key] = on and true or false
    for _, fn in ipairs(_listeners.trackedDifficulties or {}) do fn(s.trackedDifficulties) end
end

-- The minimap button's angle, in degrees (nil: its default place).
function MS:GetMinimapAngle() return self:GetSetting("minimapAngle") end
function MS:SetMinimapAngle(deg) self:SetSetting("minimapAngle", deg) end

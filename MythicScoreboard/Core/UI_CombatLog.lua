-- Combat logging, for log sites: the game writes WoWCombatLog.txt while
-- logging is on, and log sites read that file. Addons can turn logging on and
-- off, but can't read the file or upload it.
--
-- Settings (Settings.lua): off (the default), remind or auto; in raids,
-- dungeons, or both; turn on Advanced Combat Logging when logging starts.
-- (Uploading is the log site's own app: usually live, as you play.)
--   remind: going into a raid (or dungeon) with logging off shows a small
--           popup with a button to start it.
--   auto:   logging starts on the way in and stops on the way out (only if
--           the addon started it).

local MS = _G["MythicScoreboard"]
local L, UI = MS.L, MS.UI
local P, Text, Box, Btn = UI.P, UI.Text, UI.Box, UI.Btn
local function G(name) return rawget(_G, name) end

-- Logging on (true), off (false), or nil where the game doesn't offer it.
local function Logging()
    local f = G("LoggingCombat")
    if not f then return nil end
    local ok, on = pcall(f)
    return ok and on and true or false
end
local function SetLogging(on) pcall(G("LoggingCombat"), on) end

local function CVar(name)
    local get = G("GetCVar") or (G("C_CVar") and G("C_CVar").GetCVar)
    local ok, v = pcall(get or error, name)
    return ok and v or nil
end
local function SetCVarTo(name, v)
    local set = G("SetCVar") or (G("C_CVar") and G("C_CVar").SetCVar)
    return (pcall(set or error, name, v))
end

local state = { started = false, prompted = nil }

-- Turns logging on (and Advanced Combat Logging, if that's wanted).
function MS:StartCombatLog()
    if Logging() == nil then return end
    if MS:GetCombatLogACL() and CVar("advancedCombatLogging") ~= "1"
        and SetCVarTo("advancedCombatLogging", "1") then
        MS.Say(L["Advanced Combat Logging turned on."])
    end
    if not Logging() then
        SetLogging(true)
        MS.Say(L["Combat logging on."])
        state.started = true
    end
end

-- Whether this place is one to log: a raid or a dungeon, as asked for.
local function Wanted()
    local inside, kind = IsInInstance()
    if not inside then return false end
    local where = MS:GetCombatLogWhere()
    if kind == "raid" then return where ~= "dungeons", kind end
    if kind == "party" then return where ~= "raids", kind end
    return false, kind
end

local function Check()
    if Logging() == nil then return end
    local mode = MS:GetCombatLog()
    local want, kind = Wanted()
    if want then
        local here = (GetInstanceInfo()) .. ":" .. kind
        if mode == "auto" then
            MS:StartCombatLog()
        elseif mode == "remind" and not Logging() and state.prompted ~= here then
            state.prompted = here
            UI.ShowCombatLogReminder()
        end
        return
    end
    -- Out again: logging the addon started stops.
    state.prompted = nil
    if UI.HideCombatLogReminder then UI.HideCombatLogReminder() end
    if state.started and Logging() then
        SetLogging(false)
        MS.Say(L["Combat logging off."])
    end
    state.started = false
end
MS._CombatLogCheck, MS._CombatLogState = Check, state      -- (for tests)

MS:On("PLAYER_ENTERING_WORLD", Check)
MS:On("ZONE_CHANGED_NEW_AREA", Check)

-- ── The popups ─────────────────────────────────────────────────────────────
-- In the addon's stone and bronze, near the top of the screen.
local function Dialog(name, w, h, title)
    local d = CreateFrame("Frame", name, UIParent)
    d:SetSize(w, h)
    d:SetPoint("TOP", UIParent, "TOP", 0, -150)
    d:SetFrameStrata("DIALOG")
    d:EnableMouse(true)
    d:SetMovable(true); d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    UI.BuildChrome(d, 30)
    local t = Text(d, "semibold", 15, P.ivory); t:SetPoint("TOPLEFT", 14, -12); t:SetText(title)
    local close = Box(Btn(d), true)
    close:SetSize(20, 20); close:SetPoint("TOPRIGHT", -10, -9)
    local x = Text(close, "semibold", 12, P.ash, "CENTER"); x:SetPoint("CENTER", 0, 1); x:SetText("x")
    close:SetScript("OnClick", function() d:Hide() end)
    d.body = Text(d, "medium", 13, P.ash)
    d.body:SetPoint("TOPLEFT", 14, -38); d.body:SetWidth(w - 28); d.body:SetWordWrap(true)
    tinsert(UISpecialFrames, name)
    d:Hide()
    return d
end

local function Button(parent, label, onClick)
    local b = Box(Btn(parent), true)
    local t = Text(b, "medium", 13, P.ivory, "CENTER"); t:SetPoint("CENTER", 0, 0); t:SetText(label)
    b:SetSize(math.max(96, math.ceil((t:GetStringWidth() or 0) + 28)), 26)
    b:SetScript("OnClick", onClick)
    b.label = t
    return b
end

local remindF
function UI.ShowCombatLogReminder()
    if not remindF then
        local d = Dialog("MythicScoreboardLogReminder", 360, 112, L["Combat logging is off"])
        d.body:SetText(L["Log sites only show fights that were logged. Start logging now?"])
        d.start = Button(d, L["Start logging"], function() MS:StartCombatLog(); d:Hide() end)
        d.start:SetPoint("BOTTOMRIGHT", -14, 12)
        d.later = Button(d, L["Not now"], function() d:Hide() end)
        d.later:SetPoint("RIGHT", d.start, "LEFT", -8, 0)
        remindF = d
    end
    remindF:Show()
    return remindF
end
function UI.HideCombatLogReminder() if remindF then remindF:Hide() end end

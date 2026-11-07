-- Minimal World of Warcraft API stand-in for loading MythicScoreboard outside
-- the game. Widgets record their scripts so tests can fire them. Unknown
-- widget methods are no-ops; unknown *globals* are errors (that's the point:
-- a missing local after a refactor must fail loudly here).

local M = {}
M.timers, M.tickers, M.printed, M.events = {}, {}, {}, {}
M.now = 1000

-- ── Widgets ────────────────────────────────────────────────────────────────
local Widget = {}
local function noop() end
local WidgetMT = {
    __index = function(t, k)
        local v = rawget(Widget, k)
        if v ~= nil then return v end
        -- Only real widget method names fall back to a no-op; the addon's
        -- own fields (frame.SettingsPopup etc.) must read as nil until set.
        if type(k) == "string" and (k:find("^Set%u") or k:find("^Enable") or k:find("^Disable")
                or k:find("^Register") or k:find("^Unregister") or k:find("^Clear%u")
                or k:find("^Lower") or k:find("^Raise") or k:find("^Start") or k:find("^Stop")
                or k:find("^Play") or k:find("^Add%u") or k:find("^Adjust") or k:find("^Update%u")) then
            return noop
        end
        return nil
    end,
}
local allFrames = {}
M.allFrames = allFrames
local function New(kind, parent, name)
    local w = setmetatable({ _kind = kind, _parent = parent, _scripts = {}, _shown = kind ~= "Frame" or true,
                             _w = 100, _h = 20, _text = "", _children = {}, _points = 0 }, WidgetMT)
    if parent and type(parent) == "table" and parent._children then table.insert(parent._children, w) end
    allFrames[#allFrames + 1] = w
    if name then _G[name] = w end
    return w
end
M.New = New
function Widget:SetScript(n, f) self._scripts[n] = f end
function Widget:GetScript(n) return self._scripts[n] end
function Widget:HookScript(n, f)
    local old = self._scripts[n]
    self._scripts[n] = function(...) if old then old(...) end f(...) end
end
function Widget:Fire(n, ...) local f = self._scripts[n]; if f then return f(self, ...) end end
function Widget:SetSize(w, h) self._w, self._h = w, h end
function Widget:SetWidth(w) self._w = w end
function Widget:SetHeight(h) self._h = h end
function Widget:GetWidth() return self._w end
function Widget:GetHeight() return self._h end
function Widget:GetSize() return self._w, self._h end
function Widget:Show() self._shown = true; self:Fire("OnShow") end
function Widget:Hide() local was = self._shown; self._shown = false; if was then self:Fire("OnHide") end end
function Widget:SetShown(s) if s then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible() return self._shown end
function Widget:GetParent() return self._parent end
function Widget:SetParent(p) self._parent = p end
function Widget:SetText(t) self._text = t == nil and "" or tostring(t) end
function Widget:GetText() return self._text end
-- Text width by font, close to the real fonts (measured from screenshots):
-- Barlow ~0.47em a character, Cinzel ~0.75em, the game font ~0.565em.
function Widget:GetStringWidth()
    local t = (self._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if not self._fontSize then return #t * 7 end
    local path = self._fontPath or ""
    local k = path:find("Barlow") and 0.40 or path:find("Cinzel") and 0.75 or 0.565
    return #t * self._fontSize * k
end
function Widget:GetStringHeight() return 14 end
function Widget:GetFont() return "font", 12, "" end
function Widget:SetFont(path, size) self._fontPath, self._fontSize = path, size; return true end
function Widget:GetFrameLevel() return 1 end
function Widget:GetLeft() return 0 end
function Widget:GetRight() return self._w end
function Widget:GetTop() return self._h end
function Widget:GetBottom() return 0 end
function Widget:GetCenter() return 0, 0 end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetScale() return 1 end
function Widget:GetObjectType() return self._kind end
function Widget:GetName() return nil end
function Widget:GetNumPoints() return self._points end
function Widget:SetPoint(a, rel, b, x, y) self._points = self._points + 1; self._at = { a, rel, b, x, y } end
function Widget:ClearAllPoints() self._points = 0 end
function Widget:GetMinMaxValues() return self._min or 0, self._max or 0 end
function Widget:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Widget:GetValue() return self._val or 0 end
function Widget:SetValue(v) self._val = v; self:Fire("OnValueChanged", v) end
function Widget:GetVerticalScroll() return 0 end
function Widget:GetDisplayInfo() return 1234 end
function Widget:IsMouseOver() return self._mouse == true end
function Widget:GetChildren() return table.unpack(self._children) end
function Widget:GetRegions() return end
function Widget:GetAlpha() return 1 end
function Widget:GetTexture() return self._tex end
function Widget:SetTexture(t) self._tex = t end
function Widget:GetVertexColor() return 1, 1, 1, 1 end
function Widget:GetTextColor() return 1, 1, 1, 1 end
function Widget:IsMouseEnabled() return true end
function Widget:CreateTexture() return New("Texture", self) end
function Widget:CreateLine() local l = New("Line", self); return l end
function Widget:SetStartPoint(_, rel, x, y) self._start = { x, y } end
function Widget:SetEndPoint(_, rel, x, y) self._end = { x, y } end
function Widget:SetThickness(t) self._thick = t end
function Widget:CreateMaskTexture() return New("MaskTexture", self) end
function Widget:CreateFontString() return New("FontString", self) end
function Widget:CreateAnimationGroup() local g = New("AnimationGroup", self); g.CreateAnimation = function() return New("Animation", g) end; return g end
function Widget:RegisterEvent(e) M.events[e] = M.events[e] or {}; table.insert(M.events[e], self) end
function Widget:UnregisterEvent() end
function Widget:UnregisterAllEvents() end
function Widget:IsEventRegistered() return true end
function Widget:NumLines() return 0 end

function CreateFrame(kind, name, parent) return New(kind or "Frame", parent, name) end
UIParent = New("Frame", nil)
GameTooltip = New("GameTooltip", UIParent)
Minimap = New("Frame", UIParent, "Minimap"); Minimap:SetSize(200, 200)
M.cursor = { 0, 0 }
GetCursorPosition = function() return M.cursor[1], M.cursor[2] end
function GameTooltip:SetOwner(o) self._owner = o; self._shown = false end
function GameTooltip:IsOwned(o) return self._owner == o end
function GameTooltip:SetText(t) self._text = t end
GameTooltip_Hide = function() GameTooltip:Hide() end
GameFontNormal = New("Font", nil)
UISpecialFrames = {}
EncounterJournal = nil

-- ── Fire an event at every registered frame ────────────────────────────────
function M.Fire(event, ...)
    for _, f in ipairs(M.events[event] or {}) do
        local s = f._scripts.OnEvent
        if s then s(f, event, ...) end
    end
end
function M.RunTimers(times)
    for _ = 1, (times or 1) do
        local t = M.timers; M.timers = {}
        for _, fn in ipairs(t) do fn() end
    end
end
function M.Tick()
    local list = {}
    for i, t in ipairs(M.tickers) do list[i] = t end
    for _, t in ipairs(list) do if not t.cancelled then t.fn() end end
end

-- ── Global API ─────────────────────────────────────────────────────────────
C_Timer = {
    After = function(_, fn) table.insert(M.timers, fn) end,
    NewTicker = function(_, fn)
        local t = { fn = fn }
        t.Cancel = function()
            t.cancelled = true
            for i, x in ipairs(M.tickers) do if x == t then table.remove(M.tickers, i); break end end
        end
        table.insert(M.tickers, t); return t
    end,
    NewTimer = function(_, fn) table.insert(M.timers, fn); return { Cancel = noop } end,
}
GetTime = function() return M.now end
time = os.time
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end return table.unpack(out) end
issecretvalue = function(v) return type(v) == "table" and v.__secret == true end
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end M.printed[#M.printed + 1] = table.concat(t, " ") end
geterrorhandler = function() return function(e) error(e) end end
hooksecurefunc = function(tbl, name, fn)
    if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
    local orig = tbl[name]
    tbl[name] = function(...) local r = { orig(...) }; fn(...); return table.unpack(r) end
end
GetLocale = function() return "enUS" end
GetRealmName = function() return "Forever" end
IsLoggedIn = function() return true end
InCombatLockdown = function() return false end
GetAddOnMetadata = function() return "test" end
C_AddOns = { GetAddOnMetadata = function() return "test" end }

M.instance = { "Ragefire Chasm", "party", 1 }
GetInstanceInfo = function() return M.instance[1], M.instance[2], M.instance[3], "Normal", 5, 0, false, M.instance[4] or 389 end
IsInInstance = function() return M.instance[2] ~= "none", M.instance[2] end
GetRealZoneText = function() return M.instance[1] end
GetDifficultyInfo = function(id) return id == 8 and "Mythic Keystone" or "Normal" end
GetWorldElapsedTime = function() return 0, 0 end

M.roster = {
    player = { name = "Jay", surname = "Breezy", guid = "Player-1-AAA", class = "SHAMAN", level = 14 },
    party1 = { name = "Akasha", surname = "Dawnfire", guid = "Player-1-BBB", class = "MAGE", level = 14 },
    party2 = { name = "Girthy", surname = "Stone", guid = "Player-1-CCC", class = "WARRIOR", level = 13 },
    party3 = { name = "Skip", guid = "Player-1-DDD", class = "SHAMAN", level = 12 },
    party4 = { name = "Hizazi", surname = "Bow", guid = "Player-1-EEE", class = "HUNTER", level = 14 },
    party4pet = { name = "Wolf", guid = "Pet-0-1-99", npc = true },
}
M.dead = {}
local function R(u) return M.roster[u] end
UnitExists = function(u) return R(u) ~= nil end
-- Forever: the second value is the surname (not a realm). Retail: realm or nil.
local function Forever() local ms = rawget(_G, "MythicScoreboard"); return ms and ms.FLAVOR == "forever" end
UnitName = function(u) local r = R(u); if r then return r.name, Forever() and r.surname or nil end end
GetUnitName = function(u) local r = R(u); if r then return (Forever() and r.surname) and (r.name .. " " .. r.surname) or r.name end end
UnitGUID = function(u) local r = R(u); return r and r.guid end
UnitClass = function(u) local r = R(u); if r and r.class then return r.class:lower(), r.class end end
UnitLevel = function(u) if u == "player" and M.level then return M.level end local r = R(u); return r and r.level or 0 end
UnitIsPlayer = function(u) local r = R(u); return r ~= nil and not r.npc end
UnitIsDeadOrGhost = function(u) return M.dead[u] == true end
UnitIsFriend = function() return true end
UnitCanAttack = function() return false end
UnitClassification = function() return "normal" end
UnitIsBossMob = function() return false end
UnitGroupRolesAssigned = function(u) return u == "party2" and "TANK" or (u == "party3" and "HEALER" or "DAMAGER") end
UnitAffectingCombat = function() return false end
GetNumGroupMembers = function() return M.groupSize or 5 end
IsInGroup = function() return (M.groupSize or 5) > 0 end
IsInRaid = function() return false end
CanInspect = function() return false end
NotifyInspect = noop
ClearInspectPlayer = noop
GetInspectSpecialization = function() return 0 end
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff" } end })
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
GetTexCoordsForRoleSmallCircle = function() return 0, 1, 0, 1 end
SetPortraitTextureFromCreatureDisplayID = noop
HandleModifiedItemClick = function() return false end
GetItemInfo = function() return nil end
GetItemInfoInstant = function() return nil end
LE_PARTY_CATEGORY_INSTANCE = 2
INSTANCE_RESET_SUCCESS = "%s has been reset."
for _, g in ipairs({"LOOT_ITEM_MULTIPLE","LOOT_ITEM_PUSHED_MULTIPLE","LOOT_ITEM_BONUS_ROLL_MULTIPLE","LOOT_ITEM","LOOT_ITEM_PUSHED","LOOT_ITEM_BONUS_ROLL","LOOT_ITEM_SELF_MULTIPLE","LOOT_ITEM_PUSHED_SELF_MULTIPLE","LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE","LOOT_ITEM_SELF","LOOT_ITEM_PUSHED_SELF","LOOT_ITEM_BONUS_ROLL_SELF"}) do _G[g] = "%s receives loot: %s." end
UNITNAME_TITLE_PET = "%s's Pet"
UNITNAME_TITLE_COMPANION = "%s's Companion"
UNITNAME_TITLE_GUARDIAN = "%s's Guardian"
UNITNAME_TITLE_MINION = "%s's Minion"
UNITNAME_TITLE_CHARM = "%s's Charm"
UNITNAME_TITLE_CREATION = "%s's Creation"
PET_TYPE_PET = "Pet"
PET_TYPE_DEMON = "Demon"
Enum = { DamageMeterSessionType = { Overall = 0, Current = 1 }, TooltipDataType = { Unit = 2, Item = 0 } }
ScenarioChallengeModeAffixMixin = {}
TooltipDataProcessor = { AddTooltipPostCall = noop }
DeathRecap_GetEvents = function() return nil end

-- Your character's progress (RunStats.lua): tests move these.
M.xp, M.xpMax, M.level, M.money = 1000, 5000, 14, 12345
UnitXP = function() return M.xp end
UnitXPMax = function() return M.xpMax end
GetMoney = function() return M.money end
M.quests = {}   -- { { title, id, done } }
GetNumQuestLogEntries = function() return #M.quests end
GetQuestLogTitle = function(i) local q = M.quests[i]; if q then return q.title, 20, nil, false, false, q.done and 1 or nil, nil, q.id end end
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
COMBATLOG_XPGAIN_FIRSTPERSON_GROUP = "%s dies, you gain %d experience. (+%d group bonus)"
COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)"
FACTION_STANDING_INCREASED = "Your %s reputation has increased by %d."

C_Map = { GetBestMapForUnit = function() return 1 end }
C_NamePlate = { GetNamePlates = function() return {} end }
C_TooltipInfo = { GetHyperlink = function() return nil end }
C_Item = { GetItemInfo = function() return nil end, GetItemQualityByID = function() return 3 end,
           GetItemIconByID = function() return 135274 end }
ITEM_QUALITY_COLORS = { [2] = { r = 0.1, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 }, [4] = { r = 0.64, g = 0.21, b = 0.93 } }
C_PaperDollInfo = { GetInspectItemLevel = function() return 0 end }
C_PlayerInfo = { GetDisplayID = function() return 0 end }
C_ChatInfo = { RegisterAddonMessagePrefix = noop, SendAddonMessage = noop }
C_Scenario = { GetStepInfo = function() return "", "", 0 end }
C_ScenarioInfo = { GetCriteriaInfo = function() return nil end }
C_ChallengeMode = nil   -- set per test for retail M+ paths
C_MythicPlus = nil
EJ_GetInstanceForMap = function() return 0 end
EJ_SelectInstance = noop
EJ_SelectTier = noop
EJ_GetNumTiers = function() return 0 end
EJ_GetCurrentTier = function() return 0 end
EJ_GetInstanceByIndex = function() return nil end
EJ_GetEncounterInfoByIndex = function() return nil end
EJ_GetCreatureInfo = function() return nil end

-- Damage meter: tests fill M.meter[type] = { duration=, combatSources={...} }
M.meter = {}
C_DamageMeter = {
    IsDamageMeterAvailable = function() return true end,
    GetCombatSessionFromType = function(_, t) return M.meter[t] end,
    -- M.sessions: list of { sessionID, name, data = { [type] = session } }
    GetAvailableCombatSessions = function()
        local out = {}
        for _, s in ipairs(M.sessions or {}) do out[#out + 1] = { sessionID = s.sessionID, name = s.name } end
        return out
    end,
    GetCombatSessionFromID = function(id, t)
        for _, s in ipairs(M.sessions or {}) do
            if s.sessionID == id then return s.data[t] or { combatSources = {} } end
        end
    end,
    ResetAllCombatSessions = function() M.meterResets = (M.meterResets or 0) + 1 end,
}

-- ── Loading ────────────────────────────────────────────────────────────────
-- Unknown globals raise, so a missing local is caught at the line that uses it.
local allowed = {}
setmetatable(_G, {
    __index = function(_, k)
        if allowed[k] then return nil end
        error("undefined global '" .. tostring(k) .. "'", 2)
    end,
})
-- Globals the addon reads but which legitimately may be nil.
for _, k in ipairs({ "MythicScoreboardDB", "MythicScoreboardPortraitsDB", "MythicScoreboardAccountDB", "ForeverDungeonJournal_NS",
                     "SLASH_MYTHICSCOREBOARD1", "SLASH_MYTHICSCOREBOARD2", "SlashCmdList",
                     "EncounterJournal", "C_ChallengeMode", "C_MythicPlus", "MythicScoreboardFrame", "MythicScoreboard" }) do
    allowed[k] = true
end
SlashCmdList = {}

function M.LoadTOC(dir, toc)
    local files = {}
    for line in io.lines(dir .. "/" .. toc) do
        line = line:gsub("\r", "")
        if line ~= "" and not line:find("^##") then files[#files + 1] = (line:gsub("\\", "/")) end
    end
    for _, f in ipairs(files) do
        local chunk, err = loadfile(dir .. "/" .. f)
        if not chunk then error("load " .. f .. ": " .. err) end
        local ok, e = pcall(chunk, "MythicScoreboard", {})
        if not ok then error("run " .. f .. ": " .. tostring(e)) end
    end
    return files
end

return M

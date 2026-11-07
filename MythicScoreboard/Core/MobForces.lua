-- Per-mob enemy forces % for M+ nameplates and tooltips.
--
-- GetUnitCriteriaProgressValues returns Secret Values (WoW 12.0+): they can't
-- be compared or used in Lua string ops. Pass them straight to C widget calls
-- (SetFormattedText, AddDoubleLine); wrap in pcall to swallow nil on bosses.

local MS = _G["MythicScoreboard"]
local L = MS.L

-- No Mythic+ (WoW Forever): nothing to show, so no tooltip hook or events.
if not MS.Flavor.mythicPlus then return end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function IsInMythicPlus()
    return select(3, GetInstanceInfo()) == MS.MYTHIC_PLUS
end

local function IsTooltipEnabled() return MS:GetMobForcesTooltip() end
local function IsNameplateEnabled() return MS:GetMobForcesNameplate() end

-- ── Tooltip ───────────────────────────────────────────────────────────────────

local function AddForcesToTooltip(tooltip, tooltipData)
    if not IsTooltipEnabled() then return end
    if not IsInMythicPlus() then return end
    if not (C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues) then return end

    -- tooltip:GetUnit() is tainted in M+ (C_DamageMeter side-effect).
    -- Use "mouseover" — a literal string, always clean.
    if not UnitExists("mouseover") then return end
    if not UnitCanAttack("player", "mouseover") then return end

    -- Call API with the literal "mouseover" token — no taint
    local count, countPercent, countPercentString =
        C_ScenarioInfo.GetUnitCriteriaProgressValues("mouseover")

    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(L["Enemy Forces"], " ", 0.67, 0.67, 0.67, 0.00, 0.78, 1.00)

    local n = tooltip:NumLines()
    local rightFS = _G["GameTooltipTextRight" .. n]
    if rightFS then
        local ok = pcall(rightFS.SetFormattedText, rightFS, "%s%%", countPercentString)
        if ok then
            rightFS:SetTextColor(0.00, 0.78, 1.00, 1)
            tooltip:Show()
        end
    end
end

local function HookTooltip()
    -- OnTooltipSetUnit was removed in Midnight; AddTooltipPostCall is the replacement.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.Unit, AddForcesToTooltip)
    end
end

-- ── Nameplates ────────────────────────────────────────────────────────────────

-- One label per nameplate frame, kept on the frame. Blizzard reuses its
-- nameplate frames, so a label made once serves every mob that plate shows;
-- making one per appearance would pile up (the game never frees them).
-- Labels are only made in a Mythic+ key, and nameplates are only watched there.
local nameplateLabels = {}      -- unit token -> label currently showing for it
local FONT_PATH = "Fonts\\FRIZQT__.TTF"
local LABEL_KEY = "MythicScoreboardForces"

local function GetOrCreateLabel(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return nil end
    local lbl = nameplate[LABEL_KEY]
    if not lbl then
        lbl = nameplate:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT_PATH, 14, "OUTLINE")
        lbl:SetTextColor(1.00, 1.00, 1.00, 1)
        lbl:SetPoint("BOTTOM", nameplate, "TOP", 0, 2)
        lbl:SetJustifyH("CENTER")
        nameplate[LABEL_KEY] = lbl
    end
    lbl:SetText("")
    return lbl
end

local function ClearNameplateLabel(unit)
    local lbl = nameplateLabels[unit]
    if lbl then lbl:SetText("") end
    nameplateLabels[unit] = nil
end

local function UpdateNameplateLabel(unit)
    if not unit or not UnitExists(unit) then return end
    if not IsNameplateEnabled() or not IsInMythicPlus() then return ClearNameplateLabel(unit) end
    if not UnitCanAttack("player", unit) then return ClearNameplateLabel(unit) end
    if not (C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues) then return end

    local lbl = GetOrCreateLabel(unit)
    if not lbl then return end
    nameplateLabels[unit] = lbl

    -- Secret Value: pass straight to C, no Lua ops on it. pcall catches a
    -- nil countPercentString (bosses, mobs worth no forces).
    local _, _, countPercentString = C_ScenarioInfo.GetUnitCriteriaProgressValues(unit)
    local ok = pcall(lbl.SetFormattedText, lbl, "%s%%", countPercentString)
    if not ok then lbl:SetText("") end
end

local function ClearAll()
    for _, lbl in pairs(nameplateLabels) do lbl:SetText("") end
    wipe(nameplateLabels)
end

local function RefreshAllNameplates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then UpdateNameplateLabel(unit) end
    end
end

-- ── Event frame ───────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHALLENGE_MODE_START")
frame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")

-- Nameplates are watched only inside a key.
local watching = false
local function Watch()
    local want = IsInMythicPlus()
    if want == watching then return end
    watching = want
    if want then
        frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        RefreshAllNameplates()
    else
        frame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
        frame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
        ClearAll()
    end
end

frame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        UpdateNameplateLabel(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        ClearNameplateLabel(unit)
    elseif event == "SCENARIO_CRITERIA_UPDATE" then
        if watching and IsNameplateEnabled() then RefreshAllNameplates() end
    else
        -- Zone change or key start: nameplate tokens are reused across zones.
        ClearAll()
        watching = nil
        Watch()
    end
end)

HookTooltip()

-- Turning the nameplate labels on or off (Settings.lua) shows or clears them.
MS:OnSettingChanged("showMobForcesNameplates", function(on)
    if on then RefreshAllNameplates() else ClearAll() end
end)

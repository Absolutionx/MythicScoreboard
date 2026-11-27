-- Tooltips the scoreboard shares: keeping one up while the mouse stays on
-- its owner, and what a run did for your character (Forever).

local _fmt = string.format
local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
local P, Swatch = UI.P, UI.Swatch

-- ===========================================================================
-- Tooltip guard
-- ===========================================================================
-- If a tooltip owned by something in the scoreboard window disappears while
-- the mouse is still over that thing, show it again. Whatever closes it
-- (a refresh, the game, another addon), hovering keeps it up. Stops as soon
-- as the mouse moves off, the frame hides, or its OnEnter shows nothing.

local function InScoreboard(f)
    local root = UI.frame
    for _ = 1, 12 do
        if not f then return false end
        if f == root then return true end
        f = f.GetParent and f:GetParent()
    end
    return false
end

local guard = CreateFrame("Frame")
guard:Hide()
guard:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.15 then return end
    self.t = 0
    local owner = self.owner
    if not (owner and owner:IsVisible() and owner:IsMouseOver()) then
        self.owner = nil; self:Hide(); return
    end
    if GameTooltip:IsShown() and GameTooltip:IsOwned(owner) then return end
    local onEnter = owner:GetScript("OnEnter")
    if not onEnter then self.owner = nil; self:Hide(); return end
    pcall(onEnter, owner)
    -- OnEnter chose not to show a tooltip (e.g. a menu is open): stop.
    if not (GameTooltip:IsShown() and GameTooltip:IsOwned(owner)) then
        self.owner = nil; self:Hide()
    end
end)

if GameTooltip and GameTooltip.SetOwner and hooksecurefunc then
    -- Runs for every tooltip in the game: nothing to do unless our window is up.
    hooksecurefunc(GameTooltip, "SetOwner", function(_, owner)
        local root = UI.frame
        if not (root and root:IsShown()) then
            if guard.owner then guard.owner = nil; guard:Hide() end
            return
        end
        if owner and InScoreboard(owner) then
            guard.owner, guard.t = owner, 0
            guard:Show()
        else
            guard.owner = nil; guard:Hide()
        end
    end)
end

-- ===========================================================================
-- Progress (Forever)
-- ===========================================================================
-- A run's XP: (from the dungeon, from quests). Live runs and archive
-- summaries keep it the same way.
function UI.RunXP(prog)
    if not prog then return 0, 0 end
    return math.max(0, prog.xp or 0), math.max(0, prog.qx or 0)
end

-- What a run did for your character, as tooltip lines. prog: a live run's
-- run.progress, or (fromArchive) an archive entry's e.prog.
function UI.AddProgressLines(prog, fromArchive)
    if not prog then return end
    local mobXP, questXP = UI.RunXP(prog)
    local levels = (fromArchive and prog.lv or prog.levels) or 0
    local kills  = (fromArchive and prog.k or prog.kills) or 0
    local quests = fromArchive and (prog.q or 0) or #(prog.quests or {})
    local gold   = math.max(0, (fromArchive and prog.g or prog.gold) or 0)
    local a, b, c = P.ash[1], P.ash[2], P.ash[3]
    GameTooltip:AddDoubleLine(L["Experience"], MS.FormatThousands(mobXP + questXP)
        .. (levels > 0 and ("  (" .. MS.Plural(levels, "+%d level", "+%d levels") .. ")") or ""), a, b, c, 1, 1, 1)
    if questXP > 0 then
        GameTooltip:AddLine(UI.XPSplit(mobXP, questXP, 200, 6))
        GameTooltip:AddDoubleLine("   " .. Swatch(P.xpMob, 8, 8) .. " " .. L["From the dungeon"],
            MS.FormatThousands(mobXP), a, b, c, 1, 1, 1)
        GameTooltip:AddDoubleLine("   " .. Swatch(P.xpQuest, 8, 8) .. " " .. L["From quests"],
            MS.FormatThousands(questXP), a, b, c, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(L["Mobs killed"], kills, a, b, c, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Quests completed"], quests, a, b, c, 1, 1, 1)
    if not fromArchive then
        local rewards = prog.questRewards or {}
        for i, t in ipairs(prog.quests or {}) do
            local r = rewards[i]
            local x = r and r.x
            GameTooltip:AddDoubleLine("   " .. t, x and _fmt(L["+%s XP"], MS.FormatThousands(x)) or "",
                0.8, 0.8, 0.8, P.xpQuest[1], P.xpQuest[2], P.xpQuest[3])
        end
    end
    local br, bg, bb = P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3]
    GameTooltip:AddDoubleLine(L["Gold looted"], MS.FormatGold(gold), a, b, c, br, bg, bb)
    local qg = prog.qg                       -- (the same key in live runs and archive entries)
    if (qg or 0) > 0 then
        GameTooltip:AddDoubleLine("   " .. L["From quests"], MS.FormatGold(qg), a, b, c, br, bg, bb)
    end
    local reps = {}
    for f, n in pairs(prog.rep or {}) do reps[#reps + 1] = { f = f, n = n } end
    table.sort(reps, function(x, y) return x.n > y.n end)
    for _, r in ipairs(reps) do
        GameTooltip:AddDoubleLine(r.f, _fmt(L["+%s reputation"], MS.FormatThousands(r.n)),
            a, b, c, P.verdHi[1], P.verdHi[2], P.verdHi[3])
    end
end

-- ===========================================================================
-- The addon's look on the game tooltip
-- ===========================================================================
-- While one of the addon's frames owns the game tooltip, it wears the
-- scoreboard's stone and bronze and its fonts. For anything else it's left
-- exactly as the game draws it: the look comes off as soon as another owner
-- takes the tooltip, or it hides.

-- The addon's frames all carry its name ("MythicScoreboardFrame",
-- "MythicScoreboardCompact", ...); anything inside one is ours.
local function Ours(f)
    for _ = 1, 25 do
        if not f then return false end
        local n = f.GetName and f:GetName()
        if type(n) == "string" and n:find("^MythicScoreboard") then return true end
        f = f.GetParent and f:GetParent()
    end
    return false
end

local skin, worn, fonts = nil, false, {}

local function BuildSkin(tip)
    local list = {}
    local function Add(t) list[#list + 1] = t; t:Hide(); return t end
    local c = P.bronzeDk
    Add(UI.Solid(tip, "BACKGROUND", -7, 0, 0, 0, 1)):SetAllPoints()
    local inner = Add(UI.Solid(tip, "BACKGROUND", -6, c[1], c[2], c[3], 1))
    inner:SetPoint("TOPLEFT", 1, -1); inner:SetPoint("BOTTOMRIGHT", -1, 1)
    local body = Add(tip:CreateTexture(nil, "BACKGROUND", nil, -5))
    body:SetPoint("TOPLEFT", 2, -2); body:SetPoint("BOTTOMRIGHT", -2, 2)
    UI.VGrad(body, P.stoneBot, P.stoneTop)
    local grain = Add(UI.Art(tip, "Grain", "BACKGROUND", -4, true))
    grain:SetPoint("TOPLEFT", 2, -2); grain:SetPoint("BOTTOMRIGHT", -2, 2)
    grain:SetBlendMode("ADD"); grain:SetAlpha(0.5)
    local tl = Add(tip:CreateTexture(nil, "BACKGROUND", nil, -3))
    tl:SetPoint("TOPLEFT", 2, -2); tl:SetPoint("BOTTOMRIGHT", tip, "TOP", 0, -3)
    UI.HGrad(tl, P.bronze, P.bronzeHi, 0, 0.9)
    local tr = Add(tip:CreateTexture(nil, "BACKGROUND", nil, -3))
    tr:SetPoint("TOPRIGHT", -2, -2); tr:SetPoint("BOTTOMLEFT", tip, "TOP", 0, -3)
    UI.HGrad(tr, P.bronzeHi, P.bronze, 0.9, 0)
    return list
end

local function Frame9(tip) return tip.NineSlice end

local function Wear(tip)
    skin = skin or BuildSkin(tip)
    for _, t in ipairs(skin) do t:Show() end
    local ns = Frame9(tip)
    if ns then ns:SetAlpha(0) end
    worn = true
end

local function RestoreFonts()
    for fs, f in pairs(fonts) do
        fs:SetFont(f[1], f[2], f[3])
        fs._msKind = nil
    end
    fonts = {}
end

local function TakeOff(tip)
    if not worn then return end
    for _, t in ipairs(skin or {}) do t:Hide() end
    local ns = Frame9(tip)
    if ns then ns:SetAlpha(1) end
    RestoreFonts()
    worn = false
end

-- The addon's fonts on each line: the first in semibold, the rest medium.
local function FontLines(tip)
    local name = tip:GetName()
    if not name then return end
    for i = 1, tip:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G[name .. "Text" .. side .. i]
            if fs then
                if not fonts[fs] then
                    local path, size, flags = fs:GetFont()
                    if path then fonts[fs] = { path, size, flags } end
                end
                UI.SetFont(fs, i == 1 and "semibold" or "medium", i == 1 and 15 or 13)
            end
        end
    end
end

local relayout = false
local function Hook(tip)
    if not (tip and hooksecurefunc) then return end
    hooksecurefunc(tip, "SetOwner", function(self, owner)
        if Ours(owner) then Wear(self) else TakeOff(self) end
    end)
    hooksecurefunc(tip, "Show", function(self)
        if not worn or relayout then return end
        FontLines(self)
        relayout = true
        self:Show()                      -- once more, so it sizes to the new fonts
        relayout = false
    end)
    tip:HookScript("OnHide", function(self) TakeOff(self) end)
end
Hook(GameTooltip)
UI._TooltipSkin = { Ours = Ours, IsWorn = function() return worn end }   -- for tests

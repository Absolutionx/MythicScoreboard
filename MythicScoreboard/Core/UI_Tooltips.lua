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
        GameTooltip:AddDoubleLine("   " .. Swatch(P.xpMob, 8, 8) .. " " .. L["From the dungeon"], MS.FormatThousands(mobXP), a, b, c, 1, 1, 1)
        GameTooltip:AddDoubleLine("   " .. Swatch(P.xpQuest, 8, 8) .. " " .. L["From quests"], MS.FormatThousands(questXP), a, b, c, 1, 1, 1)
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
    GameTooltip:AddDoubleLine(L["Gold looted"], MS.FormatGold(gold), a, b, c, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
    local qg = (fromArchive and prog.qg) or prog.qg
    if (qg or 0) > 0 then
        GameTooltip:AddDoubleLine("   " .. L["From quests"], MS.FormatGold(qg), a, b, c, P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3])
    end
    local reps = {}
    for f, n in pairs(prog.rep or {}) do reps[#reps + 1] = { f = f, n = n } end
    table.sort(reps, function(x, y) return x.n > y.n end)
    for _, r in ipairs(reps) do
        GameTooltip:AddDoubleLine(r.f, _fmt(L["+%s reputation"], MS.FormatThousands(r.n)), a, b, c, P.verdHi[1], P.verdHi[2], P.verdHi[3])
    end
end

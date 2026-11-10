local _ceil   = math.ceil
local _floor  = math.floor
local _max    = math.max
local _min    = math.min
local _fmt    = string.format

local MS = _G["MythicScoreboard"]
local L = MS.L
local LK = MS.LK      -- a label kept in English, translated where it is shown

MS.UI = MS.UI or {}
local UI = MS.UI


-- ===========================================================================
-- Design tokens
-- ===========================================================================
-- Stone & bronze: warm basalt base, bronze structure, ivory text,
-- weathered olive for good outcomes, blood for deaths and wipes.

local MEDIA = "Interface\\AddOns\\MythicScoreboard\\Media\\"

-- Boss kill bars stay bright: they are the lit highlights on the stone.
local FIGHT_BOT, FIGHT_TOP = {0.49, 0.32, 0.15}, {0.94, 0.78, 0.54}
local WIPE_BOT,  WIPE_TOP  = {0.40, 0.09, 0.08}, {0.78, 0.27, 0.24}

local P = {
    ivory    = {0.93, 0.89, 0.81},
    ash      = {0.55, 0.51, 0.45},
    ash2     = {0.37, 0.34, 0.31},
    bronze   = {0.75, 0.54, 0.29},
    bronzeHi = {0.91, 0.72, 0.47},
    gold     = {1.00, 0.82, 0.30},   -- a +3 key
    xpMob    = {0.61, 0.46, 0.87},   -- XP from the dungeon (the game's XP bar)
    xpQuest  = {1.00, 0.82, 0.00},   -- XP from quests (the game's quest colour)
    bronzeDk = {0.29, 0.23, 0.16},
    line     = {0.227, 0.188, 0.157},
    verd     = {0.60, 0.68, 0.42},   -- weathered olive: good outcomes
    verdHi   = {0.74, 0.80, 0.55},
    blood    = {0.81, 0.25, 0.22},
    bloodHi  = {0.90, 0.44, 0.41},
    stoneTop = {0.114, 0.098, 0.082},
    stoneBot = {0.071, 0.059, 0.051},
    btnTop   = {0.150, 0.125, 0.106},
    btnBot   = {0.100, 0.086, 0.071},
    dmg      = {0.73, 0.68, 0.61},
    avoid    = {0.85, 0.54, 0.23},
    kick     = {0.50, 0.77, 0.86},
    dark     = {0.10, 0.07, 0.04},
}

local CLASS_COLORS = {
    WARRIOR     = { r=0.78, g=0.61, b=0.43 },
    PALADIN     = { r=0.96, g=0.55, b=0.73 },
    HUNTER      = { r=0.67, g=0.83, b=0.45 },
    ROGUE       = { r=1.00, g=0.96, b=0.41 },
    PRIEST      = { r=1.00, g=1.00, b=1.00 },
    DEATHKNIGHT = { r=0.77, g=0.12, b=0.23 },
    SHAMAN      = { r=0.00, g=0.44, b=0.87 },
    MAGE        = { r=0.41, g=0.80, b=0.94 },
    WARLOCK     = { r=0.58, g=0.51, b=0.79 },
    MONK        = { r=0.00, g=1.00, b=0.59 },
    DRUID       = { r=1.00, g=0.49, b=0.04 },
    DEMONHUNTER = { r=0.64, g=0.19, b=0.79 },
    EVOKER      = { r=0.20, g=0.58, b=0.50 },
    UNKNOWN     = { r=0.70, g=0.70, b=0.70 },
}

local CLASS_ICON_COORDS = {
    WARRIOR     = {0.00, 0.25, 0.00, 0.25},
    MAGE        = {0.25, 0.50, 0.00, 0.25},
    ROGUE       = {0.50, 0.75, 0.00, 0.25},
    DRUID       = {0.75, 1.00, 0.00, 0.25},
    HUNTER      = {0.00, 0.25, 0.25, 0.50},
    SHAMAN      = {0.25, 0.50, 0.25, 0.50},
    PRIEST      = {0.50, 0.75, 0.25, 0.50},
    WARLOCK     = {0.75, 1.00, 0.25, 0.50},
    PALADIN     = {0.00, 0.25, 0.50, 0.75},
    DEATHKNIGHT = {0.25, 0.50, 0.50, 0.75},
    MONK        = {0.50, 0.75, 0.50, 0.75},
    DEMONHUNTER = {0.75, 1.00, 0.50, 0.75},
    EVOKER      = {0.00, 0.25, 0.75, 1.00},
    UNKNOWN     = {0.75, 1.00, 0.75, 1.00},
}

local ROLE_ICON_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_ICON_COORDS = {
    TANK    = {0/64,  19/64, 22/64, 41/64},
    HEALER  = {20/64, 39/64, 1/64,  20/64},
    DAMAGER = {20/64, 39/64, 22/64, 41/64},
}

-- Geometry
local FRAME_W   = 1154   -- 1058 before the Damage column
local HDR_H     = 86
local COL_HDR_H = 30
local ROW_H     = 46
local MAX_ROWS  = 5
local TL_H      = 218
local FRAME_H   = HDR_H + COL_HDR_H + ROW_H * MAX_ROWS + TL_H + 2
local PAD_X     = 22

local COLS = {
    { key="player",     label=LK("Player"),       w=190, left=true },
    { key="loot",       label=LK("Loot"),         w=108, left=true },
    -- num="int":  whole numbers, right-aligned on an anchor that centres a
    --             full-width value (digits wide) under the header.
    -- num="abbr": 12.3K style, aligned on the decimal point; the suffix sits
    --             in its own slot after it.
    { key="score",      label=LK("Rating"),       w=68,  num="int", digits=4 },
    { key="deaths",     label=LK("Deaths"),       w=60,  num="int", digits=2 },
    { key="dmgTaken",   label=LK("Damage taken"), w=100, num="abbr" },
    { key="avoidable",  label=LK("Avoidable"),    w=84,  num="abbr" },
    { key="damage",     label=LK("Damage"),       w=88,  num="abbr" },
    { key="dps",        label=LK("DPS"),          w=86,  num="abbr", strong=true },
    { key="healing",    label=LK("Healing"),      w=88,  num="abbr" },
    { key="hps",        label=LK("HPS"),          w=84,  num="abbr", strong=true },
    { key="interrupts", label=LK("Interrupts"),   w=80,  num="int", digits=2 },
    { key="dispels",    label=LK("Dispels"),      w=66,  num="int", digits=2 },
}
local CELL_FONT_SIZE = 16

-- Dungeons with level ranges (Forever): the Rating column shows level instead.
if MS.Flavor.dungeonLevels then
    for i, c in ipairs(COLS) do
        if c.key == "score" then
            COLS[i] = { key="level", label=LK("Level"), w=c.w, num="int", digits=2 }
        end
    end
end

-- ===========================================================================
-- Primitive helpers
-- ===========================================================================

local _FONT_PATH = GameFontNormal:GetFont()

-- The addon's fonts only cover Latin script. On a Russian, Korean or Chinese
-- client every piece of text uses the game's own font instead.
-- (MS.Locale is the language shown: settled when the addon has loaded, and
-- every piece of text is created after that.)
local LOCALE_SCRIPT = { ruRU = "cyrillic", koKR = "hangul", zhCN = "han", zhTW = "han" }
local function ShownScript() return LOCALE_SCRIPT[MS.Locale or "enUS"] end

-- On a Latin client, a name in another script (a Russian player in the group)
-- is shown in the game font that has those letters. Found by the UTF-8 lead
-- byte: D0-D3 Cyrillic, EA-ED Hangul, E4-E9 Chinese characters.
-- (The game's own name-font globals when it has them.)
local function GameFont(global, default)
    local v = rawget(_G, global)
    return (type(v) == "string" and v ~= "") and v or default
end
local SCRIPT_FONTS = {
    cyrillic = GameFont("UNIT_NAME_FONT_CYRILLIC", "Fonts\\FRIZQT___CYR.TTF"),
    hangul   = GameFont("UNIT_NAME_FONT_KOREAN",   "Fonts\\2002.TTF"),
    han      = GameFont("UNIT_NAME_FONT_CHINESE",  "Fonts\\ARKai_T.ttf"),
}
local function ScriptOf(text)
    if type(text) ~= "string" or not text:find("[\208-\237]") then return nil end
    for i = 1, #text do
        local b = text:byte(i)
        if b >= 0xD0 and b <= 0xD3 then return "cyrillic" end
        if b >= 0xEA and b <= 0xED then return "hangul" end
        if b >= 0xE4 and b <= 0xE9 then return "han" end
    end
end

local FONTS = {
    title    = MEDIA .. "Fonts\\Cinzel-Bold.ttf",
    regular  = MEDIA .. "Fonts\\BarlowSemiCondensed-Regular.ttf",
    medium   = MEDIA .. "Fonts\\BarlowSemiCondensed-Medium.ttf",
    semibold = MEDIA .. "Fonts\\BarlowSemiCondensed-SemiBold.ttf",
}

local function SetFont(fs, kind, size, flags, script)
    flags = flags or ""
    local path = (kind == "game") and _FONT_PATH or FONTS[kind] or _FONT_PATH
    local shown = ShownScript()
    if shown then
        -- The game font has these letters in that language's own client; a
        -- preview (/sb lang) on another client takes the font that has them.
        path = (MS.Locale == MS.ClientLocale) and _FONT_PATH or SCRIPT_FONTS[shown] or _FONT_PATH
    end
    if script then path = SCRIPT_FONTS[script] or _FONT_PATH end
    fs._msKind, fs._msSize, fs._msFlags, fs._msScript = kind, size, flags, script
    local ok = fs:SetFont(path, size, flags)
    if ok == false or not fs:GetFont() then
        fs:SetFont(_FONT_PATH, size, flags)
    end
end

-- SetText for text that may hold a name in another script: switches the
-- font when the script changes, and back again for the next name.
local function SetNameText(fs, text)
    local script = (not ShownScript()) and ScriptOf(text) or nil
    if script ~= fs._msScript and fs._msKind then
        SetFont(fs, fs._msKind, fs._msSize, fs._msFlags, script)
    end
    fs:SetText(text)
end

local function Text(parent, kind, size, col, justify, flags, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    SetFont(fs, kind, size, flags)
    col = col or P.ivory
    fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Splits 135214 into "135", ".2", "K" so values align on the decimal point.
local function SplitAbbrev(n)
    n = n or 0
    local units = { {1e9, "B"}, {1e6, "M"}, {1e3, "K"} }
    for i, u in ipairs(units) do
        if n >= u[1] then
            local s = _fmt("%.1f", n / u[1])
            if s == "1000.0" and i > 1 then           -- 999.96K rounds up: show 1.0M
                s, u = _fmt("%.1f", n / units[i - 1][1]), units[i - 1]
            end
            local int, dec = s:match("^(%d+)%.(%d)$")
            return int, "." .. dec, u[2]
        end
    end
    return tostring(_floor(n)), "", ""
end

-- Measures the real font once and places every numeric column's anchor.
local function ComputeColumnAnchors()
    if COLS._anchored then return end
    local m = UIParent:CreateFontString(nil, "OVERLAY")
    local x = PAD_X - 2
    for _, c in ipairs(COLS) do
        c.x, c.cx = x, x + c.w / 2
        if c.num then
            SetFont(m, c.strong and "semibold" or "medium", CELL_FONT_SIZE)
            if c.num == "int" then
                m:SetText(string.rep("0", c.digits))
                c.anchor = _floor(c.cx + m:GetStringWidth() / 2 + 0.5)
            else
                m:SetText("000");  local wi = m:GetStringWidth()
                m:SetText(".0M");  local wt = m:GetStringWidth()
                m:SetText(".0K");  c.kW = _ceil(m:GetStringWidth())
                c.tailW  = _ceil(wt)
                c.anchor = _floor(c.cx + (wi - wt) / 2 + 0.5)
            end
        end
        x = x + c.w
    end
    m:Hide()
    COLS._anchored = true
end

local function Solid(parent, layer, sub, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- Gradients reuse two colour objects: SetGradient reads the values when it's
-- called, and making new ones each time (every row, every redraw) is garbage.
local _gc1, _gc2 = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)
local function Fill(c, col, a)
    local r, g, b = col[1], col[2], col[3]
    if c.SetRGBA then c:SetRGBA(r, g, b, a or 1) else c.r, c.g, c.b, c.a = r, g, b, a or 1 end
    return c
end

-- Vertical gradient: first colour is the bottom, second the top.
local function VGrad(t, bot, top, aBot, aTop)
    t:SetColorTexture(1, 1, 1, 1)
    t:SetGradient("VERTICAL", Fill(_gc1, bot, aBot), Fill(_gc2, top, aTop))
end

-- Horizontal gradient: first colour is the left, second the right.
local function HGrad(t, left, right, aL, aR)
    t:SetColorTexture(1, 1, 1, 1)
    t:SetGradient("HORIZONTAL", Fill(_gc1, left, aL), Fill(_gc2, right, aR))
end

-- Tiled textures repeat on the GPU via texture coordinates worked out from
-- their size. The client's own SetHorizTile/SetVertTile recalculates on every
-- move, which made dragging the window drop to single-digit FPS.
local TILE_PX = { Grain = 256, Grit = 128, Hatch = 16 }

local function Retile(t)
    local w, h = t:GetSize()
    if w and h and w > 0 and h > 0 then
        t:SetTexCoord(0, w / t._tilePx, 0, h / t._tilePx)
    end
end

local function WatchTiles(parent, t)
    local list = parent._tiles
    if not list then
        list = {}
        parent._tiles = list
        -- Anchored (not sized) tiles only know their size after layout.
        local function All() for i = 1, #list do Retile(list[i]) end end
        parent:HookScript("OnSizeChanged", All)
        parent:HookScript("OnShow", All)
        C_Timer.After(0, All)
    end
    list[#list + 1] = t
end

local function Art(parent, file, layer, sub, tile)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    if tile then
        t:SetTexture(MEDIA .. file, "REPEAT", "REPEAT")
        t._tilePx = TILE_PX[file] or 64
        local setSize, setW, setH = t.SetSize, t.SetWidth, t.SetHeight
        t.SetSize   = function(self, w, h) setSize(self, w, h); Retile(self) end
        t.SetWidth  = function(self, w) setW(self, w); Retile(self) end
        t.SetHeight = function(self, h) setH(self, h); Retile(self) end
        WatchTiles(parent, t)
    else
        t:SetTexture(MEDIA .. file)
    end
    return t
end

local function Btn(parent)
    local b = CreateFrame("Button", nil, parent)
    b:EnableMouse(true)
    return b
end

local function Tint(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or 1) end

-- 1px outline made of four textures (inside the frame bounds).
local function Outline(f, c, a, layer, sub)
    local o = {}
    for i = 1, 4 do o[i] = Solid(f, layer or "BORDER", sub or 0, c[1], c[2], c[3], a or 1) end
    o[1]:SetPoint("TOPLEFT");    o[1]:SetPoint("TOPRIGHT");    o[1]:SetHeight(1)
    o[2]:SetPoint("BOTTOMLEFT"); o[2]:SetPoint("BOTTOMRIGHT"); o[2]:SetHeight(1)
    o[3]:SetPoint("TOPLEFT");    o[3]:SetPoint("BOTTOMLEFT");  o[3]:SetWidth(1)
    o[4]:SetPoint("TOPRIGHT");   o[4]:SetPoint("BOTTOMRIGHT"); o[4]:SetWidth(1)
    o.SetColor = function(_, cc, aa)
        for i = 1, 4 do o[i]:SetColorTexture(cc[1], cc[2], cc[3], aa or 1) end
    end
    o.SetShown = function(_, s) for i = 1, 4 do o[i]:SetShown(s) end end
    return o
end

-- Bevelled box used by buttons, dropdowns and popups.
local function Box(f, hoverable)
    local fill = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
    VGrad(fill, P.btnBot, P.btnTop)
    f._fill = fill
    f._outline = Outline(f, P.line, 1, "BACKGROUND", 2)
    local hi = Solid(f, "BORDER", 0, 1, 0.92, 0.80, 0.05)
    hi:SetPoint("TOPLEFT", 1, -1); hi:SetPoint("TOPRIGHT", -1, -1); hi:SetHeight(1)
    if hoverable then
        f:HookScript("OnEnter", function() f._outline:SetColor(P.bronze, 0.9) end)
        f:HookScript("OnLeave", function() f._outline:SetColor(P.line, 1) end)
    end
    return f
end

local DN = function(n) return MS.DisplayName and MS.DisplayName(n) or n end

local function Hex(c) return _fmt("%02x%02x%02x", _floor(c[1]*255), _floor(c[2]*255), _floor(c[3]*255)) end
local function CT(c, s) return "|cff" .. Hex(c) .. s .. "|r" end

local function ClassColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    local fb = CLASS_COLORS[class] or CLASS_COLORS["UNKNOWN"]
    return fb.r, fb.g, fb.b
end

local function ClassHex(class)
    local r, g, b = ClassColor(class)
    return _fmt("%02x%02x%02x", _floor(r*255), _floor(g*255), _floor(b*255))
end

local function GetRole(p)
    if p.role and p.role ~= "" then return p.role end
    if (p.healingDone or 0) > (p.damageDone or 0) then return "HEALER" end
    return "DAMAGER"
end

local function Abbrev(n)
    n = n or 0
    if     n >= 1e9 then return _fmt("%.1f", n / 1e9) .. L["B"]
    elseif n >= 1e6 then return _fmt("%.1f", n / 1e6) .. L["M"]
    elseif n >= 1e3 then return _fmt("%.1f", n / 1e3) .. L["K"]
    else                 return tostring(_floor(n))
    end
end

local SCORE_TIERS = {
    { 3000, 1.00, 0.50, 0.00 },
    { 2500, 0.64, 0.21, 0.93 },
    { 2000, 0.00, 0.71, 1.00 },
    { 1500, 0.00, 0.78, 0.44 },
    { 1000, 1.00, 0.85, 0.00 },
    {  600, 0.80, 0.80, 0.80 },
    {    0, 0.74, 0.49, 0.22 },
}

local function ScoreColor(score)
    score = score or 0
    -- Overall season rating (GetSpecificDungeon... is for one dungeon's
    -- score, a much smaller number, and painted every rating orange).
    if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
        local ok, col = pcall(C_ChallengeMode.GetDungeonScoreRarityColor, score)
        if ok and col then return col.r, col.g, col.b end
    end
    for _, t in ipairs(SCORE_TIERS) do
        if score >= t[1] then return t[2], t[3], t[4] end
    end
    return 0.74, 0.49, 0.22
end

local function DiffShort(run)
    if MS.Flavor.dungeonLevels then
        local lo, hi
        if MS.ForeverLevelRange then lo, hi = MS:ForeverLevelRange(run) end
        return lo and (lo .. "-" .. hi) or ""
    end
    -- By difficulty ID: the stored label is in the client's language.
    local id = run.difficultyID
    local label = run.difficultyLabel or ""
    if id == 205 or label:find("Follower") then return L["Follower"] end
    if id == 24 or id == 33 then return L["TW"] end
    return label ~= "" and L[label] or "?"
end

-- How each result reads (MS:RunStatus / MS:ArchiveStatus in RunModel.lua).
local STATUS = {
    inTime    = { LK("In time"),     P.verd },
    overTime  = { LK("Over time"),   P.avoid },
    cleared   = { LK("Cleared"),     P.verd },
    live      = { LK("In progress"), P.bronzeHi },
    paused    = { LK("Paused"),      P.bronzeHi },
    finished  = { LK("Finished"),    P.ivory },
    abandoned = { LK("Abandoned"),   P.ash },
}

-- Result text + colour for a run, or for an archive entry.
local function RunResult(run)
    local s = STATUS[MS:RunStatus(run)] or STATUS.abandoned
    return L[s[1]], s[2]
end
local function ArchiveResult(e)
    local s = STATUS[MS:ArchiveStatus(e)] or STATUS.abandoned
    return L[s[1]], s[2]
end

-- Item quality colour (r, g, b), bronze when unknown.
local function QualityColor(q)
    if q and C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
        if ok and r then return r, g, b end
    end
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return P.bronze[1], P.bronze[2], P.bronze[3]
end

-- ===========================================================================
-- Scroll frame
-- ===========================================================================

local function MakeScrollFrame(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:EnableMouseWheel(true)

    local sb = CreateFrame("Slider", nil, sf)
    sb:SetPoint("TOPRIGHT",    sf, "TOPRIGHT",    -3, -2)
    sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -3,  2)
    sb:SetWidth(4)
    sb:SetOrientation("VERTICAL")
    sb:SetValueStep(1)
    sb:SetObeyStepOnDrag(true)
    sb:SetMinMaxValues(0, 0)
    sb:SetValue(0)
    local track = Solid(sb, "BACKGROUND", 0, P.line[1], P.line[2], P.line[3], 0.6)
    track:SetAllPoints()
    local thumb = sb:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(4, 36)
    thumb:SetColorTexture(P.bronze[1], P.bronze[2], P.bronze[3], 0.8)
    sb:SetThumbTexture(thumb)
    sb:Hide()

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(FRAME_W - 2)
    content:SetHeight(1)
    sf:SetScrollChild(content)

    sf:SetScript("OnMouseWheel", function(_, delta)
        local mn, mx = sb:GetMinMaxValues()
        sb:SetValue(_max(mn, _min(mx, sb:GetValue() - delta * ROW_H * 2)))
    end)
    sb:SetScript("OnValueChanged", function(_, val) sf:SetVerticalScroll(val) end)
    local function UpdateRange()
        local maxS = _max(0, content:GetHeight() - sf:GetHeight())
        sb:SetMinMaxValues(0, maxS)
        if sb:GetValue() > maxS then sb:SetValue(maxS) end
        sb:SetShown(maxS > 0)
    end
    content:SetScript("OnSizeChanged", UpdateRange)

    sf.scrollContent = content
    sf.scrollBar     = sb
    sf.UpdateRange   = UpdateRange
    return sf
end

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

-- An error line in chat, once per message (a broken redraw would otherwise
-- repeat it every poll).
function UI.SayOnce(what, err) MS:ReportError(what, err) end

-- What a run did for your character (Forever), for a tooltip.
-- prog: a live run's run.progress, or an archive entry's e.prog.
-- A chart line that stays smooth at any angle: a texture with soft edges,
-- drawn where it falls rather than snapped to whole pixels (a flat colour
-- snapped to pixels turns a slope into a staircase of dots).
function UI.ChartLine(parent, thickness)
    local l = parent:CreateLine(nil, "ARTWORK")
    l:SetTexture(MEDIA .. "LineSoft")
    l:SetThickness(thickness or 4)
    if l.SetSnapToPixelGrid then l:SetSnapToPixelGrid(false); l:SetTexelSnappingBias(0) end
    return l
end
function UI.ChartLineColor(l, col, a)
    l:SetVertexColor(col[1], col[2], col[3], a or 1)
end

-- A flat bar of one colour, in a line of text, w x h pixels.
local function Swatch(col, w, h)
    return string.format("|TInterface\\Buttons\\WHITE8X8:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t", h, math.max(1, w),
        math.floor(col[1] * 255 + 0.5), math.floor(col[2] * 255 + 0.5), math.floor(col[3] * 255 + 0.5))
end
UI.Swatch = Swatch

-- XP split two ways as a bar in a line of text: purple for what the dungeon
-- gave, yellow for quests done in it. Empty when there's no quest XP.
function UI.XPSplit(mob, quest, w, h)
    mob, quest = math.max(0, mob or 0), math.max(0, quest or 0)
    if quest <= 0 or mob + quest <= 0 then return "" end
    local q = math.max(1, math.floor(w * quest / (mob + quest) + 0.5))
    return Swatch(P.xpMob, w - q, h) .. Swatch(P.xpQuest, q, h)
end

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

-- Published for the other UI files.
UI.Abbrev = Abbrev
UI.Art = Art
UI.Box = Box
UI.Btn = Btn
UI.CELL_FONT_SIZE = CELL_FONT_SIZE
UI.CLASS_ICON_COORDS = CLASS_ICON_COORDS
UI.COLS = COLS
UI.COL_HDR_H = COL_HDR_H
UI.CT = CT
UI.ClassColor = ClassColor
UI.ClassHex = ClassHex
UI.ComputeColumnAnchors = ComputeColumnAnchors
UI.DN = DN
UI.DiffShort = DiffShort
UI.FIGHT_BOT = FIGHT_BOT
UI.FIGHT_TOP = FIGHT_TOP
UI.FRAME_H = FRAME_H
UI.FRAME_W = FRAME_W
UI.GetRole = GetRole
UI.HDR_H = HDR_H
UI.HGrad = HGrad
UI.MEDIA = MEDIA
UI.MakeScrollFrame = MakeScrollFrame
UI.Outline = Outline
UI.P = P
UI.PAD_X = PAD_X
UI.ROLE_ICON_COORDS = ROLE_ICON_COORDS
UI.ROLE_ICON_TEX = ROLE_ICON_TEX
UI.ROW_H = ROW_H
UI.RunResult = RunResult
UI.ArchiveResult = ArchiveResult
UI.QualityColor = QualityColor
UI.ScoreColor = ScoreColor
UI.SetFont = SetFont

-- SetText for a long name in a fixed width: if the game cuts it short, the
-- font steps down a size at a time (to minSize) until it fits, rather than
-- ending in "...". Back to full size for the next, shorter text.
function UI.FitText(fs, text, kind, size, minSize)
    if fs._msFitSize ~= size then SetFont(fs, kind, size); fs._msFitSize = size end
    fs:SetText(text)
    if not fs.IsTruncated then return end
    local s = size
    while fs:IsTruncated() and s > (minSize or size - 3) do
        s = s - 1
        SetFont(fs, kind, s); fs._msFitSize = s
        fs:SetText(text)
    end
end
UI.SetNameText = SetNameText
UI.ScriptOf = ScriptOf
UI.Solid = Solid
UI.SplitAbbrev = SplitAbbrev
UI.TL_H = TL_H
UI.Text = Text
UI.Tint = Tint
UI.VGrad = VGrad
UI.WIPE_BOT = WIPE_BOT
UI.WIPE_TOP = WIPE_TOP

-- A key's upgrade as three diamonds in a line of text: one filled for each
-- level it went up (+1, +2, +3), all hollow for a key over time.
function UI.Pips(n, size)
    size = size or 12
    local out = {}
    for i = 1, 3 do
        local on = i <= (n or 0)
        local c = on and P.bronzeHi or P.ash2
        out[i] = string.format("|T%s%s:%d:%d:0:0:32:32:0:32:0:32:%d:%d:%d|t", MEDIA, on and "PipFull" or "PipEmpty",
            size, size, math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
    end
    return table.concat(out)
end

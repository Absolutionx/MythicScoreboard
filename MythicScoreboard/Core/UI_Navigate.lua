local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI

-- ── The way to a dungeon (WoW Forever) ────────────────────────────────────
-- Click a dungeon's marker on the world map: the way there, step by step
-- ("Run to the flight master: Crossroads", "Fly to Camp Taurajo", "Run to
-- Razorfen Kraul"), with an arrow to where the step goes and the distance.
-- The route is Core/Travel.lua's, worked out again every couple of seconds
-- from where you are, so it follows you whatever you do.
--
-- The arrow's turn: where the step goes from you (on the continent's map,
-- in yards), against which way you face (GetPlayerFacing: 0 is north,
-- turning left). A step that's your hearthstone, Astral Recall or a
-- teleport: in the arrow's place, its icon, to click and go.

local _atan2 = math.atan2 or math.atan
local _floor, _fmt, _pi = math.floor, string.format, math.pi

local ARRIVED_YARDS = 25
local AT_YARDS = 15                          -- this close to a flight master or dock: there
local REPLAN = 2                             -- seconds between working out the route again
local REFRESH = 0.1                          -- seconds between looking where you are (the turn: every frame)

local frame, target, plan, planAt, inAir, airFor
local taxiOpen                               -- a flight master's map is open
local P = UI and UI.P

-- ── The steps ──────────────────────────────────────────────────────────────
-- What to do for a leg of the route, and where the arrow points: where the
-- leg ends (a flight or a boat too: the way you'll be going).
local function StepText(leg)
    local to = leg.to
    if leg.how == "fly" then return _fmt(L["Fly to %s"], to.name), to end
    if leg.how == "boat" then return _fmt(L["Take the boat to %s"], to.name), to end
    if leg.how == "zeppelin" then return _fmt(L["Take the zeppelin to %s"], to.name), to end
    if leg.how == "tram" then return _fmt(L["Take the tram to %s"], to.name), to end
    if leg.how == "airship" then return _fmt(L["Take the airship to %s"], to.name), to end
    -- (No arrow: there's nowhere to walk.)
    if leg.how == "hearth" then return _fmt(L["Use your Hearthstone (%s)"], to.name) end
    if leg.how == "recall" then return _fmt(L["Cast Astral Recall (%s)"], to.name) end
    if leg.how == "teleport" then return _fmt(L["Teleport to %s"], to.name) end
    if to.kind == "flight" and leg.talk then return _fmt(L["Talk to the flight master: %s"], to.name), to end
    if to.kind == "flight" then return _fmt(L["Run to the flight master: %s"], to.name), to end
    if to.kind == "dock" then
        local text = to.transport == "zeppelin" and L["Run to the zeppelin to %s"]
            or to.transport == "tram" and L["Run to the tram to %s"]
            or to.transport == "airship" and L["Run to the airship to %s"] or L["Run to the boat to %s"]
        return _fmt(text, to.other and to.other.name or to.name), to
    end
    return _fmt(L["Run to %s"], target and target.name or to.name or "?"), to
end

-- The steps from here: the route's legs, less a run already done (you're at
-- the dock). At the flight master: talk to it, until its flight map's open.
local function Steps(legs, here)
    local out = {}
    for i, leg in ipairs(legs or {}) do
        local at = i == 1 and leg.how == "run" and here and leg.to.kind ~= "end"
            and (MS:Yards(here.c, here.x, here.y, leg.to.x, leg.to.y) or 99) <= AT_YARDS
        if at and leg.to.kind == "flight" and not taxiOpen then
            out[#out + 1] = { how = leg.how, to = leg.to, talk = true }
        elseif not at then
            out[#out + 1] = leg
        end
    end
    return out
end
MS._NavigationSteps = Steps                  -- for tests

-- The turn from where you face to a spot (radians, left positive, as
-- SetRotation), and the yards to it.
function MS:TurnTo(here, spot)
    local w, h = MS:ContinentSize(here.c)
    if not w then return nil end
    local east, south = (spot.x - here.x) * w, (spot.y - here.y) * h
    local yards = math.sqrt(east * east + south * south)
    local bearing = _atan2(east, -south)                 -- clockwise from north
    local Facing = rawget(_G, "GetPlayerFacing")
    local facing = MS.ReadableNumber(Facing and Facing()) or 0
    local turn = -(bearing + facing)
    turn = (turn + _pi) % (2 * _pi) - _pi
    return turn, yards, bearing
end

-- The arrow's turn for a bearing (clockwise from north) and the way you
-- face now: all that changes from one frame to the next.
local function TurnFor(bearing)
    local Facing = rawget(_G, "GetPlayerFacing")
    local facing = MS.ReadableNumber(Facing and Facing()) or 0
    return (-(bearing + facing) + _pi) % (2 * _pi) - _pi
end

-- ── The arrow ──────────────────────────────────────────────────────────────
local passLater                              -- right-click pass-through, once out of combat
MS:On("PLAYER_REGEN_ENABLED", function()
    if passLater and frame then passLater = false; MS.SafePassThrough(frame, "RightButton") end
end)
-- The route drawn on the world map (Core/UI_RouteMap.lua) follows it.
local function RouteChanged()
    if MS.RefreshRouteMap then MS:RefreshRouteMap() end
end

-- The flight you're on, kept over a /reload: Flying(place) keeps it,
-- Flying(false) forgets it, Flying() gives it back.
local function Flying(place)
    MythicScoreboardDB = MythicScoreboardDB or {}
    if place then
        local f = MythicScoreboardDB.navFlying
        if not (f and f.name == place.name and f.x == place.x and f.y == place.y) then
            MythicScoreboardDB.navFlying = { kind = "flight", name = place.name, c = place.c, x = place.x, y = place.y }
        end
    elseif place == false then
        MythicScoreboardDB.navFlying = nil
    else
        local f = MythicScoreboardDB.navFlying
        if type(f) == "table" and f.c and f.x and f.y then return f end
    end
end

local function SaveTarget()
    MythicScoreboardDB = MythicScoreboardDB or {}
    MythicScoreboardDB.navTarget = target and { name = target.name, map = target.map, x = target.x, y = target.y } or nil
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Button", "MythicScoreboardArrow", UIParent)
    frame:SetSize(220, 110)
    -- Where it was dragged to, or just above your character (the middle of
    -- the screen): its bottom a little over your head.
    local pos = MS:GetSetting("navPos")
    if type(pos) == "table" and pos.x and pos.y then
        frame:SetPoint("BOTTOM", UIParent, "CENTER", pos.x, pos.y)
    else
        frame:SetPoint("BOTTOM", UIParent, "CENTER", 0, 60)
    end
    frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    -- Only a Shift-click stops it: the right button goes through to the game,
    -- so holding it over the arrow still turns you.
    frame:RegisterForClicks("LeftButtonUp")
    -- Right-click goes through (to turn your character). Not allowed in
    -- combat: then once the fight's over.
    local InCombat = rawget(_G, "InCombatLockdown")
    if InCombat and InCombat() then
        passLater = true
    else
        MS.SafePassThrough(frame, "RightButton")
    end
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Kept as an offset from the middle, the same at any screen size.
        local cx, by = self:GetCenter(), self:GetBottom()
        local ux, uy = UIParent:GetCenter()
        if cx and by and ux and uy then
            local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local at = { x = math.floor(cx * s - ux + 0.5), y = math.floor(by * s - uy + 0.5) }
            MS:SetSetting("navPos", at)
            self:ClearAllPoints()
            self:SetPoint("BOTTOM", UIParent, "CENTER", at.x, at.y)
        end
    end)
    frame:SetScript("OnClick", function() if IsShiftKeyDown() then MS:StopNavigation() end end)

    local arrow = frame:CreateTexture(nil, "ARTWORK")
    -- Smooth when turned and scaled (the art is drawn near its size on screen).
    arrow:SetTexture("Interface\\AddOns\\MythicScoreboard\\Media\\Arrow", nil, nil, "TRILINEAR")
    arrow:SetSize(56, 56); arrow:SetPoint("TOP", 0, 0)
    if arrow.SetSnapToPixelGrid then arrow:SetSnapToPixelGrid(false); arrow:SetTexelSnappingBias(0) end
    if P then arrow:SetVertexColor(P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3]) end
    frame.arrow = arrow

    -- The game's fonts, a little bigger: easy to read at a glance.
    local function Size(fs, size)
        local file, _, flags = fs:GetFont()
        if file then fs:SetFont(file, size, flags) end
    end
    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Size(name, 14)
    name:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
    frame.name = name
    local step = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Size(step, 14)
    step:SetPoint("TOP", name, "BOTTOM", 0, -3)
    step:SetWidth(260)
    frame.step = step
    local dist = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Size(dist, 13)
    dist:SetPoint("TOP", step, "BOTTOM", 0, -2)
    frame.dist = dist

    -- Every frame: only the arrow's turn, from the bearing last worked out
    -- and the way you face now, so it follows you with no lag. Where you
    -- are, the step and the distance: ten times a second. The route itself:
    -- every couple of seconds.
    local wait = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        wait = wait - (elapsed or 0)
        if wait <= 0 then
            wait = REFRESH
            local ok, err = pcall(MS.UpdateArrow, MS)
            if not ok then MS:ReportError("Arrow", err); MS:StopNavigation() end
        elseif self.bearing then
            self.arrow:SetRotation(TurnFor(self.bearing))
        end
    end)
    frame:Hide()
    return frame
end

-- ── Hearthstone, Astral Recall, a teleport: click to go ───────────────────
-- A secure button (only those may use an item or cast a spell for you), on
-- its own (so the arrow's frame stays free to hide in a fight) and over
-- where the arrow is. The game won't let a secure button be changed, shown
-- or hidden in combat: then it's left as it is, and set right as the fight
-- ends (you can't hearth in combat anyway).
local jump, jumpWant                         -- the button; the step it's for (nil: none)

local function JumpIcon(to)
    if to.item then
        local CItem = rawget(_G, "C_Item")
        local get = (CItem and CItem.GetItemIconByID) or rawget(_G, "GetItemIcon")
        local ok, icon = pcall(get or error, to.item)
        return ok and icon or 134400
    end
    local CSpell = rawget(_G, "C_Spell")
    local get = (CSpell and CSpell.GetSpellTexture) or rawget(_G, "GetSpellTexture")
    local ok, icon = pcall(get or error, to.spell)
    return ok and icon or 134400
end

local function BuildJump()
    if jump then return jump end
    jump = CreateFrame("Button", "MythicScoreboardJump", UIParent, "SecureActionButtonTemplate")
    jump:SetSize(48, 48)
    jump:SetPoint("CENTER", frame, "TOP", 0, -28)          -- where the arrow is
    jump:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    -- (Down and up: the game uses whichever its "cast on key down" setting says.)
    jump:RegisterForClicks("AnyUp", "AnyDown")
    local icon = jump:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    jump.icon = icon
    local edge = jump:CreateTexture(nil, "OVERLAY")
    edge:SetPoint("TOPLEFT", -3, 3); edge:SetPoint("BOTTOMRIGHT", 3, -3)
    edge:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); edge:SetBlendMode("ADD")
    if P then edge:SetVertexColor(P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3], 0.8) end
    jump:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    jump:SetScript("OnEnter", function(self)
        local to = self.to
        if not to then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = false
        if to.item and GameTooltip.SetItemByID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, to.item)
        elseif to.spell and GameTooltip.SetSpellByID then ok = pcall(GameTooltip.SetSpellByID, GameTooltip, to.spell) end
        if not ok then GameTooltip:SetText(to.name or "?", 1, 1, 1) end
        GameTooltip:AddLine(_fmt(L["Click to go to %s."], to.name or "?"), 0.91, 0.72, 0.47)
        GameTooltip:Show()
    end)
    jump:SetScript("OnLeave", function() GameTooltip:Hide() end)
    jump:Hide()
    return jump
end

-- Shows the button for a step ({ item or spell, name }), or hides it (nil).
-- In combat: nothing yet (PLAYER_REGEN_ENABLED, below, does it after).
local function SetJump(to)
    jumpWant = to
    local InCombat = rawget(_G, "InCombatLockdown")
    if InCombat and InCombat() then return end
    if not to then
        if jump and jump:IsShown() then jump:Hide() end
        if jump then jump.to, jump.key = nil, nil end
        return
    end
    BuildJump()
    local key = (to.item and "item:" .. to.item) or ("spell:" .. tostring(to.spell))
    if jump.key ~= key then
        jump.key = key
        if to.item then
            jump:SetAttribute("type", "item")
            jump:SetAttribute("item", "item:" .. to.item)
            jump:SetAttribute("spell", nil)
        else
            jump:SetAttribute("type", "spell")
            jump:SetAttribute("spell", to.spell)
            jump:SetAttribute("item", nil)
        end
        jump.icon:SetTexture(JumpIcon(to))
    end
    jump.to = to
    if not jump:IsShown() then jump:Show() end
end
MS:On("PLAYER_REGEN_ENABLED", function()
    if jump or jumpWant then pcall(SetJump, target and jumpWant or nil) end
end)
function MS:NavigationJump() return jump and jump:IsShown() and jump.to or nil end   -- for tests

-- ── Distance and time left ────────────────────────────────────────────────
-- The time left is the yards to go over how fast they've been going down
-- (on foot, mounted or in the air): measured, not guessed, and smoothed so
-- it doesn't jump about. A new place to head for starts it afresh.
local SAMPLE = 0.5                           -- seconds between measures
local pace = {}                              -- { key, t, yards, speed }

local function Clock(sec)
    sec = _floor(sec + 0.5)
    if sec >= 3600 then return _fmt("%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60) end
    return _fmt("%d:%02d", sec / 60, sec % 60)
end

local function Remaining(key, yards)
    local now = GetTime()
    if pace.key ~= key then
        pace.key, pace.t, pace.yards, pace.speed = key, now, yards, nil
    elseif now - pace.t >= SAMPLE then
        local v = (pace.yards - yards) / (now - pace.t)
        if v >= 0 then pace.speed = pace.speed and (pace.speed * 0.7 + v * 0.3) or v end
        pace.t, pace.yards = now, yards
    end
    if pace.speed and pace.speed > 1 then return yards / pace.speed end
end

-- "450 yards  0:15" (the time once it's known).
local function DistText(key, yards)
    local d = "|cffe8b878" .. _fmt(L["%s yards"], MS.FormatThousands(_floor(yards + 0.5))) .. "|r"
    local left = Remaining(key, yards)
    if left then d = d .. "  |cffffd14d" .. Clock(left) .. "|r" end
    return d
end
MS._NavClock = Clock                         -- for tests

local function SetText(fs, key, text)
    if frame[key] ~= text then frame[key] = text; fs:SetText(text) end
end

-- The arrow pointing (its bearing kept, for the frames in between), or hidden.
local function Point(turn, bearing)
    frame.bearing = bearing
    frame.arrow:Show(); frame.arrow:SetRotation(turn)
end
local function NoPoint()
    frame.bearing = nil
    frame.arrow:Hide()
end

function MS:UpdateArrow()
    if not (frame and target) then return end
    local OnTaxi = rawget(_G, "UnitOnTaxi")
    if OnTaxi and OnTaxi("player") then                  -- in the air: where you'll land, how far, how long
        -- Where this flight lands: the one taken (any flight: kept as it's
        -- taken, and over a /reload), or the route's.
        local dest = Flying()
        if not dest then
            local leg = plan and plan[1]
            if leg and leg.talk then leg = plan[2] end           -- (taken before the steps caught up)
            dest = leg and leg.how == "fly" and leg.to or nil
            if dest then Flying(dest) end
        end
        -- The rest of the way from there, worked out once for this flight.
        if dest and target.spot then
            local key = _fmt("%s:%s:%.4f:%.4f", dest.name or "", tostring(dest.c), dest.x, dest.y)
            if airFor ~= key then
                airFor = key
                local landing = { c = dest.c, x = dest.x, y = dest.y }
                plan = { { how = "fly", to = dest } }
                for _, leg in ipairs(Steps(MS:PlanRoute(landing, target.spot), landing)) do plan[#plan + 1] = leg end
                if #plan == 1 then
                    plan[2] = { how = "run", to = { kind = "end", c = target.spot.c, x = target.spot.x, y = target.spot.y, name = target.name } }
                end
                RouteChanged()
            end
        end
        local c, x, y = MS:PlayerSpot()
        local here = x and { c = c, x = x, y = y }
        -- Not known where it lands: the arrow to the dungeon itself.
        local spot = dest or target.spot
        local text = ""
        if dest then
            text = _fmt(L["Land at %s"], dest.name)
            if plan and #plan > 1 then
                text = _fmt(L["Step %d of %d"], 1, #plan) .. ": " .. text
                    .. "\n|cffbbbbbb" .. _fmt(L["Then: %s"], (StepText(plan[2]))) .. "|r"
            end
        end
        SetText(frame.step, "lastStep", text)
        SetJump(nil)
        local turn, yards, bearing
        if here and spot and here.c == spot.c then turn, yards, bearing = MS:TurnTo(here, spot) end
        if turn then Point(turn, bearing) else NoPoint() end
        SetText(frame.dist, "lastDist", yards and DistText("fly:" .. (spot.name or ""), yards) or "")
        planAt, inAir = nil, true
        return
    end
    -- Landed: the flight's done. (Not before seeing it: at a login in the air
    -- the game may not say so straight away.)
    if inAir then inAir, airFor, planAt = false, nil, nil; Flying(false) end
    local c, x, y = MS:PlayerSpot()
    local here = x and { c = c, x = x, y = y }
    local goal = target.spot
    if here and goal and here.c == goal.c then
        local yards = MS:Yards(here.c, here.x, here.y, goal.x, goal.y)
        if yards and yards <= ARRIVED_YARDS then
            MS.Say(_fmt(L["You've arrived at %s."], target.name))
            MS:StopNavigation()
            return
        end
    end
    local now = GetTime()
    if here and goal and (not planAt or now - planAt >= REPLAN) then
        planAt = now
        plan = Steps(MS:PlanRoute(here, goal), here)
        RouteChanged()
    end
    local leg = plan and plan[1]
    if not (here and leg) then
        NoPoint()
        SetJump(nil)
        local where = goal and MS:MapName(goal.c)
        SetText(frame.step, "lastStep", here and where and here.c ~= goal.c and _fmt(L["Travel to %s"], where) or "")
        SetText(frame.dist, "lastDist", "")
        return
    end
    local text, spot = StepText(leg)
    if #plan > 1 then text = _fmt(L["Step %d of %d"], 1, #plan) .. ": " .. text end
    SetText(frame.step, "lastStep", text)
    -- Hearthstone, Astral Recall, a teleport: its icon to click, in the arrow's place.
    if (leg.how == "hearth" or leg.how == "recall" or leg.how == "teleport") and (leg.to.item or leg.to.spell) then
        NoPoint()
        SetJump(leg.to)
        SetText(frame.dist, "lastDist", "|cffe8b878" .. L["Click the icon to go."] .. "|r")
        return
    end
    SetJump(nil)
    if spot then
        local turn, yards, bearing = MS:TurnTo(here, spot)
        if turn then
            Point(turn, bearing)
            SetText(frame.dist, "lastDist", DistText(_fmt("%s:%.4f:%.4f", spot.kind or "", spot.x, spot.y), yards))
            return
        end
    end
    NoPoint()
    SetText(frame.dist, "lastDist", "")
end

-- Shows the way to a dungeon's entrance ({ name, map, x, y }).
function MS:NavigateTo(t)
    target = { name = t.name, map = t.map, x = t.x, y = t.y }
    local c, x, y = MS:OnContinent(t.map, t.x, t.y)
    target.spot = c and { c = c, x = x, y = y, name = t.name } or nil
    plan, planAt, airFor = nil, nil, nil
    SaveTarget()
    Build()
    frame.lastStep, frame.lastDist = nil, nil
    frame.name:SetText(target.name)
    frame:Show()
    MS:UpdateArrow()
    RouteChanged()
end

function MS:StopNavigation()
    target, plan, planAt, airFor = nil, nil, nil, nil
    SaveTarget()
    SetJump(nil)
    if frame then frame:Hide() end
    RouteChanged()
end

function MS:NavigationTarget() return target end
function MS:NavigationSteps() return plan end
-- What a step says ("Fly to Crossroads"), or nil.
function MS:NavigationStepText(i)
    local leg = plan and plan[i]
    return leg and (StepText(leg)) or nil
end

-- Clicking a marker: the way there (again: stop).
function MS:ToggleNavigation(pin)
    local first = pin.dungeons[1]
    local e = first and first.entrance
    if not e then return end
    if target and target.map == e.map and target.x == e.x and target.y == e.y then
        MS:StopNavigation()
    else
        local name = #pin.dungeons > 1 and (pin.group or first.name) or first.name
        MS:NavigateTo({ name = name, map = e.map, x = e.x, y = e.y })
    end
end

if MS.FLAVOR ~= "forever" then return end

-- Back after a /reload; done once inside a dungeon. A new zone (off a boat,
-- say): the route again straight away.
MS:On("PLAYER_LOGIN", function()
    local t = MythicScoreboardDB and MythicScoreboardDB.navTarget
    if type(t) == "table" and t.map and t.x and t.y then pcall(MS.NavigateTo, MS, t) end
end)
MS:On("PLAYER_ENTERING_WORLD", function()
    if target and IsInInstance() then MS:StopNavigation() end
    planAt = nil
end)
MS:On("ZONE_CHANGED_NEW_AREA", function() planAt = nil end)

-- ── Taking the flight ──────────────────────────────────────────────────────
-- At a flight master with "Fly to X" the step: opening the flight map takes
-- the flight to X (unless Shift is held, or it's turned off). Travel.lua has
-- just learned this map's flight masters, so the route is worked out again
-- first, by the names the game uses.
local function NodeName(name) return name and (name:match("^([^,]+)") or name) end

local function TakeFlight()
    if not (target and MS:GetAutoTakeFlights()) or IsShiftKeyDown() then return end
    local c, x, y = MS:PlayerSpot()
    if not (x and target.spot) then return end
    local here = { c = c, x = x, y = y }
    plan, planAt = Steps(MS:PlanRoute(here, target.spot), here), GetTime()
    local leg = plan and plan[1]
    if not (leg and leg.how == "fly") then return end
    local want = NodeName(leg.to.name)
    local T = rawget(_G, "C_TaxiMap")
    if T and T.GetAllTaxiNodes then
        local ok, nodes = pcall(T.GetAllTaxiNodes, c)
        for _, n in ipairs(ok and nodes or {}) do
            -- state 1: reachable (0 is where you are, 2 not known).
            if NodeName(MS.Readable(n.name)) == want and MS.ReadableNumber(n.state) == 1 and n.slotIndex then
                TakeTaxiNode(n.slotIndex)
                return
            end
        end
    end
    local Num, Name, Type = rawget(_G, "NumTaxiNodes"), rawget(_G, "TaxiNodeName"), rawget(_G, "TaxiNodeGetType")
    for i = 1, Num and Num() or 0 do
        if NodeName(MS.Readable(Name(i))) == want and Type(i) == "REACHABLE" then
            TakeTaxiNode(i)
            return
        end
    end
end
MS:On("TAXIMAP_OPENED", function()
    taxiOpen = true
    planAt = nil
    Flying(false)                            -- a new flight: kept once it's in the route
    local ok, err = pcall(TakeFlight)
    if not ok then MS:ReportError("Flight", err) end
    if MS.RefreshRouteMap then MS:RefreshRouteMap() end
end)
MS:On("TAXIMAP_CLOSED", function() taxiOpen = false; planAt = nil end)

-- Landed (with the directions shown or not): that flight's over.
MS:On("PLAYER_CONTROL_GAINED", function()
    local OnTaxi = rawget(_G, "UnitOnTaxi")
    if not (OnTaxi and OnTaxi("player")) then Flying(false); airFor = nil end
end)

-- Any flight taken (the addon's or your own choice): where it lands, kept,
-- so the steps carry on from there.
if MS.FLAVOR == "forever" and type(rawget(_G, "TakeTaxiNode")) == "function" then
    hooksecurefunc("TakeTaxiNode", function(slot)
        local ok, spot = pcall(MS.TaxiNodeSpot, MS, slot)
        if ok and spot then
            Flying(spot)
            airFor = nil
        end
    end)
end

-- Talking to a flight master with a flight next on the way: straight past
-- the chat to the flight map, which then takes the flight (above). The
-- taxi choice is the one with the flight icon (or "taxi", where the game
-- says). Shift, or the setting off: the chat as usual.
local TAXI_ICON = 132057

local function TaxiOption(G)
    local ok, options = pcall(G.GetOptions)
    for _, o in ipairs(ok and type(options) == "table" and options or {}) do
        if o.type == "taxi" or MS.ReadableNumber(o.icon) == TAXI_ICON then return o end
    end
end

local function SkipToFlightMap()
    if not (target and target.spot and MS:GetAutoTakeFlights()) or IsShiftKeyDown() then return end
    local G = rawget(_G, "C_GossipInfo")
    if not (G and G.GetOptions) then return end
    local c, x, y = MS:PlayerSpot()
    if not x then return end
    local here = { c = c, x = x, y = y }
    plan, planAt = Steps(MS:PlanRoute(here, target.spot), here), GetTime()
    -- A flight next, or after the run to this flight master (whose spot may
    -- be a little off until its flight map has been opened once).
    local next1, next2 = plan and plan[1], plan and plan[2]
    if not ((next1 and next1.how == "fly") or (next1 and next1.to.kind == "flight" and next2 and next2.how == "fly")) then
        return
    end
    local o = TaxiOption(G)
    if not o then return end
    if o.gossipOptionID and G.SelectOption then G.SelectOption(o.gossipOptionID)
    elseif o.orderIndex and G.SelectOptionByIndex then G.SelectOptionByIndex(o.orderIndex) end
end
MS:On("GOSSIP_SHOW", function()
    local ok, err = pcall(SkipToFlightMap)
    if not ok then MS:ReportError("Flight", err) end
end)

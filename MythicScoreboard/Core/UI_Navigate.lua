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
-- turning left).

local _atan2 = math.atan2 or math.atan
local _floor, _fmt, _pi = math.floor, string.format, math.pi

local ARRIVED_YARDS = 25
local AT_YARDS = 15                          -- this close to a flight master or dock: there
local REPLAN = 2                             -- seconds between working out the route again

local frame, target, plan, planAt, inAir
local P = UI and UI.P

-- ── The steps ──────────────────────────────────────────────────────────────
-- What to do for a leg of the route, and where the arrow points: where the
-- leg ends (a flight or a boat too: the way you'll be going).
local function StepText(leg)
    local to = leg.to
    if leg.how == "fly" then return _fmt(L["Fly to %s"], to.name), to end
    if leg.how == "boat" then return _fmt(L["Take the boat to %s"], to.name), to end
    if leg.how == "zeppelin" then return _fmt(L["Take the zeppelin to %s"], to.name), to end
    if to.kind == "flight" then return _fmt(L["Run to the flight master: %s"], to.name), to end
    if to.kind == "dock" then
        local text = to.transport == "zeppelin" and L["Run to the zeppelin to %s"] or L["Run to the boat to %s"]
        return _fmt(text, to.other and to.other.name or to.name), to
    end
    return _fmt(L["Run to %s"], target and target.name or to.name or "?"), to
end

-- The steps from here: the route's legs, less a run already done (you're at
-- the flight master or dock).
local function Steps(legs, here)
    local out = {}
    for i, leg in ipairs(legs or {}) do
        local skip = i == 1 and leg.how == "run" and here and leg.to.kind ~= "end"
            and (MS:Yards(here.c, here.x, here.y, leg.to.x, leg.to.y) or 99) <= AT_YARDS
        if not skip then out[#out + 1] = leg end
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
    return turn, yards
end

-- ── The arrow ──────────────────────────────────────────────────────────────
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
    local pos = MythicScoreboardDB and MythicScoreboardDB.navPos
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
    if frame.SetPassThroughButtons then pcall(frame.SetPassThroughButtons, frame, "RightButton") end
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Kept as an offset from the middle, the same at any screen size.
        local cx, by = self:GetCenter(), self:GetBottom()
        local ux, uy = UIParent:GetCenter()
        if cx and by and ux and uy then
            local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            MythicScoreboardDB = MythicScoreboardDB or {}
            MythicScoreboardDB.navPos = { x = math.floor(cx * s - ux + 0.5), y = math.floor(by * s - uy + 0.5) }
            self:ClearAllPoints()
            self:SetPoint("BOTTOM", UIParent, "CENTER", MythicScoreboardDB.navPos.x, MythicScoreboardDB.navPos.y)
        end
    end)
    frame:SetScript("OnClick", function() if IsShiftKeyDown() then MS:StopNavigation() end end)

    local arrow = frame:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\AddOns\\MythicScoreboard\\Media\\Arrow")
    arrow:SetSize(56, 56); arrow:SetPoint("TOP", 0, 0)
    if arrow.SetSnapToPixelGrid then arrow:SetSnapToPixelGrid(false); arrow:SetTexelSnappingBias(0) end
    if P then arrow:SetVertexColor(P.bronzeHi[1], P.bronzeHi[2], P.bronzeHi[3]) end
    frame.arrow = arrow

    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
    frame.name = name
    local step = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    step:SetPoint("TOP", name, "BOTTOM", 0, -3)
    step:SetWidth(220)
    frame.step = step
    local dist = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dist:SetPoint("TOP", step, "BOTTOM", 0, -2)
    frame.dist = dist

    -- Every frame: the turn follows you as you turn, with no lag. The route
    -- itself only every couple of seconds.
    frame:SetScript("OnUpdate", function()
        local ok, err = pcall(MS.UpdateArrow, MS)
        if not ok then MS:ReportError("Arrow", err); MS:StopNavigation() end
    end)
    frame:Hide()
    return frame
end

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

function MS:UpdateArrow()
    if not (frame and target) then return end
    local OnTaxi = rawget(_G, "UnitOnTaxi")
    if OnTaxi and OnTaxi("player") then                  -- in the air: where you'll land, how far, how long
        local leg = plan and plan[1]
        local dest = leg and leg.how == "fly" and leg.to
        if dest then
            Flying(dest)
        else
            -- No flight in the route (a /reload in the air): the one taken,
            -- kept, then the rest of the way from where it lands.
            dest = Flying()
            if dest and target.spot then
                plan = { { how = "fly", to = dest },
                         { how = "run", to = { kind = "end", c = target.spot.c, x = target.spot.x, y = target.spot.y, name = target.name } } }
                RouteChanged()
            end
        end
        local c, x, y = MS:PlayerSpot()
        local here = x and { c = c, x = x, y = y }
        -- Not known where it lands: the arrow to the dungeon itself.
        local spot = dest or target.spot
        SetText(frame.step, "lastStep", dest and _fmt(L["Flying to %s"], dest.name) or "")
        local turn, yards
        if here and spot and here.c == spot.c then turn, yards = MS:TurnTo(here, spot) end
        if turn then frame.arrow:Show(); frame.arrow:SetRotation(turn) else frame.arrow:Hide() end
        SetText(frame.dist, "lastDist", yards and DistText("fly:" .. (spot.name or ""), yards) or "")
        planAt, inAir = nil, true
        return
    end
    -- Landed: the flight's done. (Not before seeing it: at a login in the air
    -- the game may not say so straight away.)
    if inAir then inAir = false; Flying(false) end
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
        frame.arrow:Hide()
        local where = goal and MS:MapName(goal.c)
        SetText(frame.step, "lastStep", here and where and here.c ~= goal.c and _fmt(L["Travel to %s"], where) or "")
        SetText(frame.dist, "lastDist", "")
        return
    end
    local text, spot = StepText(leg)
    if #plan > 1 then text = _fmt(L["Step %d of %d"], 1, #plan) .. ": " .. text end
    SetText(frame.step, "lastStep", text)
    if spot then
        local turn, yards = MS:TurnTo(here, spot)
        if turn then
            frame.arrow:Show(); frame.arrow:SetRotation(turn)
            SetText(frame.dist, "lastDist", DistText(_fmt("%s:%.4f:%.4f", spot.kind or "", spot.x, spot.y), yards))
            return
        end
    end
    frame.arrow:Hide()
    SetText(frame.dist, "lastDist", "")
end

-- Shows the way to a dungeon's entrance ({ name, map, x, y }).
function MS:NavigateTo(t)
    target = { name = t.name, map = t.map, x = t.x, y = t.y }
    local c, x, y = MS:OnContinent(t.map, t.x, t.y)
    target.spot = c and { c = c, x = x, y = y, name = t.name } or nil
    plan, planAt = nil, nil
    SaveTarget()
    Build()
    frame.lastStep, frame.lastDist = nil, nil
    frame.name:SetText(target.name)
    frame:Show()
    MS:UpdateArrow()
    RouteChanged()
end

function MS:StopNavigation()
    target, plan, planAt = nil, nil, nil
    SaveTarget()
    Flying(false)
    if frame then frame:Hide() end
    RouteChanged()
end

function MS:NavigationTarget() return target end
function MS:NavigationSteps() return plan end

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
    Flying(false)                            -- a new flight: kept once it's in the route
    local ok, err = pcall(TakeFlight)
    if not ok then MS:ReportError("Flight", err) end
    if MS.RefreshRouteMap then MS:RefreshRouteMap() end
end)
MS:On("TAXIMAP_CLOSED", function() planAt = nil end)

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

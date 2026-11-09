-- Item level, specialization, character level, role and rating for each
-- group member.
--
-- Item levels and other players' specializations need an inspect, one
-- player at a time; the result is cached for the session. Roles and ratings
-- are read on roster changes.

local _floor, _ins, _rem = math.floor, table.insert, table.remove

local MS = _G["MythicScoreboard"]
local IsSecret = _G["MythicScoreboard"].IsSecret

local inspectQueue   = {}
local inspectPending = nil
local INSPECT_DELAY  = 0.5
local inspectFrame   = nil

local function Later(fn) C_Timer.After(INSPECT_DELAY, fn) end

-- Specializations exist on this client (not in Forever).
local HAS_SPECS = rawget(_G, "GetInspectSpecialization") ~= nil and rawget(_G, "GetSpecializationInfoByID") ~= nil
MS.specCache = MS.specCache or {}

local function ValidSpec(id)
    return type(id) == "number" and not IsSecret(id) and id > 0 and id or nil
end

-- Your own specialization, read directly.
local function OwnSpec()
    if not (HAS_SPECS and GetSpecialization and GetSpecializationInfo) then return nil end
    local ok, idx = pcall(GetSpecialization)
    if not (ok and type(idx) == "number" and idx > 0) then return nil end
    local ok2, id = pcall(GetSpecializationInfo, idx)
    return ok2 and ValidSpec(id) or nil
end

-- A spec ID as "Holy Paladin" (localised), and its role.
function MS.SpecLabel(specID, class)
    if not (HAS_SPECS and specID) then return nil end
    local ok, _, specName, _, _, role = pcall(GetSpecializationInfoByID, specID)
    if not (ok and type(specName) == "string" and specName ~= "") then return nil end
    local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
    local className = names and class and names[class]
    return className and (specName .. " " .. className) or specName, role
end

local function EnsureInspectFrame()
    if inspectFrame then return end
    inspectFrame = CreateFrame("Frame")
    inspectFrame:RegisterEvent("INSPECT_READY")
    inspectFrame:SetScript("OnEvent", function(_, event, guid)
        if event ~= "INSPECT_READY" or not inspectPending then return end
        -- The GUID can be hidden in Midnight: compare only a readable one.
        local targetUnit = MS:UnitForGUID(MS.Readable(guid))
        local name = inspectPending
        inspectPending = nil
        if targetUnit and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
            local ok, il = pcall(C_PaperDollInfo.GetInspectItemLevel, targetUnit)
            if ok and type(il) == "number" and not IsSecret(il) and il > 0 then
                il = _floor(il)
                MS.itemLevelCache = MS.itemLevelCache or {}
                MS.itemLevelCache[name] = il
                local p = MS:PlayerByName(name)
                if p then p.itemLevel = il end
                MS:Changed("run")
            end
        end
        if targetUnit and HAS_SPECS then
            local ok, id = pcall(GetInspectSpecialization, targetUnit)
            id = ok and ValidSpec(id)
            if id then
                MS.specCache[name] = id
                local p = MS:PlayerByName(name)
                if p and p.specID ~= id then p.specID = id; MS:Changed("run") end
            end
        end
        ClearInspectPlayer()
        if #inspectQueue > 0 then Later(function() MS:_ProcessInspectQueue() end) end
    end)
end

function MS:_ProcessInspectQueue()
    if inspectPending or #inspectQueue == 0 then return end
    if InCombatLockdown() then
        C_Timer.After(5.0, function() self:_ProcessInspectQueue() end); return
    end
    EnsureInspectFrame()
    local entry = _rem(inspectQueue, 1)
    local unit
    for _, u in ipairs(self:GroupUnits()) do
        local p = self:PlayerForUnit(u)
        if p and p.name == entry.name then unit = u; break end
    end
    if unit and CanInspect(unit) then
        inspectPending = entry.name
        NotifyInspect(unit)
        local pendingAtCall = entry.name
        C_Timer.After(5.0, function()
            if inspectPending == pendingAtCall then
                inspectPending = nil
                ClearInspectPlayer()
                if #inspectQueue > 0 then Later(function() self:_ProcessInspectQueue() end) end
            end
        end)
    elseif #inspectQueue > 0 then
        Later(function() self:_ProcessInspectQueue() end)
    end
end

-- Roles and scores are stable mid-run; only call on GROUP_ROSTER_UPDATE.
function MS:PopulateRolesAndScores()
    if not self.currentRun then return end
    for _, unit in ipairs(self:GroupUnits()) do
        local p = self:PlayerForUnit(unit)
        if p then
            local short = p.name
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
            if role and role ~= "" and role ~= "NONE" then p.role = role end
            if unit == "player" then
                local spec = OwnSpec()
                if spec then p.specID = spec; self.specCache[short] = spec end
            elseif self.specCache[short] then
                p.specID = self.specCache[short]
            end
            local score
            if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
                local ok, sc = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
                local v = ok and type(sc) == "table" and sc.currentSeasonScore
                if type(v) == "number" and not IsSecret(v) then score = v end
            end
            if score and score > 0 then
                p.mythicScore = score
                if self.scoreCache then self.scoreCache[short] = score end
            elseif self.scoreCache and self.scoreCache[short] then
                p.mythicScore = self.scoreCache[short]
            end
        end
    end
end

-- Levels every time; item levels from the cache, or queued for an inspect.
function MS:PopulateAll()
    if not self.currentRun then return end
    self.itemLevelCache = self.itemLevelCache or {}
    local needsInspect = false
    for _, unit in ipairs(self:GroupUnits()) do
        local p = self:PlayerForUnit(unit)
        if p then
            local short = p.name
            -- Character level matters in Forever's levelling dungeons and
            -- can change mid-run, so it's refreshed on every snapshot.
            local lvl = UnitLevel and UnitLevel(unit)
            if type(lvl) == "number" and not IsSecret(lvl) and lvl > 0 then
                p.level = lvl
            end
            local cached = self.itemLevelCache[short]
            if cached and cached > 0 then p.itemLevel = cached end
            local needSpec = false
            if unit == "player" then
                p.specID = OwnSpec() or p.specID
            elseif self.specCache[short] then
                p.specID = self.specCache[short]
            elseif p.specID then
                self.specCache[short] = p.specID      -- known before a /reload
            else
                needSpec = HAS_SPECS
            end
            if (not (cached and cached > 0) or needSpec) and not inspectPending then
                local already = false
                for _, e in ipairs(inspectQueue) do
                    if e.name == short then already = true; break end
                end
                if not already then
                    _ins(inspectQueue, { name = short })
                    needsInspect = true
                end
            end
        end
    end
    if needsInspect then Later(function() self:_ProcessInspectQueue() end) end
end

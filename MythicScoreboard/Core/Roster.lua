-- Who is in the run, and how to find them.
--
-- Every other file finds a group member through the lookups at the bottom of
-- this file, never by indexing run.players with a name it built itself. That
-- keeps the rules in one place: a GUID match wins over a name, names are
-- normalised the same way everywhere, and hidden (secret) values are never
-- stored.
--
-- run.players is keyed by MS.ShortName(name) so saved runs from older
-- versions still load; each entry also carries the player's GUID once known.

local MS = _G["MythicScoreboard"]
local _issecret = issecretvalue  -- nil on pre-12.0 clients

-- ── Readable values ────────────────────────────────────────────────────────
-- A value the addon may read and store: present, not secret, a non-empty string.
local function Readable(v)
    if v == nil or (_issecret and _issecret(v)) or type(v) ~= "string" or v == "" then return nil end
    return v
end
MS.Readable = Readable

-- Readable GUID for a unit, or nil.
local function UnitGUIDReadable(unit)
    local ok, g = pcall(UnitGUID, unit)
    return ok and Readable(g) or nil
end
MS.UnitGUIDReadable = UnitGUIDReadable

MS.ValidClass = {
    WARRIOR=true, PALADIN=true,  HUNTER=true,  ROGUE=true,   PRIEST=true,
    DEATHKNIGHT=true, SHAMAN=true, MAGE=true,  WARLOCK=true, MONK=true,
    DRUID=true, DEMONHUNTER=true, EVOKER=true,
}

-- ── Names ──────────────────────────────────────────────────────────────────
-- Realms seen this session, as they appear in "Name-Realm" strings
-- (spaces and apostrophes removed), lower-cased.
local _knownRealms = {}
local function RealmKey(r) return (r:gsub("[%s']", "")):lower() end
function MS:NoteRealm(realm)
    realm = Readable(realm)
    if realm then _knownRealms[RealmKey(realm)] = true end
end

-- The key a player is stored under.
-- Retail: the name without its realm ("Jay-Stormrage" -> "Jay").
-- Forever: characters have two-part names ("Jay Breezy", which some APIs
-- give as "Jay-Breezy"), so the whole name is kept, with a hyphen between
-- the parts, and only a realm suffix is removed.
local function ShortName(name)
    if type(name) ~= "string" or (_issecret and _issecret(name)) then return name end
    if not MS.Flavor.twoPartNames then return name:match("^([^%-]+)") or name end
    local n = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "-")
    local base, last = n:match("^(.-)%-([^%-]+)$")
    if base and base ~= "" then
        local own = GetRealmName and GetRealmName()
        if own and own ~= "" then _knownRealms[RealmKey(own)] = true end
        local _, hyphens = n:gsub("%-", "")
        if _knownRealms[last:lower()] or hyphens >= 2 then n = base end
    end
    return n
end
MS.ShortName = ShortName

-- A group member's name as the addon stores it.
-- On Forever, UnitName returns (first name, surname): the second value is
-- the surname, not a realm. Retail returns (name, realm-or-nil).
function MS:UnitPlayerName(unit)
    local first, second = UnitName(unit)
    first = Readable(first)
    if not first then return nil end
    if MS.Flavor.twoPartNames then
        second = Readable(second)
        if second then return first .. "-" .. second end
        local ok, full = pcall(GetUnitName, unit, true)
        full = ok and Readable(full)
        if full then return ShortName(full) end
    end
    return first
end

-- How a stored name is shown: Forever's two parts with a space.
function MS.DisplayName(name)
    if MS.Flavor.twoPartNames and type(name) == "string" then
        return (name:gsub("%-", " "))
    end
    return name
end

-- ── Group units ────────────────────────────────────────────────────────────
local _groupUnits      = {}
local _groupUnitsDirty = true

function MS:RebuildGroupUnitsCache()
    wipe(_groupUnits)
    _groupUnits[1] = "player"
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do _groupUnits[#_groupUnits + 1] = prefix .. i end
    _groupUnitsDirty = false
end

function MS:GroupUnits()
    if _groupUnitsDirty then self:RebuildGroupUnitsCache() end
    return _groupUnits
end

function MS:InvalidateGroupUnits()
    _groupUnitsDirty = true
end

-- Group unit ("player", "party2", ...) whose GUID is guid, or nil.
function MS:UnitForGUID(guid)
    if not guid then return nil end
    for _, unit in ipairs(self:GroupUnits()) do
        if UnitGUIDReadable(unit) == guid then return unit end
    end
end

-- ── Finding a player in a run ──────────────────────────────────────────────
local function Players(run)
    run = run or MS.currentRun
    return run and run.players
end

-- By any form of their name: "Jay", "Jay-Breezy", "Jay Breezy", "Jay-Realm".
-- On Forever a first name alone ("Jay") matches when only one player in the
-- run has it, since some messages leave the surname out.
function MS:PlayerByName(name, run)
    local players = Players(run)
    name = Readable(name)
    if not (players and name) then return nil end
    local key = ShortName(name)
    if players[key] then return players[key] end
    if MS.Flavor.twoPartNames and not key:find("%-") then
        local found
        for k, p in pairs(players) do
            if k:match("^([^%-]+)") == key then
                if found then return nil end      -- two players named Jay: don't guess
                found = p
            end
        end
        return found
    end
end

-- By GUID: the GUIDs stored on the run first, then the live roster.
function MS:PlayerByGUID(guid, run)
    local players = Players(run)
    guid = Readable(guid)
    if not (players and guid) then return nil end
    for _, p in pairs(players) do
        if Readable(p.guid) == guid then return p end
    end
    local unit = self:UnitForGUID(guid)
    local p = unit and self:PlayerByName(self:UnitPlayerName(unit), run)
    if p then p.guid = guid end
    return p
end

-- For a unit token: by GUID when the game shows it, otherwise by name.
function MS:PlayerForUnit(unit, run)
    return self:PlayerByGUID(UnitGUIDReadable(unit), run) or self:PlayerByName(self:UnitPlayerName(unit), run)
end

-- For a C_DamageMeter source. Nil for pets, guardians and anyone not in the
-- group. GUID first: other players' names can be hidden, or formatted
-- differently from UnitName (Forever's two-part names).
function MS:PlayerForMeterSource(src, run)
    local guid = Readable(src.sourceGUID)
    if guid and not guid:find("^Player%-") then return nil end
    local isLocal = src.isLocalPlayer
    if _issecret and isLocal ~= nil and _issecret(isLocal) then isLocal = nil end

    local p = (isLocal and self:PlayerForUnit("player", run))
        or (guid and self:PlayerByGUID(guid, run))
        or self:PlayerByName(src.name, run)
    if not p then return nil end

    local cls = Readable(src.classFilename)
    cls = cls and cls:upper()
    if cls and MS.ValidClass[cls] then p.class = cls end
    p.guid = guid or (isLocal and UnitGUIDReadable("player")) or p.guid
    return p
end

-- Adds a group unit to the current run if missing, and refreshes what may
-- have changed (GUID, class, whether they left). Returns the player.
function MS:EnsurePlayer(unit)
    local run = self.currentRun
    if not run or not UnitIsPlayer(unit) then return nil end
    -- On Forever the second value is a surname, never a realm.
    if not MS.Flavor.twoPartNames then self:NoteRealm((select(2, UnitName(unit)))) end
    local uname = self:UnitPlayerName(unit)
    if not uname then return nil end
    local p = self:PlayerForUnit(unit)
    if not p then
        local _, cls = UnitClass(unit)
        cls = Readable(cls)
        cls = (cls and MS.ValidClass[cls:upper()]) and cls:upper() or "UNKNOWN"
        local key = ShortName(uname)
        p = MS.NewPlayerStats(key, cls, UnitGUIDReadable(unit))
        run.players[key] = p
    end
    p.guid = UnitGUIDReadable(unit) or p.guid
    p.left = nil
    return p
end

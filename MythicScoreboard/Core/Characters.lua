-- Who you are, account-wide: this character's key (name@realm) in
-- MythicScoreboardAccountDB.chars, worked out even when the game won't say
-- the realm, and which character the Stats page shows. The archive
-- (Archive.lua) keeps each character's runs under this key.

local MS = _G["MythicScoreboard"]

local Plain = MS.ReadableValue

-- The account's saved data, with its table of characters.
function MS.AccountWithChars()
    local acc = MS.AccountDB(true)
    if type(acc.chars) ~= "table" then acc.chars = {} end
    return acc
end

local Account = MS.AccountWithChars

-- name@realm, or nil until your name's known. When the game won't say the
-- realm (WoW Forever, at times for a whole session): the key this character
-- was saved under before, if there's just one; else "Name@". (An earlier
-- version made "Name@" alongside the real one: SyncAccountStats folds it in.)
-- A realm an earlier version saved by mistake: none, or (2.17.1, for a
-- moment) your WoW Forever surname ("Jay-Breezy@Breezy").
local function WrongRealm(name, realm)
    return type(realm) ~= "string" or realm == "" or realm == (name or ""):match("%-(.+)$")
end

local function CharKey()
    local name = Plain(MS.UnitPlayerName and MS:UnitPlayerName("player") or UnitName("player"))
    if type(name) ~= "string" or name == "" then return nil end
    local realm = MS.PlayerRealm()
    if realm then return name .. "@" .. realm, name, realm end
    local acc = MS.AccountDB and MS.AccountDB()
    local _, cls = UnitClass("player")
    cls = Plain(cls)
    local found
    for key, c in pairs(acc and type(acc.chars) == "table" and acc.chars or {}) do
        if c.name == name and not WrongRealm(name, c.realm) and (not cls or not c.class or c.class == cls) then
            if found then return name .. "@", name, "" end      -- (two: can't tell which)
            found = key
        end
    end
    if found then return found, name, acc.chars[found].realm end
    return name .. "@", name, ""
end

MS.WrongRealm, MS.CharKeyNow = WrongRealm, CharKey
MS._CharKeyNow = function() return (CharKey()) end   -- for tests

-- This character's key (name@realm), once known (set by Archive.lua's Store and
-- SyncAccountStats).
local _charKey
function MS:CharKey() return _charKey end

function MS:SetCharKey(key) _charKey = key end

-- "all", or one character's key.
function MS:GetStatsChar()
    local want = Account().statsChar or "all"
    if want ~= "all" and not Account().chars[want] then want = "all" end
    return want
end
function MS:SetStatsChar(key) Account().statsChar = key; MS.BumpStats() end


function MS:CharacterInfo(key) return key and Account().chars[key] end


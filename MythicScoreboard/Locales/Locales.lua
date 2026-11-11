-- Translations.
--
-- Every piece of text the addon shows goes through MS.L, keyed by its
-- English wording: L["Deaths"], L["Killed at %s"]. A key with no
-- translation for the player's language shows in English.
--
-- Each language has its own file in this folder (deDE.lua, frFR.lua, ...),
-- registered with MS.NewLocale. Once the addon has loaded, the client's
-- language is put to use (or the one picked with /sb lang, to preview
-- another) and the rest are let go. Until then L shows English, so labels
-- defined while loading are written LK("...") and translated where shown.
--
-- A key can carry a note after "#" when one English word needs different
-- translations in different places: L["Cleared#column"] shows "Cleared" in
-- English, but a language can give the column header a shorter word.
--
-- Counts go through MS.Plural(n, "%d run", "%d runs"), since languages
-- form plurals differently: a language file can set MS.PluralRule, and
-- give a third form under "<plural key>|few" (Russian: 2-4 and 22-24...).

local MS = _G["MythicScoreboard"]

MS.ClientLocale = (GetLocale and GetLocale()) or "enUS"
if MS.ClientLocale == "enGB" then MS.ClientLocale = "enUS" end
MS.Locale = MS.ClientLocale             -- the language shown (UseLocale)

local T = {}                            -- the language shown
MS.Translations = T
MS.LocaleData = {}                      -- every language, until UseLocale

-- A language file's table: MS.NewLocale("deDE", "english") (plural rule from
-- MS.PluralRules); `also` is another locale that shares it (esMX).
function MS.NewLocale(loc, rule, also)
    local data = { T = {}, rule = rule }
    MS.LocaleData[loc] = data
    if also then MS.LocaleData[also] = data end
    return data.T
end

-- An English label kept as is while loading; L[label] where it's shown.
function MS.LK(s) return s end

-- Looked up before the language is settled (while files load): English for
-- good, whatever the language. Kept so a test can catch it (use LK instead).
MS._earlyLookups = {}
MS.L = setmetatable({}, {
    __index = function(_, key)
        local early = MS._earlyLookups
        if early then early[#early + 1] = key end
        local v = T[key]
        if v == nil or v == "" then
            -- "Cleared#column": the same English, a translation of its own
            -- (a short one for a narrow column); shown as the part before #.
            return (key:gsub("#.*$", ""))
        end
        return v
    end,
    __newindex = function() error("MS.L is read-only: add translations to MS.Translations") end,
})

-- "one" | "few" | "other" for a count.
local function EnglishRule(n) return n == 1 and "one" or "other" end
MS.PluralRule = EnglishRule

-- A count with its noun: Plural(3, "%d run", "%d runs") -> "3 runs".
-- shown: what to put in place of the number (a coloured "3"), if not n.
function MS.Plural(n, one, other, shown)
    n = n or 0
    local form = MS.PluralRule(n)
    local text
    if form == "few" then text = T[other .. "|few"] end
    if not text or text == "" then
        local key = (form == "one") and one or other
        text = T[key]
        if not text or text == "" then text = key end
    end
    shown = tostring(shown or n)
    return (text:gsub("%%d", function() return shown end))
end

-- Puts a language to use: `loc` (a /sb lang preview), else the client's.
-- Called once, when the addon has loaded; the other languages are let go.
function MS:UseLocale(loc)
    local all = MS.LocaleData or {}
    if loc == "enGB" then loc = "enUS" end
    if not loc or (loc ~= "enUS" and not all[loc]) then loc = MS.ClientLocale end
    for k in pairs(T) do T[k] = nil end
    local data = all[loc]
    if data then for k, v in pairs(data.T) do T[k] = v end end
    MS.PluralRule = (data and MS.PluralRules[data.rule]) or MS.PluralRules.english
    MS.Locale = loc
    MS.LocaleData = nil
    MS._earlyLookups = nil
    return loc
end

-- The languages there are translations for (/sb lang).
MS.LOCALES = { "enUS", "deDE", "frFR", "esES", "esMX", "ptBR", "itIT", "ruRU", "koKR", "zhCN", "zhTW" }

-- Rules languages use (a language file picks one).
MS.PluralRules = {
    english = EnglishRule,
    -- French: 0 and 1 are singular.
    french  = function(n) return (n == 0 or n == 1) and "one" or "other" end,
    -- Russian: 1, 21, 31... one; 2-4, 22-24... few; the rest other.
    russian = function(n)
        local m10, m100 = n % 10, n % 100
        if m10 == 1 and m100 ~= 11 then return "one" end
        if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then return "few" end
        return "other"
    end,
    -- Korean and Chinese: no plural.
    none    = function() return "other" end,
}

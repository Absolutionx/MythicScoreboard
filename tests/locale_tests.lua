-- usage: lua5.1 locale_tests.lua DIR TOC   (translations: coverage, placeholders, plurals, a translated UI)
table.unpack = table.unpack or unpack
local DIR, TOC = arg[1], arg[2]
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function read(path) local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s end

local LOCALES = { "deDE", "frFR", "esES", "esMX", "ptBR", "itIT", "ruRU", "koKR", "zhCN", "zhTW" }
-- Fine left in English: the addon's name, number suffixes, meter terms.
local ENGLISH_OK = { ["Mythic Scoreboard"] = true, B = true, M = true, K = true, DPS = true, HPS = true,
                     ["%dm"] = true, ["%dh %02dm"] = true, Boss = true, Trash = true, Live = true, ["Quest %s"] = true,
                     ["Trash 1"] = true, ["Trash 2"] = true, ["Wipe"] = true, ["(wipe)"] = true, ["Dungeons"] = true,
                     ["Dungeon"] = true, ["Normal"] = true, ["XP"] = true, ["%s XP"] = true, ["TW"] = true,
                     ["/sb to open."] = true }

-- ── The keys the code uses ─────────────────────────────────────────────────
local keys, plurals = {}, {}
local files = {}                       -- both clients' files
for _, toc in ipairs({ "MythicScoreboard.toc", "MythicScoreboard_Forever.toc" }) do
    for line in io.lines(DIR .. "/" .. toc) do
        line = line:gsub("\r", ""):gsub("\\", "/")
        if line ~= "" and not line:find("^#") and not line:find("^Locales") then files[line] = true end
    end
end
local list = {}; for f in pairs(files) do list[#list + 1] = f end
table.sort(list); files = list
for _, f in ipairs(files) do
    local src = read(DIR .. "/" .. f)
    for k in src:gmatch('L%["(.-)"%]') do keys[k] = true end
    for k in src:gmatch('LK%("(.-)"%)') do keys[k] = true end          -- labels translated where shown
    for one, other in src:gmatch('MS%.Plural%([^,]-,%s*"(.-)",%s*"(.-)"') do
        keys[one], keys[other] = true, true
        plurals[#plurals + 1] = { one, other }
    end
end
-- Difficulty labels are stored in English and translated where shown.
local blk = read(DIR .. "/Core/Lifecycle.lua"):match("local DIFF_LABEL = (%b{})")
for v in blk:gmatch('="(.-)"') do keys[v] = true end
local nKeys = 0; for _ in pairs(keys) do nKeys = nKeys + 1 end
check("found the keys", nKeys > 200, nKeys)
check("found the plurals", #plurals >= 15, #plurals)

local function Placeholders(s)
    local out = {}
    for p in s:gmatch("%%[%-%d%.]*[sdf]") do out[#out + 1] = p end
    return table.concat(out, " ")
end
local function Count(s, pat) local _, n = s:gsub(pat, ""); return n end
local function DummyArgs(s)
    local a = {}
    for p in s:gmatch("%%[%-%d%.]*([sdf])") do a[#a + 1] = (p == "s") and "x" or 3 end
    return a
end

-- ── Each language on its own ───────────────────────────────────────────────
-- Every language file loads (as in the game); then one is put to use.
local FILES = { "deDE", "frFR", "esES", "ptBR", "itIT", "ruRU", "koKR", "zhCN", "zhTW" }
local function LoadLocale(client, use)
    local saved = rawget(_G, "MythicScoreboard")
    local MS = {}
    _G.MythicScoreboard = MS
    GetLocale = function() return client end
    dofile(DIR .. "/Locales/Locales.lua")
    for _, f in ipairs(FILES) do
        local ok, err = pcall(dofile, DIR .. "/Locales/" .. f .. ".lua")
        check(f .. ": loads", ok, err)
    end
    check(client .. ": English while loading", next(MS.Translations) == nil)
    MS:UseLocale(use)
    _G.MythicScoreboard = saved
    return MS
end

local MODE = arg[3]                    -- set when run for the whole-addon part only
for _, loc in ipairs(MODE and {} or LOCALES) do
    local MS = LoadLocale(loc)
    local T = MS.Translations
    local n, missing = 0, {}
    for k, v in pairs(T) do
        local base = k:gsub("|few$", "")
        n = n + 1
        check(loc .. ": key used by the code: " .. k, keys[base])
        check(loc .. ": text for " .. k, type(v) == "string" and v ~= "")
        if keys[base] and type(v) == "string" then
            check(loc .. ": placeholders in " .. k, Placeholders(v) == Placeholders(base),
                Placeholders(v) .. " vs " .. Placeholders(base))
            check(loc .. ": colour codes in " .. k, Count(v, "|c%x%x%x%x%x%x%x%x") == Count(base, "|c%x%x%x%x%x%x%x%x")
                and Count(v, "|r") == Count(base, "|r"))
            if Placeholders(base) ~= "" then
                local ok, err = pcall(string.format, v, table.unpack(DummyArgs(base)))
                check(loc .. ": formats " .. k, ok, err)
            end
        end
    end
    for k in pairs(keys) do
        if T[k] == nil and not ENGLISH_OK[k] then missing[#missing + 1] = k end
    end
    table.sort(missing)
    check(loc .. ": everything translated", #missing == 0, #missing .. " missing: " .. table.concat(missing, " | ", 1, math.min(#missing, 8)))
    if loc == "ruRU" and n > 0 then
        check("ruRU: Russian plurals", MS.PluralRule == MS.PluralRules.russian)
        for _, p in ipairs(plurals) do
            check("ruRU: few form of " .. p[2], T[p[2] .. "|few"] ~= nil)
        end
        check("ruRU: 1 run", MS.Plural(1, "%d run", "%d runs") == T["%d run"]:gsub("%%d", "1"))
        check("ruRU: 3 runs (few)", MS.Plural(3, "%d run", "%d runs") == T["%d runs|few"]:gsub("%%d", "3"))
        check("ruRU: 5 runs", MS.Plural(5, "%d run", "%d runs") == T["%d runs"]:gsub("%%d", "5"))
        check("ruRU: 21 runs (one)", MS.Plural(21, "%d run", "%d runs") == T["%d run"]:gsub("%%d", "21"))
        check("ruRU: 12 runs (other)", MS.Plural(12, "%d run", "%d runs") == T["%d runs"]:gsub("%%d", "12"))
    end
    if loc == "koKR" or loc == "zhCN" or loc == "zhTW" then
        check(loc .. ": no plural", MS.PluralRule == MS.PluralRules.none)
    end
    if loc == "frFR" then check("frFR: French plurals", MS.Plural(0, "%d run", "%d runs") == T["%d run"]:gsub("%%d", "0")) end
end

if not MODE then
    -- An English client: English, and the others let go.
    local MS = LoadLocale("enUS")
    check("enUS: no translations", next(MS.Translations) == nil)
    check("enUS: falls back to the key", MS.L["Deaths"] == "Deaths")
    check("enUS: plural", MS.Plural(1, "%d run", "%d runs") == "1 run" and MS.Plural(2, "%d run", "%d runs") == "2 runs")
    check("enUS: others let go", MS.LocaleData == nil)
    check("read-only", not pcall(function() MS.L.x = 1 end))
    check("LK keeps English", MS.LK("Deaths") == "Deaths")
    -- A preview on an English client.
    local P = LoadLocale("enUS", "deDE")
    check("preview: German", P.Locale == "deDE" and P.ClientLocale == "enUS" and P.L["Deaths"] == "Tode")
    local Pm = LoadLocale("enUS", "esMX")
    check("preview: esMX shares esES", Pm.Locale == "esMX" and Pm.L["Deaths"] == "Muertes")
    local B = LoadLocale("deDE", "xxXX")
    check("unknown language: the client's", B.Locale == "deDE" and B.L["Deaths"] == "Tode")
    local R = LoadLocale("ruRU", "enUS")
    check("preview English on a Russian client", R.Locale == "enUS" and R.L["Deaths"] == "Deaths"
        and R.Plural(3, "%d run", "%d runs") == "3 runs")
    -- The whole addon, as a preview on an English client.
    local ok = os.execute(("lua5.1 locale_tests.lua %s %s preview"):format(DIR, TOC))
    check("whole addon: preview on an English client", ok == 0 or ok == true)
end

-- ── The whole addon on a Russian client (or previewed on an English one) ────
local PREVIEW = (MODE == "preview")
local Mk = dofile("wowmock.lua")
GetLocale = function() return PREVIEW and "enUS" or "ruRU" end
Mk.LoadTOC(DIR, TOC)
local A = rawget(_G, "MythicScoreboard")
-- Nothing is translated while the files load: the language isn't settled
-- until ADDON_LOADED, so a label made then stays English (LK is for those).
check("no translations looked up while loading", A._earlyLookups and #A._earlyLookups == 0,
    A._earlyLookups and table.concat(A._earlyLookups, " | "))
check("English while loading", A.L["Deaths"] == "Deaths")
local clock = 1800000000
time = function() return clock end
local Mforever = (TOC:find("Forever") ~= nil)
MythicScoreboardDB, MythicScoreboardAccountDB = nil, PREVIEW and { previewLocale = "ruRU" } or nil
Mk.Fire("ADDON_LOADED", "MythicScoreboard")
check("ruRU: locale", A.Locale == "ruRU", A.Locale)
check("ruRU: translated", A.L["Deaths"] ~= "Deaths")
check("ruRU: plural rule", A.Plural(3, "%d run", "%d runs") == A.Translations["%d runs|few"]:gsub("%%d", "3"))
local inst = Mforever and { "Ragefire Chasm", "party", 1 } or { "Ragefire Chasm", "party", 8 }
if not Mforever then
    C_ChallengeMode = {
        GetActiveChallengeMapID = function() return 2526 end,
        GetActiveKeystoneInfo = function() return 12, {}, 1800 end,
        GetMapInfo = function() return { name = "Ragefire Chasm" } end,
    }
end
Mk.instance = inst; Mk.Fire("PLAYER_ENTERING_WORLD", false, false); Mk.Fire("ZONE_CHANGED_NEW_AREA"); Mk.RunTimers(8)
if not Mforever then Mk.Fire("CHALLENGE_MODE_START", 2526); Mk.RunTimers(3) end
check("ruRU: run started", A.currentRun ~= nil)
local ok, err = pcall(function()
    A:ShowScoreboard(); Mk.RunTimers(2)
    A.UI.OpenStats()
    Mk.RunTimers(2)
end)
check("ruRU: the windows draw", ok, err)
do  -- The addon's own fonts have no Cyrillic: the game's font in a Russian
    -- client, the game's Cyrillic font for a preview on an English one.
    local title = MythicScoreboardFrame and MythicScoreboardFrame.DungeonName
    local path = title and title._fontPath or ""
    if PREVIEW then check("preview: Cyrillic font", path:find("CYR") ~= nil, path)
    else check("ruRU client: game font", path == "font", path) end
end

-- Forever in Russian: the dungeon is found by its instance ID, and with the
-- bosses' names not matching the English ones, it's cleared by boss count.
if Mforever and not PREVIEW then
    local function wait(sec) Mk.now = Mk.now + sec; clock = clock + sec end
    Mk.instance = { "Orgrimmar", "none", 0 }; Mk.Fire("PLAYER_ENTERING_WORLD", false, false); Mk.Fire("ZONE_CHANGED_NEW_AREA"); Mk.RunTimers(8)
    A:AbandonRun()
    Mk.instance = { "Огненная пропасть", "party", 1, 389 }
    Mk.Fire("PLAYER_ENTERING_WORLD", false, false); Mk.Fire("ZONE_CHANGED_NEW_AREA"); Mk.RunTimers(8)
    local run = A.currentRun
    check("ruRU Forever: run", run ~= nil and run.dungeonName == "Огненная пропасть", run and run.dungeonName)
    local lo, hi = A:ForeverLevelRange(run)
    check("ruRU Forever: found by instance ID", lo == 13 and hi == 18, lo)
    check("ruRU Forever: can be cleared", A:ForeverCanDetectClear(run))
    local names = { "Огглфлинт", "Тарагаман Ненасытный", "Джергош Призыватель", "Баззалан" }
    for i, nm in ipairs(names) do
        Mk.Fire("ENCOUNTER_START", i, nm); wait(30); Mk.Fire("ENCOUNTER_END", i, nm, 1, 5, 1); Mk.RunTimers(4)
        if i == 3 then
            local k, n = A:ForeverBossProgress(run)
            check("ruRU Forever: 3 of 4", k == 3 and n == 4, tostring(k) .. "/" .. tostring(n))
            check("ruRU Forever: not cleared at 3", not run.completed)
        end
    end
    check("ruRU Forever: cleared at 4 bosses", run.completed == true)
end

-- Names in another script on a Latin client get a game font that has the letters.
local UI = A.UI
check("script: Cyrillic", UI.ScriptOf("Ёжик") == "cyrillic")
check("script: Hangul", UI.ScriptOf("홍길동") == "hangul")
check("script: Han", UI.ScriptOf("张三") == "han")
check("script: Latin", UI.ScriptOf("Thrallé") == nil)

io.stdout:write(("locale_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

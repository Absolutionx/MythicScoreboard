-- Small helpers every other file uses. Loaded right after MythicScoreboard.lua.

local MS = _G["MythicScoreboard"]
local _floor = math.floor
local _unpack = unpack
local IsSecret = MS.IsSecret

-- ── Readable values ────────────────────────────────────────────────────────
-- MS.ReadableValue(v) (MythicScoreboard.lua): v, or nil when the game hides it.

-- A number, or nil when hidden or not a number.
function MS.ReadableNumber(v)
    if v == nil or IsSecret(v) then return nil end
    return tonumber(v)
end

-- A non-empty string (a name, a GUID), or nil.
function MS.Readable(v)
    if v == nil or IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

-- The nearest whole number; anything not a number counts as 0.
function MS.Round(n) return _floor((tonumber(n) or 0) + 0.5) end

-- ── Chat ───────────────────────────────────────────────────────────────────
local TAG, WARN_TAG = "|cff00ccff[MythicScoreboard]|r ", "|cffff4444[MythicScoreboard]|r "
function MS.Say(msg) print(TAG .. tostring(msg)) end
function MS.Warn(msg) print(WARN_TAG .. tostring(msg)) end

-- ── Account-wide saved data ────────────────────────────────────────────────
-- MythicScoreboardAccountDB, or nil before the game has loaded it. With
-- create, it's made if missing (only once saved variables are in).
function MS.AccountDB(create)
    local acc = rawget(_G, "MythicScoreboardAccountDB")
    if type(acc) == "table" then return acc end
    if not create then return nil end
    MythicScoreboardAccountDB = {}
    return MythicScoreboardAccountDB
end

-- ── The game's chat lines as patterns ──────────────────────────────────────
-- A localized format string ("%s receives loot: %s.", or "%2$s ... %1$s" in
-- a language that swaps them) turned into a Lua pattern once; MatchFormat
-- then hands the values back in the format's own order, whatever order a
-- language writes them in.
--   how = nil       the whole line
--         "start"   the line starts with it (something may follow)
--         "prefix"  only up to the first number (the rest varies: rested,
--                   group bonus), so the values before it
-- Returns { pattern = "...", order = { argument index per capture }, n }.
local MAGIC = "^$()%.[]*+-?"
function MS.FormatPattern(fmt, how)
    if type(fmt) ~= "string" or IsSecret(fmt) then return nil end
    local out, order, nextArg, i = { "^" }, {}, 0, 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        if c == "%" then
            local _, e, argN, conv = fmt:find("^%%(%d)%$([sdf])", i)
            if not e then
                _, e, conv = fmt:find("^%%[%d%.]*([sdf])", i)
            end
            if e then
                if how == "prefix" and conv ~= "s" then break end
                local arg = tonumber(argN)
                if not arg then nextArg = nextArg + 1; arg = nextArg end
                order[#order + 1] = arg
                out[#out + 1] = (conv == "s") and "(.+)" or (conv == "d") and "(%d+)" or "([%d%.]+)"
                i = e + 1
            else
                if fmt:sub(i + 1, i + 1) == "%" then i = i + 1 end   -- "%%" is a literal %
                out[#out + 1] = "%%"
                i = i + 1
            end
        else
            out[#out + 1] = MAGIC:find(c, 1, true) and ("%" .. c) or c
            i = i + 1
        end
    end
    if how == nil then out[#out + 1] = "$" end
    local n = 0
    for _, a in ipairs(order) do if a > n then n = a end end
    return { pattern = table.concat(out), order = order, n = n }
end

-- The format's values out of a line (in the format's argument order), or nil.
function MS.MatchFormat(text, fp)
    if not (fp and type(text) == "string") or IsSecret(text) then return nil end
    local caps = { text:match(fp.pattern) }
    if caps[1] == nil then return nil end
    local args = {}
    for k, a in ipairs(fp.order) do args[a] = caps[k] end
    return _unpack(args, 1, fp.n)
end

-- ── Game events ────────────────────────────────────────────────────────────
-- Every file listens through here: MS:On(event, fn) calls fn(event, ...)
-- for each one, in the order files asked; MS:Off(event, fn) stops it. A
-- handler that errors is reported once (MS:ReportError) and the others still
-- run. Events a client doesn't have are skipped quietly. RegisterEvent isn't
-- a protected call, so this works in combat too.
local hub = CreateFrame("Frame")
local subs = {}   -- event -> list of fn (replaced, never changed, so a dispatch in progress is safe)

function MS:On(event, fn)
    local list = subs[event] or {}
    for _, f in ipairs(list) do if f == fn then return end end
    local copy = { unpack(list) }
    copy[#copy + 1] = fn
    if #list == 0 then pcall(hub.RegisterEvent, hub, event) end
    subs[event] = copy
end

function MS:Off(event, fn)
    local list = subs[event]
    if not list then return end
    local copy = {}
    for _, f in ipairs(list) do if f ~= fn then copy[#copy + 1] = f end end
    if #copy == 0 then
        subs[event] = nil
        pcall(hub.UnregisterEvent, hub, event)
    else
        subs[event] = copy
    end
end

hub:SetScript("OnEvent", function(_, event, ...)
    local list = subs[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then MS:ReportError(event, err) end
    end
end)

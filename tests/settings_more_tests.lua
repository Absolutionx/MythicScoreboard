-- usage: lua5.1 settings_more_tests.lua DIR TOC
-- The settings pages' newer rows: the in-run frame's style, size and lock;
-- on WoW Forever the directions and the blacklist's warnings.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local UI = MS.UI
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4)
local forever = MS.FLAVOR == "forever"
MS:BuildUI()
local pop = UI.frame.SettingsPopup
local function page(title)
    for i, e in ipairs(pop.nav) do if e.label._text == title then pop.nav[i]:GetScript("OnClick")(pop.nav[i]); return pop.pages[i] end end
end

-- ── In-run frame: style, size, lock ───────────────────────────────────────
local ip = page("In-run frame")
check("in-run page: its style choices", ip and ip.choices and #ip.choices == 3, ip and ip.choices and #ip.choices)
local compactRow
for _, c in ipairs(ip.choices) do if c.label._text == "Compact" then compactRow = c end end
compactRow:GetScript("OnClick")(compactRow)
check("style: picked from settings", MS:GetCompactStyle() == "compact")
MS:SetCompactFrame(false)
check("style: none while the frame is off", MS:GetCompactStyle() == "off")
compactRow:GetScript("OnClick")(compactRow)
check("style: picking one turns the frame on", MS:GetCompactFrame() and MS:GetCompactStyle() == "compact")

MS:ToggleCompactPreview(); M.RunTimers(2)
local cf = rawget(_G, "MythicScoreboardCompact")
check("preview up", cf and cf._shown)
MS:SetCompactStyle("minimal"); M.RunTimers(1)
check("style from settings: the preview shows it", UI._CompactShownStyle() == "minimal", UI._CompactShownStyle())
MS:SetCompactStyle("detailed"); M.RunTimers(1)
MS:SetCompactScale(1.2); M.RunTimers(1)
check("frame size: the frame follows", math.abs(cf:GetScale() - 1.2) < 0.01, cf:GetScale())
ip.CompactResetBtn:GetScript("OnClick")(ip.CompactResetBtn)
check("reset size: 100%", MS:GetCompactScale() == 1 and math.abs(cf:GetScale() - 1) < 0.01)
local moved = false
local sm = cf.StartMoving
cf.StartMoving = function() moved = true end
MS:SetCompactLocked(true)
cf:GetScript("OnDragStart")(cf)
check("locked: not dragged", not moved)
check("locked: no resize corner", not cf.ResizeGrip._shown)
MS:SetCompactLocked(false)
cf:GetScript("OnDragStart")(cf)
check("unlocked: dragged", moved)
check("unlocked: the corner again (preview)", cf.ResizeGrip._shown)
cf.StartMoving = sm
MS:ToggleCompactPreview(); M.RunTimers(2)

if forever then
    -- ── Directions ─────────────────────────────────────────────────────────
    check("directions page: its rows", page("Directions") ~= nil)
    local e = MS.ForeverData.ENTRANCES[1]
    local any = #MS:EntrancePins(e.map) > 0
    MS:SetMapEntrances(false)
    check("entrances off: none on the map", any and #MS:EntrancePins(e.map) == 0)
    MS:SetMapEntrances(true)
    MS:SetRouteJumps(false)
    check("hearth and teleports off: none used", #MS:Jumps() == 0)
    MS:SetRouteJumps(true)
    MS:SetMapRoute(false)
    check("route off: nothing drawn", MS:RouteOnMap(e.map) == nil)
    MS:SetMapRoute(true)
    -- The arrow: off leaves the steps.
    MS:NavigateTo({ name = "Ragefire Chasm", map = e.map, x = e.x, y = e.y })
    local arrow = rawget(_G, "MythicScoreboardArrow")
    MS:SetNavArrow(false)
    MS:UpdateArrow()
    check("arrow off: no arrow, the frame stays", arrow._shown and not arrow.arrow._shown)
    MS:SetNavArrow(true)
    MS:StopNavigation()

    -- ── Blacklist: how to warn ─────────────────────────────────────────────
    check("blacklist page", page("Blacklist") ~= nil)
    MS:AddToBlacklist("Grimy", nil, "ninja", "ROGUE")
    local notices, sounds = 0, 0
    rawset(_G, "RaidWarningFrame", {})
    rawset(_G, "RaidNotice_AddMessage", function() notices = notices + 1 end)
    rawset(_G, "SOUNDKIT", { RAID_WARNING = 8959 })
    rawset(_G, "PlaySound", function() sounds = sounds + 1 end)
    local function invite()
        local before = #M.printed
        notices, sounds = 0, 0
        MS:OnGroupInvite("Grimy")
        return #M.printed > before
    end
    local chat = invite()
    check("warn: chat, screen and sound", chat and notices == 1 and sounds == 1)
    MS:SetBlacklistChat(false); MS:SetBlacklistScreen(false); MS:SetBlacklistSound(false)
    chat = invite()
    check("warn: each can be turned off", not chat and notices == 0 and sounds == 0)
    MS:SetBlacklistChat(true); MS:SetBlacklistScreen(true); MS:SetBlacklistSound(true)
    check("red border: on by default", MS:GetBlacklistBorder())
end

io.stdout:write((forever and "forever" or "retail") .. ": " .. passes .. " passed, " .. fails .. " failed\n")
os.exit(fails == 0 and 0 or 1)

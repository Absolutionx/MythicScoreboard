-- usage: lua5.1 blacklist_tests.lua DIR TOC
-- The blacklist: who's on it and how they're named, a warning when one is
-- in your group, red names in the group finder, the right-click menus, the
-- note box and the window.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local forever = MS.FLAVOR == "forever"
if not MS.Flavor.blacklist then
    -- Retail: no blacklist at all.
    check("retail: not loaded", MS.AddToBlacklist == nil and MS.ShowBlacklist == nil)
    M.Fire("ADDON_LOADED", "MythicScoreboard"); M.Fire("PLAYER_LOGIN")
    MS:ShowScoreboard()
    SlashCmdList.MYTHICSCOREBOARD("blacklist")
    check("retail: no window", rawget(_G, "MythicScoreboardBlacklistFrame") == nil)
    check("retail: no header button", MS.UI.frame and MS.UI.frame.BlacklistBtn == nil)
    for _, line in ipairs(M.printed or {}) do if line:find("error") then check("no errors", false, line) end end
    io.stdout:write(("blacklist_tests: %d passed, %d failed\n"):format(passes, fails))
    os.exit(fails == 0 and 0 or 1)
end

-- The game's pieces the blacklist hooks into, before login.
local menus = {}
local MenuT = { ModifyMenu = function(tag, fn) menus[tag] = fn end }
function MenuT.PopulateDescription(generator, owner, root) generator(owner, root) end
rawset(_G, "Menu", MenuT)
local tooltipCall
rawset(_G, "Enum", { TooltipDataType = { Unit = 2 } })
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) tooltipCall = fn end }
local warnings, sounds = {}, 0
rawset(_G, "RaidWarningFrame", {})
rawset(_G, "RaidNotice_AddMessage", function(_, text) warnings[#warnings + 1] = text end)
rawset(_G, "SOUNDKIT", { RAID_WARNING = 8959 })
rawset(_G, "PlaySound", function() sounds = sounds + 1 end)
rawset(_G, "UnitIsUnit", function(a, b) return a == b end)

M.Fire("ADDON_LOADED", "MythicScoreboard")
M.Fire("PLAYER_LOGIN")
M.RunTimers(3)

-- ── Names ──────────────────────────────────────────────────────────────────
if forever then
    local k1, d1 = MS.BlacklistKey("Akasha Dawnfire")
    local k2 = MS.BlacklistKey("Akasha-Dawnfire")
    local k3 = MS.BlacklistKey("Akasha", "Dawnfire")
    check("Forever: one key for every form", k1 == "akasha-dawnfire" and k2 == k1 and k3 == k1, tostring(k1) .. " " .. tostring(k2) .. " " .. tostring(k3))
    check("Forever: shown with a space", d1 == "Akasha Dawnfire", d1)
else
    local k1, d1 = MS.BlacklistKey("Akasha")
    local k2 = MS.BlacklistKey("Akasha-Forever")
    local k3 = MS.BlacklistKey("Akasha", "Forever")
    check("retail: your realm when none is given", k1 == "akasha-forever" and k2 == k1 and k3 == k1, tostring(k1) .. " " .. tostring(k2))
    check("retail: shown with the realm", d1 == "Akasha-Forever", d1)
    local k4 = MS.BlacklistKey("Akasha-Area 52")
    local k5 = MS.BlacklistKey("Akasha", "Area52")
    check("retail: realm spaces don't matter", k4 == k5 and k4 == "akasha-area52", tostring(k4))
    check("retail: another realm, another player", k4 ~= k1)
end
check("no name: no key", MS.BlacklistKey(nil) == nil and MS.BlacklistKey("") == nil)

-- ── Adding, the note, removing ─────────────────────────────────────────────
local changes = 0
MS:OnBlacklistChanged(function() changes = changes + 1 end)
local akasha = forever and "Akasha Dawnfire" or "Akasha"
M.printed = {}
MS:AddToBlacklist(akasha, nil, "Left after the first wipe", "MAGE")
local e = MS:BlacklistEntry(akasha)
check("added", e and e.note == "Left after the first wipe" and e.class == "MAGE")
check("the account's", MythicScoreboardAccountDB.blacklist and next(MythicScoreboardAccountDB.blacklist) ~= nil)
check("a change is heard", changes == 1, changes)
MS:AddToBlacklist(akasha, nil, "Left twice")       -- (a new note: not said again)
check("the note changed, nothing else", MS:BlacklistEntry(akasha).note == "Left twice" and MS:BlacklistEntry(akasha).class == "MAGE"
    and #MS:BlacklistEntries() == 1)
check("found by the unit", MS:BlacklistEntryForUnit("party1") == MS:BlacklistEntry(akasha))
check("not someone else", MS:BlacklistEntryForUnit("party2") == nil)
check("never a pet", MS:BlacklistEntryForUnit("party4pet") == nil)

-- ── In your group: a warning, once ─────────────────────────────────────────
-- (Akasha is party1: added while in the group, said straight away.)
M.Fire("GROUP_ROSTER_UPDATE")
local function said(text)
    local n = 0
    for _, line in ipairs(M.printed) do if line:find(text, 1, true) then n = n + 1 end end
    return n
end
local shown = forever and "Akasha Dawnfire" or "Akasha-Forever"
check("in your group: said in chat", said(shown .. " from your blacklist is in your group") == 1, table.concat(M.printed, " / "))
check("in your group: the note too", said("Left after the first wipe") == 1)
check("in your group: on screen", #warnings == 1 and warnings[1]:find(shown, 1, true))
check("in your group: a sound", sounds == 1, sounds)
M.Fire("GROUP_ROSTER_UPDATE"); M.Fire("GROUP_ROSTER_UPDATE")
check("still there: not said again", said("from your blacklist") == 1 and #warnings == 1)
-- They leave, then come back: said again.
local saved = M.roster.party1
M.roster.party1 = nil; M.groupSize = 4
M.Fire("GROUP_ROSTER_UPDATE")
M.roster.party1 = saved; M.groupSize = 5
M.Fire("GROUP_ROSTER_UPDATE")
check("back again: said again", said("from your blacklist") == 2 and #warnings == 2)
-- The warning turned off: nothing.
MS:SetBlacklistWarn(false)
M.roster.party1 = nil; M.groupSize = 4; M.Fire("GROUP_ROSTER_UPDATE")
M.roster.party1 = saved; M.groupSize = 5; M.Fire("GROUP_ROSTER_UPDATE")
check("warning off: nothing", said("from your blacklist") == 2 and #warnings == 2)
MS:SetBlacklistWarn(true)
-- Added while they're already with you: said straight away.
local girthy = forever and "Girthy Stone" or "Girthy"
MS:AddToBlacklist(girthy, nil, "")
check("added while in the group: said", said((forever and "Girthy Stone" or "Girthy-Forever") .. " from your blacklist") == 1)

-- ── Their tooltip ──────────────────────────────────────────────────────────
check("tooltip hooked", type(tooltipCall) == "function")
local tipLines = {}
local tip = GameTooltip
local realAdd, realGetUnit = tip.AddLine, tip.GetUnit
tip.AddLine = function(_, text) tipLines[#tipLines + 1] = text end
tip.GetUnit = function() return "Akasha", "party1" end
tooltipCall(tip)
check("tooltip: on your blacklist", tipLines[1] == "On your blacklist" and tipLines[2] == "Left twice", table.concat(tipLines, " / "))
tipLines = {}
tip.GetUnit = function() return "Skip", "party3" end
tooltipCall(tip)
check("tooltip: nothing for others", #tipLines == 0)
tip.AddLine, tip.GetUnit = realAdd, realGetUnit

-- ── The group finder: red names ────────────────────────────────────────────
local function FontString()
    return { SetTextColor = function(fs, r, g, b) fs.color = { r, g, b } end }
end
local results = { [7] = { leaderName = forever and "Akasha-Dawnfire" or "Akasha" }, [8] = { leaderName = "Skip" } }
local applicants = { [21] = { forever and "Girthy-Stone" or "Girthy", "Skip" } }
rawset(_G, "C_LFGList", {
    GetSearchResultInfo = function(id) return results[id] end,
    GetApplicantMemberInfo = function(id, i) return applicants[id] and applicants[id][i] end,
})
rawset(_G, "LFGListSearchEntry_Update", function(entry) entry.Name:SetTextColor(1, 1, 1) end)
rawset(_G, "LFGListApplicationViewer_UpdateApplicantMember", function(member) member.Name:SetTextColor(0.5, 0.5, 1) end)
M.Fire("ADDON_LOADED", "Blizzard_GroupFinder")
local function Bordered(frame) local b = frame._msBlacklistBorder; return b ~= nil and b[1]:IsShown() end
local listing = CreateFrame("Button"); listing.resultID, listing.Name = 7, FontString()
LFGListSearchEntry_Update(listing)
check("listing by a blacklisted leader: red border", Bordered(listing))
check("listing: the name as the game drew it", listing.Name.color[2] == 1)
local other = CreateFrame("Button"); other.resultID, other.Name = 8, FontString()
LFGListSearchEntry_Update(other)
check("anyone else's listing: no border", not Bordered(other))
local member = { Name = FontString() }
LFGListApplicationViewer_UpdateApplicantMember(member, 21, 1)
check("applicant on your blacklist: red", member.Name.color[1] == 1 and member.Name.color[2] < 0.2)
local member2 = { Name = FontString() }
LFGListApplicationViewer_UpdateApplicantMember(member2, 21, 2)
check("other applicant: as the game drew it", member2.Name.color[1] == 0.5)
-- Hooked once, whatever loads after.
M.Fire("ADDON_LOADED", "SomethingElse")
local calls = 0
local realRed = listing.Name.SetTextColor
listing.Name.SetTextColor = function(...) calls = calls + 1; return realRed(...) end
LFGListSearchEntry_Update(listing)
check("hooked once", calls == 1, calls)
-- The same frame reused for another listing: the border goes.
listing.resultID = 8
LFGListSearchEntry_Update(listing)
check("frame reused: border gone", not Bordered(listing))

-- ── Forever's Looking For Group window ─────────────────────────────────────
-- Listing 30: Kul Dotha leads, Akasha (on the list) is in it. Listing 31: no one listed.
results[30] = { leaderName = "Kul Dotha", numMembers = 3 }
results[31] = { leaderName = "Datt Qt", numMembers = 1 }
local members = { [30] = { { name = "Kul Dotha" }, { name = "Akasha Dawnfire" }, { name = "Jake Hole" } }, [31] = { { name = "Datt Qt" } } }
C_LFGList.GetSearchResultPlayerInfo = function(id, i) return members[id] and members[id][i] end
rawset(_G, "LFGBrowseSearchEntry_Update", function(entry) entry.Name:SetTextColor(1, 1, 1) end)
rawset(_G, "LFGBrowseSearchEntry_Init", function(entry, data) entry.resultID = data.resultID end)
rawset(_G, "LFGBrowseSearchEntryTooltip_UpdateAndShow", function(tip)
    tip.Leader.Name:SetTextColor(1, 1, 1)
    for f in tip.memberPool:EnumerateActive() do f.Name:SetTextColor(1, 1, 1) end
end)
local dropDown = {}
local browseShown = true
rawset(_G, "LFGBrowseFrame", { SearchEntryDropDown = dropDown, IsVisible = function() return browseShown end })
M.Fire("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
local function Entry(id)
    local e = CreateFrame("Button")
    e.Name = FontString()
    LFGBrowseSearchEntry_Init(e, { resultID = id })
    return e
end
local withListed, clean = Entry(30), Entry(31)
LFGBrowseSearchEntry_Update(withListed); LFGBrowseSearchEntry_Update(clean)
check("LFG window: someone listed in the group: red border", Bordered(withListed))
check("LFG window: no one listed: no border", not Bordered(clean))
-- The member tooltip: their name in red.
local function Named(text) local fs = FontString(); fs.GetText = function() return text end; return fs end
local memberFrames = { { Name = Named("Akasha Dawnfire") }, { Name = Named("Jake Hole") } }
local tipFrame = { Leader = { Name = Named("Kul Dotha") },
    memberPool = { EnumerateActive = function() local i = 0; return function() i = i + 1; return memberFrames[i] end end } }
LFGBrowseSearchEntryTooltip_UpdateAndShow(tipFrame, 30)
check("LFG tooltip: the listed member in red", memberFrames[1].Name.color[2] < 0.2)
check("LFG tooltip: the others as drawn", memberFrames[2].Name.color[2] == 1 and tipFrame.Leader.Name.color[2] == 1)
-- Its right-click menu: built by the game with no name; the blacklist is added.
local function BrowseRoot()
    local root = { items = {} }
    function root:CreateTitle() end
    function root:CreateDivider() end
    function root:CreateButton(text, fn)
        local item = { text = text, fn = fn, items = {} }
        function item:CreateButton(t, f) self.items[#self.items + 1] = { text = t, fn = f } end
        self.items[#self.items + 1] = item
        return item
    end
    return root
end
withListed:Fire("OnMouseDown", "RightButton")
local broot = BrowseRoot()
Menu.PopulateDescription(function(_, r) r:CreateButton("Send Message") end, dropDown, broot)
check("LFG menu: the game's own first", broot.items[1].text == "Send Message")
check("LFG menu: add the leader", broot.items[2] and broot.items[2].text:find("Add to blacklist", 1, true), broot.items[2] and broot.items[2].text)
local others = broot.items[3]
check("LFG menu: the rest of the group", others and others.text == "Someone else in this group" and #others.items == 2)
check("LFG menu: who's listed already in red", others.items[1].text:find("Akasha Dawnfire", 1, true) and others.items[1].text:find("|cffff4040", 1, true)
    and others.items[2].text == "Jake Hole", others.items[1].text)
-- No dropdown of its own (the menu on the screen itself): the listing under the mouse.
rawset(_G, "GetMouseFoci", function() return { withListed } end)
withListed.GetParent = function() return nil end
M.Advance(5)
local byMouse = BrowseRoot()
Menu.PopulateDescription(function(_, r) r:CreateButton("Send Message") end, UIParent, byMouse)
check("LFG menu: found by the mouse", byMouse.items[2] and byMouse.items[2].text:find("Add to blacklist", 1, true))
-- The window closed: nothing added.
browseShown = false
local closed = BrowseRoot()
Menu.PopulateDescription(function(_, r) r:CreateButton("Send Message") end, UIParent, closed)
check("LFG window closed: nothing added", #closed.items == 1)
browseShown = true
rawset(_G, "GetMouseFoci", function() return {} end)
-- Any other menu: nothing added.
local plain = BrowseRoot()
Menu.PopulateDescription(function(_, r) r:CreateButton("Something") end, {}, plain)
check("other menus: untouched", #plain.items == 1)

-- ── Right-click menus ──────────────────────────────────────────────────────
local function Root()
    local root = { items = {} }
    function root:CreateDivider() end
    function root:CreateTitle() end
    function root:CreateButton(text, fn) self.items[#self.items + 1] = { text = text, fn = fn } end
    return root
end
check("menus: the unit's", type(menus.MENU_UNIT_PARTY) == "function" and type(menus.MENU_UNIT_PLAYER) == "function")
local root = Root()
menus.MENU_UNIT_PARTY(nil, root, { unit = "party3" })
check("menu: someone not on it: add", #root.items == 1 and root.items[1].text:find("Add to blacklist", 1, true))
root = Root()
menus.MENU_UNIT_PARTY(nil, root, { unit = "party1" })
check("menu: someone on it: note and remove", #root.items == 2 and root.items[1].text == "Change blacklist note"
    and root.items[2].text:find("Remove from blacklist", 1, true))
root = Root()
menus.MENU_UNIT_PLAYER(nil, root, { unit = "player" })
check("menu: not yourself", #root.items == 0)
root = Root()
menus.MENU_UNIT_PARTY(nil, root, { unit = "party4pet" })
check("menu: not a pet", #root.items == 0)
root = Root()
menus.MENU_LFG_FRAME_SEARCH_ENTRY(nil, root, { resultID = 7 })
check("menu: a listing's leader", #root.items == 2)
root = Root()
menus.MENU_UNIT_FRIEND(nil, root, { name = "Skip", server = forever and nil or "Forever" })
check("menu: a name from chat", #root.items == 1)

-- Remove from the menu.
root = Root()
menus.MENU_UNIT_PARTY(nil, root, { unit = "party1" })
root.items[2].fn()
check("removed from the menu", MS:BlacklistEntry(akasha) == nil)

-- ── The note box ───────────────────────────────────────────────────────────
local popups, shownPopup = {}, nil
rawset(_G, "StaticPopupDialogs", popups)
rawset(_G, "StaticPopup_Show", function(which, text, _, data) shownPopup = { which = which, text = text, data = data } end)
root = Root()
menus.MENU_UNIT_PARTY(nil, root, { unit = "party3" })
root.items[1].fn()
check("add: asks for a note", shownPopup and popups[shownPopup.which] and shownPopup.text:find("Skip", 1, true), shownPopup and shownPopup.text)
local box = { text = "", SetText = function(b, t) b.text = t end, GetText = function(b) return b.text end, HighlightText = function() end, SetFocus = function() end }
local dialog = { GetEditBox = function() return box end, Hide = function() end }
local def = popups[shownPopup.which]
def.OnShow(dialog, shownPopup.data)
box.text = "Afk the whole run"
def.OnAccept(dialog, shownPopup.data)
local skip = MS:BlacklistEntry("Skip")
check("add: saved with the note", skip and skip.note == "Afk the whole run" and skip.class == "SHAMAN")
-- The note box again: filled with the note.
MS:AskBlacklistNote("Skip")
def.OnShow(dialog, shownPopup.data)
check("change: the note filled in", box.text == "Afk the whole run", box.text)

-- ── The window ─────────────────────────────────────────────────────────────
local ok, err = pcall(MS.ShowBlacklist, MS)
check("window: opens", ok, err)
local win = rawget(_G, "MythicScoreboardBlacklistFrame")
check("window: shown", win and win:IsShown())
check("window: the count", win.count:GetText() == "2 players", win.count:GetText())
-- The cross: once to ask (the date steps aside), again to remove.
do
    local row
    for _, child in ipairs({ win.list.scrollContent:GetChildren() }) do if child:IsShown() and child._key then row = child; break end end
    local rm
    for _, c in ipairs({ row:GetChildren() }) do rm = c end
    local before = #MS:BlacklistEntries()
    rm:Fire("OnClick")
    check("remove: asks first", #MS:BlacklistEntries() == before and not row._date:IsShown())
    row.Disarm()
    check("remove: the date back", row._date:IsShown())
end
local entries = MS:BlacklistEntries()
check("window: newest first", entries[1] and entries[1].entry.name:find("Skip", 1, true) ~= nil, entries[1] and entries[1].entry.name)
MS:RemoveBlacklistKey(entries[1].key)
check("window: one fewer", win.count:GetText() == "1 player", win.count:GetText())
MS:RemoveBlacklistKey(MS:BlacklistEntries()[1].key)
check("window: empty", win.empty:IsShown())
-- The header's button: opens and closes it.
MS:ShowScoreboard()
local blBtn = MS.UI.frame.BlacklistBtn
check("header button", blBtn ~= nil)
win:Hide()
blBtn:Fire("OnClick")
check("header button opens it", win:IsShown())
blBtn:Fire("OnClick")
check("header button closes it", not win:IsShown())
-- Dates: "November 14, 2026".
local stamp = os.time({ year = 2026, month = 11, day = 4, hour = 12 })
check("date: American style", MS.UI._BlacklistDate({ added = stamp }) == "November 4, 2026", MS.UI._BlacklistDate({ added = stamp }))
rawset(_G, "CALENDAR_FULLDATE_MONTH_NAMES", { [11] = "Novembre" })
check("date: the game's month names", MS.UI._BlacklistDate({ added = stamp }) == "Novembre 4, 2026")
rawset(_G, "CALENDAR_FULLDATE_MONTH_NAMES", nil)
-- /sb blacklist
win:Hide()
SlashCmdList.MYTHICSCOREBOARD("blacklist")
check("/sb blacklist opens it", win:IsShown())

for _, line in ipairs(M.printed or {}) do
    if line:find("error") then check("no errors", false, line) end
end
io.stdout:write(("blacklist_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

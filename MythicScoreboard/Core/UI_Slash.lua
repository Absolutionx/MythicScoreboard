-- The /sb (and /mscoreboard) commands, and /sb lang and /sb demo. They work
-- before the window is first opened (it's built then).

local _slower = string.lower
local _smatch = string.match
local _fmt    = string.format

local MS = _G["MythicScoreboard"]
local L = MS.L
local UI = MS.UI
local DoClearHistory = UI.DoClearHistory
local DEMO_TIMES, DemoRun, ForeverDemoRun = UI.DEMO_TIMES, UI.DemoRun, UI.ForeverDemoRun

-- Each language by its own name (/sb lang).
local LANG_NAMES = {
    enUS = "English", deDE = "Deutsch", frFR = "Français", esES = "Español (EU)", esMX = "Español (AL)",
    ptBR = "Português", itIT = "Italiano", ruRU = "Русский", koKR = "한국어", zhCN = "简体中文", zhTW = "繁體中文",
}

-- /sb lang [code]: shows the addon in another language from the next
-- /reload, to check a translation without changing the game's language.
local function LangCommand(arg)
    local say = MS.Say
    local acc = MS.AccountDB()
    if arg == "" then
        say(_fmt(L["Language: %s"], LANG_NAMES[MS.Locale] or MS.Locale)
            .. ((MS.Locale ~= MS.ClientLocale) and ("  |cff888888(" .. L["preview"] .. ")|r") or ""))
        say(_fmt(L["Preview another with /sb lang <code>: %s"], table.concat(MS.LOCALES, " ")))
        if acc and acc.previewLocale then say(L["Back to the game's language: /sb lang off"]) end
        return
    end
    local pick
    if arg == "off" or arg == "reset" then pick = MS.ClientLocale
    else
        for _, code in ipairs(MS.LOCALES) do
            if code:lower() == arg then pick = code end
        end
    end
    if not pick then say(_fmt(L["Unknown language: %s"], arg)); return end
    acc = acc or MS.AccountDB(true)
    acc.previewLocale = (pick ~= MS.ClientLocale) and pick or nil
    say(_fmt(L["Type /reload to see the addon in %s."], LANG_NAMES[pick] or pick))
end


-- /sb demo [0-3]: a made-up finished key, to see how a key looks (the
-- diamonds, your rating gain, the +3/+2/+1 marks, specializations) without
-- running one. Shown only; never saved to history or stats. The number is
-- the upgrade it got (0 = over time; 2 if left out). On WoW Forever: a
-- made-up run of one of its own dungeons near your level instead (ForeverDemoRun).

local function DemoCommand(arg)
    local up = tonumber(arg)
    if not (up and DEMO_TIMES[up]) then up = 2 end
    MS:ShowScoreboard()
    if UI.statsOpen then UI.CloseStats() end
    MS.displayRun = MS.Flavor.progressStats and ForeverDemoRun() or DemoRun(up)
    MS:RefreshOverview()
    MS.Say(MS.Flavor.progressStats and L["A sample run, not saved. Pick a run from history to go back."]
        or L["A sample key, not saved. Pick a run from history to go back."])
end

-- Slash commands work before the window is first opened (it is built then).
SLASH_MYTHICSCOREBOARD1 = "/sb"
SLASH_MYTHICSCOREBOARD2 = "/mscoreboard"
SlashCmdList["MYTHICSCOREBOARD"] = function(msg)
    local cmd = _slower(_smatch(msg or "", "^%s*(.-)%s*$"))
    local langArg = _smatch(cmd, "^lang%s*(.*)$")
    local demoArg = _smatch(cmd, "^demo%s*(.*)$")
    local compactArg = _smatch(cmd, "^compact%s*(.*)$")
    if langArg then
        LangCommand(langArg)
    elseif demoArg then
        DemoCommand(demoArg)
    elseif compactArg then
        MS:CompactCommand(compactArg)
    elseif _smatch(cmd, "^removeloot") then
        -- /sb removeloot [item]: Shift-click the item into the line.
        local link = _smatch(msg or "", "|H(item:[%-%d:]+)") or _smatch(msg or "", "(item:%d+)")
        local n = link and MS:RemoveLootItem(link)
        if not link then
            MS.Say(L["Type /sb removeloot, then Shift-click the item into the line."])
        elseif n and n > 0 then
            MS.Say(MS.Plural(n, "Removed from %d run.", "Removed from %d runs."))
            MS:RefreshOverview()
        else
            MS.Say(L["That item isn't on any of your runs from the last day."])
        end
    elseif cmd == "" then
        MS:ShowScoreboard()
    elseif cmd == "stats" then
        MS:ShowScoreboard()
        UI.OpenStats()
    elseif cmd == "abandon" then
        if not MS:AbandonRun() then
            MS.Say(L["No run in progress to abandon."])
        end
    elseif cmd == "help" then
        MS.Say("v" .. MS.version
            .. "  " .. L["Commands:"] .. " /sb, /sb stats, /sb abandon, /sb clear, /sb autoreset, /sb lang,"
            .. " /sb demo, /sb compact, /sb removeloot, "
            .. (MS.SayInstanceLimit and "/sb limit, " or "")
            .. (MS.ShowBlacklist and "/sb blacklist, " or "") .. "/sb help")
    elseif cmd == "autoreset" then
        local newVal = not MS:GetAutoResetMeter()
        MS:SetAutoResetMeter(newVal)
        MS.Say(L["Reset meter on zone-in:"] .. " "
            .. (newVal and ("|cff00ff00" .. L["on"] .. "|r") or ("|cffff4444" .. L["off"] .. "|r")))
    elseif cmd == "clear" then
        DoClearHistory()
    elseif cmd == "killdebug" and MS.KillDebug then
        MS:KillDebug()
    elseif cmd == "wingdebug" and MS.WingDebug then
        MS:WingDebug(true)
    elseif cmd == "limit" and MS.SayInstanceLimit then
        MS:SayInstanceLimit()
    elseif (cmd == "limit test" or cmd == "limit preview") and MS.ToggleInstanceLimitPreview then
        MS:ToggleInstanceLimitPreview()
    elseif (cmd == "blacklist" or cmd == "bl") and MS.ShowBlacklist then
        MS:ShowBlacklist()
    elseif cmd == "bosses" and MS.BossNpcReport and MS.Flavor.bossProgress then
        MS:BossNpcReport()
    elseif cmd == "bosses check" and MS.CheckBossNpcs and MS.Flavor.bossProgress then
        MS:CheckBossNpcs()
    elseif cmd == "dumptravel" and MS.DumpTravel then
        MS:DumpTravel()
    elseif cmd == "routedebug" and MS.RouteDebug then
        local t = MS.NavigationTarget and MS:NavigationTarget()
        if t and t.spot then MS:RouteDebug(t.spot, t.name)
        else MS.Say("routedebug: click a dungeon marker first") end
    else
        MS.Say(L["Unknown command. Type /sb help for a list."])
    end
end

-- usage: lua5.1 account_settings_tests.lua DIR TOC
-- Settings are the account's (an alt starts with yours, not the defaults),
-- and the window comes back where you left it.
table.unpack = table.unpack or unpack
local M = dofile("wowmock.lua")
M.LoadTOC(arg[1], arg[2])
local MS = rawget(_G, "MythicScoreboard")
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
local function login() M.Fire("ADDON_LOADED", "MythicScoreboard"); M.RunTimers(4) end

-- ── Your first character after the update: its settings become the account's ──
MythicScoreboardAccountDB = nil
MythicScoreboardDB = { settings = { minimapButton = false, minimapAngle = 77 }, navPos = { x = 120, y = -40 } }
login()
local acc = MythicScoreboardAccountDB
check("first character: its settings kept", MS:GetSetting("minimapButton") == false and MS:GetSetting("minimapAngle") == 77)
check("first character: now the account's", acc.settings and acc.settings.minimapAngle == 77)
check("the arrow's place: with the settings", type(MS:GetSetting("navPos")) == "table" and MS:GetSetting("navPos").x == 120)
check("the arrow's place: no longer beside them", MythicScoreboardDB.navPos == nil)
MS:SetSetting("minimapAngle", 91)
check("a change: the account's", acc.settings.minimapAngle == 91, acc.settings.minimapAngle)

-- ── An alt that never had the addon: your settings, not the defaults ───────
MythicScoreboardDB = nil
login()
check("new alt: your settings", MS:GetSetting("minimapButton") == false and MS:GetSetting("minimapAngle") == 91)
check("new alt: the arrow's place too", MS:GetSetting("navPos") and MS:GetSetting("navPos").x == 120)

-- ── An alt with its own old settings: the account's win ────────────────────
MythicScoreboardDB = { settings = { minimapButton = true, minimapAngle = 5 }, runs = { } }
login()
check("old alt: the account's settings", MS:GetSetting("minimapAngle") == 91, MS:GetSetting("minimapAngle"))
check("old alt: its runs untouched", type(MythicScoreboardDB.runs) == "table")
-- (As the game saves them: two copies. The account's is the one read back.)
MythicScoreboardDB.settings = { minimapAngle = 5 }
login()
check("after a save and a login: still the account's", MS:GetSetting("minimapAngle") == 91)

-- ── The window: where you left it ──────────────────────────────────────────
MS:ShowScoreboard()
local win = rawget(_G, "MythicScoreboardFrame")
check("the window is built", win ~= nil)
local p, _, rp, x, y = win:GetPoint()
check("never moved: the middle", p == "CENTER" and rp == "CENTER" and x == 0 and y == 60, tostring(p) .. " " .. tostring(x) .. " " .. tostring(y))
-- Dragged: the game re-anchors it; that's what's kept.
win:ClearAllPoints(); win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 312.4, -150.6)
win:GetScript("OnDragStop")(win)
local pos = MS:GetSetting("windowPos")
check("dragged: kept", type(pos) == "table" and pos[1] == "TOPLEFT" and pos[2] == "TOPLEFT" and pos[3] == 312 and pos[4] == -151,
    pos and table.concat(pos, " "))
check("dragged: the account's", acc.settings.windowPos == pos)

-- ── Locked: it stays put, and can't be resized ─────────────────────────────
local moved = 0
win.StartMoving = function() moved = moved + 1 end
win:GetScript("OnDragStart")(win)
check("unlocked: it moves", moved == 1, moved)
local grip = win.ResizeGrip
check("unlocked: the resize corner", grip and grip:IsShown())
MS:SetWindowLocked(true)
win:GetScript("OnDragStart")(win)
check("locked: it doesn't move", moved == 1, moved)
check("locked: no resize corner", not grip:IsShown())
check("locked: the account's", acc.settings.windowLocked == true)
MS:SetWindowLocked(false)
check("unlocked again: the corner's back", grip:IsShown())

-- ── Its size ───────────────────────────────────────────────────────────────
check("size: 100% to start", MS:GetWindowScale() == 1 and win:GetScale() == 1)
MS:SetWindowScale(0.8)
check("size: set, applied", math.abs(win:GetScale() - 0.8) < 1e-6, win:GetScale())
MS:SetWindowScale(3); check("size: no more than 140%", MS:GetWindowScale() == 1.4)
MS:SetWindowScale(0.1); check("size: no less than 60%", MS:GetWindowScale() == 0.6)
MS:SetWindowScale(1)
-- Dragging the corner: the size that puts it under the cursor, kept on letting go.
M.cursor = { win:GetWidth() * 1.2, 0 }
grip:GetScript("OnMouseDown")(grip, "LeftButton")
grip:GetScript("OnUpdate")(grip, 0.01)
check("corner dragged: bigger", math.abs(win:GetScale() - 1.2) < 0.01, win:GetScale())
grip:GetScript("OnMouseUp")(grip)
check("corner let go: kept", math.abs(MS:GetWindowScale() - 1.2) < 0.01, MS:GetWindowScale())
-- Locked: the corner does nothing.
MS:SetWindowLocked(true)
M.cursor = { win:GetWidth() * 0.7, 0 }
grip:GetScript("OnMouseDown")(grip, "LeftButton")
check("locked: the corner does nothing", grip:GetScript("OnUpdate") == nil)
MS:SetWindowLocked(false)
MS:SetWindowScale(1)
-- Right-click the corner: back to 100%.
MS:SetWindowScale(1.3)
grip:GetScript("OnMouseDown")(grip, "RightButton")
check("right-click the corner: 100% again", MS:GetWindowScale() == 1 and math.abs(win:GetScale() - 1) < 1e-6)
-- Settings' Reset size button.
MS:SetWindowScale(0.7)
local pop = win.SettingsPopup
local reset = pop and pop.ResetScaleBtn
check("settings: a Reset size button", reset ~= nil)
if reset then reset:GetScript("OnClick")(reset) end
check("settings: Reset size: 100%", MS:GetWindowScale() == 1)
-- A new session: the size first, then the place.
check("size: the account's", acc.settings.windowScale == 1)

for _, line in ipairs(M.printed or {}) do if line:find("error") then check("no errors", false, line) end end
io.stdout:write(("account_settings_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

-- usage: lua5.1 layering_tests.lua DIR TOC   (the core never calls the windows; it says what changed)
local DIR = arg[1]
local fails, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else fails = fails + 1; io.stdout:write("FAIL ", name, "  ", tostring(detail or ""), "\n") end
end
-- Core files: everything in Core/ but the windows (UI*.lua). MobForces adds
-- a line to the game's own unit tooltip, which is what it's for.
local p = io.popen('ls "' .. DIR .. '/Core"')
local banned = { "MS%.UI%f[^%w_]", "RefreshOverview", "RefreshStats", "MythicScoreboardFrame", "UI%.SayOnce" }
for f in p:lines() do
    if f:find("%.lua$") and not f:find("^UI") then
        local n = 0
        for line in io.lines(DIR .. "/Core/" .. f) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            for _, pat in ipairs(banned) do
                check(f .. ":" .. n .. " doesn't call the windows (" .. pat .. ")", not code:find(pat), line)
            end
        end
    end
end
p:close()
io.stdout:write(("layering_tests: %d passed, %d failed\n"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

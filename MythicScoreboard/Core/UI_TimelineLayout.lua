-- Where the boss medallions go on the timeline.
--
-- Pure layout: given each boss's spot on the track (mx) and how wide its
-- label is (full and compact), it returns where its medallion sits. Nothing
-- here draws or measures, so it can be tested on its own.
--
-- Hard rules: nothing on a row touches (labels and medallions 10px apart), no
-- stem runs through a label, a top-row stem never hides behind a bottom-row
-- medallion, and no bent stem crosses another stem. Within those, in order of
-- preference: a full label, the medallion moved aside on a bent stem, a
-- compact label (the name on two lines; times are in the tooltip), and last,
-- no name. Worked out left to right with a beam search; partial layouts that
-- leave the same space free for what's still to come are merged, keeping the
-- cheapest. A quick search runs first, the thorough one only when a name
-- would otherwise lose its "Killed at" line.

local MS = _G["MythicScoreboard"]
local UI = MS.UI
local _floor, _max, _min = math.floor, math.max, math.min
local FRAME_W = UI.FRAME_W

-- Timeline geometry, shared with UI_Timeline.lua.
local TL = {
    TRACK_Y   = 76,
    TRACK_H   = 14,
    MED_R     = 17,
    MED_ROWS  = { 162, 122 },   -- medallion centres: top row, bottom row
    DEATH_Y   = 58,             -- centre of death diamonds
    INT_BASE  = 34,             -- baseline of the interrupt bar chart
    INT_MAXH  = 11,
    COMPACT_W = 88,             -- width of a compact (two-line) name
}
UI.TL = TL
local TRACK_Y, TRACK_H, MED_R, MED_ROWS = TL.TRACK_Y, TL.TRACK_H, TL.MED_R, TL.MED_ROWS

-- medInfo[id] = { mx = track x, lblW = full label width, compW = compact width }
-- order       = ids by priority (the run's last kill first)
-- runKey      = identifies the run, for the cache
-- Returns plan[id] = { row, cx, elbow, mode = { left, compact, bare }, x1, x2, ... }.
function UI.PlaceMedallions(medInfo, order, runKey)
    local CIRCLE = MED_R * 2 + 6
    local SHIFTS = { 0, CIRCLE, -CIRCLE, 2 * CIRCLE, -2 * CIRCLE }
    local MODES = {
        { left = false }, { left = true }, { left = false, compact = true }, { left = true, compact = true }, { bare = true },
    }
    local CLASH = 1e6
    -- An upper-row line may not pass behind a lower-row medallion (it would
    -- look as if that boss had no line).
    local HIDE_RULE = true

    -- Each stem is drawn as line segments: straight up from the fight, or up
    -- to its own elbow height, across, and up to the medallion. Bends get
    -- different elbow heights so two of them can pass without touching.
    local TOP = TRACK_Y + TRACK_H
    local ELBOWS = { TOP + 4, TOP + 8, TOP + 12 }
    local function Segments(mx, cx, row, elbow)
        local bottom = MED_ROWS[row] - MED_R
        if math.abs(cx - mx) < 1 then return { v = { { mx, TOP, bottom } }, h = {} } end
        return { v = { { mx, TOP, elbow }, { cx, elbow, bottom } }, h = { { elbow, _min(mx, cx), _max(mx, cx) } } }
    end
    local function Crosses(a, b)
        for _, h in ipairs(a.h) do
            for _, v in ipairs(b.v) do
                if v[1] > h[2] - 3 and v[1] < h[3] + 3 and h[1] > v[2] - 2 and h[1] < v[3] + 2 then return true end
            end
            for _, h2 in ipairs(b.h) do
                if math.abs(h[1] - h2[1]) < 3 and _min(h[3], h2[3]) - _max(h[2], h2[2]) > -4 then return true end
            end
        end
        return false
    end

    -- Every spot a boss could take (row, side, label size, shift, elbow),
    -- worked out once per boss.
    local function Shapes(info)
        local out = {}
        local mx = info.mx
        for pass = 1, 2 do
            for _, shift in ipairs(SHIFTS) do
                for row = 1, 2 do
                    for mi = (pass == 1 and 1 or 3), (pass == 1 and 2 or 5) do
                        local mode = MODES[mi]
                        for ei, elbow in ipairs(ELBOWS) do
                            if shift == 0 and ei > 1 then break end
                            local cx = mx + shift
                            local w = mode.compact and info.compW or info.lblW
                            local x1 = mode.bare and (cx - MED_R) or mode.left and (cx - MED_R - 8 - w) or (cx - MED_R)
                            local x2 = mode.bare and (cx + MED_R) or mode.left and (cx + MED_R) or (cx + MED_R + 8 + w)
                            if x1 >= 4 and x2 <= FRAME_W - 6 then
                                local l1, l2
                                if not mode.bare then
                                    if mode.left then l1, l2 = x1, cx - MED_R - 2 else l1, l2 = cx + MED_R + 2, x2 end
                                end
                                out[#out + 1] = {
                                    full = (pass == 1), shift = shift, ei = ei,
                                    key = row .. tostring(mode.left) .. tostring(mode.compact) .. tostring(mode.bare),
                                    row = row, mode = mode, x1 = x1, x2 = x2, l1 = l1, l2 = l2, cx = cx, mx = mx,
                                    elbow = elbow, segs = Segments(mx, cx, row, elbow), far = _max(x2, cx, mx),
                                    cost = (mode.bare and 300 or mode.compact and 150 or 0)
                                         + (shift ~= 0 and (20 + math.abs(shift) * 0.3) or 0)
                                         + (row - 1) * 0.5 + (mode.left and 0.25 or 0) + ei * 0.01,
                                }
                            end
                        end
                    end
                end
            end
        end
        return out
    end

    -- Whether a spot is free, given what's placed nearby. The second result
    -- says whether only the stem's bend was in the way (another elbow
    -- height might do).
    local function Fits(near, c)
        local row, x1, x2, cx, l1, l2 = c.row, c.x1, c.x2, c.cx, c.l1, c.l2
        for _, o in ipairs(near) do
            if o.row == row then
                if _min(x2, o.x2 + 10) - _max(x1, o.x1 - 10) > 0 then return false, false end
            elseif row == 1 then
                if o.l1 and cx > o.l1 - 4 and cx < o.l2 + 4 then return false, false end
                -- nor hidden behind a lower-row medallion
                if HIDE_RULE and math.abs(cx - o.cx) < MED_R + 4 then return false, false end
            else
                if l1 and o.cx > l1 - 4 and o.cx < l2 + 4 then return false, false end
                if HIDE_RULE and math.abs(o.cx - cx) < MED_R + 4 then return false, false end
            end
        end
        for _, o in ipairs(near) do
            if Crosses(c.segs, o.segs) or Crosses(o.segs, c.segs) then return false, true end
        end
        return true
    end

    local seq = {}
    for _, bi in ipairs(order) do seq[#seq + 1] = bi end
    table.sort(seq, function(a, b) return medInfo[a].mx < medInfo[b].mx end)
    local shapeCache = {}
    local function Search(BEAM, bound)
        local states = { { near = {}, plan = {}, score = 0 } }
        for si, bi in ipairs(seq) do
            local info = medInfo[bi]
            -- After a long gap the choices so far can't matter to what follows:
            -- settle on the best and carry on from there.
            if si > 1 and info.mx - medInfo[seq[si - 1]].mx > 300 then states = { states[1] } end
            -- Anything ending well before the next boss can't affect it or what
            -- follows: it's dropped from the comparison (and from the checks).
            local nextBi = seq[si + 1]
            local edge = (nextBi and medInfo[nextBi].mx or info.mx) - 290
            local shapes = shapeCache[bi] or Shapes(info)
            shapeCache[bi] = shapes
            local nextStates = {}
            local nextGap = nextBi and (medInfo[nextBi].mx - info.mx) or math.huge
            for _, st in ipairs(states) do
                local fullFits = false
                local lastKey
                -- Which spots fit without moving: moving only helps when it
                -- makes room for a boss coming up close behind (a move left), or
                -- when the boss's own spot is taken.
                local ownFits = {}
                for _, c in ipairs(shapes) do
                    if c.shift == 0 and c.full and Fits(st.near, c) then ownFits[c.key] = true end
                end
                for _, c in ipairs(shapes) do
                    local useful = true
                    if c.shift ~= 0 and ownFits[c.key] then
                        useful = c.shift < 0 and nextGap < 260
                    end
                    if useful and (c.full or not fullFits) then
                        -- a bend takes the lowest elbow that fits
                        local key = c.key .. c.shift
                        if key ~= lastKey or c.ei == 1 then
                            local ok, bendOnly = Fits(st.near, c)
                            if ok then
                                nextStates[#nextStates + 1] = { parent = st, bi = bi, c = c, score = st.score + c.cost }
                                if c.full then fullFits = true end
                                lastKey = key
                            elseif not bendOnly then
                                lastKey = key               -- no other elbow will help
                            end
                        end
                    end
                end
            end
            if #nextStates == 0 then
                -- Nowhere clean at all (very crowded): least-bad bare medallion.
                for _, st in ipairs(states) do
                    for k = -10, 10 do
                        for row = 1, 2 do
                            local cx = info.mx + k * CIRCLE
                            local c = { row = row, mode = MODES[5], x1 = cx - MED_R, x2 = cx + MED_R, cx = cx, mx = info.mx,
                                        elbow = ELBOWS[2], segs = Segments(info.mx, cx, row, ELBOWS[2]),
                                        far = _max(cx + MED_R, info.mx), cost = 300 + math.abs(k) * 20 }
                            local clashes = 0
                            for _, o in ipairs(st.near) do
                                if o.row == row and _min(c.x2, o.x2 + 6) - _max(c.x1, o.x1 - 6) > 0 then clashes = clashes + 1 end
                                if row == 1 and o.row == 2 and o.l1 and cx > o.l1 - 2 and cx < o.l2 + 2 then clashes = clashes + 1 end
                            end
                            nextStates[#nextStates + 1] = { parent = st, bi = bi, c = c, score = st.score + c.cost + clashes * CLASH }
                        end
                    end
                end
            end
            table.sort(nextStates, function(a, b) return a.score < b.score end)
            -- States that agree on everything near the edge are the same choice.
            local seen, kept = {}, {}
            local function Sig(o)
                if not o.sig then
                    o.sig = o.row .. ":" .. _floor(o.x1) .. ":" .. _floor(o.x2) .. ":" .. _floor(o.cx)
                        .. ":" .. (o.l1 and _floor(o.l1) or "-") .. ":" .. (o.elbow or 0)
                end
                return o.sig
            end
            for _, ns in ipairs(nextStates) do
                local near = {}
                for _, o in ipairs(ns.parent.near) do
                    if o.far > edge then near[#near + 1] = o end
                end
                if ns.c.far > edge then near[#near + 1] = ns.c end
                local parts = {}
                for i, o in ipairs(near) do parts[i] = Sig(o) end
                local sig = table.concat(parts, "|")
                if bound and ns.score >= bound then break end   -- sorted: the rest cost more
                if not seen[sig] then
                    seen[sig] = true
                    ns.near = near
                    kept[#kept + 1] = ns
                    if #kept >= BEAM then break end
                end
            end
            -- Bounded and nothing left cheaper than the bound: no better answer.
            if #kept == 0 then return nil end
            nextStates = kept
            states = {}
            for i = 1, #nextStates do
                local ns = nextStates[i]
                local plan = setmetatable({ [ns.bi] = ns.c }, { __index = ns.parent.plan })
                states[i] = { near = ns.near, plan = plan, score = ns.score }
            end
        end
        return states[1].plan, states[1].score
    end

    local cacheKey = runKey .. ":" .. #seq
    for _, bi in ipairs(seq) do
        cacheKey = cacheKey .. ":" .. _floor(medInfo[bi].mx) .. ":" .. _floor(medInfo[bi].lblW)
    end
    local cache = UI._medPlanCache
    if cache and cache.key == cacheKey then return cache.plan end
    local plan, score = Search(10)
    -- Thorough: everything cheaper than the quick answer stays in play.
    if score >= 150 then plan = Search(400, score) or plan end
    UI._medPlanCache = { key = cacheKey, plan = plan }
    return plan
end

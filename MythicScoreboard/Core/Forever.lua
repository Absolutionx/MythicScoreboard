-- WoW Forever support. Loaded only by MythicScoreboard_Forever.toc.
--
-- Forever has classic-era dungeons (plus new ones), Normal/Heroic only and no
-- Mythic+. Everything the scoreboard needs to know about those dungeons lives
-- in the DUNGEONS table below, so the addon works on its own. When the
-- ForeverDungeonJournal addon is installed its boss portraits are preferred;
-- otherwise the bundled copy in Core/BossPortraits.lua is used.

local MS = _G["MythicScoreboard"]
local L = MS.L
-- (How Forever differs from retail is in Flavor_Forever.lua.)

-- ── Dungeon data ────────────────────────────────────────────────────────
-- levels   : recommended level range
-- final    : the boss whose death means the dungeon is done
-- instance : the instance's own name, when it holds several wings and the
--            key isn't "<instance>: <wing>" (Blackrock Spire's two halves)
-- bosses : in rough kill order. A plain string is a regular boss. A table can
--          mark  rare = true    (rare spawn, never required)
--                summon = true  (summoned / optional event, never required)
--                aka = {...}    (other names the game may use for it)
-- Dungeons with an empty boss list are announced but not yet documented.

local DUNGEONS = {
    ["Ragefire Chasm"] = { levels = {13, 18}, final = "Bazzalan", bosses = {
        "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan",
    }},
    ["Hall of Thanes"] = { levels = {13, 20}, final = "Durgen Dirgehammer", bosses = {
        "Faldrim Anvilmar", { "Magmatus", aka = { "Infurnus" } }, "Plunder", "Durgen Dirgehammer",
    }},
    ["Ruins of Lordaeron"] = { levels = {15, 22}, final = "Viktor the Vile", bosses = {
        { "The Baron", aka = { "The Butcher" } }, "Witherfang", "The Abandoned", "Bjork",
        "Rath'mael", "Viktor the Vile", { "Lordaeron Captain", rare = true },
    }},
    ["Wailing Caverns"] = { levels = {15, 24}, final = "Mutanus the Devourer", bosses = {
        "Lord Cobrahn", "Lady Anacondra", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis",
        "Verdan the Everliving", "Mutanus the Devourer", { "Deviate Faerie Dragon", rare = true },
    }},
    ["The Deadmines"] = { levels = {17, 26}, final = "Edwin VanCleef", bosses = {
        "Rhahk'Zor", { "Miner Johnson", rare = true }, "Sneed's Shredder", "Sneed", "Gilnid",
        "Mr. Smite", "Captain Greenskin", "Edwin VanCleef", "Cookie",
    }},
    ["Shadowfang Keep"] = { levels = {20, 30}, final = "Archmage Arugal", bosses = {
        "Rethilgore", { "Fel Steed / Shadow Charger", aka = { "Fel Steed", "Shadow Charger" } },
        "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher",
        { "Deathsworn Captain", rare = true }, "Arugal's Voidwalker", "Fenrus the Devourer",
        "Wolf Master Nandos", "Archmage Arugal",
    }},
    ["Blackfathom Deeps"] = { levels = {24, 32}, final = "Aku'mai", bosses = {
        "Ghamoo-ra", "Lady Sarevess", { "Gelihast", aka = { "Geilhast" } },
        { "Lorgus Jett", rare = true },                -- doesn't always spawn
        "Old Serra'kis", "Twilight Lord Kelris", "Aku'mai",
    }},
    ["The Stockade"] = { levels = {24, 32}, final = "Bazil Thredd", bosses = {
        "Targorr the Dread", "Kam Deepfury", "Hamhock", "Dextren Ward", "Bazil Thredd",
        { "Bruegal Ironknuckle", rare = true },
    }},
    ["Excavation Site: Wetlands"] = { levels = {26, 33}, final = "Relic Guardian", bosses = {
        "Saltspine", "Shadetooth", "Relic Guardian",
    }},
    ["City of Dalaran"] = { levels = {28, 33}, final = "Shade of the Archmage", bosses = {
        "Atrexis the Grave Knight", "Arcane Anomaly", "Fel Ancient", "Unstable Sentinel",
        "Mana Devourer", { "Arcanic Enigma", aka = { "Mana Elemental" } },
        { "Lyn the Ignored", summon = true }, "Shade of the Archmage",
    }},
    ["Gnomeregan"] = { levels = {29, 38}, final = "Mekgineer Thermaplugg", bosses = {
        "Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60",
        { "Dark Iron Ambassador", rare = true }, "Mekgineer Thermaplugg",
    }},
    ["Razorfen Kraul"] = { levels = {29, 38}, final = "Charlga Razorflank", bosses = {
        "Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk",
        "Agathelos the Raging", { "Blind Hunter", rare = true }, { "Earthcaller Halmgar", rare = true },
        "Charlga Razorflank",
    }},
    ["Scarlet Monastery: Graveyard"] = { levels = {30, 38}, final = "Bloodmage Thalnos", bosses = {
        "Interrogator Vishas", { "Azshir the Sleepless", rare = true }, { "Fallen Champion", rare = true },
        { "Ironspine", rare = true }, "Bloodmage Thalnos",
    }},
    ["Scarlet Monastery: Library"] = { levels = {33, 41}, final = "Arcanist Doan", bosses = {
        "Houndmaster Loksey", "Arcanist Doan",
    }},
    ["Scarlet Monastery: Armory"] = { levels = {34, 42}, final = "Herod", bosses = {
        { "Herod", aka = { "Herod, the Scarlet Champion" } },
    }},
    ["Scarlet Monastery: Cathedral"] = { levels = {36, 45}, final = "High Inquisitor Whitemane", bosses = {
        { "High Inquisitor Fairbanks", aka = { "Fairbanks" } },
        { "Scarlet Commander Mograine", aka = { "Mograine" } },
        { "High Inquisitor Whitemane", aka = { "Whitemane" } },
    }},
    ["Razorfen Downs"] = { levels = {37, 46}, final = "Amnennar the Coldbringer", bosses = {
        "Tuten'kash", "Mordresh Fire Eye", "Glutton", { "Ragglesnout", rare = true },
        { "Plaguemaw the Rotting", rare = true, aka = { "Plaguemaw" } },
        { "Amnennar the Coldbringer", aka = { "Amnennar" } },
    }},
    ["Uldaman"] = { levels = {38, 48}, final = "Archaedas", bosses = {
        "Revelosh", { "The Lost Dwarves", aka = { "Baelog", "Eric \"The Swift\"", "Olaf" } },
        "Ironaya", "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas",
    }},
    ["Zul'Farrak"] = { levels = {43, 50}, final = "Chief Ukorz Sandscalp", bosses = {
        "Antu'sul", "Witch Doctor Zum'rah", "Shadowpriest Sezz'ziz", { "Gahz'rilla", summon = true },
        { "Zerillis", rare = true }, { "Sandarr Dunereaver", rare = true }, { "Dustwraith", rare = true },
        "Ruuzlu", "Chief Ukorz Sandscalp",
    }},
    ["Maraudon"] = { levels = {45, 52}, final = "Princess Theradras", bosses = {
        "Noxxion", "Razorlash", "Lord Vyletongue", { "Meshlok the Harvester", rare = true },
        "Celebras the Cursed", "Landslide", "Tinkerer Gizlock", "Rotgrip", "Princess Theradras",
    }},
    ["Sunken Temple"] = { levels = {49, 56}, final = "Shade of Eranikus", bosses = {
        "Atal'alarion", "Dreamscythe", "Weaver", "Avatar of Hakkar", "Jammal'an the Prophet",
        "Ogom the Wretched", "Morphaz", "Hazzas", "Shade of Eranikus",
    }},
    ["Blackrock Depths"] = { levels = {52, 60}, final = "Emperor Dagran Thaurissan", bosses = {
        "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Gorosh the Dervish",
        "Grizzle", "Eviscerator", "Ok'thor the Breaker", "Anub'shiah", "Hedrum the Creeper",
        "Pyromancer Loregrain", "Fineous Darkvire", "Warder Stilgiss", "Lord Incendius", "Bael'Gar",
        "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx",
        "Ribbly Screwspigot", "Plugger Spazzring", "Ambassador Flamelash",
        { "Panzor the Invincible", rare = true },
        { "The Seven", aka = { "Doom'rel", "Hate'rel", "Anger'rel", "Vile'rel", "Gloom'rel", "Seeth'rel", "Dope'rel" } },
        "Magmus", "Princess Moira Bronzebeard", "Emperor Dagran Thaurissan",
    }},
    ["Lower Blackrock Spire"] = { instance = "Blackrock Spire", levels = {55, 60}, final = "Overlord Wyrmthalak", bosses = {
        { "Spirestone Butcher", rare = true }, { "Spirestone Battle Lord", rare = true },
        { "Spirestone Lord Magus", rare = true }, "Highlord Omokk", "Shadow Hunter Vosh'gajin",
        "War Master Voone", "Mother Smolderweb", { "Crystal Fang", rare = true }, "Urok Doomhowl",
        { "Bannok Grimaxe", rare = true }, "Quartermaster Zigris", "Halycon", "Gizrul the Slavener",
        { "Ghok Bashguud", rare = true }, "Overlord Wyrmthalak",
    }},
    ["Upper Blackrock Spire"] = { instance = "Blackrock Spire", levels = {55, 60}, final = "General Drakkisath", bosses = {
        "Pyroguard Emberseer", "Solakar Flamewreath", { "Jed Runewatcher", rare = true },
        "Goraluk Anvilcrack", "Gyth", "Warchief Rend Blackhand", "The Beast",
        { "Lord Valthalak", summon = true }, "General Drakkisath",
    }},
    ["Dire Maul: East"] = { levels = {55, 60}, final = "Alzzin the Wildshaper", bosses = {
        "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper",
    }},
    ["Dire Maul: West"] = { levels = {57, 60}, final = "Prince Tortheldrin", bosses = {
        "Tendris Warpwood", "Illyanna Ravenoak", { "Tsu'zee", rare = true }, "Magister Kalendris",
        "Immol'thar", "Lord Hel'nurath", "Prince Tortheldrin",
    }},
    ["Dire Maul: North"] = { levels = {57, 60}, final = "King Gordok", bosses = {
        "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush",
        "Cho'Rush the Observer", "King Gordok",
    }},
    ["Scholomance"] = { levels = {58, 60}, final = "Darkmaster Gandling", bosses = {
        { "Kirtonos the Herald", summon = true }, "Jandice Barov", "Rattlegore", "Marduk Blackpool",
        "Vectus", "Ras Frostwhisper", "Instructor Malicia", "Doctor Theolen Krastinov",
        "Lorekeeper Polkelt", "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov",
        "Darkmaster Gandling",
    }},
    ["Stratholme: Living"] = { levels = {58, 60}, final = "Balnazzar", bosses = {
        { "Skul", rare = true }, { "Hearthsinger Forresten", rare = true }, "The Unforgiven",
        "Timmy the Cruel", "Postmaster Malown", "Cannon Master Willey", "Archivist Galford", "Balnazzar",
    }},
    ["Stratholme: Undead"] = { levels = {58, 60}, final = "Baron Rivendare", bosses = {
        { "Stonespine", rare = true }, "Magistrate Barthilas", "Nerub'enkan", "Baroness Anastari",
        "Maleki the Pallid", "Ramstein the Gorger", "Baron Rivendare",
    }},
    -- Announced, bosses not documented yet: runs are saved as "Finished".
    ["The Drowned City"]    = { levels = {35, 40}, bosses = {} },
    -- (ForeverDungeonJournal 1.7.2: bosses in its order, the last one final.)
    ["Krol'dok Stronghold"] = { levels = {40, 45}, final = "Overlord Mugg", bosses = {
        "Slavecrusher Grox", "Twilight Commander Zarmok", "War Handler Ashka", "Nar'gurk",
        "Bossman Toof", "Overlord Mugg",
    }},
    ["The Drowned City"] = { levels = {35, 40}, final = "Min'loth the Serpent", bosses = {
        "Zul'Alai", "Var'Taka", "Captain Dreadrise", "Deathless Marrow",
        { "Gill", rare = true }, "Min'loth the Serpent",
    }},
    ["Alcaz Prison"]        = { levels = {48, 53}, bosses = {} },
    ["Blackmaw Hold"]       = { levels = {55, 60}, bosses = {} },
    ["Shaper's Terrace"]    = { levels = {58, 60}, bosses = {} },
}

-- Normalise entries to { name=, rare=, summon=, aka= }.
for _, def in pairs(DUNGEONS) do
    for i, b in ipairs(def.bosses) do
        if type(b) == "string" then
            def.bosses[i] = { name = b }
        else
            b.name = b[1]; b[1] = nil
        end
    end
end
MS.FOREVER_DUNGEONS = DUNGEONS

-- Other names the game may give an instance than the key above.
local INSTANCE_ALIASES = {
    ["Deadmines"]                 = "The Deadmines",
    ["Stormwind Stockade"]        = "The Stockade",
    ["The Stockades"]             = "The Stockade",
    ["The Temple of Atal'Hakkar"] = "Sunken Temple",
    ["Temple of Atal'Hakkar"]     = "Sunken Temple",
}
local function Canonical(name)
    name = (name or ""):gsub("\226\128\153", "'")
    return INSTANCE_ALIASES[name] or name
end

-- The classic dungeons by instance ID (GetInstanceInfo), for clients in other
-- languages, where the dungeon's name isn't the English one in DUNGEONS.
-- Dungeons with wings map to the instance; the wing is found by its bosses.
local INSTANCE_IDS = {
    [389] = "Ragefire Chasm",    [43]  = "Wailing Caverns",  [36]  = "The Deadmines",
    [33]  = "Shadowfang Keep",   [48]  = "Blackfathom Deeps", [34]  = "The Stockade",
    [90]  = "Gnomeregan",        [47]  = "Razorfen Kraul",   [189] = "Scarlet Monastery",
    [129] = "Razorfen Downs",    [70]  = "Uldaman",          [209] = "Zul'Farrak",
    [349] = "Maraudon",          [109] = "Sunken Temple",    [230] = "Blackrock Depths",
    [229] = "Blackrock Spire",   [429] = "Dire Maul",        [329] = "Stratholme",
    [289] = "Scholomance",
}

-- The instance a dungeon key is part of: "Scarlet Monastery" for
-- "Scarlet Monastery: Library", its `instance` for Blackrock Spire's halves.
local function InstanceOf(key)
    local def = DUNGEONS[key]
    return (def and def.instance) or key:match("^(.-): ") or key
end
local function IsWingOf(key, name) return key ~= name and InstanceOf(key) == name end

-- ── Lookups ─────────────────────────────────────────────────────────────

-- Lower-cased, curly apostrophe made straight. Remembered: the same few
-- boss names are compared over and over while the scoreboard is open.
local Norm = MS.BossKey

local FINAL_NAMES = {}
for _, def in pairs(DUNGEONS) do
    if def.final then FINAL_NAMES[Norm(def.final)] = true end
end

-- Each boss's names (name and aliases), normalised, worked out on first use.
-- (Kept beside the entry, not on it: entries may be ForeverDungeonJournal's.)
local _names = setmetatable({}, { __mode = "k" })
local function Names(entry)
    local set = _names[entry]
    if not set then
        set = {}
        if entry.name then set[Norm(entry.name)] = true end
        for _, a in ipairs(entry.aka or entry.aliases or {}) do set[Norm(a)] = true end
        _names[entry] = set
    end
    return set
end

local function EntryMatches(entry, name)
    local n = Norm(name)
    if not n or type(entry) ~= "table" then return false end
    return Names(entry)[n] == true
end

local function IsRequired(entry)
    -- (entry.trash / summonItem: ForeverDungeonJournal's flags, for portraits lookups)
    return not entry.rare and not entry.summon and not entry.trash and not entry.summonItem
end

local _missed = setmetatable({}, { __mode = "k" })   -- run -> what it was last searched with

-- The run's dungeon as DUNGEONS names it: its own name, or (another
-- language) the name its instance ID stands for.
local _isBase = {}
for key in pairs(DUNGEONS) do _isBase[InstanceOf(key)] = true end
local function RunName(run)
    local name = Canonical(run and run.dungeonName)
    if DUNGEONS[name] or _isBase[name] then return name end
    return INSTANCE_IDS[run and run.instanceID or 0] or name
end

-- Finds the dungeon for a run: by name, then by wing name ("Scarlet
-- Monastery" -> "Scarlet Monastery: Library"), then by which dungeon
-- contains the bosses the group has fought.
function MS:ForeverDungeon(run)
    if not run then return nil end
    if run._fdjKey and DUNGEONS[run._fdjKey] then return DUNGEONS[run._fdjKey], run._fdjKey end
    local name = RunName(run)
    if DUNGEONS[name] then run._fdjKey = name; return DUNGEONS[name], name end
    -- Not found before with these bosses: don't search again until one is added.
    local sig = name .. "#" .. #(run.bosses or {})
    if _missed[run] == sig then return nil end

    local best, bestScore
    for key, def in pairs(DUNGEONS) do
        local score = 0
        for _, b in ipairs(run.bosses or {}) do
            for _, e in ipairs(def.bosses) do
                if EntryMatches(e, b.name) then score = score + 1; break end
            end
        end
        if score > 0 and IsWingOf(key, name) then score = score + 0.5 end
        if score > 0 and (not bestScore or score > bestScore) then best, bestScore = key, score end
    end
    if best then
        run._fdjKey = best
        if IsWingOf(best, name) then run.wingName = best end
        return DUNGEONS[best], best
    end
    _missed[run] = sig
    return nil
end

-- Whether a dungeon's instance holds several wings ("Scarlet Monastery" for
-- its Graveyard, Library, Armory and Cathedral).
local _wings = {}
for key in pairs(DUNGEONS) do
    local base = InstanceOf(key)
    if base ~= key then _wings[base] = true end
end
function MS:DungeonHasWings(name) return _wings[Canonical(name)] == true end

-- The dungeon entries a run may be in: the one it's known to be, else every
-- wing of its instance.
function MS:ForeverDefsFor(run)
    local def = self:ForeverDungeon(run)
    if def then return { def } end
    local out, name = {}, RunName(run)
    for key, d in pairs(DUNGEONS) do
        if key == name or IsWingOf(key, name) then out[#out + 1] = d end
    end
    return out
end

-- Can this run ever be marked cleared? False for undocumented dungeons and
-- for names the table doesn't know (e.g. non-English clients).
function MS:ForeverCanDetectClear(run)
    local def = self:ForeverDungeon(run)
    if def then return #def.bosses > 0 end
    local name = RunName(run)
    if name == "" then return false end
    for key, d in pairs(DUNGEONS) do
        if IsWingOf(key, name) and #d.bosses > 0 then return true end   -- a wing
    end
    return false
end

local function RequiredBosses(def)
    local out = {}
    for _, e in ipairs(def and def.bosses or {}) do
        if IsRequired(e) then out[#out + 1] = e end
    end
    return out
end

local function Killed(run, entry)
    for _, b in ipairs(run.bosses or {}) do
        if b.killTime and EntryMatches(entry, b.name) then return true end
    end
    return false
end

-- In another language the bosses' names don't match the English ones, so
-- bosses are counted instead: nil when names match (English), else how many
-- different bosses have died.
local function KillsByCount(run, def)
    if (MS.ClientLocale or "enUS") == "enUS" then return nil end   -- the game's language names the bosses
    local kills, seen = 0, {}
    for _, b in ipairs(run.bosses or {}) do
        for _, e in ipairs(def.bosses) do
            if EntryMatches(e, b.name) then return nil end
        end
        if b.killTime and b.name and not seen[b.name] then seen[b.name] = true; kills = kills + 1 end
    end
    return kills
end

-- The clear rule (Settings.lua) applied after each boss kill.
local function CheckRunCleared(self, run, killedBoss)
    local rule = self:GetClearRule()
    run.clearRule = rule
    if rule == "leave" then return false end

    local def = self:ForeverDungeon(run)
    -- Names that don't match: cleared once as many bosses as the dungeon
    -- requires have died (both rules; the final boss can't be told apart).
    local counted = def and #def.bosses > 0 and KillsByCount(run, def)
    if counted then
        local req = #RequiredBosses(def)
        if req > 0 and counted >= req then run.finalDown = true; return true end
        return false
    end
    if rule == "all" and def then
        local req = RequiredBosses(def)
        if #req == 0 then return false end
        for _, e in ipairs(req) do
            if not Killed(run, e) then return false end
        end
        return true
    end

    -- "Final boss": some dungeons can be done in any order (Ruins of
    -- Lordaeron), so the final boss isn't always the last kill. With it down
    -- the run is cleared once every other required boss is too, or when you
    -- leave (run.finalDown).
    if def and def.final then
        local finalEntry
        for _, e in ipairs(def.bosses) do
            if e.name == def.final then finalEntry = e end
        end
        local finalDown
        if finalEntry then finalDown = Killed(run, finalEntry)
        else
            for _, b in ipairs(run.bosses or {}) do
                if b.killTime and Norm(b.name) == Norm(def.final) then finalDown = true end
            end
        end
        if not finalDown then return false end
        run.finalDown = true
        for _, e in ipairs(RequiredBosses(def)) do
            if not Killed(run, e) then return false end
        end
        return true
    end
    if not killedBoss or not killedBoss.killTime then return false end
    return FINAL_NAMES[Norm(killedBoss.name) or ""] == true
end

-- How Completion.lua decides a Forever run is cleared.
MS:SetClearStrategy({
    isCleared = CheckRunCleared,
    canDetect = function(self, run) return self:ForeverCanDetectClear(run) end,
})

-- "6 of 9": required bosses killed / required bosses.
function MS:ForeverBossProgress(run)
    local def = self:ForeverDungeon(run)
    if not def then return nil end
    local req = RequiredBosses(def)
    if #req == 0 then return nil end
    local counted = KillsByCount(run, def)
    if counted then return math.min(counted, #req), #req end
    local n = 0
    for _, e in ipairs(req) do if Killed(run, e) then n = n + 1 end end
    return n, #req
end

-- Dungeon level range, e.g. 17, 26. Works before any boss is pulled for
-- single-wing dungeons; multi-wing ones resolve after the first boss.
function MS:ForeverLevelRange(run)
    local def = self:ForeverDungeon(run)
    if def and def.levels then return def.levels[1], def.levels[2] end
    return nil
end

-- Other names the game may use for a boss (for learned portraits).
function MS:ForeverBossAliases(boss, run)
    local def = self:ForeverDungeon(run)
    for _, e in ipairs(def and def.bosses or {}) do
        if EntryMatches(e, boss.name) then
            local out = { e.name }
            for _, a in ipairs(e.aka or {}) do out[#out + 1] = a end
            return out
        end
    end
    return nil
end

-- Portrait for a boss medallion: "display", displayID  or  "file", path.
-- ForeverDungeonJournal's live data wins when it's installed (it may be newer
-- and has custom art for a few bosses); otherwise the bundled table in
-- Core/BossPortraits.lua is used.
local function ArtFromFDJ(self, boss, run)
    local ns = _G.ForeverDungeonJournal_NS
    local db = ns and type(ns.DB) == "table" and ns.DB
    if not db then return nil end
    local _, key = self:ForeverDungeon(run)
    local jdef = key and db[key]
    if type(jdef) ~= "table" or type(jdef.bosses) ~= "table" then return nil end
    for _, e in ipairs(jdef.bosses) do
        if EntryMatches(e, boss.name) then
            local display = e.displayID
                or (e.npcID and ns.STATIC_DISPLAY_IDS and ns.STATIC_DISPLAY_IDS[e.npcID])
            if display then return "display", display end
            if type(e.customIcon) == "string" then return "file", e.customIcon end
            return nil
        end
    end
    return nil
end

-- Bundled tables, re-keyed by normalised name on first use.
local _bundled
local function Bundled()
    if _bundled then return _bundled end
    _bundled = { display = {}, icons = {} }
    for src, dst in pairs({ [MS.FOREVER_BOSS_DISPLAY or {}] = _bundled.display,
                            [MS.FOREVER_BOSS_ICONS or {}]   = _bundled.icons }) do
        for dungeon, list in pairs(src) do
            local t = {}
            for name, v in pairs(list) do t[Norm(name)] = v end
            dst[dungeon] = t
        end
    end
    return _bundled
end

local function ArtFromBundle(self, boss, run)
    local b = Bundled()
    local names = { Norm(boss.name) }
    for _, a in ipairs(self:ForeverBossAliases(boss, run) or {}) do names[#names + 1] = Norm(a) end
    local _, key = self:ForeverDungeon(run)
    local function find(tbl)
        local list = key and tbl[key]
        if list then
            for _, n in ipairs(names) do if list[n] then return list[n] end end
        end
        -- Dungeon not recognised: boss names are unique enough across Forever.
        for _, l in pairs(tbl) do
            for _, n in ipairs(names) do if l[n] then return l[n] end end
        end
    end
    local display = find(b.display)
    if display then return "display", display end
    local icon = find(b.icons)
    if icon then return "file", icon end
    return nil
end

function MS:ForeverBossArt(boss, run)
    if not boss or not boss.name then return nil end
    local kind, art = ArtFromFDJ(self, boss, run)
    if kind then return kind, art end
    return ArtFromBundle(self, boss, run)
end

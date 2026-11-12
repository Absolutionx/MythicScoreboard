# Mythic Scoreboard

**A scoreboard for every dungeon run, for World of Warcraft: Midnight and WoW Forever.**

Mythic Scoreboard follows your group through each dungeon: damage, healing, deaths, interrupts, dispels and loot, every boss kill on a timeline, and a permanent record of every run across all your characters. On WoW Forever it also tracks what each run did for you: experience, kills, quests, gold and reputation.

---

## The in-run frame

A small frame that shows how the run is going while you play. It's on by default; drag it anywhere.

**Mythic+**
- The timer and time left, matching the game's own, with a bar marking the +3, +2 and +1 times
- Every boss in the dungeon from the start, with its kill time, your best time at that key level, and how far ahead or behind you are
- Enemy forces with the count, and how much your last pull gave
- Deaths and the time they cost (hover for who died)
- Your pace against your best run of that key

**WoW Forever**
- The dungeon and its level range, the clock and the bosses
- Experience from the dungeon and from quests (hover for the split and each quest's reward)
- Mobs killed, deaths and gold looted

**Three styles:** detailed, compact and a single line. Right-click to switch, left-click to open the scoreboard, Shift-click to post the time left to your party.

Try it anywhere with `/sb compact demo`: it plays out a sample run in fast-forward, with a different dungeon each time.

---

## The scoreboard

- **Every player's numbers:** damage and DPS, healing and HPS, deaths, interrupts and dispels, with class colours and each player's spec and role
- **Boss timeline:** every boss fight on one line, with kill times. Click a boss to see damage, healing, deaths, interrupts and loot for just that fight
- **Death recaps:** each death keeps the hits that caused it
- **Loot:** who got what, from which boss
- **Mythic+ results:** the official time, the key's upgrade (bronze +1, silver +2, gold +3), the +3/+2/+1 marks on the timeline, and your new rating and what it gained
- **Run history:** the runs of every character on your account in one list, newest first

---

## The Stats page

Every run is kept in a permanent archive, even after it drops out of history. Open it with `/sb stats` or the button in the header.

- **Per dungeon:** runs, clear rate, best and typical times, and each boss's fastest and typical fight length
- **Run comparison:** pick any two runs of a dungeon to see them side by side on one timeline, with every boss kill and where one pulled ahead
- **Keys tab (Mythic+):** your rating key by key on a chart with a line per character, keys run and timed per dungeon, average upgrade, highest key timed, and how many keys of each level you timed
- **Loot tab:** every piece of gear that dropped for you, with the boss and the run it came from
- **All your characters together,** or one at a time

---

## Made for WoW Forever

- Every Forever dungeon with its level range and bosses, on any client language
- **Run stats:** experience and levels gained (from the dungeon and from quests, the moment a quest's objectives are done), mobs killed, quests completed, gold looted and reputation
- **Every kill counted,** including grey mobs and kills at max level
- **Dungeon wings tracked separately:** Scarlet Monastery, Dire Maul, Stratholme and Blackrock Spire. Scarlet Monastery wings are recognised as you walk in, from the door you used, the room you're in or the first wing-only trash you kill
- Running back after a wipe pauses the run; time logged out doesn't count
- **Dungeon entrances on the world map,** with each dungeon's levels
- **Directions to any dungeon:** click its marker for an arrow above your character, step-by-step directions using the flight paths you know (and boats and zeppelins between continents), the distance and the time left, plus the route drawn on the world map
- **Take flights automatically** (optional): talking to the flight master goes straight to the flight on your route

---

## And also

- **Fully translated:** English, German, French, Spanish, Portuguese, Italian, Russian, Korean and Chinese (Simplified and Traditional), using the game's own fonts
- **Light on your game:** nothing runs outside dungeons, and the windows are built only when you first open them
- **Minimap button:** left-click for the scoreboard, right-click for the Stats page
- **Your choice of when a run counts as cleared,** which difficulties to track and how many runs to keep

---

## Commands

| Command | What it does |
|---|---|
| `/sb` | Open the scoreboard |
| `/sb stats` | Open the Stats page |
| `/sb compact` | The in-run frame: `demo`, `detailed`, `compact`, `minimal` or `off` |
| `/sb demo` | A sample finished key (add 0 to 3 for its upgrade) |
| `/sb abandon` | Abandon the current run |
| `/sb removeloot` | Take a wrongly recorded item off your runs (Shift-click the item into the line) |
| `/sb lang <code>` | Show the addon in another language (`/sb lang off` to switch back) |
| `/sb autoreset` | Reset the game's damage meter when you enter a dungeon |
| `/sb clear` | Clear run history (your stats are kept) |
| `/sb routedebug` | WoW Forever: why the directions chose their route |
| `/sb help` | All commands |

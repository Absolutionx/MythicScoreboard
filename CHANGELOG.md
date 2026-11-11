# Changelog

## 2.10.0

### New: the in-run frame
A small frame that shows how the run is going while you play. It's on by default; turn it off under "In-run frame" in settings or with `/sb compact off`.
- **Mythic+:** the timer and time left, a bar marking the +3, +2 and +1 times, every boss with its kill time, your best time and how far ahead or behind you are, enemy forces with the count and how much the last pull gave, deaths and the time they cost, and your pace against your best run of that key. Hover the deaths for who died. Shift-click the frame to post the time left to your party.
- **WoW Forever:** the dungeon and its level range, the clock, the bosses, experience (dungeon and quests), mobs killed, deaths and gold looted.
- **Three styles:** detailed, compact and a single line. Right-click the frame to switch. Left-click opens the scoreboard; drag it wherever you like.
- **Try it anywhere:** `/sb compact demo` plays out a sample run in fast-forward, with a different dungeon each time.

### Mythic+
- The live timer now matches the game's own, deaths included. Keys you've already saved are converted to the same clock, so old and new runs compare fairly.
- Run comparison: every bar shows its time, including each boss kill, and the labels stay clear of the lines between bars. No bar runs outside the window any more.
- Key upgrades use bronze for +1, silver for +2 and gold for +3, everywhere.

### WoW Forever
- **Mobs killed counts every kill,** including grey mobs and kills at max level, not only ones that gave XP. Kills are seen on enemy nameplates, your target and your group's targets, and a kill that also gave XP is counted once. Keep enemy nameplates on for the best count.

### Fixes
- The lines between bars on the run comparison chart are smoother.
- If something goes wrong in the in-run frame or a delayed check, you get one line in chat instead of an error popup.

## 2.9.2

### WoW Forever
- **Quest XP counts with the run:** when you finish a quest's objectives inside a dungeon, its reward XP and gold are added to the run straight away, without waiting for you to hand it in. The XP shows as a two-colour bar in the header, on the "This run" tooltip and under "XP a run" on the Stats page: purple from the dungeon, yellow from quests. The tooltip gives each quest's reward. A quest handed in inside the dungeon isn't counted twice.

### Mythic+
- The Keys tab's dungeon table now has its column names. Hover one for what it counts.

### Fixes
- Column names show again on every Stats page table.
- Lines on the rating chart and the run comparison chart are smooth at any angle, instead of turning into dots on a slope.

## 2.9.1

### New for Mythic+
- **Keys tab on the Stats page:**
  - **Your rating, key by key:** a chart with a line per character. Each key is a diamond coloured by how it went: gold for +3, bronze for +2, white for +1, red over time. Hover one for the dungeon, the level and the rating it took you to.
  - **Per dungeon:** keys run, how many were timed, the average upgrade, your highest key timed and your highest key run. Click a dungeon for all its runs.
  - **By level:** how many keys of each level you timed, so you can see where it starts getting hard.
- Keys already on the Stats page pick up their upgrade and rating from your run history where it still has them.

### Fixes
- Loot is no longer listed twice for a groupmate who also runs Mythic Scoreboard.
- Gear you get after leaving the dungeon, such as from the Great Vault, no longer lands on your last run.
- Loot already saved twice is cleaned up automatically the first time you log in.
- **New:** `/sb removeloot`, then Shift-click an item into the line, takes that item off your runs from the last day and off the Stats page, for anything that ended up on a run but wasn't from it.
- A boss the addon had marked as reset (nobody was fighting) now turns into a kill if the game reports the kill afterwards.
- Deaths after a dungeon is cleared stay off the run even if you log out and back in, or restart your computer, before leaving.

## 2.9.0

### New for Mythic+
- **Key upgrades at a glance:** three diamonds show how many levels the key went up: one filled for each of +1, +2 and +3, all hollow for a key that went over time. They appear in the scoreboard's header and next to each key in the run history.
- **+3, +2 and +1 on the timeline:** the time axis is marked where the key would go up three levels (60% of the timer), two (80%) and one (the timer). A mark turns bronze if the key beat it, and hovering one shows how far inside or over it you finished.
- **Your rating change:** after a key, the header shows your new rating and what it gained ("Rating 2,845 +18"), and the gain also appears under your rating in your row.
- **Specializations:** each player's tooltip now shows their spec and role, for example "Holy Paladin · Healer".

### Run history
- **All your characters in one list:** the history list now shows the runs of every character on your account, newest first, with each character's name in their class colour. Switch between "All characters" and "This character" at the top. Another character's runs show up once that character has logged in with this version.
- You can view another character's run, with that character's row highlighted, but only that character can delete it.
- The history list is now wide enough for long dungeon names, so they are no longer cut short.

### Other changes
- **Start new run:** if you abandon a run while still inside the dungeon, a "Start new run" button appears in its place. It starts a fresh run from that moment, without having to leave and come back in. That's handy when groupmates died on their way in, or took a long time to arrive.
- The completion marker on the timeline now sits right against the last boss's bar and ends the timeline, drawn to your screen's exact pixels at any UI scale. Time spent in the dungeon after the final boss (looting, waiting to leave) is no longer drawn after it.
- **New:** `/sb demo` shows a sample finished key, so you can see how keys look without running one. Add 0 to 3 for the upgrade it got (`/sb demo 3`). The sample is never saved.

### Fixes
- Other addons' windows no longer show through the scoreboard. The history list, Settings and the Stats page's menus now stay above the window but below tooltips, so a tooltip is never covered by them.
- Long column names and run times on the Stats page (Best, Typical, and "Deaths/run" in some languages) are no longer cut short.
- WoW Forever: quests only count as completed in a run when you made progress on them during it. Picking up and handing in quests already done no longer adds to the count.
- A boss fight that the game never reported as ended now closes when the group leaves combat or pulls another boss.

## 2.8.0

### Now in your language
- Mythic Scoreboard is fully translated into German, French, Spanish, Portuguese, Italian, Russian, Korean and Chinese (Simplified and Traditional). Every window, tooltip and chat message follows your game's language.
- Russian, Korean and Chinese text uses the game's own fonts, so nothing shows up as empty boxes.
- On English and European clients, player names in Cyrillic, Korean or Chinese now display correctly.
- Gold amounts and large numbers use your language's formatting.
- New: `/sb lang <code>` (for example `/sb lang deDE`), then `/reload`, shows the addon in another language without changing your game's. `/sb lang off` switches back.

### WoW Forever
- The scoreboard now recognises dungeons on non-English clients, with level ranges and boss progress.
- Krol'dok Stronghold now tracks its bosses, and The Drowned City is supported.
- Lorgus Jett in Blackfathom Deeps is now optional, since he doesn't always spawn. Killing Aku'mai clears the dungeon.

### Fixes
- Fixed a boss staying "In combat" forever when the game never reported the fight ending. The fight now closes once combat is over, as a kill if the boss died or as a reset if not.
- Deaths after a dungeon is cleared (while looting or exploring) no longer count against the run.
- The run timeline's completion marker is now evenly spaced and lines up exactly with the last boss.
- Fixed the run number sometimes not showing in the history dropdown.

## 2.7.0

### WoW Forever
- **Run stats:** the header and the Stats page now show what a run did for you: experience and levels gained, kills, quests completed, gold looted and reputation.
- Dungeon wings are named and tracked separately: Scarlet Monastery, Dire Maul, Stratholme and Blackrock Spire.
- Running back after a wipe pauses the run under the "leaving" clear rule, and time spent logged out no longer counts towards a run's time.

### Mythic+
- Key results come straight from the game: the official time and whether it was in time, the timer for the dungeon, and the time lost to deaths. Ratings are coloured the way the game colours them.

### Fixes
- Retail Normal and Heroic dungeons are now marked as cleared.
- Each death keeps its own recap of the hits that caused it.
- Runs are no longer lost when logging in on another computer, starting a key while a run is paused, or clearing history while a run is paused or finishing.
- Players with the same name from different realms are kept apart.
- Deaths are still counted after the game's damage meter restarts.
- Loot from end-of-dungeon chests now appears on the Stats page.
- The history dropdown scrolls when it has more runs than fit.
- The Stats page updates straight away after any change.
- The timeline draws faster, especially for runs with many bosses.

## 2.6.0

### New
- **Damage and Healing columns:** the scoreboard now shows each player's total damage done and total healing done, next to DPS and HPS.
- **Run comparison:** on the Stats page, pick any two runs of a dungeon to see them side by side: both runs on one timeline, where one pulled ahead of the other, and a boss-by-boss table of kill times, fight lengths, trash time and your DPS.
- **Stats across all your characters:** see every character's runs together, or pick one character.
- **Loot history:** a new Loot tab on the Stats page lists every piece of gear that dropped for you, with the boss and the run it came from.
- **Minimap button:** left-click opens the scoreboard, right-click opens the Stats page, drag to move it. Can be turned off in Settings.
- **Abandon a run by hand:** an Abandon button (click twice to confirm) or `/sb abandon`.

### Changed
- Boss medallions on the timeline no longer overlap. Names and "Killed at" times stay readable, and crowded bosses move aside on a bent line.
- Numbers line up in their columns, including plain numbers next to "K" values.
- The bars under DPS and HPS now also show for players doing real off-healing, not just healers.
- The final boss clear setting now says plainly that it waits for the other required bosses, or for you to leave the dungeon.

### Fixed
- The green completion line overlapped the last boss's bar on the timeline.

### Performance
- Big performance pass: the scoreboard no longer leaves unused UI objects behind as it redraws, reads the damage meter far less often, and runs nothing outside dungeons.
- The window is built the first time you open it, not at login.
- Fixed nameplate labels piling up in the open world.
- Saved files are smaller (about a third smaller on our test characters). Existing data is converted once at first login, with nothing lost.

## 2.5.0

### New
- **Stats page**: every run is now kept in a permanent archive, even after it drops out of history. Open it with the new button in the header or `/sb stats`. It shows each dungeon's runs, clear rate, best and typical times, recent runs and who you've played with.
- **Per-boss breakdown**: click a boss on the run timeline to see damage, healing, deaths, interrupts and loot for just that fight. Click it again, or "Whole run", to go back.
- **Boss times on the Stats page**: each dungeon lists its bosses with your fastest and typical fight lengths and your best DPS against them.
- **Managing stats**: remove a single run from the Stats page, or reset all stats without touching your run history.
- The settings, close and history buttons now glow on hover, like the stats button.
- Short boss fights now show their length under the timeline bar.

### Changed
- Leaving the dungeon before a run is finished (releasing after a death, a repair trip) now pauses the run. Come back within 30 minutes and it carries on.
- A cleared run's time now stops at the kill that cleared it, so time spent looting or chatting afterwards no longer counts.
- Dungeons whose final boss can be killed early (like Ruins of Lordaeron) are marked cleared only once every required boss is down, or when you leave after killing the final boss.
- WoW Forever: players are shown with their full names ("Jay Breezy" instead of "Jay").
- The "Cleared" colour now fits the theme better.

### Fixed
- Runs were marked abandoned, and a new run started, after dying and releasing or zoning out and back in.
- Runs already split in two by that bug are joined back into one, in both run history and stats.
- Stats for other group members sometimes didn't fill in.
- A UI reload during a run lost its cleared status.
- Picking a saved run from history during a live run kept showing the live run.
- Tooltips on the scoreboard and Stats page disappeared after a second.
- Menu panels could overlap each other.
- Clicking a boss on an abandoned run's timeline did nothing.

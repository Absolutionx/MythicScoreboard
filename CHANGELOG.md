# Changelog

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

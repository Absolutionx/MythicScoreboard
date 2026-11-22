# Mythic Scoreboard

A dungeon run scoreboard for World of Warcraft: Midnight (retail) and WoW Forever.
Tracks damage, healing, deaths, interrupts, dispels and loot, draws a boss
timeline, and keeps permanent stats across all your characters.

## Layout

| Path | What's there |
|---|---|
| `MythicScoreboard/` | The addon, exactly as it goes in `Interface\AddOns` |
| `MythicScoreboard/MythicScoreboard.toc` | Retail (Midnight) |
| `MythicScoreboard/MythicScoreboard_Forever.toc` | WoW Forever (adds the Forever files and data) |
| `MythicScoreboard/Core/` | The code. Files named `UI_*` draw the windows; the rest track runs and keep the data, and never call the UI |
| `MythicScoreboard/Data/` | WoW Forever data: dungeons, bosses, encounter IDs and travel routes |
| `MythicScoreboard/Locales/` | Translations, one file per language |
| `MythicScoreboard/Media/`, `Icons/` | Textures and fonts |
| `tests/` | Test suites, run outside the game against a mock of the WoW API |
| `tests/wowmock.lua` | The mock WoW API the tests run on |
| `tests/fixtures/` | Real saved data used by some tests |
| `tools/release.sh` | Makes a release (see below) |
| `tools/bump.sh` | Sets the version in both TOCs |
| `tools/package.sh` | Builds the CurseForge zip into `dist/` |

## Running the tests

Needs Lua 5.1 (`lua5.1`) and Python 3.

    tests/run.sh

Every suite runs against both TOCs. `scenario.lua` replays a scripted session and
compares its output with `golden_*.txt`; after an intended change in that output,
re-record with `UPDATE_GOLDEN=1 tests/run.sh` and check the diff.

Lint with `luacheck MythicScoreboard` (settings in `.luacheckrc`). For line
coverage, install luacov and run `tests/coverage.sh`. It fails under 90%, or
under the percentage you give it. GitHub runs lint, the tests and coverage on
every push and pull request.

## Releasing

1. Add the release to the top of `CHANGELOG.md`.
2. `tools/release.sh X.Y.Z`. It bumps both TOCs, lints, runs the tests, commits,
   builds the zip and writes that release's changelog to `dist/`. Add `--push`
   to push as well.
3. Upload the zip from `dist/`.

A TOC change needs a full game restart, not just `/reload`.

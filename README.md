# Mythic Scoreboard

A dungeon run scoreboard for World of Warcraft: Midnight (retail) and WoW Forever.
Tracks damage, healing, deaths, interrupts, dispels and loot, draws a boss
timeline, and keeps permanent stats across all your characters.

## Layout

| Path | What's there |
|---|---|
| `MythicScoreboard/` | The addon, exactly as it goes in `Interface\AddOns` |
| `MythicScoreboard/MythicScoreboard.toc` | Retail (Midnight) |
| `MythicScoreboard/MythicScoreboard_Forever.toc` | WoW Forever (adds `Forever.lua`, `BossPortraits.lua`) |
| `tests/` | Test suites, run outside the game against a mock of the WoW API |
| `tests/wowmock.lua` | The mock WoW API the tests run on |
| `tests/fixtures/` | Real saved data used by some tests |
| `tools/package.sh` | Builds the CurseForge zip into `dist/` |

## Running the tests

Needs Lua 5.1 (`lua5.1`).

    tests/run.sh

Every suite runs against both TOCs. `scenario.lua` replays a scripted session and
compares its output with `golden_*.txt`; after an intended change in that output,
re-record with `UPDATE_GOLDEN=1 tests/run.sh` and check the diff.

## Releasing

1. Bump `## Version:` in both TOCs (and the fallback in `MythicScoreboard.lua`).
2. Add the release to `CHANGELOG.md`.
3. `tests/run.sh`, then `tools/package.sh`, and upload the zip from `dist/`.

A TOC change needs a full game restart, not just `/reload`.

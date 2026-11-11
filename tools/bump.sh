#!/bin/bash
# Sets the addon version in both TOCs (the only place it lives).
# Usage: tools/bump.sh 2.9.3
set -e
cd "$(dirname "$0")/.."
ver="$1"
[[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: tools/bump.sh X.Y.Z" >&2; exit 1; }
for toc in MythicScoreboard/MythicScoreboard.toc MythicScoreboard/MythicScoreboard_Forever.toc; do
  sed -i "s/^## Version: .*\r\?$/## Version: $ver/" "$toc"
done
grep -H "^## Version" MythicScoreboard/*.toc

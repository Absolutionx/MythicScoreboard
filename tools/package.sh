#!/bin/bash
# Builds dist/MythicScoreboard-<version>.zip from a commit (HEAD by default),
# never from files on disk, so what ships is exactly what's in git.
# Usage: tools/package.sh [ref]
set -e
cd "$(dirname "$0")/.."
ref="${1:-HEAD}"
if [ "$ref" = HEAD ] && [ -n "$(git status --porcelain -- MythicScoreboard)" ]; then
  echo "MythicScoreboard/ has uncommitted changes: commit them first (they wouldn't be in the zip)." >&2
  exit 1
fi
v1=$(git show "$ref:MythicScoreboard/MythicScoreboard.toc" | grep -m1 "^## Version:" | sed 's/## Version: *//' | tr -d '\r')
v2=$(git show "$ref:MythicScoreboard/MythicScoreboard_Forever.toc" | grep -m1 "^## Version:" | sed 's/## Version: *//' | tr -d '\r')
[ "$v1" = "$v2" ] || { echo "The TOCs disagree on the version ($v1 vs $v2): run tools/bump.sh" >&2; exit 1; }
mkdir -p dist
out="dist/MythicScoreboard-$v1.zip"
rm -f "$out"
git archive --format=zip -o "$out" "$ref" MythicScoreboard
echo "$out"

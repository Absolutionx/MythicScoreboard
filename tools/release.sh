#!/bin/bash
# Makes a release: version bumped, lint and tests run, committed, zipped, and
# the release's changelog written out on its own. Pushing is left to you
# (or add --push).
#
# Usage: tools/release.sh X.Y.Z [--push]
#
# Before running it: write the "## X.Y.Z" entry at the top of CHANGELOG.md.
# Commits use your git identity (git config user.name / user.email).
#
# Writes:
#   dist/MythicScoreboard-X.Y.Z.zip   (tools/package.sh)
#   dist/CHANGELOG-X.Y.Z.md           (that version's entry, for the release page)
set -e
cd "$(dirname "$0")/.."

v="$1"
[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: tools/release.sh X.Y.Z [--push]" >&2; exit 2; }
push=no; [ "$2" = "--push" ] && push=yes

# The changelog entry must be there, first.
first=$(grep -m1 "^## " CHANGELOG.md | sed 's/^## *//' | tr -d '\r')
[ "$first" = "$v" ] || { echo "CHANGELOG.md's first entry is '$first', not '$v': write it first." >&2; exit 1; }

tools/bump.sh "$v"
luacheck MythicScoreboard
bash tests/run.sh

git add -A MythicScoreboard tests tools CHANGELOG.md README.md
git commit -m "$v"
tools/package.sh

# The entry alone: from its heading to the next version's.
mkdir -p dist
awk -v v="$v" '
  /^## / { if (found) exit; if ($2 == v) { found = 1; print "# MythicScoreboard " v; next } }
  found { print }
' CHANGELOG.md > "dist/CHANGELOG-$v.md"
echo "dist/CHANGELOG-$v.md"

if [ "$push" = yes ]; then git push origin HEAD; fi

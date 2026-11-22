#!/bin/bash
# Line coverage of the addon by the test suite, both clients (needs luacov:
# luarocks --lua-version=5.1 install luacov). Prints each file's share and
# the total, and fails when the total is under the floor.
#
# Usage: tests/coverage.sh [floor-percent]      (default 90)
set -e
cd "$(dirname "$0")"
floor="${1:-90}"
cfg=$(mktemp); stats=$(mktemp); report=$(mktemp)
trap 'rm -f "$cfg" "$stats" "$report"' EXIT
cat > "$cfg" <<EOF
return { include = { "MythicScoreboard/Core/", "MythicScoreboard/Data/", "MythicScoreboard/MythicScoreboard" },
         statsfile = "$stats", reportfile = "$report", runreport = false, savestepsize = 1000000 }
EOF
export LUACOV_CONFIG="$cfg"
for f in $(ls *_tests.lua | sed 's/\.lua$//') scenario; do
  for t in MythicScoreboard_Forever.toc MythicScoreboard.toc; do
    timeout 300 lua5.1 -lluacov "$f.lua" ../MythicScoreboard "$t" >/dev/null 2>&1 || true
  done
done
luacov -c "$cfg" >/dev/null
sed -n '/^Summary/,$p' "$report" | sed 's#\.\./MythicScoreboard/##'
total=$(awk '/^Total/ {gsub("%", "", $NF); print $NF}' "$report")
awk -v t="$total" -v f="$floor" 'BEGIN { if (t + 0 < f + 0) { printf "Coverage %.2f%% is under %s%%\n", t, f; exit 1 } else printf "Coverage %.2f%% (floor %s%%)\n", t, f }'

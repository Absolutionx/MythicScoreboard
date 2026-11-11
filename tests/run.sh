#!/bin/bash
# Runs every test against both clients (Forever and retail/Midnight).
# Usage: tests/run.sh            (from anywhere; needs lua5.1)
#        UPDATE_GOLDEN=1 tests/run.sh   to re-record the scenario goldens
cd "$(dirname "$0")"
ADDON=../MythicScoreboard
# Every *_tests.lua here, plus $EXTRA.
SUITES="$(ls *_tests.lua | sed 's/\.lua$//') $EXTRA"
fail=0
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
for f in $SUITES; do
  for t in MythicScoreboard_Forever.toc MythicScoreboard.toc; do
    out=$(timeout 120 lua5.1 $f.lua $ADDON $t 2>&1); rc=$?
    if [ $rc -ne 0 ]; then fail=1; echo "== $f ($t)"; echo "$out" | tail -15; fi
  done
done
for pair in MythicScoreboard_Forever.toc:golden_forever.txt MythicScoreboard.toc:golden_retail.txt; do
  toc=${pair%%:*}; gold=${pair##*:}
  lua5.1 scenario.lua $ADDON $toc > "$tmp" 2>&1
  if [ -n "$UPDATE_GOLDEN" ]; then cp "$tmp" $gold
  elif ! diff -q "$tmp" $gold >/dev/null; then
    fail=1; echo "== scenario ($toc) differs from $gold"; diff "$tmp" $gold | head -20
  fi
done
if command -v luacheck >/dev/null; then
  out=$(cd .. && luacheck MythicScoreboard -q --no-color 2>&1) || { fail=1; echo "== luacheck"; echo "$out" | tail -15; }
else echo "(luacheck not installed: skipped)"; fi
out=$(python3 header_fit.py $ADDON 2>&1) || { fail=1; echo "== header_fit"; echo "$out" | tail -15; }
[ $fail -eq 0 ] && echo "ALL PASS"
exit $fail
